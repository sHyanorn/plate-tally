import Core
import Foundation
import Testing

@testable import Ledger

private func editing(_ item: FoodItem = rice, grams: String? = nil, kcal: String? = nil, name: String? = nil) -> ItemEditor {
    var editor = ItemEditor(editing: item)
    if let grams { editor.gramsText = grams }
    if let kcal { editor.typedKcalText = kcal }
    if let name { editor.name = name }
    return editor
}

@Suite struct EditingAnItemTests {
    @Test func theFormStartsWithTheTextsOfTheItem() {
        let editor = editing()
        #expect(editor.name == "rice")
        #expect(editor.gramsText == "150")
        #expect(editor.kcalText == "195")
        #expect(editor.problem == nil)
        #expect(editor.item() == .success(rice))
    }

    /// R10: a change of the grams scales the kcal in proportion.
    @Test func theEnergyFollowsTheGramsUntilItIsTyped() {
        let editor = editing(grams: "300")
        #expect(editor.kcalText == "390")
        #expect(editor.item() == .success(FoodItem(name: "rice", grams: 300, kcal: 390)))
    }

    @Test func theFieldShowsOneDecimalButTheItemKeepsTheScaledValue() throws {
        let editor = editing(grams: "7")
        #expect(editor.kcalText == "9.1")
        #expect(try editor.item().get().kcal == 195 * 7 / 150)
    }

    @Test func aTypedEnergyWinsOverTheScaling() {
        let editor = editing(grams: "300", kcal: "400")
        #expect(editor.kcalText == "400")
        #expect(editor.item() == .success(FoodItem(name: "rice", grams: 300, kcal: 400)))
    }

    @Test func aTypedEnergyAloneKeepsTheGrams() {
        #expect(editing(kcal: "210").item() == .success(FoodItem(name: "rice", grams: 150, kcal: 210)))
    }

    @Test func aRenameKeepsTheNumbers() {
        #expect(editing(name: "brown rice").item() == .success(FoodItem(name: "brown rice", grams: 150, kcal: 195)))
    }

    @Test func aCommaIsAPoint() {
        #expect(editing(grams: "150,5").item() == .success(FoodItem(name: "rice", grams: 150.5, kcal: 195 * 150.5 / 150)))
    }

    @Test(arguments: ["0", "2001", "0.5"])
    func gramsOutOfRangeAreRefusedWithTheBounds(text: String) {
        let problem = editing(grams: text).problem
        #expect(problem?.what == "the grams are out of range")
        #expect(problem?.expected == "a number from 1 to 2000")
    }

    @Test func gramsThatPushTheScaledEnergyOutOfRangeAreRefusedAsAWhole() {
        let tall = FoodItem(name: "oil", grams: 100, kcal: 4000)
        #expect(editing(tall, grams: "200").problem?.what == #"changing the grams of "oil" to 200 puts its kcal out of range"#)
        // The user can still type the energy of the larger portion.
        #expect(editing(tall, grams: "200", kcal: "5000").item() == .success(FoodItem(name: "oil", grams: 200, kcal: 5000)))
    }

    @Test func aTypedEnergyOutOfRangeIsRefused() {
        let problem = editing(kcal: "5001").problem
        #expect(problem?.what == "the kcal are out of range")
        #expect(problem?.saw == "5001")
        #expect(editing(kcal: "0").problem == nil)
        #expect(editing(kcal: "5000").problem == nil)
    }

    @Test func textThatIsNotANumberNamesTheField() {
        #expect(editing(grams: "abc").problem?.what == "Grams is not a number")
        #expect(editing(kcal: "12x").problem?.what == "Energy is not a number")
    }

    @Test func aNameOfOneHundredAndOneCharactersIsRefused() {
        let problem = editing(name: String(repeating: "a", count: 101)).problem
        #expect(problem?.what == "the name is not valid")
        #expect(problem?.saw == "a name of 101 characters")
        #expect(editing(name: String(repeating: "a", count: 100)).problem == nil)
    }

    @Test func aBlankFieldIsNoComplaintYetButTheItemIsNotThere() {
        for editor in [editing(name: "  "), editing(grams: ""), editing(kcal: " ")] {
            #expect(editor.problem == nil)
            guard case .failure = editor.item() else { Issue.record("a blank field made an item"); continue }
        }
    }
}

@Suite struct AddingAnItemTests {
    @Test func aNewFormIsEmptyAndMakesNoItem() {
        let editor = ItemEditor()
        #expect(editor.kcalText == "")
        #expect(editor.problem == nil)
        guard case .failure = editor.item() else { Issue.record("an empty form made an item"); return }
    }

    @Test func aNewItemNeedsNameGramsAndEnergy() {
        var editor = ItemEditor()
        editor.name = "salad"
        editor.gramsText = "80"
        guard case .failure = editor.item() else { Issue.record("no energy typed, yet an item"); return }
        #expect(editor.problem == nil)
        editor.typedKcalText = "30"
        #expect(editor.item() == .success(FoodItem(name: "salad", grams: 80, kcal: 30)))
    }

    @Test func aNewItemWithBadNumbersGetsTheSameRefusals() {
        var editor = ItemEditor()
        editor.name = "salad"
        editor.gramsText = "0"
        editor.typedKcalText = "30"
        #expect(editor.problem?.what == "the grams are out of range")
        editor.gramsText = "80"
        editor.typedKcalText = "6000"
        #expect(editor.problem?.what == "the kcal are out of range")
    }
}

@Suite struct ApplyingTheEditorTests {
    @Test func theItemAtTheIndexIsReplacedAndTheRestStays() throws {
        let start = try meal([rice, peas])
        let next = try editing(grams: "300").applied(to: start, at: 0).get()
        #expect(next.items == [FoodItem(name: "rice", grams: 300, kcal: 390), peas])
        #expect(next.totalKcal == 454)
    }

    @Test func aNewItemIsAdded() throws {
        var editor = ItemEditor()
        editor.name = "salad"
        editor.gramsText = "80"
        editor.typedKcalText = "30"
        let next = try editor.applied(to: meal([rice]), at: nil).get()
        #expect(next.items == [rice, FoodItem(name: "salad", grams: 80, kcal: 30)])
    }

    @Test func aTwentyFirstItemIsRefused() throws {
        var editor = ItemEditor()
        editor.name = "one more"
        editor.gramsText = "1"
        editor.typedKcalText = "1"
        let full = try meal(Array(repeating: rice, count: 20))
        guard case .failure(let problem) = editor.applied(to: full, at: nil) else { Issue.record("20 items grew to 21"); return }
        #expect(problem.what == "the meal has too many items")
    }

    @Test func anIndexThatIsNotThereIsRefused() throws {
        guard case .failure(let problem) = editing().applied(to: try meal([rice]), at: 3) else {
            Issue.record("an index out of range was accepted")
            return
        }
        #expect(problem.what == "the item index is out of range")
    }

    @Test func anInvalidFormChangesNothing() throws {
        let start = try meal([rice])
        guard case .failure = editing(grams: "abc").applied(to: start, at: 0) else { Issue.record("invalid form applied"); return }
        #expect(start.items == [rice])
    }
}
