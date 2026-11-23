import Foundation

/// A value that lives in one stored file (D013). The package gives the bytes and takes the bytes.
public protocol StoredValue {
    /// What the file holds before the first save.
    init()
    init(decoding data: Data) throws(FormatError)
    func encoded() throws(FormatError) -> Data
}

/// A file that cannot be read or written. The place is in `saw`, because a screen shows only this text.
public struct StoreError: PlateError, Equatable {
    public let what: String
    public let expected: String
    public let saw: String
}

/// One file that holds one value, read and written whole. The app chooses the URL (D013).
public struct FileStore<Value: StoredValue>: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// A missing file is a first start and gives the empty value. A file that is there and cannot be
    /// read is an error, so the caller never overwrites a file it did not understand.
    public func load() throws(StoreError) -> Value {
        guard FileManager.default.fileExists(atPath: url.path) else { return Value() }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError(
                what: "the file cannot be read", expected: "a readable file",
                saw: "\(url.path): \(error.localizedDescription)")
        }
        do throws(FormatError) {
            return try Value(decoding: data)
        } catch {
            throw StoreError(what: error.what, expected: error.expected, saw: "\(error.saw) in \(url.path)")
        }
    }

    /// Writes the whole file. The bytes go to a temporary file that then replaces the old one, so a
    /// crash leaves the old file or the new one and never half of one.
    public func save(_ value: Value) throws(StoreError) {
        let data: Data
        do throws(FormatError) {
            data = try value.encoded()
        } catch {
            throw StoreError(what: error.what, expected: error.expected, saw: "\(error.saw) for \(url.path)")
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError(
                what: "the file cannot be written", expected: "a writable place",
                saw: "\(url.path): \(error.localizedDescription)")
        }
    }
}
