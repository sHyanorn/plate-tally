/// The bounds of R5. The reply of the model and the edits of the user obey the same ones.
public enum Limits {
    public static let maxItems = 20
    public static let nameLength = 1...100
    public static let grams: ClosedRange<Double> = 1...2000
    public static let kcal: ClosedRange<Double> = 0...5000
}
