#if DEBUG
import SwiftData
import SwiftUI

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        do {
            let container = try ModelContainer.fitTrack(inMemory: true)
            let context = container.mainContext
            let profile = UserProfile()
            context.insert(profile)

            let samples: [(String, MealType, Nutrients)] = [
                ("Greek Yogurt", .breakfast, Nutrients(calories: 150, protein: 15, carbs: 8, fat: 6)),
                ("Banana", .breakfast, Nutrients(calories: 105, protein: 1.3, carbs: 27, fat: 0.4)),
                ("Chicken Salad", .lunch, Nutrients(calories: 480, protein: 42, carbs: 18, fat: 26)),
                ("Protein Bar", .snack, Nutrients(calories: 210, protein: 20, carbs: 22, fat: 7)),
            ]
            for (name, meal, nutrients) in samples {
                context.insert(FoodEntry(name: name, meal: meal, source: .manual,
                                         quantity: 1, unit: "serving", nutrients: nutrients))
            }
            for offset in 1...14 {
                let day = Date.now.adding(days: -offset)
                context.insert(FoodEntry(name: "Logged day", meal: .lunch, source: .manual, consumedAt: day,
                                         quantity: 1, unit: "serving",
                                         nutrients: Nutrients(calories: Double.random(in: 1600...2400),
                                                              protein: 120, carbs: 200, fat: 70)))
                context.insert(WeightEntry(date: day, kilograms: 70 + Double(offset) * 0.1))
            }
            return container
        } catch {
            fatalError("Preview container failed: \(error)")
        }
    }()

    static var profile: UserProfile {
        (try? container.mainContext.fetch(FetchDescriptor<UserProfile>()).first) ?? UserProfile()
    }
}
#endif
