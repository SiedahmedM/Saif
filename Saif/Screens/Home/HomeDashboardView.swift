import SwiftUI
import Foundation

struct HomeDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @EnvironmentObject var networkMonitor: NetworkMonitor
    @State private var lastSession: WorkoutSession?
    @State private var showChat = false
    @State private var showProfileEdit = false
    @State private var tipText: String? = nil
    @State private var showTip = false
    @State private var weeklyStats: WeeklyStats? = nil
    @State private var recommendation: SmartWorkoutRecommendation? = nil
    @State private var recoveryStatuses: [MuscleRecoveryStatus] = []
    @State private var showRecoveryInfo = false
    @State private var overtrainingWarning: String? = nil
    @State private var sessionsThisWeek: Int = 0
    @State private var setsThisWeek: Int = 0
    @State private var showToast: Bool = false
    @State private var toastMessage: String = ""
    @State private var goPlan = false
    @State private var goLog = false
    @State private var showEndWorkoutConfirmation = false

    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                    if workoutManager.hasSavedWorkout(), let state = workoutManager.loadSavedWorkoutState() {
                        activeWorkoutCard(state)
                    }
                    header
                    quickActions

            if let stats = weeklyStats {
                ProgressRingsCard(stats: stats)
            }

            if let rec = recommendation {
                SmartRecommendationCard(recommendation: rec)
            } else if lastSession == nil {
                CardView(title: "GET STARTED") {
                    VStack(spacing: SAIFSpacing.md) {
                        Text("Let’s start your first session!")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(SAIFColors.text)
                        NavigationLink(destination: WorkoutStartView(selectedPreset: nil)) {
                            Text("Begin Now").font(.system(size: 16, weight: .semibold)).frame(maxWidth: .infinity).padding().foregroundStyle(.white).background(Color.green).clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                        }
                    }
                }
            }

                    profileCard
                    recoveryStatusCard
                    quickAccessMenu
                }
                .padding(SAIFSpacing.xl)
            }
        }
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showChat = true } label: { Image(systemName: "message.fill") }
            }
        }
        .sheet(isPresented: $showChat) { ChatBotSheet().presentationDetents([.medium, .large]) }
        .task {
            if let id = authManager.userProfile?.id {
                lastSession = try? await SupabaseService.shared.getLastCompletedSession(userId: id)
            }
            await loadWeeklyStats()
            recommendation = await workoutManager.getSmartRecommendation()
            await loadRecoveryStatus()
        }
        // Floating chat button (safe, non-blocking)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button { showChat = true } label: {
                    Image(systemName: "message.fill")
                        .foregroundStyle(.white)
                        .padding()
                        .background(SAIFColors.primary)
                        .clipShape(Circle())
                        .shadow(radius: 4)
                        .accessibilityLabel("Open Coach Chat")
                }
            }
            .padding(24)
        }
        .background(
            Group {
                NavigationLink(isActive: $goPlan) {
                    if let plan = workoutManager.currentPlan { SessionPlanView(plan: plan).environmentObject(workoutManager) } else { EmptyView() }
                } label: { EmptyView() }
                NavigationLink(isActive: $goLog) {
                    if let ex = workoutManager.currentExercise { ExerciseLoggingView(exercise: ex).environmentObject(workoutManager) } else { EmptyView() }
                } label: { EmptyView() }
            }
        )
        .confirmationDialog("End Workout?", isPresented: $showEndWorkoutConfirmation) {
            Button("End & Save Progress", role: .destructive) {
                Task { await workoutManager.completeWorkout(notes: nil) }
            }
            Button("Discard Workout", role: .destructive) {
                workoutManager.clearSavedWorkoutState()
                workoutManager.currentSession = nil
                workoutManager.currentPlan = nil
                workoutManager.completedSets.removeAll()
                workoutManager.currentExercise = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have \(workoutManager.completedSets.count) sets logged. What would you like to do?")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Welcome back,").foregroundStyle(SAIFColors.mutedText)
            Text(authManager.userProfile?.fullName ?? "Athlete").font(.system(size: 28, weight: .bold)).foregroundStyle(SAIFColors.text)
        }
    }

    private var quickActions: some View {
        VStack(spacing: SAIFSpacing.md) {
            NavigationLink(destination: WorkoutStartView(selectedPreset: nil)) {
                Text("Start Workout").font(.system(size: 18, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, SAIFSpacing.lg).foregroundStyle(.white).background(SAIFColors.primary).clipShape(RoundedRectangle(cornerRadius: SAIFRadius.xl))
            }

            NavigationLink(destination: ExerciseLibraryView()) {
                HStack {
                    Image(systemName: "book.fill")
                    Text("Exercise Library")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14))
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(SAIFColors.text)
                .padding(SAIFSpacing.lg)
                .background(SAIFColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: SAIFRadius.lg).stroke(SAIFColors.border, lineWidth: 1))
            }
        }
    }

    private func activeWorkoutCard(_ state: WorkoutState) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                HStack {
                    Image(systemName: "clock.fill").foregroundStyle(.orange)
                    Text("Active Workout").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("\(state.completedSets.count) sets").foregroundStyle(SAIFColors.mutedText)
                }
                Text("\(state.session.workoutType.capitalized) • Started \(timeAgo(state.session.startedAt))")
                    .font(.system(size: 14)).foregroundStyle(SAIFColors.mutedText)
                HStack(spacing: SAIFSpacing.md) {
                    PrimaryButton("Resume Workout") {
                        workoutManager.restoreWorkoutState(state)
                        navigateToActiveWorkout()
                    }
                    Button("End Workout") { showEndWorkoutConfirmation = true }
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func navigateToActiveWorkout() {
        if workoutManager.currentExercise != nil { goLog = true }
        else if workoutManager.currentPlan != nil { goPlan = true }
    }

    private func timeAgo(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    private var profileCard: some View {
        CardView(title: "Your Profile") {
            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                if let p = authManager.userProfile {
                    ProfileRow(icon: "target", label: "Goal", value: p.primaryGoal.displayName)
                    ProfileRow(icon: "figure.strengthtraining.traditional", label: "Experience", value: p.fitnessLevel.displayName)
                    ProfileRow(icon: "calendar", label: "Frequency", value: "\(p.workoutFrequency)x/week")
                    ProfileRow(icon: "dumbbell.fill", label: "Equipment", value: p.gymType.displayName)
                    
                if let s = lastSession {
                    Divider()
                        .padding(.vertical, SAIFSpacing.sm)
                    Text("Last: \(s.workoutType.capitalized) on \(s.startedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.system(size: 12))
                        .foregroundStyle(SAIFColors.mutedText)
                }
                if let inj = authManager.userProfile?.injuriesLimitations, !inj.isEmpty {
                    Divider().padding(.vertical, SAIFSpacing.sm)
                    ProfileRow(icon: "cross.case.fill", label: "Limitations", value: inj.joined(separator: ", "))
                    let parsed = InjuryRuleEngine.shared.parseInjuries(from: inj.joined(separator: ", "))
                    if !parsed.isEmpty {
                        Text("✅ Workouts adapted for: \(parsed.joined(separator: ", "))")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                            .padding(.top, 2)
                    }
                }
                    
                    Button {
                        showProfileEdit = true
                    } label: {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit Profile")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SAIFColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SAIFSpacing.sm)
                        .background(SAIFColors.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
                    }
                    .padding(.top, SAIFSpacing.sm)
                } else {
                    Text("Complete onboarding to personalize your plan.")
                        .foregroundStyle(SAIFColors.mutedText)
                }
            }
        }
        .sheet(isPresented: $showProfileEdit) {
            ProfileEditSheet()
        }
    }
}

private let tipDismissKey = "coachDailyTipDismissedAt"

extension HomeDashboardView {
    private func shouldShowTip() -> Bool {
        if let ts = UserDefaults.standard.object(forKey: tipDismissKey) as? Date {
            let cal = Calendar.current
            return !cal.isDateInToday(ts)
        }
        return true
    }
    private func dismissTipForToday() {
        UserDefaults.standard.set(Date(), forKey: tipDismissKey)
        withAnimation { showTip = false }
    }
}

// MARK: - Quick Access
private extension HomeDashboardView {
    var quickAccessMenu: some View {
        CardView(title: "Quick Access") {
            VStack(spacing: 0) {
                QuickAccessRow(
                    icon: "book.fill",
                    title: "Exercise Library",
                    destination: AnyView(ExerciseLibraryView())
                )
                Divider().padding(.leading, 44)
                QuickAccessRow(
                    icon: "chart.bar.fill",
                    title: "Progress & Analytics",
                    destination: AnyView(ProgressAnalyticsView())
                )
                Divider().padding(.leading, 44)
                QuickAccessRow(
                    icon: "calendar",
                    title: "Workout History",
                    destination: AnyView(CalendarHistoryView())
                )
                Divider().padding(.leading, 44)
                QuickAccessRow(
                    icon: "message.fill",
                    title: "AI Coach Chat",
                    destination: AnyView(ChatBotSheet())
                )
            }
        }
    }
}

struct QuickAccessRow: View {
    let icon: String
    let title: String
    let destination: AnyView

    var body: some View {
        NavigationLink(destination: destination) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(SAIFColors.primary)
                    .frame(width: 28)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(SAIFColors.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SAIFColors.mutedText)
            }
            .padding(.vertical, SAIFSpacing.md)
        }
    }
}

