import Core
import Cost
import Energy
import SwiftUI
import Tally

/// The key, the profile, the activity factor and the call limit (R13, R19, R20), and the cost totals (R18).
/// Every change is saved at once. A profile value that is empty or not a number counts as not set.
struct SettingsView: View {
    let model: AppModel
    let keys: any KeyStore

    @Environment(\.dismiss) private var dismiss
    @State private var keyText = ""
    @State private var confirmingRemove = false
    @State private var problem: Problem?
    @State private var heightText: String
    @State private var weightText: String
    @State private var ageText: String

    init(model: AppModel, keys: any KeyStore) {
        self.model = model
        self.keys = keys
        _heightText = State(initialValue: model.settings.heightCm.map(plainNumber) ?? "")
        _weightText = State(initialValue: model.settings.weightKg.map(plainNumber) ?? "")
        _ageText = State(initialValue: model.settings.ageYears.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("Language", selection: languageBinding) {
                        ForEach(Language.allCases, id: \.self) { language in
                            Text(verbatim: language.locale.localizedString(forIdentifier: language.rawValue) ?? language.rawValue)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("language")
                }
                keySection
                Section("Profile") {
                    field("Height (cm)", text: $heightText, id: "height", keyboard: .decimalPad)
                    field("Weight (kg)", text: $weightText, id: "weight", keyboard: .decimalPad)
                    field("Age (years)", text: $ageText, id: "age", keyboard: .numberPad)
                    Picker("Sex", selection: sexBinding) {
                        Text("Not set").tag(Sex?.none)
                        Text("Female").tag(Sex?.some(.female))
                        Text("Male").tag(Sex?.some(.male))
                    }
                    .accessibilityIdentifier("sex")
                }
                Section("Activity") {
                    Picker("Activity", selection: activityBinding) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            let factor = level.factor.formatted(.number.precision(.fractionLength(2)))
                            HStack {
                                Text(Self.name(of: level))
                                Spacer()
                                Text(verbatim: "×\(factor)").foregroundStyle(.secondary)
                            }
                            .tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Calls") {
                    Stepper(value: limitBinding, in: UserSettings.dailyLimits) {
                        LabeledContent("Daily limit", value: "\(model.settings.dailyCallLimit)")
                    }
                    .accessibilityIdentifier("daily-limit")
                }
                Section("Usage") {
                    let today = model.today
                    LabeledContent("Calls today") {
                        Text("\(model.callLog.count(on: today)) of \(model.settings.dailyCallLimit)")
                    }
                    LabeledContent("Cost today", value: usd(model.callLog.total(on: today)))
                    LabeledContent("Cost this month", value: usd(model.callLog.total(inMonthOf: today)))
                }
                Section {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: heightText) { _, text in
                change { $0.heightCm = try? Number.parse(text, field: "Height") }
            }
            .onChange(of: weightText) { _, text in
                change { $0.weightKg = try? Number.parse(text, field: "Weight") }
            }
            .onChange(of: ageText) { _, text in
                change { $0.ageYears = (try? Number.parse(text, field: "Age")).flatMap { Int(exactly: $0) } }
            }
            .confirmationDialog("Remove the saved key?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { removeKey() }
                Button("Cancel", role: .cancel) {}
            }
            .problemAlert("Could not save", $problem)
        }
    }

    private var keySection: some View {
        Section("API key") {
            SecureField("Anthropic API key", text: $keyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("api-key")
            Button("Save key", action: saveKey)
                .disabled(trimmedKey.isEmpty)
                .accessibilityIdentifier("save-key")
            if model.hasKey {
                Label("Key saved", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                Button("Remove key", role: .destructive) { confirmingRemove = true }
            }
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, id: String, keyboard: UIKeyboardType) -> some View {
        LabeledContent(title) {
            TextField("", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier(id)
        }
    }

    private var trimmedKey: String { keyText.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var languageBinding: Binding<Language> {
        Binding(main: { model.settings.language }, set: { value in change { $0.language = value } })
    }

    private var sexBinding: Binding<Sex?> {
        Binding(main: { model.settings.sex }, set: { value in change { $0.sex = value } })
    }

    private var activityBinding: Binding<ActivityLevel> {
        Binding(main: { model.settings.activity }, set: { value in change { $0.activity = value } })
    }

    private var limitBinding: Binding<Int> {
        Binding(main: { model.settings.dailyCallLimit }, set: { value in change { $0.dailyCallLimit = value } })
    }

    private func change(_ edit: (inout UserSettings) -> Void) {
        var next = model.settings
        edit(&next)
        do throws(Problem) {
            try model.update(next)
        } catch {
            problem = error
        }
    }

    private func saveKey() {
        do throws(KeychainError) {
            try keys.save(trimmedKey)
            keyText = ""
            model.refreshKey()
        } catch {
            problem = Problem(error)
        }
    }

    private func removeKey() {
        do throws(KeychainError) {
            try keys.remove()
            model.refreshKey()
        } catch {
            problem = Problem(error)
        }
    }

    private static func name(of level: ActivityLevel) -> LocalizedStringKey {
        switch level {
        case .atHome: "At home"
        case .light: "Light"
        case .moderate: "Moderate"
        case .heavy: "Heavy"
        }
    }

    /// The name and the build number that CI gave the app.
    private static let version = "\(infoValue("CFBundleShortVersionString")) (\(infoValue("CFBundleVersion")))"
}

// A missing key stops the app, because CI sets both and a wrong build must not be installed unnoticed.
private func infoValue(_ key: String) -> String {
    let value = Bundle.main.object(forInfoDictionaryKey: key)
    guard let text = value as? String else {
        fatalError("Info.plist key \(key): expected a string, saw \(String(describing: value))")
    }
    return text
}
