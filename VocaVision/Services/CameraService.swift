@preconcurrency import AVFoundation
import CoreImage
import Foundation
import Synchronization
import UIKit

/// Wraps `AVCaptureSession`: live preview for SwiftUI, the latest frame
/// as a JPEG + perceptual fingerprint for the model, and front/back
/// switching. All AVFoundation work happens on a private serial queue;
/// frame sampling (Core Image) runs off the main actor as well.
nonisolated final class CameraService: NSObject, @unchecked Sendable {
    enum Position: Sendable {
        case back, front
        var avPosition: AVCaptureDevice.Position { self == .back ? .back : .front }
    }

    enum CameraError: Error {
        case noDeviceAvailable
        case cannotAddInput
        case cannotAddOutput
        case notAuthorized
    }

    /// 256-bit average hash of a downscaled grayscale frame.
    struct Fingerprint: Equatable, Sendable {
        let words: [UInt64]
        func hammingDistance(to other: Fingerprint) -> Int {
            guard words.count == other.words.count else { return Int.max }
            return zip(words, other.words).reduce(0) { $0 + ($1.0 ^ $1.1).nonzeroBitCount }
        }
    }

    struct FrameSample: Sendable {
        let jpeg: Data
        let fingerprint: Fingerprint
    }

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.vocavision.camera.session")
    private let sampleQueue = DispatchQueue(label: "com.vocavision.camera.samples")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private let position = Mutex<Position>(.back)
    private let pixelLock = NSLock()
    nonisolated(unsafe) private var latestPixelBuffer: CVPixelBuffer?
    private let currentInput = Mutex<AVCaptureDeviceInput?>(nil)

    var currentPosition: Position { position.withLock { $0 } }

    /// Most recent frame, for on-device analysis. Cheap: no copy.
    func latestFrame() -> CVPixelBuffer? {
        pixelLock.withLock { latestPixelBuffer }
    }

    /// How a raw buffer must be rotated to be upright. The output
    /// connection rotates to portrait when the hardware supports it;
    /// otherwise buffers arrive landscape and need a 90° turn.
    var bufferOrientation: CGImagePropertyOrientation {
        buffersArePortrait.withLock { $0 } ? .up : .right
    }
    private let buffersArePortrait = Mutex<Bool>(false)
    private let loggedDimensions = Mutex<Bool>(false)

    deinit {
        if session.isRunning { session.stopRunning() }
    }

    // MARK: Lifecycle

    func start(initialPosition: Position) async throws {
        vlog("camera", "▶️ start(\(initialPosition == .back ? "back" : "front"))")
        guard await Permissions.requestCamera() else {
            throw CameraError.notAuthorized
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureSessionIfNeeded(position: initialPosition)
                    if !self.session.isRunning { self.session.startRunning() }
                    vlog("camera", "✅ capture session running")
                    if let device = self.currentInput.withLock({ $0 })?.device { self.configureForReading(device) }
                    continuation.resume()
                } catch {
                    vlog("camera", "❌ session config failed: \(error.localizedDescription)", level: .error)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func switchCamera() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                let target: Position = (self.currentPosition == .back) ? .front : .back
                do {
                    try self.replaceInput(with: target)
                    self.position.withLock { $0 = target }
                    if let device = self.currentInput.withLock({ $0 })?.device { self.configureForReading(device) }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: Frames

    /// Latest frame as JPEG (≤ `maxDimension` px) plus its fingerprint.
    /// Runs Core Image work on the sample queue, never on the caller.
    func captureFrameSample(maxDimension: CGFloat = 768, quality: CGFloat = 0.7) async -> FrameSample? {
        await withCheckedContinuation { continuation in
            sampleQueue.async {
                continuation.resume(returning: self.makeFrameSample(maxDimension: maxDimension, quality: quality))
            }
        }
    }

    private func makeFrameSample(maxDimension: CGFloat, quality: CGFloat) -> FrameSample? {
        let buffer: CVPixelBuffer? = pixelLock.withLock { latestPixelBuffer }
        guard let buffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let fingerprint = computeFingerprint(from: ciImage)

        let extent = ciImage.extent
        let scale = min(1, maxDimension / max(extent.width, extent.height))
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let portrait = buffersArePortrait.withLock { $0 }
        let orientation: CGImagePropertyOrientation = portrait ? .up : (currentPosition == .front ? .leftMirrored : .right)
        let oriented = scaled.oriented(orientation)
        guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else { return nil }
        guard let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: quality) else { return nil }
        return FrameSample(jpeg: jpeg, fingerprint: fingerprint)
    }

    private func computeFingerprint(from ciImage: CIImage) -> Fingerprint {
        let extent = ciImage.extent
        let scale = 16 / max(extent.width, extent.height)
        let downscaled = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .applyingFilter("CIPhotoEffectMono")

        var pixels = [UInt8](repeating: 0, count: 256)
        let bounds = CGRect(x: downscaled.extent.minX, y: downscaled.extent.minY, width: 16, height: 16)
        ciContext.render(downscaled, toBitmap: &pixels, rowBytes: 16, bounds: bounds,
                         format: .L8, colorSpace: CGColorSpaceCreateDeviceGray())

        let avg = UInt8(pixels.reduce(0) { $0 + Int($1) } / pixels.count)
        var words = [UInt64](repeating: 0, count: 4)
        for (i, pixel) in pixels.enumerated() where pixel > avg {
            words[i / 64] |= UInt64(1) << UInt64(i % 64)
        }
        return Fingerprint(words: words)
    }

    // MARK: Session configuration (session queue)

    private func configureSessionIfNeeded(position: Position) throws {
        if currentInput.withLock({ $0 }) != nil { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 1080p: screen text needs the extra resolution for OCR; the
        // change detector downsamples anyway and JPEGs are capped at 1024.
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
        } else if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        }
        try addInput(for: position)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        // Bi-planar YUV: the Y plane is a ready-made grayscale image for
        // the change detector, and Core Image reads it directly for JPEGs.
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.setSampleBufferDelegate(self, queue: sampleQueue)
        guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
        session.addOutput(videoOutput)
        applyRotation()
        self.position.withLock { $0 = position }
    }

    private func addInput(for position: Position) throws {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position.avPosition)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CameraError.noDeviceAvailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        input.unifiedAutoExposureDefaultsEnabled = true
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)
        currentInput.withLock { $0 = input }
    }

    private func replaceInput(with position: Position) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let input = currentInput.withLock({ $0 }) {
            session.removeInput(input)
            currentInput.withLock { $0 = nil }
        }
        try addInput(for: position)
        applyRotation()
        if let connection = videoOutput.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (position == .front)
        }
    }

    /// Tunes the device for reading screens and documents at arm's
    /// length (evidence-based settings, see research notes):
    ///   * near focus range, fast (non-smooth) AF, no face-driven AF so a
    ///     reflection in the screen cannot steal focus;
    ///   * exposure duration locked at 1/60 s with automatic ISO — an
    ///     integer multiple of a 60 Hz panel's refresh, which removes
    ///     rolling-shutter flicker bands, plus a negative bias so a bright
    ///     display does not clip;
    ///   * video HDR off and global tone mapping on, so pixel values stay
    ///     stable frame to frame for the change detector.
    private func configureForReading(_ device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }
            if device.isSmoothAutoFocusSupported { device.isSmoothAutoFocusEnabled = false }
            device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            device.isFaceDrivenAutoFocusEnabled = false
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }

            device.automaticallyAdjustsVideoHDREnabled = false
            if device.activeFormat.isVideoHDRSupported { device.isVideoHDREnabled = false }
            if device.activeFormat.isGlobalToneMappingSupported { device.isGlobalToneMappingEnabled = true }

            // Auto exposure, but never longer than 1/60 s (a 60 Hz panel's
            // refresh period) so rolling-shutter bands stay small, and a
            // negative bias so a bright display does not clip. Custom
            // exposure is deliberately avoided: it throws an ObjC
            // exception on some format/device combinations.
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            let sixtieth = CMTime(value: 1, timescale: 60)
            if CMTimeCompare(device.activeFormat.minExposureDuration, sixtieth) <= 0,
               CMTimeCompare(device.activeFormat.maxExposureDuration, sixtieth) >= 0 {
                device.activeMaxExposureDuration = sixtieth
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.setExposureTargetBias(max(-1.0, device.minExposureTargetBias), completionHandler: nil)

            device.isSubjectAreaChangeMonitoringEnabled = true
        } catch {
            vlog("camera", "⚠️ device configuration failed: \(error.localizedDescription)", level: .warning)
        }
    }

    /// Optical-quality zoom (never past the sensor's upscale threshold).
    /// Used in screen-watch mode so menu text gets more pixels.
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async {
            guard let device = self.currentInput.withLock({ $0 })?.device else { return }
            let limit = min(device.activeFormat.videoZoomFactorUpscaleThreshold, device.activeFormat.videoMaxZoomFactor)
            let target = min(max(1, factor), max(1, limit))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: target, withRate: 4)
                device.unlockForConfiguration()
                vlog("camera", "🔍 zoom → \(String(format: "%.2f", target))×")
            } catch {
                vlog("camera", "⚠️ zoom failed: \(error.localizedDescription)", level: .warning)
            }
        }
    }

    /// Portrait capture: the app runs portrait-only on iPhone, and the
    /// frames we send are re-oriented in `makeFrameSample`.
    private func applyRotation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        let angle: CGFloat = 90
        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}

nonisolated extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        buffersArePortrait.withLock { $0 = h > w }
        if !loggedDimensions.withLock({ let was = $0; $0 = true; return was }) {
            vlog("camera", "🧭 buffers \(w)×\(h) (\(h > w ? "portrait" : "landscape"))")
        }
        pixelLock.withLock { latestPixelBuffer = buffer }
    }
}
