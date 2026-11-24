import Core
import Foundation
import Testing

@testable import Ledger

private func editing(_ item: FoodItem = rice, grams: String? = nil, kcal: String? = nil, name: String? = nil) -> ItemEditor {
    var editor = ItemEditor(editing: item)
    if let grams { editor.gramsText = grams }
    if let kcal { editor.typeEnergy(kcal) }
    if let name { editor.name = name }
    return editor
}

@Suite struct EditingAnItemTests {
    @Test func theFormStartsWithTheTextsOfTheItem() {
        let editor = editing()
        #expect(editor.name == "rice")
        #expect(editor.gramsText == "150")
        #expect(editor.energyText == "195")
        #expect(editor.problem == nil)
        #expect(editor.item() == .success(rice))
    }

    /// R10: a change of the grams scales the kcal in proportion.
    @Test func theEnergyFollowsTheGramsUntilItIsTyped() {
        let editor = editing(grams: "300")
        #expect(editor.energyText == "390")
        #expect(editor.item() == .success(FoodItem(name: "rice", grams: 300, kcal: 390)))
    }

    /// A field hands back the text it shows when it gains or loses the focus. That is no input: the energy
    /// still follows the grams and stays an estimate (R9, R10).
    @Test func theShownTextHandedBackIsNoInput() {
        var editor = editing()
        editor.typeEnergy(editor.energyText)
        editor.gramsText = "300"
        #expect(editor.energyText == "390")
        #expect(editor.energyIsEstimate)
    }

    @Test func theFieldShowsOneDecimalButTheItemKeepsTheScaledValue() throws {
        let editor = editing(grams: "7")
        #expect(editor.energyText == "9.1")
        #expect(try editor.item().get().kcal == 195 * 7 / 150)
    }

