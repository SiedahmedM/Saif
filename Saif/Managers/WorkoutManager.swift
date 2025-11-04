import Foundation
import SwiftUI

@MainActor
class WorkoutManager: ObservableObject {
    @Published var currentSession: WorkoutSession?
    @Published var currentExercise: Exercise?
    @Published var completedSets: [ExerciseSet] = []
    @Published var workoutRecommendation: WorkoutRecommendation?
    @Published var exerciseRecommendations: [ExerciseRecommendation] = []
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
            exerciseRecommendations = try await openAIService.getExerciseRecommendations(profile: profile, workoutType: session.workoutType, muscleGroup: muscleGroup, availableExercises: exercises, recentSets: [])
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
                                recs.append(ExerciseRecommendation(exerciseName: match.name, priority: recs.count+1, reasoning: reason))
                            }
                        }
                        if recs.count >= 5 { break }
                    }
                    if !recs.isEmpty { exerciseRecommendations = recs }
                }
                if exerciseRecommendations.isEmpty {
                    exerciseRecommendations = exercises.prefix(5).enumerated().map { idx, ex in
                        ExerciseRecommendation(exerciseName: ex.name, priority: idx+1, reasoning: "Available exercise")
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
                            recs.append(ExerciseRecommendation(exerciseName: match.name, priority: recs.count+1, reasoning: reason))
                        }
                    }
                    if recs.count >= 5 { break }
                }
                if !recs.isEmpty { exerciseRecommendations = recs }
            }
            // If still empty, show first few available exercises plainly
            if exerciseRecommendations.isEmpty && !availableExercises.isEmpty {
                exerciseRecommendations = availableExercises.prefix(5).enumerated().map { idx, ex in
                    ExerciseRecommendation(exerciseName: ex.name, priority: idx+1, reasoning: "Available exercise")
                }
            }
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
        // Simple heuristic: beginners lower volume, bulk higher volume; frequency balances volume
        let exp = profile?.fitnessLevel ?? .beginner
        let goal = profile?.primaryGoal ?? .maintain
        let freq = profile?.workoutFrequency ?? 3
        var base = exp == .beginner ? 2 : (exp == .intermediate ? 3 : 4)
        if goal == .bulk { base += 1 }
        if freq >= 5 { base = max(2, base - 1) }
        let reason = "Based on your \(exp.displayName.lowercased()) level, \(goal.displayName.lowercased()) goal, and training \(freq)x/week, \(base) exercises for \(group.replacingOccurrences(of: "_", with: " ")) balances stimulus and recovery."
        return (min(max(base,1),5), reason)
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
