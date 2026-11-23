import Core
import Ledger
import SwiftUI
import Tally

/// The energy converter (R27): the energy of a label in kJ or kcal, per serving or per 100 g, made into one
/// item of the latest meal of today or of a new meal. The arithmetic and the rules are EnergyConverter's.
/// A conversion is exact, so its results carry "="; the item it makes is an estimate in every list (R9).
struct ConverterView: View {
    let model: AppModel

    private enum Field: Hashable {
        case energy(EnergyUnit)
        case name
        case grams
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var form = EnergyConverter()
    /// The meal the item joins, or nil for a new meal.
    @State private var targetID: UUID?
    @State private var problem: Problem?
    @FocusState private var focus: Field?

    init(model: AppModel) {
        self.model = model
        _targetID = State(initialValue: model.latestMeal(on: model.today)?.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Energy converter", selection: $form.basis) {
                    Text("Per serving").tag(EnergyConverter.Basis.serving)
                    Text("Per 100 g").tag(EnergyConverter.Basis.per100g)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack(spacing: 8) {
                    energyCard(.kJ)
                    energyCard(.kcal)
                }
                .overlay {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .frame(width: 36, height: 36)
                        .background(Palette.canvas, in: .circle)
                        .overlay { Circle().strokeBorder(Palette.line, lineWidth: 1.5) }
                        .accessibilityHidden(true)
                }
                HStack(spacing: 8) {
                    InputCard(label: "Name", focused: focus == .name) {
                        TextField("", text: $form.name)
                            .textRole(.inputText)
                            .focused($focus, equals: .name)
                            .tint(Palette.moss)
                            .accessibilityIdentifier("converter-name")
                    }
                    InputCard(label: form.basis == .serving ? "Grams" : "Grams eaten", focused: focus == .grams) {
                        TextField("", text: $form.gramsText)
                            .textRole(.inputText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .grams)
                            .tint(Palette.moss)
                            .accessibilityIdentifier("converter-grams")
                    }
                    .frame(maxWidth: 140)
                }
                if let kcal = form.portionKcal, let kilojoules = form.portionKilojoules {
                    PortionTag(grams: form.gramsText, kcal: kcal, kilojoules: kilojoules)
                }
                Text(verbatim: "1 kcal = \(plainNumber(EnergyUnit.kilojoulesPerKilocalorie)) kJ")
                    .textRole(.caption)
                    .foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity)
                if let shown = problem ?? form.problem {
                    ProblemText(problem: shown)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .foregroundStyle(Palette.ink)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHeader(title: "Energy converter", titleID: "converter-title") {
                CloseButton { dismiss() }
            }
        }
        .background(Palette.canvas)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                targetMenu
                Button(action: add) {
                    Text("Add item").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .disabled(!isValid)
                .accessibilityIdentifier("converter-add")
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 8)
        }
        .onChange(of: form) { problem = nil }
        .designSheet()
    }

    /// One energy field. Per serving the kcal field is the result and carries the moss of a tag.
    private func energyCard(_ unit: EnergyUnit) -> some View {
        let isResult = form.basis == .serving && unit == .kcal
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: form.basis == .serving ? unit.rawValue : "\(unit.rawValue) / 100 g")
                .textRole(.caption)
                .foregroundStyle(isResult ? Palette.onMoss : Palette.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if form.follows(unit) {
                    Text(verbatim: "=").textRole(.inputUnit)
                }
                TextField("", text: energyField(unit))
                    .textRole(.inputNumber)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .energy(unit))
                    .tint(isResult ? Palette.onMoss : Palette.moss)
                    .accessibilityIdentifier(unit == .kJ ? "converter-kj" : "converter-kcal")
            }
        }
        .foregroundStyle(isResult ? Palette.onMoss : Palette.ink)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(isResult ? Palette.moss : Palette.surface, in: .rect(cornerRadius: Metrics.inputRadius))
        .overlay {
            if focus == .energy(unit) {
                RoundedRectangle(cornerRadius: Metrics.inputRadius)
                    .strokeBorder(isResult ? Palette.onMoss : Palette.ink, lineWidth: 2)
            }
        }
    }

    private func energyField(_ unit: EnergyUnit) -> Binding<String> {
        Binding(main: { form.text(in: unit) }, set: { form.type($0, in: unit) })
    }

    /// The meal the item joins: the latest of today, shown with its time, or a new one. Without a meal today
    /// the menu has the new meal only.
    private var targetMenu: some View {
        Menu {
            Picker(selection: $targetID) {
                if let latest = model.latestMeal(on: model.today) {
                    Text("Latest meal \(time(of: latest))").tag(Optional(latest.id))
                }
                Text("New meal").tag(UUID?.none)
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: 6) {
                Text("Add to \(targetName)").lineLimit(1).minimumScaleFactor(0.7)
                Image(systemName: "chevron.down")
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                    .accessibilityHidden(true)
            }
            .textRole(.label)
            .padding(.horizontal, 18)
            .frame(minHeight: Metrics.pillHeight)
            .background(Palette.surface2, in: .capsule)
            .foregroundStyle(Palette.ink)
        }
        .accessibilityIdentifier("converter-target")
    }

    private var targetName: Text {
        guard let id = targetID, let meal = model.ledger.meals.first(where: { $0.id == id }) else {
            return Text("New meal")
        }
        return Text("Latest meal \(time(of: meal))")
    }

    private func time(of meal: Meal) -> String {
        model.instant(of: meal.at).formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
    }

    private var isValid: Bool {
        if case .success = form.item() { return true }
        return false
    }

    private func add() {
        // The button is off while the form is invalid, so only the meal can refuse the item.
        guard case .success(let item) = form.item() else { return }
        do throws(Problem) {
            try model.add(item, toMealWithID: targetID)
            dismiss()
        } catch {
            problem = error
        }
    }
}

/// Per 100 g: what the grams eaten hold, the result of the conversion, as a moss tag.
private struct PortionTag: View {
    let grams: String
    let kcal: Double
    let kilojoules: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "\(grams.trimmingCharacters(in: .whitespaces)) g")
                Spacer(minLength: 4)
                Text(verbatim: "kcal").accessibilityHidden(true)
            }
            .textRole(.unit)
            HStack(alignment: .lastTextBaseline) {
                SignedNumber(
                    sign: "=", value: kcal, text: wholeNumber(kcal), spoken: "= \(wholeNumber(kcal)) kcal",
                    role: .tagNumber
                )
                .accessibilityIdentifier("converter-result")
                Spacer(minLength: 8)
                Text(verbatim: "= \(wholeNumber(kilojoules)) kJ").textRole(.label)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .foregroundStyle(Palette.onMoss)
        .background(Palette.moss, in: .rect(cornerRadius: Metrics.tagRadius))
    }
}
