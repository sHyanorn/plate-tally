import Core
import Cost
import Energy
import Estimation
import Foundation
import Ledger
import Testing

@testable import Tally

/// A model over three files in a fresh folder. The system cleans the temporary directory, so the tests remove nothing.
@MainActor
private final class Rig {
    final class Switch {
        var on = true
    }

    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plate-tally-\(UUID().uuidString)")
    let key = Switch()
    var transport = RecordingTransport(status: 200, body: Data())

    var ledgerURL: URL { folder.appendingPathComponent("meals.json") }
    var callURL: URL { folder.appendingPathComponent("calls.json") }
    var settingsURL: URL { folder.appendingPathComponent("settings.json") }

    init(reply: String = twoItems) throws {
        transport = RecordingTransport(status: 200, body: try responseBody(text: reply))
    }

    /// A model at 2026-11-23 12:30 UTC. Call again to simulate a restart over the same files.
    func model(
        ledger: URL? = nil, calls: URL? = nil, timeZone: TimeZone = TimeZone(identifier: "UTC")!
    ) throws -> AppModel {
        let key = key
        return try AppModel(
            ledgerFile: FileStore(url: ledger ?? ledgerURL), callFile: FileStore(url: calls ?? callURL),
            settingsFile: FileStore(url: settingsURL), send: transport.transport,
            keyPresent: { key.on }, clock: { Date(timeIntervalSince1970: 1_795_437_000) }, timeZone: timeZone)
    }

    /// A place where no file can be written: its parent is a regular file.
    func blocked() throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        return blocker.appendingPathComponent("file.json")
    }
}

private let testVector = {
    var settings = UserSettings()
    settings.heightCm = 175
    settings.weightKg = 70
    settings.ageYears = 30
    settings.sex = .male
    return settings
}()

@MainActor @Suite struct StartTests {
    @Test func withoutFilesTheModelIsEmptyWithTheDefaults() throws {
        let model = try Rig().model()
        #expect(model.ledger.meals.isEmpty)
        #expect(model.callLog.calls.isEmpty)
        #expect(model.settings == UserSettings())
    }

    @Test func theClockGivesTheLocalTimeInTheZoneOfTheModel() throws {
        let utc = try Rig().model()
        #expect(utc.now == (try LocalDateTime("2026-11-23T12:30")))
        let shanghai = try Rig().model(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        #expect(shanghai.now == (try LocalDateTime("2026-11-23T20:30")))
        let auckland = try Rig().model(timeZone: TimeZone(identifier: "Pacific/Auckland")!)
        #expect(auckland.today == (try LocalDay("2026-11-24")))
    }

    @Test func anUnreadableFileStopsTheStartAndIsLeftAsItIs() throws {
        let rig = try Rig()
        try FileManager.default.createDirectory(at: rig.folder, withIntermediateDirectories: true)
        let damaged = Data("not json".utf8)
        try damaged.write(to: rig.ledgerURL)
        let error = #expect(throws: StoreError.self) { try rig.model() }
        #expect(error?.saw.hasSuffix(rig.ledgerURL.path) == true)
        #expect(try Data(contentsOf: rig.ledgerURL) == damaged)
    }

    @Test func theKeyIsAskedAtTheStartAndAgainOnRequest() throws {
        let rig = try Rig()
        let model = try rig.model()
        #expect(model.hasKey)
        rig.key.on = false
        #expect(model.hasKey)
        model.refreshKey()
        #expect(!model.hasKey)
    }

    @Test func aLocalTimeAndItsInstantGoBothWays() throws {
        let model = try Rig().model(timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        let time = try LocalDateTime("2026-11-23T08:15")
        #expect(model.localTime(of: model.instant(of: time)) == time)
    }
}

@MainActor @Suite struct MealTests {
    @Test func aSavedMealIsThereAfterARestart() throws {
        let rig = try Rig()
        let saved = try meal()
        try rig.model().add(saved)
        let again = try rig.model()
        #expect(again.meals(on: saved.at.day) == [saved])
        #expect(again.intake(on: saved.at.day) == 195)
    }

    @Test func anEditedMealReplacesTheOldOneAndTheTotalsFollow() throws {
        let rig = try Rig()
        let model = try rig.model()
        let saved = try meal()
        try model.add(saved)
        try model.replace(Meal(id: saved.id, at: saved.at, items: [FoodItem(name: "rice", grams: 300, kcal: 390)]))
        #expect(model.intake(on: saved.at.day) == 390)
        #expect(try rig.model().intake(on: saved.at.day) == 390)
    }

    @Test func aDeletedMealIsGoneAfterARestart() throws {
        let rig = try Rig()
        let model = try rig.model()
        let saved = try meal()
        try model.add(saved)
        try model.deleteMeal(id: saved.id)
        #expect(model.intake(on: saved.at.day) == 0)
        #expect(try rig.model().ledger.meals.isEmpty)
    }

    @Test func aRefusedOperationChangesNothingAndWritesNothing() throws {
        let rig = try Rig()
        let model = try rig.model()
        let saved = try meal()
        try model.add(saved)
        let before = try Data(contentsOf: rig.ledgerURL)
        #expect(throws: Problem.self) { try model.add(saved) }
        #expect(throws: Problem.self) { try model.replace(meal(id: 2)) }
        #expect(throws: Problem.self) { try model.deleteMeal(id: UUID()) }
        #expect(model.ledger.meals == [saved])
        #expect(try Data(contentsOf: rig.ledgerURL) == before)
    }

    @Test func aMealThatCannotBeReadBackIsRefusedAndNothingIsWritten() throws {
        let rig = try Rig()
        let model = try rig.model()
        let error = #expect(throws: Problem.self) {
            try model.add(meal(items: [FoodItem(name: "rice", grams: 0, kcal: 1)]))
        }
        #expect(error?.what == "the grams are out of range")
        #expect(model.ledger.meals.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: rig.ledgerURL.path))
    }

    @Test func aMealThatCannotBeWrittenIsNotShown() throws {
        let rig = try Rig()
        let model = try rig.model(ledger: rig.blocked())
        let error = #expect(throws: Problem.self) { try model.add(meal()) }
        #expect(error?.what == "the file cannot be written")
        #expect(model.ledger.meals.isEmpty)
    }

    @Test func aDraftHasTheTimeOfTheClockAndAFreshId() throws {
        let model = try Rig().model()
        let items = [FoodItem(name: "rice", grams: 150, kcal: 195)]
        let first = model.draft(items: items)
        #expect(first.at == model.now)
        #expect(first.items == items)
        #expect(first.id != model.draft(items: items).id)
    }
}

@MainActor @Suite struct SettingsModelTests {
    @Test func expenditureWaitsForTheProfileAndThenFollowsTheTestVector() throws {
        let model = try Rig().model()
        #expect(model.expenditure == nil)
        try model.update(testVector)
        #expect(model.expenditure == 2555.5625)
    }

