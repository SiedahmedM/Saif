import SwiftUI

struct MuscleGroupSelectionView: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var selected: String?
    @State private var goNext = false
    @State private var goSummary = false

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                    VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                        Text("Choose Muscle Group").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                        if let session = workoutManager.currentSession {
                            Text(session.workoutType.capitalized + " Workout").foregroundStyle(SAIFColors.mutedText)
                        }
                    }

                    if workoutManager.muscleGroupPriority.isEmpty {
                        CardView {
                            VStack(spacing: SAIFSpacing.md) {
                                HStack { ProgressView(); Text("Planning your workout...").foregroundStyle(SAIFColors.mutedText) }
                                Button("Retry") { Task { await workoutManager.refreshMusclePriority() } }
                                    .foregroundStyle(SAIFColors.primary)
                            }
                        }
                    } else {
                        CardView(title: "Recommended Order") {
                            HStack(spacing: 8) {
                                ForEach(Array(workoutManager.muscleGroupPriority.enumerated()), id: \.offset) { idx, g in
                                    Text("\(idx+1). \(displayName(for: g))").padding(.horizontal, 12).padding(.vertical, 8).background(SAIFColors.primary.opacity(0.1)).clipShape(Capsule())
                                }
                            }
                        }

                        CardView(title: "Select Muscle Group") {
                            VStack(spacing: SAIFSpacing.md) {
                                ForEach(workoutManager.muscleGroupPriority, id: \.self) { g in
                                    Button(action: { selected = g }) {
                                        HStack { Text(displayName(for: g)).foregroundStyle(SAIFColors.text); Spacer(); if selected == g { Image(systemName: "checkmark.circle.fill").foregroundStyle(SAIFColors.primary) } }
                                            .padding(SAIFSpacing.lg)
                                            .background(selected == g ? SAIFColors.primary.opacity(0.08) : SAIFColors.surface)
                                            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(selected == g ? SAIFColors.primary : SAIFColors.border, lineWidth: selected == g ? 2 : 1))
                                            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    PrimaryButton("Continue") { goNext = selected != nil }

                    NavigationLink(destination: GroupPlanView(muscleGroup: selected ?? "").environmentObject(workoutManager), isActive: $goNext) { EmptyView() }
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("End") { goSummary = true } }
        .background(
            NavigationLink(isActive: $goSummary) { WorkoutSummaryView() } label: { EmptyView() }
        )
    }

    private func loadExercises() {
        guard let group = selected else { return }
        Task { await workoutManager.getExerciseRecommendations(for: group); goNext = true }
    }

    private func displayName(for key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview { NavigationStack { MuscleGroupSelectionView().environmentObject(WorkoutManager()) } }
