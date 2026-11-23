import Core
import Testing

@testable import Ledger

private func converter(
    _ basis: EnergyConverter.Basis, name: String = "Muesli bar", grams: String = "35"
) -> EnergyConverter {
    var form = EnergyConverter()
    form.basis = basis
    form.name = name
    form.gramsText = grams
    return form
}

@Suite struct PerServingTests {
    @Test func kilojoulesBecomeTheKcalOfTheItem() {
        var form = converter(.serving)
        form.type("1250", in: .kJ)
        #expect(form.text(in: .kJ) == "1250")
        #expect(form.text(in: .kcal) == "299")
        #expect(form.follows(.kcal))
        #expect(!form.follows(.kJ))
        #expect(form.portionKcal == nil)
        #expect(form.item() == .success(FoodItem(name: "Muesli bar", grams: 35, kcal: 1250 / 4.18)))
    }

    @Test func kcalGiveTheKilojoulesBesideThem() {
        var form = converter(.serving)
        form.type("299", in: .kcal)
        #expect(form.text(in: .kJ) == "1249.8")
        #expect(form.follows(.kJ))
        #expect(form.item() == .success(FoodItem(name: "Muesli bar", grams: 35, kcal: 299)))
    }

    @Test func kilojoulesAboveFiveThousandKcalAreRefused() {
        var form = converter(.serving)
        form.type("20901", in: .kJ)
        #expect(form.problem?.what == "the kcal are out of range")
        form.type("x", in: .kJ)
        #expect(form.problem?.what == "Energy is not a number")
        #expect(form.text(in: .kcal) == "")
    }
}

@Suite struct PerHundredGramsTests {
    @Test func theEnergyPerHundredGramsTimesTheGramsEatenIsTheItem() throws {
        var form = converter(.per100g)
        form.type("1520", in: .kJ)
        #expect(form.text(in: .kcal) == "363.6")
        let kcal = try #require(form.portionKcal)
        #expect(kcal == 1520 / 4.18 * 35 / 100)
        #expect(abs(try #require(form.portionKilojoules) - 532) < 1e-9)
        #expect(form.item() == .success(FoodItem(name: "Muesli bar", grams: 35, kcal: kcal)))
    }

    @Test func kcalPerHundredGramsWorkTheSameWay() {
        var form = converter(.per100g, grams: "150")
        form.type("364", in: .kcal)
        #expect(form.text(in: .kJ) == "1521.5")
        #expect(form.portionKcal == 546)
        #expect(form.item() == .success(FoodItem(name: "Muesli bar", grams: 150, kcal: 546)))
    }

    @Test func aPortionAboveFiveThousandKcalIsRefusedWithItsKcal() {
        var form = converter(.per100g, grams: "600")
        form.type("900", in: .kcal)
        #expect(form.portionKcal == 5400)
        #expect(form.problem?.what == "the kcal are out of range")
        #expect(form.problem?.saw == "5400")
    }

    @Test func eachFieldIsNamedInItsRefusal() {
        var form = converter(.per100g, grams: "x")
        form.type("1520", in: .kJ)
        #expect(form.problem?.what == "Grams eaten is not a number")
        form.gramsText = "35"
        form.type("abc", in: .kJ)
        #expect(form.problem?.what == "kJ / 100 g is not a number")
        form.type("abc", in: .kcal)
        #expect(form.problem?.what == "kcal / 100 g is not a number")
    }
}

@Suite struct ConverterFormTests {
    @Test func eachBasisKeepsItsOwnEnergy() {
        var form = converter(.serving)
        form.type("1250", in: .kJ)
        form.basis = .per100g
        #expect(form.text(in: .kJ) == "")
        #expect(form.text(in: .kcal) == "")
        form.type("364", in: .kcal)
        form.basis = .serving
        #expect(form.text(in: .kJ) == "1250")
        form.basis = .per100g
        #expect(form.text(in: .kcal) == "364")
    }

    @Test(arguments: ["0", "2001"])
    func gramsOutsideOneToTwoThousandAreRefused(grams: String) {
        for basis in EnergyConverter.Basis.allCases {
            var form = converter(basis, grams: grams)
            form.type("100", in: .kcal)
            #expect(form.problem?.what == "the grams are out of range")
        }
    }

    @Test func aBlankFieldIsNoComplaintYetButTheItemIsNotThere() {
        var blankName = converter(.serving, name: " ")
        blankName.type("100", in: .kcal)
        var blankEnergy = converter(.serving)
        blankEnergy.type("", in: .kJ)
        for form in [EnergyConverter(), blankName, blankEnergy, converter(.per100g)] {
            #expect(form.problem == nil)
            guard case .failure = form.item() else { Issue.record("a blank field made an item"); continue }
        }
    }

    @Test func aNameOfOneHundredAndOneCharactersIsRefused() {
        var form = converter(.serving, name: String(repeating: "a", count: 101))
        form.type("100", in: .kcal)
        #expect(form.problem?.what == "the name is not valid")
    }
}
