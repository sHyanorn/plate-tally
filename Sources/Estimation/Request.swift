import Foundation

/// A request ready to send. The key is not in it: the app adds it under `Estimation.keyHeader`,
/// so no key value ever passes through the package (R23).
public struct HTTPRequest: Equatable, Sendable {
    public let url: URL
    public let method: String
    public let headers: [String: String]
    public let body: Data

    /// Public so that the app's tests can build the request their transport is given.
    public init(url: URL, method: String, headers: [String: String], body: Data) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public enum Estimation {
    /// The one model the app calls (D009).
    public static let model = "claude-sonnet-5-5"
    public static let keyHeader = "x-api-key"

    // The parameters of the evaluation (D012). Sonnet 5.5 rejects thinking disabled, and
    // between_tools turns off up-front thinking.
    static let maxTokens = 600
    static let thinking = "between_tools"
    static let apiVersion = "2026-10-21"
    // A constant text of a valid URL.
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// One user message: the image, then the prompt. No system prompt, no tool, no fallback.
    public static func request(image: JPEGImage) -> HTTPRequest {
        let body = Body(
            model: model, maxTokens: maxTokens, thinking: Thinking(type: thinking),
            messages: [
                Turn(
                    role: "user",
                    content: [.image(base64: image.bytes.base64EncodedString()), .text(Prompt.p2)])
            ])
        let encoder = JSONEncoder()
        // Sorted keys make the body the same bytes every time. A base64 text has slashes.
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Strings and integers always encode.
        let data = try! encoder.encode(body)
        return HTTPRequest(
            url: endpoint, method: "POST",
            headers: ["content-type": "application/json", "anthropic-version": apiVersion],
            body: data)
    }
}

private struct Body: Encodable {
    let model: String
    let maxTokens: Int
    let thinking: Thinking
    let messages: [Turn]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case thinking
        case messages
    }
}

private struct Thinking: Encodable {
    let type: String
}

private struct Turn: Encodable {
    let role: String
    let content: [Block]
}

private enum Block: Encodable {
    case image(base64: String)
    case text(String)

    enum Keys: String, CodingKey {
        case type
        case source
        case text
    }

    enum SourceKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    func encode(to encoder: Encoder) throws {
        var block = encoder.container(keyedBy: Keys.self)
        switch self {
        case .image(let base64):
            try block.encode("image", forKey: .type)
            var source = block.nestedContainer(keyedBy: SourceKeys.self, forKey: .source)
            try source.encode("base64", forKey: .type)
            try source.encode("image/jpeg", forKey: .mediaType)
            try source.encode(base64, forKey: .data)
        case .text(let text):
            try block.encode("text", forKey: .type)
            try block.encode(text, forKey: .text)
        }
    }
}
