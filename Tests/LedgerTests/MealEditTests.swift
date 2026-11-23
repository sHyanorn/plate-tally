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

@Suite struct RenameTests {
    @Test func renamingChangesTheNameAndNothingElse() throws {
        let before = try meal([rice, peas])
        let after = try before.renamingItem(at: 0, to: "brown rice")
        #expect(after.items == [FoodItem(name: "brown rice", grams: 150, kcal: 195), peas])
        #expect(after.id == before.id && after.at == before.at)
    }

    @Test func aRefusedEditLeavesTheMealAsItWas() throws {
        let before = try meal([rice])
        #expect(throws: LedgerError.self) { try before.renamingItem(at: 0, to: "") }
        #expect(before.items == [rice])
    }

    @Test func theNameIsKeptAsTyped() throws {
        let after = try meal([rice]).renamingItem(at: 0, to: "  rice \n")
        #expect(after.items[0].name == "  rice \n")
    }

    @Test(arguments: [("", 0), ("   \n", 0), (String(repeating: "x", count: 101), 101), (" " + String(repeating: "x", count: 101), 101)])
    func refusesANameOutsideOneToHundredCharacters(name: String, length: Int) throws {
        #expect(throws: LedgerError.name(length: length)) { try meal([rice]).renamingItem(at: 0, to: name) }
    }

    @Test func acceptsNamesOfOneAndOneHundredCharacters() throws {
        let long = "  " + String(repeating: "x", count: 100) + "\n"
        #expect(try meal([rice]).renamingItem(at: 0, to: long).items[0].name == long)
        #expect(try meal([rice]).renamingItem(at: 0, to: "x").items[0].name == "x")
    }

    /// Length counts Unicode scalars, as R5 does for the reply: one family emoji is five.
    @Test func nameLengthCountsScalarsNotGraphemes() throws {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(try meal([rice]).renamingItem(at: 0, to: String(repeating: family, count: 20)).items.count == 1)
        #expect(throws: LedgerError.name(length: 105)) {
            try meal([rice]).renamingItem(at: 0, to: String(repeating: family, count: 21))
        }
    }
}

@Suite struct GramsTests {
    @Test func gramsScaleTheKcalInProportion() throws {
        let after = try meal([rice]).settingGrams(ofItemAt: 0, to: 300)
        #expect(after.items[0] == FoodItem(name: "rice", grams: 300, kcal: 390))
        #expect(after.items[0].kcalPer100g == 130)
        #expect(after.totalKcal == 390)
    }

    @Test func halvingTheGramsHalvesTheKcal() throws {
        #expect(try meal([rice]).settingGrams(ofItemAt: 0, to: 75).items[0].kcal == 97.5)
    }

    /// 130 kcal at 150 g, scaled to 100 g: the product comes first and one division rounds once.
    @Test func theProductComesBeforeTheDivision() throws {
        let item = FoodItem(name: "rice", grams: 150, kcal: 130)
        let kcal = try meal([item]).settingGrams(ofItemAt: 0, to: 100).items[0].kcal
        #expect(kcal == 86.66666666666667)
    }

    @Test func otherItemsAreNotTouched() throws {
        let after = try meal([rice, peas, melon]).settingGrams(ofItemAt: 1, to: 160)
        #expect(after.items == [rice, FoodItem(name: "peas", grams: 160, kcal: 128), melon])
    }

    @Test func aKcalTypedFirstIsTheBaseOfTheNextScaling() throws {
        let typed = try meal([FoodItem(name: "rice", grams: 100, kcal: 130)]).settingKcal(ofItemAt: 0, to: 200)
        #expect(try typed.settingGrams(ofItemAt: 0, to: 150).items[0].kcal == 300)
    }

    @Test func zeroKcalStaysZero() throws {
        let water = FoodItem(name: "water", grams: 100, kcal: 0)
        #expect(try meal([water]).settingGrams(ofItemAt: 0, to: 500).items[0].kcal == 0)
    }

