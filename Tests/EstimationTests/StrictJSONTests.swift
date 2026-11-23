import Testing

@testable import Estimation

@Suite struct StrictJSONTests {
    @Test(arguments: [
        ("{}", JSONValue.object([:])),
        ("[]", .array([])),
        (#""text""#, .string("text")),
        ("true", .bool(true)),
        ("false", .bool(false)),
        ("null", .null),
        ("0", .number(0)),
        ("-12.5", .number(-12.5)),
        ("1e3", .number(1000)),
        ("1E-2", .number(0.01)),
        ("2e+2", .number(200)),
        (" \t\r\n[ 1 , 2 ] \n", .array([.number(1), .number(2)])),
        (#"{"a": [{"b": null}], "c": "d"}"#, .object(["a": .array([.object(["b": .null])]), "c": .string("d")])),
        (#""é""#, .string("\u{E9}")),
        (#""😀""#, .string("\u{1F600}")),
        (#""\"\\\/\b\f\n\r\t""#, .string("\"\\/\u{8}\u{C}\n\r\t")),
        ("\"caf\u{E9} \u{1F600}\"", .string("caf\u{E9} \u{1F600}")),
        (#""""#, .string("")),
    ])
    func parsesValues(text: String, value: JSONValue) throws {
        #expect(try StrictJSON.parse(text) == value)
    }

    @Test func aNumberTooLargeForADoubleReadsAsInfinity() throws {
        #expect(try StrictJSON.parse("1e999") == .number(.infinity))
        #expect(try StrictJSON.parse("-1e999") == .number(-.infinity))
    }

    @Test func minusZeroKeepsItsSign() throws {
        guard case .number(let value) = try StrictJSON.parse("-0") else {
            Issue.record("not a number")
            return
        }
        #expect(value == 0 && value.sign == .minus)
    }

    @Test(arguments: [
        "", " ", "{", "}", "[", "]", "[1,]", "[,1]", "[1 2]", "{,}", #"{"a":1,}"#, #"{"a" 1}"#, #"{"a":}"#,
        "{a:1}", "{1:1}", "'a'", "01", "00", "1.", ".5", "+1", "1e", "1e+", "-", "--1", "0x10", "NaN", "nan",
        "Infinity", "-Infinity", "nul", "tru", "falsy", "trueX", #""abc"#, #""\x""#, #""\u12""#, #""\u12G4""#,
        #""\ud800""#, #""\ud800A""#, #""\udc00""#, "\"a\tb\"", "\"a\nb\"", #"{"a":1}{}"#, #"{"a":1} x"#,
        "// c\n{}", "/*c*/{}", "{} {}", "[] []", "1 2",
    ])
    func rejectsSyntax(text: String) {
        #expect(throws: JSONSyntaxError.self) { try StrictJSON.parse(text) }
    }

    @Test func aRepeatedKeyIsAnErrorAtTheSecondKey() {
        let text = #"{"a":1,"a":2}"#
        let error = #expect(throws: JSONSyntaxError.self) { try StrictJSON.parse(text) }
        #expect(error == JSONSyntaxError(offset: 7, message: #"the key "a" is repeated"#))
    }

    @Test(arguments: [
        #"{"a":{"b":1,"b":1}}"#, #"[{"a":1,"a":1}]"#, #"{"a":1,"b":2,"a":3}"#, #"{"a":1,"a":1}"#,
    ])
    func aRepeatedKeyIsRejectedWhereverItIs(text: String) {
        #expect(throws: JSONSyntaxError.self) { try StrictJSON.parse(text) }
    }

    @Test func differentKeysAreNotRepeated() throws {
        #expect(try StrictJSON.parse(#"{"a":1,"b":1,"A":1}"#) == .object(["a": .number(1), "b": .number(1), "A": .number(1)]))
    }

    @Test(arguments: [("[1,]", 3), ("tru", 0), (#"{"a":1} x"#, 8), ("[1 2]", 3), ("", 0)])
    func errorsGiveTheOffset(text: String, offset: Int) {
        let error = #expect(throws: JSONSyntaxError.self) { try StrictJSON.parse(text) }
        #expect(error?.offset == offset)
    }
}
