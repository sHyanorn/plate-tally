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
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: Date
    @State private var path: [UUID] = []
    @State private var showSettings = false
    @State private var choosingSource = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var photo: Photo?
    @State private var showRefusal = false
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
        NavigationStack(path: $path) {
            List {
                title
                    .textRole(.pageTitle)
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("day-title")
                    .plainListRow()
                EnergyHero(intake: model.intake(on: day), expenditure: model.expenditure) { showSettings = true }
                    .plainListRow()
                if meals.isEmpty {
                    EmptyDay().plainListRow()
                }
                ForEach(meals, id: \.id) { meal in
                    Button {
                        path.append(meal.id)
                    } label: {
                        MealCard(
                            meal: meal,
                            time: model.instant(of: meal.at)
                                .formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal-row")
                    .cardListRow()
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) { deleting = meal }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(Metrics.gap)
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .foregroundStyle(Palette.ink)
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
            .safeAreaBar(edge: .bottom) {
                Button(action: startCapture) {
                    Label("Add meal", systemImage: "camera").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("add-meal")
                .padding(.horizontal, Metrics.margin)
                .padding(.vertical, 8)
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
            LocalizedStringKey(model.hasKey ? "Daily limit reached" : "No API key"), isPresented: $showRefusal
        ) {
            if model.hasKey {
                Button("OK") {}
            } else {
                Button("Open settings") { showSettings = true }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if model.hasKey {
                Text("\(model.callLog.count(on: model.today)) of \(model.settings.dailyCallLimit)")
            }
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

    private var title: Text {
        day == model.today
            ? Text("Today") : Text(selected.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale)))
    }

    /// The limit and the key are checked before the photo is taken, so no photo is wasted (R19, R20).
    private func startCapture() {
        if model.analysisRefusal == nil {
            choosingSource = true
        } else {
            showRefusal = true
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

/// The intake as a moss price tag beside the outlined expenditure. They stand side by side and nothing compares
/// them (R15, D004). At accessibility text sizes the two stack.
private struct EnergyHero: View {
    let intake: Double
    let expenditure: Double?
    let addProfile: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title) private var sideWidth: CGFloat = 136
    /// The height of a block inside its 18 pt padding, 132 pt in all.
    @ScaledMetric(relativeTo: .largeTitle) private var innerHeight: CGFloat = Metrics.tagHeight - 36

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        layout {
            EnergyTag(label: "Intake", kcal: intake, numberID: "intake", minHeight: innerHeight)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("Expenditure").textRole(.label).lineLimit(1).minimumScaleFactor(0.6)
                    if expenditure != nil {
                        Spacer(minLength: 4)
                        Text(verbatim: "kcal").textRole(.unit).accessibilityHidden(true)
                    }
                }
                Spacer(minLength: 8)
                if let expenditure {
                    KcalNumber(kcal: expenditure, role: .sideNumber).accessibilityIdentifier("expenditure")
                } else {
                    Button(action: addProfile) {
                        Text("Add profile")
                            .underline()
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottomLeading)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .textRole(.label)
                    .accessibilityIdentifier("add-profile")
                }
            }
            .frame(width: stacked ? nil : sideWidth - 28)
            .frame(
                maxWidth: stacked ? CGFloat.infinity : nil, minHeight: innerHeight, maxHeight: .infinity,
                alignment: .leading)
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
            .background(Palette.surface, in: .rect(cornerRadius: Metrics.tagRadius))
            .overlay { RoundedRectangle(cornerRadius: Metrics.tagRadius).strokeBorder(Palette.line, lineWidth: 1.5) }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct MealCard: View {
    let meal: Meal
    let time: String

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(time).textRole(.caption).foregroundStyle(Palette.ink2)
                Text(meal.items.map(\.name).joined(separator: ", ")).textRole(.name).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                KcalNumber(kcal: meal.totalKcal, role: .cardNumber)
                Text(verbatim: "kcal").textRole(.caption).foregroundStyle(Palette.ink2).accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56)
        .cardPadding()
        .contentShape(.rect)
    }
}

/// A day without meals: an outlined card that names the state. The button below says what to do.
private struct EmptyDay: View {
    @ScaledMetric(relativeTo: .title) private var circle: CGFloat = 64

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "fork.knife")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .frame(width: circle, height: circle)
                .background(Palette.surface2, in: .circle)
                .accessibilityHidden(true)
            Text("No meals").textRole(.name).foregroundStyle(Palette.ink2)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .overlay { RoundedRectangle(cornerRadius: Metrics.cardRadius).strokeBorder(Palette.line, lineWidth: 2) }
    }
}
