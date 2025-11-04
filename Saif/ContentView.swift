//
//  ContentView.swift
//  Saif
//
//  Created by Mohamed Siedahmed on 11/1/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager

    var body: some View {
        NavigationStack { WelcomeView() }
            .onAppear { if let p = authManager.userProfile { workoutManager.initialize(with: p) } }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthManager())
        .environmentObject(WorkoutManager())
}
