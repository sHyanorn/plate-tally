import Core
import Ledger
import SwiftUI
import Tally

private struct ItemTarget: Identifiable {
    /// The index of the item, or nil for a new one.
    let index: Int?
    var id: Int { index ?? -1 }
}

/// One item on the card of items, with a hairline below it.
private struct ItemRow: View {
    let item: FoodItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).textRole(.name).lineLimit(1)
                Text(gramsText(item.grams)).textRole(.caption).foregroundStyle(Palette.ink2)
            }
            Spacer(minLength: 8)
            Text(kcalText(item.kcal)).textRole(.rowNumber)
        }
        .frame(minHeight: 64)
        .padding(.horizontal, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 20)
        }
        .contentShape(.rect)
    }
}

/// The photo of a draft, which is never stored (R11), with the cost of its analysis on it (R17).
private struct PhotoCard: View {
    let photo: Photo
    let cost: Decimal?

    var body: some View {
        Color.clear
            .frame(height: 196)
            .overlay {
                Image(uiImage: photo.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Photo of the meal")
            }
            .clipShape(.rect(cornerRadius: Metrics.cardRadius))
            .overlay(alignment: .bottomLeading) {
                if let cost {
                    HStack(spacing: 4) {
                        Text("Analysis cost")
                        Text(verbatim: usd(cost))
                    }
                    .textRole(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 30)
                    .background(Color.black.opacity(0.7), in: .capsule)
                    .padding(12)
                }
            }
    }
}

/// The time and the items of one meal, with their edits (R10). A draft and a saved meal share it: the
/// caller decides what `apply` does with the changed meal.
struct MealForm: View {
    let model: AppModel
    let meal: Meal
    let title: LocalizedStringKey
    var photo: Photo?
    var cost: Decimal?
    let apply: @MainActor (Meal) throws(Problem) -> Void

    @State private var target: ItemTarget?
    @State private var problem: Problem?

    var body: some View {
        List {
            Text(title)
                .textRole(.pageTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("meal-title")
                .padding(.bottom, Metrics.gap)
                .plainListRow()
            if let photo {
                PhotoCard(photo: photo, cost: cost)
                    .padding(.bottom, Metrics.gap)
                    .plainListRow()
            }
            EnergyTag(label: "Total", kcal: meal.totalKcal, numberID: "meal-total", minHeight: 72)
                .padding(.bottom, Metrics.gap)
                .plainListRow()
            ForEach(meal.items.indices, id: \.self) { index in
                Button {
                    target = ItemTarget(index: index)
                } label: {
                    ItemRow(item: meal.items[index])
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("item-\(index)")
                .cardListRow(roundsTop: index == 0, roundsBottom: false)
            }
            .onDelete { remove(at: $0) }
            Button {
                target = ItemTarget(index: nil)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(.subheadline, design: .rounded, weight: .heavy))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Palette.onInk)
                        .background(Palette.ink, in: .circle)
                        .accessibilityHidden(true)
                    Text("Add item").textRole(.label)
                }
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .padding(.horizontal, 20)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add-item")
            .cardListRow(roundsTop: meal.items.isEmpty, roundsBottom: true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.canvas)
        .foregroundStyle(Palette.ink)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DatePicker("Time", selection: time).labelsHidden()
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
        MealForm(model: model, meal: meal, title: "New meal", photo: photo, cost: cost) { meal = $0 }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { confirmingDiscard = true }
                }
            }
            .safeAreaBar(edge: .bottom) {
                Button(action: save) {
                    Text("Save").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle())
                .accessibilityIdentifier("meal-save")
                .padding(.horizontal, Metrics.margin)
                .padding(.vertical, 8)
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
            MealForm(model: model, meal: meal, title: "Meal") { (next: Meal) throws(Problem) in
                try model.replace(next)
            }
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
