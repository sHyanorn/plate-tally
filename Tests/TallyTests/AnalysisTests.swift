import Core
import Cost
import Estimation
import Foundation
import Testing

@testable import Tally

private let noon = try! LocalDateTime("2026-11-23T12:30")

private func logWithCalls(_ count: Int, on day: String = "2026-11-23") throws -> CallLog {
    var log = CallLog()
    for _ in 0..<count {
        log.add(try CallRecord(at: LocalDateTime("\(day)T08:00"), model: Estimation.model, usage: Usage(inputTokens: 1, outputTokens: 1)))
    }
    return log
}

private func run(_ transport: RecordingTransport) async throws -> Analysis.Outcome {
    await Analysis.run(image: try testImage(), at: noon, send: transport.transport)
}

/// The check before a call. That nothing is sent when it refuses is tested on AppModel, which asks it.
@Suite struct RefusalTests {
    @Test func theMissingKeyIsSaidInThreeParts() {
        let problem = Problem(MissingKey())
        #expect(problem.description == "no API key is set: expected a key saved in settings, saw no key")
    }

    @Test func atTheLimitTheLimitAndTheCountAreSaid() throws {
        let problem = try Analysis.refusal(hasKey: true, log: logWithCalls(3), inFlight: 0, on: noon.day, limit: 3)
        #expect(problem?.description == "the daily call limit is reached: expected fewer than 3 calls today, saw 3 calls")
    }

    @Test func callsOfAnotherDayDoNotCount() throws {
        #expect(try Analysis.refusal(hasKey: true, log: logWithCalls(5, on: "2026-11-22"), inFlight: 0, on: noon.day, limit: 3) == nil)
    }

    @Test func aCallInFlightCountsAgainstTheLimit() throws {
        #expect(try Analysis.refusal(hasKey: true, log: logWithCalls(2), inFlight: 0, on: noon.day, limit: 3) == nil)
        #expect(try Analysis.refusal(hasKey: true, log: logWithCalls(2), inFlight: 1, on: noon.day, limit: 3)?.saw == "3 calls")
    }

    @Test func theRefusalCanBeAskedBeforeAPhotoIsTaken() throws {
        let day = noon.day
        #expect(Analysis.refusal(hasKey: true, log: CallLog(), inFlight: 0, on: day, limit: 30) == nil)
        #expect(Analysis.refusal(hasKey: false, log: CallLog(), inFlight: 0, on: day, limit: 30)?.what == "no API key is set")
        #expect(try Analysis.refusal(hasKey: true, log: logWithCalls(30), inFlight: 0, on: day, limit: 30)?.saw == "30 calls")
        // A missing key comes first, because the limit cannot be fixed by the user the same way.
        #expect(try Analysis.refusal(hasKey: false, log: logWithCalls(30), inFlight: 0, on: day, limit: 30)?.what == "no API key is set")
    }
}

@Suite struct RunTests {
    @Test func aValidReplyGivesTheItemsAndTheBilledCall() async throws {
        let transport = RecordingTransport(status: 200, body: try responseBody(text: twoItems))
        let outcome = try await run(transport)
        #expect(try outcome.items.get() == [FoodItem(name: "rice", grams: 150, kcal: 195), FoodItem(name: "chicken", grams: 100, kcal: 165)])
        let call = try #require(outcome.call)
        #expect(call.costUSD == usd0035)
        #expect(call.at == noon)
        #expect(call.model == "claude-sonnet-5-5")
    }

    @Test func theRequestGoesToTheAPIWithoutAKey() async throws {
        let transport = RecordingTransport(status: 200, body: try responseBody(text: twoItems))
        _ = try await run(transport)
        let request = try #require(transport.sent.first)
        #expect(transport.sent.count == 1)
        #expect(request.url.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.method == "POST")
        // The app adds the key at the last moment (R23).
        #expect(request.headers.keys.sorted() == ["anthropic-version", "content-type"])
    }

    /// A reply that fails R5 was still billed, so it is costed and logged (SPEC, Cost).
    @Test func aRejectedReplyIsBilledAndShownWithItsReasonCode() async throws {
        let transport = RecordingTransport(status: 200, body: try responseBody(text: "Here you go: \(twoItems)"))
        let outcome = try await run(transport)
        #expect(outcome.call?.costUSD == usd0035)
        guard case .failure(let problem) = outcome.items else { Issue.record("expected a rejection"); return }
        #expect(problem.code == "not_json")
    }

    @Test func anHTTPErrorIsNotBilledAndHasItsCode() async throws {
        let body = Data(#"{"error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
        let outcome = try await run(RecordingTransport(status: 529, body: body))
        #expect(outcome.call == nil)
        guard case .failure(let problem) = outcome.items else { Issue.record("expected an error"); return }
        #expect(problem.code == "http")
        #expect(problem.saw == "status 529, overloaded_error: Overloaded")
    }

    @Test func aResponseWithoutUsageIsNotBilled() async throws {
        let outcome = try await run(RecordingTransport(status: 200, body: Data(#"{"content":[]}"#.utf8)))
        #expect(outcome.call == nil)
        guard case .failure(let problem) = outcome.items else { Issue.record("expected an error"); return }
        #expect(problem.code == "bad_response")
    }

    /// The response states its tokens, so it was billed, though it has no content (SPEC, Cost).
    @Test func aResponseWithUsageButNoContentIsBilledAndIsABadResponse() async throws {
        let body = Data(#"{"stop_reason":"end_turn","usage":{"input_tokens":1200,"output_tokens":110}}"#.utf8)
        let outcome = try await run(RecordingTransport(status: 200, body: body))
        #expect(outcome.call?.costUSD == usd0035)
        guard case .failure(let problem) = outcome.items else { Issue.record("expected an error"); return }
        #expect(problem.code == "bad_response")
    }

    @Test func aFailureOfTheNetworkIsNotBilledAndIsNotRepeated() async throws {
        let failure = TransportFailure(
            what: "the request did not complete", expected: "a response from api.anthropic.com",
            saw: "-1009 (offline)")
        let transport = RecordingTransport(.failure(failure))
        let outcome = try await run(transport)
        #expect(outcome.call == nil)
        #expect(outcome.items == .failure(Problem(failure)))
        #expect(transport.sent.count == 1)
    }

    @Test func aRefusedReplyIsBilledToo() async throws {
        let message: [String: Any] = [
            "content": [], "stop_reason": "refusal", "usage": ["input_tokens": 1000, "output_tokens": 5],
        ]
        let transport = RecordingTransport(status: 200, body: try JSONSerialization.data(withJSONObject: message))
        let outcome = try await run(transport)
        #expect(outcome.call?.usage == Usage(inputTokens: 1000, outputTokens: 5))
        guard case .failure(let problem) = outcome.items else { Issue.record("expected a refusal"); return }
        #expect(problem.code == "refusal")
    }
}
