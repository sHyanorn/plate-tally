import Foundation

/// A JSON value. An object is a dictionary because a repeated key is an error, so no order is lost.
enum JSONValue: Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

struct JSONSyntaxError: Error, Equatable {
    let offset: Int
    let message: String
}

/// RFC 8259 and nothing more: no comments, no trailing commas, no NaN, no repeated keys.
/// The readers of the standard library differ on Linux (one keeps the first and the other the last
/// of a repeated key, and one reads a boolean as a number). This parser does not depend on them.
enum StrictJSON {
    static func parse(_ text: String) throws(JSONSyntaxError) -> JSONValue {
        var reader = Reader(bytes: Array(text.utf8))
        reader.skipWhitespace()
        let value = try reader.value()
        reader.skipWhitespace()
        guard reader.atEnd else { throw reader.error("\(reader.saw) after the end of the value") }
        return value
    }
}

private enum Byte {
    static let quote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let comma = UInt8(ascii: ",")
    static let colon = UInt8(ascii: ":")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let minus = UInt8(ascii: "-")
    static let plus = UInt8(ascii: "+")
    static let dot = UInt8(ascii: ".")
    static let zero = UInt8(ascii: "0")
    static let nine = UInt8(ascii: "9")
    static let lowerE = UInt8(ascii: "e")
    static let upperE = UInt8(ascii: "E")
    static let lowerU = UInt8(ascii: "u")
}

private struct Reader {
    let bytes: [UInt8]
    var position = 0

    var atEnd: Bool { position >= bytes.count }
    var peek: UInt8? { atEnd ? nil : bytes[position] }

    /// What is at the current position, for an error message.
    var saw: String {
        guard let byte = peek else { return "the end of the text" }
        if byte >= 0x20, byte < 0x7F { return "'\(Character(Unicode.Scalar(byte)))'" }
        return "the byte 0x\(String(byte, radix: 16))"
    }

    func error(_ message: String) -> JSONSyntaxError {
        JSONSyntaxError(offset: position, message: message)
    }

