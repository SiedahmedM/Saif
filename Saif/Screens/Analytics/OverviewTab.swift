import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var authManager: AuthManager
    let data: AnalyticsData
    @State private var selectedRange: OverviewRange = .month
    @State private var rangeStats: OverviewStats? = nil
    @State private var loadingRange = false
    @State private var splitRange: OverviewRange = .month
    @State private var splitData: [SplitBalanceData]? = nil
    @State private var showSplitTuning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
            // This Month Summary (with range selector)
            CardView(title: "THIS MONTH") {
                VStack(spacing: SAIFSpacing.md) {
                    HStack { Spacer()
                        Menu {
                            Button("Past Week") { setRange(.week) }
                            Button("Past Month") { setRange(.month) }
                            Button("Past Year") { setRange(.year) }
                        } label: {
                            HStack(spacing: 6) {
                                Text(rangeTitle).font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down").font(.system(size: 12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SAIFColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    if loadingRange && rangeStats == nil { ProgressView() }
                    let stats = rangeStats ?? data.overview
                    StatRow(icon: "figure.strengthtraining.traditional", label: "Workouts completed", value: "\(stats.totalWorkouts)")
                    StatRow(icon: "chart.bar.fill", label: "Total sets", value: "\(stats.totalSets)")
                    if stats.totalWorkouts > 8 {
                        StatRow(icon: "trophy.fill", label: "New personal records", value: "\(stats.personalRecordsThisMonth)", valueColor: .orange)
                    }
                    StatRow(icon: "arrow.up.right", label: "Avg strength increase", value: "+\(String(format: "%.1f", stats.averageStrengthIncrease))%", valueColor: .green)
                }
            }

            // Training Split Balance (range selectable)
            CardView(title: "TRAINING SPLIT BALANCE") {
                VStack(spacing: SAIFSpacing.md) {
                    HStack {
                        // Tuning button
                        Button {
                            showSplitTuning = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.primary)
                        }
                        Spacer()
                        Menu {
                            Button("Past Week") { splitRange = .week; Task { await refreshSplit() } }
                            Button("Past Month") { splitRange = .month; Task { await refreshSplit() } }
                        } label: {
                            HStack(spacing: 6) {
                                Text(splitRangeTitle).font(.system(size: 12, weight: .medium))
                                Image(systemName: "chevron.down").font(.system(size: 12))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(SAIFColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    let items = splitData ?? data.splitBalance
                    if items.isEmpty {
                        EmptyStateView(icon: "diagram.3", title: "No recent sessions", message: "Complete some workouts to see split balance")
                    } else {
                        ForEach(items) { split in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(split.category).font(.system(size: 14, weight: .medium)).foregroundStyle(SAIFColors.text)
                                    Spacer()
                                    Text("\(split.workoutCount) / \(split.recommendedCount) workouts")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(split.isLow ? .orange : .green)
                                }
                                GeometryReader { geometry in
                                    let width = geometry.size.width
                                    let rec = max(split.recommendedCount, 1)
                                    let currentRatio = min(Double(split.workoutCount) / Double(rec), 1.0)
                                    ZStack(alignment: .leading) {
                                        // Recommended (target) bar
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(SAIFColors.border)
                                            .frame(width: width, height: 10)
                                        // Current bar overlay
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(split.isLow ? Color.orange : Color.green)
                                            .frame(width: width * currentRatio, height: 10)
                                    }
                                }
                                .frame(height: 10)
                            }
                        }
                        if let low = items.first(where: { $0.isLow }) {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle.fill").foregroundStyle(.orange)
                                Text("\(low.category) workouts are below recommended frequency").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                            }
                            .padding(.top, SAIFSpacing.sm)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text("Balanced training across all muscle groups").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                            }
                            .padding(.top, SAIFSpacing.sm)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSplitTuning) {
                SplitTuningSheet(onSave: { push, pull, legs in
                    let d = UserDefaults.standard
                    d.set(push, forKey: "splitTune_push")
                    d.set(pull, forKey: "splitTune_pull")
                    d.set(legs, forKey: "splitTune_legs")
                    Task { await refreshSplit() }
                })
            }

            // Volume by Muscle Group
            CardView(title: "VOLUME BY MUSCLE GROUP (This Week)") {
                if data.volumeByMuscle.isEmpty {
                    VStack(spacing: SAIFSpacing.md) {
                        Image(systemName: "chart.bar").font(.system(size: 40)).foregroundStyle(SAIFColors.mutedText)
                        Text("No training data this week").font(.system(size: 14, weight: .semibold)).foregroundStyle(SAIFColors.text)
                        Text("Complete workouts to see volume breakdown").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, SAIFSpacing.xl)
                } else {
                    VStack(spacing: SAIFSpacing.md) {
                        ForEach(data.volumeByMuscle) { muscle in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(muscle.muscleGroup.capitalized).font(.system(size: 14, weight: .medium)).foregroundStyle(SAIFColors.text)
                                    Spacer()
                                    Text("\(muscle.sets) sets").font(.system(size: 14, weight: .semibold)).foregroundStyle(SAIFColors.primary)
                                }
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).fill(SAIFColors.border).frame(height: 8)
                                        RoundedRectangle(cornerRadius: 4).fill(volumeColor(for: muscle)).frame(width: geometry.size.width * muscle.percentage, height: 8)
                                    }
                                }
                                .frame(height: 8)
                                Text("Target: \(muscle.targetMin)-\(muscle.targetMax) sets").font(.system(size: 11)).foregroundStyle(SAIFColors.mutedText)
                            }
                        }
                    }
                }
            }
        }
        .task { await refreshRange() }
        .onChange(of: selectedRange) { _, _ in Task { await refreshRange() } }
        .task { await refreshSplit() }
    }
    
    private func volumeColor(for muscle: MuscleVolumeData) -> Color {
        if muscle.sets < muscle.targetMin { return .orange }
        if muscle.sets <= muscle.targetMax { return .green }
        return .red
    }
}

