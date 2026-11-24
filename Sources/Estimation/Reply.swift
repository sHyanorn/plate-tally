import Core
import Foundation

/// What one call gave back. `usage` is there for every reply that has one, whether or not the items
/// are valid, because a failed call is billed all the same.
public struct Reply: Equatable, Sendable {
    public let usage: Usage
    public let items: Result<[FoodItem], EstimationError>
}

extension Estimation {
    /// Judges the response of the API. The usage is read first and on its own: a response that states its
    /// tokens was billed, whatever else is wrong with it, so it gives a `Reply` and the call is costed, logged
    /// and counted (SPEC, Cost). A response without usage throws. Anything else that is wrong, a status other
    /// than 200 included, is a failure inside `items`.
    public static func read(status: Int, body: Data) throws(EstimationError) -> Reply {
        let usage: Usage
        do {
            let counts = try JSONDecoder().decode(Billed.self, from: body).usage
            usage = Usage(inputTokens: counts.inputTokens, outputTokens: counts.outputTokens)
        } catch {
            guard status == 200 else { throw .http(status: status, body: body) }
            throw .noUsage(error)
        }
        return Reply(
            usage: usage,
            items: Result { () throws(EstimationError) in try items(status: status, body: body, usage: usage) })
    }

    private static func items(status: Int, body: Data, usage: Usage) throws(EstimationError) -> [FoodItem] {
        guard status == 200 else { throw .http(status: status, body: body) }
        let message: Message
        do {
            message = try JSONDecoder().decode(Message.self, from: body)
        } catch {
            throw .badResponse(error)
        }
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
    /// The lines are compared scalar by scalar, as the evaluation compares code points: as Swift strings,
    /// three U+1FEF, which decomposes to the backtick, equal "```".
    static func unfence(_ text: String) -> String {
        // Lines end at the scalar \n, as in the evaluation. Swift reads "\r\n" as one Character, so a
        // split on Characters would not see the end of a line that has it.
        let lines = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
        let fence = "```".unicodeScalars
        guard lines.count >= 3, lines[lines.count - 1].elementsEqual(fence), lines[0].starts(with: fence),
            lines[0].dropFirst(3).allSatisfy(isWordCharacter)
        else { return text }
        return lines[1..<(lines.count - 1)].map { String($0) }.joined(separator: "\n")
    }

    /// \w of the evaluation's `re` for one code point: a letter (Lu, Ll, Lt, Lm, Lo), a scalar with a
    /// numeric value, or "_". Unicode data newer than that of the evaluation's Python can still differ.
    private static func isWordCharacter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
        default: scalar.properties.numericType != nil || scalar == "_"
        }
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
        let length = Limits.nameLength(of: name)
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

/// The part of a response that says what the call was billed.
private struct Billed: Decodable {
    struct TokenCounts: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        /// A count below 0 is not a count. Its cost would be below 0, and the call log refuses such a cost.
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try values.decode(Int.self, forKey: .inputTokens)
            outputTokens = try values.decode(Int.self, forKey: .outputTokens)
            for (key, count) in [(CodingKeys.inputTokens, inputTokens), (.outputTokens, outputTokens)] where count < 0 {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: values, debugDescription: "\(key.rawValue) is \(count), below 0")
            }
        }
    }

    let usage: TokenCounts
}

private struct Message: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    let content: [Block]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}
