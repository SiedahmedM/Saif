//
//  SaifApp.swift
//  Saif
//
//  Created by Mohamed Siedahmed on 11/1/25.
//

import SwiftUI

@main
struct SaifApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var workoutManager = WorkoutManager()
    @StateObject private var networkMonitor = NetworkMonitor()

    init() {
        print("🟢 App init started")
        // Debug: temporarily avoid touching singletons here to isolate startup issues
        // print("TrainingKnowledgeService available: \(TrainingKnowledgeService.shared)")
        print("🟢 App init completed")
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack { AuthFlowView() }
                .environmentObject(authManager)
                .environmentObject(workoutManager)
                .environmentObject(networkMonitor)
                .tint(SAIFColors.primary)
        }
    }
}
