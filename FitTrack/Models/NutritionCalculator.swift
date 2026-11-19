import Foundation

enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female, male
    var id: String { rawValue }
    var title: String { self == .female ? "Female" : "Male" }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    /// Standard TDEE multipliers applied to BMR.
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }

    var title: String {
        switch self {
        case .sedentary: "Sedentary"
        case .light: "Lightly Active"
        case .moderate: "Moderately Active"
        case .active: "Very Active"
        case .veryActive: "Extremely Active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Desk job, little or no exercise"
        case .light: "Light exercise 1–3 days a week"
        case .moderate: "Moderate exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job or twice-daily training"
        }
    }
}

enum WeightGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose, maintain, gain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: "Lose Weight"
        case .maintain: "Maintain Weight"
        case .gain: "Build Muscle"
        }
    }

    var detail: String {
        switch self {
        case .lose: "About 0.5 kg (1 lb) per week"
        case .maintain: "Stay where you are"
        case .gain: "Lean surplus of ~300 kcal"
        }
    }

    var symbolName: String {
        switch self {
        case .lose: "arrow.down.right.circle.fill"
        case .maintain: "equal.circle.fill"
        case .gain: "arrow.up.right.circle.fill"
        }
    }

    /// kcal/day added to TDEE.
    var calorieAdjustment: Double {
        switch self {
        case .lose: -500
        case .maintain: 0
        case .gain: 300
        }
    }

    /// Protein target in g per kg of body weight.
    var proteinPerKg: Double {
        switch self {
        case .lose: 2.0
        case .maintain: 1.6
        case .gain: 1.8
        }
    }
}

struct EnergyPlan: Equatable, Sendable {
    let bmr: Double
    let tdee: Double
    let targets: Nutrients
}

enum NutritionCalculator {
    /// Mifflin–St Jeor resting energy expenditure, kcal/day.
    static func bmr(sex: BiologicalSex, weightKg: Double, heightCm: Double, age: Int) -> Double {
        let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
        return sex == .male ? base + 5 : base - 161
    }

    static func plan(sex: BiologicalSex,
                     age: Int,
                     heightCm: Double,
                     weightKg: Double,
                     activity: ActivityLevel,
                     goal: WeightGoal) -> EnergyPlan {
        let restingEnergy = Self.bmr(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age)
        let tdee = restingEnergy * activity.multiplier

        // Never recommend below commonly cited safe minimums without medical supervision.
        let minimum: Double = sex == .male ? 1500 : 1200
        let calories = (max(minimum, tdee + goal.calorieAdjustment) / 10).rounded() * 10

        // Protein by body weight, fat at 25 % of energy (at least 0.6 g/kg), carbs fill the rest.
        var protein = (weightKg * goal.proteinPerKg).rounded()
        var fat = max(calories * 0.25 / 9, weightKg * 0.6).rounded()
        // Guard against very small budgets where protein + fat would exceed calories.
        if protein * 4 + fat * 9 > calories {
            let scale = calories * 0.9 / (protein * 4 + fat * 9)
            protein = (protein * scale).rounded()
            fat = (fat * scale).rounded()
        }
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4).rounded()

        return EnergyPlan(bmr: restingEnergy,
                          tdee: tdee,
                          targets: Nutrients(calories: calories, protein: protein, carbs: carbs, fat: fat))
    }
}

enum UnitConversion {
    static let poundsPerKilogram = 2.204_622_62
    static let centimetersPerInch = 2.54
}