struct ProgressAnalyticsPlaceholder: View {
    var body: some View {
        ZStack {
            SAIFColors.background.ignoresSafeArea()
            VStack {
                Text("📊").font(.system(size: 60))
                Text("Progress & Analytics").font(.system(size: 24, weight: .bold)).padding(.top)
                Text("Coming soon!").foregroundStyle(SAIFColors.mutedText)
            }
        }
        .navigationTitle("Analytics")
    }
}

struct ProfileRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(SAIFColors.primary)
            Text("\(label):")
                .font(.system(size: 14))
                .foregroundStyle(SAIFColors.mutedText)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SAIFColors.text)
        }
    }
}

// MARK: - Weekly Progress (Rings)
extension HomeDashboardView {
    private func loadWeeklyStats() async {
        guard let userId = authManager.userProfile?.id else { return }
        let calendar = Calendar.current
        let now = Date()
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) else { return }
        do {
            let sessions = try await SupabaseService.shared.getSessionsBetween(userId: userId, start: weekAgo, end: now)
            let completed = sessions.filter { $0.completedAt != nil }
            var totalSets = 0
            for s in completed {
                if let sets = try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id) {
                    totalSets += sets.count
                }
            }
            if let profile = authManager.userProfile {
                let targetSets = calculateWeeklyTargetSets(profile: profile)
                weeklyStats = WeeklyStats(
                    workoutsCompleted: completed.count,
                    workoutsTarget: profile.workoutFrequency,
                    setsCompleted: totalSets,
                    setsTarget: targetSets,
                    adherencePercentage: calculateAdherence(completed: completed.count, target: profile.workoutFrequency)
                )
            }
        } catch {
            if let urlErr = error as? URLError, urlErr.code == .cancelled { return }
            // Silently ignore transient failures
        }
    }

    private func calculateWeeklyTargetSets(profile: UserProfile) -> Int {
        // Evidence-based: derive per-session set targets by summing per-muscle setsPerSessionRange midpoints
        func setsPerSessionMidpoint(for group: String) -> Int {
            let norm = mapGroup(group)
            guard let lm = TrainingKnowledgeService.shared.getVolumeLandmarks(for: norm, goal: profile.primaryGoal, experience: profile.fitnessLevel) else { return 0 }
            return parseRangeMidpoint(from: lm.setsPerSessionRange) ?? 0
        }

        // Define canonical PPL groupings
        let pushGroups = ["chest", "shoulders", "triceps"]
        let pullGroups = ["back", "biceps", "shoulders"] // treat rear delts as shoulders bucket
        let legsGroups = ["quads", "hamstrings", "glutes", "calves"]

        let pushSets = pushGroups.map(setsPerSessionMidpoint).reduce(0, +)
        let pullSets = pullGroups.map(setsPerSessionMidpoint).reduce(0, +)
        let legsSets = legsGroups.map(setsPerSessionMidpoint).reduce(0, +)

        // Average per-session target across PPL archetype (ignore zeros to avoid skew if data missing)
        let sessionSetTotals = [pushSets, pullSets, legsSets].filter { $0 > 0 }
        guard !sessionSetTotals.isEmpty else {
            // Fallback to simple heuristic if research missing
            let basePerWorkout: Int = (profile.fitnessLevel == .beginner) ? 12 : (profile.fitnessLevel == .intermediate ? 16 : 20)
            return max(basePerWorkout * max(profile.workoutFrequency, 1), 1)
        }
        let avgPerSession = Double(sessionSetTotals.reduce(0, +)) / Double(sessionSetTotals.count)
        let weekly = Int(round(avgPerSession * Double(max(profile.workoutFrequency, 1))))
        return max(weekly, 1)
    }

    private func parseRangeMidpoint(from text: String) -> Int? {
        // Extract up to two integers from text like "8-10 sets" or "8 – 10" or "8 to 10"
        let cleaned = text.replacingOccurrences(of: "to", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let nums = cleaned.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        if nums.isEmpty { return nil }
        if nums.count == 1 { return nums[0] }
        return (nums[0] + nums[1]) / 2
    }

    private func mapGroup(_ group: String) -> String {
        let g = group.lowercased()
        if g.contains("rear") && g.contains("delt") { return "shoulders" }
        return g
    }

    private func calculateAdherence(completed: Int, target: Int) -> Int {
        guard target > 0 else { return 0 }
        return min(Int((Double(completed) / Double(target)) * 100.0), 100)
    }
}

