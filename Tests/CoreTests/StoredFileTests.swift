import Foundation
import Testing

@testable import Core

private struct Sample: Codable, Equatable {
    var version: Int
    var zebra: [Double]
    var apricot: String
}

@Suite struct StoredFileTests {
    @Test func theCurrentVersionIsOne() {
        #expect(StoredFile.version == 1)
    }

    @Test func keysComeSortedAndSlashesStay() throws {
        let data = try StoredFile.encode(Sample(version: 1, zebra: [1.5, 2], apricot: "a/b"))
        #expect(String(decoding: data, as: UTF8.self) == #"{"apricot":"a/b","version":1,"zebra":[1.5,2]}"#)
    }

    @Test func aFileRoundTrips() throws {
        let sample = Sample(version: 1, zebra: [0.1 + 0.2, 33.333333333333336, 1e-7], apricot: "caf\u{E9} \u{1F600}")
        #expect(try StoredFile.decode(Sample.self, from: StoredFile.encode(sample)) == sample)
    }

    @Test func aNumberThatCannotBeWrittenIsAnError() {
        let error = #expect(throws: FormatError.self) {
            try StoredFile.encode(Sample(version: 1, zebra: [.nan], apricot: ""))
        }
        #expect(error?.what == "the data cannot be stored")
    }

    @Test func anotherVersionIsRefusedWithBothVersions() {
        let error = #expect(throws: FormatError.self) {
            try StoredFile.decode(Sample.self, from: Data(#"{"version":2,"zebra":[],"apricot":""}"#.utf8))
        }
        #expect(error?.description == "the file has another version: expected version 1, saw version 2")
    }

    /// A newer file may have another shape. Its version is what the user needs to hear.
    @Test func theVersionIsReadBeforeTheShape() {
        let error = #expect(throws: FormatError.self) {
            try StoredFile.decode(Sample.self, from: Data(#"{"version":7,"other":true}"#.utf8))
        }
        #expect(error?.saw == "version 7")
    }

    @Test(arguments: ["", "not json", "[]", "{}", #"{"version":"1"}"#, #"{"version":1.5}"#, #"{"version":null}"#])
    func aFileWithoutAnIntegerVersionIsNotAStoredFile(text: String) {
        let error = #expect(throws: FormatError.self) { try StoredFile.decode(Sample.self, from: Data(text.utf8)) }
        #expect(error?.what == "the file is not a stored file")
    }

    @Test func aFileOfTheRightVersionButTheWrongShapeNamesTheField() {
        let error = #expect(throws: FormatError.self) {
            try StoredFile.decode(Sample.self, from: Data(#"{"version":1,"zebra":[1,"x"],"apricot":""}"#.utf8))
        }
        #expect(error?.what == "the file cannot be read")
        #expect(error?.expected == "the format of version 1")
        #expect(error?.saw.hasSuffix("at zebra.Index 1") == true)
    }

    @Test func aMissingKeyIsNamed() {
        let error = #expect(throws: FormatError.self) {
            try StoredFile.decode(Sample.self, from: Data(#"{"version":1,"zebra":[]}"#.utf8))
        }
        #expect(error?.saw == "no key apricot at the top")
    }
}
