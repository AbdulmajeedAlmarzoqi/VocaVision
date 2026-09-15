import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Observation

/// Coordinates one Voca call on top of the Gemini Live API.
///
/// **Live video** (always on): the camera is streamed to the model as
/// JPEG frames at the API's rate limit (1 fps while watching, 0.5 fps in
/// plain conversation). With Gemini 3.1's turn coverage every frame
/// since the last turn is part of the next turn, so the model answers
/// about what it is seeing *now*, not a stale snapshot.
///
/// **Watch** (on request): Google's documented proactive pattern —
/// video frames never trigger a turn on their own, so the app sends a
/// short private `[WATCH]` ping after each turn completes. The model
/// compares the newest frames with what it last said and either speaks
/// the change or calls the silent `nothing_changed` tool. Pings are
/// driven by the on-device detectors (re-aim settled, picture changed,
/// menu highlight moved, page changed) with a slow idle cadence as a
/// safety net, and are never sent while anyone is talking.
@Observable
@MainActor
final class SpeechFeedbackOrchestrator {
    enum Status: Equatable {
        case idle, starting, listening, userSpeaking, modelSpeaking, reconnecting
        case error(String)
    }

    enum WatchFocus: String, Sendable { case auto, screen, scene }

    private(set) var status: Status = .idle
    private(set) var isWatching = false
    private(set) var watchFocus: WatchFocus = .auto
    var inputTranscript: String { live.inputTranscript }
    var interimInputTranscript: String { live.interimInputTranscript }
    var outputTranscript: String { live.outputTranscript }

    private let camera: CameraService
    private let motion: MotionService
    private let audio: CallAudioEngine
    private let live: GeminiLiveClient
    private let customization: CustomizationStore
    private let apiKey: () -> String?
    private let detector = SceneChangeDetector()
    private let screenWatcher = ScreenWatcher()

    private var watchTask: Task<Void, Never>?
    private var videoTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var mirrorTask: Task<Void, Never>?
    private var isMicPaused = false

    var onSessionReady: (() -> Void)?
    var onWatchModeChanged: ((Bool) -> Void)?

    init(camera: CameraService, motion: MotionService, audio: CallAudioEngine,
         live: GeminiLiveClient, customization: CustomizationStore, apiKey: @escaping () -> String?) {
        self.camera = camera
        self.motion = motion
        self.audio = audio
        self.live = live
        self.customization = customization
        self.apiKey = apiKey
    }

    // MARK: Lifecycle

    func start() {
        guard sessionTask == nil else { return }
        status = .starting
        sessionTask = Task { [weak self] in await self?.runSession() }
    }

    func stop() {
        watchTask?.cancel(); watchTask = nil
        videoTask?.cancel(); videoTask = nil
        mirrorTask?.cancel(); mirrorTask = nil
        sessionTask?.cancel(); sessionTask = nil
        detector.enabled = false
        live.disconnect()
        audio.flushPlayback()
        status = .idle
    }

    /// Typed instruction — the user's words, with the live view already
    /// in the stream.
    func sendInstruction(_ text: String) {
        sendCurrentFrame(reason: "instruction")
        live.sendText(text)
    }

    func setMicPaused(_ paused: Bool) {
        isMicPaused = paused
    }

    func setWatching(_ enabled: Bool, focus: WatchFocus = .auto) {
        let changed = isWatching != enabled || watchFocus != focus
        isWatching = enabled
        watchFocus = focus
        detector.enabled = enabled
        detector.reset()
        screenWatcher.reset()
        pendingEvent = nil
        noScreenSamples = 0
        camera.setZoom(enabled && focus != .scene ? 1.6 : 1.0)
        vlog("session", enabled ? "👁 watch mode ON (\(focus.rawValue))" : "👁 watch mode OFF")
        if changed { onWatchModeChanged?(enabled) }
    }

    // MARK: Session