struct WeeklyStats {
    let workoutsCompleted: Int
    let workoutsTarget: Int
    let setsCompleted: Int
    let setsTarget: Int
    let adherencePercentage: Int
}

struct ProgressRingsCard: View {
    @EnvironmentObject var authManager: AuthManager
    let stats: WeeklyStats
    @State private var showWorkoutsInfo = false
    @State private var showVolumeInfo = false
    @State private var showAdherenceInfo = false

    var body: some View {
        CardView(title: "YOUR PROGRESS THIS WEEK") {
            HStack(spacing: SAIFSpacing.xl) {
                // Workouts ring
                VStack(spacing: SAIFSpacing.sm) {
                    ZStack {
                        ProgressRing(progress: safeProgress(Double(stats.workoutsCompleted), Double(stats.workoutsTarget)), color: SAIFColors.primary, lineWidth: 8)
                            .frame(width: 70, height: 70)
                        VStack(spacing: 2) {
                            Text("\(stats.workoutsCompleted)").font(.system(size: 20, weight: .bold)).foregroundStyle(SAIFColors.text)
                            Text("/ \(stats.workoutsTarget)").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                        }
                    }
                    Text("Workouts").font(.system(size: 12, weight: .medium)).foregroundStyle(SAIFColors.mutedText)
                    Text("Completed").font(.system(size: 10)).foregroundStyle(SAIFColors.mutedText)
                }

                // Volume ring (with info)
                VStack(spacing: SAIFSpacing.sm) {
                    ZStack {
                        ProgressRing(progress: safeProgress(Double(stats.setsCompleted), Double(stats.setsTarget)), color: SAIFColors.accent, lineWidth: 8)
                            .frame(width: 70, height: 70)
                        VStack(spacing: 2) {
                            Text("\(stats.setsCompleted)").font(.system(size: 20, weight: .bold)).foregroundStyle(SAIFColors.text)
                            Text("/ \(stats.setsTarget)").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("Sets/Week").font(.system(size: 12, weight: .medium)).foregroundStyle(SAIFColors.mutedText)
                        Button { showVolumeInfo = true } label: { Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(SAIFColors.primary) }
                    }
                    Text("(MAV range)").font(.system(size: 10)).foregroundStyle(SAIFColors.mutedText)
                }

                // Adherence ring (with info)
                VStack(spacing: SAIFSpacing.sm) {
                    ZStack {
                        ProgressRing(progress: min(Double(stats.adherencePercentage) / 100.0, 1.0), color: adherenceColor, lineWidth: 8)
                            .frame(width: 70, height: 70)
                        Text("\(stats.adherencePercentage)%").font(.system(size: 18, weight: .bold)).foregroundStyle(SAIFColors.text)
                    }
                    HStack(spacing: 4) {
                        Text("Adherence").font(.system(size: 12, weight: .medium)).foregroundStyle(SAIFColors.mutedText)
                        Button { showAdherenceInfo = true } label: { Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(SAIFColors.primary) }
                    }
                    Text("to Plan").font(.system(size: 10)).foregroundStyle(SAIFColors.mutedText)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SAIFSpacing.md)

            Divider().padding(.vertical, SAIFSpacing.sm)

            HStack {
                Text("GOAL:").font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.mutedText)
                Text(authManager.userProfile?.primaryGoal.displayName ?? "Build Muscle").font(.system(size: 12, weight: .semibold)).foregroundStyle(SAIFColors.text)
                Spacer()
                Text(statusText).font(.system(size: 12, weight: .semibold)).foregroundStyle(statusColor)
            }
        }
        .sheet(isPresented: $showVolumeInfo) {
            MetricExplanationSheet(
                title: "Weekly Volume Target",
                explanation: volumeExplanation,
                calculation: volumeCalculation
            )
        }
        .sheet(isPresented: $showAdherenceInfo) {
            MetricExplanationSheet(
                title: "Adherence Percentage",
                explanation: adherenceExplanation,
                calculation: adherenceCalculation
            )
        }
    }

    private func safeProgress(_ completed: Double, _ target: Double) -> Double { guard target > 0 else { return 0 }; return min(completed / target, 1.0) }
    private var adherenceColor: Color { stats.adherencePercentage >= 80 ? .green : (stats.adherencePercentage >= 60 ? .orange : .red) }
    private var statusText: String { stats.adherencePercentage >= 80 ? "✅ On track" : (stats.adherencePercentage >= 60 ? "⚠️ Close" : "❌ Off track") }
    private var statusColor: Color { adherenceColor }

    // Explanations
    private var volumeExplanation: String {
        """
        Your weekly volume target is based on evidence-based training research.

        The number (\(stats.setsTarget) sets) comes from:

        • Your goal: \(goalName)
        • Your experience level: \(experienceLevel)
        • Muscle groups you're training

        This range represents the "Maximum Adaptive Volume" (MAV) — optimal weekly work for growth without overtraining.
        """
    }

    private var volumeCalculation: String {
        """
        CALCULATION BREAKDOWN:

        Target sets/week derives from per-session set guidance across Push/Pull/Legs, scaled by your frequency.
        × Training frequency: \(workoutsPerWeek)x/week
        = Target: \(stats.setsTarget) sets/week

        This keeps you near the MAV zone (Israetel, Schoenfeld) for your goal and level.
        """
    }

    private var adherenceExplanation: String {
        """
        Adherence measures how closely you're following your planned training schedule.

        Currently: \(stats.workoutsCompleted)/\(stats.workoutsTarget) workouts completed

        HIGH ADHERENCE (80-100%): On track and building consistency
        MODERATE (60-79%): Still progressing; room to improve
        LOW (<60%): Consider adjusting schedule or session length
        """
    }

    private var adherenceCalculation: String {
        """
        CALCULATION:

        Planned workouts: \(stats.workoutsTarget)/week
        Completed workouts: \(stats.workoutsCompleted)

        Adherence = (Completed ÷ Planned) × 100
                  = (\(stats.workoutsCompleted) ÷ \(stats.workoutsTarget)) × 100
                  = \(stats.adherencePercentage)%

        Your plan is based on your profile setting of training \(stats.workoutsTarget)x per week.
        """
    }

    private var goalName: String { authManager.userProfile?.primaryGoal.displayName ?? "—" }
    private var experienceLevel: String { authManager.userProfile?.fitnessLevel.displayName ?? "—" }
    private var workoutsPerWeek: Int { stats.workoutsTarget }
}

struct MetricExplanationSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let explanation: String
    let calculation: String

