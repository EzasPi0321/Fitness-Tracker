import SwiftData
import SwiftUI

@main
struct FitTrackApp: App {
    @State private var healthKit = HealthKitManager()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer.fitTrack()
        } catch {
            fatalError("Unable to create the SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(healthKit)
        }
        .modelContainer(container)
    }
}
