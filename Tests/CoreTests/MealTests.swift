import Foundation
import Testing

@testable import Core

@Suite struct MealTests {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func meal(_ items: [FoodItem]) throws -> Meal {
        Meal(id: id, at: try LocalDateTime("2026-11-23T12:30"), items: items)
    }

    @Test func totalIsTheSumOfTheItems() throws {
        let rice = FoodItem(name: "rice", grams: 150, kcal: 195)
        let peas = FoodItem(name: "peas", grams: 80, kcal: 64.5)
        #expect(try meal([rice, peas]).totalKcal == 259.5)
        #expect(try meal([]).totalKcal == 0)
    }

    @Test func totalFollowsAChangeOfAnItem() throws {
        var saved = try meal([FoodItem(name: "rice", grams: 100, kcal: 130)])
        saved.items[0].kcal = 200
        #expect(saved.totalKcal == 200)
    }

    @Test func energyPer100gIsDerivedFromTheItem() {
        #expect(FoodItem(name: "rice", grams: 150, kcal: 195).kcalPer100g == 130)
        #expect(FoodItem(name: "oil", grams: 10, kcal: 88).kcalPer100g == 880)
    }

    @Test func recordRoundTripsThroughJSON() throws {
        let saved = try meal([
            FoodItem(name: "rice", grams: 150, kcal: 195), FoodItem(name: "caf\u{E9}", grams: 80.5, kcal: 64.25),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(saved)
        #expect(try JSONDecoder().decode(Meal.self, from: data) == saved)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""at":"2026-11-23T12:30""#))
        #expect(text.contains(#""id":"00000000-0000-0000-0000-000000000001""#))
        #expect(!text.contains("total"))
    }
}
