import SwiftUI

struct FirstWorkoutChoiceView: View {
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: SAIFSpacing.lg) {
            Text("🎉 First workout! Which feels freshest today?")
                .font(.system(size: 18, weight: .semibold))
                .multilineTextAlignment(.center)

            choice(title: "Upper Body (Push)", subtitle: "Chest, Shoulders, Triceps") { choose("push") }
            choice(title: "Upper Body (Pull)", subtitle: "Back, Biceps, Rear Delts") { choose("pull") }
            choice(title: "Lower Body (Legs)", subtitle: "Quads, Hamstrings, Glutes") { choose("legs") }
            choice(title: "Surprise Me", subtitle: "Let AI decide") { choose("surprise") }
        }
        .padding(SAIFSpacing.xl)
        .background(SAIFColors.background)
    }

    @ViewBuilder private func choice(title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(SAIFColors.text)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(SAIFSpacing.lg)
            .background(SAIFColors.surface)
            .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        }
        .buttonStyle(.plain)
    }

    private func choose(_ type: String) {
        onChoose(type)
        dismiss()
    }
}

#Preview { FirstWorkoutChoiceView(onChoose: { _ in }) }

