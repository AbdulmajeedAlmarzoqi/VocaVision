import AVFAudio
import Foundation
import LiveCommunicationKit
import Observation
import UIKit

/// Registers the Voca conversation with the system through
/// **LiveCommunicationKit** — Apple's current API for VoIP-style calls
/// (iOS 17.4+, recommended over `CXProvider` since WWDC26).
///
/// What the system gives us in return:
///   * a call-priority audio session that it activates for us (we only
///     configure the category — never `setActive` — and start audio in
///     `didActivate`);
///   * the in-call indicator on the Dynamic Island / Lock Screen,
///     Voice Isolation in Control Center, AirPods/Bluetooth call
///     routing and mute gestures, proper handling against incoming
///     phone calls;
///   * system mute/end actions that we mirror in the app.
///
/// Outgoing only — there is no remote party, so no incoming-call UI
/// and no PushKit.
@MainActor
@Observable
final class CallSessionController {
    enum Status: Equatable {
        case idle
        case starting
        case active
        case ended
    }

    private(set) var status: Status = .idle

    /// The system activated our audio session — start the engine now.
    @ObservationIgnored var onAudioActivated: (() -> Void)?
    /// The system took the session away (another call won).
    @ObservationIgnored var onAudioDeactivated: (() -> Void)?
    /// The user ended the call from the system UI.
    @ObservationIgnored var onEndRequestedFromSystem: (() -> Void)?
    /// The user toggled mute from the system UI / AirPods.
    @ObservationIgnored var onMuteRequestedFromSystem: ((Bool) -> Void)?
    /// The system paused / resumed us (hold from another call).
    @ObservationIgnored var onPauseRequestedFromSystem: ((Bool) -> Void)?

    @ObservationIgnored nonisolated(unsafe) private let manager: ConversationManager
    @ObservationIgnored private(set) var conversationUUID: UUID?
    @ObservationIgnored private var didReportConnected = false

    init() {
        var configuration = ConversationManager.Configuration(
            ringtoneName: nil,
            iconTemplateImageData: UIImage(systemName: "eye.fill")?
                .withRenderingMode(.alwaysTemplate).pngData(),
            maximumConversationGroups: 1,
            maximumConversationsPerConversationGroup: 1,
            includesConversationInRecents: false,
            supportsVideo: false,
            supportedHandleTypes: [.generic]
        )
        configuration.supportsAudioTranslation = false
        manager = ConversationManager(configuration: configuration)
        manager.delegate = self
    }

    // MARK: Control

    /// Asks the system to start the conversation. Returns once the
    /// start action was accepted; audio starts when `onAudioActivated`
    /// fires.
    func start(displayName: String) async throws {
        let uuid = UUID()
        conversationUUID = uuid
        didReportConnected = false
        status = .starting
        let handle = Handle(type: .generic, value: "voca", displayName: displayName)
        let action = StartConversationAction(conversationUUID: uuid, handles: [handle], isVideo: false)
        try await manager.perform([action])
        vlog("call", "▶️ conversation requested (\(uuid.uuidString.prefix(8)))")
    }

    /// Marks the conversation as connected in the system UI (timer
    /// starts) once the Live session is actually ready.
    func reportConnected() {
        guard !didReportConnected, let uuid = conversationUUID,
              let conversation = manager.conversations.first(where: { $0.uuid == uuid }) else { return }
        didReportConnected = true
        manager.reportConversationEvent(.conversationConnected(.now), for: conversation)
        vlog("call", "✅ reported connected")
    }

    func end() async {
        guard let uuid = conversationUUID else {
            status = .ended
            return
        }
        conversationUUID = nil
        do {
            try await manager.perform([EndConversationAction(conversationUUID: uuid)])
        } catch {
            vlog("call", "⚠️ end action failed: \(error.localizedDescription)", level: .warning)
            if let conversation = manager.conversations.first(where: { $0.uuid == uuid }) {
                manager.reportConversationEvent(.conversationEnded(.now, .failed), for: conversation)
            }
        }
        status = .ended
    }

    /// Reflects an in-app mute toggle in the system call UI.
    func reportMuted(_ muted: Bool) {
        guard let uuid = conversationUUID else { return }
        Task {
            try? await manager.perform([MuteConversationAction(conversationUUID: uuid, isMuted: muted)])
        }
    }
}

// MARK: - ConversationManagerDelegate

extension CallSessionController: ConversationManagerDelegate {
    nonisolated func conversationManagerDidBegin(_ manager: ConversationManager) {
        vlog("call", "🟢 manager began")
    }

    nonisolated func conversationManagerDidReset(_ manager: ConversationManager) {
        vlog("call", "🔄 manager reset", level: .warning)
        Task { @MainActor [weak self] in
            self?.conversationUUID = nil
            self?.status = .idle
            self?.onAudioDeactivated?()
        }
    }

    nonisolated func conversationManager(_ manager: ConversationManager, conversationChanged conversation: Conversation) {
        vlog("call", "ℹ️ conversation state: \(String(describing: conversation.state))", level: .debug)
    }

    nonisolated func conversationManager(_ manager: ConversationManager, perform action: ConversationAction) {
        switch action {
        case let start as StartConversationAction:
            // Configure the session category here; the system activates
            // it (call priority) and tells us via didActivate.
            do {
                try CallAudioEngine.configureSession()
                vlog("call", "🎚 audio session configured for the call")
            } catch {
                vlog("call", "❌ session configure failed: \(error.localizedDescription)", level: .error)
            }
            if let conversation = manager.conversations.first(where: { $0.uuid == start.conversationUUID }) {
                manager.reportConversationEvent(.conversationStartedConnecting(.now), for: conversation)
            }
            start.fulfill(dateStarted: .now)
            Task { @MainActor [weak self] in
                self?.status = .active
                vlog("call", "✅ start action fulfilled")
            }

        case let end as EndConversationAction:
            end.fulfill(dateEnded: .now)
            let endedUUID = end.conversationUUID
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOurs = self.conversationUUID == endedUUID
                self.conversationUUID = nil
                self.status = .ended
                vlog("call", "🛑 end action fulfilled (\(wasOurs ? "system/user" : "already ended"))")
                if wasOurs { self.onEndRequestedFromSystem?() }
            }

        case let mute as MuteConversationAction:
            mute.fulfill()
            let muted = mute.isMuted
            Task { @MainActor [weak self] in
                vlog("call", muted ? "🔇 system muted" : "🎙 system unmuted")
                self?.onMuteRequestedFromSystem?(muted)
            }

        case let pause as PauseConversationAction:
            pause.fulfill()
            let paused = pause.isPaused
            Task { @MainActor [weak self] in
                vlog("call", paused ? "⏸ system paused" : "▶️ system resumed")
                self?.onPauseRequestedFromSystem?(paused)
            }

        default:
            vlog("call", "⚠️ unsupported action \(type(of: action)) — failing", level: .warning)
            action.fail()
        }
    }

    nonisolated func conversationManager(_ manager: ConversationManager, timedOutPerforming action: ConversationAction) {
        vlog("call", "⏰ action timed out: \(type(of: action))", level: .warning)
    }

    nonisolated func conversationManager(_ manager: ConversationManager, didActivate audioSession: AVAudioSession) {
        vlog("call", "🎧 audio session activated by system")
        Task { @MainActor [weak self] in self?.onAudioActivated?() }
    }

    nonisolated func conversationManager(_ manager: ConversationManager, didDeactivate audioSession: AVAudioSession) {
        vlog("call", "🔇 audio session deactivated by system", level: .warning)
        Task { @MainActor [weak self] in self?.onAudioDeactivated?() }
    }
}
