import Foundation
import Testing

@testable import Core

private struct Note: StoredValue, Equatable {
    private struct File: Codable {
        var version: Int
        var text: String
    }

    var text = ""

    init() {}

    init(_ text: String) { self.text = text }

    init(decoding data: Data) throws(FormatError) {
        self.text = try StoredFile.decode(File.self, from: data).text
    }

    func encoded() throws(FormatError) -> Data {
        if text == "unwritable" {
            throw FormatError(what: "the note cannot be stored", expected: "another text", saw: text)
        }
        return try StoredFile.encode(File(version: StoredFile.version, text: text))
    }
}

/// A fresh place for each test. The system cleans the temporary directory, so the tests remove nothing.
private func place(_ name: String = "notes.json") -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("plate-tally-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

@Suite struct FileStoreTests {
    @Test func aMissingFileGivesTheEmptyValue() throws {
        #expect(try FileStore<Note>(url: place()).load() == Note())
    }

    @Test func aSavedValueComesBackAndTheFolderIsMade() throws {
        let store = FileStore<Note>(url: place("deep/er/notes.json"))
        try store.save(Note("rice"))
        #expect(try store.load() == Note("rice"))
    }

    @Test func aSaveReplacesTheWholeFile() throws {
        let store = FileStore<Note>(url: place())
        try store.save(Note("a long first text"))
        try store.save(Note("b"))
        #expect(try store.load() == Note("b"))
        #expect(String(decoding: try Data(contentsOf: store.url), as: UTF8.self) == #"{"text":"b","version":1}"#)
    }

    @Test func aFileThatCannotBeReadIsAnErrorWithItsPathAndStaysAsItIs() throws {
        let store = FileStore<Note>(url: place())
        try store.save(Note("kept"))
        let damaged = Data("not json".utf8)
        try damaged.write(to: store.url)
        let error = #expect(throws: StoreError.self) { try store.load() }
        #expect(error?.what == "the file is not a stored file")
        #expect(error?.saw.hasSuffix(" in \(store.url.path)") == true)
        #expect(try Data(contentsOf: store.url) == damaged)
    }

    @Test func aFileOfAnotherVersionNamesBothVersionsAndThePath() throws {
        let store = FileStore<Note>(url: place())
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"version":2,"text":""}"#.utf8).write(to: store.url)
        let error = #expect(throws: StoreError.self) { try store.load() }
        #expect(error?.description == "the file has another version: expected version 1, saw version 2 in \(store.url.path)")
    }

    @Test func aPlaceThatCannotBeWrittenIsAnError() throws {
        let blocker = place()
        try FileManager.default.createDirectory(
            at: blocker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: blocker)
        // The parent of this file is a regular file, so no folder can be made there.
        let store = FileStore<Note>(url: blocker.appendingPathComponent("notes.json"))
        let error = #expect(throws: StoreError.self) { try store.save(Note("x")) }
        #expect(error?.what == "the file cannot be written")
        #expect(error?.saw.hasPrefix(store.url.path) == true)
    }

    @Test func aValueThatCannotBeEncodedWritesNothing() throws {
        let store = FileStore<Note>(url: place())
        let error = #expect(throws: StoreError.self) { try store.save(Note("unwritable")) }
        #expect(error?.what == "the note cannot be stored")
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
    }
}

@Suite struct ProblemTests {
    @Test func aProblemKeepsTheThreePartsOfTheError() {
        let problem = Problem(FormatError(what: "w", expected: "e", saw: "s"))
        #expect(problem.description == "w: expected e, saw s")
        #expect(problem.code == nil)
    }

    @Test func theReasonCodeComesFirstInTheDescription() {
        let problem = Problem(FormatError(what: "w", expected: "e", saw: "s"), code: "not_json")
        #expect(problem.description == "not_json: w: expected e, saw s")
        #expect(problem == Problem(FormatError(what: "w", expected: "e", saw: "s"), code: "not_json"))
    }
}
