import SwiftUI

struct ResearchInfoView: View {
    let exercise: ExerciseDetail?
    let isCompound: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    Text("Why This Exercise?")
                        .font(.system(size: 22, weight: .bold))

                    if let ex = exercise {
                        Text(ex.name)
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 8) {
                            Label("High EMG Activation: \(TextSanitizer.firstSentence(from: ex.emgActivation))", systemImage: "checkmark.seal.fill")
                            Label("Hypertrophy Rating: \(ex.effectiveness.hypertrophy)", systemImage: "checkmark.seal.fill")
                            Label(isCompound ? "Compound movement - works multiple muscle groups" : "Isolation movement - focused on target muscle", systemImage: isCompound ? "bolt.fill" : "target")
                            Label("Safety: \(ex.safetyLevel.rawValue.capitalized) — \(TextSanitizer.firstSentence(from: ex.injuryRisk))", systemImage: "exclamationmark.triangle.fill")
                        }
                        .font(.system(size: 14))
                        .foregroundStyle(SAIFColors.text)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Evidence: Contreras EMG Study, Schoenfeld Meta-Analysis")
                                .foregroundStyle(SAIFColors.mutedText)
                                .font(.system(size: 12))
                        }
                    } else {
                        Text("Research details unavailable for this exercise.")
                            .foregroundStyle(SAIFColors.mutedText)
                            .font(.system(size: 14))
                    }
                }
                .padding(SAIFSpacing.xl)
            }
            .navigationTitle("Research")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

