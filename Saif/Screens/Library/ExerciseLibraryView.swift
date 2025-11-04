import SwiftUI

struct ExerciseLibraryView: View {
    @State private var selectedMuscleGroup: String? = nil
    @State private var searchText: String = ""

    private var allMuscleGroups: [String] {
        ["chest", "back", "shoulders", "quads", "hamstrings", "glutes", "biceps", "triceps", "calves", "core"]
    }

    private var groupedExercises: [(group: String, exercises: [ExerciseDetail])] {
        allMuscleGroups.compactMap { group in
            let exercises = TrainingKnowledgeService.shared.getExercises(for: group)
            guard !exercises.isEmpty else { return nil }
            let filtered = searchText.isEmpty ? exercises : exercises.filter { $0.name.lowercased().contains(searchText.lowercased()) }
            return (group, filtered)
        }.filter { !$0.exercises.isEmpty }
    }

    private var filteredGroups: [(group: String, exercises: [ExerciseDetail])] {
        if let selected = selectedMuscleGroup {
            return groupedExercises.filter { $0.group == selected }
        }
        return groupedExercises
    }

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea() }
            .overlay(
                ScrollView {
                    VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(SAIFColors.mutedText)
                            TextField("Search exercises...", text: $searchText).textFieldStyle(.plain)
                        }
                        .padding(SAIFSpacing.md)
                        .background(SAIFColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))

                        // Filter chips (only when not searching)
                        if searchText.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: SAIFSpacing.sm) {
                                    FilterChip(title: "All", isSelected: selectedMuscleGroup == nil) { selectedMuscleGroup = nil }
                                    ForEach(allMuscleGroups, id: \.self) { group in
                                        FilterChip(title: group.capitalized, isSelected: selectedMuscleGroup == group) {
                                            selectedMuscleGroup = (selectedMuscleGroup == group) ? nil : group
                                        }
                                    }
                                }
                            }
                        }

                        // Grouped results
                        ForEach(filteredGroups, id: \.group) { item in
                            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                                HStack {
                                    Text(item.group.uppercased())
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(SAIFColors.mutedText)
                                    Text("(\(item.exercises.count) exercises)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(SAIFColors.mutedText)
                                }
                                .padding(.top, SAIFSpacing.md)

                                ForEach(item.exercises) { exercise in
                                    NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                                        ExerciseLibraryCard(exercise: exercise)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(SAIFSpacing.xl)
                }
            )
            .navigationTitle("Exercise Library")
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Components
private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, SAIFSpacing.md)
                .padding(.vertical, SAIFSpacing.sm)
                .background(isSelected ? SAIFColors.primary : SAIFColors.surface)
                .foregroundStyle(isSelected ? .white : SAIFColors.text)
                .clipShape(Capsule())
        }
    }
}

private struct ExerciseLibraryCard: View {
    let exercise: ExerciseDetail

    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SAIFColors.text)
                    HStack(spacing: 8) {
                        Text(exercise.isCompound ? "Compound" : "Isolation")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(SAIFColors.primary.opacity(0.1))
                            .foregroundStyle(SAIFColors.primary)
                            .clipShape(Capsule())
                        Text(equipmentSummary)
                            .font(.system(size: 12))
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                }
                Spacer()
                SafetyBadge(level: exercise.safetyLevel)
            }

            // Effectiveness
            HStack(spacing: SAIFSpacing.md) {
                EffectivenessIndicator(label: "Hypertrophy", rating: exercise.effectiveness.hypertrophyScore)
                EffectivenessIndicator(label: "Strength", rating: exercise.effectiveness.strengthScore)
            }

            // EMG snippet
            Text(emgPreview)
                .font(.system(size: 12))
                .foregroundStyle(SAIFColors.mutedText)
                .lineLimit(1)
        }
        .padding(SAIFSpacing.md)
        .background(SAIFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
    }

    private var equipmentSummary: String {
        let e = exercise.equipment.lowercased()
        if e.contains("barbell") { return "Barbell" }
        if e.contains("dumbbell") { return "Dumbbells" }
        if e.contains("machine") { return "Machine" }
        if e.contains("cable") { return "Cable" }
        if e.contains("bodyweight") { return "Bodyweight" }
        return "Various"
    }

    private var emgPreview: String {
        exercise.emgActivation.components(separatedBy: ".").first ?? "High muscle activation"
    }
}

private struct SafetyBadge: View {
    let level: SafetyLevel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text("Injury Risk: \(level.rawValue)")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private var icon: String {
        switch level {
        case .low: return "checkmark.circle.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.triangle.fill"
        }
    }
    private var color: Color {
        switch level {
        case .low: return .green
        case .medium: return .orange
        case .high: return .red
        }
    }
}

private struct EffectivenessIndicator: View {
    let label: String
    let rating: Int // 1-4

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(SAIFColors.mutedText)
            HStack(spacing: 2) {
                ForEach(0..<rating, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(SAIFColors.primary)
                }
                ForEach(rating..<4, id: \.self) { _ in
                    Image(systemName: "star")
                        .font(.system(size: 10))
                        .foregroundStyle(SAIFColors.border)
                }
            }
        }
    }
}
