import Core
import Foundation
import Tally

/// What the screens need: the state and the place of the key.
struct Session {
    let model: AppModel
    let keys: any KeyStore
}

/// The parts of the app that touch the system, put together.
@MainActor
enum AppEnvironment {
    static let keys: KeychainKeyStore = {
        guard let id = Bundle.main.bundleIdentifier else {
            fatalError("Info.plist key CFBundleIdentifier: expected a string, saw nil")
        }
        return KeychainKeyStore(service: "\(id).api-key")
    }()

    /// The three files live in Application Support (D013). An unreadable one is an error and stays as it is.
    static func live() -> Result<Session, Problem> {
        let folder = URL.applicationSupportDirectory.appending(path: "PlateTally", directoryHint: .isDirectory)
        return model(folder: folder, keys: keys, clock: { Date() }, timeZone: .current)
    }

    static func model(
        folder: URL, keys: any KeyStore, clock: @escaping @MainActor () -> Date, timeZone: TimeZone,
        send: Transport? = nil
    ) -> Result<Session, Problem> {
        do throws(StoreError) {
            let model = try AppModel(
                ledgerFile: FileStore(url: folder.appending(path: "meals.json")),
                callFile: FileStore(url: folder.appending(path: "calls.json")),
                settingsFile: FileStore(url: folder.appending(path: "settings.json")),
                send: send ?? URLSessionTransport(keys: keys).transport,
                keyPresent: { (try? keys.read()) != nil }, clock: clock, timeZone: timeZone)
            return .success(Session(model: model, keys: keys))
        } catch {
            return .failure(Problem(error))
        }
    }
}
