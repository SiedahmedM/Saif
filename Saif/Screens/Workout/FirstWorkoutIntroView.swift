import SwiftUI

struct FirstWorkoutIntroView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) var dismiss
    @State private var isStarting = false
    var body: some View {
        NavigationStack {
            ZStack { SAIFColors.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                    Text("Get Your First Workout").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                    Text("Let's kick off with a personalized session. We'll guide you step by step.")
                        .foregroundStyle(SAIFColors.mutedText)
                    Spacer()
                    if isStarting { ProgressView().tint(SAIFColors.primary) }
                    else {
                        PrimaryButton("Start Your First Session") { startFirst() }
                        Button("Maybe later") { dismiss() }.foregroundStyle(SAIFColors.mutedText)
                    }
                }
                .padding(SAIFSpacing.xl)
            }
            .navigationTitle("SAIF").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func startFirst() {
        isStarting = true
        Task {
            if let profile = authManager.userProfile { workoutManager.initialize(with: profile) }
            await workoutManager.startWorkout(workoutType: "push")
            isStarting = false
            dismiss()
        }
    }
}

