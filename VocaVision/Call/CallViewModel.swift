import Foundation
import Observation
import UIKit

/// Owns the lifecycle of one Voca call: system call registration
/// (LiveCommunicationKit), audio engine, camera, motion, the Live API
/// session, and the orchestrator that ties them together.
///
/// Order matters: the system activates the audio session for us after
/// the conversation starts; only then do we start the engine, camera
/// and the Live session.
@Observable
@MainActor
final class CallViewModel {
    let camera = CameraService()
    let motion = MotionService()
    let audio = CallAudioEngine()
    let live = GeminiLiveClient()
    let callSession = CallSessionController()

    private let apiKeyStore: APIKeyStore
    private let customizationStore: CustomizationStore
    private(set) var orchestrator: SpeechFeedbackOrchestrator!

    private(set) var startupError: String?
    private(set) var isMicMuted = false
    private(set) var isOutputMuted = false
    private(set) var isPausedBySystem = false
    private(set) var callStartedAt: Date?
    private var hasStarted = false
    private var hasEnded = false

    var cameraPosition: CameraService.Position { camera.currentPosition }
    var isWatching: Bool { orchestrator?.isWatching ?? false }
    var status: SpeechFeedbackOrchestrator.Status { orchestrator?.status ?? .idle }
    var inputTranscript: String { orchestrator?.inputTranscript ?? "" }
    var interimInputTranscript: String { orchestrator?.interimInputTranscript ?? "" }
    var outputTranscript: String { orchestrator?.outputTranscript ?? "" }

    init(apiKeyStore: APIKeyStore, customizationStore: CustomizationStore) {
        self.apiKeyStore = apiKeyStore
        self.customizationStore = customizationStore
        self.orchestrator = SpeechFeedbackOrchestrator(
            camera: camera,
            motion: motion,
            audio: audio,
            live: live,
            customization: customizationStore,
            apiKey: { [weak apiKeyStore] in apiKeyStore?.currentKey() }
        )
    }

    // MARK: Start

    func startCallIfNeeded() async {
        guard !hasStarted else { return }
        hasStarted = true
        vlog("session", "📞 startCallIfNeeded")

        let auth = await Permissions.requestForCall()
        if !auth.cameraGranted {
            startupError = tr(
                ar: "إذن الكاميرا مقفل. افتح الإعدادات ثم VocaVision ثم الكاميرا، وشغّل الإذن.",
                en: "Camera access is off. Open Settings → VocaVision → Camera and turn it on."
            )
            return
        }
        if !auth.microphoneGranted {
            startupError = tr(
                ar: "إذن الميكروفون مقفل. افتح الإعدادات ثم VocaVision ثم الميكروفون، وشغّل الإذن.",
                en: "Microphone access is off. Open Settings → VocaVision → Microphone and turn it on."
            )
            return
        }

        wireSystemCallbacks()
        orchestrator.onSessionReady = { [weak self] in
            self?.callSession.reportConnected()
        }
        orchestrator.onWatchModeChanged = { enabled in
            announce(enabled
                     ? tr(ar: "وضع المراقبة شغّال: Voca تبلّغك لما يتغيّر شي فعلاً", en: "Watch mode on: Voca will tell you when something really changes")
                     : tr(ar: "وضع المراقبة متوقف", en: "Watch mode off"),
                     englishTokens: ["Voca"])
        }

        do {
            try await callSession.start(displayName: "Voca")
        } catch {
            vlog("session", "⚠️ system call unavailable (\(error.localizedDescription)) — running without it", level: .warning)
            // Fallback: manage the session ourselves.
            audio.managesSessionActivation = true
            await continueAfterAudioActivated()
        }
    }

    private func wireSystemCallbacks() {
        callSession.onAudioActivated = { [weak self] in
            Task { @MainActor [weak self] in await self?.continueAfterAudioActivated() }
        }
        callSession.onAudioDeactivated = { [weak self] in
            self?.handleSystemDeactivation()
        }
        callSession.onEndRequestedFromSystem = { [weak self] in
            self?.endCall()
        }
        callSession.onMuteRequestedFromSystem = { [weak self] muted in
            self?.setMicMuted(muted, announce: true, reportToSystem: false)
        }
        callSession.onPauseRequestedFromSystem = { [weak self] paused in
            self?.setPausedBySystem(paused)
        }
        audio.onMutedSpeechDetected = { [weak self] in
            guard let self, self.isMicMuted else { return }
            announce(tr(ar: "الميكروفون مكتوم", en: "Your microphone is muted"))
        }
    }

