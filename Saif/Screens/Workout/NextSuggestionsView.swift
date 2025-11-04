import SwiftUI

struct NextSuggestionsView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    var currentGroupToExclude: String? = nil
    @State private var navigateToExercises = false
    @State private var selectedGroup: String?
    @State private var goSummary = false

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                Text("What’s next?").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                Text("Choose your next focus or end workout.").foregroundStyle(SAIFColors.mutedText)

                if let session = workoutManager.currentSession {
                    CardView(title: "Today's Workout", subtitle: session.workoutType.capitalized) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(suggestions().enumerated()), id: \.offset) { _, group in
                                Button(action: { selectedGroup = group; navigateToExercises = true }) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(displayName(for: group))
                                                .font(.system(size: 18, weight: isRecommended(group) ? .bold : .semibold))
                                                .foregroundStyle(isRecommended(group) ? SAIFColors.primary : SAIFColors.text)
                                            if isRecommended(group) { Text("Recommended").font(.system(size: 12)).foregroundStyle(SAIFColors.primary) }
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
                            }
                        }
                    }
                }

                PrimaryButton("End Workout", variant: .accent) { goSummary = true }
                Spacer()

                NavigationLink(isActive: $navigateToExercises) {
                    if let g = selectedGroup { ExerciseSelectionView(muscleGroup: g) } else { EmptyView() }
                } label: { EmptyView() }

                NavigationLink(isActive: $goSummary) { WorkoutSummaryView() } label: { EmptyView() }
            }
            .padding(SAIFSpacing.xl)
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func suggestions() -> [String] {
        guard let type = workoutManager.currentSession?.workoutType else { return [] }
        let priority = workoutManager.muscleGroupPriority
        let completed = workoutManager.completedGroups
        let exclude = currentGroupToExclude?.lowercased()
        // Recommended first: first in priority not yet completed
        var result: [String] = []
        if let top = priority.first(where: { g in
            let k = g.lowercased(); return !completed.contains(k) && k != exclude
        }) { result.append(top) }
        // Add next two options
        let others = priority.filter { g in let k = g.lowercased(); return !result.contains(g) && !completed.contains(k) && k != exclude }
        result.append(contentsOf: others.prefix(2))
        // If still less than 3, fill from allowed groups
        let allowed = workoutManager.allowedGroups(for: type)
        let fillers = allowed.filter { g in let k = g.lowercased(); return !result.contains(g) && !completed.contains(k) && k != exclude }
        result.append(contentsOf: fillers.prefix(max(0, 3 - result.count)))
        return result
    }

    private func isRecommended(_ group: String) -> Bool { group == suggestions().first }
    private func displayName(for key: String) -> String { key.replacingOccurrences(of: "_", with: " ").capitalized }
}
