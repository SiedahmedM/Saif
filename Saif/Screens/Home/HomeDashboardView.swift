import SwiftUI

struct HomeDashboardView: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var workoutManager: WorkoutManager
    @State private var lastSession: WorkoutSession?
    @State private var showChat = false
    @State private var tipText: String? = nil
    @State private var showTip = false
    @State private var weeklyStats: WeeklyStats? = nil
    @State private var recommendation: SmartWorkoutRecommendation? = nil

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: SAIFSpacing.lg) {
                header
                if showTip, let tip = tipText {
                    HStack { Spacer(); TipCardView(text: tip, onClose: { dismissTipForToday() }).frame(maxWidth: 340) }
                }
                if let stats = weeklyStats { ProgressRingsCard(stats: stats).environmentObject(authManager) }
                if let rec = recommendation { SmartRecommendationCard(recommendation: rec) }
                quickActions
                profileCard
            }
            .padding(SAIFSpacing.xl)
        }
        .background(SAIFColors.background.ignoresSafeArea())
        .navigationTitle("SAIF")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let id = authManager.userProfile?.id {
                lastSession = try? await SupabaseService.shared.getLastCompletedSession(userId: id)
            }
        }
        .task {
            // Touch the knowledge singleton so it loads JSON and log a quick sanity check
            _ = TrainingKnowledgeService.shared
            if let ordering = TrainingKnowledgeService.shared.getOrderingPrinciples() {
                print("Ordering OK:", ordering.optimalSequence.prefix(30), "…")
            }
            let chestCount = TrainingKnowledgeService.shared.getExercises(for: "chest").count
            print("Chest research count:", chestCount)
        }
        .task {
            if shouldShowTip() {
                tipText = makeDailyTip()
                showTip = tipText != nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showChat = true } label: { Image(systemName: "message.fill") }
            }
        }
        .sheet(isPresented: $showChat) { ChatBotSheet().presentationDetents([.medium, .large]) }
        .task {
            // Consolidated async tasks on appear
            if let id = authManager.userProfile?.id {
                lastSession = try? await SupabaseService.shared.getLastCompletedSession(userId: id)
            }
            _ = TrainingKnowledgeService.shared
            if shouldShowTip() { tipText = makeDailyTip(); showTip = tipText != nil }
            await loadWeeklyStats()
            recommendation = await workoutManager.getSmartRecommendation()
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

    private var profileCard: some View {
        CardView(title: "Your Profile") {
            VStack(alignment: .leading, spacing: 6) {
                if let p = authManager.userProfile {
                    Text("Goal: \(p.primaryGoal.displayName)")
                    Text("Experience: \(p.fitnessLevel.displayName)")
                    Text("Frequency: \(p.workoutFrequency)x/week")
                    Text("Gym: \(p.gymType.displayName)")
                    if let s = lastSession {
                        Text("Last: \(s.workoutType.capitalized) on \(s.startedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(SAIFColors.mutedText)
                    }
                } else {
                    Text("Complete onboarding to personalize your plan.").foregroundStyle(SAIFColors.mutedText)
                }
            }
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
            print("Failed to load weekly stats: \(error)")
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

                // Volume ring
                VStack(spacing: SAIFSpacing.sm) {
                    ZStack {
                        ProgressRing(progress: safeProgress(Double(stats.setsCompleted), Double(stats.setsTarget)), color: SAIFColors.accent, lineWidth: 8)
                            .frame(width: 70, height: 70)
                        VStack(spacing: 2) {
                            Text("\(stats.setsCompleted)").font(.system(size: 20, weight: .bold)).foregroundStyle(SAIFColors.text)
                            Text("/ \(stats.setsTarget)").font(.system(size: 12)).foregroundStyle(SAIFColors.mutedText)
                        }
                    }
                    Text("Sets/Week").font(.system(size: 12, weight: .medium)).foregroundStyle(SAIFColors.mutedText)
                    Text("(MAV range)").font(.system(size: 10)).foregroundStyle(SAIFColors.mutedText)
                }

                // Adherence ring
                VStack(spacing: SAIFSpacing.sm) {
                    ZStack {
                        ProgressRing(progress: min(Double(stats.adherencePercentage) / 100.0, 1.0), color: adherenceColor, lineWidth: 8)
                            .frame(width: 70, height: 70)
                        Text("\(stats.adherencePercentage)%").font(.system(size: 18, weight: .bold)).foregroundStyle(SAIFColors.text)
                    }
                    Text("Adherence").font(.system(size: 12, weight: .medium)).foregroundStyle(SAIFColors.mutedText)
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
    }

    private func safeProgress(_ completed: Double, _ target: Double) -> Double { guard target > 0 else { return 0 }; return min(completed / target, 1.0) }
    private var adherenceColor: Color { stats.adherencePercentage >= 80 ? .green : (stats.adherencePercentage >= 60 ? .orange : .red) }
    private var statusText: String { stats.adherencePercentage >= 80 ? "✅ On track" : (stats.adherencePercentage >= 60 ? "⚠️ Close" : "❌ Off track") }
    private var statusColor: Color { adherenceColor }
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
                    if let pn = plan.notes, !pn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        let short = String(pn.prefix(120)).replacingOccurrences(of: "\n", with: " ")
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
