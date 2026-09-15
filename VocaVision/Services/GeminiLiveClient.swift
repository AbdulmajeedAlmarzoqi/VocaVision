import Foundation
import Observation
import os

/// Session-level client for the Gemini Live API.
///
/// Owns the conversation state the UI observes and what keeps a long
/// call alive on top of a 10-minute WebSocket: session resumption
/// (graceful rotation on `goAway`, retries on drops) and context-window
/// compression (no 2-minute audio+video cap). Wire protocol in
/// `LiveMessages.swift`; ordered transport in `LiveSocket`.
@Observable
@MainActor
final class GeminiLiveClient {
    enum SessionState: Equatable {
        case disconnected, connecting, ready, reconnecting
        case error(String)
    }

    struct Configuration: Sendable {
        var apiKey: String
        var model: String
        var voiceName: String
        var systemInstruction: String
        var bargeInEnabled: Bool
        /// 2.5 native-audio only: the model may decide not to answer
        /// irrelevant input and can react without an explicit prompt.
        var proactiveAudio: Bool = false
        var affectiveDialog: Bool = false
        var tools: [LiveClientMessage.FunctionDeclaration] = []
    }

    struct FunctionCall: Sendable {
        let id: String?
        let name: String
        let args: [String: JSONValue]
    }

    static let endpoint = URL(string:
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    )!

    // MARK: Observable state

    private(set) var state: SessionState = .disconnected
    private(set) var inputTranscript = ""
    private(set) var interimInputTranscript = ""
    private(set) var outputTranscript = ""
    private(set) var modelIsSpeaking = false
    private(set) var lastUserActivityAt: Date?
    private(set) var reconnectCount = 0

    func userIsActive(within window: TimeInterval, of now: Date = Date()) -> Bool {
        guard let last = lastUserActivityAt else { return false }
        return now.timeIntervalSince(last) < window
    }

    // MARK: Callbacks (main actor)

    var onAudioChunk: ((Data) -> Void)?
    var onInterrupted: (() -> Void)?
    var onGenerationComplete: (() -> Void)?
    var onTurnComplete: (() -> Void)?
    var onToolCall: ((FunctionCall) -> Void)?
    /// The model started pronouncing an app control message.
    var onProtocolLeak: (() -> Void)?

    // MARK: Private

    private static let log = Logger(subsystem: "com.vocavision.app", category: "live")
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private var configuration: Configuration?
    @ObservationIgnored private var socket: LiveSocket?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var resumptionHandle: String?
    @ObservationIgnored private var isEndedByUser = false
    @ObservationIgnored private var isSwappingSockets = false
    @ObservationIgnored private var sentAudioChunks = 0

    // MARK: - Connect / disconnect

    @discardableResult
    func connect(_ config: Configuration) async -> Bool {
        guard !config.apiKey.isEmpty else {
            state = .error(tr(ar: "لا يوجد مفتاح Gemini محفوظ.", en: "No Gemini key is saved."))
            return false
        }
        configuration = config
        isEndedByUser = false
        resumptionHandle = nil
        reconnectCount = 0
        resetTurnState()
        state = .connecting
        vlog("live", "▶️ connect model=\(config.model) voice=\(config.voiceName) bargeIn=\(config.bargeInEnabled) proactive=\(config.proactiveAudio)")
        do {
            let socket = try await openSession(config: config, resumeHandle: nil)
            adopt(socket)
            state = .ready
            vlog("live", "✅ session ready")
            return true
        } catch {
            state = .error(error.localizedDescription)
            vlog("live", "❌ connect failed: \(error.localizedDescription)", level: .error)
            return false
        }
    }

    func disconnect() {
        isEndedByUser = true
        eventTask?.cancel(); eventTask = nil
        socket?.close(); socket = nil
        modelIsSpeaking = false
        state = .disconnected
    }

    // MARK: - Realtime input

    func sendAudioChunk(_ pcm16k: Data) {
        guard state == .ready, !pcm16k.isEmpty else { return }
        sentAudioChunks += 1
        if sentAudioChunks == 1 { vlog("live", "📤 first audio chunk (\(pcm16k.count) B)") }
        send(.init(realtimeInput: .init(audio: .init(data: pcm16k, mimeType: "audio/pcm;rate=16000"))), droppable: true)
    }

