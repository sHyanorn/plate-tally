import Core
import Foundation
import Testing

@testable import Estimation

private let oneItem = #"{"items": [{"name": "rice", "grams": 100, "kcal": 130}]}"#

@Suite struct EnvelopeTests {
    @Test func thinkingBlocksAreIgnoredAndTextBlocksAreJoinedWithoutSeparator() throws {
        let body = try response(
            blocks: [
                ["type": "thinking", "thinking": "", "signature": "x"],
                ["type": "text", "text": #"{"items": ["#],
                ["type": "text", "text": #"{"name": "rice", "grams": 100, "kcal": 130}]}"#],
            ])
        let reply = try Estimation.read(status: 200, body: body)
        #expect(try reply.items.get() == [FoodItem(name: "rice", grams: 100, kcal: 130)])
    }

    @Test func usageComesWithTheItems() throws {
        let reply = try Estimation.read(status: 200, body: response(text: oneItem, input: 566, output: 107))
        #expect(reply.usage == Usage(inputTokens: 566, outputTokens: 107))
        #expect(try reply.items.get().count == 1)
    }

    /// A call whose reply fails validation is billed all the same (SPEC, Cost).
    @Test func usageComesWithAnInvalidReply() throws {
        let reply = try Estimation.read(status: 200, body: response(text: "nope", input: 1036, output: 3))
        #expect(reply.usage == Usage(inputTokens: 1036, outputTokens: 3))
        #expect(reply.items.failure?.reason == .notJSON)
    }

    @Test func otherFieldsOfTheUsageAreIgnored() throws {
        let extra: [String: Any] = [
            "cache_read_input_tokens": 5, "service_tier": "standard", "speed": "standard",
            "cache_creation": ["ephemeral_5m_input_tokens": 0], "server_tool_use": NSNull(),
        ]
        let reply = try Estimation.read(status: 200, body: response(text: oneItem, extraUsage: extra))
        #expect(reply.usage == Usage(inputTokens: 100, outputTokens: 50))
    }

    @Test func aRefusalIsAnErrorWhateverTheTextSays() throws {
        let reply = try Estimation.read(status: 200, body: response(text: oneItem, stop: "refusal", output: 0))
        #expect(reply.items.failure == .refusal)
        #expect(reply.usage.outputTokens == 0)
    }

    @Test func aCutOffReplyIsAnErrorEvenIfItsTextParses() throws {
        let reply = try Estimation.read(status: 200, body: response(text: oneItem, stop: "max_tokens", output: 600))
        let error = try #require(reply.items.failure)
        #expect(error.reason == .maxTokens)
        #expect(error.description == "max_tokens: the reply was cut off: expected a finished reply, saw stop reason max_tokens after 600 output tokens")
    }

    @Test(arguments: [Optional("end_turn"), "stop_sequence", nil])
    func otherStopReasonsAreRead(stop: String?) throws {
        let reply = try Estimation.read(status: 200, body: response(text: oneItem, stop: stop))
        #expect(try reply.items.get().count == 1)
    }

    @Test func noTextBlockIsAnEmptyText() throws {
        let body = try response(blocks: [["type": "thinking", "thinking": "hm", "signature": "x"]])
        #expect(try Estimation.read(status: 200, body: body).items.failure?.reason == .emptyText)
    }

    @Test(arguments: [
        "", "not json", "[]", "{}", #"{"content": [], "stop_reason": "end_turn"}"#,
        #"{"stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1}}"#,
        #"{"content": "x", "stop_reason": "end_turn", "usage": {"input_tokens": 1, "output_tokens": 1}}"#,
        #"{"content": [], "stop_reason": "end_turn", "usage": {"input_tokens": "1", "output_tokens": 1}}"#,
        #"{"content": [], "stop_reason": "end_turn", "usage": {"input_tokens": 1}}"#,
    ])
    func aBodyWithoutContentAndUsageCannotBeBilledAndThrows(body: String) {
        let error = #expect(throws: EstimationError.self) {
            try Estimation.read(status: 200, body: Data(body.utf8))
        }
        #expect(error?.reason == .badResponse)
    }

    @Test func aMissingUsageIsNamed() {
        let body = #"{"content": [], "stop_reason": "end_turn"}"#
        let error = #expect(throws: EstimationError.self) { try Estimation.read(status: 200, body: Data(body.utf8)) }
        #expect(error?.saw == "no key usage")
    }

    @Test func anErrorBodyGivesStatusTypeAndMessage() {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        let error = #expect(throws: EstimationError.self) { try Estimation.read(status: 401, body: Data(body.utf8)) }
        #expect(
            error?.description
                == "http: the request failed: expected status 200, saw status 401, authentication_error: invalid x-api-key")
    }

    @Test func aBodyThatIsNotAnErrorObjectIsQuoted() {
        let error = #expect(throws: EstimationError.self) {
            try Estimation.read(status: 529, body: Data("<html>Overloaded</html>".utf8))
        }
        #expect(error?.saw == #"status 529, body "<html>Overloaded</html>""#)
    }

    @Test(arguments: [201, 204, 301, 400, 429, 500, 529])
    func onlyStatus200IsAMessage(status: Int) throws {
        let body = try response(text: oneItem)
        let error = #expect(throws: EstimationError.self) { try Estimation.read(status: status, body: body) }
        #expect(error?.reason == .http)
    }
}
