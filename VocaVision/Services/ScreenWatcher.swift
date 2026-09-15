import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Foundation
import ImageIO
import Vision

/// Watches a screen (BIOS, menu, terminal, app) held in front of the
/// camera and decides **where** and **when** something changed — no OCR
/// on the phone. Reading the text is left to the model, which gets a
/// high-resolution crop of exactly the row that changed.
///
/// Pipeline per sample (≈5 Hz):
///   1. Find the display rectangle (Vision `DetectRectanglesRequest`,
///      refreshed every second) and rectify it with a perspective
///      correction so rows are horizontal and undistorted.
///   2. Build a colour profile of the rectified screen: the mean colour
///      of every scan line. The page background is the median line
///      colour; a selection bar is a short band of lines whose colour
///      deviates strongly from it (inverted, tinted or lighter).
///   3. Bands that stay put (title bar, footer, status line) are
///      furniture. A band that *appears where there was none* is the
///      highlight moving; confirmed on the next sample it becomes an
///      event with a crop of that band at up to 1600 px wide.
///   4. Independently, a luma thumbnail of the rectified screen feeds
///      the change detector: a change over most of the screen is a page
///      change, reported with a full screen image.
nonisolated final class ScreenWatcher: @unchecked Sendable {
    struct Band: Sendable {
        /// Normalised vertical extent within the screen, origin top.
        let y0: CGFloat
        let y1: CGFloat
        let strength: Float
        var center: CGFloat { (y0 + y1) / 2 }
        var height: CGFloat { y1 - y0 }
    }

    enum Update: Sendable {
        case highlight(crop: Data, band: Band)
        case page(screen: Data)
    }

    private struct Quad {
        var tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint
        var confidence: Float
        var area: CGFloat
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])
    private let rectangleRequest: DetectRectanglesRequest = {
        var r = DetectRectanglesRequest()
        r.minimumAspectRatio = 0.4
        r.maximumAspectRatio = 1.0     // aspect is min/max side; a screen is 1.3…2.4
        r.minimumSize = 0.25
        r.minimumConfidence = 0.5
        r.quadratureToleranceDegrees = 25
        r.maximumObservations = 3
        return r
    }()
    private let pageDetector = SceneChangeDetector()

    // Profile geometry.
    private let profileWidth = 384

    // State (single caller at a time — the orchestrator awaits each call).
    private var quad: Quad?
    private var quadDetectedAt: Date = .distantPast
    private var quadAdoptedAt: Date = .distantPast
    private var lastQuadSeenAt: Date = .distantPast
    private var previousBands: [Band] = []
    private var candidate: Band?
    private var candidateHits = 0
    private var announced: Band?
    private var samplesSinceReset = 0
    private var lastPageEventAt: Date = .distantPast
    private(set) var hasScreen = false

    func reset() {
        quad = nil
        quadDetectedAt = .distantPast
        quadAdoptedAt = .distantPast
        lastQuadSeenAt = .distantPast
        previousBands = []
        candidate = nil
        candidateHits = 0
        announced = nil
        samplesSinceReset = 0
        pageDetector.enabled = true
        pageDetector.reset()
    }

    init() { pageDetector.enabled = true }

    // MARK: - Sampling

    func process(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) async -> Update? {
        nonisolated(unsafe) let buffer = pixelBuffer
        let oriented = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        let size = oriented.extent.size
        samplesSinceReset += 1

        // 1. Display rectangle (refresh once a second). Prefer the
        // largest quad and never trade a good one for a smaller inner
        // rectangle (a menu bar or table can look like a rectangle too).
        if Date().timeIntervalSince(quadDetectedAt) >= 1.0 {
            quadDetectedAt = Date()
            let found = await detectScreen(in: buffer, orientation: orientation, size: size)
            if let found {
                let shouldAdopt: Bool
                if let current = quad {
                    let stale = Date().timeIntervalSince(quadAdoptedAt) > 6
                    shouldAdopt = !Self.sameQuad(found, current) && (found.area >= current.area * 0.9 || stale)
                } else {
                    shouldAdopt = true
                }
                if shouldAdopt {
                    quad = found
                    quadAdoptedAt = Date()
                    previousBands = []
                    candidate = nil
                    announced = nil
                    pageDetector.reset()
                }
                lastQuadSeenAt = Date()
            } else if Date().timeIntervalSince(lastQuadSeenAt) > 4 {
                quad = nil
            }
            hasScreen = quad != nil
        }

        // 2. Rectify.
        let screen: CIImage
        if let quad {
            let f = CIFilter.perspectiveCorrection()
            f.inputImage = oriented
            f.topLeft = quad.tl; f.topRight = quad.tr; f.bottomLeft = quad.bl; f.bottomRight = quad.br
            f.crop = true
            guard let out = f.outputImage else { return nil }
            screen = out.transformed(by: CGAffineTransform(translationX: -out.extent.minX, y: -out.extent.minY))
        } else {
            screen = oriented
        }
        let sw = screen.extent.width, sh = screen.extent.height
        guard sw > 16, sh > 16 else { return nil }

        // 3. Colour profile of scan lines.
        let scale = CGFloat(profileWidth) / sw
        let ph = max(24, Int(sh * scale))
        var rgba = [UInt8](repeating: 0, count: profileWidth * ph * 4)
        let small = screen.transformed(by: CGAffineTransform(scaleX: scale, y: CGFloat(ph) / sh))
        rgba.withUnsafeMutableBytes { raw in
            ciContext.render(small, toBitmap: raw.baseAddress!, rowBytes: profileWidth * 4,
                             bounds: CGRect(x: 0, y: 0, width: profileWidth, height: ph),
                             format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        }
        let (bands, luma) = analyseProfile(rgba, width: profileWidth, height: ph)

        // 4. Page change: most of the rectified screen changed, or many
        // bands appeared at once (new content, not one moving bar).
        var pageUpdate: Update?
        let appearedNow = samplesSinceReset > 1
            ? bands.filter { b in !previousBands.contains { Self.sameBand($0, b) } }.count : 0
        let pixelChange = pageDetector.analyze(grayThumbnail: luma, width: profileWidth, height: ph)
        let bigChange = pixelChange.map { $0.changedFraction >= 0.5 } ?? false
        if (bigChange || appearedNow >= 3), Date().timeIntervalSince(lastPageEventAt) > 2.5 {
            lastPageEventAt = Date()
            previousBands = bands
            candidate = nil
            announced = nil
            if let jpeg = jpeg(of: screen, maxWidth: 1280, quality: 0.8) {
                pageUpdate = .page(screen: jpeg)
            }
        }

        // 5. Highlight movement: a band that was not there before.
        defer { previousBands = bands }
        guard samplesSinceReset > 1 else { return pageUpdate }
        let appeared = bands.filter { b in !previousBands.contains { Self.sameBand($0, b) } }
        vlog("watch", "bands=\(bands.map { String(format: "%.2f–%.2f/%d", $0.y0, $0.y1, Int($0.strength)) }) new=\(appeared.count) cand=\(candidate.map { String(format: "%.2f", $0.center) } ?? "-")x\(candidateHits) ann=\(announced.map { String(format: "%.2f", $0.center) } ?? "-")", level: .debug)
        if let strongest = appeared.max(by: { $0.strength < $1.strength }) {
            if let c = candidate, Self.sameBand(c, strongest) {
                candidateHits += 1
            } else {
                candidate = strongest
                candidateHits = 1
            }
        } else if let c = candidate, bands.contains(where: { Self.sameBand($0, c) }) {
            candidateHits += 1
        } else {
            candidate = nil
            candidateHits = 0
        }
        if pageUpdate != nil { return pageUpdate }
        guard let c = candidate, candidateHits >= 2 else { return nil }
        guard !(announced.map { Self.sameBand($0, c) } ?? false) else { return nil }
        announced = c
        candidate = nil
        candidateHits = 0

        // Crop the band with margin, full width, at up to 1600 px wide.
        let margin = c.height * 0.55
        let top = max(0, c.y0 - margin), bottom = min(1, c.y1 + margin)
        let cropRect = CGRect(x: 0, y: (1 - bottom) * sh, width: sw, height: (bottom - top) * sh)
        let crop = screen.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: 0, y: -cropRect.minY))
        guard let jpeg = jpeg(of: crop, maxWidth: 1600, quality: 0.88) else { return nil }
        vlog("watch", "🎯 highlight band y=\(String(format: "%.2f–%.2f", c.y0, c.y1)) strength=\(Int(c.strength)) crop=\(jpeg.count / 1024) KB")
        return .highlight(crop: jpeg, band: c)
    }

    // MARK: - Screen rectangle

    private func detectScreen(in buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, size: CGSize) async -> Quad? {
        nonisolated(unsafe) let pb = buffer
        do {
            let observations = try await rectangleRequest.perform(on: pb, orientation: orientation)
            // Largest confident quad.
            let best = observations.max { a, b in
                Self.area(a) < Self.area(b)
            }
            guard let best, Self.area(best) >= 0.15 else { return nil }
            func p(_ n: NormalizedPoint) -> CGPoint { CGPoint(x: n.x * size.width, y: n.y * size.height) }
            // Vision's corners are named in image space (bottom-left origin); map to CI's.
            return Quad(tl: p(best.topLeft), tr: p(best.topRight), bl: p(best.bottomLeft), br: p(best.bottomRight),
                        confidence: best.confidence, area: Self.area(best))
        } catch {
            vlog("watch", "⚠️ rectangle detection failed: \(error.localizedDescription)", level: .debug)
            return nil
        }
    }

    private static func area(_ o: RectangleObservation) -> CGFloat {
        let pts = [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map(\.cgPoint)
        var s: CGFloat = 0
        for i in 0..<4 { let a = pts[i], b = pts[(i + 1) % 4]; s += a.x * b.y - b.x * a.y }
        return abs(s) / 2
    }

    private static func sameQuad(_ a: Quad, _ b: Quad) -> Bool {
        func close(_ p: CGPoint, _ q: CGPoint) -> Bool { abs(p.x - q.x) < 40 && abs(p.y - q.y) < 40 }
        return close(a.tl, b.tl) && close(a.tr, b.tr) && close(a.bl, b.bl) && close(a.br, b.br)
    }

    private static func sameBand(_ a: Band, _ b: Band) -> Bool {
        abs(a.center - b.center) <= max(a.height, b.height) * 0.6
    }

    // MARK: - Colour profile

    /// Returns the deviant bands and a luma thumbnail of the profile image.
    private func analyseProfile(_ rgba: [UInt8], width: Int, height: Int) -> ([Band], [Float]) {
        let x0 = width / 16, x1 = width - width / 16      // skip bezels
        var r = [Float](repeating: 0, count: height), g = r, b = r
        var luma = [Float](repeating: 0, count: width * height)
        rgba.withUnsafeBufferPointer { px in
            for y in 0..<height {
                var sr: Float = 0, sg: Float = 0, sb: Float = 0
                let row = y * width * 4
                for x in 0..<width {
                    let i = row + x * 4
                    let R = Float(px[i]), G = Float(px[i + 1]), B = Float(px[i + 2])
                    luma[y * width + x] = 0.299 * R + 0.587 * G + 0.114 * B
                    if x >= x0, x < x1 { sr += R; sg += G; sb += B }
                }
                let n = Float(x1 - x0)
                r[y] = sr / n; g[y] = sg / n; b[y] = sb / n
            }
        }
        func median(_ v: [Float]) -> Float { let s = v.sorted(); return s[s.count / 2] }
        let bgR = median(r), bgG = median(g), bgB = median(b)
        var d = [Float](repeating: 0, count: height)
        for y in 0..<height {
            let dr = r[y] - bgR, dg = g[y] - bgG, db = b[y] - bgB
            d[y] = (dr * dr + dg * dg + db * db).squareRoot()
        }
        // Smooth (3 taps) and threshold against the robust spread.
        var s = d
        for y in 1..<(height - 1) { s[y] = (d[y - 1] + d[y] + d[y + 1]) / 3 }
        let med = median(s)
        let mad = median(s.map { abs($0 - med) })
        let threshold = max(30, med + 4 * mad)

        var bands: [Band] = []
        var y = 0
        while y < height {
            guard s[y] > threshold else { y += 1; continue }
            var end = y
            var strength: Float = 0
            while end < height, s[end] > threshold { strength = max(strength, s[end]); end += 1 }
            let h = CGFloat(end - y) / CGFloat(height)
            if h >= 0.012, h <= 0.16 {
                bands.append(Band(y0: CGFloat(y) / CGFloat(height), y1: CGFloat(end) / CGFloat(height), strength: strength))
            }
            y = end
        }
        return (bands, luma)
    }

    // MARK: - Encoding

    private func jpeg(of image: CIImage, maxWidth: CGFloat, quality: CGFloat) -> Data? {
        let scale = min(1, maxWidth / image.extent.width)
        let scaled = scale < 1 ? image.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) : image
        let origin = scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY))
        return ciContext.jpegRepresentation(of: origin, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                                            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality])
    }
}
