import SwiftUI

struct HomeRootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        TabView {
            NavigationStack { HomeDashboardView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { CalendarHistoryView() }
                .tabItem { Label("Calendar", systemImage: "calendar") }
        }
        .onAppear {
            if let profile = authManager.userProfile { workoutManager.initialize(with: profile) }
        }
    }
}

