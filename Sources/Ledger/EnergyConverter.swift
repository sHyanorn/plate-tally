import Core

/// The form of the energy converter: the energy on a label, per serving or per 100 g, in kJ or kcal, made
/// into one item. The two energy fields follow each other, so the user types into either. The rules are
/// those of ItemEditor: the bounds of R5, the same errors, and no complaint while a field is blank.
public struct EnergyConverter: Equatable, Sendable {
    public enum Basis: Sendable, CaseIterable {
        case serving
        case per100g
    }

    public var basis = Basis.serving
    public var name = ""
    public var gramsText = ""
    /// The energy typed for each basis. Kept apart, so a change of basis never reads a value per serving
    /// as one per 100 g.
    private var typed: [Basis: TypedEnergy] = [:]

    public init() {}

    /// Takes the text of the energy field of a unit, for the current basis.
    public mutating func type(_ text: String, in unit: EnergyUnit) {
        typed[basis] = TypedEnergy(unit: unit, text: text)
    }

    /// What the energy field of a unit shows: the text typed in it, else the other field converted, to one
    /// decimal, or nothing while the other holds no number.
    public func text(in unit: EnergyUnit) -> String {
        guard let entry = typed[basis] else { return "" }
        if entry.unit == unit { return entry.text }
        guard let kcal = try? entry.kcal(field: "") else { return "" }
        return Number.fieldText(unit.value(ofKcal: kcal))
    }

    /// True when the field of the unit shows the conversion of the other field.
    public func follows(_ unit: EnergyUnit) -> Bool {
        typed[basis].map { $0.unit != unit } ?? false
    }

    /// Per 100 g: the kcal of the grams eaten, with the bounds aside. Nil per serving, where the kcal field
    /// is the result, and until the energy and the grams are numbers.
    public var portionKcal: Double? {
        guard basis == .per100g, let per100g = try? typed[basis]?.kcal(field: ""),
            let grams = try? Number.parse(gramsText, field: "")
        else { return nil }
        return per100g * grams / 100
    }

    public var portionKilojoules: Double? {
        portionKcal.map { EnergyUnit.kJ.value(ofKcal: $0) }
    }

    /// The item the texts make, or the first thing wrong with them.
    public func item() -> Result<FoodItem, Problem> {
        Result { () throws(Problem) in try build() }
    }

    /// What to tell the user now: nil when the item is valid or a field is still blank.
    public var problem: Problem? {
        guard case .failure(let problem) = item() else { return nil }
        let energyBlank = typed[basis].map { isBlank($0.text) } ?? true
        return isBlank(name) || isBlank(gramsText) || energyBlank ? nil : problem
    }

    private func build() throws(Problem) -> FoodItem {
        let length = Limits.nameLength(of: name)
        guard Limits.nameLength.contains(length) else { throw Problem(LedgerError.name(length: length)) }
        let grams = try number(gramsText, field: basis == .serving ? "Grams" : "Grams eaten")
        guard Limits.grams.contains(grams) else { throw Problem(LedgerError.grams(grams)) }
        let entry = typed[basis] ?? TypedEnergy(unit: .kcal, text: "")
        let typedKcal: Double
        do throws(NumberError) {
            typedKcal = try entry.kcal(field: basis == .serving ? "Energy" : "\(entry.unit.rawValue) / 100 g")
        } catch {
            throw Problem(error)
        }
        // Multiply first, then divide, as the scaling of an item does.
        let kcal = basis == .serving ? typedKcal : typedKcal * grams / 100
        guard Limits.kcal.contains(kcal) else { throw Problem(LedgerError.kcal(kcal)) }
        return FoodItem(name: name, grams: grams, kcal: kcal)
    }
}
