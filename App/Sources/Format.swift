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

/// R9: every energy figure is an estimate, so it carries the approximation sign. A sum of nothing is exactly 0.
func kcalText(_ kcal: Double) -> String {
    if kcal == 0 { return "0 kcal" }
    return "≈ \(wholeKcal(kcal)) kcal"
}

func estimateSign(_ kcal: Double) -> String {
    kcal == 0 ? "" : "≈"
}

/// Whole kcal with the grouping of the region: 1,275.
func wholeKcal(_ kcal: Double) -> String {
    kcal.formatted(.number.precision(.fractionLength(0)))
}

func gramsText(_ grams: Double) -> String {
    "\(grams.formatted(.number.precision(.fractionLength(0...1)))) g"
}
