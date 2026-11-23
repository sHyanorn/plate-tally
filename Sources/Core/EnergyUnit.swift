/// A unit of energy the user can type. Australian labels give kJ; an item stores kcal. The raw value is the
/// symbol on the screen.
public enum EnergyUnit: String, Sendable, CaseIterable {
    case kcal
    case kJ

    /// kJ per kcal on a food label: kcal = kJ / 4.18. Australia New Zealand Food Standards Code, Schedule 11,
    /// section S11-2(4), https://www.legislation.gov.au/F2015L00481/latest/text
    public static let kilojoulesPerKilocalorie = 4.18

    /// The kcal that a value in this unit holds.
    public func kcal(_ value: Double) -> Double {
        switch self {
        case .kcal: value
        case .kJ: value / Self.kilojoulesPerKilocalorie
        }
    }

    /// A value in kcal, given in this unit.
    public func value(ofKcal kcal: Double) -> Double {
        switch self {
        case .kcal: kcal
        case .kJ: kcal * Self.kilojoulesPerKilocalorie
        }
    }
}

/// An energy as the user typed it: the text of the field and the unit of that field.
public struct TypedEnergy: Equatable, Sendable {
    public let unit: EnergyUnit
    public let text: String

    public init(unit: EnergyUnit, text: String) {
        self.unit = unit
        self.text = text
    }

    /// The kcal the text holds. A text that is not a number is refused with the name of its field.
    public func kcal(field: String) throws(NumberError) -> Double {
        unit.kcal(try Number.parse(text, field: field))
    }
}
