/// The tokens a call was billed for, from the `usage` fields of the response.
public struct Usage: Equatable, Sendable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}
