import Foundation

// Typed wire messages for the Gemini Live API (BidiGenerateContent, v1beta).
// Reference: https://ai.google.dev/api/live

nonisolated enum LiveClientMessage {
    struct Setup: Encodable, Sendable {
        var model: String
        var generationConfig: GenerationConfig
        var systemInstruction: Content?
        var realtimeInputConfig: RealtimeInputConfig
        var inputAudioTranscription = AudioTranscriptionConfig()
        var outputAudioTranscription = AudioTranscriptionConfig()
        var sessionResumption: SessionResumption
        var contextWindowCompression = ContextWindowCompression()
        var proactivity: Proactivity?
        var tools: [Tool]?
    }

    struct Proactivity: Encodable, Sendable {
        var proactiveAudio: Bool
    }

    struct AudioTranscriptionConfig: Encodable, Sendable {
        var customVocabulary: [String]?
    }

    struct GenerationConfig: Encodable, Sendable {
        var responseModalities: [String] = ["AUDIO"]
        var speechConfig: SpeechConfig
        /// HIGH = zoomed reframing at the same token cost; needed to read
        /// small screen text without guessing.
        var mediaResolution: String = "MEDIA_RESOLUTION_HIGH"
        var enableAffectiveDialog: Bool?
    }

    struct SpeechConfig: Encodable, Sendable {
        struct VoiceConfig: Encodable, Sendable {
            struct Prebuilt: Encodable, Sendable { var voiceName: String }
            var prebuiltVoiceConfig: Prebuilt
        }
        var voiceConfig: VoiceConfig
        init(voiceName: String) { voiceConfig = VoiceConfig(prebuiltVoiceConfig: .init(voiceName: voiceName)) }
    }

    struct Content: Encodable, Sendable {
        struct Part: Encodable, Sendable { var text: String }
        var role: String?
        var parts: [Part]
        init(text: String, role: String? = nil) { self.role = role; self.parts = [Part(text: text)] }
    }

    struct RealtimeInputConfig: Encodable, Sendable {
        struct AutomaticActivityDetection: Encodable, Sendable {
            var disabled = false
            var startOfSpeechSensitivity: String
            var endOfSpeechSensitivity: String
            var prefixPaddingMs: Int
            var silenceDurationMs: Int
        }
        var automaticActivityDetection: AutomaticActivityDetection
        var activityHandling = "START_OF_ACTIVITY_INTERRUPTS"
        var turnCoverage = "TURN_INCLUDES_AUDIO_ACTIVITY_AND_ALL_VIDEO"
    }

    struct SessionResumption: Encodable, Sendable { var handle: String? }
    struct ContextWindowCompression: Encodable, Sendable { var slidingWindow = EmptyObject() }

    struct Tool: Encodable, Sendable { var functionDeclarations: [FunctionDeclaration] }
    struct FunctionDeclaration: Encodable, Sendable {
        var name: String
        var description: String
        var parameters: Schema?
    }
    final class Schema: Encodable, Sendable {
        let type: String
        let description: String?
        let properties: [String: Schema]?
        let required: [String]?
        let `enum`: [String]?
        init(type: String, description: String? = nil, properties: [String: Schema]? = nil,
             required: [String]? = nil, enum values: [String]? = nil) {
            self.type = type; self.description = description; self.properties = properties
            self.required = required; self.enum = values
        }
    }

    struct FunctionResponse: Encodable, Sendable {
        var id: String?
        var name: String
        var response: [String: JSONValue]
    }
    struct ToolResponse: Encodable, Sendable { var functionResponses: [FunctionResponse] }
    struct ToolResponseEnvelope: Encodable, Sendable { var toolResponse: ToolResponse }

    struct Blob: Encodable, Sendable {
        var data: Data
        var mimeType: String
    }
    struct RealtimeInput: Encodable, Sendable {
        var audio: Blob?
        var video: Blob?
        var text: String?
        var audioStreamEnd: Bool?
    }
    struct SetupEnvelope: Encodable, Sendable { var setup: Setup }
    struct RealtimeInputEnvelope: Encodable, Sendable { var realtimeInput: RealtimeInput }
}

nonisolated struct EmptyObject: Codable, Sendable, Equatable {
    init() {}
    init(from decoder: Decoder) throws { _ = try decoder.container(keyedBy: NoKeys.self) }
    func encode(to encoder: Encoder) throws { _ = encoder.container(keyedBy: NoKeys.self) }
    private enum NoKeys: CodingKey {}
}

nonisolated struct LiveServerMessage: Decodable, Sendable {
    struct ServerContent: Decodable, Sendable {
        var modelTurn: ModelContent?
        var interrupted: Bool?
        var turnComplete: Bool?
        var generationComplete: Bool?
        var waitingForInput: Bool?
        var inputTranscription: Transcription?
        var interimInputTranscription: Transcription?
        var outputTranscription: Transcription?
    }
    struct ModelContent: Decodable, Sendable {
        var role: String?
        var parts: [Part]?
    }
    struct Part: Decodable, Sendable {
        var text: String?
        var inlineData: InlineData?
        var thought: Bool?
        private enum CodingKeys: String, CodingKey { case text, inlineData, thought; case inlineDataSnake = "inline_data" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decodeIfPresent(String.self, forKey: .text)
            thought = try c.decodeIfPresent(Bool.self, forKey: .thought)
            inlineData = try c.decodeIfPresent(InlineData.self, forKey: .inlineData)
                ?? c.decodeIfPresent(InlineData.self, forKey: .inlineDataSnake)
        }
    }
    struct InlineData: Decodable, Sendable {
        var mimeType: String?
        var data: Data
        private enum CodingKeys: String, CodingKey { case mimeType, data; case mimeTypeSnake = "mime_type" }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? c.decodeIfPresent(String.self, forKey: .mimeTypeSnake)
            data = try c.decode(Data.self, forKey: .data)
        }
    }
    struct Transcription: Decodable, Sendable {
        var text: String?
        var finished: Bool?
        var languageCode: String?
    }
    struct GoAway: Decodable, Sendable { var timeLeft: String? }
    struct SessionResumptionUpdate: Decodable, Sendable {
        var newHandle: String?
        var resumable: Bool?
    }
    struct UsageMetadata: Decodable, Sendable {
        var promptTokenCount: Int?
        var responseTokenCount: Int?
        var totalTokenCount: Int?
    }
    struct ToolCall: Decodable, Sendable {
        struct FunctionCall: Decodable, Sendable {
            var id: String?
            var name: String?
            var args: [String: JSONValue]?
        }
        var functionCalls: [FunctionCall]?
    }
    struct ToolCallCancellation: Decodable, Sendable { var ids: [String]? }
    struct APIError: Decodable, Sendable {
        var code: Int?
        var message: String?
        var status: String?
    }

    var setupComplete: EmptyObject?
    var serverContent: ServerContent?
    var toolCall: ToolCall?
    var toolCallCancellation: ToolCallCancellation?
    var goAway: GoAway?
    var sessionResumptionUpdate: SessionResumptionUpdate?
    var usageMetadata: UsageMetadata?
    var error: APIError?
}

nonisolated extension LiveServerMessage.GoAway {
    var secondsLeft: Double? {
        guard let timeLeft, timeLeft.hasSuffix("s") else { return nil }
        return Double(timeLeft.dropLast())
    }
}

/// Loose JSON value for tool-call arguments and responses.
nonisolated enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n): try c.encode(n)
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return ["true", "yes", "on"].contains(s.lowercased()) ? true : (["false", "no", "off"].contains(s.lowercased()) ? false : nil)
        case .number(let n): return n != 0
        default: return nil
        }
    }
}
