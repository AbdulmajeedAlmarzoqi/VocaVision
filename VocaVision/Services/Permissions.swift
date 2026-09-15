import AVFoundation
import Foundation

/// System permission prompts the call screen needs.
enum Permissions {
    struct CallAuthorization: Sendable {
        let cameraGranted: Bool
        let microphoneGranted: Bool
        var allGranted: Bool { cameraGranted && microphoneGranted }
    }

    /// Camera + microphone, requested in parallel.
    static func requestForCall() async -> CallAuthorization {
        vlog("perm", "▶️ requesting camera + microphone")
        async let camera = requestCamera()
        async let mic = requestMicrophone()
        let result = CallAuthorization(cameraGranted: await camera, microphoneGranted: await mic)
        vlog("perm", "📋 camera=\(result.cameraGranted) mic=\(result.microphoneGranted)",
             level: result.allGranted ? .info : .warning)
        return result
    }

    nonisolated static func requestCamera() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    nonisolated static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        case .undetermined: return await AVAudioApplication.requestRecordPermission()
        @unknown default: return false
        }
    }
}
