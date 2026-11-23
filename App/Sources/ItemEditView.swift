import Core
import Ledger
import SwiftUI

/// The form of one item. The energy follows the grams until the user types in it (R10).
struct ItemEditView: View {
    let meal: Meal
    /// The index of the item, or nil for a new one.
    let index: Int?
    let onSave: (Meal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editor: ItemEditor

    init(meal: Meal, index: Int?, onSave: @escaping (Meal) -> Void) {
        self.meal = meal
        self.index = index
        self.onSave = onSave
        _editor = State(initialValue: index.map { ItemEditor(editing: meal.items[$0]) } ?? ItemEditor())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Name") {
                        TextField("", text: $editor.name)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("item-name")
                    }
                    LabeledContent("Grams") {
                        TextField("", text: $editor.gramsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("item-grams")
                    }
                    LabeledContent("Energy (kcal)") {
                        TextField("", text: energyField)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("item-kcal")
                    }
                }
                if let problem = editor.problem {
                    Section {
                        Text(problem.message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(index == nil ? LocalizedStringKey("New item") : LocalizedStringKey("Item"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid)
                }
            }
        }
    }

    private var energyField: Binding<String> {
        Binding(main: { editor.kcalText }, set: { editor.typedKcalText = $0 })
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
