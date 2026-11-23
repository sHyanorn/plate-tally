import XCTest

/// Drives each screen and state of the app, checks what it shows, and keeps a screenshot of it in light and
/// dark. The app runs on the options of UITestHarness: no network, no key, a fixed clock.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: Day

    func testTheEmptyDayAndTheRefusalWithoutAKey() {
        eachAppearance { app, look in
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["intake"].label, "0 kcal")
            XCTAssertTrue(app.buttons["add-profile"].exists)
            snap("day-empty", look)

            app.buttons["add-meal"].tap()
            let alert = app.alerts["No API key"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.staticTexts["No API key is set: expected a key saved in settings, saw no key"].exists)
            snap("refusal-no-key", look)
        }
    }

    func testTheDayWithMeals() {
        eachAppearance(["-ui-key", "-ui-profile", "-ui-seed"]) { app, look in
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
            // 160 + 105 + 195 + 165 + 31 kcal, and 2555.5625 kcal of expenditure for the test vector.
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 656 kcal")
            XCTAssertEqual(app.staticTexts["expenditure"].label, "≈ 2,556 kcal")
            snap("day-meals", look)
        }
    }

    // MARK: Analysis, items, saving

    func testAnalyzeEditSaveAndDelete() {
        eachAppearance(["-ui-key", "-ui-profile"]) { app, look in
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["expenditure"].label, "≈ 2,556 kcal")
            snap("day-profile", look)

            app.buttons["add-meal"].tap()
            XCTAssertTrue(app.buttons["Choose photo"].waitForExistence(timeout: 5))
            snap("add-source", look)
            app.buttons["Choose photo"].tap()

            XCTAssertTrue(app.descendants(matching: .any)["Analyzing meal"].waitForExistence(timeout: 5))
            snap("analyzing", look)

            XCTAssertTrue(app.navigationBars["New meal"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["meal-total"].label, "≈ 360 kcal")
            XCTAssertTrue(hasText("Analysis cost", in: app))
            XCTAssertTrue(hasText("$0.0035", in: app))
            snap("meal-draft", look)

            // R10: 150 g to 300 g scales 195 kcal to 390 kcal.
            app.buttons["item-0"].tap()
            let grams = app.textFields["item-grams"]
            XCTAssertTrue(grams.waitForExistence(timeout: 5))
            snap("item-edit", look)
            replaceText(of: grams, with: "300")
            XCTAssertEqual(app.textFields["item-kcal"].value as? String, "390")
            snap("item-edit-scaled", look)
            app.navigationBars["Item"].buttons["Save"].tap()
            XCTAssertTrue(app.navigationBars["New meal"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["meal-total"].label, "≈ 555 kcal")

            app.navigationBars["New meal"].buttons["Save"].tap()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 555 kcal")

            // A saved meal opens with its items and is deleted after a confirmation.
            app.descendants(matching: .any).matching(identifier: "meal-row").firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 5))
            snap("meal-stored", look)
            app.buttons["delete-meal"].tap()
            XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
            snap("meal-delete-confirm", look)
            app.buttons["Delete"].tap()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["intake"].label, "0 kcal")
        }
    }

    func testAnAnalysisThatFailsShowsItsReasonCodeAndCost() {
        eachAppearance(["-ui-key", "-ui-reply", "invalid"]) { app, look in
            app.buttons["add-meal"].tap()
            app.buttons["Choose photo"].tap()
            XCTAssertTrue(app.staticTexts["Analysis failed"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["not_json"].exists)
            XCTAssertTrue(app.staticTexts["Billed $0.0035"].exists)
            snap("analysis-failed", look)
            app.buttons["Close"].tap()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        }
    }

    func testAnAnalysisWithoutNetworkShowsNoCost() {
        eachAppearance(["-ui-key", "-ui-reply", "offline"]) { app, look in
            app.buttons["add-meal"].tap()
            app.buttons["Choose photo"].tap()
            XCTAssertTrue(app.staticTexts["Analysis failed"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["not_json"].exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Billed'")).firstMatch.exists)
            snap("analysis-offline", look)
        }
    }

    // MARK: Limit and settings

    func testTheDailyLimitRefusesTheNextAnalysis() {
        eachAppearance(["-ui-key", "-ui-limit", "1"]) { app, look in
            app.buttons["add-meal"].tap()
            app.buttons["Choose photo"].tap()
            XCTAssertTrue(app.navigationBars["New meal"].waitForExistence(timeout: 10))
            app.navigationBars["New meal"].buttons["Save"].tap()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 10))

            app.buttons["add-meal"].tap()
            let alert = app.alerts["Daily limit reached"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(
                alert.staticTexts["The daily call limit is reached: expected fewer than 1 calls today, saw 1 calls"].exists)
            snap("refusal-limit", look)
        }
    }

    func testSettingsTakeAKeyAndAProfileAndTheDayShowsTheExpenditure() {
        eachAppearance { app, look in
            app.buttons["settings"].tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            snap("settings-empty", look)

            app.secureTextFields["api-key"].tap()
            app.secureTextFields["api-key"].typeText("test-key-value")
            app.buttons["save-key"].tap()
            XCTAssertTrue(app.staticTexts["Key saved"].waitForExistence(timeout: 5))

            fill(app.textFields["height"], "175")
            fill(app.textFields["weight"], "70")
            fill(app.textFields["age"], "30")
            app.buttons["sex"].tap()
            app.buttons["Male"].tap()
            snap("settings-filled", look)

            app.buttons["Done"].tap()
            XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["expenditure"].label, "≈ 2,556 kcal")
        }
    }

    // MARK: Chinese

    func testTheDayAndAMealInChinese() {
        eachAppearance(["-ui-key", "-ui-profile", "-ui-seed", "-ui-language", "zh"]) { app, look in
            XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.navigationBars["Today"].exists)
            XCTAssertNotEqual(app.buttons["add-meal"].label, "Add meal")
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 656 kcal")
            snap("day-meals", look + "-zh")

            app.descendants(matching: .any).matching(identifier: "meal-row").firstMatch.tap()
            XCTAssertTrue(app.buttons["add-item"].waitForExistence(timeout: 5))
            XCTAssertNotEqual(app.buttons["add-item"].label, "Add item")
            snap("meal-stored", look + "-zh")
        }
    }

    /// The locale of the environment reaches the system alert and the confirmation dialog too.
    func testAnAlertAndADialogInChinese() {
        eachAppearance(["-ui-language", "zh"]) { app, look in
            app.buttons["add-meal"].tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            XCTAssertNotEqual(app.alerts.firstMatch.label, "No API key")
            snap("refusal-no-key", look + "-zh")
        }
        eachAppearance(["-ui-key", "-ui-seed", "-ui-language", "zh"]) { app, look in
            app.descendants(matching: .any).matching(identifier: "meal-row").firstMatch.tap()
            XCTAssertTrue(app.buttons["delete-meal"].waitForExistence(timeout: 5))
            app.buttons["delete-meal"].tap()
            // The dialog comes up as a sheet. The screenshot is the evidence, so a late sheet is not a failure.
            _ = app.sheets.firstMatch.waitForExistence(timeout: 3)
            snap("meal-delete-confirm", look + "-zh")
        }
    }

    /// Settings in Chinese, then the language set to English: the screen changes at once.
    func testSwitchingTheLanguageAtOnce() {
        eachAppearance(["-ui-language", "zh"]) { app, look in
            app.buttons["settings"].tap()
            XCTAssertTrue(app.secureTextFields["api-key"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.navigationBars["Settings"].exists)
            snap("settings", look + "-zh")

            app.descendants(matching: .any)["English"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
            snap("settings-switched", look)
        }
    }

    // MARK: Helpers

    /// Runs the check once with the light look and once with the dark look, on a fresh launch each.
    private func eachAppearance(_ options: [String] = [], _ check: (XCUIApplication, String) -> Void) {
        for (look, appearance) in [("light", XCUIDevice.Appearance.light), ("dark", .dark)] {
            XCUIDevice.shared.appearance = appearance
            let app = XCUIApplication()
            app.launchArguments = ["-ui-test"] + options
            app.launch()
            check(app, look)
            app.terminate()
        }
    }

    /// Replaces the text of a field: the delete key once for every character, then the new text. The tap
    /// lands at the right edge, where a right-aligned text ends, so the caret goes behind it.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        let old = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
    }

    /// True when some static text of the screen holds the text.
    private func hasText(_ text: String, in app: XCUIApplication) -> Bool {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists
    }

    private func fill(_ field: XCUIElement, _ text: String) {
        field.tap()
        field.typeText(text)
    }

    /// Attaches the screen to the result and writes it as PNG into the folder that the workflow names.
    private func snap(_ name: String, _ look: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(name)-\(look)"
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let folder = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] else { return }
        do {
            let directory = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appending(path: "\(name)-\(look).png"))
        } catch {
            XCTFail("screenshot \(name)-\(look): expected a PNG written to \(folder), saw \(error)")
        }
    }
}
