import Accelerate
import CoreVideo
import Foundation
import Synchronization

/// On-device "did the scene really change?" detector.
///
/// Runs entirely on the phone at a few frames per second and decides
/// whether — and where — the picture in front of the camera changed,
/// so the model is only ever asked about *real* changes. Designed for
/// two situations a blind user cares about:
///
///   * a screen (BIOS / menu / document) where a highlight or a window
///     changes while the phone is held still;
///   * a real scene where a person or object appears, leaves, or moves.
///
/// The algorithm (all Accelerate, no allocation per frame):
///   1. Take the luma (Y) plane and downscale it to a 64×36 thumbnail.
///   2. Normalise brightness (zero mean / unit variance) so auto-exposure
///      and lighting flicker cancel out.
///   3. Compare with the *reference* thumbnail at ±2 px shifts and keep
///      the best-aligned difference — cancels hand jitter without any
///      registration pass.
///   4. Split the aligned difference into a 16×9 grid; a cell "changed"
///      when its mean absolute difference exceeds an adaptive noise
///      floor learned from static frames (temporal noise estimate).
///   5. Hysteresis: a change must persist and *settle* (two consecutive
///      samples agree) before an event fires, then the current frame
///      becomes the new reference. Transitions and flicker never fire.
///
/// Output: a `SceneChange` with the fraction of the frame that changed,
/// its bounding region and a coarse classification, or nothing.
nonisolated final class SceneChangeDetector: @unchecked Sendable {
    struct SceneChange: Sendable {
        enum Kind: String, Sendable {
            case scene      // most of the frame changed (new view, new window)
            case region     // a localised change (highlight moved, object appeared)
        }
        let kind: Kind
        /// 0…1 fraction of grid cells that changed.
        let changedFraction: Double
        /// Normalised (0…1, origin top-left) bounding box of the change.
        let region: CGRect
        /// Vertical position of the change centre, 0 (top) … 1 (bottom).
        var verticalCenter: Double { region.midY }
        let timestamp: Date
    }

    // Thumbnail + grid geometry.
    private let thumbWidth = 64
    private let thumbHeight = 36
    private let gridColumns = 16
    private let gridRows = 9
    private let maxShift = 2

    // Tunables (8-bit gray levels).
    /// Minimum absolute cell difference to count as a change.
    private let minimumCellDelta: Float = 14
    /// Multiplier over the learned noise floor.
    private let noiseMultiplier: Float = 3.5
    /// Cells changed (fraction) for a "scene" event.
    private let sceneFraction = 0.45
    /// Cells changed (fraction) for a "region" event (one menu row ≈ 5 %).
    private let regionFraction = 0.03

    // Working buffers (detector queue only).
    private var current: [Float]
    private var reference: [Float]
    private var candidate: [Float]
    private var scratch: [Float]
    private var thumb: [UInt8]
    private var noiseFloor: [Float]
    /// How often each cell flips (EMA of "changed" per sample). A clock,
    /// a blinking cursor or a progress bar becomes volatile and is
    /// ignored instead of waking the model every second.
    private var volatility: [Float]
    private var cellDelta: [Float]
    private var candidateMask: [Bool]
    private var candidateStreak = 0
    private var hasReference = false
    private var staticSamples = 0
    private let queue = DispatchQueue(label: "com.vocavision.scenechange", qos: .userInitiated)
    private let isEnabled = Atomic<Bool>(false)

    init() {
        let n = thumbWidth * thumbHeight
        let cells = gridColumns * gridRows
        current = .init(repeating: 0, count: n)
        reference = .init(repeating: 0, count: n)
        candidate = .init(repeating: 0, count: n)
        scratch = .init(repeating: 0, count: n)
        thumb = .init(repeating: 0, count: n)
        noiseFloor = .init(repeating: 3, count: cells)
        volatility = .init(repeating: 0, count: cells)
        cellDelta = .init(repeating: 0, count: cells)
        candidateMask = .init(repeating: false, count: cells)
    }

    var enabled: Bool {
        get { isEnabled.load(ordering: .relaxed) }
        set { isEnabled.store(newValue, ordering: .relaxed) }
    }

    /// Forget the reference (e.g. after the phone moved) so the next
    /// stable frame becomes the baseline without firing an event.
    func reset() {
        queue.async { [self] in
            hasReference = false
            candidateStreak = 0
            staticSamples = 0
            for i in 0..<volatility.count { volatility[i] = 0 }
        }
    }

    /// Analyses one frame. Returns on the detector queue via `completion`
    /// with a change event or `nil`.
    func analyze(_ pixelBuffer: CVPixelBuffer, completion: @escaping @Sendable (SceneChange?) -> Void) {
        guard enabled else { completion(nil); return }
        // CVPixelBuffer is reference-counted and immutable once emitted by
        // the capture output; handing it to the detector queue is safe.
        nonisolated(unsafe) let buffer = pixelBuffer
        queue.async { [self] in
            completion(process(buffer))
        }
    }

    /// Synchronous variant for callers that already have a grayscale
    /// image (e.g. a rectified screen). Must be called from one serial
    /// context — never concurrently with `analyze(_:completion:)`.
    func analyze(grayThumbnail gray: [Float], width: Int, height: Int) -> SceneChange? {
        guard enabled, width >= thumbWidth, height >= thumbHeight else { return nil }
        // Area-average down to the working thumbnail.
        for ty in 0..<thumbHeight {
            let sy0 = ty * height / thumbHeight, sy1 = max(sy0 + 1, (ty + 1) * height / thumbHeight)
            for tx in 0..<thumbWidth {
                let sx0 = tx * width / thumbWidth, sx1 = max(sx0 + 1, (tx + 1) * width / thumbWidth)
                var sum: Float = 0
                for y in sy0..<sy1 { for x in sx0..<sx1 { sum += gray[y * width + x] } }
                current[ty * thumbWidth + tx] = sum / Float((sy1 - sy0) * (sx1 - sx0))
            }
        }
        return processCurrent()
    }

    // MARK: - Pipeline (detector queue)

    private func process(_ pixelBuffer: CVPixelBuffer) -> SceneChange? {
        guard makeThumbnail(from: pixelBuffer) else { return nil }
        return processCurrent()
    }

    private func processCurrent() -> SceneChange? {

        guard hasReference else {
            reference = current
            hasReference = true
            candidateStreak = 0
            return nil
        }

        // Pass 1: cancel exposure/white-level drift with a global linear
        // fit (reference ≈ a·current + b), then find candidate cells.
        var adjusted = photometricallyMatched(current, to: reference, using: nil)
        var bestDiff = alignedDifference(of: adjusted, against: reference)
        computeCellDeltas(from: bestDiff)
        var (mask, changedCells, bounds) = thresholdCells()

        // Passes 2–3: refit using only the cells that did NOT change, so a
        // new object or a moved highlight bar cannot skew the fit and make
        // the whole frame look different. Keep a refit only if it explains
        // more of the frame (fewer changed cells).
        var round = 0
        while round < 2, changedCells > 0, cellDelta.count - changedCells >= cellDelta.count / 5 {
            round += 1
            let refit = photometricallyMatched(current, to: reference, using: mask)
            let refitDiff = alignedDifference(of: refit, against: reference)
            let previousDeltas = cellDelta
            computeCellDeltas(from: refitDiff)
            let (newMask, newCount, newBounds) = thresholdCells()
            if newCount < changedCells {
                adjusted = refit; bestDiff = refitDiff
                (mask, changedCells, bounds) = (newMask, newCount, newBounds)
            } else {
                cellDelta = previousDeltas
                break
            }
        }
        _ = adjusted; _ = bestDiff
        // Track volatility and drop cells that flip all the time.
        var stableMask = mask
        for i in 0..<mask.count {
            volatility[i] = volatility[i] * 0.94 + (mask[i] ? 0.06 : 0)
            if volatility[i] > 0.3 { stableMask[i] = false }
        }
        if stableMask != mask {
            let (m, c, b) = boundsFor(mask: stableMask)
            (mask, changedCells, bounds) = (m, c, b)
        }
        let (minCol, maxCol, minRow, maxRow) = bounds
        let fraction = Double(changedCells) / Double(cellDelta.count)

        // Learn the noise floor from every cell that did not change — on
        // a flickering screen there is never a fully static frame, but
        // most cells are still quiet.
        for i in 0..<cellDelta.count where !mask[i] {
            noiseFloor[i] = noiseFloor[i] * 0.9 + cellDelta[i] * 0.1
        }

        if fraction < regionFraction {
            // Static: refresh the reference very slowly so lighting
            // drift never accumulates.
            staticSamples += 1
            if staticSamples >= 40 {          // ~8 s at 5 Hz
                reference = current
                staticSamples = 0
            }
            candidateStreak = 0
            return nil
        }

        staticSamples = 0

        // Candidate change: require it to settle — the current frame must
        // also match the previous candidate frame (transition finished).
        if candidateStreak > 0 {
            let settleDiff = alignedDifference(of: current, against: candidate)
            let settleMean = meanAbs(settleDiff)
            if settleMean > minimumCellDelta * 0.4 {
                // Still moving/transitioning — wait.
                candidate = current
                candidateMask = mask
                return nil
            }
            candidateStreak += 1
        } else {
            candidate = current
            candidateMask = mask
            candidateStreak = 1
            return nil
        }

        guard candidateStreak >= 2 else { return nil }

        // Commit: the settled frame is the new reference.
        reference = current
        candidateStreak = 0

        let region = CGRect(
            x: Double(minCol) / Double(gridColumns),
            y: Double(minRow) / Double(gridRows),
            width: Double(maxCol - minCol + 1) / Double(gridColumns),
            height: Double(maxRow - minRow + 1) / Double(gridRows)
        )
        let kind: SceneChange.Kind = fraction >= sceneFraction ? .scene : .region
        return SceneChange(kind: kind, changedFraction: fraction, region: region, timestamp: Date())
    }

    /// Luma plane → 64×36 grayscale thumbnail (vImage, no allocation).
    private func makeThumbnail(from pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let isBiPlanar = format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        let plane = isBiPlanar ? 0 : 0
        guard let base = isBiPlanar
                ? CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, plane)
                : CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }
        let width = isBiPlanar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, 0) : CVPixelBufferGetWidth(pixelBuffer)
        let height = isBiPlanar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, 0) : CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = isBiPlanar ? CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0) : CVPixelBufferGetBytesPerRow(pixelBuffer)

        var src = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: rowBytes)

        if !isBiPlanar {
            // BGRA fallback: extract a luma plane first.
            var lumaPlane = [UInt8](repeating: 0, count: width * height)
            let ok = lumaPlane.withUnsafeMutableBufferPointer { luma -> Bool in
                var dst = vImage_Buffer(data: luma.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                // BT.601 luma weights, 8-bit.
                var matrix: [Int16] = [ 29, 150, 77, 0 ]   // B G R A order for BGRA
                var preBias: [Int16] = [0, 0, 0, 0]
                let postBias: Int32 = 0
                let err = vImageMatrixMultiply_ARGB8888ToPlanar8(&src, &dst, &matrix, 256, &preBias, postBias, vImage_Flags(kvImageNoFlags))
                return err == kvImageNoError
            }
            guard ok else { return false }
            return lumaPlane.withUnsafeMutableBufferPointer { luma -> Bool in
                var planar = vImage_Buffer(data: luma.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width)
                return scale(&planar)
            }
        }
        return scale(&src)
    }

    private func scale(_ src: inout vImage_Buffer) -> Bool {
        let ok = thumb.withUnsafeMutableBufferPointer { out -> Bool in
            var dst = vImage_Buffer(data: out.baseAddress, height: vImagePixelCount(thumbHeight), width: vImagePixelCount(thumbWidth), rowBytes: thumbWidth)
            return vImageScale_Planar8(&src, &dst, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError
        }
        guard ok else { return false }
        vDSP.convertElements(of: thumb, to: &current)
        return true
    }

    /// Returns `a·cur + b` with (a, b) fitted by least squares so that
    /// the result matches `ref` on the pixels of unchanged cells
    /// (`excluding` marks changed cells; nil = use every pixel).
    private func photometricallyMatched(_ cur: [Float], to ref: [Float], using changedMask: [Bool]?) -> [Float] {
        let cellW = thumbWidth / gridColumns
        let cellH = thumbHeight / gridRows
        var n: Float = 0, sx: Float = 0, sy: Float = 0, sxx: Float = 0, sxy: Float = 0
        for y in 0..<thumbHeight {
            for x in 0..<thumbWidth {
                if let changedMask {
                    let cell = (y / cellH) * gridColumns + (x / cellW)
                    if changedMask[cell] { continue }
                }
                let i = y * thumbWidth + x
                let cx = cur[i], ry = ref[i]
                n += 1; sx += cx; sy += ry; sxx += cx * cx; sxy += cx * ry
            }
        }
        var a: Float = 1, b: Float = 0
        if n > 16 {
            let varX = sxx - sx * sx / n
            if varX > 1 {
                a = (sxy - sx * sy / n) / varX
                a = min(max(a, 0.5), 2.0)          // only plausible gain changes
            }
            b = (sy - a * sx) / n
        }
        var gain = a, offset = b
        vDSP_vsmsa(cur, 1, &gain, &offset, &scratch, 1, vDSP_Length(cur.count))
        return scratch
    }

    private func boundsFor(mask: [Bool]) -> ([Bool], Int, (Int, Int, Int, Int)) {
        var count = 0
        var minCol = gridColumns, maxCol = -1, minRow = gridRows, maxRow = -1
        for i in 0..<mask.count where mask[i] {
            count += 1
            let col = i % gridColumns, row = i / gridColumns
            minCol = min(minCol, col); maxCol = max(maxCol, col)
            minRow = min(minRow, row); maxRow = max(maxRow, row)
        }
        return (mask, count, (minCol, maxCol, minRow, maxRow))
    }

    /// Applies the adaptive threshold; returns mask, count and bounds.
    private func thresholdCells() -> ([Bool], Int, (Int, Int, Int, Int)) {
        var mask = [Bool](repeating: false, count: cellDelta.count)
        var changedCells = 0
        var minCol = gridColumns, maxCol = -1, minRow = gridRows, maxRow = -1
        for i in 0..<cellDelta.count {
            let threshold = max(minimumCellDelta, noiseFloor[i] * noiseMultiplier)
            if cellDelta[i] > threshold {
                mask[i] = true
                changedCells += 1
                let col = i % gridColumns, row = i / gridColumns
                minCol = min(minCol, col); maxCol = max(maxCol, col)
                minRow = min(minRow, row); maxRow = max(maxRow, row)
            }
        }
        return (mask, changedCells, (minCol, maxCol, minRow, maxRow))
    }

    /// |a − b| minimised over small integer shifts of `a`.
    private func alignedDifference(of a: [Float], against b: [Float]) -> [Float] {
        var best = [Float](repeating: 0, count: a.count)
        var bestScore = Float.greatestFiniteMagnitude
        var diff = [Float](repeating: 0, count: a.count)
        for dy in -maxShift...maxShift {
            for dx in -maxShift...maxShift {
                var sum: Float = 0
                for y in 0..<thumbHeight {
                    let sy = min(max(y + dy, 0), thumbHeight - 1)
                    for x in 0..<thumbWidth {
                        let sx = min(max(x + dx, 0), thumbWidth - 1)
                        let d = abs(a[sy * thumbWidth + sx] - b[y * thumbWidth + x])
                        diff[y * thumbWidth + x] = d
                        sum += d
                    }
                }
                if sum < bestScore {
                    bestScore = sum
                    best = diff
                }
            }
        }
        return best
    }

    private func computeCellDeltas(from diff: [Float]) {
        let cellW = thumbWidth / gridColumns
        let cellH = thumbHeight / gridRows
        for row in 0..<gridRows {
            for col in 0..<gridColumns {
                var sum: Float = 0
                for y in (row * cellH)..<((row + 1) * cellH) {
                    for x in (col * cellW)..<((col + 1) * cellW) {
                        sum += diff[y * thumbWidth + x]
                    }
                }
                cellDelta[row * gridColumns + col] = sum / Float(cellW * cellH)
            }
        }
    }

    private func meanAbs(_ v: [Float]) -> Float {
        var m: Float = 0
        vDSP_meanv(v, 1, &m, vDSP_Length(v.count))
        return m
    }
}
