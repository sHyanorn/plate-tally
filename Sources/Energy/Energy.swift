import Core

public enum Sex: String, Sendable, Codable, CaseIterable {
    case female
    case male
}

/// The four activity factors of D003.
public enum ActivityLevel: String, Sendable, Codable, CaseIterable {
    case atHome
    case light
    case moderate
    case heavy

    public var factor: Double {
        switch self {
        case .atHome: 1.40
        case .light: 1.55
        case .moderate: 1.75
        case .heavy: 2.00
        }
    }
}

public struct Profile: Equatable, Sendable, Codable {
    public var heightCm: Double
    public var weightKg: Double
    public var ageYears: Int
    public var sex: Sex
    public var activity: ActivityLevel

    public init(heightCm: Double, weightKg: Double, ageYears: Int, sex: Sex, activity: ActivityLevel) {
        self.heightCm = heightCm
        self.weightKg = weightKg
        self.ageYears = ageYears
        self.sex = sex
        self.activity = activity
    }
}

public struct EnergyError: PlateError, Equatable {
    public let field: String
    public let value: Double

    public var what: String { "\(field) is out of range" }
    public var expected: String { "a number above 0" }
    public var saw: String { plainNumber(value) }
}

public enum Energy {
    /// Resting energy expenditure in kcal per day. Mifflin et al. 1990 (Am J Clin Nutr 51:241-247),
    /// in the rounded form of the abstract.
    public static func resting(_ profile: Profile) throws -> Double {
        try requirePositive(profile.heightCm, field: "heightCm")
        try requirePositive(profile.weightKg, field: "weightKg")
        try requirePositive(Double(profile.ageYears), field: "ageYears")
        let weight: Double = profile.weightKg
        let height: Double = profile.heightCm
        let age = Double(profile.ageYears)
        let base: Double = 10 * weight + 6.25 * height - 5 * age
        return profile.sex == .male ? base + 5 : base - 161
    }

    /// Estimated daily expenditure in kcal: resting expenditure times the activity factor (R14).
    public static func expenditure(_ profile: Profile) throws -> Double {
        try resting(profile) * profile.activity.factor
    }

    // `value > 0` also rejects NaN, which no comparison with 0 accepts.
    private static func requirePositive(_ value: Double, field: String) throws {
        guard value > 0 else { throw EnergyError(field: field, value: value) }
    }
}
