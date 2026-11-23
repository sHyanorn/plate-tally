/// Any `PlateError` as a plain value. A screen holds one of these whatever module the error came from,
/// and it compares, which an existential error does not. `code` is the reason code of a rejected reply (R6).
public struct Problem: PlateError, Equatable {
    public let code: String?
    public let what: String
    public let expected: String
    public let saw: String

    public init(_ error: some PlateError, code: String? = nil) {
        self.code = code
        self.what = error.what
        self.expected = error.expected
        self.saw = error.saw
    }

    public var description: String {
        let message = "\(what): expected \(expected), saw \(saw)"
        return code.map { "\($0): \(message)" } ?? message
    }
}
