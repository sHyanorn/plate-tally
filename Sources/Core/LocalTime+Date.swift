import Foundation

extension LocalDateTime {
    /// The instant of this local time in the zone, for a date picker. A time that the zone skips, the hour
    /// lost when the clocks go forward, lands one hour later, which is how Calendar resolves it.
    public func date(in timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute)
        // The parts of a valid LocalDateTime always make a date.
        return calendar.date(from: parts)!
    }
}
