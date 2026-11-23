import Core
import Foundation

extension Problem {
    /// The three parts of the error as one sentence for a screen. The reason code is shown by the caller.
    var message: String {
        let text = "\(what): expected \(expected), saw \(saw)"
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

/// A price of one call is a fraction of a cent, so four decimals.
func usd(_ amount: Decimal) -> String {
    amount.formatted(.currency(code: "USD").precision(.fractionLength(4)))
}
