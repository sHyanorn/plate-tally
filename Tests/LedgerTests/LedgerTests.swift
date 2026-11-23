import Core
import Foundation
import Testing

@testable import Ledger

private func ledger(_ meals: Meal...) throws -> Ledger {
    var ledger = Ledger()
    for meal in meals { try ledger.add(meal) }
    return ledger
}

private func day(_ text: String) throws -> LocalDay { try LocalDay(text) }

private let riceMealJSON =
    #"{"at":"2026-11-23T12:30","id":"00000000-0000-0000-0000-000000000001","items":[{"grams":150,"kcal":195,"name":"rice"}]}"#
private let oneMeal = #"{"meals":[\#(riceMealJSON)],"version":1}"#

@Suite struct LedgerOperationTests {
    @Test func aNewLedgerIsEmpty() {
        #expect(Ledger().meals == [])
    }

    @Test func addKeepsTheMealsInTheOrderOfAdding() throws {
        let first = try meal([rice], id: 1)
        let second = try meal([peas], id: 2, at: "2026-11-23T08:00")
        #expect(try ledger(first, second).meals == [first, second])
    }

    @Test func aMealIdCannotBeAddedTwice() throws {
        var saved = try ledger(try meal([rice], id: 1))
        let error = #expect(throws: LedgerError.self) { try saved.add(try meal([peas], id: 1)) }
        #expect(error == .duplicateID(mealID(1)))
        #expect(
            error?.description
                == "a meal with this id is already in the ledger: expected an id that is not in the ledger, saw 00000000-0000-0000-0000-000000000001"
        )
        #expect(saved.meals.count == 1)
    }

    @Test func replaceSwapsTheMealWithTheSameIdAndKeepsItsPlace() throws {
        var saved = try ledger(try meal([rice], id: 1), try meal([peas], id: 2), try meal([melon], id: 3))
        let edited = try meal([rice], id: 2).renamingItem(at: 0, to: "lentil")
        try saved.replace(edited)
        #expect(saved.meals.map(\.id) == (1...3).map(mealID))
        #expect(saved.meals[1] == edited)
        #expect(saved.meals.count == 3)
    }

    @Test func replaceOfAnUnknownIdIsAnError() throws {
        var saved = try ledger(try meal([rice], id: 1))
        let error = #expect(throws: LedgerError.self) { try saved.replace(try meal([peas], id: 9)) }
        #expect(
            error?.description
                == "no meal in the ledger has this id: expected the id of a meal in the ledger, saw 00000000-0000-0000-0000-000000000009"
        )
        #expect(saved.meals.map(\.items) == [[rice]])
    }

    @Test func deleteRemovesTheMealWithThatIdOnly() throws {
        var saved = try ledger(try meal([rice], id: 1), try meal([peas], id: 2), try meal([melon], id: 3))
        try saved.delete(id: mealID(2))
        #expect(saved.meals.map(\.items) == [[rice], [melon]])
    }

    @Test func deleteOfAnUnknownIdIsAnError() throws {
        var saved = try ledger(try meal([rice], id: 1))
        #expect(throws: LedgerError.unknownID(mealID(9))) { try saved.delete(id: mealID(9)) }
        #expect(saved.meals.count == 1)
    }
}

@Suite struct DayTests {
    @Test func mealsOfADayComeByTimeWhateverTheOrderOfAdding() throws {
        let dinner = try meal([rice], id: 1, at: "2026-11-23T19:00")
        let breakfast = try meal([peas], id: 2, at: "2026-11-23T07:45")
        let lunch = try meal([melon], id: 3, at: "2026-11-23T12:30")
        #expect(try ledger(dinner, breakfast, lunch).meals(on: day("2026-11-23")) == [breakfast, lunch, dinner])
    }

    @Test func mealsOfOneMinuteKeepTheOrderOfAdding() throws {
        let first = try meal([rice], id: 1, at: "2026-11-23T12:30")
        let second = try meal([peas], id: 2, at: "2026-11-23T12:30")
        let earlier = try meal([melon], id: 3, at: "2026-11-23T12:29")
        let saved = try ledger(first, second, earlier)
        #expect(saved.meals(on: try day("2026-11-23")) == [earlier, first, second])
        let reversed = try ledger(second, first)
        #expect(reversed.meals(on: try day("2026-11-23")) == [second, first])
    }

    @Test func aDayHoldsOnlyItsOwnMealsAcrossMidnight() throws {
        let late = try meal([rice], id: 1, at: "2026-11-23T23:59")
        let early = try meal([peas], id: 2, at: "2026-11-24T00:00")
        let saved = try ledger(late, early)
        #expect(saved.meals(on: try day("2026-11-23")) == [late])
        #expect(saved.meals(on: try day("2026-11-24")) == [early])
        #expect(saved.meals(on: try day("2026-11-25")) == [])
    }

    @Test func intakeIsTheSumOfTheItemsOfTheDay() throws {
        let saved = try ledger(
            try meal([rice, peas], id: 1, at: "2026-11-23T12:30"), try meal([melon], id: 2, at: "2026-11-23T19:00"),
            try meal([rice], id: 3, at: "2026-11-24T08:00"))
        #expect(saved.intake(on: try day("2026-11-23")) == 319)
        #expect(saved.intake(on: try day("2026-11-24")) == 195)
        #expect(saved.intake(on: try day("2026-11-25")) == 0)
    }

