import Accelerate
import AVFoundation
import Foundation
import os
import Synchronization

/// Real-time audio I/O for one Voca call.
///
/// **Capture** — the microphone goes through Apple's voice-processing
/// I/O unit (acoustic echo cancellation, noise suppression, automatic
/// gain) so the speaker's playback of Voca's own voice does not leak
/// back into the stream and trigger a server-side interruption. The
/// tap output is converted to 16 kHz Int16 mono in `MicPipeline` and
/// emitted as fixed 40 ms chunks.
///
/// **Playback** — server audio (24 kHz Int16 mono) is written into a
/// lock-free `PlaybackRingBuffer`; an `AVAudioSourceNode` pulls from it
/// on the render thread. That decouples playback from network jitter,
/// which is what removes the stutter an `AVAudioPlayerNode` shows when
/// chunks arrive late. `flushPlayback()` empties the buffer instantly
/// when the user barges in.
///
/// **Session ownership** — when the call runs under CallKit (the normal
/// path) the *system* activates and deactivates the audio session; we
/// only configure the category. `managesSessionActivation` flips that
/// for the rare non-CallKit fallback.
@MainActor
final class CallAudioEngine {
    enum AudioError: Error, LocalizedError {
        case sessionConfigureFailed(String)
        case sessionActivationFailed(String)
        case engineStartFailed(String)

        var errorDescription: String? {
            switch self {
            case .sessionConfigureFailed(let msg):
                return tr(ar: "تعذّر تهيئة جلسة الصوت: \(msg)", en: "Couldn't configure the audio session: \(msg)")
            case .sessionActivationFailed(let msg):
                return tr(ar: "تعذّر تفعيل جلسة الصوت: \(msg)", en: "Couldn't activate the audio session: \(msg)")
            case .engineStartFailed(let msg):
                return tr(ar: "تعذّر تشغيل محرك الصوت: \(msg)", en: "Couldn't start the audio engine: \(msg)")
            }
        }
    }

    nonisolated static let captureSampleRate: Double = 16_000
    nonisolated static let playbackSampleRate: Double = 24_000

    // MARK: Public state

    private(set) var isRunning = false
    private(set) var isMicMuted = false
    private(set) var isOutputMuted = false
    private(set) var isVoiceProcessingActive = false

    /// `true` only when no CallKit call owns the session.
    var managesSessionActivation = false

    /// Fires (on the main actor) when the user speaks while muted —
    /// the system's voice-processing unit detects it for us.
    var onMutedSpeechDetected: (() -> Void)?

    /// `true` while there is still Voca audio waiting to be rendered.
    nonisolated var isPlayingAudio: Bool { !ring.isEmpty }

    /// Seconds of Voca audio queued but not yet heard.
    nonisolated var bufferedPlaybackSeconds: Double { ring.bufferedSeconds }

    /// Milliseconds of the current reply the user actually heard —
    /// what the server should keep when the user interrupts.
    nonisolated var playedMillisecondsOfCurrentReply: Int {
        let rendered = ring.totalFramesRendered - replyStartRendered.load(ordering: .relaxed)
        return max(0, Int(Double(rendered) / Self.playbackSampleRate * 1000))
    }
    private let replyStartRendered = Atomic<Int>(0)

    // MARK: Private

