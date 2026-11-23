import Core
import Foundation

/// USD per million tokens.
struct Price: Equatable, Sendable {
    public let input: Decimal
    public let output: Decimal
}

public enum Pricing {
    /// The day the prices below were read on the vendor's pricing page (SPEC, Cost).
    public static let readOn = "2026-11-22"

    /// Whole dollars, built from integers: a Decimal made from a float literal would carry a binary fraction.
    static let table: [String: Price] = [
        "claude-sonnet-5-5": Price(input: Decimal(2), output: Decimal(10))
    ]

    /// The price of a call in USD, exact (R17). `model` is the id the app sent, `Estimation.model`.
    public static func cost(of usage: Usage, model: String) throws(CostError) -> Decimal {
        guard let price = table[model] else { throw .unknownModel(model, known: table.keys.sorted()) }
        let input: Decimal = Decimal(usage.inputTokens) * price.input / Decimal(1_000_000)
        let output: Decimal = Decimal(usage.outputTokens) * price.output / Decimal(1_000_000)
        return input + output
    }
}