    @Test func intakeFollowsAnEditAndADeletion() throws {
        var saved = try ledger(try meal([rice, peas], id: 1), try meal([melon], id: 2, at: "2026-11-23T19:00"))
        let today = try day("2026-11-23")
        #expect(saved.intake(on: today) == 319)
        try saved.replace(try meal([rice, peas], id: 1).settingGrams(ofItemAt: 0, to: 300))
        #expect(saved.intake(on: today) == 514)
        try saved.replace(try meal([rice, peas], id: 1).settingGrams(ofItemAt: 0, to: 300).removingItem(at: 1))
        #expect(saved.intake(on: today) == 450)
        try saved.delete(id: mealID(2))
        #expect(saved.intake(on: today) == 390)
    }

    @Test func aDayIsAYearAMonthAndADayNotOnlyADayOfTheMonth() throws {
        let november = try meal([rice], id: 1, at: "2026-11-23T12:00")
        let december = try meal([peas], id: 2, at: "2026-12-23T12:00")
        let lastYear = try meal([melon], id: 3, at: "2025-11-23T12:00")
        let saved = try ledger(november, december, lastYear)
        #expect(saved.meals(on: try day("2026-11-23")) == [november])
        #expect(saved.intake(on: try day("2026-11-23")) == 195)
    }

    @Test func movingAMealToAnotherTimeMovesItToThatDay() throws {
        var saved = try ledger(try meal([rice], id: 1, at: "2026-11-23T23:50"))
        try saved.replace(try meal([rice], id: 1, at: "2026-11-24T00:10"))
        #expect(saved.intake(on: try day("2026-11-23")) == 0)
        #expect(saved.intake(on: try day("2026-11-24")) == 195)
    }
}

@Suite struct LedgerFileTests {
    @Test func theFileIsTheDocumentedJSON() throws {
        let data = try ledger(try meal([rice], id: 1)).encoded()
        #expect(String(decoding: data, as: UTF8.self) == oneMeal)
    }

    @Test func anEmptyLedgerIsAVersionAndAnEmptyList() throws {
        #expect(String(decoding: try Ledger().encoded(), as: UTF8.self) == #"{"meals":[],"version":1}"#)
    }

    @Test func theBytesDoNotChangeFromOneWriteToTheNext() throws {
        let saved = try ledger(try meal([rice, peas], id: 1), try meal([melon], id: 2, at: "2026-11-24T08:00"))
        #expect(try saved.encoded() == saved.encoded())
        #expect(try Ledger(decoding: saved.encoded()).encoded() == saved.encoded())
    }

    @Test func aLedgerRoundTrips() throws {
        let hard = FoodItem(name: "caf\u{E9} \u{1F600} / \"x\"", grams: 33.333333333333336, kcal: 0.1 + 0.2)
        let saved = try ledger(try meal([rice, hard], id: 1), try meal([], id: 2, at: "0001-01-01T00:00"))
        #expect(try Ledger(decoding: saved.encoded()) == saved)
    }

    @Test func aStoredMealHasNoTotalAndNoDensity() throws {
        let text = String(decoding: try ledger(try meal([rice], id: 1)).encoded(), as: UTF8.self)
        #expect(!text.contains("total") && !text.contains("100g") && !text.contains("per100"))
    }

    @Test func aFileOfAnotherVersionIsRefusedWithBothVersions() {
        let error = #expect(throws: FormatError.self) {
            try Ledger(decoding: Data(#"{"meals":[],"version":2}"#.utf8))
        }
        #expect(error?.description == "the file has another version: expected version 1, saw version 2")
    }

    @Test func theVersionIsReadBeforeTheShapeSoANewerFileSaysSo() {
        let error = #expect(throws: FormatError.self) {
            try Ledger(decoding: Data(#"{"version":2,"days":[{"d":1}]}"#.utf8))
        }
        #expect(error?.saw == "version 2")
    }

    @Test(arguments: [
        "", "not json", "[]", "{}", #"{"meals":[]}"#, #"{"version":"1","meals":[]}"#, #"{"version":1.5,"meals":[]}"#,
        #"{"version":1}"#, #"{"version":1,"meals":{}}"#, #"{"version":1,"meals":[{"id":"x"}]}"#,
        #"{"version":1,"meals":[{"at":"2026-02-30T12:00","id":"00000000-0000-0000-0000-000000000001","items":[]}]}"#,
    ])
    func aFileThatIsNotTheFormatIsRefused(text: String) {
        #expect(throws: FormatError.self) { try Ledger(decoding: Data(text.utf8)) }
    }

    @Test func aFileWithTheSameIdTwiceIsRefused() throws {
        let text = #"{"meals":[\#(riceMealJSON),\#(riceMealJSON)],"version":1}"#
        #expect(throws: LedgerError.duplicateID(mealID(1))) { try Ledger(decoding: Data(text.utf8)) }
    }

    @Test func aMealWithAnItemThatCannotBeStoredIsRefusedAtWrite() throws {
        let broken = try meal([FoodItem(name: "x", grams: 1, kcal: .nan)])
        let error = #expect(throws: FormatError.self) { try ledger(broken).encoded() }
        #expect(error?.what == "the data cannot be stored")
    }

    @Test func aReadFileHasTheMealsOfTheFile() throws {
        let saved = try Ledger(decoding: Data(oneMeal.utf8))
        #expect(saved.meals == [try meal([rice], id: 1)])
        #expect(saved.intake(on: try day("2026-11-23")) == 195)
    }
}
