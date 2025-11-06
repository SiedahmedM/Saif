import SwiftUI

struct WorkoutSummaryView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var saving = false
    @State private var goHome = false
    @State private var goPostSummary = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    Text("Workout Summary").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)

                    if let session = workoutManager.currentSession {
                        CardView(title: "Details") {
                            VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                Text("Type: \(session.workoutType.capitalized)")
                                Text("Started: \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                            }
                        }
                    }

                    CardView(title: "Completed Sets") {
                        ForEach(grouped, id: \.exerciseId) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.name).font(.system(size: 16, weight: .semibold))
                                Text(group.summary).foregroundStyle(SAIFColors.mutedText)
                            }
                            .padding(.vertical, 6)
                        }
                    }

                    CardView(title: "Notes (optional)") { TextEditor(text: $notes).frame(height: 100).padding(SAIFSpacing.sm).background(SAIFColors.background).clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md)) }

                    if saving { HStack { ProgressView(); Text("Saving...") } }
                    else { PrimaryButton("Save & Finish") { save() } }
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF").navigationBarTitleDisplayMode(.inline)
        .background(
            Group {
                NavigationLink(isActive: $goHome) { HomeRootView() } label: { EmptyView() }
                NavigationLink(isActive: $goPostSummary) { PostWorkoutSummaryView(initialNotes: notes).environmentObject(workoutManager) } label: { EmptyView() }
            }
        )
    }

    private var grouped: [(exerciseId: UUID, name: String, summary: String)] {
        let groups = Dictionary(grouping: workoutManager.completedSets, by: { $0.exerciseId })
        return groups.map { (id, sets) in
            let summary = sets.sorted { $0.setNumber < $1.setNumber }.map { "\($0.reps)x@\(Int($0.weight))" }.joined(separator: ", ")
            return (id, "Exercise", summary)
        }
    }

    private func save() {
        // Navigate to the richer summary; do NOT complete the workout yet,
        // so summary can use current session + plan state. Completion happens on Done.
        goPostSummary = true
    }
}

#Preview { NavigationStack { WorkoutSummaryView().environmentObject(WorkoutManager()) } }
