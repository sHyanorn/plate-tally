import Core
import SwiftUI
import Tally

/// One analysis: the photo, a spinner while the model works, and the error with its reason code when
/// the reply cannot be used. A good reply goes to `onResult` (R6, R7, R17).
struct AnalysisView: View {
    let model: AppModel
    let photo: Photo
    let onResult: (_ meal: Meal, _ cost: Decimal?) -> Void
    let onClose: () -> Void

    private enum Phase {
        case running
        case failed(Problem, cost: Decimal?)
    }

    @State private var phase = Phase.running
    @State private var attempt = 0

    var body: some View {
        VStack(spacing: 24) {
            Image(uiImage: photo.thumbnail)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 240)
                .clipShape(.rect(cornerRadius: Metrics.cardRadius))
                .accessibilityLabel("Photo of the meal")
            switch phase {
            case .running:
                ProgressView("Analyzing meal")
            case .failed(let problem, let cost):
                failure(problem, cost: cost)
            }
            Spacer()
        }
        .padding(Metrics.margin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
        .foregroundStyle(Palette.ink)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if isRunning {
                    Button("Cancel", action: onClose)
                } else {
                    Button("Close", action: onClose)
                }
            }
        }
        // A new attempt cancels the old task, and closing the screen cancels the request (R7).
        .task(id: attempt) { await run() }
    }

    private var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    private func failure(_ problem: Problem, cost: Decimal?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analysis failed").textRole(.name)
            if let code = problem.code {
                Text(code).font(.caption.monospaced()).foregroundStyle(Palette.ink2)
            }
            Text(problem.message)
            if let cost {
                Text("Billed \(usd(cost))").foregroundStyle(Palette.ink2)
            }
            Button("Try again") {
                phase = .running
                attempt += 1
            }
            .buttonStyle(PillButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func run() async {
        let outcome = await model.analyze(photo.jpeg)
        guard !Task.isCancelled else { return }
        switch outcome.items {
        case .success(let items):
            onResult(model.draft(items: items), outcome.call?.costUSD)
        case .failure(let problem):
            phase = .failed(problem, cost: outcome.call?.costUSD)
        }
    }
}
