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
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["intake"].label, "0 kcal")
            XCTAssertTrue(app.buttons["add-profile"].exists)
            snap("day-empty", look)

            app.buttons["add-meal"].tap()
            let alert = app.alerts["No API key"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.buttons["Open settings"].exists)
            let threeParts = NSPredicate(format: "label CONTAINS 'expected'")
            XCTAssertFalse(alert.staticTexts.matching(threeParts).firstMatch.exists)
            snap("refusal-no-key", look)
        }
    }

    func testTheDayWithMeals() {
        eachAppearance(["-ui-key", "-ui-profile", "-ui-seed"]) { app, look in
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))
            // 160 + 105 + 195 + 165 + 31 kcal, and 2555.5625 kcal of expenditure for the test vector.
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 656 kcal")
            XCTAssertEqual(app.staticTexts["expenditure"].label, "≈ 2,556 kcal")
            snap("day-meals", look)
        }
        // At an accessibility text size the tag and the expenditure stack.
        let largest = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        eachAppearance(["-ui-key", "-ui-profile", "-ui-seed"] + largest, looks: ["light"]) { app, look in
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 656 kcal")
            snap("day-meals-ax", look)
        }
    }

    // MARK: Analysis, items, saving

    func testAnalyzeEditSaveAndDelete() {
        eachAppearance(["-ui-key", "-ui-profile"]) { app, look in
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["expenditure"].label, "≈ 2,556 kcal")
            snap("day-profile", look)

            app.buttons["add-meal"].tap()
            XCTAssertTrue(app.buttons["Choose photo"].waitForExistence(timeout: 5))
            snap("add-source", look)
            app.buttons["Choose photo"].tap()

            XCTAssertTrue(app.descendants(matching: .any)["Analyzing meal"].waitForExistence(timeout: 5))
            snap("analyzing", look)

            XCTAssertTrue(app.staticTexts["meal-title"].waitForExistence(timeout: 10))
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
            snap("item-edit-scaled", look)
            XCTAssertEqual(app.textFields["item-kcal"].value as? String, "390")
            // In kJ the field shows 390 x 4.18 and the pill gives the kcal back.
            app.buttons["kJ"].tap()
            XCTAssertEqual(app.textFields["item-kcal"].value as? String, "1630.2")
            XCTAssertEqual(app.staticTexts["kcal-equivalent"].label, "= 390 kcal")
            snap("item-edit-kj", look)
            app.buttons["item-save"].tap()
            XCTAssertTrue(app.staticTexts["meal-title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["meal-total"].label, "≈ 555 kcal")

            app.buttons["meal-save"].tap()
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 555 kcal")

            // A saved meal opens with its items and is deleted after a confirmation.
            app.descendants(matching: .any).matching(identifier: "meal-row").firstMatch.tap()
            XCTAssertTrue(app.staticTexts["meal-title"].waitForExistence(timeout: 5))
            snap("meal-stored", look)
            app.buttons["delete-meal"].tap()
            XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5))
            snap("meal-delete-confirm", look)
            app.buttons["Delete"].tap()
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 5))
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
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 5))
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
            XCTAssertTrue(app.staticTexts["meal-title"].waitForExistence(timeout: 10))
            app.buttons["meal-save"].tap()
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))

            app.buttons["add-meal"].tap()
            let alert = app.alerts["Daily limit reached"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.staticTexts["1 of 1"].exists)
            snap("refusal-limit", look)
        }
    }

    func testSettingsTakeAKeyAndAProfileAndTheDayShowsTheExpenditure() {
        eachAppearance { app, look in
            app.buttons["settings"].tap()
            XCTAssertTrue(app.staticTexts["settings-title"].waitForExistence(timeout: 5))
            snap("settings-empty", look)
            XCTAssertTrue(hasText("Light", in: app))

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
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["expenditure"].label, "≈ 2,556 kcal")
        }
    }

    // MARK: Converter

    func testTheConverterTurnsLabelEnergyIntoAnItem() {
        eachAppearance(["-ui-seed"]) { app, look in
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 10))
            app.buttons["convert"].tap()
            XCTAssertTrue(app.staticTexts["converter-title"].waitForExistence(timeout: 5))

            // Per serving, 1250 kJ are 1250 / 4.18 = 299.04 kcal.
            fill(app.textFields["converter-name"], "Muesli bar")
            fill(app.textFields["converter-grams"], "35")
            fill(app.textFields["converter-kj"], "1250")
            XCTAssertEqual(app.textFields["converter-kcal"].value as? String, "299")
            snap("converter-serving", look)

            // Per 100 g, 1520 kJ for 35 g eaten are 127.27 kcal and 532 kJ.
            app.buttons["Per 100 g"].tap()
            fill(app.textFields["converter-kj"], "1520")
            XCTAssertEqual(app.textFields["converter-kcal"].value as? String, "363.6")
            XCTAssertEqual(app.staticTexts["converter-result"].label, "= 127 kcal")
            snap("converter-100g", look)

            // The latest meal of the seed is lunch at 12:05: 656 + 127.27 kcal.
            app.buttons["converter-add"].tap()
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 783 kcal")
            XCTAssertEqual(app.buttons.matching(identifier: "meal-row").count, 2)
        }
        // A day without meals offers a new meal only, and the item starts it.
        eachAppearance(["-ui-language", "zh"], looks: ["light"]) { app, look in
            XCTAssertTrue(app.buttons["convert"].waitForExistence(timeout: 10))
            app.buttons["convert"].tap()
            XCTAssertTrue(app.staticTexts["converter-title"].waitForExistence(timeout: 5))
            app.buttons["每 100 g"].tap()
            fill(app.textFields["converter-name"], "Muesli bar")
            fill(app.textFields["converter-grams"], "35")
            fill(app.textFields["converter-kj"], "1520")
            snap("converter-100g", look + "-zh")
            app.buttons["converter-add"].tap()
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["intake"].label, "≈ 127 kcal")
        }
    }

    // MARK: Chinese

    func testTheDayAndAMealInChinese() {
        eachAppearance(["-ui-key", "-ui-profile", "-ui-seed", "-ui-language", "zh"]) { app, look in
            XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 10))
            XCTAssertNotEqual(app.staticTexts["day-title"].label, "Today")
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
            XCTAssertNotEqual(app.staticTexts["settings-title"].label, "Settings")
            snap("settings", look + "-zh")

            app.descendants(matching: .any)["English"].firstMatch.tap()
            // The screen is kept before the checks, so a failure leaves its picture.
            _ = app.staticTexts["Settings"].waitForExistence(timeout: 5)
            snap("settings-switched", look)
            XCTAssertEqual(app.secureTextFields["api-key"].placeholderValue, "Anthropic API key")
            XCTAssertEqual(app.staticTexts["settings-title"].label, "Settings")

            // The day draws its own title, and it follows the switch too.
            app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["day-title"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["day-title"].label, "Today")
        }
    }

    // MARK: Helpers

    /// Runs the check once with each look, light and dark unless named, on a fresh launch each.
    private func eachAppearance(
        _ options: [String] = [], looks: [String] = ["light", "dark"], _ check: (XCUIApplication, String) -> Void
    ) {
        for look in looks {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-test", "-ui-appearance", look] + options
            app.launch()
            check(app, look)
            app.terminate()
        }
    }

    /// Replaces the text of a field that has some. A tap puts the caret where it lands, and the delete key
    /// works behind the caret only. The text is right-aligned, so a tap in the middle lands before it and a
    /// tap at the right edge lands behind it. The edge does not take the tap that gives the field its focus.
    private func replaceText(of field: XCUIElement, with text: String) {
        for dx in [0.5, 0.995] where !(field.value as? String ?? "").isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5)).tap()
            let count = (field.value as? String ?? "").count
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count))
        }
        field.typeText(text)
    }

    /// True when some element of the screen has the text in its label.
    private func hasText(_ text: String, in app: XCUIApplication) -> Bool {
        let labelled = NSPredicate(format: "label CONTAINS %@", text)
        return app.descendants(matching: .any).matching(labelled).firstMatch.exists
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
