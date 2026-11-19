import SwiftData
import SwiftUI

struct RootView: View {
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                MainTabView(profile: profile)
                    .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.default, value: profiles.isEmpty)
    }
}

struct MainTabView: View {
    let profile: UserProfile

    var body: some View {
        TabView {
            DashboardView(profile: profile)
                .tabItem { Label("Today", systemImage: "chart.pie.fill") }
            TrendsView(profile: profile)
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            SettingsView(profile: profile)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .modelContainer(PreviewData.container)
        .environment(HealthKitManager())
}
#endif
