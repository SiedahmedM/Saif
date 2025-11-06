import SwiftUI
import UIKit

struct HomeRootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        TabView {
            NavigationStack { HomeDashboardView() }
                .tabItem { Label("Home", systemImage: "house") }
            NavigationStack { ProgressAnalyticsView() }
                .tabItem { Label("Analytics", systemImage: "chart.bar.doc.horizontal") }
            NavigationStack { CalendarHistoryView() }
                .tabItem { Label("Calendar", systemImage: "calendar") }
        }
        .onAppear {
            if let profile = authManager.userProfile { workoutManager.initialize(with: profile) }
        }
        .onChange(of: authManager.userProfile?.updatedAt) { _, _ in
            if let p = authManager.userProfile { workoutManager.initialize(with: p) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            workoutManager.saveWorkoutState()
            print("📱 App going to background - saved workout state")
        }
    }
}
