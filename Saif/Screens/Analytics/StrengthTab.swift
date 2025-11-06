import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct StrengthTab: View {
    let data: AnalyticsData
    @State private var selectedExercise: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
            // Exercise selector
            CardView(title: "SELECT EXERCISE") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SAIFSpacing.sm) {
                        ForEach(data.strengthProgress, id: \.exerciseName) { exercise in
                            ExerciseChip(name: exercise.exerciseName, isSelected: selectedExercise == exercise.exerciseName) {
                                selectedExercise = exercise.exerciseName
                            }
                        }
                    }
                }
            }

            // Progression chart
            if let selectedExercise,
               let exercise = data.strengthProgress.first(where: { $0.exerciseName == selectedExercise }) {
                CardView(title: exercise.exerciseName.uppercased()) {
                    VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                        HStack(spacing: SAIFSpacing.xl) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Max").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                                Text("\(Int(exercise.dataPoints.last?.weight ?? 0)) lbs").font(.system(size: 20, weight: .bold)).foregroundStyle(SAIFColors.text)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Est. 1RM").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                                Text("\(Int(exercise.dataPoints.last?.estimatedOneRM ?? 0)) lbs").font(.system(size: 20, weight: .bold)).foregroundStyle(SAIFColors.primary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Progress").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                                Text(progressText(exercise)).font(.system(size: 20, weight: .bold)).foregroundStyle(.green)
                            }
                        }
                        
                        #if canImport(Charts)
                        if #available(iOS 16.0, *) {
                            Chart(exercise.dataPoints, id: \.date) { point in
                                LineMark(x: .value("Date", point.date), y: .value("Weight", point.weight))
                                    .foregroundStyle(SAIFColors.primary)
                                    .interpolationMethod(.catmullRom)
                                PointMark(x: .value("Date", point.date), y: .value("Weight", point.weight))
                                    .foregroundStyle(SAIFColors.primary)
                            }
                            .frame(height: 200)
                        } else {
                            Text("Chart requires iOS 16+").frame(height: 200)
                        }
                        #else
                        Text("Charts unavailable").frame(height: 200)
                        #endif
                    }
                }
            } else {
                EmptyStateView(icon: "chart.line.uptrend.xyaxis", title: "No Exercise Selected", message: "Select an exercise above to view progression")
            }

            // Personal Records (placeholder until implemented)
            CardView(title: "RECENT PERSONAL RECORDS") {
                Text("Coming soon once calculation is implemented.")
                    .font(.system(size: 14))
                    .foregroundStyle(SAIFColors.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private func progressText(_ exercise: ExerciseProgress) -> String {
        guard let first = exercise.dataPoints.first?.weight,
              let last = exercise.dataPoints.last?.weight,
              first > 0 else { return "+0%" }
        let increase = ((last - first) / first) * 100
        return "+\(String(format: "%.0f", increase))%"
    }
}

struct ExerciseChip: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(name)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, SAIFSpacing.md)
                .padding(.vertical, SAIFSpacing.sm)
                .background(isSelected ? SAIFColors.primary : SAIFColors.surface)
                .foregroundStyle(isSelected ? .white : SAIFColors.text)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.clear : SAIFColors.border, lineWidth: 1))
        }
    }
}

