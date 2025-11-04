import SwiftUI

struct GroupPlanView: View {
    let muscleGroup: String
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var count: Int = 2
    @State private var reason: String = ""
    @State private var goSelect = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                if !reason.isEmpty {
                    CardView(title: "AI Recommendation") {
                        Text(reason)
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                }

                Text("How many exercises for \(displayName(muscleGroup))?")
                    .font(.system(size: 22, weight: .bold))

                // Slider 1-5 with live value
                HStack {
                    Slider(value: Binding(get: { Double(count) }, set: { count = Int($0.rounded()) }), in: 1...5, step: 1)
                    Text("\(count)")
                        .frame(width: 36)
                }

                PrimaryButton("Confirm") {
                    workoutManager.setTarget(for: muscleGroup, count: count)
                    goSelect = true
                }

                NavigationLink(isActive: $goSelect) { ExerciseSelectionView(muscleGroup: muscleGroup) } label: { EmptyView() }
                Spacer()
            }
            .padding(SAIFSpacing.xl)
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let rec = workoutManager.recommendExerciseCount(for: muscleGroup)
            count = rec.count
            reason = rec.reason
        }
    }

    private func displayName(_ key: String) -> String { key.replacingOccurrences(of: "_", with: " ").capitalized }
}
