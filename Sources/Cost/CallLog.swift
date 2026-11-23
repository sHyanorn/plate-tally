import Core
import Foundation

/// One call that the API billed. Only a call with `usage` has one: a call that fails before a
/// message comes back costs nothing and is not logged, nor does it count against the limit.
public struct CallRecord: Equatable, Sendable {
    public let at: LocalDateTime
    public let model: String
    public let usage: Usage
    /// Worked out when the call is made and kept, so a later change of the prices cannot rewrite the past.
    public let costUSD: Decimal

    public init(at: LocalDateTime, model: String, usage: Usage) throws(CostError) {
        self.at = at
        self.model = model
        self.usage = usage
        self.costUSD = try Pricing.cost(of: usage, model: model)
    }
}

extension CallRecord: Codable {
    private enum Keys: String, CodingKey {
        case at, model, usage, costUSD
    }

    /// A Decimal encodes as a JSON number, which another reader takes for a binary fraction, so the
    /// cost is stored as text. `Decimal(string:)` reads a prefix and stops at the first stray
    /// character, so the text is checked first.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: Keys.self)
        let text = try values.decode(String.self, forKey: .costUSD)
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
            parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
            let cost = Decimal(string: text)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .costUSD, in: values, debugDescription: "expected a decimal number as text, saw \"\(text)\"")
        }
        self.at = try values.decode(LocalDateTime.self, forKey: .at)
        self.model = try values.decode(String.self, forKey: .model)
        self.usage = try values.decode(Usage.self, forKey: .usage)
        self.costUSD = cost
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: Keys.self)
        try values.encode(at, forKey: .at)
        try values.encode(model, forKey: .model)
        try values.encode(usage, forKey: .usage)
        try values.encode("\(costUSD)", forKey: .costUSD)
    }
}

/// The calls made, for the cost totals (R18) and the daily limit (R19).
public struct CallLog: Equatable, Sendable {
    public static let defaultDailyLimit = 30

    public private(set) var calls: [CallRecord] = []

    public init() {}

    public mutating func add(_ call: CallRecord) {
        calls.append(call)
    }

    public func count(on day: LocalDay) -> Int {
        calls.count { $0.at.day == day }
    }

    public func total(on day: LocalDay) -> Decimal {
        calls.filter { $0.at.day == day }.reduce(Decimal.zero) { $0 + $1.costUSD }
    }

    /// The month of `day`: same year, same month.
    public func total(inMonthOf day: LocalDay) -> Decimal {
        calls.filter { $0.at.day.year == day.year && $0.at.day.month == day.month }
            .reduce(Decimal.zero) { $0 + $1.costUSD }
    }

    /// Throws when the day already has `limit` calls (R19). The caller passes the limit of the settings.
    public func requireRoom(on day: LocalDay, limit: Int) throws(CostError) {
        let used = count(on: day)
        guard used < limit else { throw .limitReached(limit: limit, count: used) }
    }
}

extension CallLog {
    private struct File: Codable {
        var version: Int
        var calls: [CallRecord]
    }

    public func encoded() throws(FormatError) -> Data {
        try StoredFile.encode(File(version: StoredFile.version, calls: calls))
    }

    public init(decoding data: Data) throws(FormatError) {
        self.init()
        self.calls = try StoredFile.decode(File.self, from: data).calls
    }
}
