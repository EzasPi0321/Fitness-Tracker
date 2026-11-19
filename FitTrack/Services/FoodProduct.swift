import Foundation

/// A food resolved from a barcode, either from Open Food Facts or the user's own "My Foods".
struct FoodProduct: Identifiable, Hashable, Sendable {
    let barcode: String
    let name: String
    let brand: String?
    let imageURL: URL?
    let servingDescription: String?
    /// Grams (or ml) in one serving, when known.
    let servingGrams: Double?
    let per100g: Nutrients?
    /// Per-serving values as reported by the source (may be absent).
    let perServingReported: Nutrients?
    let source: EntrySource

    var id: String { barcode }

    /// Per-serving nutrition, derived from per-100 g values when not reported directly.
    var perServing: Nutrients? {
        if let perServingReported { return perServingReported }
        if let per100g, let servingGrams, servingGrams > 0 { return per100g * (servingGrams / 100) }
        return nil
    }

    var hasNutrition: Bool { per100g != nil || perServing != nil }

    var supportsGrams: Bool { nutrients(forGrams: 100) != nil }

    func nutrients(forGrams grams: Double) -> Nutrients? {
        if let per100g { return per100g * (grams / 100) }
        if let perServingReported, let servingGrams, servingGrams > 0 {
            return perServingReported * (grams / servingGrams)
        }
        return nil
    }

    func nutrients(forServings servings: Double) -> Nutrients? {
        perServing.map { $0 * servings }
    }

    var servingLabel: String {
        if let servingDescription, !servingDescription.isEmpty { return servingDescription }
        if let servingGrams { return "serving (\(servingGrams.formatted(.number.precision(.fractionLength(0...1)))) g)" }
        return "serving"
    }
}

extension FoodProduct {
    init(customFood food: CustomFood) {
        let perServing = food.perServing
        var per100g: Nutrients?
        if let grams = food.servingGrams, grams > 0 { per100g = perServing * (100 / grams) }
        self.init(barcode: food.barcode ?? food.id.uuidString,
                  name: food.name,
                  brand: food.brand,
                  imageURL: nil,
                  servingDescription: food.servingDescription,
                  servingGrams: food.servingGrams,
                  per100g: per100g,
                  perServingReported: perServing,
                  source: .customFood)
    }
}
