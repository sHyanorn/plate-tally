import Testing

@testable import Energy

private func profile(
    height: Double = 175, weight: Double = 70, age: Int = 30, sex: Sex = .male,
    activity: ActivityLevel = .light
) -> Profile {
    Profile(heightCm: height, weightKg: weight, ageYears: age, sex: sex, activity: activity)
}

@Suite struct EnergyTests {
    /// The test vector of docs/SPEC.md: male, 70 kg, 175 cm, 30 years, Light.
    @Test func specVector() throws {
        let person = profile()
        #expect(try Energy.resting(person) == 1648.75)
        #expect(try Energy.expenditure(person) == 2555.5625)
    }

    @Test func femaleRestsBelowMaleByTheDifferenceOfTheConstants() throws {
        #expect(try Energy.resting(profile(sex: .female)) == 1482.75)
        for age in [18, 45, 90] {
            let male = try Energy.resting(profile(age: age, sex: .male))
            let female = try Energy.resting(profile(age: age, sex: .female))
            #expect(male - female == 166)
        }
    }

    @Test(arguments: [
        (ActivityLevel.atHome, 2308.25), (.light, 2555.5625), (.moderate, 2885.3125), (.heavy, 3297.5),
    ])
    func eachFactorScalesTheRestingValue(level: ActivityLevel, kcal: Double) throws {
        #expect(try Energy.expenditure(profile(activity: level)) == kcal)
    }

    @Test func factorsAreThoseOfD003() {
        #expect(ActivityLevel.allCases.map(\.factor) == [1.40, 1.55, 1.75, 2.00])
    }

    @Test func storedNamesAreStable() {
        #expect(ActivityLevel.allCases.map(\.rawValue) == ["atHome", "light", "moderate", "heavy"])
        #expect(Sex.allCases.map(\.rawValue) == ["female", "male"])
    }

    @Test(arguments: [
        ("heightCm", profile(height: 0)), ("heightCm", profile(height: -1)),
        ("heightCm", profile(height: .nan)),
        ("weightKg", profile(weight: 0)), ("weightKg", profile(weight: -0.5)),
        ("weightKg", profile(weight: .nan)),
        ("ageYears", profile(age: 0)), ("ageYears", profile(age: -3)),
    ])
    func rejectsNoPositiveInput(field: String, person: Profile) {
        let error = #expect(throws: EnergyError.self) { try Energy.expenditure(person) }
        #expect(error?.field == field)
    }

    @Test func errorNamesTheFieldAndTheValue() {
        let error = #expect(throws: EnergyError.self) { try Energy.resting(profile(weight: -3)) }
        #expect(error?.description == "weightKg is out of range: expected a number above 0, saw -3")
    }

    @Test func smallestPositiveInputsAreAccepted() throws {
        #expect(throws: Never.self) { try Energy.resting(profile(height: 0.1, weight: 0.1, age: 1)) }
    }

    @Test func firstInvalidFieldIsReported() {
        let error = #expect(throws: EnergyError.self) {
            try Energy.resting(profile(height: 0, weight: 0, age: 0))
        }
        #expect(error?.field == "heightCm")
    }
}
