import Foundation
import SwiftUI

@MainActor
class WorkoutManager: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var currentExercise: Exercise?
    @Published var completedSets: [ExerciseSet] = []
    @Published var workoutRecommendation: WorkoutRecommendation?
    @Published var exerciseRecommendations: [ExerciseRecommendation] = []
    @Published var targetSetsRange: String? = nil
    @Published var totalSetsRecommended: Int? = nil
    @Published var availableExercises: [Exercise] = []
    @Published var exerciseDebug: ExerciseDebug? = nil
    @Published var setRepRecommendation: SetRepRecommendation?
    @Published var muscleGroupPriority: [String] = []
    @Published var completedGroups: Set<String> = []
    @Published var completedExerciseIds: Set<UUID> = []
    @Published var isLoading = false
    @Published var error: String?

    private let supabaseService = SupabaseService.shared
    private let openAIService = OpenAIService.shared
    private var profile: UserProfile?

    func initialize(with profile: UserProfile) { self.profile = profile }

    func getWorkoutRecommendation() async {
        guard let profile else { error = "User profile not found"; return }
        isLoading = true; defer { isLoading = false }
        do {
            // Pull recent sessions to decide first-time logic
            let recent = try await supabaseService.getRecentWorkoutSessions(userId: profile.id, limit: 5)
            if recent.isEmpty {
                // First workout smart default
                let weekday = Calendar.current.component(.weekday, from: Date())
                let isMonday = (weekday == 2)
                let recommended: String
                if isMonday { recommended = "push" }
                else if profile.primaryGoal == .bulk { recommended = "legs" }
                else { recommended = "push" }
                workoutRecommendation = WorkoutRecommendation(
                    workoutType: recommended,
                    reasoning: "Welcome to your first workout! Starting with \(recommended.capitalized) helps establish a baseline. We'll learn what works best for you and optimize from here.",
                    alternatives: ["pull", "legs"],
                    confidence: 0.7,
                    isFirstWorkout: true,
                    educationalNote: "Push/Pull/Legs is a proven split to build momentum.",
                    progressMessage: nil
                )
            } else {
                // Ask OpenAI with context
                workoutRecommendation = try await openAIService.getWorkoutTypeRecommendation(profile: profile, recentWorkouts: recent)
            }
        } catch { self.error = error.localizedDescription }
    }

    func startWorkout(workoutType: String) async {
        guard let profile else { error = "User profile not found"; return }
        isLoading = true; defer { isLoading = false }
        do {
            // Reset state for a fresh session to avoid stale data from previous type
            muscleGroupPriority = []
            availableExercises = []
            exerciseRecommendations = []
            exerciseDebug = nil
            completedGroups.removeAll()
            completedExerciseIds.removeAll()
            groupTargets.removeAll()
            groupCompletedExercises.removeAll()

            currentSession = try await supabaseService.createWorkoutSession(userId: profile.id, workoutType: workoutType)
            let order = try await openAIService.getMuscleGroupPriority(profile: profile, workoutType: workoutType, recentWorkouts: [])
            muscleGroupPriority = sanitizePriority(for: workoutType, proposed: order)
            muscleGroupOrderNote = buildOrderNote(for: workoutType, priority: muscleGroupPriority)
        } catch {
            self.error = error.localizedDescription
        }
        if muscleGroupPriority.isEmpty {
            muscleGroupPriority = defaultPriority(for: workoutType)
            muscleGroupOrderNote = buildOrderNote(for: workoutType, priority: muscleGroupPriority)
        }
    }

    func getExerciseRecommendations(for muscleGroup: String) async {
        guard let profile, let session = currentSession else { error = "Session not started"; return }
        isLoading = true; defer { isLoading = false }
        do {
            // Fetch live exercises from Supabase for this group
            let exercises = try await supabaseService.getExercisesByMuscleGroup(workoutType: session.workoutType, muscleGroup: muscleGroup)
            availableExercises = exercises
            // Build AI ordering
            let aiResponse = try await openAIService.getExerciseRecommendations(
                profile: profile,
                workoutType: session.workoutType,
                muscleGroup: muscleGroup,
                availableExercises: exercises,
                recentSets: []
            )
            exerciseRecommendations = aiResponse.recommendations
            totalSetsRecommended = aiResponse.totalSets
            targetSetsRange = aiResponse.targetSetsRange
            // De-duplicate by exercise name to avoid SwiftUI ForEach ID collisions
            var seen = Set<String>()
            exerciseRecommendations = exerciseRecommendations.filter { rec in
                if seen.contains(rec.exerciseName.lowercased()) { return false }
                seen.insert(rec.exerciseName.lowercased())
                return true
            }
            // Fallbacks if AI returned nothing
            if exerciseRecommendations.isEmpty {
                let research = TrainingKnowledgeService.shared.getExercisesRanked(for: muscleGroup, goal: profile.primaryGoal)
                if !research.isEmpty && !exercises.isEmpty {
                    func sanitize(_ s: String) -> String {
                        var t = s.lowercased()
                        if let r = t.range(of: "(") { t.removeSubrange(r.lowerBound..<t.endIndex) }
                        return t.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    func stripCitations(_ s: String) -> String {
                        var t = s
                        let patterns = [
                            #"contentReference\[.*?\]\{.*?\}"#,
                            #"\\[image [^\\]]*\\]"#,
                            #"contentReference\[.*?\]"#,
                            #"\{index=\d+\}"#
                        ]
                        for p in patterns {
                            if let r = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                                t = r.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
                            }
                        }
                        return t.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    var used = Set<String>()
                    var recs: [ExerciseRecommendation] = []
                    for rex in research {
                        let rname = sanitize(rex.name)
                        if let match = exercises.first(where: { ex in
                            let aname = sanitize(ex.name)
                            return aname.contains(rname) || rname.contains(aname)
                        }) {
                            if used.insert(match.name.lowercased()).inserted {
                                let emgFirst = TextSanitizer.firstSentence(from: rex.emgActivation)
                                let reason = "\(match.isCompound ? "Compound" : "Isolation"): \(emgFirst). Hypertrophy: \(rex.effectiveness.hypertrophy), Strength: \(rex.effectiveness.strength). Safety: \(rex.safetyLevel.rawValue)."
                                recs.append(ExerciseRecommendation(exerciseName: match.name, priority: recs.count+1, sets: nil, reasoning: reason))
                            }
                        }
                        if recs.count >= 5 { break }
                    }
                    if !recs.isEmpty { exerciseRecommendations = recs }
                }
                if exerciseRecommendations.isEmpty {
                    exerciseRecommendations = exercises.prefix(5).enumerated().map { idx, ex in
                        ExerciseRecommendation(exerciseName: ex.name, priority: idx+1, sets: nil, reasoning: "Available exercise")
                    }
                }
            }
            var allTypeCount = 0
            if availableExercises.isEmpty {
                let allType = try await supabaseService.getExercisesByWorkoutTypeFuzzy(session.workoutType)
                allTypeCount = allType.count
            }
            exerciseDebug = ExerciseDebug(requestedWorkoutType: session.workoutType, requestedGroup: muscleGroup, matchedCount: availableExercises.count, allForTypeCount: allTypeCount, error: nil)
            error = availableExercises.isEmpty ? "No exercises found for \(muscleGroup.capitalized) in \(session.workoutType.capitalized)." : nil
        } catch {
            // Graceful fallback on any AI/API failure.
            // Attempt research-based local ranking first; otherwise show available exercises.
            let research = TrainingKnowledgeService.shared.getExercisesRanked(for: muscleGroup, goal: profile.primaryGoal)
            if !research.isEmpty && !availableExercises.isEmpty {
                func sanitize(_ s: String) -> String {
                    var t = s.lowercased()
                    if let r = t.range(of: "(") { t.removeSubrange(r.lowerBound..<t.endIndex) }
                    return t.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                func stripCitations(_ s: String) -> String {
                    var t = s
                    let patterns = [
                        #"contentReference\[.*?\]\{.*?\}"#,
                        #"\\[image [^\\]]*\\]"#,
                        #"contentReference\[.*?\]"#,
                        #"\{index=\d+\}"#
                    ]
                    for p in patterns {
                        if let r = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                            t = r.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
                        }
                    }
                    return t.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                var used = Set<String>()
                var recs: [ExerciseRecommendation] = []
                for rex in research {
                    let rname = sanitize(rex.name)
                    if let match = availableExercises.first(where: { ex in
                        let aname = sanitize(ex.name)
                        return aname.contains(rname) || rname.contains(aname)
                    }) {
                        if used.insert(match.name.lowercased()).inserted {
                            let emgFirst = TextSanitizer.firstSentence(from: rex.emgActivation)
                            let reason = "\(match.isCompound ? "Compound" : "Isolation"): \(emgFirst). Hypertrophy: \(rex.effectiveness.hypertrophy), Strength: \(rex.effectiveness.strength). Safety: \(rex.safetyLevel.rawValue)."
                            recs.append(ExerciseRecommendation(exerciseName: match.name, priority: recs.count+1, sets: nil, reasoning: reason))
                        }
                    }
                    if recs.count >= 5 { break }
                }
                if !recs.isEmpty { exerciseRecommendations = recs }
            }
            // If still empty, show first few available exercises plainly
            if exerciseRecommendations.isEmpty && !availableExercises.isEmpty {
                exerciseRecommendations = availableExercises.prefix(5).enumerated().map { idx, ex in
                    ExerciseRecommendation(exerciseName: ex.name, priority: idx+1, sets: nil, reasoning: "Available exercise")
                }
            }
            // Clear volume metadata on failure
            self.totalSetsRecommended = nil
            self.targetSetsRange = nil
            self.error = error.localizedDescription
        }
    }

    // Calendar / History
    @Published var sessionsByDay: [Date: [WorkoutSession]] = [:]

    func loadSessionsForMonth(containing date: Date) async {
        guard let profile else { return }
        isLoading = true; defer { isLoading = false }
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
        let end = cal.date(byAdding: DateComponents(month: 1), to: start) ?? date
        do {
            let sessions = try await supabaseService.getSessionsBetween(userId: profile.id, start: start, end: end)
            let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
            sessionsByDay = grouped
        } catch { self.error = error.localizedDescription }
    }

    func sessions(on day: Date) -> [WorkoutSession] {
        let key = Calendar.current.startOfDay(for: day)
        return sessionsByDay[key] ?? []
    }

    // MARK: - Helpers
    func defaultPriority(for workoutType: String) -> [String] {
        switch workoutType {
        case "push": return ["chest", "shoulders", "triceps"]
        case "pull": return ["back", "biceps", "rear_delts"]
        default: return ["quads", "hamstrings", "glutes", "calves"]
        }
    }

    func allowedGroups(for workoutType: String) -> [String] {
        switch workoutType {
        case "push": return ["chest", "shoulders", "triceps"]
        case "pull": return ["back", "biceps", "rear_delts"]
        default: return ["quads", "hamstrings", "glutes", "calves"]
        }
    }

    private func sanitizePriority(for workoutType: String, proposed: [String]) -> [String] {
        let allowed = Set(allowedGroups(for: workoutType))
        let filtered = proposed.map { $0.lowercased() }.filter { allowed.contains($0) }
        if !filtered.isEmpty { return filtered }
        return defaultPriority(for: workoutType)
    }

    func refreshMusclePriority() async {
        guard let profile, let type = currentSession?.workoutType else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let order = try await openAIService.getMuscleGroupPriority(profile: profile, workoutType: type, recentWorkouts: [])
            muscleGroupPriority = sanitizePriority(for: type, proposed: order)
            muscleGroupOrderNote = buildOrderNote(for: type, priority: muscleGroupPriority)
        } catch {
            muscleGroupPriority = defaultPriority(for: type)
            muscleGroupOrderNote = buildOrderNote(for: type, priority: muscleGroupPriority)
        }
    }

    // MARK: - Group planning
    @Published var groupTargets: [String:Int] = [:] // group -> number of exercises to complete
    @Published var groupCompletedExercises: [String:Int] = [:] // group -> completed exercise count
    @Published var muscleGroupOrderNote: String? = nil

    func setTarget(for group: String, count: Int) {
        let key = group.lowercased()
        groupTargets[key] = count
        groupCompletedExercises[key] = 0
    }

    func markExerciseCompleted(exerciseId: UUID, group: String) {
        completedExerciseIds.insert(exerciseId)
        let key = group.lowercased()
        let newVal = (groupCompletedExercises[key] ?? 0) + 1
        groupCompletedExercises[key] = newVal
        let target = groupTargets[key] ?? 0
        if target > 0 && newVal >= target { completedGroups.insert(key) }
    }

    func recommendExerciseCount(for group: String) -> (count: Int, reason: String) {
        guard let profile = profile else {
            return (3, "Default recommendation")
        }

        // NEW: Query volume landmarks from research
        if let landmarks = TrainingKnowledgeService.shared.getVolumeLandmarks(
            for: group,
            goal: profile.primaryGoal,
            experience: profile.fitnessLevel
        ) {
            let count = landmarks.exerciseCount
            let eps = TextSanitizer.sanitizedResearchText(landmarks.exercisesPerSession)
            let mav = TextSanitizer.sanitizedResearchText(landmarks.mav)
            let sps = TextSanitizer.sanitizedResearchText(landmarks.setsPerSessionRange)
            let reason = """
            Research recommends \(eps) for \(displayName(group)) at your \(profile.fitnessLevel.displayName) level with \(profile.primaryGoal.displayName) goal.

            Volume targets:
            • Optimal weekly sets: \(mav) (Maximum Adaptive Volume)
            • Sets per session: \(sps)
            • This allows progressive overload within your recovery capacity.
            """
            return (count, reason)
        }

        // Fallback to existing heuristic if no research data
        let exp = profile.fitnessLevel
        let goal = profile.primaryGoal
        let freq = profile.workoutFrequency

        var base = exp == .beginner ? 2 : (exp == .intermediate ? 3 : 4)
        if goal == .bulk { base += 1 }
        if freq >= 5 { base = max(2, base - 1) }

        let reason = "Based on your \(exp.displayName.lowercased()) level, \(goal.displayName.lowercased()) goal, and training \(freq)x/week, \(base) exercises for \(displayName(group)) balances stimulus and recovery."
        return (min(max(base, 1), 5), reason)
    }

    private func displayName(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func selectExercise(_ exercise: Exercise) async { currentExercise = exercise; await getSetRepRecommendation(for: exercise) }

    func getSetRepRecommendation(for exercise: Exercise) async {
        guard let profile else { error = "Profile missing"; return }
        isLoading = true; defer { isLoading = false }
        do { setRepRecommendation = try await openAIService.getSetRepRecommendation(profile: profile, exercise: exercise, previousSets: []) }
        catch { self.error = error.localizedDescription }
    }

    func completeWorkout(notes: String?) async {
        guard let session = currentSession else { return }
        isLoading = true; defer { isLoading = false }
        do {
            try await supabaseService.completeWorkoutSession(sessionId: session.id, notes: notes)
            currentSession = nil
        } catch { self.error = error.localizedDescription }
    }
}

extension WorkoutManager {
    func buildOrderNote(for workoutType: String, priority: [String]) -> String {
        let normalized = priority.map { $0.replacingOccurrences(of: "_", with: " ") }
        let orderText = normalized.prefix(3).map { $0.capitalized }.joined(separator: " → ")
        let principles = TrainingKnowledgeService.shared.getOrderingPrinciples()
        let raw = principles?.optimalSequence.components(separatedBy: ".").first ?? "Compound lifts first, then accessories"
        let guidance = TextSanitizer.sanitizedResearchText(raw)
        return "Recommended order: \(orderText). Rationale: \(guidance)."
    }
}

struct ExerciseDebug {
    let requestedWorkoutType: String
    let requestedGroup: String
    let matchedCount: Int
    let allForTypeCount: Int
    let error: String?
}

// MARK: - Smart Recommendation (Home)
struct SmartWorkoutRecommendation {
    let workoutType: String
    let muscleGroups: [String]
    let daysSinceLastTrained: Int
    let reasoning: String
    let suggestedExercises: [(name: String, sets: Int)]
}

extension WorkoutManager {
    func getSmartRecommendation() async -> SmartWorkoutRecommendation? {
        guard let profile = profile else { return nil }
        let userId = profile.id
        let cal = Calendar.current
        let now = Date()
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: now) else { return defaultRecommendation() }
        do {
            let sessions = try await SupabaseService.shared.getSessionsBetween(userId: userId, start: weekAgo, end: now).filter { $0.completedAt != nil }
            if sessions.isEmpty { return defaultRecommendation() }
            let lastTrained = analyzeLastTrainedDates(sessions: sessions)
            guard let oldest = lastTrained.sorted(by: { $0.value < $1.value }).first else { return defaultRecommendation() }
            let daysSince = cal.dateComponents([.day], from: oldest.value, to: now).day ?? 0
            let (type, groups) = determineWorkoutType(primaryGroup: oldest.key)
            let isDeload = await detectDeload(for: oldest.key, in: sessions)
            let ex = await getSuggestedExercises(for: groups.first ?? oldest.key, isDeload: isDeload)
            let reasoning: String
            if daysSince >= 3 { reasoning = "✅ Optimal recovery window (\(daysSince) days since last \(oldest.key) workout)" }
            else if daysSince >= 2 { reasoning = "⚠️ Adequate recovery (\(daysSince) days rest)" }
            else { reasoning = "Consider training different muscle groups (only \(daysSince) days since last \(oldest.key) workout)" }
            let finalReason = isDeload ? reasoning + " — last session was a deload, so volume is reduced today." : reasoning
            return SmartWorkoutRecommendation(workoutType: type, muscleGroups: groups, daysSinceLastTrained: daysSince, reasoning: finalReason, suggestedExercises: ex)
        } catch {
            return defaultRecommendation()
        }
    }

    private func analyzeLastTrainedDates(sessions: [WorkoutSession]) -> [String: Date] {
        var last: [String: Date] = [:]
        for s in sessions {
            let groups = getMuscleGroupsForWorkoutType(s.workoutType)
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

    private func getMuscleGroupsForWorkoutType(_ type: String) -> [String] {
        let t = type.lowercased()
        if t.contains("push") { return ["chest", "shoulders", "triceps"] }
        if t.contains("pull") { return ["back", "biceps", "shoulders"] }
        if t.contains("leg") { return ["quads", "hamstrings", "glutes", "calves"] }
        if t.contains("upper") { return ["chest", "back", "shoulders", "biceps", "triceps"] }
        if t.contains("lower") { return ["quads", "hamstrings", "glutes", "calves"] }
        return [t]
    }

    private func determineWorkoutType(primaryGroup: String) -> (type: String, groups: [String]) {
        switch primaryGroup.lowercased() {
        case "chest", "shoulders", "triceps": return ("push", ["chest", "shoulders", "triceps"])
        case "back", "biceps": return ("pull", ["back", "biceps"])
        case "quads", "hamstrings", "glutes", "calves": return ("legs", ["quads", "hamstrings", "glutes"]) // calves optional
        default: return (primaryGroup.lowercased(), [primaryGroup])
        }
    }

    private func getSuggestedExercises(for muscleGroup: String, isDeload: Bool) async -> [(name: String, sets: Int)] {
        let goal = profile?.primaryGoal ?? .bulk
        let level = profile?.fitnessLevel ?? .intermediate
        let freq = max(profile?.workoutFrequency ?? 3, 1)
        let rankedDetailsSlice = TrainingKnowledgeService.shared.getExercisesRanked(for: muscleGroup, goal: goal).prefix(3)
        let rankedDetails = Array(rankedDetailsSlice)
        let volume = TrainingKnowledgeService.shared.getVolumeLandmarks(for: muscleGroup, goal: goal, experience: level)
        let weeklyMin = volume?.setsPerWeekRange.lowerBound ?? 10
        var targetPerSession = max(weeklyMin / freq, 6)
        if isDeload { targetPerSession = max(Int(Double(targetPerSession) * 0.7), 4) }

        // Map research names to DB exercises to fetch history
        var dbExercises: [String: Exercise] = [:]
        if let all = try? await SupabaseService.shared.getAllExercises() {
            for d in all {
                dbExercises[d.name.lowercased()] = d
            }
        }

        // Compute historical average sets per session for each candidate
        struct Hist { let name: String; let avgSets: Double }
        var history: [Hist] = []
        let firstName = rankedDetails.first?.name
        for (idx, ex) in rankedDetails.enumerated() {
            let key = ex.name.lowercased()
            if let match = dbExercises[key] {
                if let uid = profile?.id, let sets = try? await SupabaseService.shared.getExerciseHistory(userId: uid, exerciseId: match.id, limit: 50) {
                    // average sets per session (group by session)
                    let grouped = Dictionary(grouping: sets, by: { $0.sessionId })
                    let perSessionCounts = grouped.values.map { $0.count }
                    if let avg = perSessionCounts.isEmpty ? nil : Double(perSessionCounts.reduce(0,+)) / Double(perSessionCounts.count) {
                        history.append(Hist(name: ex.name, avgSets: max(avg, 2)))
                        continue
                    }
                }
            }
            // No history fallback
            let base = (idx == 0) ? 4.0 : 3.0
            history.append(Hist(name: ex.name, avgSets: base))
        }

        // Scale historical averages to meet targetPerSession
        let baseSum = history.reduce(0.0) { $0 + $1.avgSets }
        var allocated: [(String, Int)] = []
        if baseSum > 0 {
            var total = 0
            for h in history {
                let raw = (Double(targetPerSession) * (h.avgSets / baseSum))
                let sets = max(Int(round(raw)), h.name == firstName ? 3 : 2)
                allocated.append((h.name, sets))
                total += sets
            }
            // Adjust to match target exactly by +/- 1 on last items
            var diff = targetPerSession - total
            var i = 0
            while diff != 0 && !allocated.isEmpty {
                let idx = i % allocated.count
                if diff > 0 {
                    allocated[idx].1 += 1; diff -= 1
                } else if diff < 0 {
                    if allocated[idx].1 > (idx == 0 ? 3 : 2) { allocated[idx].1 -= 1; diff += 1 }
                }
                i += 1
            }
        }

        return allocated.isEmpty ? history.map { ($0.name, Int($0.avgSets)) } : allocated
    }

    private func detectDeload(for muscleGroup: String, in sessions: [WorkoutSession]) async -> Bool {
        // Find most recent session that included this muscle group
        let candidates = sessions.sorted { $0.startedAt > $1.startedAt }
        for s in candidates {
            let groups = getMuscleGroupsForWorkoutType(s.workoutType)
            if groups.contains(where: { $0 == muscleGroup || $0 == muscleGroup.lowercased() }) {
                let notes = (s.notes ?? "").lowercased()
                if notes.contains("deload") || notes.contains("recovery week") { return true }
                if let plan = try? await SupabaseService.shared.getSessionPlan(sessionId: s.id) {
                    let p = (plan.notes ?? "").lowercased()
                    if p.contains("deload") || p.contains("recovery week") { return true }
                }
                return false
            }
        }
        return false
    }

    private func defaultRecommendation() -> SmartWorkoutRecommendation {
        SmartWorkoutRecommendation(
            workoutType: "push",
            muscleGroups: ["chest", "shoulders", "triceps"],
            daysSinceLastTrained: 0,
            reasoning: "Start your training journey!",
            suggestedExercises: [("Barbell Bench Press", 3), ("Pull-Ups", 3), ("Back Squat", 3)]
        )
    }
}

// MARK: - Volume and Research Helpers (UI access)
extension WorkoutManager {
    func setsCompletedToday(for group: String) -> Int {
        let key = group.lowercased()
        let ids = Set(availableExercises.filter { $0.muscleGroup.lowercased() == key }.map { $0.id })
        if ids.isEmpty {
            // Fallback: count only current exercise sets
            let curId = currentExercise?.id
            return completedSets.filter { $0.exerciseId == curId }.count
        }
        return completedSets.filter { ids.contains($0.exerciseId) }.count
    }

    func volumeLandmarks(for group: String) -> VolumeLandmarks? {
        guard let profile else { return nil }
        return TrainingKnowledgeService.shared.getVolumeLandmarks(
            for: group,
            goal: profile.primaryGoal,
            experience: profile.fitnessLevel
        )
    }

    func researchDetails(for exerciseName: String) -> ExerciseDetail? {
        TrainingKnowledgeService.shared.findExercise(named: exerciseName)
    }

    // MARK: - Volume progress helpers for ExerciseSelectionView
    func getSetsCompletedForGroup(_ group: String) -> Int {
        let lower = group.lowercased()
        let groupExercises = completedSets.filter { set in
            availableExercises.first(where: { $0.id == set.exerciseId })?.muscleGroup.lowercased() == lower
        }
        return groupExercises.count
    }

    func getVolumeTarget(for group: String) -> (min: Int, max: Int, status: String)? {
        guard let profile else { return nil }
        guard let landmarks = TrainingKnowledgeService.shared.getVolumeLandmarks(
            for: group,
            goal: profile.primaryGoal,
            experience: profile.fitnessLevel
        ) else { return nil }
        let mavRange = landmarks.setsPerWeekRange
        let sessionsPerWeek = profile.workoutFrequency >= 5 ? 2 : 1
        let minSetsToday = mavRange.lowerBound / max(sessionsPerWeek, 1)
        let maxSetsToday = mavRange.upperBound / max(sessionsPerWeek, 1)
        let status = "Training \(sessionsPerWeek)x/week → \(mavRange.lowerBound)-\(mavRange.upperBound) total sets"
        return (minSetsToday, maxSetsToday, status)
    }
}