    @Test func settingsSurviveARestart() throws {
        let rig = try Rig()
        var settings = testVector
        settings.dailyCallLimit = 5
        try rig.model().update(settings)
        #expect(try rig.model().settings == settings)
    }

    @Test func aLimitOutOfRangeIsRefusedAndTheOldSettingsStay() throws {
        let model = try Rig().model()
        var bad = testVector
        bad.dailyCallLimit = 0
        let error = #expect(throws: Problem.self) { try model.update(bad) }
        #expect(error?.what == "the daily call limit is out of range")
        #expect(model.settings == UserSettings())
    }
}

@MainActor @Suite struct AnalyzeTests {
    @Test func aBilledCallIsLoggedAndKeptAfterARestart() async throws {
        let rig = try Rig()
        let model = try rig.model()
        let outcome = await model.analyze(try testImage())
        #expect(try outcome.items.get().count == 2)
        #expect(model.callLog.count(on: model.today) == 1)
        #expect(model.callLog.total(on: model.today) == usd0035)
        #expect(try rig.model().callLog.total(inMonthOf: model.today) == usd0035)
    }

    @Test func aRejectedReplyCountsAgainstTheLimitToo() async throws {
        let rig = try Rig(reply: "no json here")
        let model = try rig.model()
        let outcome = await model.analyze(try testImage())
        #expect(outcome.call != nil)
        #expect(model.callLog.count(on: model.today) == 1)
    }

    @Test func theLimitStopsTheNextAnalysisBeforeAnyPhotoIsTaken() async throws {
        let rig = try Rig()
        let model = try rig.model()
        var settings = UserSettings()
        settings.dailyCallLimit = 1
        try model.update(settings)
        #expect(model.analysisRefusal == nil)
        _ = await model.analyze(try testImage())
        #expect(model.analysisRefusal?.what == "the daily call limit is reached")
        let refused = await model.analyze(try testImage())
        #expect(refused.call == nil)
        #expect(rig.transport.sent.count == 1)
    }

