import SwiftUI

struct WorkoutStartView: View {
    let selectedPreset: Preset?
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var isLoading = false
    @State private var started = false
    @State private var showAlternatives = false
    @State private var showFirstChoice = false
    @State private var goSummary = false

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            VStack(spacing: SAIFSpacing.xl) {
                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                    Text(selectedPreset == nil ? "Start Workout" : "Start \(selectedPreset!.displayName)")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(SAIFColors.text)
                    Text("We’ll plan the session and suggest a flow.")
                        .font(.system(size: 16))
                        .foregroundStyle(SAIFColors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let preset = selectedPreset {
                    CardView(title: "Today’s Focus", subtitle: preset.displayName) {
                        Text(hint(for: preset))
                            .font(.system(size: 16))
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                }

                if isLoading {
                    ProgressView().tint(SAIFColors.primary)
                } else if let preset = selectedPreset {
                    PrimaryButton("Start Workout") { start(workoutType: preset.rawValue) }
                } else {
                    // AI-first flow
                    if let rec = workoutManager.workoutRecommendation {
                        CardView {
                            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                                Text("Recommended for Today").font(.system(size: 16, weight: .semibold))
                                Text(rec.workoutType.capitalized + " Workout")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(SAIFColors.primary)
                                Text(rec.reasoning).font(.system(size: 15)).foregroundStyle(SAIFColors.mutedText)
                                PrimaryButton("Start \(rec.workoutType.capitalized) Workout") { start(workoutType: rec.workoutType) }
                                Button("Select Other Workout") { showAlternatives = true }
                                    .foregroundStyle(SAIFColors.mutedText)
                            }
                        }
                    } else {
                        PrimaryButton("Get Recommendation") { Task { await workoutManager.getWorkoutRecommendation() } }
                    }
                }

                Spacer()
                NavigationLink(destination: MuscleGroupSelectionView().environmentObject(workoutManager), isActive: $started) { EmptyView() }
            }
            .padding(SAIFSpacing.xl)
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if selectedPreset == nil && workoutManager.workoutRecommendation == nil {
                await workoutManager.getWorkoutRecommendation()
            }
        }
        .onChange(of: workoutManager.workoutRecommendation) { rec in
            if let rec, rec.isFirstWorkout == true { showFirstChoice = true }
        }
        .actionSheet(isPresented: $showAlternatives) {
            ActionSheet(title: Text("Choose Workout Type"), buttons: [
                .default(Text("Push")) { start(workoutType: "push") },
                .default(Text("Pull")) { start(workoutType: "pull") },
                .default(Text("Legs")) { start(workoutType: "legs") },
                .cancel()
            ])
        }
        .sheet(isPresented: $showFirstChoice) {
            FirstWorkoutChoiceView { choice in
                if choice == "surprise" {
                    Task { await workoutManager.getWorkoutRecommendation() }
                } else {
                    start(workoutType: choice)
                }
            }
        }
        .toolbar { Button("End") { goSummary = true } }
        .background(
            NavigationLink(isActive: $goSummary) { WorkoutSummaryView() } label: { EmptyView() }
        )
    }

    private func hint(for preset: Preset) -> String {
        switch preset { case .push: return "Chest • Shoulders • Triceps"; case .pull: return "Back • Biceps • Rear Delts"; case .legs: return "Quads • Hamstrings • Glutes • Calves" }
    }

    private func start(workoutType: String) {
        isLoading = true
        Task { await workoutManager.startWorkout(workoutType: workoutType); isLoading = false; started = true }
    }
}

#Preview {
    NavigationStack { WorkoutStartView(selectedPreset: .push).environmentObject(WorkoutManager()) }
}
