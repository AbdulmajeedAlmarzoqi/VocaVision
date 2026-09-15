@preconcurrency import CoreMotion
import Foundation
import Synchronization

/// Continuous motion signal from the IMU, classified into four
/// intensities from both linear acceleration and rotation rate — a slow
/// pan produces almost no acceleration, so the gyroscope is essential
/// for detecting "the user stopped moving the camera".
nonisolated final class MotionService: Sendable {
    enum Intensity: Int, Sendable {
        case still = 0
        case subtle = 1
        case moving = 2
        case sharp = 3

        var description: String {
            switch self {
            case .still: return "still"
            case .subtle: return "small movement"
            case .moving: return "moving"
            case .sharp: return "fast movement"
            }
        }
    }

    private struct Sample: Sendable {
        var accel: Double = 0
        var rotation: Double = 0
    }

    nonisolated(unsafe) private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private let latest = Mutex<Sample>(Sample())

    init() {
        queue.name = "com.vocavision.motion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
    }

    deinit {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self else { return }
            guard let motion else { return }
            let acc = motion.userAcceleration
            let rot = motion.rotationRate
            let sample = Sample(
                accel: (acc.x * acc.x + acc.y * acc.y + acc.z * acc.z).squareRoot(),
                rotation: (rot.x * rot.x + rot.y * rot.y + rot.z * rot.z).squareRoot()
            )
            self.latest.withLock { $0 = sample }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    func currentIntensity() -> Intensity {
        let sample = latest.withLock { $0 }
        return Self.classify(accel: sample.accel, rotation: sample.rotation)
    }

    /// Thresholds tuned against hand-held recordings (m/s², rad/s).
    private static func classify(accel: Double, rotation: Double) -> Intensity {
        let accelClass: Intensity
        switch accel {
        case ..<0.04: accelClass = .still
        case ..<0.18: accelClass = .subtle
        case ..<0.6: accelClass = .moving
        default: accelClass = .sharp
        }
        let rotClass: Intensity
        switch rotation {
        case ..<0.10: rotClass = .still
        case ..<0.40: rotClass = .subtle
        case ..<1.30: rotClass = .moving
        default: rotClass = .sharp
        }
        return accelClass.rawValue >= rotClass.rawValue ? accelClass : rotClass
    }
}
