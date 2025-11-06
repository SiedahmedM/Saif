import SwiftUI

struct CustomWorkoutSelectionView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) var dismiss

    let presetGroups: [String]
    let presetName: String

    @State private var selectedGroups: Set<String>

    let availableGroups = [
        "chest", "back", "shoulders",
        "biceps", "triceps", "quads",
        "hamstrings", "glutes", "calves", "abs"
    ]

    init(presetGroups: [String], presetName: String) {
        self.presetGroups = presetGroups
        self.presetName = presetName
        self._selectedGroups = State(initialValue: Set(presetGroups))
    }

    var body: some View {
        NavigationStack {
            ZStack { SAIFColors.background.ignoresSafeArea() }
                .overlay(
                    VStack(spacing: SAIFSpacing.xl) {
                        Text(presetName)
                            .font(.system(size: 24, weight: .bold))

                        Text(presetGroups.isEmpty ? "Select muscle groups to train today" : "Customize your muscle group selection")
                            .foregroundStyle(SAIFColors.mutedText)

                        if !presetGroups.isEmpty {
                            VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                                Text("Default groups:")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(SAIFColors.mutedText)
                                Text(presetGroups.map { $0.capitalized }.joined(separator: ", "))
                                    .font(.system(size: 14))
                                    .foregroundStyle(SAIFColors.text)
                                Text("Tap to add or remove groups")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SAIFColors.mutedText)
                            }
                            .padding()
                            .background(SAIFColors.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                        }

                        ScrollView {
                            VStack(spacing: SAIFSpacing.md) {
                                ForEach(availableGroups, id: \.self) { group in
                                    Button {
                                        if selectedGroups.contains(group) { selectedGroups.remove(group) } else { selectedGroups.insert(group) }
                                    } label: {
                                        HStack {
                                            Image(systemName: selectedGroups.contains(group) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedGroups.contains(group) ? SAIFColors.primary : SAIFColors.mutedText)
                                            Text(group.capitalized)
                                                .foregroundStyle(SAIFColors.text)
                                            Spacer()
                                            if presetGroups.contains(group) {
                                                Text("Default")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(SAIFColors.primary)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(SAIFColors.primary.opacity(0.1))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding()
                                        .background(selectedGroups.contains(group) ? SAIFColors.primary.opacity(0.1) : SAIFColors.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: SAIFRadius.lg)
                                                .stroke(selectedGroups.contains(group) ? SAIFColors.primary : Color.clear, lineWidth: 2)
                                        )
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 0)

                        VStack(spacing: SAIFSpacing.md) {
                            if !selectedGroups.isEmpty {
                                PrimaryButton("Generate Plan for \(selectedGroups.count) Group\(selectedGroups.count == 1 ? "" : "s")") {
                                    Task {
                                        let workoutTypeName = presetName == "Custom Workout" ? "custom" : presetName.lowercased().replacingOccurrences(of: " ", with: "_")
                                        await workoutManager.startCustomWorkout(
                                            muscleGroups: Array(selectedGroups),
                                            workoutTypeName: workoutTypeName
                                        )
                                        dismiss()
                                    }
                                }
                            }

                            Button("Just Track Freely (No Plan)") {
                                Task {
                                    await workoutManager.startFreeformWorkout()
                                    dismiss()
                                }
                            }
                            .foregroundStyle(SAIFColors.mutedText)
                        }
                    }
                    .padding(SAIFSpacing.xl)
                )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

#Preview {
    CustomWorkoutSelectionView(presetGroups: ["chest","back","shoulders"], presetName: "Upper Body").environmentObject(WorkoutManager())
}