    var body: some View {
        NavigationStack {
            ZStack {
                SAIFColors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                        // Explanation
                        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                            Label("What This Means", systemImage: "lightbulb.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SAIFColors.primary)
                            Text(explanation)
                                .font(.system(size: 15))
                                .foregroundStyle(SAIFColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(SAIFSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SAIFColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))

                        // Calculation
                        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                            Label("How It's Calculated", systemImage: "function")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SAIFColors.primary)
                            Text(calculation)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(SAIFColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(SAIFSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SAIFColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))

                        // Tip
                        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                            Label("Pro Tip", systemImage: "star.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(SAIFColors.accent)
                            Text(proTip)
                                .font(.system(size: 15))
                                .foregroundStyle(SAIFColors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(SAIFSpacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SAIFColors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                    }
                    .padding(SAIFSpacing.xl)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private var proTip: String {
        if title.contains("Volume") {
            return "Tracking volume helps ensure progressive overload — the key driver of muscle growth. Aim to gradually increase your weekly sets over time."
        } else {
            return "Consistency beats perfection. Even 75% adherence consistently will deliver better results than 100% adherence sporadically."
        }
    }
}

struct ProgressRing: View {
    let progress: Double // 0.0 to 1.0
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(SAIFColors.border, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(progress, 1.0)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: progress)
        }
    }
}

// MARK: - Recovery Status Card
struct MuscleRecoveryStatus: Identifiable {
    let id = UUID()
    let group: String
    let daysRest: Int
    let statusText: String
    let icon: String
}

// MARK: - Visual Heatmap
struct MuscleGroupHeatmap: View {
    let statuses: [MuscleRecoveryStatus]

    var body: some View {
        VStack(spacing: SAIFSpacing.lg) {
            HStack(spacing: SAIFSpacing.md) {
                MuscleCard(status: statusFor("Chest"))
                MuscleCard(status: statusFor("Shoulders"))
                MuscleCard(status: statusFor("Back"))
            }
            HStack(spacing: SAIFSpacing.md) {
                MuscleCard(status: statusFor("Legs")).frame(maxWidth: .infinity)
            }
        }
    }

    private func statusFor(_ group: String) -> MuscleRecoveryStatus? {
        statuses.first { $0.group.lowercased() == group.lowercased() }
    }
}

struct MuscleCard: View {
    let status: MuscleRecoveryStatus?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 24))
                .foregroundStyle(colorForStatus)
            Text(status?.group ?? "Unknown").font(.system(size: 12, weight: .semibold))
            Text(status?.statusText ?? "—").font(.system(size: 10)).foregroundStyle(SAIFColors.mutedText)
            if let days = status?.daysRest { Text("\(days)d").font(.system(size: 11, weight: .bold)).foregroundStyle(colorForStatus) }
        }
        .padding(SAIFSpacing.md)
        .frame(maxWidth: .infinity)
        .background(colorForStatus.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
        .overlay(RoundedRectangle(cornerRadius: SAIFRadius.md).stroke(colorForStatus, lineWidth: 2))
    }

