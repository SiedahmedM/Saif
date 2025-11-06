import SwiftUI

struct ExercisePreferenceSheet: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) var dismiss

    let exerciseId: UUID?
    let exerciseName: String
    let muscleGroup: String

    @State private var selected: ExercisePreference.PreferenceLevel = .neutral
    @State private var reason: String = ""
    @State private var isLoading = false
    @State private var error: String? = nil

    private func currentLevel() -> ExercisePreference.PreferenceLevel {
        if let id = exerciseId, let pref = workoutManager.exercisePreferences.first(where: { $0.exerciseId == id }) {
            return pref.preferenceLevel
        }
        return .neutral
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                Text(exerciseName)
                    .font(.system(size: 20, weight: .semibold))
                Text(muscleGroup.capitalized)
                    .font(.system(size: 13))
                    .foregroundStyle(SAIFColors.mutedText)

                VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                    prefRow(level: .favorite, label: "❤️ Favorite (prioritize in plans)")
                    prefRow(level: .neutral, label: "👍 Neutral")
                    prefRow(level: .avoid, label: "👎 Avoid (don’t suggest)")
                }

                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                    Text("Reason (optional)").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                    TextField("e.g., shoulder pain, no equipment", text: $reason)
                        .textFieldStyle(.roundedBorder)
                }

                if let e = error { Text(e).foregroundStyle(.red).font(.system(size: 12)) }

                HStack {
                    if isLoading { ProgressView().tint(SAIFColors.primary) }
                    Spacer()
                    Button("Save") { Task { await savePreference() } }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, SAIFSpacing.md)

                Spacer()
            }
            .padding(SAIFSpacing.xl)
            .navigationTitle("Exercise Preference")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remove") { Task { await removePreference() } }
                        .disabled(exerciseId == nil)
                }
            }
            .task {
                selected = currentLevel()
            }
        }
    }

    private func prefRow(level: ExercisePreference.PreferenceLevel, label: String) -> some View {
        Button {
            selected = level
        } label: {
            HStack {
                Image(systemName: selected == level ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(SAIFColors.primary)
                Text(label).foregroundStyle(SAIFColors.text)
                Spacer()
            }
            .padding(SAIFSpacing.md)
            .background(SAIFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
        }
        .buttonStyle(.plain)
    }

    private func savePreference() async {
        isLoading = true; defer { isLoading = false }
        do {
            if let id = exerciseId {
                await workoutManager.setExercisePreference(exerciseId: id, level: selected, reason: reason.isEmpty ? nil : reason)
            } else {
                // Resolve by name+group
                if let resolved = try await SupabaseService.shared.getExerciseByName(name: exerciseName, muscleGroup: muscleGroup) {
                    await workoutManager.setExercisePreference(exerciseId: resolved.id, level: selected, reason: reason.isEmpty ? nil : reason)
                } else {
                    error = "Failed to find exercise. Please try again."
                    return
                }
            }
            dismiss()
        } catch {
            print("❌ [ExercisePreferenceSheet.savePreference] failed: \(error)")
            if (error as NSError).domain == NSURLErrorDomain {
                self.error = "Network error. Please try again."
            } else {
                self.error = "Failed to save preference. Please try again."
            }
        }
    }

    private func removePreference() async {
        guard let id = exerciseId else { dismiss(); return }
        isLoading = true; defer { isLoading = false }
        do {
            await workoutManager.removeExercisePreference(exerciseId: id)
            dismiss()
        } catch {
            print("❌ [ExercisePreferenceSheet.removePreference] failed: \(error)")
            if (error as NSError).domain == NSURLErrorDomain {
                self.error = "Network error. Please try again."
            } else {
                self.error = "Failed to remove preference. Please try again."
            }
        }
    }
}

