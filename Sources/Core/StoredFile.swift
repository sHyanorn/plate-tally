import Foundation

/// A stored file that the package cannot read or write.
public struct FormatError: PlateError, Equatable {
    public let what: String
    public let expected: String
    public let saw: String
}

/// The files the package defines (D013) are one JSON object: {"version": 1, "<name>": [...]}.
/// The package gives the bytes and takes the bytes. Where they live is the app's business.
public enum StoredFile {
    public static let version = 1

    /// The same bytes every time: sorted keys, slashes as they are.
    public static func encode<File: Encodable>(_ file: File) throws(FormatError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try encoder.encode(file)
        } catch {
            throw FormatError(
                what: "the data cannot be stored", expected: "numbers that are finite", saw: describe(error))
        }
    }

    /// Reads the version first. A file of another version may have another shape, so its version is
    /// reported and not an error about a field.
    public static func decode<File: Decodable>(_ type: File.Type, from data: Data) throws(FormatError) -> File {
        let header: Header
        do {
            header = try JSONDecoder().decode(Header.self, from: data)
        } catch {
            throw FormatError(
                what: "the file is not a stored file", expected: "a JSON object with an integer version",
                saw: describe(error))
        }
        guard header.version == version else {
            throw FormatError(
                what: "the file has another version", expected: "version \(version)", saw: "version \(header.version)")
        }
        do {
            return try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw FormatError(
                what: "the file cannot be read", expected: "the format of version \(version)", saw: describe(error))
        }
    }
}

private struct Header: Decodable {
    let version: Int
}

private func describe(_ error: Error) -> String {
    func path(_ context: DecodingError.Context) -> String {
        context.codingPath.isEmpty ? "the top" : context.codingPath.map(\.stringValue).joined(separator: ".")
    }
    switch error {
    case DecodingError.keyNotFound(let key, let context): return "no key \(key.stringValue) at \(path(context))"
    case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context),
        DecodingError.dataCorrupted(let context):
        return "\(context.debugDescription) at \(path(context))"
    default: return String(describing: error)
    }
}
