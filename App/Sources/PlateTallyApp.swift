import SwiftUI

@main
struct PlateTallyApp: App {
    var body: some Scene {
        WindowGroup {
            BuildInfoView()
        }
    }
}

struct BuildInfoView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(infoValue("CFBundleDisplayName"))
                .font(.largeTitle)
            Text("Version \(infoValue("CFBundleShortVersionString")) (\(infoValue("CFBundleVersion")))")
                .foregroundStyle(.secondary)
        }
    }
}

// The screen exists to show what CI built, so a missing key stops the app.
private func infoValue(_ key: String) -> String {
    let value = Bundle.main.object(forInfoDictionaryKey: key)
    guard let text = value as? String else {
        fatalError("Info.plist key \(key): expected a string, saw \(String(describing: value))")
    }
    return text
}
