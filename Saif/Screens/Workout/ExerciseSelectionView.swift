import SwiftUI

struct ExerciseSelectionView: View {
    let muscleGroup: String
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var goLog = false
    @State private var selectedExercise: Exercise?
    @State private var goSummary = false
    @State private var goNextGroups = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    Text(muscleGroup.capitalized).font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                    Text("Pick one to begin sets").foregroundStyle(SAIFColors.mutedText)

                    if let dbg = workoutManager.exerciseDebug {
                        CardView(title: "Debug: Supabase Query") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("workout_type: \(dbg.requestedWorkoutType)")
                                Text("muscle_group: \(dbg.requestedGroup)")
                                Text("matched: \(dbg.matchedCount)")
                                Text("all for type: \(dbg.allForTypeCount)")
                                if let e = workoutManager.error { Text(e).foregroundStyle(.red) }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(SAIFColors.mutedText)
                        }
                    }

                    if workoutManager.isLoading && workoutManager.availableExercises.isEmpty && workoutManager.exerciseRecommendations.isEmpty {
                        CardView { HStack { ProgressView(); Text("Loading exercises...").foregroundStyle(SAIFColors.mutedText) } }
                    }
                    if !workoutManager.isLoading && workoutManager.availableExercises.isEmpty {
                        CardView(title: "No exercises found") {
                            VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                Text("We couldn't find exercises for \(muscleGroup.capitalized) in this workout type.")
                                    .foregroundStyle(SAIFColors.mutedText)
                                Text("Ensure 'exercises' has rows with workout_type='\(workoutManager.currentSession?.workoutType ?? "")' and muscle_group like '\(muscleGroup)'.")
                                    .foregroundStyle(SAIFColors.mutedText)
                                Button("Retry") { Task { await workoutManager.getExerciseRecommendations(for: muscleGroup) } }
                                    .foregroundStyle(SAIFColors.primary)
                            }
                        }
                    }
                    // Show AI-ordered list when available
                    ForEach(workoutManager.exerciseRecommendations) { rec in
                        Button {
                            let ex = workoutManager.availableExercises.first { $0.name == rec.exerciseName } ?? Exercise(id: UUID(), name: rec.exerciseName, muscleGroup: muscleGroup, workoutType: workoutManager.currentSession?.workoutType ?? "", equipment: [], difficulty: .beginner, isCompound: true, description: "", formCues: [])
                            selectedExercise = ex
                            Task { await workoutManager.selectExercise(ex); goLog = true }
                        } label: {
                            let exId = workoutManager.availableExercises.first{ $0.name == rec.exerciseName }?.id
                            let isDone = exId.map { workoutManager.completedExerciseIds.contains($0) } ?? false
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(rec.exerciseName)
                                        .foregroundStyle(isDone ? SAIFColors.mutedText : SAIFColors.text)
                                        .font(.system(size: 18, weight: .semibold))
                                    HStack(spacing: 8) {
                                        Text("Priority \(rec.priority)").foregroundStyle(SAIFColors.mutedText).font(.system(size: 14))
                                        if isDone { Text("Completed").font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.primary) }
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(SAIFColors.mutedText)
                            }
                                .padding(SAIFSpacing.lg)
                                .background(SAIFColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                        }
                        .buttonStyle(.plain)
                        .disabled({ let id = workoutManager.availableExercises.first{ $0.name == rec.exerciseName }?.id; return id.map{ workoutManager.completedExerciseIds.contains($0) } ?? false }())
                    }

                    // Fallback: if AI list is empty but we have exercises, show them directly
                    if workoutManager.exerciseRecommendations.isEmpty && !workoutManager.availableExercises.isEmpty {
                        ForEach(workoutManager.availableExercises, id: \.id) { ex in
                            Button {
                                selectedExercise = ex
                                Task { await workoutManager.selectExercise(ex); goLog = true }
                            } label: {
                                let isDone = workoutManager.completedExerciseIds.contains(ex.id)
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(ex.name).foregroundStyle(isDone ? SAIFColors.mutedText : SAIFColors.text).font(.system(size: 18, weight: .semibold))
                                        HStack(spacing: 8) {
                                            Text(ex.muscleGroup.capitalized).foregroundStyle(SAIFColors.mutedText).font(.system(size: 14))
                                            if isDone { Text("Completed").font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.primary) }
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(SAIFColors.mutedText)
                                }
                                .padding(SAIFSpacing.lg)
                                .background(SAIFColors.surface)
                                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                            }
                            .buttonStyle(.plain)
                            .disabled(workoutManager.completedExerciseIds.contains(ex.id))
                        }
                    }

                    if !workoutManager.availableExercises.isEmpty {
                        PrimaryButton("Choose Another Muscle Group", variant: .outline) { goNextGroups = true }
                    }

                    NavigationLink(isActive: $goLog) {
                        if let ex = selectedExercise { ExerciseLoggingView(exercise: ex).environmentObject(workoutManager) } else { EmptyView() }
                    } label: { EmptyView() }
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("End") { goSummary = true } }
        .background(
            Group {
                NavigationLink(isActive: $goSummary) { WorkoutSummaryView() } label: { EmptyView() }
                NavigationLink(isActive: $goNextGroups) { NextSuggestionsView(currentGroupToExclude: muscleGroup) } label: { EmptyView() }
            }
        )
        .task {
            if workoutManager.availableExercises.isEmpty || workoutManager.exerciseDebug == nil {
                await workoutManager.getExerciseRecommendations(for: muscleGroup)
            }
        }
    }
}

#Preview { NavigationStack { ExerciseSelectionView(muscleGroup: "chest").environmentObject(WorkoutManager()) } }