    private func runSession() async {
        vlog("session", "🚀 runSession")
        guard let key = apiKey(), !key.isEmpty else {
            status = .error(tr(ar: "أضِف مفتاح Gemini من الإعدادات لتبدأ المكالمة.", en: "Add a Gemini key in Settings before starting a call."))
            return
        }
        let model = await GeminiClient.preferredLiveModel(apiKey: key)
        vlog("session", "🧬 model: \(model)")

        live.onAudioChunk = { [weak self] data in
            guard let self else { return }
            self.audio.enqueue(pcm24k: data)
            if self.status != .modelSpeaking, self.status != .reconnecting { self.status = .modelSpeaking }
        }
        live.onInterrupted = { [weak self] in
            self?.audio.flushPlayback()
            self?.status = .userSpeaking
        }
        live.onGenerationComplete = { [weak self] in
            self?.audio.markReplyComplete()
        }
        live.onTurnComplete = { [weak self] in
            guard let self else { return }
            self.audio.markReplyComplete()
            self.pingInFlight = false
            self.lastTurnCompletedAt = Date()
            if self.status == .modelSpeaking || self.status == .userSpeaking { self.status = .listening }
        }
        live.onToolCall = { [weak self] call in self?.handleToolCall(call) }
        live.onProtocolLeak = { [weak self] in
            self?.audio.flushPlayback()
        }

        let voice = customization.voice
        // Proactive audio lets the 2.5 native-audio model swallow a ping
        // silently; 3.1 rejects the field, so only send it where it works.
        let isNativeAudio25 = model.contains("native-audio")
        let config = GeminiLiveClient.Configuration(
            apiKey: key,
            model: model,
            voiceName: voice.id,
            systemInstruction: customization.resolvedSystemPrompt(),
            bargeInEnabled: customization.bargeInEnabled,
            proactiveAudio: isNativeAudio25,
            affectiveDialog: false,
            tools: Self.toolDeclarations
        )
        vlog("session", "🧬 voice=\(voice.id) dialect=\(customization.dialect.id) preset=\(customization.preset.rawValue) bargeIn=\(config.bargeInEnabled)")

        let ready = await live.connect(config)
        guard !Task.isCancelled else { return }
        if ready {
            status = .listening
            onSessionReady?()
            startVideoStream()
            startWatchLoop()
            startStateMirror()
        } else if case .error(let message) = live.state {
            status = .error(message)
        } else {
            status = .error(tr(ar: "تعذَّر الاتصال بـ Voca.", en: "Couldn't connect to Voca."))
        }
    }