    /// A live video frame (JPEG). Frames join the model's next turn.
    /// Returns false when the link is backed up and the frame was skipped.
    @discardableResult
    func sendVideoFrame(_ jpeg: Data, skipIfBacklogged: Bool = false) -> Bool {
        guard state == .ready, !jpeg.isEmpty, let socket else { return false }
        if skipIfBacklogged, socket.backlog > 6 { return false }
        send(.init(realtimeInput: .init(video: .init(data: jpeg, mimeType: "image/jpeg"))), droppable: false)
        return true
    }

    /// Outbound frames still waiting to be written.
    var outboundBacklog: Int { socket?.backlog ?? 0 }

    /// Text from the app (typed instruction or trigger). Sent as
    /// realtime input — on 3.1 `clientContent` is history-seeding only.
    func sendText(_ text: String) {
        guard state == .ready, !text.isEmpty else { return }
        send(.init(realtimeInput: .init(text: text)), droppable: false)
    }

    func sendAudioStreamEnd() {
        guard state == .ready else { return }
        send(.init(realtimeInput: .init(audioStreamEnd: true)), droppable: false)
    }

    func sendToolResponse(id: String?, name: String, response: [String: JSONValue]) {
        guard let socket else { return }
        let envelope = LiveClientMessage.ToolResponseEnvelope(
            toolResponse: .init(functionResponses: [.init(id: id, name: name, response: response)])
        )
        guard let data = try? encoder.encode(envelope) else { return }
        socket.send(data, droppable: false)
        vlog("live", "🛠 toolResponse \(name)")
    }

    private func send(_ envelope: LiveClientMessage.RealtimeInputEnvelope, droppable: Bool) {
        guard let socket, let data = try? encoder.encode(envelope) else { return }
        socket.send(data, droppable: droppable)
    }

    // MARK: - Session plumbing

    private struct SetupFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func openSession(config: Configuration, resumeHandle: String?) async throws -> LiveSocket {
        var request = URLRequest(url: Self.endpoint)
        request.setValue(config.apiKey, forHTTPHeaderField: "x-goog-api-key")
        let socket = LiveSocket(request: request)
        socket.connect()

        let setup = makeSetup(config: config, resumeHandle: resumeHandle)
        let setupData = try encoder.encode(LiveClientMessage.SetupEnvelope(setup: setup))
        var iterator = socket.events.makeAsyncIterator()

        guard let first = await iterator.next() else {
            throw SetupFailure(message: tr(ar: "تعذّر فتح الاتصال.", en: "Couldn't open the connection."))
        }
        switch first {
        case .opened: break
        case .failed(let reason):
            socket.close(); throw SetupFailure(message: tr(ar: "تعذّر الاتصال: \(reason)", en: "Connection failed: \(reason)"))
        case .closed(let code, let reason):
            socket.close(); throw SetupFailure(message: closeMessage(code: code, reason: reason))
        case .message: break
        }

        socket.send(setupData, droppable: false)
        vlog("live", "📤 setup sent (resume=\(resumeHandle != nil)) — awaiting setupComplete")

        while let event = await iterator.next() {
            switch event {
            case .message(let message):
                if message.setupComplete != nil { return socket }
                if let error = message.error {
                    socket.close()
                    throw SetupFailure(message: error.message ?? tr(ar: "رفض الخادم الإعداد.", en: "The server rejected the setup."))
                }
                if let update = message.sessionResumptionUpdate { applyResumption(update) }
            case .failed(let reason):
                socket.close(); throw SetupFailure(message: tr(ar: "تعذّر الاتصال: \(reason)", en: "Connection failed: \(reason)"))
            case .closed(let code, let reason):
                socket.close(); throw SetupFailure(message: closeMessage(code: code, reason: reason))
            case .opened: continue
            }
        }
        socket.close()
        throw SetupFailure(message: tr(ar: "أُغلق الاتصال قبل اكتمال الإعداد.", en: "The connection closed before setup completed."))
    }

