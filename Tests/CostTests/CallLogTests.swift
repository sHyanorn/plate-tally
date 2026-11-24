import Core
import Estimation
import Foundation
import Testing

@testable import Cost

private let sonnet = "claude-sonnet-5-5"

private func day(_ text: String) throws -> LocalDay { try LocalDay(text) }

private func call(_ at: String, input: Int = 1000, output: Int = 100) throws -> CallRecord {
    try CallRecord(at: LocalDateTime(at), model: sonnet, usage: Usage(inputTokens: input, outputTokens: output))
}

/// 1,000 input and 100 output tokens: 0.002 + 0.001.
private let usd003 = decimal("0.003")

private func log(_ calls: CallRecord...) -> CallLog {
    var log = CallLog()
    for call in calls { log.add(call) }
    return log
}

@Suite struct CallRecordTests {
    @Test func theCostIsWorkedOutFromTheUsageAndTheTable() throws {
        let record = try call("2026-11-23T12:30", input: 566, output: 107)
        #expect(record.costUSD == decimal("0.002202"))
        #expect(record.usage == Usage(inputTokens: 566, outputTokens: 107))
    }

    /// The reply carries the usage, and a failed call has no reply, so there is nothing to put in a record.
    @Test func aCallThatFailsWithAnHTTPErrorGivesNoReplyAndNoUsage() {
        let body = Data(#"{"error":{"type":"api_error","message":"Internal server error"}}"#.utf8)
        let error = #expect(throws: EstimationError.self) { try Estimation.read(status: 500, body: body) }
        #expect(error?.reason == .http)
    }

    @Test func aCallToAnUnknownModelHasNoRecord() throws {
        #expect(throws: CostError.self) {
            try CallRecord(at: LocalDateTime("2026-11-23T12:30"), model: "no-such-model", usage: Usage(inputTokens: 1, outputTokens: 1))
        }
    }
}

@Suite struct TotalsTests {
    @Test func aNewLogHasNoCallsAndNoCost() throws {
        let empty = CallLog()
        #expect(empty.count(on: try day("2026-11-23")) == 0)
        #expect(empty.total(on: try day("2026-11-23")) == 0)
        #expect(empty.total(inMonthOf: try day("2026-11-23")) == 0)
    }

    @Test func aDayCountsAndSumsItsOwnCalls() throws {
        let calls = log(
            try call("2026-11-23T08:00"), try call("2026-11-23T12:30", input: 566, output: 107),
            try call("2026-11-24T08:00"))
        #expect(calls.count(on: try day("2026-11-23")) == 2)
        #expect(calls.total(on: try day("2026-11-23")) == usd003 + decimal("0.002202"))
        #expect(calls.count(on: try day("2026-11-24")) == 1)
        #expect(calls.total(on: try day("2026-11-24")) == usd003)
    }

    @Test func aDayIsAYearAMonthAndADayNotOnlyADayOfTheMonth() throws {
        let calls = log(try call("2026-11-23T12:00"), try call("2026-12-23T12:00"), try call("2025-11-23T12:00"))
        #expect(calls.count(on: try day("2026-11-23")) == 1)
        #expect(calls.total(on: try day("2026-11-23")) == usd003)
    }

    @Test func aCallBelongsToTheDayOfItsLocalTimeAcrossMidnight() throws {
        let calls = log(try call("2026-11-23T23:59"), try call("2026-11-24T00:00"), try call("2026-11-24T00:01"))
        #expect(calls.count(on: try day("2026-11-23")) == 1)
        #expect(calls.count(on: try day("2026-11-24")) == 2)
        #expect(calls.total(on: try day("2026-11-24")) == usd003 * 2)
    }

    @Test func aMonthHoldsEveryDayOfThatMonthAndNoOtherMonth() throws {
        let calls = log(
            try call("2026-10-31T23:59"), try call("2026-11-01T00:00"), try call("2026-11-15T12:00"),
            try call("2026-11-30T23:59"), try call("2026-12-01T00:00"))
        for anyDay in ["2026-11-01", "2026-11-15", "2026-11-30"] {
            #expect(calls.total(inMonthOf: try day(anyDay)) == usd003 * 3, "from \(anyDay)")
        }
        #expect(calls.total(inMonthOf: try day("2026-12-31")) == usd003)
        #expect(calls.total(inMonthOf: try day("2026-10-01")) == usd003)
    }

