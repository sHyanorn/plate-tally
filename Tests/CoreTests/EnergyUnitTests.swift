import Testing

@testable import Core

@Suite struct EnergyUnitTests {
    /// Food Standards Code, Schedule 11, S11-2(4): kcal = kJ / 4.18.
    @Test func kilojoulesAreDividedByFourPointOneEight() {
        #expect(EnergyUnit.kJ.kcal(418) == 100)
        #expect(EnergyUnit.kJ.kcal(1000) == 1000 / 4.18)
        #expect(EnergyUnit.kJ.kcal(20900) == 5000)
        #expect(EnergyUnit.kJ.value(ofKcal: 250) == 1045)
    }

    @Test func kcalStayAsTheyAre() {
        #expect(EnergyUnit.kcal.kcal(195) == 195)
        #expect(EnergyUnit.kcal.value(ofKcal: 195) == 195)
    }

    @Test func aTypedEnergyIsReadInItsUnit() throws {
        #expect(try TypedEnergy(unit: .kJ, text: "836").kcal(field: "Energy") == 200)
        let error = #expect(throws: NumberError.self) { try TypedEnergy(unit: .kJ, text: "8x").kcal(field: "Energy") }
        #expect(error?.what == "Energy is not a number")
    }

    @Test(arguments: [(815.1, "815.1"), (390.0, "390"), (1250 / 4.18, "299"), (1520 / 4.18, "363.6"), (0.04, "0")])
    func aComputedNumberIsShownToOneDecimal(value: Double, text: String) throws {
        #expect(Number.fieldText(value) == text)
        #expect(try Number.parse(text, field: "Energy") == (value * 10).rounded() / 10)
    }
}
