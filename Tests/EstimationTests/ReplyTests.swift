import Core
import Foundation
import Testing

@testable import Estimation

private let rice = #"{"name": "rice", "grams": 100, "kcal": 130}"#
private func items(_ elements: String...) -> String { #"{"items": [\#(elements.joined(separator: ", "))]}"# }
private func item(name: String = "rice", grams: String = "100", kcal: String = "130") -> String {
    #"{"name": \#(jsonString(name)), "grams": \#(grams), "kcal": \#(kcal)}"#
}
private func jsonString(_ text: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [text])
    let array = String(decoding: data, as: UTF8.self)
    return String(array.dropFirst().dropLast())
}

@Suite struct ValidReplyTests {
    @Test func anEmptyListIsValid() throws {
        #expect(try accepted(#"{"items": []}"#) == [])
    }

    @Test func itemsKeepTheirValuesInOrder() throws {
        let text = items(rice, item(name: " peas ", grams: "50.5", kcal: "40.25"))
        #expect(
            try accepted(text) == [
                FoodItem(name: "rice", grams: 100, kcal: 130), FoodItem(name: " peas ", grams: 50.5, kcal: 40.25),
            ])
    }

    @Test func twentyItemsAreValid() throws {
        #expect(try accepted(items(Array(repeating: rice, count: 20).joined(separator: ", "))).count == 20)
    }

    @Test(arguments: ["```", "```json", "```JSON", "```python", "```json5", "```a_b"])
    func oneSurroundingFenceIsRemoved(fence: String) throws {
        #expect(try accepted("\(fence)\n\(items(rice))\n```").count == 1)
        #expect(try accepted("\n  \(fence)\n\(items(rice))\n``` \n\n").count == 1)
    }

    @Test func surroundingWhitespaceIsRemoved() throws {
        #expect(try accepted("  \n\t\(items(rice))\n\n ").count == 1)
    }

    @Test func numbersMayBeIntegersOrDecimals() throws {
        let text = items(item(grams: "1e2", kcal: "130.0"), item(grams: "250", kcal: "0.5"))
        #expect(try accepted(text).map(\.grams) == [100, 250])
    }

    @Test(arguments: [
        (item(grams: "1", kcal: "0"), 1.0, 0.0), (item(grams: "2000", kcal: "5000"), 2000.0, 5000.0),
        (item(grams: "1.000001", kcal: "0.000001"), 1.000001, 0.000001),
        (item(grams: "1999.999", kcal: "4999.999"), 1999.999, 4999.999),
    ])
    func boundsAreInclusive(element: String, grams: Double, kcal: Double) throws {
        let result = try accepted(items(element))
        #expect(result.first?.grams == grams && result.first?.kcal == kcal)
    }

    @Test func aNameOf100CharactersAfterTrimmingIsValid() throws {
        #expect(try accepted(items(item(name: "  " + String(repeating: "x", count: 100) + "\n"))).count == 1)
        #expect(try accepted(items(item(name: "x"))).count == 1)
    }

    /// Length counts Unicode scalars, as the evaluation does: one family emoji is five.
    @Test func nameLengthCountsScalarsNotGraphemes() throws {
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        #expect(family.count == 1 && family.unicodeScalars.count == 5)
        #expect(try accepted(items(item(name: String(repeating: family, count: 20)))).count == 1)
        #expect(try rejection(items(item(name: String(repeating: family, count: 21)))) == .badValue)
        #expect(try accepted(items(item(name: String(repeating: "\u{E9}", count: 100)))).count == 1)
        #expect(try rejection(items(item(name: String(repeating: "\u{E9}", count: 101)))) == .badValue)
    }

    @Test func escapedCharactersInANameAreDecoded() throws {
        let text = #"{"items": [{"name": "café \"x\"", "grams": 1, "kcal": 1}]}"#
        #expect(try accepted(text).first?.name == "caf\u{E9} \"x\"")
    }
}

@Suite struct RejectedReplyTests {
    @Test(arguments: [
        #"``` json\#n{"items": []}\#n```"#,
        "````\n{\"items\": []}\n```",
        "~~~\n{\"items\": []}\n~~~",
        "```json\n{\"items\": []}",
        "{\"items\": []}\n```",
        "```json {\"items\": []} ```",
        "```\n```",
        "```json\n{\"items\": []}\n```\n```json\n{\"items\": []}\n```",
        "Here you go: {\"items\": []}",
        "{\"items\": []} Hope this helps.",
        "{\"items\": []}\n{\"items\": []}",
        "about 300 kcal",
        "{\"items\": [",
        "{\"items\": [{\"name\": \"rice\", \"grams\": 100, \"kcal\": 130}",
        "{\"items\": [{\"name\": \"a\", \"grams\": 5, \"kcal\": NaN}]}",
        "{\"items\": [{\"name\": \"a\", \"grams\": 5, \"kcal\": Infinity}]}",
        "{\"items\": [{\"name\": \"a\", \"grams\": 5, \"kcal\": -Infinity}]}",
        "{\"items\": [], \"items\": []}",
        "{\"items\": [{\"name\": \"a\", \"name\": \"b\", \"grams\": 5, \"kcal\": 5}]}",
        "```json\n{\"items\": [], \"items\": []}\n```",
    ])
    func notJSON(text: String) throws {
        #expect(try rejection(text) == .notJSON)
    }

