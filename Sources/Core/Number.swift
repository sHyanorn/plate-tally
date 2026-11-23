import Foundation

/// A field of a form that holds no number.
public struct NumberError: PlateError, Equatable {
    public let field: String
    public let text: String

    public init(field: String, text: String) {
        self.field = field
        self.text = text
    }

    public var what: String { "\(field) is not a number" }
    public var expected: String { "digits with an optional decimal point or comma" }
    public var saw: String { text.isEmpty ? "nothing" : "\"\(text)\"" }
}

public enum Number {
    /// A number as a decimal keypad types it: digits, then at most one point or comma and more digits.
    /// No sign, no exponent and no grouping, so every text that parses has one meaning in every region.
    public static func parse(_ text: String, field: String) throws(NumberError) -> Double {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: { $0 == "." || $0 == "," })
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
            parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let value = Double("\(parts[0]).\(parts.count == 2 && !parts[1].isEmpty ? String(parts[1]) : "0")"),
            value.isFinite
        else { throw NumberError(field: field, text: text) }
        return value
    }
}
