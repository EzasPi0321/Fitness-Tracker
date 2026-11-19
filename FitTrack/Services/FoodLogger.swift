import Foundation
import SwiftData

/// Single entry point for creating, editing and deleting food entries so that SwiftData and
/// Apple Health always stay in step.
@MainActor
struct FoodLogger {
    let context: ModelContext
    let healthKit: HealthKitManager

    private var syncToHealth: Bool {
        healthKit.isAvailable && UserDefaults.standard.bool(forKey: SettingsKey.healthKitEnabled)
    }

    func log(_ entries: [FoodEntry]) async {
        for entry in entries { context.insert(entry) }
        save()
        guard syncToHealth else { return }
        for entry in entries { await pushToHealth(entry) }
        save()
    }

    /// Call after mutating an entry (portion, meal, time) to persist and re-sync it.
    func update(_ entry: FoodEntry) async {
        save()
        if let previous = entry.healthKitCorrelationID {
            do { try await healthKit.deleteFood(correlationID: previous) } catch { healthKit.report(error) }
            entry.healthKitCorrelationID = nil
        }
        if syncToHealth { await pushToHealth(entry) }
        save()
    }

    func delete(_ entry: FoodEntry) async {
        let correlationID = entry.healthKitCorrelationID
        context.delete(entry)
        save()
        if let correlationID {
            do { try await healthKit.deleteFood(correlationID: correlationID) } catch { healthKit.report(error) }
        }
    }

    private func pushToHealth(_ entry: FoodEntry) async {
        do {
            entry.healthKitCorrelationID = try await healthKit.saveFood(
                name: entry.name, nutrients: entry.nutrients, date: entry.consumedAt, entryID: entry.id
            )
        } catch {
            healthKit.report(error)
        }
    }

    private func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
