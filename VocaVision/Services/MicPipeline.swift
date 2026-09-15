import Accelerate
import AVFoundation
import Foundation
import Synchronization

/// One captured microphone chunk, ready for the wire.
struct MicChunk: Sendable {
    /// 16 kHz, 16-bit, mono, little-endian PCM.
    let pcm: Data
    /// RMS level in 0…1 (linear) — used by the local echo guard.
    let rms: Float
    /// Peak absolute sample in 0…1.
    let peak: Float
}

/// Runs on the input-tap thread only. Converts whatever format the
/// voice-processing input unit produces (usually 24 kHz or 48 kHz mono
/// Float32) into fixed-size 16 kHz Int16 chunks, and measures the level
/// of each chunk so the orchestrator can tell real speech from residual
/// speaker echo.
///
/// The tap thread is the single caller of `process`; `reset` is only
/// called while no tap is installed. Everything else is atomic.
nonisolated final class MicPipeline: @unchecked Sendable {
    let targetFormat: AVAudioFormat
    let chunkBytes: Int

    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?
    private var pending = Data()
    private var scratch: [Float] = []

    private let muted = Atomic<Bool>(false)
    /// Plain lock + property on purpose: storing a closure inside
    /// `Mutex`/`withLock` re-wraps it in a reabstraction thunk on every
    /// inout write-back, and 25 reads per second grew that chain until
    /// the audio thread overflowed its stack.
    private let handlerLock = NSLock()
    nonisolated(unsafe) private var handlerBlock: (@Sendable (MicChunk) -> Void)?

    /// Diagnostics counters (tap thread only).
    private(set) var buffersSeen = 0
    private(set) var chunksEmitted = 0

    init(targetSampleRate: Double = 16_000, chunkMilliseconds: Int = 40) {
        targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: true
        )!
        chunkBytes = Int(targetSampleRate) * chunkMilliseconds / 1000 * MemoryLayout<Int16>.size
    }

    var isMuted: Bool {
        get { muted.load(ordering: .relaxed) }
        set { muted.store(newValue, ordering: .relaxed) }
    }

    func setHandler(_ block: (@Sendable (MicChunk) -> Void)?) {
        handlerLock.lock()
        handlerBlock = block
        handlerLock.unlock()
    }

    func reset() {
        converter = nil
        converterInputFormat = nil
        pending.removeAll(keepingCapacity: true)
        buffersSeen = 0
        chunksEmitted = 0
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        buffersSeen += 1
        let inputFrames = Int(buffer.frameLength)
        if buffersSeen <= 3 || buffersSeen % 250 == 0 {
            vlog("audio", "🎤 tap buffer #\(buffersSeen) frames=\(inputFrames) fmt=\(Int(buffer.format.sampleRate)) Hz/\(buffer.format.channelCount) ch",
                 level: inputFrames == 0 ? .warning : .debug)
        }
        guard inputFrames > 0 else { return }
        if isMuted {
            // Keep the converter primed but emit nothing — the voice
            // processing unit is already sending silence upstream.
            pending.removeAll(keepingCapacity: true)
            return
        }

        if converter == nil || converterInputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
            converterInputFormat = buffer.format
            pending.removeAll(keepingCapacity: true)
            vlog("audio", "🎛 mic converter: \(Int(buffer.format.sampleRate)) Hz/\(buffer.format.channelCount) ch → 16 kHz Int16 mono")
        }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(inputFrames) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil, out.frameLength > 0,
              let int16 = out.int16ChannelData?[0] else {
            if let error {
                vlog("audio", "❌ mic converter failed: \(error.localizedDescription)", level: .error)
            }
            return
        }

        pending.append(UnsafeBufferPointer(start: int16, count: Int(out.frameLength)))

        while pending.count >= chunkBytes {
            let chunk = pending.prefix(chunkBytes)
            pending.removeFirst(chunkBytes)
            emit(Data(chunk))
        }
    }

    private func emit(_ data: Data) {
        let frameCount = data.count / MemoryLayout<Int16>.size
        if scratch.count < frameCount { scratch = [Float](repeating: 0, count: frameCount) }

        var rms: Float = 0
        var peak: Float = 0
        data.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Int16.self).baseAddress else { return }
            scratch.withUnsafeMutableBufferPointer { dst in
                vDSP_vflt16(src, 1, dst.baseAddress!, 1, vDSP_Length(frameCount))
                var scale = Float(1.0 / 32768.0)
                vDSP_vsmul(dst.baseAddress!, 1, &scale, dst.baseAddress!, 1, vDSP_Length(frameCount))
                vDSP_rmsqv(dst.baseAddress!, 1, &rms, vDSP_Length(frameCount))
                vDSP_maxmgv(dst.baseAddress!, 1, &peak, vDSP_Length(frameCount))
            }
        }

        chunksEmitted += 1
        if chunksEmitted == 1 {
            vlog("audio", "🎙 first mic chunk (\(data.count) B, rms=\(String(format: "%.3f", rms)))")
        } else if chunksEmitted % 250 == 0 {
            vlog("audio", "🎙 mic alive — \(chunksEmitted) chunks", level: .debug)
        }

        handlerLock.lock()
        let block = handlerBlock
        handlerLock.unlock()
        block?(MicChunk(pcm: data, rms: rms, peak: peak))
    }
}
