import Core
import Foundation

/// The saved meals (R11, R12). A value: the app holds one and writes `encoded()` to its file.
public struct Ledger: Equatable, Sendable {
    public private(set) var meals: [Meal] = []

    public init() {}

    public mutating func add(_ meal: Meal) throws(LedgerError) {
        guard !meals.contains(where: { $0.id == meal.id }) else { throw .duplicateID(meal.id) }
        meals.append(meal)
    }

    /// Swaps the meal with the same id, in place, so the order of adding is kept.
    public mutating func replace(_ meal: Meal) throws(LedgerError) {
        let found = try position(of: meal.id)
        meals[found] = meal
    }

    public mutating func delete(id: UUID) throws(LedgerError) {
        meals.remove(at: try position(of: id))
    }

    /// The meals of a day by time. Meals of one minute keep the order in which they were added.
    public func meals(on day: LocalDay) -> [Meal] {
        meals.enumerated().filter { $0.element.at.day == day }
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    /// The sum of the day's items, worked out on demand so that an edit is always in it.
    public func intake(on day: LocalDay) -> Double {
        meals(on: day).reduce(0) { $0 + $1.totalKcal }
    }

    private func position(of id: UUID) throws(LedgerError) -> Int {
        guard let found = meals.firstIndex(where: { $0.id == id }) else { throw .unknownID(id) }
        return found
    }
}

extension Ledger {
    private struct File: Codable {
        var version: Int
        var meals: [Meal]
    }

    public func encoded() throws(FormatError) -> Data {
        try StoredFile.encode(File(version: StoredFile.version, meals: meals))
    }

    /// Throws `FormatError` for a file that is not version 1 of the format, and `LedgerError` for one
    /// that holds a meal id twice.
    public init(decoding data: Data) throws {
        let file = try StoredFile.decode(File.self, from: data)
        self.init()
        for meal in file.meals { try add(meal) }
    }
}
