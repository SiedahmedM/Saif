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

    var body: some Scene {
        WindowGroup {
            NavigationStack { AuthFlowView() }
                .environmentObject(authManager)
                .environmentObject(workoutManager)
                .tint(SAIFColors.primary)
        }
    }
}
