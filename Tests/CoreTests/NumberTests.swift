import Testing

@testable import Core

@Suite struct NumberTests {
    @Test(arguments: [
        ("150", 150.0), ("150.5", 150.5), ("150,5", 150.5), ("  70  ", 70), ("70.", 70), ("70,", 70),
        ("0", 0), ("007", 7), ("0.25", 0.25),
    ])
    func whatAKeypadTypesIsRead(text: String, value: Double) throws {
        #expect(try Number.parse(text, field: "Grams") == value)
    }

    @Test(arguments: [
        "", "   ", "abc", "-5", "+5", "1e3", "1.2.3", "1,2,3", "1.2,3", ".5", ",5", "1 000", "12abc", "\u{663}",
        "NaN", "inf", "\u{221E}", "1" + String(repeating: "0", count: 400),
    ])
    func anythingElseIsRefused(text: String) {
        #expect(throws: NumberError.self) { try Number.parse(text, field: "Grams") }
    }

    @Test func theRefusalNamesTheFieldAndWhatWasTyped() {
        let error = #expect(throws: NumberError.self) { try Number.parse("abc", field: "Energy") }
        #expect(error?.description == #"Energy is not a number: expected digits with an optional decimal point or comma, saw "abc""#)
    }

    @Test func anEmptyFieldIsSaidToHoldNothing() {
        let error = #expect(throws: NumberError.self) { try Number.parse("  ", field: "Grams") }
        #expect(error?.saw == "\"  \"")
        let empty = #expect(throws: NumberError.self) { try Number.parse("", field: "Grams") }
        #expect(empty?.saw == "nothing")
    }
}
