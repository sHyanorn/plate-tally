import Core
import Cost
import Energy
import Foundation

/// The language of the screens. The app starts in Chinese whatever the language of the device is.
public enum Language: String, Sendable, Codable, CaseIterable {
    case chinese = "zh-Hans"
    case english = "en"

    public var locale: Locale { Locale(identifier: rawValue) }
}

/// What the user sets (R13, R19): the language, the profile, the activity factor and the daily call limit.
/// The key is not here, because the package never holds it (R23).
public struct UserSettings: Equatable, Sendable, Codable {
    public static let dailyLimits = 1...100

    public var heightCm: Double?
    public var weightKg: Double?
    public var ageYears: Int?
    /// Unset until the user picks one: a default would change the estimate without being seen.
    public var sex: Sex?
    public var activity: ActivityLevel = .light
    public var dailyCallLimit = CallLog.defaultDailyLimit
    public var language = Language.chinese

    public init() {}

    /// The profile of R13, or nil until the four values are there and above 0. Expenditure needs all four.
    public var profile: Profile? {
        guard let heightCm, heightCm > 0, let weightKg, weightKg > 0, let ageYears, ageYears > 0, let sex else {
            return nil
        }
        return Profile(heightCm: heightCm, weightKg: weightKg, ageYears: ageYears, sex: sex, activity: activity)
    }

    fileprivate func validate() throws(FormatError) {
        guard Self.dailyLimits.contains(dailyCallLimit) else {
            throw FormatError(
                what: "the daily call limit is out of range",
                expected: "\(Self.dailyLimits.lowerBound) to \(Self.dailyLimits.upperBound)",
                saw: "\(dailyCallLimit)")
        }
    }
}

extension UserSettings: StoredValue {
    private struct File: Codable {
        var version: Int
        var settings: UserSettings
    }

    public func encoded() throws(FormatError) -> Data {
        try validate()
        return try StoredFile.encode(File(version: StoredFile.version, settings: self))
    }

    public init(decoding data: Data) throws(FormatError) {
        self = try StoredFile.decode(File.self, from: data).settings
        try validate()
    }
}