    private func makeSetup(config: Configuration, resumeHandle: String?) -> LiveClientMessage.Setup {
        let vad = LiveClientMessage.RealtimeInputConfig.AutomaticActivityDetection(
            disabled: false,
            startOfSpeechSensitivity: config.bargeInEnabled ? "START_SENSITIVITY_LOW" : "START_SENSITIVITY_HIGH",
            endOfSpeechSensitivity: "END_SENSITIVITY_LOW",
            prefixPaddingMs: config.bargeInEnabled ? 150 : 60,
            silenceDurationMs: 600
        )
        var generation = LiveClientMessage.GenerationConfig(speechConfig: .init(voiceName: config.voiceName))
        if config.affectiveDialog { generation.enableAffectiveDialog = true }
        var setup = LiveClientMessage.Setup(
            model: config.model,
            generationConfig: generation,
            systemInstruction: .init(text: config.systemInstruction),
            realtimeInputConfig: .init(automaticActivityDetection: vad),
            sessionResumption: .init(handle: resumeHandle),
            proactivity: config.proactiveAudio ? .init(proactiveAudio: true) : nil,
            tools: config.tools.isEmpty ? nil : [.init(functionDeclarations: config.tools)]
        )
        setup.inputAudioTranscription.customVocabulary = ["راقب", "تابع", "وقف المراقبة", "Voca"]
        return setup
    }

    private func adopt(_ socket: LiveSocket) {
        let previous = self.socket
        eventTask?.cancel()
        self.socket = socket
        previous?.close()
        let socketID = socket.id
        eventTask = Task { [weak self] in
            for await event in socket.events {
                guard let self, self.socket?.id == socketID else { return }
                self.handle(event)
            }
        }
    }

    private func handle(_ event: LiveSocket.Event) {
        switch event {
        case .opened: break
        case .message(let message): handle(message)
        case .closed(let code, let reason): handleTransportLoss(closeMessage(code: code, reason: reason))
        case .failed(let reason): handleTransportLoss(tr(ar: "انقطع الاتصال: \(reason)", en: "Connection lost: \(reason)"))
        }
    }

    private func handle(_ message: LiveServerMessage) {
        if let update = message.sessionResumptionUpdate { applyResumption(update) }
        if let content = message.serverContent { handleServerContent(content) }
        if let goAway = message.goAway {
            vlog("live", "⏳ goAway (timeLeft=\(goAway.timeLeft ?? "?")) — rotating connection", level: .warning)
            Task { await self.rotateConnection() }
        }
        if let error = message.error {
            let text = error.message ?? tr(ar: "خطأ غير معروف من الخادم.", en: "Unknown server error.")
            vlog("live", "❌ server error: \(text)", level: .error)
            state = .error(text)
        }
        if let usage = message.usageMetadata, let total = usage.totalTokenCount {
            Self.log.debug("usage total=\(total, privacy: .public)")
        }
        if let calls = message.toolCall?.functionCalls {
            for call in calls {
                guard let name = call.name else { continue }
                vlog("live", "🛠 toolCall \(name) \(call.args ?? [:])")
                onToolCall?(FunctionCall(id: call.id, name: name, args: call.args ?? [:]))
            }
        }
        if let cancelled = message.toolCallCancellation?.ids {
            vlog("live", "🛠 toolCallCancellation \(cancelled)", level: .debug)
        }
    }

