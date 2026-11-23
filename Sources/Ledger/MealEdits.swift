import Core

/// The edits of R10. Each returns the changed meal and leaves this one as it is, so a refused edit
/// changes nothing. The total is derived from the items, so it follows every edit.
extension Meal {
    public func renamingItem(at index: Int, to name: String) throws(LedgerError) -> Meal {
        var item = try requireItem(at: index)
        try Self.requireName(name)
        item.name = name
        return replacing(index, with: item)
    }

    /// The kcal of the item scale in proportion to the grams (R10). An edit that would put the scaled
    /// kcal outside 0 to 5000 is refused as a whole.
    public func settingGrams(ofItemAt index: Int, to grams: Double) throws(LedgerError) -> Meal {
        var item = try requireItem(at: index)
        guard Limits.grams.contains(grams) else { throw .grams(grams) }
        // Multiply first, then divide: 130 kcal for 150 g at 100 g is 86.66666666666667, and one
        // rounding is all it has.
        let kcal = item.kcal * grams / item.grams
        guard Limits.kcal.contains(kcal) else {
            throw .scaledKcal(name: item.name, grams: grams, kcal: kcal)
        }
        item.grams = grams
        item.kcal = kcal
        return replacing(index, with: item)
    }

    /// The grams stay, so the energy per 100 g changes, and a later change of the grams scales from it.
    public func settingKcal(ofItemAt index: Int, to kcal: Double) throws(LedgerError) -> Meal {
        var item = try requireItem(at: index)
        guard Limits.kcal.contains(kcal) else { throw .kcal(kcal) }
        item.kcal = kcal
        return replacing(index, with: item)
    }

    public func removingItem(at index: Int) throws(LedgerError) -> Meal {
        _ = try requireItem(at: index)
        var copy = self
        copy.items.remove(at: index)
        return copy
    }

    /// An added item needs a name, grams and kcal (R10), which the type already requires.
    public func adding(_ item: FoodItem) throws(LedgerError) -> Meal {
        guard items.count < Limits.maxItems else { throw .tooManyItems(items.count + 1) }
        try Self.requireName(item.name)
        guard Limits.grams.contains(item.grams) else { throw .grams(item.grams) }
        guard Limits.kcal.contains(item.kcal) else { throw .kcal(item.kcal) }
        var copy = self
        copy.items.append(item)
        return copy
    }

    private func requireItem(at index: Int) throws(LedgerError) -> FoodItem {
        guard items.indices.contains(index) else { throw .itemIndex(index, count: items.count) }
        return items[index]
    }

    private func replacing(_ index: Int, with item: FoodItem) -> Meal {
        var copy = self
        copy.items[index] = item
        return copy
    }

    private static func requireName(_ name: String) throws(LedgerError) {
        let length = Limits.nameLength(of: name)
        guard Limits.nameLength.contains(length) else { throw .name(length: length) }
    }
}
