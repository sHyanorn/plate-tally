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
        let item = try requireItem(at: index)
        return replacing(index, with: try item.settingGrams(to: grams))
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

    public func adding(_ item: FoodItem) throws(LedgerError) -> Meal {
        guard items.count < Limits.maxItems else { throw .tooManyItems(items.count + 1) }
        try Self.requireInBounds(item)
        var copy = self
        copy.items.append(item)
        return copy
    }

    /// The bounds of R5 for one item. An added item and an item read from a file both meet them.
    static func requireInBounds(_ item: FoodItem) throws(LedgerError) {
        try requireName(item.name)
        guard Limits.grams.contains(item.grams) else { throw .grams(item.grams) }
        guard Limits.kcal.contains(item.kcal) else { throw .kcal(item.kcal) }
    }

    private func requireItem(at index: Int) throws(LedgerError) -> FoodItem {
        guard items.indices.contains(index) else { throw .itemIndex(index, count: items.count) }
        return items[index]
    }

    /// Swaps the item at the index for another, which the caller has checked.
    func replacingItem(at index: Int, with item: FoodItem) throws(LedgerError) -> Meal {
        _ = try requireItem(at: index)
        return replacing(index, with: item)
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

private let scalingTolerance = 1e-9

extension FoodItem {
    /// Grams equal to the current ones change nothing, because the scaling can move the kcal by one ulp.
    func settingGrams(to grams: Double) throws(LedgerError) -> FoodItem {
        guard Limits.grams.contains(grams) else { throw .grams(grams) }
        if grams == self.grams { return self }
        // Multiply first, then divide: when the product is exact, one rounding is all the result
        // has, and whole numbers stay whole (195 kcal at 150 g set to 300 g is 390).
        let scaled = kcal * grams / self.grams
        // The scaling is not reversible to the last bit: 5000 kcal at 1541.3 g set to 1324.1 g and back
        // gives 5000.000000000001, which would refuse the restore. A value that close is the bound.
        let upper = Limits.kcal.upperBound
        let kept = scaled > upper && scaled - upper <= scalingTolerance ? upper : scaled
        guard Limits.kcal.contains(kept) else { throw .scaledKcal(name: name, grams: grams, kcal: scaled) }
        var changed = self
        changed.grams = grams
        changed.kcal = kept
        return changed
    }
}
