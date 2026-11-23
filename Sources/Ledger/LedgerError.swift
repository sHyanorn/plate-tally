import Core
import Foundation

/// An edit or a ledger operation that is refused (R10, R12). The three parts follow R26.
public enum LedgerError: PlateError, Equatable {
    case itemIndex(Int, count: Int)
    case name(length: Int)
    case grams(Double)
    case kcal(Double)
    /// The grams are valid but the kcal that follow in proportion are not.
    case scaledKcal(name: String, grams: Double, kcal: Double)
    case tooManyItems(Int)
    case duplicateID(UUID)
    case unknownID(UUID)

    public var what: String {
        switch self {
        case .itemIndex: "the item index is out of range"
        case .name: "the name is not valid"
        case .grams: "the grams are out of range"
        case .kcal: "the kcal are out of range"
        case .scaledKcal(let name, let grams, _):
            "changing the grams of \"\(name)\" to \(plainNumber(grams)) puts its kcal out of range"
        case .tooManyItems: "the meal has too many items"
        case .duplicateID: "a meal with this id is already in the ledger"
        case .unknownID: "no meal in the ledger has this id"
        }
    }

    public var expected: String {
        switch self {
        case .itemIndex(_, let count): "an index of at least 0 and below \(count)"
        case .name:
            "a name of \(Limits.nameLength.lowerBound) to \(Limits.nameLength.upperBound) characters "
                + "after surrounding whitespace is removed"
        case .grams: Self.numberRule(Limits.grams)
        case .kcal, .scaledKcal: Self.numberRule(Limits.kcal)
        case .tooManyItems: "at most \(Limits.maxItems) items"
        case .duplicateID: "an id that is not in the ledger"
        case .unknownID: "the id of a meal in the ledger"
        }
    }

    public var saw: String {
        switch self {
        case .itemIndex(let index, _): "\(index)"
        case .name(let length): "a name of \(length) characters"
        case .grams(let value), .kcal(let value): plainNumber(value)
        case .scaledKcal(_, _, let kcal): "\(plainNumber(kcal)) kcal"
        case .tooManyItems(let count): "\(count) items"
        case .duplicateID(let id), .unknownID(let id): id.uuidString
        }
    }

    private static func numberRule(_ range: ClosedRange<Double>) -> String {
        "a number from \(plainNumber(range.lowerBound)) to \(plainNumber(range.upperBound))"
    }
}