    private func startStateMirror() {
        mirrorTask?.cancel()
        mirrorTask = Task { [weak self] in
            var frameSentForThisUtterance = false
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(120))
                guard let self else { return }
                switch self.live.state {
                case .reconnecting: if self.status != .reconnecting { self.status = .reconnecting }
                case .error(let message): if self.status != .error(message) { self.status = .error(message) }; return
                case .ready: if self.status == .reconnecting { self.status = .listening }
                default: break
                }
                // The user started talking → make sure the very latest
                // view is in the stream before VAD closes the turn.
                if self.live.userIsActive(within: 0.6) {
                    if !frameSentForThisUtterance {
                        frameSentForThisUtterance = true
                        self.sendCurrentFrame(reason: "user-speaking")
                    }
                    if self.status == .listening { self.status = .userSpeaking }
                } else {
                    frameSentForThisUtterance = false
                }
            }
        }
    }

    // MARK: Tools (model → app)

    static let toolDeclarations: [LiveClientMessage.FunctionDeclaration] = [
        .init(
            name: "set_watch_mode",
            description: "Turn continuous live monitoring of the camera on or off. Call with enabled=true ONLY when the user unmistakably asks you to keep watching over time and report changes (Arabic: راقب الشاشة، تابع الشاشة، راقب اللي قدامك، قول لي إذا تغير شي، نبهني لما يتغير الخيار). Do NOT call it for one-off requests such as 'look', 'what do you see', 'read this', 'خليني نشوف', 'وش تشوف' — answer those directly from the live video. Call with enabled=false when the user asks to stop (وقف المراقبة، كفاية، خلاص).",
            parameters: .init(
                type: "OBJECT",
                properties: [
                    "enabled": .init(type: "BOOLEAN", description: "true to start monitoring, false to stop."),
                    "focus": .init(type: "STRING", description: "'screen' for a computer/TV screen or menu, 'scene' for the real world, 'auto' to let the app decide.", enum: ["auto", "screen", "scene"])
                ],
                required: ["enabled"]
            )
        ),
        .init(
            name: "nothing_changed",
            description: "Call this instead of speaking when a [WATCH] message arrives and the newest video frames show nothing meaningfully different from what you last reported (or the change is unreadable). It keeps you silent; do not say anything before or after calling it.",
            parameters: nil
        )
    ]

    private func handleToolCall(_ call: GeminiLiveClient.FunctionCall) {
        switch call.name {
        case "set_watch_mode":
            let enabled = call.args["enabled"]?.boolValue ?? true
            let focus = WatchFocus(rawValue: call.args["focus"]?.stringValue ?? "auto") ?? .auto
            setWatching(enabled, focus: focus)
            let response: [String: JSONValue] = enabled
                ? ["status": .string("monitoring_started"), "focus": .string(focus.rawValue),
                   "note": .string("Confirm in one short sentence that you are now watching, then stay silent until a [WATCH] message or the user speaks.")]
                : ["status": .string("monitoring_stopped"), "note": .string("Confirm in one short sentence that you stopped watching.")]
            live.sendToolResponse(id: call.id, name: call.name, response: response)
        case "nothing_changed":
            quietPings += 1
            live.sendToolResponse(id: call.id, name: call.name, response: ["result": .string("ok"), "note": .string("Stay silent.")])
        default:
            live.sendToolResponse(id: call.id, name: call.name, response: ["error": .string("unknown function")])
        }
    }

    // MARK: Microphone → server

    func attachMicPipeline() {
        audio.setMicChunkHandler { [weak self] chunk in
            Task { @MainActor [weak self] in self?.handleMicChunk(chunk) }
        }
    }

    private var echoFloor: Float = 0.004
    private var loudStreak = 0
    private var bargeInHangover = 0

    private func handleMicChunk(_ chunk: MicChunk) {
        guard !isMicPaused, live.state == .ready else { return }
        let vocaIsTalking = live.modelIsSpeaking || audio.isPlayingAudio
        guard vocaIsTalking else {
            loudStreak = 0; bargeInHangover = 0
            live.sendAudioChunk(chunk.pcm)
            return
        }
        guard customization.bargeInEnabled else { return }
        if bargeInHangover > 0 {
            bargeInHangover -= 1
            live.sendAudioChunk(chunk.pcm)
            return
        }
        let isLoud = chunk.rms > max(echoFloor * 3.5, 0.012)
        if isLoud { loudStreak += 1 } else { loudStreak = 0; echoFloor = echoFloor * 0.95 + chunk.rms * 0.05 }
        if loudStreak >= 3 {
            bargeInHangover = 25
            live.sendAudioChunk(chunk.pcm)
        }
    }

    // MARK: Camera → server (live video)

    /// Frame spacing: the API caps video at 1 fps.
    private var frameInterval: TimeInterval { isWatching ? 1.0 : 2.0 }
    private var lastFrameSentAt: Date = .distantPast
    private var framesSent = 0
    private var framesSkipped = 0

    private func startVideoStream() {
        videoTask?.cancel()
        videoTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            while !Task.isCancelled {
                guard let self else { return }
                let wait = max(0.1, self.frameInterval - Date().timeIntervalSince(self.lastFrameSentAt))
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                guard !Task.isCancelled else { return }
                await self.streamFrame()
            }
        }
    }

    private func streamFrame() async {
        guard live.state == .ready else { return }
        guard let sample = await camera.captureFrameSample(maxDimension: 768, quality: 0.7) else { return }
        guard live.state == .ready else { return }
        if live.sendVideoFrame(sample.jpeg, skipIfBacklogged: true) {
            lastFrameSentAt = Date()
            framesSent += 1
            if framesSent == 1 || framesSent % 60 == 0 {
                vlog("session", "🎥 live video: \(framesSent) frames sent, \(framesSkipped) skipped (\(sample.jpeg.count / 1024) KB/frame)", level: .debug)
            }
        } else {
            framesSkipped += 1
            lastFrameSentAt = Date()
        }
    }

    /// One extra frame right now (the user started talking, a typed
    /// instruction); rate-limited so it never exceeds the API cap.
    private func sendCurrentFrame(reason: String) {
        guard live.state == .ready else { return }
        guard Date().timeIntervalSince(lastFrameSentAt) >= 0.6 else { return }
        lastFrameSentAt = Date()
        Task { [weak self] in
            guard let self, let sample = await self.camera.captureFrameSample(maxDimension: 768, quality: 0.7) else { return }
            self.live.sendVideoFrame(sample.jpeg)
            self.framesSent += 1
            vlog("session", "🖼 extra frame (\(reason))", level: .debug)
        }
    }

    // MARK: Watch loop (on-device triggers)

    private var lastPingAt: Date = .distantPast
    private var lastTurnCompletedAt: Date = .distantPast
    private var lastPlaybackEndedAt: Date = .distantPast
    private var pingInFlight = false
    private var pingSentAt: Date = .distantPast
    private var quietPings = 0
    private var wasPlaying = false
    private var isAnalyzing = false
    private var noScreenSamples = 0

    /// Idle cadence while watching: Google's reference agent pings every
    /// 2 s; we go a little slower and let the detectors ping instantly.
    private let idlePingInterval: TimeInterval = 3.0
    /// A ping that never completed (dropped tool call, lost turn) is
    /// abandoned after this, as in Google's reference agent.
    private let pingTimeout: TimeInterval = 10.0

    /// What the phone noticed; the model turns it into words.
    private enum WatchEvent {
        case view                                    // phone re-aimed and settled
        case change(SceneChangeDetector.SceneChange) // picture changed in place
        case highlight(crop: Data)                   // menu highlight moved
        case page(screen: Data)                      // screen shows a new page
        case idle                                    // periodic look
    }
    private var pendingEvent: WatchEvent?

    private func startWatchLoop() {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            var lastLoggedIntensity: MotionService.Intensity = .still
            var motionSettledAt: Date?
            var movedSinceLastView = false
            var lastViewAt: Date = .distantPast
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }

                let playing = self.audio.isPlayingAudio
                if self.wasPlaying && !playing { self.lastPlaybackEndedAt = Date() }
                self.wasPlaying = playing

                let intensity = self.motion.currentIntensity()
                if intensity != lastLoggedIntensity {
                    vlog("motion", "\(lastLoggedIntensity.description) → \(intensity.description)", level: .debug)
                    lastLoggedIntensity = intensity
                }
                let now = Date()
                guard self.isWatching else { continue }

                // Phone is being re-aimed: rebase detectors, remember to
                // describe the new view once it settles.
                if intensity == .moving || intensity == .sharp {
                    self.detector.reset()
                    self.screenWatcher.reset()
                    self.pendingEvent = nil
                    motionSettledAt = nil
                    movedSinceLastView = true
                    continue
                }
                if motionSettledAt == nil { motionSettledAt = now }
                guard now.timeIntervalSince(motionSettledAt!) >= 0.5 else { continue }

                if movedSinceLastView, now.timeIntervalSince(lastViewAt) >= 3 {
                    movedSinceLastView = false
                    lastViewAt = now
                    self.pendingEvent = .view
                    self.flushPendingEventIfPossible()
                    continue
                }

                // Nothing detected for a while → let the model look anyway.
                if self.pendingEvent == nil, now.timeIntervalSince(self.lastPingAt) >= self.idlePingInterval {
                    self.pendingEvent = .idle
                }
                self.flushPendingEventIfPossible()

                guard !self.isAnalyzing, let frame = self.camera.latestFrame() else { continue }
                let useScreen = self.watchFocus == .screen || (self.watchFocus == .auto && self.noScreenSamples < 10)
                self.isAnalyzing = true
                if useScreen {
                    let orientation = self.camera.bufferOrientation
                    Task { [weak self] in
                        guard let self else { return }
                        let update = await self.screenWatcher.process(frame, orientation: orientation)
                        self.noScreenSamples = self.screenWatcher.hasScreen ? 0 : self.noScreenSamples + 1
                        self.isAnalyzing = false
                        switch update {
                        case .highlight(let crop, _): self.pendingEvent = .highlight(crop: crop)
                        case .page(let screen): self.pendingEvent = .page(screen: screen)
                        case nil: break
                        }
                        self.flushPendingEventIfPossible()
                    }
                } else {
                    self.detector.analyze(frame) { [weak self] change in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            self.isAnalyzing = false
                            if let change, change.kind == .scene || change.changedFraction >= 0.05 {
                                self.pendingEvent = .change(change)
                            }
                            self.flushPendingEventIfPossible()
                        }
                    }
                }
            }
        }
    }

    /// Sends the pending ping when nobody is talking and the previous
    /// ping's turn has completed (a ping during generation would cancel
    /// it). Detector events carry their evidence as an extra frame.
    private func flushPendingEventIfPossible() {
        guard let event = pendingEvent else { return }
        guard live.state == .ready, !live.modelIsSpeaking, !audio.isPlayingAudio else { return }
        let now = Date()
        if pingInFlight {
            guard now.timeIntervalSince(pingSentAt) >= pingTimeout else { return }
            vlog("session", "⏱ ping unanswered for \(Int(pingTimeout)) s — continuing", level: .warning)
            pingInFlight = false
        }
        guard now.timeIntervalSince(lastPlaybackEndedAt) >= 0.4 else { return }
        guard !live.userIsActive(within: 1.2, of: now) else { return }
        guard now.timeIntervalSince(lastPingAt) >= 0.5 else { return }
        if case .idle = event, now.timeIntervalSince(lastPingAt) < idlePingInterval { return }
        pendingEvent = nil
        lastPingAt = now
        pingInFlight = true
        pingSentAt = now

        switch event {
        case .highlight(let crop):
            live.sendVideoFrame(crop)
            live.sendText("[WATCH] The last frame is a close-up of the menu row that just became highlighted. Say only that row's text, verbatim, exactly as written (English words stay English, codes as-is), nothing else. If it is unreadable, call nothing_changed.")
            vlog("session", "🎬 HIGHLIGHT ping (\(crop.count / 1024) KB)")
        case .page(let screen):
            live.sendVideoFrame(screen)
            live.sendText("[WATCH] The last frame is the whole screen after it changed to a new page. In ONE short sentence say what this page is (its title if visible) and, if a row is highlighted, read that row verbatim. Do not list rows.")
            vlog("session", "🎬 PAGE ping (\(screen.count / 1024) KB)")
        case .view:
            Task { [weak self] in
                guard let self else { return }
                if let sample = await self.camera.captureFrameSample(maxDimension: 768, quality: 0.72) {
                    self.live.sendVideoFrame(sample.jpeg); self.lastFrameSentAt = Date()
                }
                self.live.sendText("[WATCH] The camera was just pointed somewhere new; the newest frame is what it sees now. In one or two short sentences describe what is in front of the camera — the most useful things first (people, text, screens, obstacles). Only what is clearly visible; never guess.")
                vlog("session", "🎬 VIEW ping")
            }
        case .change(let change):
            let region: String
            switch (change.region.midX, change.region.midY) {
            case (let x, let y) where y < 0.33: region = x < 0.33 ? "top-left" : (x > 0.66 ? "top-right" : "top")
            case (let x, let y) where y > 0.66: region = x < 0.33 ? "bottom-left" : (x > 0.66 ? "bottom-right" : "bottom")
            case (let x, _): region = x < 0.33 ? "left" : (x > 0.66 ? "right" : "centre")
            }
            let percent = Int(change.changedFraction * 100)
            Task { [weak self] in
                guard let self else { return }
                if let sample = await self.camera.captureFrameSample(maxDimension: 768, quality: 0.72) {
                    self.live.sendVideoFrame(sample.jpeg); self.lastFrameSentAt = Date()
                }
                self.live.sendText("[WATCH] Something in the view changed a moment ago (about \(percent)% of the frame, \(region)). Compare the newest frame with the earlier ones and say in ONE short sentence only what is different now (a person, an object, a door, a cursor, a screen…). If you see no real difference, call nothing_changed.")
                vlog("session", "🎬 CHANGE ping \(percent)% \(region)")
            }
        case .idle:
            Task { [weak self] in
                guard let self else { return }
                if let sample = await self.camera.captureFrameSample(maxDimension: 768, quality: 0.7) {
                    self.live.sendVideoFrame(sample.jpeg); self.lastFrameSentAt = Date()
                }
                self.live.sendText("[WATCH] Look at the newest frames. If nothing meaningful changed since what you last said, call nothing_changed. If something did change (a highlighted row moved, the page changed, something or someone appeared), say only the change in ONE short sentence.")
                vlog("session", "🎬 idle ping (quiet so far: \(self.quietPings))", level: .debug)
            }
        }
    }
}