struct StatRow: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = SAIFColors.primary
    
    var body: some View {
        HStack {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(SAIFColors.primary).frame(width: 24)
            Text(label).font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
            Spacer()
            Text(value).font(.system(size: 16, weight: .bold)).foregroundStyle(valueColor)
        }
    }
}

// MARK: - Split Tuning Sheet
private struct SplitTuningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var push: Double
    @State private var pull: Double
    @State private var legs: Double
    let onSave: (Double, Double, Double) -> Void

    init(onSave: @escaping (Double, Double, Double) -> Void) {
        let d = UserDefaults.standard
        _push = State(initialValue: (d.object(forKey: "splitTune_push") as? Double) ?? 1.0)
        _pull = State(initialValue: (d.object(forKey: "splitTune_pull") as? Double) ?? 1.0)
        _legs = State(initialValue: (d.object(forKey: "splitTune_legs") as? Double) ?? 1.0)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Recommended Distribution Multipliers").font(.system(size: 12))) {
                    TuningRow(label: "Push", value: $push)
                    TuningRow(label: "Pull", value: $pull)
                    TuningRow(label: "Legs", value: $legs)
                    Text("Tip: Values scale each category's target. Default is 1.0").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                }
            }
            .navigationTitle("Split Tuning")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(push, pull, legs); dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct TuningRow: View {
    let label: String
    @Binding var value: Double
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Stepper(value: $value, in: 0.5...2.0, step: 0.1) {
                Text(String(format: "%.1fx", value)).monospaced()
            }
            .labelsHidden()
        }
    }
}

private extension OverviewTab {
    func setRange(_ r: OverviewRange) { selectedRange = r }
    var rangeTitle: String {
        switch selectedRange { case .week: return "Past Week"; case .month: return "Past Month"; case .year: return "Past Year" }
    }
    func refreshRange() async {
        guard let uid = authManager.userProfile?.id, let profile = authManager.userProfile else { return }
        loadingRange = true
        defer { loadingRange = false }
        if let stats = try? await AnalyticsService.shared.getOverviewStats(userId: uid, userProfile: profile, range: selectedRange) {
            rangeStats = stats
        }
    }
    
    var splitRangeTitle: String { splitRange == .week ? "Past Week" : "Past Month" }
    
    func refreshSplit() async {
        guard let uid = authManager.userProfile?.id, let profile = authManager.userProfile else { return }
        splitData = try? await AnalyticsService.shared.getSplitBalance(userId: uid, userProfile: profile, range: splitRange)
    }
}
