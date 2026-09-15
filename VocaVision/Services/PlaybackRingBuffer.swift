import Foundation
import Synchronization

/// Lock-free single-producer / single-consumer ring buffer of Float32
/// PCM samples that feeds the real-time render thread of an
/// `AVAudioSourceNode`.
///
/// Why this exists: scheduling each network chunk on an
/// `AVAudioPlayerNode` as it arrives makes playback hostage to network
/// jitter — every late packet becomes an audible gap ("تقطيع"). Here the
/// network side simply *writes* samples as they arrive (often far
/// faster than real time), and the audio thread *pulls* a steady stream
/// at exactly the hardware cadence. A small pre-roll absorbs jitter, an
/// underrun produces silence instead of a glitch, and a flush drops
/// everything the moment the user interrupts the model.
///
/// Concurrency contract:
///   * Exactly **one** producer calls `write`, `markEndOfBurst`, and
///     `flush` (any thread, but never concurrently with itself).
///   * Exactly **one** consumer calls `render` (the audio render thread).
///   * Everything is plain atomics — no locks, no allocation, no ObjC
///     messaging on the render thread.
nonisolated final class PlaybackRingBuffer: @unchecked Sendable {
    let capacity: Int
    let sampleRate: Double

    private let storage: UnsafeMutablePointer<Float>

    /// Monotonic write position (producer-owned).
    private let head = Atomic<Int>(0)
    /// Monotonic read position (consumer-owned).
    private let tail = Atomic<Int>(0)

    /// Flush protocol — the producer bumps `flushGeneration` after
    /// recording `flushMark = head`; the consumer drops everything
    /// written before the mark on its next render.
    private let flushGeneration = Atomic<Int>(0)
    private let flushMark = Atomic<Int>(0)
    private var lastSeenFlushGeneration = 0          // consumer-only

    /// Producer sets this when the server says the burst is over so the
    /// consumer plays out the tail even if it is below the pre-roll.
    private let endOfBurst = Atomic<Bool>(false)

    /// Frames that must be buffered before playback starts (or
    /// restarts after an underrun). Tunable from the producer side.
    private let primeThresholdFrames: Atomic<Int>

    /// Consumer-only state: are we currently streaming out?
    private var isPrimed = false

    /// Frames handed to the hardware since the last flush — lets the
    /// producer side know audio is actually being *heard*.
    private let framesRendered = Atomic<Int>(0)

    init(sampleRate: Double, seconds: Double, primeMilliseconds: Int) {
        self.sampleRate = sampleRate
        self.capacity = Int(sampleRate * seconds)
        self.storage = .allocate(capacity: capacity)
        self.storage.initialize(repeating: 0, count: capacity)
        self.primeThresholdFrames = Atomic(Int(sampleRate * Double(primeMilliseconds) / 1000))
    }

    deinit {
        storage.deallocate()
    }

    // MARK: Producer side

    /// Number of frames waiting to be played.
    var bufferedFrames: Int {
        max(0, head.load(ordering: .acquiring) - tail.load(ordering: .acquiring))
    }

    /// Seconds of audio queued but not yet rendered.
    var bufferedSeconds: Double {
        Double(bufferedFrames) / sampleRate
    }

    var isEmpty: Bool { bufferedFrames == 0 }

    var totalFramesRendered: Int {
        framesRendered.load(ordering: .relaxed)
    }

    func setPrimeThreshold(milliseconds: Int) {
        primeThresholdFrames.store(Int(sampleRate * Double(milliseconds) / 1000), ordering: .relaxed)
    }

    /// Appends samples. Returns the number of frames actually written;
    /// anything that does not fit is dropped (the buffer holds tens of
    /// seconds, so this only happens if the server floods us).
    @discardableResult
    func write(_ samples: UnsafeBufferPointer<Float>) -> Int {
        guard let base = samples.baseAddress, samples.count > 0 else { return 0 }
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        let space = capacity - (h - t)
        let n = min(samples.count, space)
        guard n > 0 else { return 0 }

        let start = h % capacity
        let firstRun = min(n, capacity - start)
        (storage + start).update(from: base, count: firstRun)
        if n > firstRun {
            storage.update(from: base + firstRun, count: n - firstRun)
        }
        endOfBurst.store(false, ordering: .relaxed)
        head.store(h + n, ordering: .releasing)
        return n
    }

    /// The server finished this reply — let the consumer drain whatever
    /// is left even if it is shorter than the pre-roll.
    func markEndOfBurst() {
        endOfBurst.store(true, ordering: .releasing)
    }

    /// Drops every queued sample (user interrupted the model). Samples
    /// written *after* this call are kept.
    func flush() {
        flushMark.store(head.load(ordering: .relaxed), ordering: .relaxed)
        flushGeneration.wrappingAdd(1, ordering: .releasing)
        endOfBurst.store(false, ordering: .relaxed)
    }

    // MARK: Consumer side (render thread only)

    /// Fills `out` with up to `frameCount` frames. Returns `true` when
    /// real audio was written, `false` when the block is pure silence.
    func render(into out: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        // 1. Honour a pending flush.
        let gen = flushGeneration.load(ordering: .acquiring)
        if gen != lastSeenFlushGeneration {
            lastSeenFlushGeneration = gen
            let mark = flushMark.load(ordering: .relaxed)
            let t = tail.load(ordering: .relaxed)
            if mark > t { tail.store(mark, ordering: .releasing) }
            isPrimed = false
        }

        let h = head.load(ordering: .acquiring)
        let t = tail.load(ordering: .relaxed)
        let available = h - t

        // 2. Pre-roll: wait for enough audio unless the burst is over.
        if !isPrimed {
            let threshold = primeThresholdFrames.load(ordering: .relaxed)
            let burstDone = endOfBurst.load(ordering: .acquiring)
            if available >= threshold || (burstDone && available > 0) {
                isPrimed = true
            } else {
                out.update(repeating: 0, count: frameCount)
                return false
            }
        }

        // 3. Stream out; underrun → silence and re-prime.
        let n = min(frameCount, available)
        if n > 0 {
            let start = t % capacity
            let firstRun = min(n, capacity - start)
            out.update(from: storage + start, count: firstRun)
            if n > firstRun {
                (out + firstRun).update(from: storage, count: n - firstRun)
            }
            tail.store(t + n, ordering: .releasing)
            framesRendered.wrappingAdd(n, ordering: .relaxed)
        }
        if n < frameCount {
            (out + n).update(repeating: 0, count: frameCount - n)
            if n == 0 || !endOfBurst.load(ordering: .relaxed) {
                // Ran dry mid-burst: rebuffer before continuing so we
                // don't stutter sample-by-sample on a bad connection.
                isPrimed = false
            }
        }
        return n > 0
    }
}
