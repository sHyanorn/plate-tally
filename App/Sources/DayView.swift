import Core
import PhotosUI
import SwiftUI
import Tally

/// The day (R15): what was eaten, the intake and the estimated expenditure. No difference, no target (D004).
struct DayView: View {
    let model: AppModel
    let keys: any KeyStore

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    @State private var selected: Date
    @State private var showSettings = false
    @State private var choosingSource = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var photo: Photo?
    @State private var refusal: Problem?
    @State private var photoProblem: Problem?
    @State private var deleting: Meal?
    @State private var deleteProblem: Problem?

    init(model: AppModel, keys: any KeyStore) {
        self.model = model
        self.keys = keys
        _selected = State(initialValue: model.instant(of: model.now))
    }

    private var day: LocalDay { model.localTime(of: selected)?.day ?? model.today }
    private var meals: [Meal] { model.meals(on: day) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(alignment: .top) {
                        metric("Intake", value: kcalText(model.intake(on: day)), id: "intake")
                        expenditure
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    if meals.isEmpty {
                        ContentUnavailableView("No meals", systemImage: "fork.knife")
                            .listRowBackground(Color.clear)
                    }
                    ForEach(meals, id: \.id) { meal in
                        NavigationLink(value: meal.id) {
                            MealRow(
                                meal: meal,
                                time: model.instant(of: meal.at)
                                    .formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                        }
                        .accessibilityIdentifier("meal-row")
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { deleting = meal }
                        }
                    }
                }
            }
            .navigationTitle(
                day == model.today
                    ? Text("Today")
                    : Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                        .accessibilityIdentifier("settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    DatePicker("Day", selection: $selected, displayedComponents: .date).labelsHidden()
                }
            }
            .navigationDestination(for: UUID.self) { StoredMealView(model: model, id: $0) }
            .safeAreaInset(edge: .bottom) {
                Button(action: startCapture) {
                    Label("Add meal", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityIdentifier("add-meal")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model, keys: keys) }
        .fullScreenCover(item: $photo) { photo in
            CaptureFlow(model: model, photo: photo) { self.photo = nil }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    showCamera = false
                    use(image)
                },
                onFailure: { problem in
                    showCamera = false
                    photoProblem = problem
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickedItem, matching: .images)
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            pickedItem = nil
            Task { await load(item) }
        }
        .confirmationDialog("Add meal", isPresented: $choosingSource, titleVisibility: .hidden) {
            if CameraPicker.isAvailable {
                Button("Take photo") { showCamera = true }
            }
            Button("Choose photo", action: choosePhoto)
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete this meal?",
            isPresented: Binding(main: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible, presenting: deleting
        ) { meal in
            Button("Delete", role: .destructive) { delete(meal) }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            LocalizedStringKey(model.hasKey ? "Daily limit reached" : "No API key"),
            isPresented: Binding(main: { refusal != nil }, set: { if !$0 { refusal = nil } }),
            presenting: refusal
        ) { _ in
            if !model.hasKey {
                Button("Open settings") { showSettings = true }
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { shown in
            Text(shown.message)
        }
        .problemAlert("Could not use the photo", $photoProblem)
        .problemAlert("Could not delete", $deleteProblem)
        .problemAlert(
            "Could not save",
            Binding(main: { model.storeProblem }, set: { if $0 == nil { model.dismissStoreProblem() } })
        )
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.refreshKey()
            selected = model.instant(of: model.now)
        }
    }

    @ViewBuilder
    private var expenditure: some View {
        if let kcal = model.expenditure {
            metric("Expenditure", value: kcalText(kcal), id: "expenditure")
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Expenditure").font(.subheadline).foregroundStyle(.secondary)
                Button("Add profile") { showSettings = true }
                    .buttonStyle(.borderless)
                    .font(.title3)
                    .accessibilityIdentifier("add-profile")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metric(_ title: LocalizedStringKey, value: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier(id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The limit and the key are checked before the photo is taken, so no photo is wasted (R19, R20).
    private func startCapture() {
        if let problem = model.analysisRefusal {
            refusal = problem
        } else {
            choosingSource = true
        }
    }

    private func choosePhoto() {
        #if DEBUG
        if let picture = UITestHarness.photo {
            use(picture)
            return
        }
        #endif
        showLibrary = true
    }

    private func use(_ image: UIImage) {
        do throws(Problem) {
            photo = try PhotoPrep.photo(from: image)
        } catch {
            photoProblem = error
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                photoProblem = Problem(
                    PhotoError(
                        what: "the photo cannot be read", expected: "image data the system can decode",
                        saw: "no image"))
                return
            }
            use(image)
        } catch {
            photoProblem = Problem(
                PhotoError(
                    what: "the photo cannot be loaded", expected: "image data from the library",
                    saw: error.localizedDescription))
        }
    }

    private func delete(_ meal: Meal) {
        do throws(Problem) {
            try model.deleteMeal(id: meal.id)
        } catch {
            deleteProblem = error
        }
    }
}

private struct MealRow: View {
    let meal: Meal
    let time: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(time).font(.subheadline).foregroundStyle(.secondary)
                Text(meal.items.map(\.name).joined(separator: ", ")).lineLimit(1)
            }
            Spacer()
            Text(kcalText(meal.totalKcal)).monospacedDigit()
        }
    }
}
