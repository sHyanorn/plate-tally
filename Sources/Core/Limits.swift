import Foundation

/// The bounds of R5. The reply of the model and the edits of the user obey the same ones.
public enum Limits {
    public static let maxItems = 20
    public static let nameLength = 1...100
    public static let grams: ClosedRange<Double> = 1...2000
    public static let kcal: ClosedRange<Double> = 0...5000

    /// The length of a name as R5 counts it: Unicode scalars after surrounding whitespace is removed,
    /// so one emoji with joiners counts as several, as in the evaluation.
    public static func nameLength(of name: String) -> Int {
        name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
    }
}
