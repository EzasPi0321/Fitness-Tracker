import Foundation
import SwiftData

/// A user-defined food ("My Foods"). Also acts as a local cache for barcodes that
/// Open Food Facts doesn't know, so the next scan resolves instantly and offline.
@Model
final class CustomFood {
    var id: UUID = UUID()
    var name: String = ""
    var brand: String?
    var barcode: String?
    var servingDescription: String = "serving"
    var servingGrams: Double?

    // Per single serving
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    var createdAt: Date = Date.now
    var lastUsedAt: Date = Date.now
    var useCount: Int = 0

    init(name: String,
         brand: String? = nil,
         barcode: String? = nil,
         servingDescription: String,
         servingGrams: Double? = nil,
         perServing: Nutrients) {
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.servingDescription = servingDescription
        self.servingGrams = servingGrams
        self.perServing = perServing
    }

    var perServing: Nutrients {
        get { Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat) }
        set {
            let clean = newValue.sanitized
            calories = clean.calories
            protein = clean.protein
            carbs = clean.carbs
            fat = clean.fat
        }
    }

    func markUsed() {
        lastUsedAt = .now
        useCount += 1
    }
}
