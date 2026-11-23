import Core
import Foundation

/// What one call gave back. `usage` is there for every reply that has one, whether or not the items
/// are valid, because a failed call is billed all the same.
public struct Reply: Equatable, Sendable {
    public let usage: Usage
    public let items: Result<[FoodItem], EstimationError>
}

extension Estimation {
    /// Judges the response of the API. It throws when there is no message with usage to bill, and
    /// returns a `Reply` otherwise; a reply that fails R5 or R6 is a failure inside `items`.
    public static func read(status: Int, body: Data) throws(EstimationError) -> Reply {
        guard status == 200 else { throw .http(status: status, body: body) }
        let message: Message
        do {
            message = try JSONDecoder().decode(Message.self, from: body)
        } catch {
            throw .badResponse(error)
        }
        let usage = Usage(
            inputTokens: message.usage.inputTokens, outputTokens: message.usage.outputTokens)
        return Reply(
            usage: usage,
            items: Result { () throws(EstimationError) in try items(in: message, usage: usage) })
    }

    private static func items(in message: Message, usage: Usage) throws(EstimationError) -> [FoodItem] {
        switch message.stopReason {
        case "refusal": throw .refusal
        case "max_tokens": throw .cutOff(outputTokens: usage.outputTokens)
        default: break
        }
        let text = message.content.filter { $0.type == "text" }.compactMap(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .emptyText }
        let json = unfence(text)
        let value: JSONValue
        do throws(JSONSyntaxError) {
            value = try StrictJSON.parse(json)
        } catch {
            throw .notJSON(error, text: json)
        }
        return try validated(value)
    }

    /// Removes one surrounding code fence: a first line of three backticks with an optional
    /// language word, and a last line of three backticks. Any other wrapper stays and fails to parse.
    static func unfence(_ text: String) -> String {
        // Lines end at the scalar \n, as in the evaluation. Swift reads "\r\n" as one Character, so a
        // split on Characters would not see the end of a line that has it.
        let lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
        guard lines.count >= 3, lines[lines.count - 1] == "```", lines[0].hasPrefix("```"),
            lines[0].dropFirst(3).allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" })
        else { return text }
        return lines[1..<(lines.count - 1)].joined(separator: "\n")
    }

    private static func validated(_ value: JSONValue) throws(EstimationError) -> [FoodItem] {
        guard case .object(let top) = value else { throw .notObject(value) }
        guard top.count == 1, let list = top["items"] else {
            throw .wrongKeys("the reply object", expected: ["items"], saw: value)
        }
        guard case .array(let elements) = list else {
            throw .badValue(
                "items", expected: "a list of at most \(Limits.maxItems) objects", saw: kind(of: list))
        }
        guard elements.count <= Limits.maxItems else { throw .tooManyItems(elements.count) }
        var items: [FoodItem] = []
        for (index, element) in elements.enumerated() {
            items.append(try item(element, place: "items[\(index)]"))
        }
        return items
    }

    private static func item(_ value: JSONValue, place: String) throws(EstimationError) -> FoodItem {
        let keys = ["name", "grams", "kcal"]
        guard case .object(let members) = value, Set(members.keys) == Set(keys),
            let nameValue = members["name"], let gramsValue = members["grams"],
            let kcalValue = members["kcal"]
        else { throw .wrongKeys(place, expected: keys, saw: value) }

        let nameRule = "a string of \(Limits.nameLength.lowerBound) to \(Limits.nameLength.upperBound) "
            + "characters after surrounding whitespace is removed"
        guard case .string(let name) = nameValue else {
            throw .badValue("\(place).name", expected: nameRule, saw: kind(of: nameValue))
        }
        // Characters are Unicode scalars, as in the evaluation, so one emoji with joiners counts as several.
        let length = name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        guard Limits.nameLength.contains(length) else {
            throw .badValue("\(place).name", expected: nameRule, saw: "a string of \(length) characters")
        }
        let grams = try number(gramsValue, in: Limits.grams, place: "\(place).grams")
        let kcal = try number(kcalValue, in: Limits.kcal, place: "\(place).kcal")
        return FoodItem(name: name, grams: grams, kcal: kcal)
    }

    private static func number(
        _ value: JSONValue, in range: ClosedRange<Double>, place: String
    ) throws(EstimationError) -> Double {
        let rule = "a number from \(plainNumber(range.lowerBound)) to \(plainNumber(range.upperBound))"
        guard case .number(let number) = value else {
            throw .badValue(place, expected: rule, saw: kind(of: value))
        }
        guard range.contains(number) else {
            throw .badValue(place, expected: rule, saw: plainNumber(number))
        }
        return number
    }
}

private struct Message: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    struct TokenCounts: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    let content: [Block]
    let stopReason: String?
    let usage: TokenCounts

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case usage
    }
}
