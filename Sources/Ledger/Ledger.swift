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

extension Ledger: StoredValue {
    private struct File: Codable {
        var version: Int
        var meals: [Meal]
    }

    /// A file is held to what an edit keeps (D013), on the way out as on the way in. A ledger that
    /// decoding would refuse is not written: a file that cannot be read stops the start for good.
    public func encoded() throws(FormatError) -> Data {
        try Self.requireStorable(meals)
        return try StoredFile.encode(File(version: StoredFile.version, meals: meals))
    }

    /// Each refusal is a `FormatError` that names the place in the file.
    public init(decoding data: Data) throws(FormatError) {
        let file = try StoredFile.decode(File.self, from: data)
        try Self.requireStorable(file.meals)
        self.meals = file.meals
    }

    /// Each meal id once and the bounds of R5 for every item.
    private static func requireStorable(_ meals: [Meal]) throws(FormatError) {
        var firstAt: [UUID: Int] = [:]
        for (m, meal) in meals.enumerated() {
            if let first = firstAt[meal.id] {
                throw FormatError(
                    what: "the file holds a meal id twice", expected: "each meal id once",
                    saw: "\(meal.id.uuidString) at meals.Index \(first).id and meals.Index \(m).id")
            }
            firstAt[meal.id] = m
            guard meal.items.count <= Limits.maxItems else {
                throw Self.refusal(.tooManyItems(meal.items.count), at: "meals.Index \(m).items")
            }
            for (i, item) in meal.items.enumerated() {
                do {
                    try Meal.requireInBounds(item)
                } catch {
                    throw Self.refusal(error, at: "meals.Index \(m).items.Index \(i)")
                }
            }
        }
    }

    private static func refusal(_ error: LedgerError, at path: String) -> FormatError {
        FormatError(what: error.what, expected: error.expected, saw: "\(error.saw) at \(path)")
    }
}
