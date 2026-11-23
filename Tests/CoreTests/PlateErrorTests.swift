import Foundation
import Testing

@testable import Core

private struct SampleError: PlateError {
    let what = "weight is wrong"
    let expected = "a number above 0"
    let saw = "-3"
}

@Suite struct PlateErrorTests {
    @Test func descriptionStatesWhatExpectedAndSaw() {
        #expect(SampleError().description == "weight is wrong: expected a number above 0, saw -3")
    }

    @Test func localizedDescriptionIsTheSameText() {
        let error: any Error = SampleError()
        #expect(error.localizedDescription == "weight is wrong: expected a number above 0, saw -3")
    }

    @Test(arguments: [
        (2000.0, "2000"), (0.0, "0"), (-1.0, "-1"), (5000.5, "5000.5"), (70.25, "70.25"),
        (Double.nan, "nan"), (Double.infinity, "inf"), (1e20, "1e+20"),
    ])
    func plainNumberDropsTheTrailingZero(value: Double, text: String) {
        #expect(plainNumber(value) == text)
    }
}

@Suite struct LimitsTests {
    @Test func boundsOfR5AreInclusive() {
        #expect(Limits.maxItems == 20)
        #expect(Limits.nameLength == 1...100)
        #expect(Limits.grams.contains(1) && Limits.grams.contains(2000))
        #expect(!Limits.grams.contains(0.999) && !Limits.grams.contains(2000.001))
        #expect(Limits.kcal.contains(0) && Limits.kcal.contains(5000))
        #expect(!Limits.kcal.contains(-0.001) && !Limits.kcal.contains(5000.001))
    }

    /// Unicode scalars after surrounding whitespace is removed: one family emoji is five.
    @Test(arguments: [("rice", 4), ("  rice \n", 4), ("", 0), (" \t\n", 0), ("caf\u{E9}", 4), ("e\u{301}", 2),
        ("\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}", 5), ("\u{0}", 1), ("a b", 3)])
    func nameLengthCountsScalarsAfterTrimming(name: String, length: Int) {
        #expect(Limits.nameLength(of: name) == length)
    }
}