    private var colorForStatus: Color {
        guard let s = status else { return SAIFColors.mutedText }
        switch s.icon { case "✅": return .green; case "⏰": return .orange; case "⚠️": return .red; default: return SAIFColors.mutedText }
    }
    private var iconName: String {
        guard let g = status?.group else { return "figure.stand" }
        switch g.lowercased() {
        case "chest": return "figure.strengthtraining.traditional"
        case "back": return "figure.cooldown"
        case "shoulders": return "figure.arms.open"
        case "legs": return "figure.walk"
        default: return "figure.stand"
        }
    }
}

// MARK: - Recommendation
struct RecoveryRecommendation: View {
    let statuses: [MuscleRecoveryStatus]

    private var rec: (title: String, message: String, action: String, color: Color) {
        let ready = statuses.filter { $0.icon == "✅" }
        if ready.isEmpty {
            if let next = statuses.min(by: { $0.daysRest < $1.daysRest }) {
                let remaining = max(0, 2 - next.daysRest)
                return ("Rest Day Recommended", "All groups need more recovery. \(next.group) may be ready in \(remaining) day(s).", "Take active recovery", .orange)
            }
        }
        if let best = ready.first {
            let wt = workoutTypeFor(best.group)
            return ("\(best.group) is Ready!", "Optimal recovery (\(best.daysRest) day(s) rest). Great time to train.", "Start \(wt) Workout", .green)
        }
        if let ok = statuses.first(where: { $0.icon == "⏰" }) {
            return ("\(ok.group) Adequate", "You can train today, or rest one more day for optimal gains.", "Start anyway", .yellow)
        }
        return ("Keep Resting", "Listen to your body.", "Check back tomorrow", SAIFColors.mutedText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
            HStack(spacing: SAIFSpacing.sm) {
                Image(systemName: "brain.head.profile").foregroundStyle(rec.color)
                Text("Smart Suggestion").font(.system(size: 14, weight: .semibold)).foregroundStyle(SAIFColors.mutedText)
            }
            Text(rec.title).font(.system(size: 18, weight: .bold)).foregroundStyle(rec.color)
            Text(rec.message).font(.system(size: 14)).foregroundStyle(SAIFColors.text)
            if !rec.action.contains("tomorrow") {
                Button(rec.action) { /* Navigate to workout start */ }
                    .buttonStyle(.borderedProminent)
                    .tint(rec.color)
            }
        }
        .padding(SAIFSpacing.lg)
        .background(rec.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
    }

    private func workoutTypeFor(_ group: String) -> String {
        switch group.lowercased() { case "chest", "shoulders": return "Push"; case "back": return "Pull"; case "legs": return "Legs"; default: return group.capitalized }
    }
}

// MARK: - Weekly Volume Summary
struct WeeklyVolumeSummary: View {
    let sessionsThisWeek: Int
    let setsThisWeek: Int
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("This Week").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                HStack(spacing: SAIFSpacing.md) {
                    HStack(spacing: 4) { Image(systemName: "calendar"); Text("\(sessionsThisWeek)").font(.system(size: 18, weight: .bold)); Text("workouts").font(.system(size: 12)) }
                    HStack(spacing: 4) { Image(systemName: "chart.bar"); Text("\(setsThisWeek)").font(.system(size: 18, weight: .bold)); Text("sets").font(.system(size: 12)) }
                }
            }
            Spacer()
            if sessionsThisWeek >= 4 {
                VStack { Text("🔥").font(.system(size: 24)); Text("On fire!").font(.system(size: 11, weight: .semibold)).foregroundStyle(.orange) }
            }
        }
        .padding(SAIFSpacing.md)
        .background(SAIFColors.accent.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))
    }
}

