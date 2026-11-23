#if DEBUG
import Core
import Foundation
import SwiftUI
import Tally
import UIKit

/// The UI tests start the app with `-ui-test`. The app then runs on a fresh folder, a fixed clock, an
/// in-memory key and a canned model reply, and a generated picture stands in for the camera and the
/// library, so a test needs no network and no key. The options:
/// `-ui-key` starts with a key, `-ui-profile` with a profile, `-ui-seed` with two meals today,
/// `-ui-limit N` with a daily limit of N, `-ui-reply good|invalid|offline` picks the reply,
/// `-ui-language zh` starts in Chinese (the tests read the English texts otherwise).
/// `-ui-appearance light|dark` sets the colour scheme of the app. The appearance that the tests set
/// through XCUIDevice did not reach it.
/// Release builds have none of this.
@MainActor
enum UITestHarness {
    private static let arguments = ProcessInfo.processInfo.arguments

    /// 2026-11-23 12:30 UTC, the day of the test vector.
    private static let now = Date(timeIntervalSince1970: 1_795_437_000)

    static var isActive: Bool { arguments.contains("-ui-test") }

    /// The colour scheme that `-ui-appearance` names, or nil to follow the system.
    static var colorScheme: ColorScheme? {
        guard isActive else { return nil }
        switch option("-ui-appearance") {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    /// The picture that the "Choose photo" button hands over instead of opening the library.
    static var photo: UIImage? {
        guard isActive else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1200), format: format).image { context in
            UIColor.systemBrown.withAlphaComponent(0.35).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 300, y: 100, width: 1000, height: 1000))
            let food: [(UIColor, CGRect)] = [
                (.systemYellow, CGRect(x: 450, y: 300, width: 400, height: 300)),
                (.systemBrown, CGRect(x: 800, y: 450, width: 300, height: 300)),
                (.systemGreen, CGRect(x: 520, y: 650, width: 260, height: 260)),
            ]
            for (color, rect) in food {
                color.setFill()
                context.cgContext.fillEllipse(in: rect)
            }
        }
    }

    static func session() -> Result<Session, Problem>? {
        guard isActive else { return nil }
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "plate-tally-ui-\(UUID().uuidString)", directoryHint: .isDirectory)
        let keys = MemoryKeyStore(arguments.contains("-ui-key") ? "test-key-value" : nil)
        let result = AppEnvironment.model(
            folder: folder, keys: keys, clock: { now }, timeZone: TimeZone(identifier: "UTC")!,
            send: transport(reply: option("-ui-reply") ?? "good"))
        if case .success(let session) = result { seed(session.model) }
        return result
    }

    private static func option(_ name: String) -> String? {
        arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
    }

    private static func seed(_ model: AppModel) {
        var settings = UserSettings()
        settings.language = option("-ui-language") == "zh" ? .chinese : .english
        if arguments.contains("-ui-profile") {
            settings.heightCm = 175
            settings.weightKg = 70
            settings.ageYears = 30
            settings.sex = .male
        }
        if let limit = option("-ui-limit").flatMap(Int.init) { settings.dailyCallLimit = limit }
        do throws(Problem) {
            try model.update(settings)
            guard arguments.contains("-ui-seed") else { return }
            try model.add(
                Meal(
                    id: UUID(), at: try! LocalDateTime("2026-11-23T08:10"),
                    items: [
                        FoodItem(name: "Oatmeal", grams: 240, kcal: 160),
                        FoodItem(name: "Banana", grams: 118, kcal: 105),
                    ]))
            try model.add(
                Meal(
                    id: UUID(), at: try! LocalDateTime("2026-11-23T12:05"),
                    items: [
                        FoodItem(name: "Rice", grams: 150, kcal: 195),
                        FoodItem(name: "Grilled chicken", grams: 100, kcal: 165),
                        FoodItem(name: "Broccoli", grams: 90, kcal: 31),
                    ]))
        } catch {
            fatalError("UI test seed: expected the seed to be stored, saw \(error)")
        }
    }

    /// 1,200 input and 110 output tokens: 0.0035 USD.
    private static func transport(reply: String) -> Transport {
        { _ throws(TransportFailure) in
            // Long enough for a test to see the progress screen.
            try? await Task.sleep(for: .seconds(2))
            switch reply {
            case "offline":
                throw TransportFailure(
                    what: "the request did not complete", expected: "a response from api.anthropic.com",
                    saw: "URL error -1009, The Internet connection appears to be offline.")
            case "invalid":
                return HTTPResponse(status: 200, body: body(text: "Here are the foods on the plate: rice and chicken."))
            default:
                return HTTPResponse(
                    status: 200,
                    body: body(
                        text: #"{"items":[{"name":"Rice","grams":150,"kcal":195},{"name":"Grilled chicken","grams":100,"kcal":165}]}"#
                    ))
            }
        }
    }

    private nonisolated static func body(text: String) -> Data {
        let message: [String: Any] = [
            "content": [["type": "text", "text": text]],
            "stop_reason": "end_turn",
            "usage": ["input_tokens": 1200, "output_tokens": 110],
        ]
        // A literal of strings and numbers always serializes.
        return try! JSONSerialization.data(withJSONObject: message)
    }
}
#endif
