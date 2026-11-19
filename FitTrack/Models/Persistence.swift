import Foundation
import SwiftData

enum AppConfig {
    /// Flip to `true` after adding the iCloud (CloudKit) capability + container in Xcode.
    static let cloudKitSyncEnabled = false
}

enum SettingsKey {
    static let healthKitEnabled = "settings.healthKitEnabled"
    static let addActiveEnergyToBudget = "settings.addActiveEnergyToBudget"
    static let visionProvider = "settings.visionProvider"
    static let visionModel = "settings.visionModel"
}

extension ModelContainer {
    static let fitTrackSchema = Schema([
        FoodEntry.self,
        CustomFood.self,
        UserProfile.self,
        WeightEntry.self,
    ])

    static func fitTrack(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: fitTrackSchema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: (AppConfig.cloudKitSyncEnabled && !inMemory) ? .automatic : .none
        )
        return try ModelContainer(for: fitTrackSchema, configurations: [configuration])
    }
}
