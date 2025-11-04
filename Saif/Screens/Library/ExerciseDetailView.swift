import SwiftUI

struct ExerciseDetailView: View {
    let exercise: ExerciseDetail

    var body: some View {
        ZStack { SAIFColors.background.ignoresSafeArea() }
            .overlay(
                ScrollView {
                    VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                        // Header badges
                        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                            HStack {
                                Text(exercise.isCompound ? "💪 COMPOUND EXERCISE" : "🎯 ISOLATION EXERCISE")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(SAIFColors.primary)
                                Spacer()
                                SafetyBadge(level: exercise.safetyLevel)
                            }
                            Text("🏋️ Equipment: \(exercise.equipment)")
                                .font(.system(size: 14))
                                .foregroundStyle(SAIFColors.mutedText)
                        }

                        SectionCard(title: "WHY THIS WORKS") {
                            Text(whyItWorks)
                                .font(.system(size: 15))
                                .foregroundStyle(SAIFColors.text)
                        }

                        SectionCard(title: "EFFECTIVENESS") {
                            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                                EffectivenessRow(label: "Hypertrophy", rating: exercise.effectiveness.hypertrophyScore, description: exercise.effectiveness.hypertrophy)
                                EffectivenessRow(label: "Strength", rating: exercise.effectiveness.strengthScore, description: exercise.effectiveness.strength)
                                EffectivenessRow(label: "Power", rating: exercise.effectiveness.powerScore, description: exercise.effectiveness.power)
                            }
                        }

                        if !exercise.prerequisites.isEmpty {
                            SectionCard(title: "PREREQUISITES") {
                                Text(exercise.prerequisites)
                                    .font(.system(size: 15))
                                    .foregroundStyle(SAIFColors.text)
                            }
                        }

                        SectionCard(title: "PROGRESSION PATH") {
                            Text(progressionSummary)
                                .font(.system(size: 15))
                                .foregroundStyle(SAIFColors.text)
                        }

                        SectionCard(title: "SAFETY & INJURY RISK") {
                            Text(exercise.injuryRisk)
                                .font(.system(size: 15))
                                .foregroundStyle(SAIFColors.text)
                        }
                    }
                    .padding(SAIFSpacing.xl)
                }
            )
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
    }

    private var whyItWorks: String {
        exercise.emgActivation.components(separatedBy: ":contentReference").first ?? exercise.emgActivation
    }

    private var progressionSummary: String {
        exercise.progressionPath.components(separatedBy: ". ").prefix(5).joined(separator: ". ")
    }
}

// Shared section UI
struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
            Text(title)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(SAIFColors.mutedText)
            content
        }
        .padding(SAIFSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SAIFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
    }
}

struct EffectivenessRow: View {
    let label: String
    let rating: Int
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 14, weight: .medium))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(0..<rating, id: \.self) { _ in
                        Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(SAIFColors.primary)
                    }
                    ForEach(rating..<4, id: \.self) { _ in
                        Image(systemName: "star").font(.system(size: 12)).foregroundStyle(SAIFColors.border)
                    }
                }
            }
            Text(description).font(.system(size: 13)).foregroundStyle(SAIFColors.mutedText)
        }
    }
}

// Local SafetyBadge for detail screen
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
        case .medium, .high: return "exclamationmark.triangle.fill"
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
