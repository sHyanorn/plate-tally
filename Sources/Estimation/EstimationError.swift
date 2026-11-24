import Core
import Foundation

/// A reply that cannot be used. `reason` is the code shown with the error (R6).
public struct EstimationError: PlateError, Equatable {
    public enum Reason: String, Sendable {
        case http
        case badResponse = "bad_response"
        case refusal
        case maxTokens = "max_tokens"
        case emptyText = "empty_text"
        case notJSON = "not_json"
        case notObject = "not_object"
        case wrongKeys = "wrong_keys"
        case badValue = "bad_value"
        case tooManyItems = "too_many_items"
    }

    public let reason: Reason
    public let what: String
    public let expected: String
    public let saw: String

    public var description: String { "\(reason.rawValue): \(what): expected \(expected), saw \(saw)" }
}

extension EstimationError {
    static func http(status: Int, body: Data) -> EstimationError {
        struct Body: Decodable {
            struct Detail: Decodable {
                let type: String?
                let message: String?
            }
            let error: Detail?
        }
        var seen = "status \(status)"
        if let detail = (try? JSONDecoder().decode(Body.self, from: body))?.error {
            let parts = [detail.type, detail.message].compactMap { $0 }
            seen += parts.isEmpty ? "" : ", \(parts.joined(separator: ": "))"
        } else {
            seen += ", body \(excerpt(String(decoding: body, as: UTF8.self)))"
        }
        return EstimationError(
            reason: .http, what: "the request failed", expected: "status 200", saw: seen)
    }

    static func noUsage(_ error: Error) -> EstimationError {
        EstimationError(
            reason: .badResponse, what: "the response has no usage",
            expected: "an object with usage (input_tokens, output_tokens)", saw: describe(error))
    }

    static func badResponse(_ error: Error) -> EstimationError {
        EstimationError(
            reason: .badResponse, what: "the response is not a message",
            expected: "an object with content and stop_reason", saw: describe(error))
    }

    static let refusal = EstimationError(
        reason: .refusal, what: "the model declined the request",
        expected: "a reply with the items", saw: "stop reason refusal")

    static func cutOff(outputTokens: Int) -> EstimationError {
        EstimationError(
            reason: .maxTokens, what: "the reply was cut off",
            expected: "a finished reply", saw: "stop reason max_tokens after \(outputTokens) output tokens")
    }

    static let emptyText = EstimationError(
        reason: .emptyText, what: "the reply has no text", expected: "one JSON object", saw: "no text")

    static func notJSON(_ error: JSONSyntaxError, text: String) -> EstimationError {
        EstimationError(
            reason: .notJSON, what: "the reply is not one JSON object", expected: "one JSON object",
            saw: "\(error.message) at byte \(error.offset) of \(excerpt(text))")
    }

    static func notObject(_ value: JSONValue) -> EstimationError {
        EstimationError(
            reason: .notObject, what: "the reply is not a JSON object",
            expected: "an object with the key items", saw: kind(of: value))
    }

    static func wrongKeys(_ place: String, expected: [String], saw value: JSONValue) -> EstimationError {
        var seen = kind(of: value)
        if case .object(let members) = value {
            seen = members.isEmpty ? "no keys" : "the keys \(members.keys.sorted().joined(separator: ", "))"
        }
        return EstimationError(
            reason: .wrongKeys, what: "\(place) has the wrong keys",
            expected: "exactly the keys \(expected.joined(separator: ", "))", saw: seen)
    }

    static func badValue(_ place: String, expected: String, saw: String) -> EstimationError {
        EstimationError(reason: .badValue, what: "\(place) is not valid", expected: expected, saw: saw)
    }

    static func tooManyItems(_ count: Int) -> EstimationError {
        EstimationError(
            reason: .tooManyItems, what: "the list of items is too long",
            expected: "at most \(Limits.maxItems) items", saw: "\(count) items")
    }
}

func kind(of value: JSONValue) -> String {
    switch value {
    case .object: "an object"
    case .array: "a list"
    case .string: "a string"
    case .number: "a number"
    case .bool: "a boolean"
    case .null: "null"
    }
}

private func excerpt(_ text: String) -> String {
    let limit = 60
    let shown = text.prefix(limit)
    return "\"\(shown)\(text.count > limit ? "..." : "")\""
}

private func describe(_ error: Error) -> String {
    switch error {
    case DecodingError.keyNotFound(let key, _): "no key \(key.stringValue)"
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
        DecodingError.dataCorrupted(let context):
        context.debugDescription
    default: String(describing: error)
    }
}