    private let engine = AVAudioEngine()
    private let ring = PlaybackRingBuffer(
        sampleRate: CallAudioEngine.playbackSampleRate,
        seconds: 120,
        primeMilliseconds: 120
    )
    private let micPipeline = MicPipeline(
        targetSampleRate: CallAudioEngine.captureSampleRate,
        chunkMilliseconds: 40
    )
    private var sourceNode: AVAudioSourceNode?
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: CallAudioEngine.playbackSampleRate,
        channels: 1,
        interleaved: false
    )!
    private var observers: [NSObjectProtocol] = []
    private static let log = Logger(subsystem: "com.vocavision.app", category: "audio")

    init() {}

    // MARK: Session

    /// Category/mode for a two-way voice+camera call. Safe to call
    /// repeatedly; CallKit's start action calls it *before* fulfilling
    /// so the system activates the session with the right settings.
    nonisolated static func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
            )
        } catch {
            throw AudioError.sessionConfigureFailed(error.localizedDescription)
        }
        // Alerts (timers, notifications) must not knock a call off the
        // speaker; the system honours this for call-style apps.
        try? session.setPrefersNoInterruptionsFromSystemAlerts(true)
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.02)
    }

    // MARK: Lifecycle

    func setMicChunkHandler(_ block: (@Sendable (MicChunk) -> Void)?) {
        micPipeline.setHandler(block)
    }

    func start() throws {
        guard !isRunning else { return }
        vlog("audio", "▶️ engine start (sessionManaged=\(managesSessionActivation ? "app" : "system"))")

        let session = AVAudioSession.sharedInstance()
        if managesSessionActivation {
            try Self.configureSession()
            do {
                try session.setActive(true, options: [])
            } catch {
                throw AudioError.sessionActivationFailed(error.localizedDescription)
            }
        }
        logSessionState(session)

        ring.flush()
        micPipeline.reset()

        // Voice processing must be toggled while the engine is stopped.
        let input = engine.inputNode
        do {
            try input.setVoiceProcessingEnabled(true)
            isVoiceProcessingActive = input.isVoiceProcessingEnabled
            input.isVoiceProcessingAGCEnabled = true
            input.setMutedSpeechActivityEventListener { @Sendable [weak self] event in
                guard event == .started else { return }
                Task { @MainActor [weak self] in self?.onMutedSpeechDetected?() }
            }
            vlog("audio", "🛡 voice processing on (AEC + NS + AGC), output=\(engine.outputNode.isVoiceProcessingEnabled)")
        } catch {
            isVoiceProcessingActive = false
            vlog("audio", "⚠️ voice processing unavailable: \(error.localizedDescription)", level: .warning)
        }

        attachSourceNode()

        engine.prepare()
        do {
            try engine.start()
        } catch {
            vlog("audio", "❌ engine.start failed: \(error.localizedDescription)", level: .error)
            throw AudioError.engineStartFailed(error.localizedDescription)
        }

        installTap()
        registerObservers()
        applyMuteStates()
        isRunning = true

        let inFmt = input.outputFormat(forBus: 0)
        vlog("audio", "✅ engine running — mic \(Int(inFmt.sampleRate)) Hz/\(inFmt.channelCount) ch → 16 kHz, playback 24 kHz via source node")
    }

    func stop() {
        guard isRunning else { return }
        vlog("audio", "⏹ engine stop")
        removeObservers()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        ring.flush()
        micPipeline.reset()
        isRunning = false
        if managesSessionActivation {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    // MARK: Mute

    func setMicMuted(_ muted: Bool) {
        isMicMuted = muted
        applyMuteStates()
        vlog("audio", muted ? "🔇 mic muted" : "🎙 mic live")
    }

    func setOutputMuted(_ muted: Bool) {
        isOutputMuted = muted
        applyMuteStates()
    }

    private func applyMuteStates() {
        micPipeline.isMuted = isMicMuted
        if isVoiceProcessingActive {
            engine.inputNode.isVoiceProcessingInputMuted = isMicMuted
        }
        engine.mainMixerNode.outputVolume = isOutputMuted ? 0 : 1
    }

    // MARK: Playback (single producer: the Live client's receive loop)

    /// Queues a 24 kHz Int16 mono chunk. Returns immediately; the render
    /// thread plays it at the hardware cadence.
    nonisolated func enqueue(pcm24k data: Data) {
        let frameCount = data.count / MemoryLayout<Int16>.size
        guard frameCount > 0 else { return }
        if ring.isEmpty, replyArmed.exchange(false, ordering: .acquiringAndReleasing) {
            replyStartRendered.store(ring.totalFramesRendered, ordering: .relaxed)
        }
        var floats = [Float](repeating: 0, count: frameCount)
        data.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
            floats.withUnsafeMutableBufferPointer { dst in
                vDSP_vflt16(src, 1, dst.baseAddress!, 1, vDSP_Length(frameCount))
                var scale = Float(1.0 / 32768.0)
                vDSP_vsmul(dst.baseAddress!, 1, &scale, dst.baseAddress!, 1, vDSP_Length(frameCount))
            }
        }
        _ = floats.withUnsafeBufferPointer { ring.write($0) }
    }

    /// The server finished a reply — play out the tail immediately and
    /// arm the played-ms counter for the next reply.
    nonisolated func markReplyComplete() {
        ring.markEndOfBurst()
        replyArmed.store(true, ordering: .relaxed)
    }
    private let replyArmed = Atomic<Bool>(true)

    /// Drops everything queued (user interrupted Voca).
    nonisolated func flushPlayback() {
        ring.flush()
        replyArmed.store(true, ordering: .relaxed)
    }

    // MARK: Graph

    private func attachSourceNode() {
        if let sourceNode {
            engine.disconnectNodeOutput(sourceNode)
            engine.detach(sourceNode)
        }
        let ring = self.ring
        // `@Sendable` keeps this closure nonisolated: with MainActor as the
        // default isolation, an un-annotated closure would be inferred as
        // main-actor-isolated and the runtime traps when the real-time
        // audio thread calls it (that was the crash on call start).
        let node = AVAudioSourceNode(format: playbackFormat) { @Sendable isSilence, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let mData = buffers[0].mData else { return noErr }
            let out = mData.assumingMemoryBound(to: Float.self)
            let hasAudio = ring.render(into: out, frameCount: Int(frameCount))
            isSilence.pointee = ObjCBool(!hasAudio)
            return noErr
        }
        engine.attach(node)
        do {
            try connect(node, to: engine.mainMixerNode, format: playbackFormat)
        } catch {
            vlog("audio", "❌ source node connect failed: \(error.localizedDescription)", level: .error)
        }
        sourceNode = node
    }

    /// iOS 27 made `connect(_:to:format:)` throwing; keep one call site.
    private func connect(_ node: AVAudioNode, to target: AVAudioNode, format: AVAudioFormat) throws {
        if #available(iOS 27.0, *) {
            try engine.connectNode(node, to: target, format: format)
        } else {
            engine.connect(node, to: target, format: format)
        }
    }

    private func installTap() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let pipeline = micPipeline
        // `format: nil` → the node's own output format, which is the
        // only safe choice once voice processing rewrites the I/O
        // formats. The pipeline re-creates its converter if it changes.
        // Taps deliver ≥ 100 ms per buffer; ask for exactly that.
        let rate = input.outputFormat(forBus: 0).sampleRate
        let bufferSize = AVAudioFrameCount(max(rate, 8_000) * 0.1)
        if #available(iOS 27.0, *) {
            do {
                try input.installAudioTap(onBus: 0, bufferSize: bufferSize, format: nil) { readOnly, _ in
                    pipeline.process(AVAudioPCMBuffer(copying: readOnly))
                }
            } catch {
                vlog("audio", "❌ tap install failed: \(error.localizedDescription)", level: .error)
            }
        } else {
            input.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { @Sendable buffer, _ in
                pipeline.process(buffer)
            }
        }
    }

    // MARK: Observers

    private func registerObservers() {
        removeObservers()
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: session, queue: .main
        ) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            MainActor.assumeIsolated { self?.handleRouteChange(reason) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: session, queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            let optRaw = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
            MainActor.assumeIsolated { self?.handleInterruption(type, shouldResume: shouldResume) }
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    /// iOS rebuilt the I/O graph (new route, sample-rate change, voice
    /// processing kicking in). Our custom connections must be re-made.
    private func handleConfigurationChange() {
        guard isRunning else { return }
        vlog("audio", "🔁 engine configuration changed — re-wiring", level: .warning)
        attachSourceNode()
        restartEngineIfNeeded()
        installTap()
        applyMuteStates()
    }

    private func handleRouteChange(_ reason: AVAudioSession.RouteChangeReason?) {
        vlog("audio", "🔀 route change: \(reason.map { String(describing: $0) } ?? "?")")
        logSessionState(AVAudioSession.sharedInstance())
        guard isRunning else { return }
        restartEngineIfNeeded()
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            vlog("audio", "⏸ interruption began", level: .warning)
        case .ended:
            vlog("audio", "▶️ interruption ended (resume=\(shouldResume))")
            guard isRunning, shouldResume else { return }
            if managesSessionActivation {
                try? AVAudioSession.sharedInstance().setActive(true, options: [])
            }
            restartEngineIfNeeded()
        @unknown default:
            break
        }
    }

    private func handleMediaServicesReset() {
        vlog("audio", "💥 media services reset — rebuilding engine", level: .error)
        guard isRunning else { return }
        let mic = isMicMuted, out = isOutputMuted
        stop()
        isMicMuted = mic
        isOutputMuted = out
        try? start()
    }

    private func restartEngineIfNeeded() {
        guard isRunning, !engine.isRunning else { return }
        do {
            try engine.start()
            vlog("audio", "🔁 engine restarted")
        } catch {
            Self.log.error("Engine restart failed: \(error.localizedDescription, privacy: .public)")
            vlog("audio", "❌ engine restart failed: \(error.localizedDescription)", level: .error)
        }
    }

    private func logSessionState(_ session: AVAudioSession) {
        let route = session.currentRoute
        let inputs = route.inputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        let outputs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        vlog("audio", "🔍 session sr=\(Int(session.sampleRate)) io=\(Int(session.ioBufferDuration * 1000)) ms cat=\(session.category.rawValue) mode=\(session.mode.rawValue)")
        vlog("audio", "🔍 route in=[\(inputs)] out=[\(outputs)]")
    }
}