    mutating func skipWhitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            position += 1
        }
    }

    mutating func value() throws(JSONSyntaxError) -> JSONValue {
        guard let byte = peek else { throw error("\(saw) where a value should start") }
        switch byte {
        case Byte.openBrace: return try object()
        case Byte.openBracket: return try array()
        case Byte.quote: return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        case Byte.minus, Byte.zero...Byte.nine: return .number(try number())
        default: throw error("\(saw) where a value should start")
        }
    }

    mutating func literal(_ word: String) throws(JSONSyntaxError) {
        let expected = Array(word.utf8)
        guard bytes[position...].starts(with: expected) else {
            throw error("text that is not the word \(word)")
        }
        position += expected.count
    }

    mutating func object() throws(JSONSyntaxError) -> JSONValue {
        position += 1
        var members: [String: JSONValue] = [:]
        skipWhitespace()
        if peek == Byte.closeBrace {
            position += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard peek == Byte.quote else { throw error("\(saw) where a string key should start") }
            let keyOffset = position
            let key = try string()
            guard members[key] == nil else {
                throw JSONSyntaxError(offset: keyOffset, message: "the key \"\(key)\" is repeated")
            }
            skipWhitespace()
            guard peek == Byte.colon else { throw error("\(saw) where ':' should be") }
            position += 1
            skipWhitespace()
            members[key] = try value()
            skipWhitespace()
            switch peek {
            case Byte.comma: position += 1
            case Byte.closeBrace:
                position += 1
                return .object(members)
            default: throw error("\(saw) where ',' or '}' should be")
            }
        }
    }

    mutating func array() throws(JSONSyntaxError) -> JSONValue {
        position += 1
        var elements: [JSONValue] = []
        skipWhitespace()
        if peek == Byte.closeBracket {
            position += 1
            return .array(elements)
        }
        while true {
            skipWhitespace()
            elements.append(try value())
            skipWhitespace()
            switch peek {
            case Byte.comma: position += 1
            case Byte.closeBracket:
                position += 1
                return .array(elements)
            default: throw error("\(saw) where ',' or ']' should be")
            }
        }
    }

    mutating func string() throws(JSONSyntaxError) -> String {
        position += 1
        var utf8: [UInt8] = []
        while true {
            guard let byte = peek else { throw error("a string that is not closed") }
            switch byte {
            case Byte.quote:
                position += 1
                return String(decoding: utf8, as: UTF8.self)
            case Byte.backslash:
                position += 1
                try escape(into: &utf8)
            case 0..<0x20:
                throw error("a control character in a string")
            default:
                utf8.append(byte)
                position += 1
            }
        }
    }

    mutating func escape(into utf8: inout [UInt8]) throws(JSONSyntaxError) {
        guard let byte = peek else { throw error("an escape that is not finished") }
        let simple: [UInt8: UInt8] = [
            UInt8(ascii: "\""): 0x22, UInt8(ascii: "\\"): 0x5C, UInt8(ascii: "/"): 0x2F,
            UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "n"): 0x0A,
            UInt8(ascii: "r"): 0x0D, UInt8(ascii: "t"): 0x09,
        ]
        if let decoded = simple[byte] {
            utf8.append(decoded)
            position += 1
        } else if byte == Byte.lowerU {
            position += 1
            utf8.append(contentsOf: Array(String(try unicodeEscape()).utf8))
        } else {
            throw error("an unknown escape \(saw)")
        }
    }

    /// The scalar of \uXXXX, with the low half of a surrogate pair read from a second \uXXXX.
    mutating func unicodeEscape() throws(JSONSyntaxError) -> Unicode.Scalar {
        let first = try hexFour()
        var code = first
        if (0xD800...0xDBFF).contains(first) {
            guard peek == Byte.backslash, position + 1 < bytes.count, bytes[position + 1] == Byte.lowerU
            else { throw error("a high surrogate without a low surrogate after it") }
            position += 2
            let second = try hexFour()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw error("a high surrogate followed by a value that is not a low surrogate")
            }
            code = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
        }
        guard let scalar = Unicode.Scalar(code) else { throw error("a lone low surrogate") }
        return scalar
    }

    mutating func hexFour() throws(JSONSyntaxError) -> UInt32 {
        var code: UInt32 = 0
        for _ in 0..<4 {
            guard let byte = peek, let digit = Character(Unicode.Scalar(byte)).hexDigitValue else {
                throw error("\(saw) where a hex digit should be")
            }
            code = code << 4 | UInt32(digit)
            position += 1
        }
        return code
    }

    mutating func number() throws(JSONSyntaxError) -> Double {
        let start = position
        if peek == Byte.minus { position += 1 }
        guard let first = peek, (Byte.zero...Byte.nine).contains(first) else {
            throw error("\(saw) where a digit should be")
        }
        if first == Byte.zero { position += 1 } else { skipDigits() }
        if peek == Byte.dot {
            position += 1
            try requireDigits()
        }
        if peek == Byte.lowerE || peek == Byte.upperE {
            position += 1
            if peek == Byte.plus || peek == Byte.minus { position += 1 }
            try requireDigits()
        }
        // A number too large for a Double reads as infinity. The range check of the reply rejects it.
        let text = String(decoding: bytes[start..<position], as: UTF8.self)
        guard let value = Double(text) else {
            throw JSONSyntaxError(offset: start, message: "the number \(text) cannot be read")
        }
        return value
    }

    mutating func skipDigits() {
        while let byte = peek, (Byte.zero...Byte.nine).contains(byte) { position += 1 }
    }

    mutating func requireDigits() throws(JSONSyntaxError) {
        guard let byte = peek, (Byte.zero...Byte.nine).contains(byte) else {
            throw error("\(saw) where a digit should be")
        }
        skipDigits()
    }
}
