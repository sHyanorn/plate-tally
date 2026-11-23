import Foundation

/// One saved meal (R11). An edit of the grams of an item scales its kcal by the energy per 100 g
/// that the item has (R10).
public struct Meal: Equatable, Sendable, Codable {
    /// Given by the caller, so the package draws no random numbers.
    public let id: UUID
    public var at: LocalDateTime
    public var items: [FoodItem]

    public init(id: UUID, at: LocalDateTime, items: [FoodItem]) {
        self.id = id
        self.at = at
        self.items = items
    }

    /// The sum of the items, never stored: a stored total could disagree with them.
    public var totalKcal: Double { items.reduce(0) { $0 + $1.kcal } }
}
