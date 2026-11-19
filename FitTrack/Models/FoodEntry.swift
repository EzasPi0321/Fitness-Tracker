import Foundation
import SwiftData

/// A single logged food. Nutrition values are stored as *totals for the logged portion*,
/// so daily sums are a simple reduction. `quantity` + `unit` describe the portion and allow
/// linear rescaling when the user edits it later.
///
/// All properties have defaults and there are no unique constraints so the model is
/// compatible with SwiftData's CloudKit sync.
@Model
final class FoodEntry {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var barcode: String?
    var mealRaw: String = MealType.snack.rawValue
    var sourceRaw: String = EntrySource.manual.rawValue
    var consumedAt: Date = Date.now

    /// Portion description, e.g. `1.5` × `"serving (30 g)"` or `180` × `"g"`.
    var quantity: Double = 1
    var unit: String = "serving"
    /// Total grams for the portion, when known.
    var grams: Double?

    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    /// UUID of the `HKCorrelation` (food) written to Apple Health, used for deletes/updates.
    var healthKitCorrelationID: UUID?

    init(name: String,
         brand: String? = nil,
         barcode: String? = nil,
         meal: MealType,
         source: EntrySource,
         consumedAt: Date = .now,
         quantity: Double,
         unit: String,
         grams: Double? = nil,
         nutrients: Nutrients) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.mealRaw = meal.rawValue
        self.sourceRaw = source.rawValue
        self.consumedAt = consumedAt
        self.quantity = quantity
        self.unit = unit
        self.grams = grams
        let clean = nutrients.sanitized
        self.calories = clean.calories
        self.protein = clean.protein
        self.carbs = clean.carbs
        self.fat = clean.fat
    }

    var meal: MealType {
        get { MealType(rawValue: mealRaw) ?? .snack }
        set { mealRaw = newValue.rawValue }
    }

    var source: EntrySource {
        get { EntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var nutrients: Nutrients {
        get { Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat) }
        set {
            let clean = newValue.sanitized
            calories = clean.calories
            protein = clean.protein
            carbs = clean.carbs
            fat = clean.fat
        }
    }

    var portionDescription: String {
        let amount = quantity.formatted(.number.precision(.fractionLength(0...2)))
        return unit == "g" ? "\(amount) g" : "\(amount) × \(unit)"
    }

    /// Linearly rescales nutrition (and grams) to a new portion quantity.
    func rescale(toQuantity newQuantity: Double) {
        guard quantity > 0, newQuantity > 0, newQuantity != quantity else { return }
        let factor = newQuantity / quantity
        nutrients = nutrients * factor
        grams = grams.map { $0 * factor }
        quantity = newQuantity
    }
}
