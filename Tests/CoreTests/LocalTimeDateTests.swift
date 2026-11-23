import Foundation
import Testing

@testable import Core

private func zone(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

@Suite struct LocalDateTimeInstantTests {
    /// 2026-11-23T12:30:00Z is 1,795,437,000 seconds after the epoch.
    @Test func aLocalTimeInUTCIsTheKnownInstant() throws {
        let time = try LocalDateTime("2026-11-23T12:30")
        #expect(time.date(in: zone("UTC")) == Date(timeIntervalSince1970: 1_795_437_000))
    }

    @Test func theSameLocalTimeIsAnEarlierInstantEastOfGreenwich() throws {
        let time = try LocalDateTime("2026-11-23T20:30")
        #expect(time.date(in: zone("Asia/Shanghai")) == Date(timeIntervalSince1970: 1_795_437_000))
    }

    @Test(arguments: ["UTC", "Asia/Shanghai", "America/New_York", "Pacific/Auckland"])
    func theInstantGoesBackToTheSameLocalTime(id: String) throws {
        let time = try LocalDateTime("2026-07-04T09:05")
        #expect(try LocalDateTime(time.date(in: zone(id)), in: zone(id)) == time)
    }
}
