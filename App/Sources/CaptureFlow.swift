import Core
import SwiftUI
import Tally

/// The cover of one analysis: the call first, then the meal that came back, which the user corrects
/// and saves or discards.
struct CaptureFlow: View {
    let model: AppModel
    let photo: Photo
    let onFinish: () -> Void

    private struct Draft {
        let meal: Meal
        let cost: Decimal?
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var draft: Draft?

    var body: some View {
        NavigationStack {
            if let draft {
                DraftMealView(
                    model: model, photo: photo, cost: draft.cost, meal: draft.meal, onSaved: onFinish,
                    onDiscard: onFinish)
            } else {
                AnalysisView(
                    model: model, photo: photo,
                    onResult: { meal, cost in draft = Draft(meal: meal, cost: cost) }, onClose: onFinish)
            }
        }
        // The system keeps a picture of the screen for the app switcher when the app leaves the foreground.
        // The photo is never stored (R11), so the canvas covers it from the moment the app is no longer active.
        .overlay {
            if scenePhase != .active {
                Palette.canvas.ignoresSafeArea()
            }
        }
    }
}
