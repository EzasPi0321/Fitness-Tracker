import Foundation

/// Energy and macronutrients for an arbitrary amount of food.
struct Nutrients: Codable, Hashable, Sendable {
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double

    init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    static let zero = Nutrients()

    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(calories: lhs.calories + rhs.calories,
                  protein: lhs.protein + rhs.protein,
                  carbs: lhs.carbs + rhs.carbs,
                  fat: lhs.fat + rhs.fat)
    }

    static func += (lhs: inout Nutrients, rhs: Nutrients) { lhs = lhs + rhs }

    static func * (lhs: Nutrients, factor: Double) -> Nutrients {
        Nutrients(calories: lhs.calories * factor,
                  protein: lhs.protein * factor,
                  carbs: lhs.carbs * factor,
                  fat: lhs.fat * factor)
    }

    /// Replaces negative or non-finite values (common in crowd-sourced / AI data) with zero.
    var sanitized: Nutrients {
        func clean(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
        return Nutrients(calories: clean(calories), protein: clean(protein), carbs: clean(carbs), fat: clean(fat))
    }
}

extension Sequence where Element == Nutrients {
    func sum() -> Nutrients { reduce(.zero, +) }
}

enum Macro: String, CaseIterable, Identifiable, Sendable {
    case protein, carbs, fat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }

    var shortTitle: String {
        switch self {
        case .protein: "P"
        case .carbs: "C"
        case .fat: "F"
        }
    }

    var kcalPerGram: Double { self == .fat ? 9 : 4 }

    func value(in nutrients: Nutrients) -> Double {
        switch self {
        case .protein: nutrients.protein
        case .carbs: nutrients.carbs
        case .fat: nutrients.fat
        }
    }
}