    @Test func aTypedEnergyWinsOverTheScaling() {
        let editor = editing(grams: "300", kcal: "400")
        #expect(editor.energyText == "400")
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

@Suite struct NameRuleTests {
    @Test func theNameIsKeptAsTyped() {
        #expect(editing(name: "  rice \n").item() == .success(FoodItem(name: "  rice \n", grams: 150, kcal: 195)))
    }

    @Test(arguments: [("", 0), ("   \n", 0), (String(repeating: "x", count: 101), 101), (" " + String(repeating: "x", count: 101), 101)])
    func refusesANameOutsideOneToHundredCharacters(name: String, length: Int) {
        guard case .failure(let problem) = editing(name: name).item() else { Issue.record("a bad name made an item"); return }
        #expect(problem == Problem(LedgerError.name(length: length)))
    }

    @Test func acceptsNamesOfOneAndOneHundredCharacters() {
        let long = "  " + String(repeating: "x", count: 100) + "\n"
        #expect(editing(name: long).item() == .success(FoodItem(name: long, grams: 150, kcal: 195)))
        #expect(editing(name: "x").item() == .success(FoodItem(name: "x", grams: 150, kcal: 195)))
    }

    /// Length counts Unicode scalars, as R5 does for the reply: one family emoji is five.
    @Test func nameLengthCountsScalarsNotGraphemes() {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        guard case .success = editing(name: String(repeating: family, count: 20)).item() else {
            Issue.record("20 family emoji are 100 scalars and fit")
            return
        }
        guard case .failure(let problem) = editing(name: String(repeating: family, count: 21)).item() else {
            Issue.record("21 family emoji are 105 scalars and do not fit")
            return
        }
        #expect(problem == Problem(LedgerError.name(length: 105)))
    }
}

@Suite struct AddingAnItemTests {
    @Test func aNewFormIsEmptyAndMakesNoItem() {
        let editor = ItemEditor()
        #expect(editor.energyText == "")
        #expect(editor.problem == nil)
        guard case .failure = editor.item() else { Issue.record("an empty form made an item"); return }
    }

    @Test func aNewItemNeedsNameGramsAndEnergy() {
        var editor = ItemEditor()
        editor.name = "salad"
        editor.gramsText = "80"
        guard case .failure = editor.item() else { Issue.record("no energy typed, yet an item"); return }
        #expect(editor.problem == nil)
        editor.typeEnergy("30")
        #expect(editor.item() == .success(FoodItem(name: "salad", grams: 80, kcal: 30)))
    }

    @Test func aNewItemWithBadNumbersGetsTheSameRefusals() {
        var editor = ItemEditor()
        editor.name = "salad"
        editor.gramsText = "0"
        editor.typeEnergy("30")
        #expect(editor.problem?.what == "the grams are out of range")
        editor.gramsText = "80"
        editor.typeEnergy("6000")
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
        editor.typeEnergy("30")
        let next = try editor.applied(to: meal([rice]), at: nil).get()
        #expect(next.items == [rice, FoodItem(name: "salad", grams: 80, kcal: 30)])
    }

    @Test func aTwentyFirstItemIsRefused() throws {
        var editor = ItemEditor()
        editor.name = "one more"
        editor.gramsText = "1"
        editor.typeEnergy("1")
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

@Suite struct KilojouleFieldTests {
    private func inKilojoules(_ item: FoodItem = rice) -> ItemEditor {
        var editor = ItemEditor(editing: item)
        editor.unit = .kJ
        return editor
    }

    @Test func theFieldShowsTheEnergyOfTheItemInKilojoulesAndItsKcal() {
        let editor = inKilojoules()
        #expect(editor.energyText == "815.1")
        #expect(editor.kcalEquivalent == 195)
        #expect(editor.energyIsEstimate)
        #expect(editor.item() == .success(rice))
    }

    @Test func typedKilojoulesAreStoredAsKcalWithoutRounding() {
        var editor = inKilojoules()
        editor.typeEnergy("1000")
        #expect(editor.energyText == "1000")
        #expect(editor.kcalEquivalent == 1000 / 4.18)
        #expect(!editor.energyIsEstimate)
        #expect(editor.item() == .success(FoodItem(name: "rice", grams: 150, kcal: 1000 / 4.18)))
    }

    @Test func aChangeOfUnitChangesNoItemAndKeepsTheTypedText() {
        var editor = ItemEditor(editing: rice)
        editor.typeEnergy("200")
        editor.unit = .kJ
        #expect(editor.energyText == "836")
        #expect(editor.item() == .success(FoodItem(name: "rice", grams: 150, kcal: 200)))
        editor.unit = .kcal
        #expect(editor.energyText == "200")
        #expect(editor.kcalEquivalent == nil)
    }

    @Test func kilojoulesUpToTheBoundOfFiveThousandKcalAreAccepted() {
        var editor = inKilojoules()
        editor.typeEnergy("20900")
        #expect(editor.item() == .success(FoodItem(name: "rice", grams: 150, kcal: 5000)))
        editor.typeEnergy("20901")
        #expect(editor.problem?.what == "the kcal are out of range")
        #expect(editor.problem?.saw == plainNumber(20901 / 4.18))
    }

    @Test func kilojoulesThatAreNotANumberNameTheEnergyField() {
        var editor = inKilojoules()
        editor.typeEnergy("12x")
        #expect(editor.problem?.what == "Energy is not a number")
        #expect(editor.energyText == "12x")
        #expect(editor.kcalEquivalent == nil)
    }

    @Test func aNewItemTakesItsEnergyInKilojoules() {
        var editor = ItemEditor()
        editor.unit = .kJ
        #expect(editor.energyText == "")
        #expect(!editor.energyIsEstimate)
        editor.name = "salad"
        editor.gramsText = "80"
        editor.typeEnergy("125.4")
        #expect(editor.item() == .success(FoodItem(name: "salad", grams: 80, kcal: 125.4 / 4.18)))
    }
}
