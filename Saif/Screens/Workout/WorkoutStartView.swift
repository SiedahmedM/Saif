import SwiftUI

struct WorkoutStartView: View {
    let selectedPreset: Preset?
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var navigationPath = NavigationPath()
    @State private var showAlternatives = false
    @State private var showFirstChoice = false
    @State private var showPlanSheet = false
    @State private var showCustomWorkout = false
    @State private var presetMuscleGroups: [String] = []
    @State private var presetWorkoutName: String = ""

    var body: some View {
        NavigationStack(path: $navigationPath) {
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
                .default(Text("Push (Chest, Shoulders, Triceps)")) {
                    start(workoutType: "push")
                },
                .default(Text("Pull (Back, Biceps)")) {
                    start(workoutType: "pull")
                },
                .default(Text("Legs (Quads, Hamstrings, Glutes)")) {
                    start(workoutType: "legs")
                },
                .default(Text("Upper Body (Customize...)")) {
                    showCustomWorkout(presetGroups: ["chest", "back", "shoulders"], presetName: "Upper Body")
                },
                .default(Text("Lower Body (Customize...)")) {
                    showCustomWorkout(presetGroups: ["quads", "hamstrings", "glutes"], presetName: "Lower Body")
                },
                .default(Text("Full Body (Customize...)")) {
                    showCustomWorkout(presetGroups: ["chest", "back", "shoulders", "quads", "hamstrings"], presetName: "Full Body")
                },
                .default(Text("Build From Scratch...")) {
                    showCustomWorkout(presetGroups: [], presetName: "Custom Workout")
                },
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
        // Remove legacy End toolbar; end is handled via plan's Current tab summary
        // Plan now navigates as its own page (no sheet)
        .sheet(isPresented: $showCustomWorkout, onDismiss: {
            if workoutManager.currentPlan != nil {
                navigationPath.append("plan")
            } else if workoutManager.currentSession != nil { // freeform started
                navigationPath.append("exerciseSelection")
            }
        }) {
            CustomWorkoutSelectionView(
                presetGroups: presetMuscleGroups,
                presetName: presetWorkoutName
            ).environmentObject(workoutManager)
        }
        .onChange(of: workoutManager.currentExercise?.id) { _ in
            if workoutManager.currentExercise != nil { navigationPath.append("exerciseLogging") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saifWorkoutCompleted)) { _ in
            if navigationPath.count > 0 { navigationPath.removeLast(navigationPath.count) }
            dismiss()
        }
        .navigationDestination(for: String.self) { dest in
            switch dest {
            case "exerciseSelection":
                MuscleGroupSelectionView().environmentObject(workoutManager)
            case "exerciseLogging":
                if let ex = workoutManager.currentExercise { ExerciseLoggingView(exercise: ex).environmentObject(workoutManager) } else { EmptyView() }
            case "plan":
                if let plan = workoutManager.currentPlan { SessionPlanView(plan: plan).environmentObject(workoutManager) } else { EmptyView() }
            default:
                EmptyView()
            }
        }
        }
    }

    private func showCustomWorkout(presetGroups: [String], presetName: String) {
        presetMuscleGroups = presetGroups
        presetWorkoutName = presetName
        showCustomWorkout = true
    }

    private func hint(for preset: Preset) -> String {
        switch preset { case .push: return "Chest • Shoulders • Triceps"; case .pull: return "Back • Biceps • Rear Delts"; case .legs: return "Quads • Hamstrings • Glutes • Calves" }
    }

    private func start(workoutType: String) {
        isLoading = true
        Task {
            await workoutManager.startWorkout(workoutType: workoutType)
            // Ensure UI updates on main thread
            await MainActor.run {
                isLoading = false
                if let plan = workoutManager.currentPlan {
                    print("🎯 SHOWING PLAN SHEET - Plan has \(plan.exercises.count) exercises")
                    navigationPath.append("plan")
                } else {
                    print("❌ NO PLAN FOUND - Navigating directly")
                    navigationPath.append("exerciseSelection")
                }
            }
        }
    }
}

#Preview {
    NavigationStack { WorkoutStartView(selectedPreset: .push).environmentObject(WorkoutManager()) }
}
