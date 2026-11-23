import Core
import Foundation
import Testing

@testable import Ledger

let rice = FoodItem(name: "rice", grams: 150, kcal: 195)
let peas = FoodItem(name: "peas", grams: 80, kcal: 64)
let melon = FoodItem(name: "melon", grams: 200, kcal: 60)

func mealID(_ number: Int) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", number))")!
}

func meal(_ items: [FoodItem], id: Int = 1, at: String = "2026-11-23T12:30") throws -> Meal {
    Meal(id: mealID(id), at: try LocalDateTime(at), items: items)
}

@Suite struct FoodItemGramsTests {
    @Test func gramsScaleTheKcalInProportion() throws {
        let after = try rice.settingGrams(to: 300)
        #expect(after == FoodItem(name: "rice", grams: 300, kcal: 390))
        #expect(after.kcalPer100g == 130)
    }

    @Test func halvingTheGramsHalvesTheKcal() throws {
        #expect(try rice.settingGrams(to: 75).kcal == 97.5)
    }

    /// 7 kcal at 25 g set to 100 g is exactly 28 when the product comes first. The quotient first gives
    /// 28.000000000000004.
    @Test func theProductComesBeforeTheDivision() throws {
        #expect(try FoodItem(name: "x", grams: 25, kcal: 7).settingGrams(to: 100).kcal == 28)
    }

    @Test func aKcalTypedFirstIsTheBaseOfTheNextScaling() throws {
        #expect(try FoodItem(name: "rice", grams: 100, kcal: 200).settingGrams(to: 150).kcal == 300)
    }

    @Test func zeroKcalStaysZero() throws {
        #expect(try FoodItem(name: "water", grams: 100, kcal: 0).settingGrams(to: 500).kcal == 0)
    }

    @Test func scaledKcalAtTheUpperBoundIsAcceptedAndPastItRefused() throws {
        let item = FoodItem(name: "oil", grams: 100, kcal: 2500)
        #expect(try item.settingGrams(to: 200).kcal == 5000)
        let error = #expect(throws: LedgerError.self) { try item.settingGrams(to: 200.5) }
        #expect(error == .scaledKcal(name: "oil", grams: 200.5, kcal: 5012.5))
    }

    /// Scaling by a ratio and then by its inverse is off by one ulp for these grams.
    @Test(arguments: [(1541.3, 1324.1), (1797.0, 1648.6), (592.5, 138.1)])
    func anItemAtTheUpperBoundCanBeRestoredAfterAChangeOfTheGrams(start: Double, other: Double) throws {
        let oil = FoodItem(name: "oil", grams: start, kcal: 5000)
        let changed = try oil.settingGrams(to: other)
        #expect(changed.kcal < 5000)
        #expect(try changed.settingGrams(to: start) == oil)
    }

    @Test func aScaledKcalJustPastTheUpperBoundIsTheBoundAndFurtherPastIsRefused() throws {
        let oil = FoodItem(name: "oil", grams: 100, kcal: 5000)
        #expect(try oil.settingGrams(to: 100.00000000001).kcal == 5000)
        #expect(throws: LedgerError.self) { try oil.settingGrams(to: 100.000000001) }
    }

    /// 0.1 kcal at 3 g, scaled by 3 / 3, is 0.10000000000000002.
    @Test func theSameGramsLeaveTheItemAsItIs() throws {
        let item = FoodItem(name: "x", grams: 3, kcal: 0.1)
        #expect(try item.settingGrams(to: 3) == item)
    }

