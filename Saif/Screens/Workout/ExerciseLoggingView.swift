import SwiftUI

struct ExerciseLoggingView: View {
    let exercise: Exercise
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) private var dismiss

    @State private var setNumber = 1
    @State private var reps = ""
    @State private var weight = ""
    @State private var goSummary = false
    @State private var nextInGroup = false
    @State private var goSuggestions = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                Text(exercise.name).font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                Text(exercise.muscleGroup.capitalized).foregroundStyle(SAIFColors.mutedText)

                if let rec = workoutManager.setRepRecommendation {
                    CardView(title: "AI Recommendation") {
                        HStack(spacing: SAIFSpacing.lg) {
                            Text("Reps: \(rec.reps)")
                            Text("Weight: \(Int(rec.weight))lbs")
                            Text("Rest: \(rec.restSeconds)s")
                        }.foregroundStyle(SAIFColors.text)
                    }
                }

                CardView(title: "Log Set #\(setNumber)") {
                    VStack(spacing: SAIFSpacing.md) {
                        HStack { Text("Reps"); Spacer(); TextField("0", text: $reps).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                        HStack { Text("Weight (lb)"); Spacer(); TextField("0", text: $weight).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        PrimaryButton("Add Set") { addSet() }
                    }
                }

                PrimaryButton("Finish Exercise", variant: .accent) { finishExercise() }
                Spacer()
                NavigationLink(destination: ExerciseSelectionView(muscleGroup: exercise.muscleGroup).environmentObject(workoutManager), isActive: $nextInGroup) { EmptyView() }
                NavigationLink(destination: NextSuggestionsView().environmentObject(workoutManager), isActive: $goSuggestions) { EmptyView() }
            }.padding(SAIFSpacing.xl)
        }
        .navigationTitle("SAIF").navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("End") { goSummary = true } }
    }

    private func addSet() {
        let repsVal = Int(reps) ?? 0
        let weightVal = Double(weight) ?? 0
        let sessionId = workoutManager.currentSession?.id ?? UUID()
        let set = ExerciseSet(id: UUID(), sessionId: sessionId, exerciseId: exercise.id, setNumber: setNumber, reps: repsVal, weight: weightVal, rpe: nil, restSeconds: nil, completedAt: Date())
        workoutManager.completedSets.append(set)
        // Persist to Supabase
        Task { _ = try? await SupabaseService.shared.logExerciseSet(set) }
        setNumber += 1
        reps = ""; weight = ""
    }

    private func finishExercise() {
        // mark exercise completed
        workoutManager.markExerciseCompleted(exerciseId: exercise.id, group: exercise.muscleGroup)
        let key = exercise.muscleGroup.lowercased()
        let completed = workoutManager.groupCompletedExercises[key] ?? 0
        let target = workoutManager.groupTargets[key] ?? 0
        if target > 0 && completed < target {
            // do next exercise in same group
            nextInGroup = true
        } else {
            goSuggestions = true
        }
    }
}

#Preview { NavigationStack { ExerciseLoggingView(exercise: Exercise(id: UUID(), name: "Bench Press", muscleGroup: "chest", workoutType: "push", equipment: [], difficulty: .beginner, isCompound: true, description: "", formCues: [])).environmentObject(WorkoutManager()) } }
