import Foundation
import Observation

/// Google's published voice directory, loaded from Google's own servers.
///
/// The Gemini API has no `voices.list` endpoint; the authoritative list
/// lives in Google's documentation. Two pages are read and merged:
///   • Firebase AI Logic — Live API configuration: name, characteristic,
///     gender and an official sample recording for every voice.
///   • Gemini API — Speech generation: the voice names and characteristics
///     the TTS/Live models accept.
/// The merged list is cached on disk so it is available offline, and
/// refreshed at most once a day; the bundled catalogue in `VoiceCatalog`
/// is the last resort.
@Observable
@MainActor
final class VoiceDirectory {
    static let shared = VoiceDirectory()

    nonisolated struct Entry: Codable, Sendable, Equatable {
        var name: String
        var style: String
        /// "Male", "Female" or "" when Google does not say.
        var gender: String
        var sampleURL: String?
    }

    private(set) var entries: [Entry] = []
    private(set) var fetchedAt: Date?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    nonisolated static let firebasePage = URL(string: "https://firebase.google.com/docs/ai-logic/live-api/configuration")!
    nonisolated static let geminiPage = URL(string: "https://ai.google.dev/gemini-api/docs/speech-generation")!

    private init() {
        if let cached = Self.readCache() {
            entries = cached.entries
            fetchedAt = cached.fetchedAt
        }
    }

    /// Refreshes when the cached list is missing or older than `maxAge`.
    func refreshIfStale(maxAge: TimeInterval = 24 * 3600) async {
        if let fetchedAt, !entries.isEmpty, Date().timeIntervalSince(fetchedAt) < maxAge { return }
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh = try await Self.fetch()
            guard !fresh.isEmpty else { throw DirectoryError.empty }
            if fresh != entries { vlog("voices", "🎙 directory updated: \(fresh.count) voices from Google") }
            entries = fresh
            fetchedAt = Date()
            lastError = nil
            Self.writeCache(.init(fetchedAt: Date(), entries: fresh))
        } catch {
            lastError = error.localizedDescription
            vlog("voices", "⚠️ directory refresh failed: \(error.localizedDescription)", level: .warning)
        }
    }

    // MARK: - Fetch + parse

    nonisolated private enum DirectoryError: LocalizedError {
        case empty
        var errorDescription: String? { "Google's voice pages returned no voices." }
    }

    nonisolated static func fetch() async throws -> [Entry] {
        async let firebase = fetchPage(firebasePage)
        async let gemini = fetchPage(geminiPage)
        let firebaseRows = (try? await firebase).map(parseFirebaseTable) ?? []
        let geminiRows = (try? await gemini).map(parseGeminiTable) ?? []
        guard !firebaseRows.isEmpty || !geminiRows.isEmpty else { throw DirectoryError.empty }
        return merge(firebase: firebaseRows, gemini: geminiRows)
    }

    nonisolated private static func fetchPage(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let html = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
        return html
    }

    /// Rows of the Firebase table: `<td><code>Name</code></td><td>Style</td><td>Gender</td><td><audio><source src=…>`.
    nonisolated static func parseFirebaseTable(_ html: String) -> [Entry] {
        var result: [Entry] = []
        let rows = html.components(separatedBy: "<tr")
        for row in rows.dropFirst() {
            let cells = cellTexts(in: row)
            guard cells.count >= 3 else { continue }
            let name = cells[0], style = cells[1], gender = cells[2]
            guard isVoiceName(name), ["Male", "Female"].contains(gender) else { continue }
            var sample: String?
            if let range = row.range(of: #"<source src="([^"]+\.wav)""#, options: .regularExpression) {
                let tag = String(row[range])
                if let start = tag.range(of: "src=\""), let end = tag.range(of: "\"", range: start.upperBound..<tag.endIndex) {
                    let path = String(tag[start.upperBound..<end.lowerBound])
                    sample = path.hasPrefix("http") ? path : "https://firebase.google.com" + path
                }
            }
            result.append(Entry(name: name, style: style, gender: gender, sampleURL: sample))
        }
        return result
    }

    /// Cells of the Gemini docs table: `<b>Name</b> -- <em>Style</em>`.
    nonisolated static func parseGeminiTable(_ html: String) -> [(name: String, style: String)] {
        var result: [(String, String)] = []
        let pattern = #"<b>([A-Za-z]+)</b>\s*--\s*<em>([^<]+)</em>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        for match in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            let style = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            if isVoiceName(name) { result.append((name, style)) }
        }
        return result
    }

    nonisolated private static func merge(firebase: [Entry], gemini: [(name: String, style: String)]) -> [Entry] {
        var byName: [String: Entry] = [:]
        var order: [String] = []
        for row in firebase {
            byName[row.name] = row
            order.append(row.name)
        }
        for row in gemini {
            if var existing = byName[row.name] {
                if existing.style.isEmpty { existing.style = row.style; byName[row.name] = existing }
            } else {
                byName[row.name] = Entry(name: row.name, style: row.style, gender: "", sampleURL: nil)
                order.append(row.name)
            }
        }
        return order.compactMap { byName[$0] }
    }

    nonisolated private static func cellTexts(in row: String) -> [String] {
        var cells: [String] = []
        var rest = Substring(row)
        while let open = rest.range(of: "<td") {
            guard let openEnd = rest[open.upperBound...].firstIndex(of: ">") else { break }
            let afterOpen = rest.index(after: openEnd)
            guard let close = rest[afterOpen...].range(of: "</td>") else { break }
            let inner = String(rest[afterOpen..<close.lowerBound])
            cells.append(stripTags(inner))
            rest = rest[close.upperBound...]
        }
        return cells
    }

    nonisolated private static func stripTags(_ s: String) -> String {
        var out = ""
        var inTag = false
        for ch in s {
            if ch == "<" { inTag = true; continue }
            if ch == ">" { inTag = false; continue }
            if !inTag { out.append(ch) }
        }
        return out.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func isVoiceName(_ s: String) -> Bool {
        !s.isEmpty && s.count <= 24 && s.allSatisfy(\.isLetter) && s.first!.isUppercase
    }

    // MARK: - Cache

    nonisolated private struct CacheFile: Codable { var fetchedAt: Date; var entries: [Entry] }

    nonisolated private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("voice-directory.json")
    }

    nonisolated private static func readCache() -> CacheFile? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CacheFile.self, from: data)
    }

    nonisolated private static func writeCache(_ file: CacheFile) {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(file) { try? data.write(to: cacheURL, options: .atomic) }
    }
}
