import Core
import SwiftUI
import Tally

@main
struct PlateTallyApp: App {
    private let session: Result<Session, Problem> = {
        #if DEBUG
        if let stubbed = UITestHarness.session() { return stubbed }
        #endif
        return AppEnvironment.live()
    }()

    var body: some Scene {
        WindowGroup {
            switch session {
            case .success(let session):
                RootView(session: session)
            case .failure(let problem):
                StartupFailureView(problem: problem)
                    .environment(\.locale, Language.chinese.locale)
            }
        }
    }
}

/// The screens in the language of the settings. A change of the setting shows at once, because the
/// locale of the environment is read from the model.
private struct RootView: View {
    let session: Session

    var body: some View {
        DayView(model: session.model, keys: session.keys)
            .environment(\.locale, session.model.settings.language.locale)
            // Controls stay neutral: moss belongs to the tags alone (D017).
            .tint(Palette.ink)
            #if DEBUG
            .preferredColorScheme(UITestHarness.colorScheme)
            #endif
    }
}

/// A file of the app is there and cannot be read. Nothing is written, so the file stays as it is.
struct StartupFailureView: View {
    let problem: Problem

    var body: some View {
        ContentUnavailableView {
            Label("Cannot start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(problem.message)
        }
    }
}
