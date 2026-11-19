import Foundation
import SwiftData

@Model
final class UserProfile {
    var createdAt: Date = Date.now
    var sexRaw: String = BiologicalSex.female.rawValue
    var birthDate: Date = Date(timeIntervalSince1970: 631_152_000) // 1 Jan 1990
    var heightCm: Double = 170
    var weightKg: Double = 70
    var activityRaw: String = ActivityLevel.moderate.rawValue
    var goalRaw: String = WeightGoal.maintain.rawValue
    var usesMetric: Bool = true

    // Daily targets
    var calorieTarget: Double = 2000
    var proteinTarget: Double = 140
    var carbsTarget: Double = 220
    var fatTarget: Double = 65

    init() {}

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .female }
        set { sexRaw = newValue.rawValue }
    }

    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var goal: WeightGoal {
        get { WeightGoal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }

    var age: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    var targets: Nutrients {
        Nutrients(calories: calorieTarget, protein: proteinTarget, carbs: carbsTarget, fat: fatTarget)
    }

    func apply(_ plan: EnergyPlan) {
        calorieTarget = plan.targets.calories
        proteinTarget = plan.targets.protein
        carbsTarget = plan.targets.carbs
        fatTarget = plan.targets.fat
    }
}

@Model
final class WeightEntry {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kilograms: Double = 0

    init(date: Date, kilograms: Double) {
        self.date = date
        self.kilograms = kilograms
    }
}