extension HomeDashboardView {
    private var recoveryStatusCard: some View {
        CardView(title: "RECOVERY STATUS") {
            VStack(spacing: SAIFSpacing.lg) {
                WeeklyVolumeSummary(sessionsThisWeek: sessionsThisWeek, setsThisWeek: setsThisWeek)
                MuscleGroupHeatmap(statuses: recoveryStatuses)

                if let warning = overtrainingWarning {
                    HStack(alignment: .top, spacing: SAIFSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(warning).font(.system(size: 13)).foregroundStyle(.orange)
                        Spacer(minLength: 0)
                    }
                    .padding(SAIFSpacing.sm)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.sm))
                }

                Divider()
                RecoveryRecommendation(statuses: recoveryStatuses)

                Button {
                    showRecoveryInfo = true
                } label: {
                    HStack { Image(systemName: "info.circle"); Text("Learn about recovery science") }
                        .font(.system(size: 13))
                        .foregroundStyle(SAIFColors.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(isPresented: $showRecoveryInfo) { RecoveryInfoSheet() }
        .onReceive(NotificationCenter.default.publisher(for: .saifWorkoutCompleted)) { _ in
            Task {
                await loadWeeklyStats()
                recommendation = await workoutManager.getSmartRecommendation()
                await loadRecoveryStatus()
            }
            // Show success toast
            toastMessage = "Workout saved"
            withAnimation { showToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { showToast = false }
            }
        }
        .overlay(alignment: .bottom) {
            if showToast {
                Text(toastMessage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private func loadRecoveryStatus() async {
        if Task.isCancelled { return }
        // Avoid kicking network calls when offline; keep previous values
        if let isConnected = try? await Task { @MainActor in networkMonitor.isConnected }.value, !isConnected { return }
        guard let userId = authManager.userProfile?.id else { return }
        let cal = Calendar.current
        let now = Date()
        guard let tenDaysAgo = cal.date(byAdding: .day, value: -10, to: now) else { return }
        do {
            // Fetch sessions for last 10 days
            let sessions = try await SupabaseService.shared.getSessionsBetween(userId: userId, start: tenDaysAgo, end: now)
            let sessionIds = sessions.map { $0.id }
            let allSets = try await SupabaseService.shared.getExerciseSetsForSessions(sessionIds: sessionIds)
            let setsBySession = Dictionary(grouping: allSets, by: { $0.sessionId })
            // Build a global exercise map to avoid per-session calls
            let allExIds = Array(Set(allSets.map { $0.exerciseId }))
            let allExercises = try await SupabaseService.shared.getExercisesByIds(allExIds)
            var exById: [UUID: Exercise] = [:]
            for ex in allExercises { exById[ex.id] = ex }

            // Build last-trained map using actual exercises hit in sessions
            var last: [String: Date] = [:]
            for s in sessions {
                if let sets = setsBySession[s.id], !sets.isEmpty {
                    let exIds = Array(Set(sets.map { $0.exerciseId }))
                    for eid in exIds {
                        if let ex = exById[eid] {
                            let norm = TrainingKnowledgeService.shared.normalizeMuscleGroup(ex.muscleGroup)
                            if let prev = last[norm] {
                                if s.startedAt > prev { last[norm] = s.startedAt }
                            } else {
                                last[norm] = s.startedAt
                            }
                        }
                    }
                }
            }
            // Helper: days since for a canonical group, cap at 10 if missing
            func daysSince(_ group: String) -> Int {
                if let d = last[group] { return cal.dateComponents([.day], from: d, to: now).day ?? 0 }
                return 10
            }
            // Compute per-category days
            let chestDays = daysSince("chest")
            let backDays = daysSince("back")
            let shoulderDays = max(daysSince("shoulders"), daysSince("rear delts"))
            let quadsDays = daysSince("quads")
            let hamDays = daysSince("hamstrings")
            let glutesDays = daysSince("glutes")
            let legsDays = min(quadsDays, min(hamDays, glutesDays))

            // Recommended rest days from guidelines
            let recBack = recommendedRestDays(for: "Back")
            let recChest = recommendedRestDays(for: "Chest")
            let recShoulders = recommendedRestDays(for: "Shoulders")
            let recLegs = max(recommendedRestDays(for: "Quads"), max(recommendedRestDays(for: "Hamstrings"), recommendedRestDays(for: "Glutes")))

            let entries: [(String, Int, Int)] = [
                ("Back", backDays, recBack),
                ("Legs", legsDays, recLegs),
                ("Chest", chestDays, recChest),
                ("Shoulders", shoulderDays, recShoulders)
            ]
            var out: [MuscleRecoveryStatus] = []
            for (name, days, rec) in entries {
                let status: (String, String) = {
                    if days >= rec + 1 { return ("Optimal", "✅") }
                    if days >= rec { return ("Ready", "✅") }
                    if days == rec - 1 { return ("Adequate", "⏰") }
                    return ("Too soon", "⚠️")
                }()
                out.append(MuscleRecoveryStatus(group: name, daysRest: days, statusText: status.0, icon: status.1))
            }
            // Order: ✅ first, then by most rested
            out.sort { a, b in
                if a.icon == "✅" && b.icon != "✅" { return true }
                if a.icon != "✅" && b.icon == "✅" { return false }
                return a.daysRest > b.daysRest
            }
            recoveryStatuses = out

            // Weekly stats and overtraining detection
            if let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: now) {
                let weekSessions = sessions.filter { $0.startedAt >= sevenDaysAgo }
                sessionsThisWeek = weekSessions.count
                setsThisWeek = allSets.filter { set in
                    if let session = sessions.first(where: { $0.id == set.sessionId }) { return session.startedAt >= sevenDaysAgo }
                    return false
                }.count
                let frequentlyTrained = out.filter { $0.daysRest <= 1 }
                if frequentlyTrained.count >= 3 {
                    overtrainingWarning = "⚠️ Multiple groups trained recently. Consider a rest day to avoid overtraining."
                } else if weekSessions.count >= 6 {
                    overtrainingWarning = "💪 You've trained \(weekSessions.count) times in the last 7 days. Great consistency! Consider a deload soon."
                } else { overtrainingWarning = nil }
            }
        } catch {
            let ns = error as NSError
            // Suppress noisy -999 (cancelled) errors due to task cancellation/reruns
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            print("❌ [HomeDashboardView.loadRecoveryStatus] \(error)")
            // Leave previous values; show gentle warning
            overtrainingWarning = "Network issue loading recovery. Data may be stale."
        }
    }

    private func analyzeLastTrainedDates(sessions: [WorkoutSession]) -> [String: Date] {
        var last: [String: Date] = [:]
        for s in sessions {
            let groups = mapWorkoutTypeToGroups(s.workoutType)
            for g in groups {
                if let prev = last[g] {
                    if s.startedAt > prev { last[g] = s.startedAt }
                } else {
                    last[g] = s.startedAt
                }
            }
        }
        return last
    }

    private func mapWorkoutTypeToGroups(_ type: String) -> [String] {
        let t = type.lowercased()
        if t.contains("push") { return ["chest", "shoulders", "triceps"] }
        if t.contains("pull") { return ["back", "biceps", "rear_delts"] }
        if t.contains("leg") { return ["quads", "hamstrings", "glutes", "calves"] }
        if t.contains("upper") { return ["chest", "back", "shoulders", "biceps", "triceps"] }
        if t.contains("lower") { return ["quads", "hamstrings", "glutes", "calves"] }
        return [t]
    }

    private func recommendedRestDays(for group: String) -> Int {
        // Load from bundled guidelines JSON (once)
        struct Cache { static var map: [String:Int]? = nil }
        if Cache.map == nil {
            if let url = Bundle.main.url(forResource: "recovery_guidelines", withExtension: "json", subdirectory: "Knowledge/Data"),
               let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let groups = (obj["groups"] as? [String: Any]) {
                var m: [String:Int] = [:]
                for (k, v) in groups {
                    if let dict = v as? [String: Any], let rec = dict["recommended_rest_days"] as? Int {
                        m[k.lowercased()] = rec
                    }
                }
                Cache.map = m
            } else {
                Cache.map = [:]
            }
        }
        let key = group.lowercased()
        return Cache.map?[key] ?? 2
    }
}

struct RecoveryInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let info: RecoveryGeneral? = {
        if let url = Bundle.main.url(forResource: "recovery_general", withExtension: "json", subdirectory: "Knowledge/Data"),
           let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(RecoveryGeneral.self, from: data)
        }
        return nil
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SAIFSpacing.xl) {
                    section("Recovery Windows", info?.recovery_windows)
                    section("Frequency Optimization", info?.frequency_optimization)
                    if let vl = info?.volume_landmarks { volumeSection(vl) }
                    section("Split Optimization", info?.split_optimization)
                    section("Individual Variation", info?.individual_variation_factors)
                }
                .padding(SAIFSpacing.xl)
            }
            .navigationTitle("Recovery Insights")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func section(_ title: String, _ map: [String:String]?) -> some View {
        if let map, !map.isEmpty {
            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                Text(title.uppercased()).font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.mutedText)
                ForEach(map.keys.sorted(), id: \.self) { k in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(k).font(.system(size: 14, weight: .semibold))
                        Text(map[k] ?? "").font(.system(size: 14)).foregroundStyle(SAIFColors.text)
                    }
                }
            }
            .padding(SAIFSpacing.lg)
            .background(SAIFColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
        }
    }

