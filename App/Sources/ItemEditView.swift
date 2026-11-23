import Core
import Ledger
import SwiftUI

/// The form of one item. The energy follows the grams until the user types in it (R10). It can be typed in kJ,
/// and then its kcal show beside it.
struct ItemEditView: View {
    let meal: Meal
    /// The index of the item, or nil for a new one.
    let index: Int?
    let onSave: (Meal) -> Void

    private enum Field {
        case name
        case grams
        case energy
    }

    @Environment(\.dismiss) private var dismiss
    @State private var editor: ItemEditor
    @FocusState private var focus: Field?

    init(meal: Meal, index: Int?, onSave: @escaping (Meal) -> Void) {
        self.meal = meal
        self.index = index
        self.onSave = onSave
        _editor = State(initialValue: index.map { ItemEditor(editing: meal.items[$0]) } ?? ItemEditor())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                InputCard(label: "Name", focused: focus == .name) {
                    TextField("", text: $editor.name)
                        .textRole(.inputText)
                        .focused($focus, equals: .name)
                        .tint(Palette.moss)
                        .accessibilityIdentifier("item-name")
                }
                InputCard(label: "Grams", focused: focus == .grams) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TextField("", text: $editor.gramsText)
                            .textRole(.inputNumber)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .grams)
                            .tint(Palette.moss)
                            .accessibilityIdentifier("item-grams")
                        Text(verbatim: "g").textRole(.inputUnit).foregroundStyle(Palette.ink2)
                    }
                }
                energyCard
                if let problem = editor.problem {
                    ProblemText(problem: problem)
                }
            }
            .padding(.horizontal, Metrics.margin)
            .foregroundStyle(Palette.ink)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) {
            SheetHeader(title: index == nil ? "New item" : "Item", titleID: "item-title") {
                CloseButton { dismiss() }
            }
        }
        .background(Palette.canvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Save").frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle())
            .disabled(!isValid)
            .accessibilityIdentifier("item-save")
            .padding(.horizontal, Metrics.margin)
            .padding(.vertical, 8)
        }
        .designSheet()
    }

    /// The energy in the unit of the switch. In kJ a moss pill gives the kcal, the result of the conversion.
    private var energyCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Energy").textRole(.caption).foregroundStyle(Palette.ink2)
                Spacer(minLength: 8)
                Picker("Energy unit", selection: $editor.unit) {
                    ForEach(EnergyUnit.allCases, id: \.self) { unit in
                        Text(verbatim: unit.rawValue).tag(unit)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if editor.energyIsEstimate {
                    Text(verbatim: "≈").textRole(.inputUnit).foregroundStyle(Palette.ink2)
                }
                TextField("", text: energyField)
                    .textRole(.inputNumber)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .energy)
                    .tint(Palette.moss)
                    .accessibilityIdentifier("item-kcal")
                Text(verbatim: editor.unit.rawValue).textRole(.inputUnit).foregroundStyle(Palette.ink2)
            }
            if let kcal = editor.kcalEquivalent {
                Text("= \(Number.fieldText(kcal)) kcal")
                    .textRole(.label)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 32)
                    .foregroundStyle(Palette.onMoss)
                    .background(Palette.moss, in: .capsule)
                    .accessibilityIdentifier("kcal-equivalent")
            }
        }
        .inputCardStyle(focused: focus == .energy)
    }

    private var energyField: Binding<String> {
        Binding(main: { editor.energyText }, set: { editor.typeEnergy($0) })
    }

    private var isValid: Bool {
        if case .success = editor.item() { return true }
        return false
    }

    private func save() {
        // The button is off while the form is invalid, so a failure here has nothing left to show.
        guard case .success(let next) = editor.applied(to: meal, at: index) else { return }
        onSave(next)
        dismiss()
    }
}
