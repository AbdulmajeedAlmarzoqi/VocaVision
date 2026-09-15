import Foundation

/// REST helper for the Gemini API: key validation, Live model discovery,
/// and the voice catalogue (see `VoiceCatalog`). All conversation
/// traffic goes through `GeminiLiveClient` (WebSocket).
enum GeminiClient {
    nonisolated static let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Live models in preference order; the first one the key can use wins.
    nonisolated static let preferredLiveModels: [String] = [
        "models/gemini-3.1-flash-live-preview",
        "models/gemini-2.5-flash-native-audio-preview-12-2025",
    ]
    nonisolated static let defaultLiveModel = "models/gemini-3.1-flash-live-preview"

    enum ValidationError: Error {
        case unauthorized
        case rateLimited
        case network(String)
        case unknown(Int)

        var userMessage: String {
            switch self {
            case .unauthorized:
                return tr(ar: "Gemini رفض هالمفتاح. تأكد إنك ناسخه كامل من Google AI Studio.",
                          en: "Gemini rejected this key. Make sure you copied the full key from Google AI Studio.")
            case .rateLimited:
                return tr(ar: "تخطّيت حدّ الطلبات على هالمفتاح حاليّاً. خذ شوي ثم حاول.",
                          en: "You've hit the request limit on this key. Wait a bit and try again.")
            case .network(let message):
                return tr(ar: "ما قدرت أوصل للشبكة: \(message)", en: "Couldn't reach the network: \(message)")
            case .unknown(let code):
                return tr(ar: "ردّ غير متوقّع من Gemini (HTTP \(code)).", en: "Unexpected response from Gemini (HTTP \(code)).")
            }
        }
    }

    nonisolated static func request(_ path: String, apiKey: String, method: String = "GET", query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        return request
    }

    nonisolated static func validate(apiKey: String) async throws {
        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request("models", apiKey: apiKey))
        } catch {
            throw ValidationError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw ValidationError.unknown(-1) }
        switch http.statusCode {
        case 200..<300: return
        case 400, 401, 403: throw ValidationError.unauthorized
        case 429: throw ValidationError.rateLimited
        default: throw ValidationError.unknown(http.statusCode)
        }
    }

    nonisolated struct ModelInfo: Decodable, Sendable {
        var name: String
        var supportedGenerationMethods: [String]?
    }

    /// Every model the key can see, in canonical `models/…` form.
    nonisolated static func listModels(apiKey: String) async throws -> [ModelInfo] {
        let (data, response) = try await session.data(for: request("models", apiKey: apiKey, query: [URLQueryItem(name: "pageSize", value: "1000")]))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
        struct ModelList: Decodable { var models: [ModelInfo]? }
        return try JSONDecoder().decode(ModelList.self, from: data).models ?? []
    }

    /// Every model whose `supportedGenerationMethods` include
    /// `bidiGenerateContent`.
    nonisolated static func listLiveModels(apiKey: String) async throws -> [String] {
        try await listModels(apiKey: apiKey)
            .filter { ($0.supportedGenerationMethods ?? []).contains("bidiGenerateContent") }
            .map(\.name)
    }

    /// TTS models in preference order; used for voice previews.
    nonisolated static let preferredTTSModels: [String] = [
        "models/gemini-3.1-flash-tts-preview",
        "models/gemini-2.5-flash-preview-tts",
        "models/gemini-2.5-pro-preview-tts",
    ]

    private static var ttsCache: [String: String] = [:]

    static func preferredTTSModel(apiKey: String) async -> String {
        let cacheKey = String(apiKey.suffix(8))
        if let cached = ttsCache[cacheKey] { return cached }
        var chosen = preferredTTSModels[0]
        if let models = try? await listModels(apiKey: apiKey) {
            let tts = models.filter { $0.name.localizedCaseInsensitiveContains("tts") && ($0.supportedGenerationMethods ?? []).contains("generateContent") }.map(\.name)
            if let preferred = preferredTTSModels.first(where: { tts.contains($0) }) { chosen = preferred }
            else if let first = tts.first { chosen = first }
        }
        ttsCache[cacheKey] = chosen
        return chosen
    }

    private static var modelCache: [String: String] = [:]

    static func preferredLiveModel(apiKey: String) async -> String {
        let cacheKey = String(apiKey.suffix(8))
        if let cached = modelCache[cacheKey] { return cached }
        var chosen = defaultLiveModel
        do {
            let available = try await listLiveModels(apiKey: apiKey)
            vlog("session", "🔎 live models: \(available.map { $0.replacingOccurrences(of: "models/", with: "") }.joined(separator: ", "))",
                 level: available.isEmpty ? .warning : .info)
            if let preferred = preferredLiveModels.first(where: { available.contains($0) }) {
                chosen = preferred
            } else if let first = available.first(where: { $0.contains("live") || $0.contains("native-audio") }) {
                chosen = first
            }
        } catch {
            vlog("session", "⚠️ ListModels failed: \(error.localizedDescription) — using \(defaultLiveModel)", level: .warning)
        }
        modelCache[cacheKey] = chosen
        return chosen
    }
}