    @ViewBuilder
    private func volumeSection(_ vol: [String:[String:[String:String]]]) -> some View {
        VStack(alignment: .leading, spacing: SAIFSpacing.md) {
            Text("VOLUME LANDMARKS").font(.system(size: 12, weight: .bold)).foregroundStyle(SAIFColors.mutedText)
            ForEach(vol.keys.sorted(), id: \.self) { muscle in
                VStack(alignment: .leading, spacing: 6) {
                    Text(muscle.capitalized).font(.system(size: 14, weight: .semibold))
                    if let tiers = vol[muscle] {
                        ForEach(["MV","MEV","MAV","MRV"], id: \.self) { tier in
                            if let levels = tiers[tier] {
                                Text("\(tier): \(levels.map { "\($0.key): \($0.value)" }.joined(separator: ", "))")
                                    .font(.system(size: 13))
                                    .foregroundStyle(SAIFColors.text)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(SAIFSpacing.lg)
        .background(SAIFColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
    }
}

// Local model for decoding general recovery info
struct RecoveryGeneral: Codable {
    let recovery_windows: [String:String]
    let frequency_optimization: [String:String]
    let volume_landmarks: [String:[String:[String:String]]]
    let split_optimization: [String:String]
    let individual_variation_factors: [String:String]
}

// MARK: - Smart Recommendation Card
struct SmartRecommendationCard: View {
    let recommendation: SmartWorkoutRecommendation

    var body: some View {
        CardView(title: "TODAY'S RECOMMENDATION") {
            VStack(alignment: .leading, spacing: SAIFSpacing.md) {
                // Workout type and timing
                HStack {
                    Text("📅").font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleText)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(SAIFColors.text)
                        if recommendation.daysSinceLastTrained > 0 {
                            Text("Last trained: \(recommendation.daysSinceLastTrained) day\(recommendation.daysSinceLastTrained == 1 ? "" : "s") ago")
                                .font(.system(size: 14))
                                .foregroundStyle(SAIFColors.mutedText)
                        }
                    }
                }

                // Reasoning
                Text(recommendation.reasoning)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(reasoningColor)
                    .padding(.vertical, SAIFSpacing.sm)
                    .padding(.horizontal, SAIFSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(reasoningColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.md))

                // Suggested exercises
                VStack(alignment: .leading, spacing: SAIFSpacing.sm) {
                    Text("Suggested exercises:")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SAIFColors.mutedText)
                    ForEach(recommendation.suggestedExercises.indices, id: \.self) { i in
                        HStack {
                            Text("•")
                            Text(recommendation.suggestedExercises[i].name).font(.system(size: 14))
                            Text("(\(recommendation.suggestedExercises[i].sets) sets)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(SAIFColors.primary)
                        }
                        .foregroundStyle(SAIFColors.text)
                    }
                }
                .padding(.vertical, SAIFSpacing.sm)

                // Start button
                NavigationLink(destination: WorkoutStartView(selectedPreset: presetFromType(recommendation.workoutType))) {
                    Text("Start \(titleText)")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, SAIFSpacing.md)
                        .foregroundStyle(.white)
                        .background(SAIFColors.primary)
                        .clipShape(RoundedRectangle(cornerRadius: SAIFRadius.lg))
                }
            }
        }
    }

    private var reasoningColor: Color {
        if recommendation.reasoning.contains("✅") { return .green }
        if recommendation.reasoning.contains("⚠️") { return .orange }
        return SAIFColors.mutedText
    }
    private var titleText: String {
        switch recommendation.workoutType.lowercased() {
        case "push": return "Push Day"
        case "pull": return "Pull Day"
        case "legs": return "Leg Day"
        default: return recommendation.workoutType.capitalized + " Day"
        }
    }
    private func presetFromType(_ t: String) -> Preset? {
        switch t.lowercased() { case "push": return .push; case "pull": return .pull; case "legs": return .legs; default: return nil }
    }
}

// (Diagnostic view removed)

extension HomeDashboardView {
    func makeDailyTip() -> String? {
        guard let profile = authManager.userProfile else { return nil }
        let goal = profile.primaryGoal
        let level = profile.fitnessLevel
        let freq = profile.workoutFrequency
        let last = lastSession
        var lines: [String] = []
        if let last {
            let days = Calendar.current.dateComponents([.day], from: last.startedAt, to: Date()).day ?? 0
            if days >= 2 { lines.append("It's been \(days) days since your last session — let's build momentum today.") }
            else if days == 0 { lines.append("Nice consistency — keep the streak going today.") }
        }
        switch (level, goal) {
        case (.beginner, .bulk): lines.append("Start with key compounds and aim for 6–12 reps.")
        case (.beginner, .maintain): lines.append("Keep intensity moderate and focus on clean technique (8–10 reps).")
        case (.intermediate, .bulk): lines.append("Add a small progression (load or reps) on a primary lift.")
        case (.intermediate, .cut): lines.append("Preserve strength with steady tempo and moderate volume.")
        case (.advanced, .bulk): lines.append("Rotate intensities (heavy/moderate) to manage fatigue.")
        default: lines.append("Prioritize quality compounds, then accessories for weak links.")
        }
        if freq >= 5 && lines.count < 2 { lines.append("Shorter sessions still count — keep recovery in check.") }
        let tip = lines.prefix(2).joined(separator: " ")
        return tip.isEmpty ? nil : tip
    }
}

struct ChatBotSheet: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var messages: [String] = ["Hi, I’m your SAIF coach. How can I help?"]
    @State private var input: String = ""
    @State private var userContext: String = ""

    var body: some View {
        NavigationStack {
            VStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages.indices, id: \.self) { i in
                            Text(messages[i]).padding(10).background(i % 2 == 0 ? SAIFColors.surface : SAIFColors.primary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
                HStack {
                    TextField("Ask me anything...", text: $input).textFieldStyle(.roundedBorder)
                    Button("Send") { send() }
                }.padding()
            }
            .navigationTitle("Coach")
        }
        .task { await loadUserContext() }
    }

    private func send() {
        guard !input.isEmpty else { return }
        let prompt = input
        messages.append(prompt)
        input = ""
        Task {
            let profile = authManager.userProfile
            let context = "User: \(profile?.fullName ?? "Athlete"); Goal: \(profile?.primaryGoal.rawValue ?? ""); Experience: \(profile?.fitnessLevel.rawValue ?? ""); Frequency: \(profile?.workoutFrequency ?? 0)\n" + userContext
            let system = "You are a helpful fitness coach. Use provided user history and context to tailor answers. If data is missing, ask a clarifying question."
            let reply = try? await OpenAIService.shared.getChatReply(system: system, user: context + "\nQuestion: " + prompt)
            messages.append(reply ?? "I’ll think about that and get back to you.")
        }
    }

    @MainActor
    private func loadUserContext() async {
        guard let profile = authManager.userProfile else { return }
        do {
            let sessions = try await SupabaseService.shared.getRecentWorkoutSessions(userId: profile.id, limit: 20)
            var lines: [String] = []
            let recent = Array(sessions.prefix(5))
            for s in recent {
                let sets = try await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id)
                let exIds = Array(Set(sets.map { $0.exerciseId }))
                let exercises = try await SupabaseService.shared.getExercisesByIds(exIds)
                let names = exercises.prefix(3).map { $0.name }.joined(separator: ", ")
                let dateStr = s.startedAt.formatted(date: .abbreviated, time: .omitted)
                var noteBits: [String] = []
                if let n = s.notes, !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let short = String(n.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                    noteBits.append("Notes: \(short)")
                }
                if let plan = try? await SupabaseService.shared.getSessionPlan(sessionId: s.id) {
                    // Include first safety note if present
                    if let firstNote = plan.safetyNotes.first {
                        let short = String(firstNote.prefix(120)).replacingOccurrences(of: "\n", with: " ")
                        noteBits.append("Plan: \(short)")
                    }
                }
                let deloadFlag: String = {
                    let t = (s.notes ?? "").lowercased()
                    if t.contains("deload") || t.contains("recovery week") { return " (DELOAD)" }
                    return ""
                }()
                let suffix = noteBits.isEmpty ? "" : " — " + noteBits.joined(separator: " | ")
                lines.append("- \(s.workoutType.capitalized) on \(dateStr): \(sets.count) sets across \(exercises.count) exercises\(deloadFlag) (e.g., \(names))\(suffix)")
            }
            var ctx = "Recent sessions (most recent first):\n" + lines.joined(separator: "\n")

            // Aggregate simple volume by muscle group over last 14 days
            if let first = sessions.first {
                let cal = Calendar.current
                let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: first.startedAt) ?? Date().addingTimeInterval(-14*86400)
                let within14 = sessions.filter { $0.startedAt >= twoWeeksAgo }
                var agg: [String:Int] = [:]
                var weeklyTotals: [Date:Int] = [:]
                func startOfWeek(_ d: Date) -> Date { cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d }
                for s in within14.prefix(14) {
                    let sets = try await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id)
                    let exIds = Array(Set(sets.map { $0.exerciseId }))
                    let exercises = try await SupabaseService.shared.getExercisesByIds(exIds)
                    let setsByExercise: [UUID:Int] = sets.reduce(into: [:]) { $0[$1.exerciseId, default: 0] += 1 }
                    for ex in exercises {
                        let c = setsByExercise[ex.id] ?? 0
                        agg[ex.muscleGroup, default: 0] += c
                    }
                    let sow = startOfWeek(s.startedAt)
                    weeklyTotals[sow, default: 0] += sets.count
                }
                if !agg.isEmpty {
                    let top = agg.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key.capitalized): \($0.value) sets" }.joined(separator: ", ")
                    ctx += "\n\nLast ~2 weeks volume by muscle (approx): \(top)"
                }
                // Week-over-week progression (last two full weeks available)
                if weeklyTotals.count >= 2 {
                    let sorted = weeklyTotals.keys.sorted()
                    let lastTwo = Array(sorted.suffix(2))
                    let w1 = lastTwo.first!
                    let w2 = lastTwo.last!
                    let v1 = weeklyTotals[w1] ?? 0
                    let v2 = weeklyTotals[w2] ?? 0
                    let delta = v2 - v1
                    let sign = delta == 0 ? "±" : (delta > 0 ? "+" : "")
                    let w1Str = w1.formatted(date: .abbreviated, time: .omitted)
                    let w2Str = w2.formatted(date: .abbreviated, time: .omitted)
                    ctx += "\n\nWeekly progression: Week of \(w1Str): \(v1) sets → Week of \(w2Str): \(v2) sets (Δ \(sign)\(delta))"
                }
            }
            userContext = ctx
        } catch {
            userContext = "(No history loaded)"
        }
    }
}
