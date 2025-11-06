import SwiftUI

struct PostWorkoutSummaryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    var initialNotes: String? = nil
    @State private var summaryData: WorkoutManager.WorkoutSummaryData?
    @State private var isFinalizing = false
    @State private var showFinalizeError = false
    @State private var finalizeMessage: String = ""

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: SAIFSpacing.xl) {
                    header

                    if let data = summaryData {
                        CardView(title: "PERFORMANCE") {
                            VStack(spacing: SAIFSpacing.lg) {
                                ComparisonRow(label: "Exercises", planned: data.plannedExercises, actual: data.actualExercises)
                                ComparisonRow(label: "Total Sets", planned: data.plannedSets, actual: data.actualSets)
                                ComparisonRow(label: "Duration", planned: data.plannedDuration, actual: data.actualDuration, unit: "min")
                                if data.overachievement > 0.05 {
                                    HStack {
                                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                                        Text("+\(Int(data.overachievement * 100))% volume")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.green)
                                        Spacer()
                                    }
                                }
                            }
                        }

                        if !data.topExercises.isEmpty {
                            CardView(title: "TOP PERFORMANCES") {
                                VStack(spacing: SAIFSpacing.md) {
                                    ForEach(data.topExercises) { highlight in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(highlight.exerciseName).font(.system(size: 16, weight: .semibold))
                                                Text(highlight.achievement).font(.system(size: 14)).foregroundStyle(SAIFColors.accent)
                                            }
                                            Spacer()
                                            Text(highlight.metric).font(.system(size: 16, weight: .bold)).foregroundStyle(SAIFColors.primary)
                                        }
                                        .padding()
                                        .background(SAIFColors.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                                    }
                                }
                            }
                        }

                        if !data.insights.isEmpty {
                            CardView(title: "INSIGHTS") {
                                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                    ForEach(data.insights, id: \.self) { insight in
                                        HStack(alignment: .top, spacing: SAIFSpacing.sm) {
                                            Text("•")
                                            Text(insight).font(.system(size: 15))
                                        }
                                    }
                                }
                            }
                        }

                        CardView {
                            VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                Label("Next Workout", systemImage: "calendar").font(.system(size: 14, weight: .semibold)).foregroundStyle(SAIFColors.mutedText)
                                Text(data.nextWorkoutSuggestion).font(.system(size: 16))
                            }
                        }
                    }

                    // Actions
                    VStack(spacing: SAIFSpacing.md) {
                        PrimaryButton(isFinalizing ? "Saving..." : "Done") { finalizeWorkout() }
                        .disabled(isFinalizing)
                    }
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("Workout Complete").navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(true)
        // NavigationLink fallback not needed when presented as a sheet.
        .task { summaryData = await workoutManager.generateWorkoutSummary() }
        .alert("Save Failed", isPresented: $showFinalizeError) {
            Button("Retry") {
                finalizeWorkout()
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text(finalizeMessage) }
    }

    private var header: some View {
        ZStack(alignment: .top) {
            VStack(spacing: SAIFSpacing.sm) {
                Text("✅").font(.system(size: 48))
                Text("All done! Great work today.")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(SAIFColors.text)
                Text("Here’s how you did:")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                if let data = summaryData {
                    Text("\(data.actualExercises) exercises • \(data.actualSets) sets • \(data.actualDuration) min")
                        .foregroundStyle(SAIFColors.mutedText)
                }
            }
        }
    }

    private func finalizeWorkout() {
        guard !isFinalizing else { return }
        isFinalizing = true
        Task {
            await workoutManager.completeWorkout(notes: initialNotes)
            await MainActor.run {
                isFinalizing = false
                if workoutManager.currentSession == nil {
                    NotificationCenter.default.post(name: .saifWorkoutCompleted, object: nil)
                    // Give listeners a beat to react
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dismiss()
                    }
                } else {
                    finalizeMessage = "Your workout couldn’t be saved. Please try again."
                    showFinalizeError = true
                }
            }
        }
    }
}

private struct ComparisonRow: View {
    let label: String
    let planned: Int
    let actual: Int
    var unit: String = ""
    var body: some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
            Spacer()
            Text("\(planned)\(unit)").font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
            Image(systemName: "arrow.right").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
            Text("\(actual)\(unit)").font(.system(size: 16, weight: .bold)).foregroundStyle(actual >= planned ? .green : SAIFColors.text)
        }
    }
}

#Preview {
    NavigationStack { PostWorkoutSummaryView().environmentObject(WorkoutManager()) }
}