    @Test func aMonthOfAnotherYearIsAnotherMonth() throws {
        let calls = log(try call("2025-11-23T12:00"), try call("2026-11-23T12:00"), try call("2026-11-24T12:00"))
        #expect(calls.total(inMonthOf: try day("2026-11-01")) == usd003 * 2)
        #expect(calls.total(inMonthOf: try day("2025-11-30")) == usd003)
    }

    @Test func theYearEndFallsInTwoMonths() throws {
        let calls = log(try call("2026-12-31T23:59"), try call("2027-01-01T00:00"))
        #expect(calls.total(inMonthOf: try day("2026-12-15")) == usd003)
        #expect(calls.total(inMonthOf: try day("2027-01-15")) == usd003)
    }
}

@Suite struct LimitTests {
    private func callsToday(_ count: Int) throws -> CallLog {
        var log = CallLog()
        for minute in 0..<count { log.add(try call("2026-11-23T10:\(String(format: "%02d", minute))")) }
        return log
    }

    @Test func theDefaultLimitIs30() {
        #expect(CallLog.defaultDailyLimit == 30)
    }

    @Test func the30thCallIsAllowedAndThe31stRefused() throws {
        let today = try day("2026-11-23")
        #expect(throws: Never.self) { try self.callsToday(29).requireRoom(on: today, limit: CallLog.defaultDailyLimit, inFlight: 0) }
        let error = #expect(throws: CostError.self) {
            try self.callsToday(30).requireRoom(on: today, limit: CallLog.defaultDailyLimit, inFlight: 0)
        }
        #expect(error == .limitReached(limit: 30, count: 30))
        #expect(error?.description == "the daily call limit is reached: expected fewer than 30 calls today, saw 30 calls")
    }

    @Test func theLimitComesFromTheCaller() throws {
        let today = try day("2026-11-23")
        #expect(throws: CostError.limitReached(limit: 5, count: 5)) { try self.callsToday(5).requireRoom(on: today, limit: 5, inFlight: 0) }
        #expect(throws: Never.self) { try self.callsToday(5).requireRoom(on: today, limit: 6, inFlight: 0) }
        #expect(throws: CostError.limitReached(limit: 0, count: 0)) { try CallLog().requireRoom(on: today, limit: 0, inFlight: 0) }
    }

    @Test func theLimitCountsOnlyTheDayAsked() throws {
        let full = try callsToday(30)
        #expect(throws: Never.self) { try full.requireRoom(on: try day("2026-11-24"), limit: 30, inFlight: 0) }
        #expect(throws: Never.self) { try full.requireRoom(on: try day("2026-11-22"), limit: 30, inFlight: 0) }
    }

    /// A call in flight has no record yet and counts all the same, so overlapping analyses share the limit.
    @Test func callsInFlightCountWithTheLoggedOnes() throws {
        let today = try day("2026-11-23")
        #expect(throws: Never.self) { try self.callsToday(4).requireRoom(on: today, limit: 5, inFlight: 0) }
        #expect(throws: CostError.limitReached(limit: 5, count: 5)) {
            try self.callsToday(4).requireRoom(on: today, limit: 5, inFlight: 1)
        }
    }

    @Test func callsPastTheLimitAreStillCounted() throws {
        #expect(try callsToday(31).count(on: try day("2026-11-23")) == 31)
    }
}

@Suite struct CallLogFileTests {
    private let oneCall =
        #"{"calls":[{"at":"2026-11-23T12:30","costUSD":"0.002202","model":"claude-sonnet-5-5","usage":{"inputTokens":566,"outputTokens":107}}],"version":1}"#

    @Test func theFileIsTheDocumentedJSONWithTheCostAsText() throws {
        let data = try log(try call("2026-11-23T12:30", input: 566, output: 107)).encoded()
        #expect(String(decoding: data, as: UTF8.self) == oneCall)
    }

    @Test func anEmptyLogIsAVersionAndAnEmptyList() throws {
        #expect(String(decoding: try CallLog().encoded(), as: UTF8.self) == #"{"calls":[],"version":1}"#)
    }

