import Foundation
import os
import Synchronization

/// One WebSocket connection to the Gemini Live API: reports the
/// completed upgrade, keeps a single ordered outbound queue (audio must
/// never be reordered), and decodes every frame — text or binary — off
/// the main actor into typed `LiveServerMessage`s.
nonisolated final class LiveSocket: NSObject, @unchecked Sendable {
    enum Event: Sendable {
        case opened
        case message(LiveServerMessage)
        case closed(code: Int, reason: String)
        case failed(String)
    }

    let id = UUID()
    let events: AsyncStream<Event>

    /// Frames queued but not yet written — lets callers skip a video
    /// frame instead of piling more onto a slow link.
    var backlog: Int { pendingSends.load(ordering: .relaxed) }

    private static let log = Logger(subsystem: "com.vocavision.app", category: "socket")
    private let eventContinuation: AsyncStream<Event>.Continuation
    private let outbound: AsyncStream<Data>
    private let outboundContinuation: AsyncStream<Data>.Continuation
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var sendTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private let decoder = JSONDecoder()
    private let isFinished = Atomic<Bool>(false)
    private let pendingSends = Atomic<Int>(0)
    private let droppedSends = Atomic<Int>(0)
    private let maxPendingDroppable = 150
    private let request: URLRequest

    init(request: URLRequest) {
        self.request = request
        (events, eventContinuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        (outbound, outboundContinuation) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        super.init()
    }

    func connect() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        config.networkServiceType = .voice
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        let session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        self.session = session
        var request = self.request
        request.timeoutInterval = 30
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 16 * 1024 * 1024
        self.task = task
        task.resume()
    }

    func close(code: URLSessionWebSocketTask.CloseCode = .normalClosure) {
        guard !isFinished.exchange(true, ordering: .acquiringAndReleasing) else { return }
        receiveTask?.cancel(); sendTask?.cancel(); pingTask?.cancel()
        outboundContinuation.finish()
        task?.cancel(with: code, reason: nil)
        session?.invalidateAndCancel()
        eventContinuation.finish()
    }

    /// Enqueues an encoded JSON frame; `droppable` (audio) frames are
    /// discarded when the network is backed up.
    func send(_ json: Data, droppable: Bool) {
        guard !isFinished.load(ordering: .relaxed) else { return }
        let pending = pendingSends.load(ordering: .relaxed)
        if droppable, pending > maxPendingDroppable {
            let dropped = droppedSends.wrappingAdd(1, ordering: .relaxed).oldValue + 1
            if dropped == 1 || dropped % 100 == 0 {
                vlog("live", "⚠️ outbound backlog (\(pending)) — dropped \(dropped) audio frames", level: .warning)
            }
            return
        }
        pendingSends.wrappingAdd(1, ordering: .relaxed)
        outboundContinuation.yield(json)
    }

    private func startSendLoop() {
        guard sendTask == nil, let task else { return }
        let stream = outbound
        sendTask = Task { [weak self] in
            for await frame in stream {
                guard let self, !self.isFinished.load(ordering: .relaxed) else { return }
                self.pendingSends.wrappingSubtract(1, ordering: .relaxed)
                do {
                    guard let string = String(data: frame, encoding: .utf8) else { continue }
                    try await task.send(.string(string))
                } catch {
                    self.fail("send: \(error.localizedDescription)")
                    return
                }
            }
        }
    }

    private func startReceiveLoop() {
        guard receiveTask == nil, let task else { return }
        receiveTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    self.handle(try await task.receive())
                } catch {
                    if !self.isFinished.load(ordering: .relaxed) { self.fail("receive: \(error.localizedDescription)") }
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        guard pingTask == nil else { return }
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard let self, let task = self.task, task.state == .running else { return }
                task.sendPing { error in
                    if let error { Self.log.notice("ping failed: \(error.localizedDescription, privacy: .public)") }
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        do {
            eventContinuation.yield(.message(try decoder.decode(LiveServerMessage.self, from: data)))
        } catch {
            let preview = String(decoding: data.prefix(300), as: UTF8.self)
            vlog("live", "⚠️ undecodable frame: \(preview)", level: .warning)
        }
    }

    private func fail(_ reason: String) {
        guard !isFinished.load(ordering: .relaxed) else { return }
        eventContinuation.yield(.failed(reason))
        close(code: .abnormalClosure)
    }
}

nonisolated extension LiveSocket: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        vlog("live", "🤝 socket open")
        startSendLoop(); startReceiveLoop(); startPingLoop()
        eventContinuation.yield(.opened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let text = reason.map { String(decoding: $0, as: UTF8.self) } ?? ""
        vlog("live", "🚪 socket closed code=\(closeCode.rawValue) reason=\(text)", level: .warning)
        guard !isFinished.load(ordering: .relaxed) else { return }
        eventContinuation.yield(.closed(code: closeCode.rawValue, reason: text))
        close(code: closeCode)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        vlog("live", "💥 socket task failed domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)", level: .error)
        fail(ns.localizedDescription)
    }
}
