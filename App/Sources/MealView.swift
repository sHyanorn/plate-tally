import Core
import Ledger
import SwiftUI
import Tally

private struct ItemTarget: Identifiable {
    /// The index of the item, or nil for a new one.
    let index: Int?
    var id: Int { index ?? -1 }
}

private struct ItemRow: View {
    let item: FoodItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                Text(gramsText(item.grams)).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(kcalText(item.kcal)).monospacedDigit()
        }
        .contentShape(.rect)
    }
}

/// The time and the items of one meal, with their edits (R10). A draft and a saved meal share it: the
/// caller decides what `apply` does with the changed meal.
struct MealForm: View {
    let model: AppModel
    let meal: Meal
    var photo: Photo?
    var cost: Decimal?
    let apply: @MainActor (Meal) throws(Problem) -> Void

    @State private var target: ItemTarget?
    @State private var problem: Problem?

    var body: some View {
        List {
            if let photo {
                Section {
                    Image(uiImage: photo.thumbnail)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(.rect(cornerRadius: 12))
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .accessibilityLabel("Photo of the meal")
                    if let cost {
                        LabeledContent("Analysis cost", value: usd(cost))
                    }
                }
            }
            Section {
                DatePicker("Time", selection: time)
            }
            Section("Items") {
                ForEach(meal.items.indices, id: \.self) { index in
                    Button {
                        target = ItemTarget(index: index)
                    } label: {
                        ItemRow(item: meal.items[index])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("item-\(index)")
                }
                .onDelete { remove(at: $0) }
                Button("Add item", systemImage: "plus") { target = ItemTarget(index: nil) }
                    .accessibilityIdentifier("add-item")
            }
            Section {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(kcalText(meal.totalKcal))
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .accessibilityIdentifier("meal-total")
                }
            }
        }
        .sheet(item: $target) { edited in
            ItemEditView(meal: meal, index: edited.index) { commit($0) }
        }
        .problemAlert("Could not save", $problem)
    }

    private var time: Binding<Date> {
        Binding(
            main: { model.instant(of: meal.at) },
            set: { date in
                guard let at = model.localTime(of: date) else { return }
                var moved = meal
                moved.at = at
                commit(moved)
            })
    }

    private func remove(at offsets: IndexSet) {
        var next = meal
        do throws(LedgerError) {
            for index in offsets.sorted(by: >) { next = try next.removingItem(at: index) }
        } catch {
            problem = Problem(error)
            return
        }
        commit(next)
    }

    private func commit(_ next: Meal) {
        do throws(Problem) {
            try apply(next)
        } catch {
            problem = error
        }
    }
}

/// A meal that came back from the model and is not saved yet. Saving stores it (R11); the photo goes with
/// the screen and is never stored.
struct DraftMealView: View {
    let model: AppModel
    let photo: Photo
    let cost: Decimal?
    let onSaved: () -> Void
    let onDiscard: () -> Void

    @State private var meal: Meal
    @State private var confirmingDiscard = false
    @State private var problem: Problem?

    init(
        model: AppModel, photo: Photo, cost: Decimal?, meal: Meal, onSaved: @escaping () -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.model = model
        self.photo = photo
        self.cost = cost
        self.onSaved = onSaved
        self.onDiscard = onDiscard
        _meal = State(initialValue: meal)
    }

    var body: some View {
        MealForm(model: model, meal: meal, photo: photo, cost: cost) { meal = $0 }
            .navigationTitle("New meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { confirmingDiscard = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .confirmationDialog("Discard this meal?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { onDiscard() }
                Button("Keep editing", role: .cancel) {}
            }
            .problemAlert("Could not save", $problem)
    }

    private func save() {
        do throws(Problem) {
            try model.add(meal)
            onSaved()
        } catch {
            problem = error
        }
    }
}

/// A saved meal (R12). Every edit is saved at once.
struct StoredMealView: View {
    let model: AppModel
    let id: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDelete = false
    @State private var problem: Problem?

    var body: some View {
        if let meal = model.ledger.meals.first(where: { $0.id == id }) {
            MealForm(model: model, meal: meal) { (next: Meal) throws(Problem) in try model.replace(next) }
                .navigationTitle("Meal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete meal", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("delete-meal")
                    }
                }
                .confirmationDialog("Delete this meal?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { delete() }
                    Button("Cancel", role: .cancel) {}
                }
                .problemAlert("Could not delete", $problem)
        }
    }

    private func delete() {
        do throws(Problem) {
            try model.deleteMeal(id: id)
            dismiss()
        } catch {
            problem = error
        }
    }
}
