import SwiftUI

struct WorkoutCheckinView: View {
    let goal: Goal

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    Text("Workout Check‑in")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(SAIFColors.text)
                    Text("Goal: \(goal.rawValue)")
                        .font(.system(size: 16))
                        .foregroundStyle(SAIFColors.mutedText)

                    WorkoutCard(title: "Push Day", subtitle: "Chest • Shoulders • Triceps", preset: .push)
                    WorkoutCard(title: "Pull Day", subtitle: "Back • Biceps • Rear Delts", preset: .pull)
                    WorkoutCard(title: "Legs", subtitle: "Quads • Hamstrings • Glutes • Calves", preset: .legs)
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Preset.self) { p in
            MuscleMapView(preset: p)
        }
    }
}

private struct WorkoutCard: View {
    let title: String
    let subtitle: String
    let preset: Preset

    var badgeColor: Color {
        switch preset {
        case .push: return SAIFColors.primary
        case .pull: return Color(hex: "#6B7C93")
        case .legs: return SAIFColors.accent
        }
    }

    var body: some View {
        NavigationLink(value: preset) {
            CardView {
                HStack { Spacer()
                    Text(presetLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(badgeColor, in: Capsule())
                }
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(SAIFColors.text)
                Text(subtitle).font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
            }
        }
        .buttonStyle(.plain)
    }

    private var presetLabel: String {
        switch preset {
        case .push: return "PUSH"
        case .pull: return "PULL"
        case .legs: return "LEGS"
        }
    }
}

#Preview {
    NavigationStack { WorkoutCheckinView(goal: .bulk) }
}

