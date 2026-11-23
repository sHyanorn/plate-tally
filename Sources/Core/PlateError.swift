import Foundation

/// An error that states what happened, what was expected and what was seen (R26).
/// The protocol makes the three parts a compile-time requirement for every module.
public protocol PlateError: LocalizedError, CustomStringConvertible, Sendable {
    var what: String { get }
    var expected: String { get }
    var saw: String { get }
}

extension PlateError {
    public var description: String { "\(what): expected \(expected), saw \(saw)" }
    public var errorDescription: String? { description }
}

/// A number as text for an error message: 2000, not 2000.0.
public func plainNumber(_ value: Double) -> String {
    if value.isFinite, abs(value) < 1e15, value == value.rounded() {
        return String(Int(value))
    }
    return String(value)
}
