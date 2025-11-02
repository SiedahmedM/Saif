//
//  ContentView.swift
//  Saif
//
//  Created by Mohamed Siedahmed on 11/1/25.
//

import SwiftUI

// Keep ContentView as a simple entry that forwards to WelcomeView
struct ContentView: View {
    var body: some View {
        NavigationStack { WelcomeView() }
    }
}

#Preview {
    ContentView()
}
