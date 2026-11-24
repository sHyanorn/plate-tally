import Core
import Cost
import Energy
import Estimation
import Foundation
import Ledger
import Observation

/// What the app holds: the meals, the call log and the settings, each in its own file (D013).
/// Every change is written whole before the screens see it, except the call log, which is written after:
/// the call has been paid for either way, so the count must not lose it.
@MainActor @Observable
public final class AppModel {
    public private(set) var ledger: Ledger
    public private(set) var callLog: CallLog
    public private(set) var settings: UserSettings
    public private(set) var hasKey: Bool
    /// A call log that could not be written. The screens show it once and call `dismissStoreProblem`.
    public private(set) var storeProblem: Problem?

    private let ledgerFile: FileStore<Ledger>
    private let callFile: FileStore<CallLog>
    private let settingsFile: FileStore<UserSettings>
    private let send: Transport
    private let keyPresent: @MainActor () -> Bool
    private let clock: @MainActor () -> Date
    private let timeZone: TimeZone

    /// Reads the three files. A file that is there and unreadable is an error and is left as it is.
    public init(
        ledgerFile: FileStore<Ledger>, callFile: FileStore<CallLog>, settingsFile: FileStore<UserSettings>,
        send: @escaping Transport, keyPresent: @escaping @MainActor () -> Bool,
        clock: @escaping @MainActor () -> Date, timeZone: TimeZone
    ) throws(StoreError) {
        self.ledger = try ledgerFile.load()
        self.callLog = try callFile.load()
        self.settings = try settingsFile.load()
        self.ledgerFile = ledgerFile
        self.callFile = callFile
        self.settingsFile = settingsFile
        self.send = send
        self.keyPresent = keyPresent
        self.clock = clock
        self.timeZone = timeZone
        self.hasKey = keyPresent()
    }

    // MARK: Time

    /// The clock is read here and nowhere else. A real instant is within the years 1 to 9999.
    public var now: LocalDateTime { try! LocalDateTime(clock(), in: timeZone) }
    public var today: LocalDay { now.day }

    /// For a date picker. An instant outside the years 1 to 9999 gives nil.
    public func localTime(of date: Date) -> LocalDateTime? { try? LocalDateTime(date, in: timeZone) }

    public func instant(of time: LocalDateTime) -> Date { time.date(in: timeZone) }

    // MARK: Day

    public func meals(on day: LocalDay) -> [Meal] { ledger.meals(on: day) }
    public func intake(on day: LocalDay) -> Double { ledger.intake(on: day) }

    /// Estimated expenditure (R14), or nil until the profile is complete.
    public var expenditure: Double? {
        // A profile that exists has four positive values, so Energy has nothing to refuse.
        settings.profile.flatMap { try? Energy.expenditure($0) }
    }

    // MARK: Meals

    /// A meal that is not saved yet. Tally draws the id and takes the time from the clock of the app; no other
    /// module draws a random number or reads a clock.
    public func draft(items: [FoodItem]) -> Meal { Meal(id: UUID(), at: now, items: items) }

    public func add(_ meal: Meal) throws(Problem) {
        var next = ledger
        do throws(LedgerError) { try next.add(meal) } catch { throw Problem(error) }
        try write(next, to: ledgerFile)
        ledger = next
    }

    public func replace(_ meal: Meal) throws(Problem) {
        var next = ledger
        do throws(LedgerError) { try next.replace(meal) } catch { throw Problem(error) }
        try write(next, to: ledgerFile)
        ledger = next
    }

    public func deleteMeal(id: UUID) throws(Problem) {
        var next = ledger
        do throws(LedgerError) { try next.delete(id: id) } catch { throw Problem(error) }
        try write(next, to: ledgerFile)
        ledger = next
    }

    /// The last meal of the day by time, which the converter offers as its target.
    public func latestMeal(on day: LocalDay) -> Meal? { meals(on: day).last }

    /// Adds one item to the meal with the id, or to a new meal at the time of the clock when the id is nil.
    public func add(_ item: FoodItem, toMealWithID id: UUID?) throws(Problem) {
        guard let id else { return try add(try adding(item, to: draft(items: []))) }
        guard let meal = ledger.meals.first(where: { $0.id == id }) else { throw Problem(LedgerError.unknownID(id)) }
        try replace(try adding(item, to: meal))
    }

    private func adding(_ item: FoodItem, to meal: Meal) throws(Problem) -> Meal {
        do throws(LedgerError) { return try meal.adding(item) } catch { throw Problem(error) }
    }

    // MARK: Settings and key

    public func update(_ next: UserSettings) throws(Problem) {
        try write(next, to: settingsFile)
        settings = next
    }

    /// The app calls this after it saves or removes the key.
    public func refreshKey() { hasKey = keyPresent() }

    // MARK: Analysis

    /// Analyses whose outcome is not recorded yet. Each counts against the daily limit from before its request
    /// leaves, so two analyses that overlap cannot both pass the limit (R19).
    private var callsInFlight = 0

    /// Why an analysis may not start now, or nil (R19, R20).
    public var analysisRefusal: Problem? { refusal(on: today) }

    /// Makes one call and records it when the API billed it. The check and the count of the call in flight
    /// happen on the main actor before the first wait, so no other analysis passes the check between them.
    public func analyze(_ image: JPEGImage) async -> Analysis.Outcome {
        let at = now
        if let refusal = refusal(on: at.day) { return Analysis.Outcome(call: nil, items: .failure(refusal)) }
        callsInFlight += 1
        let outcome = await Analysis.run(image: image, at: at, send: send)
        callsInFlight -= 1
        if let call = outcome.call {
            callLog.add(call)
            do throws(StoreError) {
                try callFile.save(callLog)
            } catch {
                storeProblem = Problem(error)
            }
        }
        return outcome
    }

    public func dismissStoreProblem() { storeProblem = nil }

    private func refusal(on day: LocalDay) -> Problem? {
        Analysis.refusal(
            hasKey: hasKey, log: callLog, inFlight: callsInFlight, on: day, limit: settings.dailyCallLimit)
    }

    private func write<Value: StoredValue>(_ value: Value, to file: FileStore<Value>) throws(Problem) {
        do throws(StoreError) { try file.save(value) } catch { throw Problem(error) }
    }
}