    @Test func aLogRoundTripsWithItsExactCosts() throws {
        let saved = log(try call("2026-11-23T12:30", input: 566, output: 107), try call("2026-11-24T00:00", input: 1, output: 0))
        let again = try CallLog(decoding: saved.encoded())
        #expect(again == saved)
        #expect(again.total(inMonthOf: try day("2026-11-23")) == decimal("0.002202") + decimal("0.000002"))
        #expect(try again.encoded() == saved.encoded())
    }

    @Test func aReadLogCountsAndLimitsAsBefore() throws {
        let again = try CallLog(decoding: Data(oneCall.utf8))
        #expect(again.count(on: try day("2026-11-23")) == 1)
        #expect(throws: CostError.limitReached(limit: 1, count: 1)) { try again.requireRoom(on: try day("2026-11-23"), limit: 1, inFlight: 0) }
    }

    /// A price that changes later must not change what an old call cost.
    @Test func aStoredCostIsKeptNotWorkedOutAgain() throws {
        let text = oneCall.replacingOccurrences(of: "0.002202", with: "9.99")
        #expect(try CallLog(decoding: Data(text.utf8)).calls.first?.costUSD == decimal("9.99"))
    }

    @Test func aFileOfAnotherVersionIsRefusedWithBothVersions() {
        let error = #expect(throws: FormatError.self) { try CallLog(decoding: Data(#"{"calls":[],"version":2}"#.utf8)) }
        #expect(error?.description == "the file has another version: expected version 1, saw version 2")
    }

    @Test(arguments: ["abc", "", "1.5x", "-1", "1e3", "1.2.3", ".5", "5.", "+1", " 1", "\u{661}\u{662}", "NaN"])
    func aCostThatIsNotPlainDecimalTextIsRefused(cost: String) {
        let text = oneCall.replacingOccurrences(of: "0.002202", with: cost)
        #expect(throws: FormatError.self) { try CallLog(decoding: Data(text.utf8)) }
    }

    @Test(arguments: ["0", "12", "0.002202", "0.000002", "1234.5678"])
    func aPlainDecimalCostIsRead(cost: String) throws {
        let text = oneCall.replacingOccurrences(of: "0.002202", with: cost)
        #expect(try CallLog(decoding: Data(text.utf8)).calls.first?.costUSD == decimal(cost))
    }

    @Test func aCostThatIsNotTextSaysSoAtItsPlace() {
        let text = oneCall.replacingOccurrences(of: "0.002202", with: "abc")
        let error = #expect(throws: FormatError.self) { try CallLog(decoding: Data(text.utf8)) }
        #expect(
            error?.description
                == #"the file cannot be read: expected the format of version 1, saw not a decimal number written as text: "abc" at calls.Index 0.costUSD"#
        )
    }

    @Test func aBadDateIsReportedWithItsPlaceInTheFile() {
        let text = oneCall.replacingOccurrences(of: "2026-11-23T12:30", with: "2026-02-30T12:00")
        let error = #expect(throws: FormatError.self) { try CallLog(decoding: Data(text.utf8)) }
        #expect(
            error?.description
                == #"the file cannot be read: expected the format of version 1, saw not a calendar day and time written as YYYY-MM-DDTHH:MM: "2026-02-30T12:00" at calls.Index 0.at"#
        )
    }

    @Test func aCostWrittenAsANumberIsRefused() {
        let text = oneCall.replacingOccurrences(of: #""0.002202""#, with: "0.002202")
        #expect(throws: FormatError.self) { try CallLog(decoding: Data(text.utf8)) }
    }

    @Test(arguments: [
        "", "[]", "{}", #"{"calls":[]}"#, #"{"version":1}"#, #"{"version":1,"calls":{}}"#, #"{"version":1,"calls":[{}]}"#,
        #"{"version":1,"calls":[{"at":"2026-13-01T00:00","costUSD":"1","model":"m","usage":{"inputTokens":1,"outputTokens":1}}]}"#,
        #"{"version":1,"calls":[{"at":"2026-11-23T12:30","costUSD":"1","model":"m","usage":{"inputTokens":"1","outputTokens":1}}]}"#,
    ])
    func aFileThatIsNotTheFormatIsRefused(text: String) {
        #expect(throws: FormatError.self) { try CallLog(decoding: Data(text.utf8)) }
    }
}