    @Test func scaledKcalAtTheUpperBoundIsAcceptedAndPastItRefused() throws {
        let item = FoodItem(name: "oil", grams: 100, kcal: 2500)
        #expect(try meal([item]).settingGrams(ofItemAt: 0, to: 200).items[0].kcal == 5000)
        let error = #expect(throws: LedgerError.self) { try meal([item]).settingGrams(ofItemAt: 0, to: 200.5) }
        #expect(error == .scaledKcal(name: "oil", grams: 200.5, kcal: 5012.5))
    }

    @Test func aRefusedScalingNamesTheItemTheGramsAndTheKcal() throws {
        let item = FoodItem(name: "oil", grams: 100, kcal: 4000)
        let error = #expect(throws: LedgerError.self) { try meal([item]).settingGrams(ofItemAt: 0, to: 2000) }
        #expect(
            error?.description
                == "changing the grams of \"oil\" to 2000 puts its kcal out of range: expected a number from 0 to 5000, saw 80000 kcal")
    }

    @Test func aRefusedScalingChangesNothing() throws {
        let before = try meal([FoodItem(name: "oil", grams: 100, kcal: 4000)])
        #expect(throws: LedgerError.self) { try before.settingGrams(ofItemAt: 0, to: 2000) }
        #expect(before.items[0] == FoodItem(name: "oil", grams: 100, kcal: 4000))
    }

    @Test(arguments: [(1.0, true), (2000.0, true), (0.999, false), (2000.001, false), (0.0, false), (-5.0, false), (Double.nan, false), (Double.infinity, false)])
    func gramsBoundsAreInclusive(grams: Double, accepted: Bool) throws {
        let item = FoodItem(name: "rice", grams: 100, kcal: 100)
        if accepted {
            #expect(try meal([item]).settingGrams(ofItemAt: 0, to: grams).items[0].grams == grams)
        } else {
            #expect(throws: LedgerError.self) { try meal([item]).settingGrams(ofItemAt: 0, to: grams) }
        }
    }

    @Test func aBadGramsValueIsReportedAsGramsNotAsKcal() throws {
        let error = #expect(throws: LedgerError.self) { try meal([rice]).settingGrams(ofItemAt: 0, to: 2000.001) }
        #expect(error?.description == "the grams are out of range: expected a number from 1 to 2000, saw 2000.001")
    }
}

@Suite struct KcalTests {
    @Test func kcalChangeAndGramsStay() throws {
        let after = try meal([rice, peas]).settingKcal(ofItemAt: 0, to: 250)
        #expect(after.items == [FoodItem(name: "rice", grams: 150, kcal: 250), peas])
        #expect(after.totalKcal == 314)
    }

    @Test(arguments: [(0.0, true), (5000.0, true), (-0.001, false), (5000.001, false), (-1.0, false), (Double.nan, false), (-Double.infinity, false)])
    func kcalBoundsAreInclusive(kcal: Double, accepted: Bool) throws {
        if accepted {
            #expect(try meal([rice]).settingKcal(ofItemAt: 0, to: kcal).items[0].kcal == kcal)
        } else {
            #expect(throws: LedgerError.self) { try meal([rice]).settingKcal(ofItemAt: 0, to: kcal) }
        }
    }

    @Test func aBadKcalValueIsReported() throws {
        let error = #expect(throws: LedgerError.self) { try meal([rice]).settingKcal(ofItemAt: 0, to: 5000.001) }
        #expect(error?.description == "the kcal are out of range: expected a number from 0 to 5000, saw 5000.001")
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
        #expect(throws: expected) { try two.renamingItem(at: index, to: "x") }
        #expect(throws: expected) { try two.settingGrams(ofItemAt: index, to: 100) }
        #expect(throws: expected) { try two.settingKcal(ofItemAt: index, to: 100) }
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
