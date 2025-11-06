import SwiftUI
import UIKit

struct HomeRootView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @State private var showResumePrompt = false

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
            // Prompt to resume saved workout if present and no active session
            if workoutManager.currentSession == nil && workoutManager.hasSavedWorkout() {
                showResumePrompt = true
            }
        }
        .onChange(of: authManager.userProfile?.updatedAt) { _, _ in
            if let p = authManager.userProfile { workoutManager.initialize(with: p) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            workoutManager.saveWorkoutState()
            print("📱 App going to background - saved workout state")
        }
        // Offline banner
        .safeAreaInset(edge: .top) {
            if !networkMonitor.isConnected { OfflineBanner(text: "No connection. Offline mode enabled.") }
        }
        .alert("Resume your last workout?", isPresented: $showResumePrompt) {
            Button("Resume") {
                if let state = workoutManager.loadSavedWorkoutState() { workoutManager.restoreWorkoutState(state) }
            }
            Button("Discard", role: .destructive) {
                workoutManager.clearSavedWorkoutState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We found an in-progress workout. You can resume where you left off.")
        }
    }
}