    @Test func proseBeforeTheObjectIsAnErrorEvenIfTheObjectIsValid() throws {
        #expect(try rejection("Sure! " + items(rice)) == .notJSON)
    }

    @Test func nothingButWhitespaceIsAnEmptyText() throws {
        #expect(try rejection("") == .emptyText)
        #expect(try rejection(" \n\t ") == .emptyText)
    }

    @Test(arguments: ["[1, 2]", #""text""#, "5", "null", "true"])
    func notObject(text: String) throws {
        #expect(try rejection(text) == .notObject)
    }

    @Test(arguments: [
        "{}", #"{"kcal": 7}"#, #"{"items": [], "total": 1}"#, #"{"item": []}"#, #"{"Items": []}"#,
        #"{"items": ["rice"]}"#, #"{"items": [5]}"#, #"{"items": [null]}"#, #"{"items": [[1, 2, 3]]}"#,
        #"{"items": [{"name": "rice", "grams": 100}]}"#,
        #"{"items": [{"name": "rice", "grams": 100, "kcal": 130, "note": "x"}]}"#,
        #"{"items": [{"name": "rice", "grams": 100, "calories": 130}]}"#, #"{"items": [{}]}"#,
    ])
    func wrongKeys(text: String) throws {
        #expect(try rejection(text) == .wrongKeys)
    }

    @Test(arguments: [
        #"{"items": "rice"}"#, #"{"items": null}"#, #"{"items": {}}"#,
        items(item(name: "")), items(item(name: "   ")), items(item(name: String(repeating: "x", count: 101))),
        items(item(name: " " + String(repeating: "x", count: 101))),
        #"{"items": [{"name": 5, "grams": 100, "kcal": 130}]}"#,
        #"{"items": [{"name": null, "grams": 100, "kcal": 130}]}"#,
        items(item(grams: "0.5")), items(item(grams: "0.999999")), items(item(grams: "0")), items(item(grams: "-1")),
        items(item(grams: "2000.001")), items(item(grams: "2500")),
        items(item(grams: "true")), items(item(grams: "false")), items(item(grams: #""100""#)), items(item(grams: "null")),
        items(item(grams: "[100]")), items(item(grams: "1e999")), items(item(grams: "-1e999")),
        items(item(kcal: "-1")), items(item(kcal: "-0.001")), items(item(kcal: "5000.001")), items(item(kcal: "5001")),
        items(item(kcal: "true")), items(item(kcal: "false")), items(item(kcal: #""130""#)), items(item(kcal: "null")),
        items(item(kcal: "1e999")),
    ])
    func badValue(text: String) throws {
        #expect(try rejection(text) == .badValue)
    }

    @Test func moreThanTwentyItemsAreTooMany() throws {
        #expect(try rejection(items(Array(repeating: rice, count: 21).joined(separator: ", "))) == .tooManyItems)
    }

    /// The first failure decides, items in order and name, grams, kcal within an item.
    @Test func theFirstFailureIsReported() throws {
        let badKcal = item(kcal: "-1")
        let wrongKeys = #"{"name": "x"}"#
        #expect(try rejection(items(rice, badKcal, wrongKeys)) == .badValue)
        #expect(try rejection(items(rice, wrongKeys, badKcal)) == .wrongKeys)
        #expect(try rejection(items(item(name: "", grams: "0", kcal: "-1"))) == .badValue)
        let error = try #require(try read(items(item(name: "ok", grams: "0", kcal: "-1"))).items.failure)
        #expect(error.what == "items[0].grams is not valid")
    }

    @Test func messagesStateWhatWasExpectedAndSeen() throws {
        let text = items(rice, item(grams: "2500"))
        let error = try #require(try read(text).items.failure)
        #expect(
            error.description
                == "bad_value: items[1].grams is not valid: expected a number from 1 to 2000, saw 2500")

        let keys = try #require(try read(#"{"items": [{"name": "x", "grams": 1, "note": "n"}]}"#).items.failure)
        #expect(keys.description == "wrong_keys: items[0] has the wrong keys: expected exactly the keys name, grams, kcal, saw the keys grams, name, note")

        let many = try #require(try read(items(Array(repeating: rice, count: 21).joined(separator: ", "))).items.failure)
        #expect(many.description == "too_many_items: the list of items is too long: expected at most 20 items, saw 21 items")

        let name = try #require(try read(items(item(name: " "))).items.failure)
        #expect(name.description == "bad_value: items[0].name is not valid: expected a string of 1 to 100 characters after surrounding whitespace is removed, saw a string of 0 characters")

        let prose = try #require(try read("Sure! " + items(rice)).items.failure)
        #expect(prose.reason == .notJSON && prose.description.hasPrefix("not_json: the reply is not one JSON object: expected one JSON object, saw 'S' where a value should start at offset 0 of \"Sure!"))
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
