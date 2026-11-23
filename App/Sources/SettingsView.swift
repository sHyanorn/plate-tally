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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group("Language") {
                    Picker("Language", selection: languageBinding) {
                        ForEach(Language.allCases, id: \.self) { language in
                            Text(verbatim: language.locale.localizedString(forIdentifier: language.rawValue) ?? language.rawValue)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("language")
                }
                group("API key") {
                    SettingsCard {
                        HStack(spacing: 12) {
                            SecureField("Anthropic API key", text: $keyText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .tint(Palette.moss)
                                .accessibilityIdentifier("api-key")
                            Button("Save key", action: saveKey)
                                .buttonStyle(SmallPillStyle(prominent: false))
                                .disabled(trimmedKey.isEmpty)
                                .accessibilityIdentifier("save-key")
                        }
                        .settingsRow()
                        if model.hasKey {
                            SettingsDivider()
                            HStack(spacing: 12) {
                                Label("Key saved", systemImage: "checkmark")
                                Spacer(minLength: 8)
                                Button("Remove key", role: .destructive) { confirmingRemove = true }
                                    .buttonStyle(SmallPillStyle(prominent: false))
                            }
                            .settingsRow()
                        }
                    }
                }
                group("Profile") {
                    SettingsCard {
                        field("Height (cm)", text: $heightText, id: "height", keyboard: .decimalPad)
                        SettingsDivider()
                        field("Weight (kg)", text: $weightText, id: "weight", keyboard: .decimalPad)
                        SettingsDivider()
                        field("Age (years)", text: $ageText, id: "age", keyboard: .numberPad)
                        SettingsDivider()
                        sexRow
                    }
                }
                group("Activity") {
                    Picker("Activity", selection: activityBinding) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text(Self.name(of: level)).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                group("Calls") {
                    SettingsCard {
                        Stepper(value: limitBinding, in: UserSettings.dailyLimits) {
                            LabeledContent("Daily limit", value: "\(model.settings.dailyCallLimit)")
                        }
                        .settingsRow()
                        .accessibilityIdentifier("daily-limit")
                    }
                }
                group("Usage") {
                    SettingsCard {
                        let today = model.today
                        LabeledContent("Calls today") {
                            Text("\(model.callLog.count(on: today)) of \(model.settings.dailyCallLimit)")
                        }
                        .settingsRow()
                        SettingsDivider()
                        LabeledContent("Cost today", value: usd(model.callLog.total(on: today))).settingsRow()
                        SettingsDivider()
                        LabeledContent("Cost this month", value: usd(model.callLog.total(inMonthOf: today)))
                            .settingsRow()
                        SettingsDivider()
                        LabeledContent("Version", value: Self.version).settingsRow()
                    }
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, Metrics.margin)
            .foregroundStyle(Palette.ink)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHeader(title: "Settings", titleID: "settings-title") {
                Button("Done") { dismiss() }.buttonStyle(SmallPillStyle(prominent: true))
            }
        }
        .background(Palette.canvas)
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
        .designSheet()
    }

    /// A group of settings under its caption.
    private func group(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).textRole(.caption).foregroundStyle(Palette.ink2).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func field(_ title: LocalizedStringKey, text: Binding<String>, id: String, keyboard: UIKeyboardType) -> some View {
        LabeledContent(title) {
            TextField("", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .textRole(.name)
                .tint(Palette.moss)
                .accessibilityIdentifier(id)
        }
        .settingsRow()
    }

    /// The whole row opens the menu, as a row of a list does: with the number pad up after the age, only the
    /// top of the row stays in sight.
    private var sexRow: some View {
        Menu {
            Picker(selection: sexBinding) {
                ForEach(Self.sexes, id: \.self) { sex in
                    Text(Self.name(of: sex)).tag(sex)
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 6) {
                Text("Sex")
                Spacer(minLength: 8)
                Text(Self.name(of: model.settings.sex))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity)
            .settingsRow()
            .contentShape(.rect)
        }
        .accessibilityIdentifier("sex")
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

    private static let sexes: [Sex?] = [nil, .female, .male]

    private static func name(of sex: Sex?) -> LocalizedStringKey {
        switch sex {
        case nil: "Not set"
        case .female?: "Female"
        case .male?: "Male"
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

/// Rows of settings on one card.
private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .textRole(.body)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .background(Palette.surface, in: .rect(cornerRadius: Metrics.cardRadius))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Palette.line).frame(height: 1)
    }
}

extension View {
    fileprivate func settingsRow() -> some View {
        frame(minHeight: 52)
    }
}

/// A small round button inside a row or beside a title. The prominent one is ink, the other the second surface.
private struct SmallPillStyle: ButtonStyle {
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textRole(.label)
            .lineLimit(1)
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .foregroundStyle(prominent ? Palette.onInk : Palette.ink)
            .background(prominent ? Palette.ink : Palette.surface2, in: .capsule)
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
