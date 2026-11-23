/// One food of a meal: weight and energy for that weight, as the model gave them or the user typed them.
public struct FoodItem: Equatable, Sendable, Codable {
    public var name: String
    public var grams: Double
    public var kcal: Double

    public init(name: String, grams: Double, kcal: Double) {
        self.name = name
        self.grams = grams
        self.kcal = kcal
    }

    /// Derived, not stored: a stored copy could disagree with `kcal` after an edit.
    public var kcalPer100g: Double { kcal * 100 / grams }
}

/// The tokens a call was billed for, from the `usage` fields of the response.
public struct Usage: Equatable, Sendable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
