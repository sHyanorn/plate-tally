import Foundation
import Testing

@testable import Core

@Suite struct LocalDayTests {
    @Test(arguments: ["2026-11-23", "0001-01-01", "9999-12-31", "2024-02-29", "2000-02-29"])
    func textRoundTrip(text: String) throws {
        #expect(try LocalDay(text).description == text)
    }

    @Test(arguments: [
        "2023-02-29", "1900-02-29", "2026-13-01", "2026-00-10", "2026-11-00", "2026-11-31",
        "2026-4-05", "26-11-23", "2026/11/23", "2026-11-23T10:00", "+026-11-23", "2026-11-23-1",
        "0000-01-01", "",
    ])
    func rejectsText(text: String) {
        #expect(throws: DateError.self) { try LocalDay(text) }
    }

    @Test func errorSaysWhatWasExpectedAndSeen() {
        let error = #expect(throws: DateError.self) { try LocalDay("2026-4-05") }
        #expect(error?.description == "not a day text: expected YYYY-MM-DD, saw \"2026-4-05\"")
    }

    @Test func monthLengthsAndLeapYears() throws {
        #expect(throws: Never.self) { try LocalDay(year: 2000, month: 2, day: 29) }
        #expect(throws: DateError.self) { try LocalDay(year: 1900, month: 2, day: 29) }
        #expect(throws: Never.self) { try LocalDay(year: 2026, month: 4, day: 30) }
        #expect(throws: DateError.self) { try LocalDay(year: 2026, month: 4, day: 31) }
    }

    @Test func ordersByYearThenMonthThenDay() throws {
        #expect(try LocalDay("2026-11-30") < LocalDay("2026-12-01"))
        #expect(try LocalDay("2025-12-31") < LocalDay("2026-01-01"))
        #expect(try LocalDay("2026-11-23") == LocalDay(year: 2026, month: 11, day: 23))
    }

    @Test func encodesAsOneString() throws {
        let day = try LocalDay("2026-11-23")
        let data = try JSONEncoder().encode([day])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-23"]"#)
        #expect(try JSONDecoder().decode([LocalDay].self, from: data) == [day])
    }

    @Test func decodingABadTextFailsAtItsPlace() {
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDay].self, from: Data(#"["2026-02-30"]"#.utf8))
        }
        guard case .dataCorrupted(let context)? = error else {
            Issue.record("not a dataCorrupted error: \(String(describing: error))")
            return
        }
        #expect(context.debugDescription == #"not a calendar day written as YYYY-MM-DD: "2026-02-30""#)
        #expect(context.codingPath.map(\.stringValue) == ["Index 0"])
    }
}

@Suite struct LocalDateTimeTests {
    @Test(arguments: ["2026-11-23T12:30", "2026-11-23T00:00", "2026-11-23T23:59"])
    func textRoundTrip(text: String) throws {
        #expect(try LocalDateTime(text).description == text)
    }

    @Test(arguments: [
        "2026-11-23T24:00", "2026-11-23T12:60", "2026-11-23T1:30", "2026-11-23 12:30",
        "2026-11-23", "2026-11-23T12:30:00", "2026-11-23T+1:30", "2026-02-30T12:00", "T12:30",
    ])
    func rejectsText(text: String) {
        #expect(throws: DateError.self) { try LocalDateTime(text) }
    }

    @Test func ordersByDayThenTime() throws {
        #expect(try LocalDateTime("2026-11-23T23:59") < LocalDateTime("2026-11-24T00:00"))
        #expect(try LocalDateTime("2026-11-23T08:05") < LocalDateTime("2026-11-23T08:06"))
        #expect(try LocalDateTime("2026-11-23T08:05").day == LocalDay("2026-11-23"))
    }

    @Test func encodesAsOneString() throws {
        let moment = try LocalDateTime("2026-11-23T12:30")
        let data = try JSONEncoder().encode([moment])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-23T12:30"]"#)
        #expect(try JSONDecoder().decode([LocalDateTime].self, from: data) == [moment])
    }

    @Test func decodingABadTextFailsAtItsPlace() {
        let error = #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LocalDateTime].self, from: Data(#"["2026-02-30T12:00"]"#.utf8))
        }
        guard case .dataCorrupted(let context)? = error else {
            Issue.record("not a dataCorrupted error: \(String(describing: error))")
            return
        }
        #expect(
            context.debugDescription
                == #"not a calendar day and time written as YYYY-MM-DDTHH:MM: "2026-02-30T12:00""#)
        #expect(context.codingPath.map(\.stringValue) == ["Index 0"])
    }

    /// 2026-11-22T20:30:00Z read in three time zones, and a year change.
    @Test(arguments: [
        (0, "2026-11-22T20:30"), (8 * 3600, "2026-11-23T04:30"), (-5 * 3600, "2026-11-22T15:30"),
    ])
    func localTimeOfAnInstant(offset: Int, expected: String) throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-11-22T20:30:00Z"))
        let zone = try #require(TimeZone(secondsFromGMT: offset))
        #expect(try LocalDateTime(instant, in: zone).description == expected)
    }

    @Test func instantCrossesTheYear() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-12-31T16:00:00Z"))
        let zone = try #require(TimeZone(secondsFromGMT: 8 * 3600))
        #expect(try LocalDateTime(instant, in: zone).description == "2027-01-01T00:00")
    }

    /// The first second of year 1 and the last of year 9999, in UTC. Foundation reads year 1 in the
    /// Julian calendar, so its first second is 62,135,769,600 s before 1970, not 62,135,596,800.
    @Test(arguments: [(-62_135_769_600.0, "0001-01-01T00:00"), (253_402_300_799.0, "9999-12-31T23:59")])
    func theFirstAndLastInstantsOfTheSupportedYearsAreRead(seconds: Double, expected: String) throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(try LocalDateTime(Date(timeIntervalSince1970: seconds), in: zone).description == expected)
    }

    /// 253,402,300,800 s is 10000-01-01T00:00:00Z. One second before year 1 reads as 0001-12-31 of era 0.
    /// A Date is a Double, so it can also be NaN or infinite, and NaN reads as 4713 BC.
    @Test(arguments: [253_402_300_800.0, -62_135_769_601.0, Double.infinity, -Double.infinity, Double.nan])
    func anInstantBeyondTheSupportedYearsIsRefused(seconds: Double) throws {
        let zone = try #require(TimeZone(secondsFromGMT: 0))
        #expect(throws: DateError.self) { try LocalDateTime(Date(timeIntervalSince1970: seconds), in: zone) }
    }
}
