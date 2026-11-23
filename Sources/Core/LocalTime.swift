import Foundation

public struct DateError: PlateError, Equatable {
    public let what: String
    public let expected: String
    public let saw: String
}

/// A calendar day as the user lives it, with no time zone. Day totals and month totals group
/// by it, so a change of time zone cannot move a stored record to another day.
public struct LocalDay: Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws(DateError) {
        guard (1...9999).contains(year), (1...12).contains(month),
            (1...Self.daysIn(month: month, year: year)).contains(day)
        else {
            throw DateError(
                what: "not a calendar day",
                expected: "a day from 0001-01-01 to 9999-12-31",
                saw: "\(year)-\(month)-\(day)")
        }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads YYYY-MM-DD.
    public init(_ text: String) throws(DateError) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy(isDigits),
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            throw DateError(what: "not a day text", expected: "YYYY-MM-DD", saw: "\"\(text)\"")
        }
        try self.init(year: year, month: month, day: day)
    }

    public static func < (a: LocalDay, b: LocalDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

extension LocalDay: CustomStringConvertible, Codable {
    public var description: String { "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))" }

    /// A DateError would pass through the decoder with no coding path, so it is turned into one that has.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            try self.init(text)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "not a calendar day written as YYYY-MM-DD: \"\(text)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// A day and a time of day, to the minute, with no time zone.
public struct LocalDateTime: Hashable, Comparable, Sendable {
    public let day: LocalDay
    public let hour: Int
    public let minute: Int

    public init(day: LocalDay, hour: Int, minute: Int) throws(DateError) {
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            throw DateError(
                what: "not a time of day", expected: "hour 0 to 23 and minute 0 to 59",
                saw: "\(hour):\(minute)")
        }
        self.day = day
        self.hour = hour
        self.minute = minute
    }

    /// Reads YYYY-MM-DDTHH:MM.
    public init(_ text: String) throws(DateError) {
        let parts = text.split(separator: "T", omittingEmptySubsequences: false)
        let clock = parts.count == 2 ? parts[1].split(separator: ":", omittingEmptySubsequences: false) : []
        guard clock.count == 2, clock.allSatisfy({ $0.count == 2 }), clock.allSatisfy(isDigits),
            let hour = Int(clock[0]), let minute = Int(clock[1])
        else {
            throw DateError(
                what: "not a date and time text", expected: "YYYY-MM-DDTHH:MM", saw: "\"\(text)\"")
        }
        try self.init(day: LocalDay(String(parts[0])), hour: hour, minute: minute)
    }

    /// The Gregorian day and time of an instant in the given time zone. The calendar is fixed so
    /// that the region settings of the user (Buddhist years, a 13th month) cannot leak in. An instant
    /// outside the years 1 to 9999 is refused. Foundation reads the days before 1582-10-15 in the
    /// Julian calendar.
    public init(_ date: Date, in timeZone: TimeZone) throws(DateError) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func part(_ component: Calendar.Component) -> Int { calendar.component(component, from: date) }
        // Before the common era (era 0) the calendar counts years upward, and it gives NaN and
        // negative infinity as 4713 BC, which LocalDay would take for the year 4713.
        guard part(.era) == 1 else {
            throw DateError(
                what: "not an instant of the common era", expected: "an instant from 0001-01-01 to 9999-12-31",
                saw: "\(date.timeIntervalSince1970) seconds since 1970")
        }
        try self.init(
            day: LocalDay(year: part(.year), month: part(.month), day: part(.day)),
            hour: part(.hour), minute: part(.minute))
    }

    public static func < (a: LocalDateTime, b: LocalDateTime) -> Bool {
        (a.day, a.hour, a.minute) < (b.day, b.hour, b.minute)
    }
}

extension LocalDateTime: CustomStringConvertible, Codable {
    public var description: String { "\(day)T\(pad(hour, 2)):\(pad(minute, 2))" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        do {
            try self.init(text)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "not a calendar day and time written as YYYY-MM-DDTHH:MM: \"\(text)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

private func pad(_ value: Int, _ width: Int) -> String {
    let text = String(value)
    return String(repeating: "0", count: max(0, width - text.count)) + text
}

private func isDigits(_ text: Substring) -> Bool {
    text.allSatisfy { $0 >= "0" && $0 <= "9" }
}
