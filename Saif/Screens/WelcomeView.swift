import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var navigateTo: Goal?
    @State private var startWorkout = false
    @State private var showGoalSelection = false

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            VStack(spacing: SAIFSpacing.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SAIF")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(SAIFColors.text)
                        .kerning(1.0)
                    Text("Stronger. Smarter. Simpler.")
                        .font(.system(size: 16))
                        .foregroundStyle(SAIFColors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: SAIFSpacing.lg) {
                    if let currentGoal = authManager.userProfile?.primaryGoal {
                        Text("Current Goal: \(currentGoal.displayName)")
                            .font(.system(size: 16))
                            .foregroundStyle(SAIFColors.mutedText)
                    }

                    PrimaryButton("Start Workout") { startWorkout = true }

                    Button("Change Goal") { showGoalSelection = true }
                        .foregroundStyle(SAIFColors.mutedText)
                }

                Spacer()
                Text("Designed for gym-goers. No fluff, just progress.")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(SAIFSpacing.xl)
            .navigationDestination(isPresented: $startWorkout) {
                WorkoutStartView(selectedPreset: nil)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            NavigationLink(destination: CalendarHistoryView()) {
                Image(systemName: "calendar")
            }
        }
        .sheet(isPresented: $showGoalSelection) {
            GoalChangeSheet()
                .presentationDetents([.fraction(0.45)])
        }
    }
}

#Preview {
    NavigationStack { 
        WelcomeView()
            .environmentObject(WorkoutManager())
    }
}

// MARK: - Goal Change
private struct GoalChangeSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: SAIFSpacing.lg) {
            Text("Change Goal").font(.system(size: 20, weight: .semibold))
            ForEach([Goal.bulk, .cut, .maintain], id: \.self) { g in
                PrimaryButton(g.displayName) {
                    Task {
                        if var p = authManager.userProfile {
                            p.primaryGoal = g
                            try? await SupabaseService.shared.updateProfile(p)
                            authManager.userProfile = p
                        }
                        dismiss()
                    }
                }
            }
        }
        .padding(SAIFSpacing.xl)
        .background(SAIFColors.background)
    }
}
