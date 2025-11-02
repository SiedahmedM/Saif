import SwiftUI

struct MuscleMapView: View {
    let preset: Preset

    private var highlighted: Set<String> {
        switch preset {
        case .push: return ["chest", "shoulders", "triceps"]
        case .pull: return ["back", "biceps", "rearDelts"]
        case .legs: return ["quads", "hamstrings", "glutes", "calves"]
        }
    }

    private func active(_ key: String) -> Color {
        highlighted.contains(key) ? SAIFColors.primary : SAIFColors.idle
    }

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            VStack(alignment: .center, spacing: SAIFSpacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Muscle Map").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
                    Text("Preset: \(preset.rawValue)").font(.system(size: 16)).foregroundStyle(SAIFColors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(spacing: SAIFSpacing.md) {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color(hex: "#E7ECF5"))
                        .frame(width: 56, height: 56)

                    HStack(spacing: SAIFSpacing.lg) {
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("shoulders")).frame(width: 56, height: 24)
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("shoulders")).frame(width: 56, height: 24)
                    }

                    RoundedRectangle(cornerRadius: SAIFRadius.md)
                        .fill(active("chest"))
                        .frame(width: 160, height: 40)

                    HStack(spacing: SAIFSpacing.lg) {
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("biceps")).frame(width: 56, height: 64)
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("triceps")).frame(width: 56, height: 64)
                    }

                    RoundedRectangle(cornerRadius: SAIFRadius.md)
                        .fill(highlighted.contains("abs") ? SAIFColors.primary : Color(hex: "#E7ECF5"))
                        .frame(width: 100, height: 48)

                    HStack(spacing: SAIFSpacing.lg) {
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("quads")).frame(width: 64, height: 80)
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("quads")).frame(width: 64, height: 80)
                    }

                    HStack(spacing: SAIFSpacing.lg) {
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("calves")).frame(width: 48, height: 56)
                        RoundedRectangle(cornerRadius: SAIFRadius.md).fill(active("calves")).frame(width: 48, height: 56)
                    }
                }
                .padding(.vertical, SAIFSpacing.lg)
                .padding(.horizontal, SAIFSpacing.xl)
                .frame(maxWidth: .infinity)
                .background(SAIFColors.surface)
                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.xl).stroke(SAIFColors.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl, style: .continuous))
                .cardShadow()

                HStack(spacing: SAIFSpacing.xl) {
                    LegendDot(color: SAIFColors.primary, label: "Trained")
                    LegendDot(color: SAIFColors.idle, label: "Idle")
                }
                .padding(.top, SAIFSpacing.lg)

                Spacer()
            }
            .padding(SAIFSpacing.xl)
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 12, height: 12)
            Text(label).foregroundStyle(SAIFColors.mutedText).font(.system(size: 14))
        }
    }
}

#Preview {
    NavigationStack { MuscleMapView(preset: .push) }
}