    private func handleServerContent(_ content: LiveServerMessage.ServerContent) {
        if content.interrupted == true {
            vlog("live", "✋ interrupted — flushing playback")
            modelIsSpeaking = false
            onInterrupted?()
        }
        if let t = content.interimInputTranscription?.text, !t.isEmpty {
            interimInputTranscript = t
            lastUserActivityAt = Date()
        }
        if let t = content.inputTranscription?.text, !t.isEmpty {
            inputTranscript += t
            interimInputTranscript = ""
            lastUserActivityAt = Date()
            vlog("live", "🗣 user: \(t)")
        }
        if let t = content.outputTranscription?.text, !t.isEmpty {
            outputTranscript += t
            if Self.protocolTokens.contains(where: { outputTranscript.localizedCaseInsensitiveContains($0) }) {
                vlog("live", "🚫 protocol leak in speech — cutting off", level: .warning)
                onProtocolLeak?()
            }
        }
        if let parts = content.modelTurn?.parts {
            for part in parts {
                guard let inline = part.inlineData, !inline.data.isEmpty else { continue }
                if !modelIsSpeaking { vlog("live", "🔊 reply audio started"); modelIsSpeaking = true }
                onAudioChunk?(inline.data)
            }
        }
        if content.generationComplete == true {
            vlog("live", "✓ generationComplete")
            onGenerationComplete?()
        }
        if content.turnComplete == true {
            if !outputTranscript.isEmpty { vlog("live", "🤖 voca: \(outputTranscript)") }
            modelIsSpeaking = false
            onTurnComplete?()
            inputTranscript = ""
            interimInputTranscript = ""
            outputTranscript = ""
        }
    }

    private func applyResumption(_ update: LiveServerMessage.SessionResumptionUpdate) {
        if update.resumable == true, let handle = update.newHandle, !handle.isEmpty { resumptionHandle = handle }
    }

    // MARK: - Reconnect

    private func rotateConnection() async {
        guard let configuration, !isEndedByUser, !isSwappingSockets else { return }
        isSwappingSockets = true
        defer { isSwappingSockets = false }
        do {
            let replacement = try await openSession(config: configuration, resumeHandle: resumptionHandle)
            guard !isEndedByUser else { replacement.close(); return }
            adopt(replacement)
            reconnectCount += 1
            state = .ready
            vlog("live", "🔁 connection rotated (#\(reconnectCount))")
        } catch {
            vlog("live", "⚠️ rotation failed: \(error.localizedDescription) — will retry on drop", level: .warning)
        }
    }

    private func handleTransportLoss(_ message: String) {
        guard !isEndedByUser else { return }
        guard let configuration else { state = .error(message); return }
        modelIsSpeaking = false
        state = .reconnecting
        vlog("live", "🔌 transport lost — reconnecting: \(message)", level: .warning)
        Task { await self.reconnect(config: configuration, lastError: message) }
    }

    private func reconnect(config: Configuration, lastError: String) async {
        guard !isSwappingSockets else { return }
        isSwappingSockets = true
        defer { isSwappingSockets = false }
        var lastMessage = lastError
        for attempt in 1...3 {
            guard !isEndedByUser else { return }
            do {
                let replacement = try await openSession(config: config, resumeHandle: resumptionHandle)
                guard !isEndedByUser else { replacement.close(); return }
                adopt(replacement)
                reconnectCount += 1
                state = .ready
                vlog("live", "🔁 reconnected on attempt \(attempt) (resume=\(resumptionHandle != nil))")
                return
            } catch {
                lastMessage = error.localizedDescription
                vlog("live", "⚠️ reconnect attempt \(attempt) failed: \(lastMessage)", level: .warning)
                if attempt == 2 { resumptionHandle = nil }
                try? await Task.sleep(for: .milliseconds(400 * attempt))
            }
        }
        state = .error(lastMessage)
    }

    // MARK: - Helpers

    /// Fragments of app control messages that must never be spoken.
    private static let protocolTokens = ["[WATCH", "WATCH]", "nothing_changed", "set_watch_mode", "HEARTBEAT"]

    private func resetTurnState() {
        inputTranscript = ""; interimInputTranscript = ""; outputTranscript = ""
        modelIsSpeaking = false; lastUserActivityAt = nil; sentAudioChunks = 0
    }

    private func closeMessage(code: Int, reason: String) -> String {
        let detail = reason.isEmpty ? "" : " — \(reason)"
        switch code {
        case 1008: return tr(ar: "رفض الخادم الجلسة (1008)\(detail).", en: "The server rejected the session (1008)\(detail).")
        default: return tr(ar: "أُغلق الاتصال (الرمز \(code))\(detail).", en: "Connection closed (code \(code))\(detail).")
        }
    }
}
