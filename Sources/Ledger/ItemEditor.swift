import Core

/// The form behind one item (R10): the three texts as the user typed them. It says which item they make
/// and why they do not, so a screen has no rule of its own.
public struct ItemEditor: Equatable, Sendable {
    public var name: String
    public var gramsText: String
    /// The unit in which the energy field shows and takes its number. A change of it changes no item.
    public var unit = EnergyUnit.kcal
    /// Set when the user types in the energy field. Until then the energy follows the grams.
    public private(set) var typedEnergy: TypedEnergy?
    /// The item being edited, or nil for a new one.
    private let original: FoodItem?

    public init() {
        name = ""
        gramsText = ""
        original = nil
    }

    public init(editing item: FoodItem) {
        name = item.name
        gramsText = plainNumber(item.grams)
        original = item
    }

    /// Takes the text of the energy field, in the unit the field is in. The text the field shows is no input:
    /// a field hands it back when it gains or loses the focus, and taken as typed it would stop the energy
    /// from following the grams.
    public mutating func typeEnergy(_ text: String) {
        guard text != energyText else { return }
        typedEnergy = TypedEnergy(unit: unit, text: text)
    }

    /// What the energy field shows: the text typed in this unit, else the energy in this unit to one decimal.
    public var energyText: String {
        if let typedEnergy, typedEnergy.unit == unit { return typedEnergy.text }
        return energyKcal.map { Number.fieldText(unit.value(ofKcal: $0)) } ?? ""
    }

    /// The kcal of the field while it is in kJ, or nil in kcal and while the field holds no number.
    public var kcalEquivalent: Double? { unit == .kJ ? energyKcal : nil }

    /// True while the energy is the item's own and not typed, which the screen marks as an estimate (R9).
    public var energyIsEstimate: Bool { typedEnergy == nil && original != nil }

    /// The item the texts make, or the first thing wrong with them.
    public func item() -> Result<FoodItem, Problem> {
        Result { () throws(Problem) in try build() }
    }

    /// What to tell the user now. Nil when the item is valid, and nil while a field is still blank,
    /// because a form that was just opened needs no complaint.
    public var problem: Problem? {
        guard case .failure(let problem) = item() else { return nil }
        // An energy field that was never typed in is blank for a new item and follows the grams otherwise.
        let energyBlank = typedEnergy.map { isBlank($0.text) } ?? (original == nil)
        return isBlank(name) || isBlank(gramsText) || energyBlank ? nil : problem
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

    /// The energy of the form in kcal with the bounds aside: typed, or following the grams.
    private var energyKcal: Double? {
        if let typedEnergy { return try? typedEnergy.kcal(field: "Energy") }
        guard let original else { return nil }
        let followed = (try? Number.parse(gramsText, field: "Grams")).flatMap { try? original.settingGrams(to: $0) }
        return (followed ?? original).kcal
    }

    private func build() throws(Problem) -> FoodItem {
        let length = Limits.nameLength(of: name)
        guard Limits.nameLength.contains(length) else { throw Problem(LedgerError.name(length: length)) }
        let grams = try number(gramsText, field: "Grams")
        if let typedEnergy {
            let kcal: Double
            do throws(NumberError) { kcal = try typedEnergy.kcal(field: "Energy") } catch { throw Problem(error) }
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
}

/// A number from a field of a form, its refusal as a problem the form shows.
func number(_ text: String, field: String) throws(Problem) -> Double {
    do throws(NumberError) {
        return try Number.parse(text, field: field)
    } catch {
        throw Problem(error)
    }
}

func isBlank(_ text: String) -> Bool {
    text.allSatisfy(\.isWhitespace)
}