    @Test func aRefusedScalingNamesTheItemTheGramsAndTheKcal() throws {
        let item = FoodItem(name: "oil", grams: 100, kcal: 4000)
        let error = #expect(throws: LedgerError.self) { try item.settingGrams(to: 2000) }
        #expect(
            error?.description
                == "changing the grams of \"oil\" to 2000 puts its kcal out of range: expected a number from 0 to 5000, saw 80000 kcal")
    }

    @Test(arguments: [(1.0, true), (2000.0, true), (0.999, false), (2000.001, false), (0.0, false), (-5.0, false), (Double.nan, false), (Double.infinity, false)])
    func gramsBoundsAreInclusive(grams: Double, accepted: Bool) throws {
        let item = FoodItem(name: "rice", grams: 100, kcal: 100)
        if accepted {
            #expect(try item.settingGrams(to: grams).grams == grams)
        } else {
            #expect(throws: LedgerError.self) { try item.settingGrams(to: grams) }
        }
    }

    @Test func aBadGramsValueIsReportedAsGramsNotAsKcal() throws {
        let error = #expect(throws: LedgerError.self) { try rice.settingGrams(to: 2000.001) }
        #expect(error?.description == "the grams are out of range: expected a number from 1 to 2000, saw 2000.001")
    }
}

@Suite struct RemoveAndAddTests {
    @Test func removingTakesOutTheNamedItemOnly() throws {
        let after = try meal([rice, peas, melon]).removingItem(at: 1)
        #expect(after.items == [rice, melon])
        #expect(after.totalKcal == 255)
    }

    @Test func theLastItemMayGo() throws {
        #expect(try meal([rice]).removingItem(at: 0).items == [])
    }

    @Test func addingAppendsAtTheEnd() throws {
        let after = try meal([rice]).adding(peas)
        #expect(after.items == [rice, peas])
        #expect(after.totalKcal == 259)
    }

    @Test func aMealMayHoldTwentyItemsAndNoMore() throws {
        let nineteen = try meal(Array(repeating: peas, count: 19))
        let twenty = try nineteen.adding(rice)
        #expect(twenty.items.count == 20)
        let error = #expect(throws: LedgerError.self) { try twenty.adding(rice) }
        #expect(error == .tooManyItems(21))
        #expect(error?.description == "the meal has too many items: expected at most 20 items, saw 21 items")
    }

    @Test(arguments: [
        FoodItem(name: "", grams: 100, kcal: 100), FoodItem(name: "  ", grams: 100, kcal: 100),
        FoodItem(name: "x", grams: 0.999, kcal: 100), FoodItem(name: "x", grams: 2000.001, kcal: 100),
        FoodItem(name: "x", grams: 100, kcal: -0.001), FoodItem(name: "x", grams: 100, kcal: 5000.001),
        FoodItem(name: "x", grams: .nan, kcal: 100), FoodItem(name: "x", grams: 100, kcal: .nan),
    ])
    func anAddedItemKeepsTheBounds(item: FoodItem) throws {
        #expect(throws: LedgerError.self) { try meal([]).adding(item) }
    }

    @Test(arguments: [
        FoodItem(name: "x", grams: 1, kcal: 0), FoodItem(name: "x", grams: 2000, kcal: 5000),
    ])
    func anAddedItemAtTheBoundsIsAccepted(item: FoodItem) throws {
        #expect(try meal([]).adding(item).items == [item])
    }
}

@Suite struct IndexTests {
    @Test(arguments: [-1, 2, 3, 100])
    func everyEditRefusesAnIndexOutsideTheItems(index: Int) throws {
        let two = try meal([rice, peas])
        let expected = LedgerError.itemIndex(index, count: 2)
        #expect(throws: expected) { try two.replacingItem(at: index, with: melon) }
        #expect(throws: expected) { try two.removingItem(at: index) }
    }

    @Test func theFirstAndLastIndexAreInside() throws {
        let two = try meal([rice, peas])
        #expect(throws: Never.self) { try two.removingItem(at: 0) }
        #expect(throws: Never.self) { try two.removingItem(at: 1) }
    }

    @Test func theMessageStatesWhatWasExpectedAndSeen() throws {
        let error = #expect(throws: LedgerError.self) { try meal([rice, peas]).removingItem(at: 2) }
        #expect(error?.description == "the item index is out of range: expected an index of at least 0 and below 2, saw 2")
        let empty = #expect(throws: LedgerError.self) { try meal([]).removingItem(at: 0) }
        #expect(empty?.description == "the item index is out of range: expected an index of at least 0 and below 0, saw 0")
    }
}
