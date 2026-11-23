import Core

/// The form behind one item (R10): the three texts as the user typed them. It says which item they make
/// and why they do not, so a screen has no rule of its own.
public struct ItemEditor: Equatable, Sendable {
    public var name: String
    public var gramsText: String
    /// Set when the user types in the energy field. Until then the energy follows the grams.
    public var typedKcalText: String?
    /// The item being edited, or nil for a new one.
    private let original: FoodItem?

    public init() {
        name = ""
        gramsText = ""
        typedKcalText = nil
        original = nil
    }

    public init(editing item: FoodItem) {
        name = item.name
        gramsText = plainNumber(item.grams)
        typedKcalText = nil
        original = item
    }

    /// What the energy field shows: the typed text, else the energy that follows the grams to one decimal.
    public var kcalText: String {
        if let typedKcalText { return typedKcalText }
        guard let original else { return "" }
        let followed = (try? Number.parse(gramsText, field: "Grams")).flatMap { try? original.settingGrams(to: $0) }
        return plainNumber(((followed ?? original).kcal * 10).rounded() / 10)
    }

    /// The item the texts make, or the first thing wrong with them.
    public func item() -> Result<FoodItem, Problem> {
        Result { () throws(Problem) in try build() }
    }

    /// What to tell the user now. Nil when the item is valid, and nil while a field is still blank,
    /// because a form that was just opened needs no complaint.
    public var problem: Problem? {
        guard case .failure(let problem) = item() else { return nil }
        // An energy field that was never typed in is blank for a new item and follows the grams otherwise.
        let kcalBlank = typedKcalText.map(isBlank) ?? (original == nil)
        return isBlank(name) || isBlank(gramsText) || kcalBlank ? nil : problem
    }

    /// The meal with this item put in place of the one at the index, or added when the index is nil.
    /// A refused edit gives a problem and nothing else changes.
    public func applied(to meal: Meal, at index: Int?) -> Result<Meal, Problem> {
        Result { () throws(Problem) in
            let built = try item().get()
            do throws(LedgerError) {
                if let index { return try meal.replacingItem(at: index, with: built) }
                return try meal.adding(built)
            } catch {
                throw Problem(error)
            }
        }
    }

    private func build() throws(Problem) -> FoodItem {
        let length = Limits.nameLength(of: name)
        guard Limits.nameLength.contains(length) else { throw Problem(LedgerError.name(length: length)) }
        let grams = try number(gramsText, field: "Grams")
        if let typedKcalText {
            let kcal = try number(typedKcalText, field: "Energy")
            guard Limits.kcal.contains(kcal) else { throw Problem(LedgerError.kcal(kcal)) }
            guard Limits.grams.contains(grams) else { throw Problem(LedgerError.grams(grams)) }
            return FoodItem(name: name, grams: grams, kcal: kcal)
        }
        // A new item has nothing to follow, so its energy must be typed.
        guard let original else { throw Problem(NumberError(field: "Energy", text: "")) }
        do throws(LedgerError) {
            var followed = try original.settingGrams(to: grams)
            followed.name = name
            return followed
        } catch {
            throw Problem(error)
        }
    }

    private func number(_ text: String, field: String) throws(Problem) -> Double {
        do throws(NumberError) {
            return try Number.parse(text, field: field)
        } catch {
            throw Problem(error)
        }
    }
}

private func isBlank(_ text: String) -> Bool {
    text.allSatisfy(\.isWhitespace)
}
