//
//  SaifApp.swift
//  Saif
//
//  Created by Mohamed Siedahmed on 11/1/25.
//

import SwiftUI

@main
struct SaifApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WelcomeView()
            }
            .tint(SAIFColors.primary)
        }
    }
}