    /// The second analysis starts while the first waits for the network. Only one request may leave.
    @Test func twoAnalysesAtOnceDoNotBothPassALimitOfOne() async throws {
        let rig = try Rig()
        rig.transport = RecordingTransport(body: try responseBody(text: twoItems), delay: .milliseconds(100))
        let model = try rig.model()
        var settings = UserSettings()
        settings.dailyCallLimit = 1
        try model.update(settings)
        let image = try testImage()
        async let first = model.analyze(image)
        async let second = model.analyze(image)
        let outcomes = await [first, second]
        #expect(rig.transport.sent.count == 1)
        #expect(outcomes.filter { $0.call != nil }.count == 1)
        #expect(model.callLog.count(on: model.today) == 1)
        let refused = outcomes.first { $0.call == nil }
        guard case .failure(let problem)? = refused?.items else { Issue.record("expected a refusal"); return }
        #expect(problem.description == "the daily call limit is reached: expected fewer than 1 calls today, saw 1 calls")
    }

    @Test func withoutAKeyNothingIsSentAndTheScreenCanSayWhy() async throws {
        let rig = try Rig()
        rig.key.on = false
        let model = try rig.model()
        #expect(model.analysisRefusal?.what == "no API key is set")
        let outcome = await model.analyze(try testImage())
        #expect(outcome.call == nil)
        #expect(rig.transport.sent.isEmpty)
    }

    @Test func aFailedCallIsNotLoggedAndAStoreProblemIsNotRaised() async throws {
        let rig = try Rig()
        rig.transport = RecordingTransport(status: 500, body: Data(#"{"error":{"type":"api_error","message":"x"}}"#.utf8))
        let model = try rig.model()
        _ = await model.analyze(try testImage())
        #expect(model.callLog.calls.isEmpty)
        #expect(model.storeProblem == nil)
    }

    /// A count below 0 is not a usage, so nothing is logged and the next start reads the log.
    @Test func aReplyWithANegativeTokenCountIsNotLoggedAndTheNextStartReadsTheLog() async throws {
        let rig = try Rig()
        rig.transport = RecordingTransport(body: try responseBody(text: twoItems, input: -1, output: 0))
        let model = try rig.model()
        let outcome = await model.analyze(try testImage())
        #expect(outcome.call == nil)
        #expect(model.storeProblem == nil)
        #expect(throws: Never.self) { _ = try rig.model() }
    }

    /// The money is spent either way, so the count must hold the call even when the file cannot be written.
    @Test func aCallLogThatCannotBeWrittenStillCountsTheCallAndIsReported() async throws {
        let rig = try Rig()
        let model = try rig.model(calls: rig.blocked())
        let outcome = await model.analyze(try testImage())
        #expect(outcome.call != nil)
        #expect(model.callLog.count(on: model.today) == 1)
        #expect(model.storeProblem?.what == "the file cannot be written")
        model.dismissStoreProblem()
        #expect(model.storeProblem == nil)
    }
}

@MainActor @Suite struct AddingOneItemTests {
    private let bar = FoodItem(name: "Muesli bar", grams: 35, kcal: 1250 / 4.18)

    @Test func theLatestMealOfTheDayIsTheLastByTime() throws {
        let model = try Rig().model()
        #expect(model.latestMeal(on: model.today) == nil)
        let lunch = try meal("2026-11-23T12:05", id: 2)
        try model.add(lunch)
        try model.add(meal("2026-11-23T08:10", id: 1))
        try model.add(meal("2026-11-22T21:00", id: 3))
        #expect(model.latestMeal(on: model.today) == lunch)
    }

    @Test func anItemJoinsTheMealWithTheIdAndIsThereAfterARestart() throws {
        let rig = try Rig()
        let model = try rig.model()
        let lunch = try meal("2026-11-23T12:05")
        try model.add(lunch)
        try model.add(bar, toMealWithID: lunch.id)
        #expect(model.ledger.meals.map(\.items) == [lunch.items + [bar]])
        #expect(try rig.model().intake(on: model.today) == 195 + 1250 / 4.18)
    }

    @Test func withoutAnIdTheItemStartsAMealAtTheTimeOfTheClock() throws {
        let model = try Rig().model()
        try model.add(bar, toMealWithID: nil)
        #expect(model.ledger.meals.count == 1)
        #expect(model.ledger.meals.first?.at == model.now)
        #expect(model.ledger.meals.first?.items == [bar])
    }

    @Test func aFullMealOrAnUnknownIdRefusesTheItemAndWritesNothing() throws {
        let rig = try Rig()
        let model = try rig.model()
        let full = try meal(items: Array(repeating: bar, count: 20))
        try model.add(full)
        let before = try Data(contentsOf: rig.ledgerURL)
        let error = #expect(throws: Problem.self) { try model.add(bar, toMealWithID: full.id) }
        #expect(error?.what == "the meal has too many items")
        #expect(throws: Problem.self) { try model.add(bar, toMealWithID: UUID()) }
        #expect(model.ledger.meals == [full])
        #expect(try Data(contentsOf: rig.ledgerURL) == before)
    }
}