    /// Runs once the audio session is live (system-activated, or our
    /// own fallback activation).
    private func continueAfterAudioActivated() async {
        guard !hasEnded else { return }
        if audio.isRunning {
            // Re-activation after a system pause: just resume.
            setPausedBySystem(false)
            return
        }
        vlog("session", "▶️ audio activated — starting engine, camera, session")

        do {
            try audio.start()
        } catch {
            startupError = (error as? CallAudioEngine.AudioError)?.errorDescription
                ?? tr(ar: "تعذَّر تشغيل الصوت: \(error.localizedDescription)", en: "Couldn't start audio: \(error.localizedDescription)")
            vlog("session", "❌ audio start failed: \(error.localizedDescription)", level: .error)
            await callSession.end()
            return
        }

        do {
            try await camera.start(initialPosition: .back)
        } catch {
            startupError = userFacingMessage(for: error)
            vlog("session", "❌ camera start failed: \(error.localizedDescription)", level: .error)
            audio.stop()
            await callSession.end()
            return
        }

        motion.start()
        orchestrator.attachMicPipeline()
        orchestrator.start()
        callStartedAt = .now
        UIApplication.shared.isIdleTimerDisabled = true
        vlog("session", "✅ call fully active")
    }

    // MARK: End

    func endCall() {
        guard !hasEnded else { return }
        hasEnded = true
        vlog("session", "🛑 endCall")
        orchestrator.stop()
        camera.stop()
        motion.stop()
        audio.stop()
        UIApplication.shared.isIdleTimerDisabled = false
        Task { [callSession] in
            await callSession.end()
        }
    }

    private func handleSystemDeactivation() {
        // Another call took the session. Pause instead of tearing down:
        // the system re-activates us when the other call ends.
        guard !hasEnded else { return }
        setPausedBySystem(true)
    }

    private func setPausedBySystem(_ paused: Bool) {
        guard isPausedBySystem != paused else { return }
        isPausedBySystem = paused
        orchestrator.setMicPaused(paused || isMicMuted)
        if paused {
            audio.flushPlayback()
            audio.setOutputMuted(true)
            announce(tr(ar: "المكالمة متوقفة مؤقتاً", en: "Call paused"))
        } else {
            audio.setOutputMuted(isOutputMuted)
            announce(tr(ar: "استُؤنفت المكالمة", en: "Call resumed"))
        }
    }

    // MARK: Controls

    func toggleMicMute() {
        setMicMuted(!isMicMuted, announce: true, reportToSystem: true)
    }

    private func setMicMuted(_ muted: Bool, announce shouldAnnounce: Bool, reportToSystem: Bool) {
        guard isMicMuted != muted else { return }
        isMicMuted = muted
        audio.setMicMuted(muted)
        orchestrator.setMicPaused(muted || isPausedBySystem)
        if reportToSystem { callSession.reportMuted(muted) }
        if shouldAnnounce {
            announce(muted
                     ? tr(ar: "تمّ كتم الميكروفون", en: "Microphone muted")
                     : tr(ar: "تمّ إلغاء كتم الميكروفون", en: "Microphone unmuted"))
        }
    }

    func toggleOutputMute() {
        isOutputMuted.toggle()
        audio.setOutputMuted(isOutputMuted)
        announce(isOutputMuted
                 ? tr(ar: "تمّ كتم صوت Voca", en: "Voca's voice muted")
                 : tr(ar: "تمّ إلغاء كتم صوت Voca", en: "Voca's voice unmuted"),
                 englishTokens: ["Voca"])
    }

    func switchCamera() {
        Task {
            do {
                try await camera.switchCamera()
                announce(cameraPosition == .front
                         ? tr(ar: "تمّ التبديل إلى الكاميرا الأماميّة", en: "Switched to the front camera")
                         : tr(ar: "تمّ التبديل إلى الكاميرا الخلفيّة", en: "Switched to the back camera"))
            } catch {
                announce(tr(ar: "تعذَّر تبديل الكاميرا", en: "Couldn't switch the camera"))
            }
        }
    }

    func toggleWatchMode() {
        orchestrator.setWatching(!orchestrator.isWatching, focus: .auto)
    }

    /// Typed instruction (e.g. "اقرأ فقط الخيار المحدَّد") — no need to speak.
    func sendInstruction(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        orchestrator.sendInstruction(trimmed)
        announce(tr(ar: "أُرسلت التعليمات إلى Voca", en: "Instruction sent to Voca"), englishTokens: ["Voca"])
    }

    private func userFacingMessage(for error: Error) -> String {
        if let cameraError = error as? CameraService.CameraError {
            switch cameraError {
            case .notAuthorized:
                return tr(
                    ar: "إذن الكاميرا مقفل. افتح الإعدادات ثم VocaVision ثم الكاميرا، وشغّل الإذن.",
                    en: "Camera access is off. Open Settings → VocaVision → Camera and turn it on."
                )
            case .noDeviceAvailable:
                return tr(ar: "لم يُعثَر على كاميرا في هذا الجهاز.", en: "No camera was found on this device.")
            case .cannotAddInput, .cannotAddOutput:
                return tr(ar: "تعذّر تهيئة الكاميرا. حاول مرّةً أخرى.", en: "Couldn't set up the camera. Please try again.")
            }
        }
        return tr(ar: "تعذَّر بدء المكالمة: \(error.localizedDescription)", en: "Couldn't start the call: \(error.localizedDescription)")
    }
}
