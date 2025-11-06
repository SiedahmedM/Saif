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
    @Published var currentPlan: SessionPlan?
    @Published var adaptations: [SessionAdaptation] = []
    @Published var exercisePreferences: [ExercisePreference] = []

    private let supabaseService = SupabaseService.shared
    private let openAIService = OpenAIService.shared
    private var profile: UserProfile?

    func initialize(with profile: UserProfile) { self.profile = profile; Task { await loadExercisePreferences() } }

    // MARK: - Workout State Persistence
    private let workoutStateKey = "active_workout_state"

    func saveWorkoutState() {
        guard let session = currentSession else { clearSavedWorkoutState(); return }
        let state = WorkoutState(
            session: session,
            plan: currentPlan,
            completedSets: completedSets,
            currentExerciseId: currentExercise?.id,
            savedAt: Date()
        )
        do {
            let encoded = try JSONEncoder().encode(state)
            UserDefaults.standard.set(encoded, forKey: workoutStateKey)
            print("✅ Workout state saved")
        } catch {
            print("❌ [saveWorkoutState] failed: \(error)")
        }
    }

    func loadSavedWorkoutState() -> WorkoutState? {
        guard let data = UserDefaults.standard.data(forKey: workoutStateKey) else { return nil }
        do {
            let state = try JSONDecoder().decode(WorkoutState.self, from: data)
            if state.isStale {
                print("⚠️ Saved workout state is stale (>24 hours), ignoring")
                clearSavedWorkoutState(); return nil
            }
            return state
        } catch {
            print("❌ [loadSavedWorkoutState] failed: \(error)")
            clearSavedWorkoutState(); return nil
        }
    }

    func restoreWorkoutState(_ state: WorkoutState) {
        currentSession = state.session
        currentPlan = state.plan
        completedSets = state.completedSets
        if let exId = state.currentExerciseId {
            Task {
                do { currentExercise = try await supabaseService.getExerciseById(exId) }
                catch { print("❌ [restoreWorkoutState] failed: \(error)") }
            }
        }
        print("✅ Workout state restored:\n  - Session: \(state.session.workoutType)\n  - Completed sets: \(state.completedSets.count)\n  - Plan exercises: \(state.plan?.exercises.count ?? 0)")
    }

    func clearSavedWorkoutState() { UserDefaults.standard.removeObject(forKey: workoutStateKey); print("🗑️ Cleared saved workout state") }
    func hasSavedWorkout() -> Bool { loadSavedWorkoutState() != nil }

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
        } catch {
            print("❌ [getWorkoutRecommendation] error: \(error)")
            self.error = "Couldn’t load recommendation. Please try again."
        }
    }

    func startWorkout(workoutType: String, customGroups: [String]? = nil) async {
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
            // Generate full plan for this session
            if let session = currentSession {
                let cal = Calendar.current
                let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                let recent = (try? await supabaseService.getWorkoutSessions(userId: profile.id, from: twoWeeksAgo, to: Date())) ?? []
                let groups = customGroups ?? determineMuscleGroups(for: workoutType)
                let plan = try await SessionPlanGenerator.shared.generatePlan(workoutType: workoutType, muscleGroups: groups, userProfile: profile, recentSessions: recent, sessionId: session.id, userId: profile.id)
                print("🎯 PLAN GENERATED:")
                print("  - Exercises count: \(plan.exercises.count)")
                print("  - Muscle groups: \(plan.muscleGroups)")
                print("  - Volume targets: \(plan.volumeTargets.count)")
                currentPlan = plan
                print("🎯 PLAN SET IN MANAGER:")
                print("  - Plan ID: \(plan.id)")
                print("  - Exercises: \(plan.exercises.count)")
                print("  - Muscle groups: \(plan.muscleGroups)")
            }
            if let customGroups {
                muscleGroupPriority = customGroups.map { $0.lowercased() }
                muscleGroupOrderNote = buildOrderNote(for: workoutType, priority: muscleGroupPriority)
            } else {
                let order = try await openAIService.getMuscleGroupPriority(profile: profile, workoutType: workoutType, recentWorkouts: [])
                muscleGroupPriority = sanitizePriority(for: workoutType, proposed: order)
                muscleGroupOrderNote = buildOrderNote(for: workoutType, priority: muscleGroupPriority)
            }
        } catch {
            print("❌ [startWorkout] error: \(error)")
            self.error = "Couldn’t start workout. Please try again."
        }
        if muscleGroupPriority.isEmpty {
            muscleGroupPriority = defaultPriority(for: workoutType)
            muscleGroupOrderNote = buildOrderNote(for: workoutType, priority: muscleGroupPriority)
        }
        saveWorkoutState()
    }

    func startCustomWorkout(muscleGroups: [String], workoutTypeName: String = "custom") async {
        await startWorkout(workoutType: workoutTypeName, customGroups: muscleGroups)
    }

    func startFreeformWorkout() async {
        guard let profile else { return }
        isLoading = true; defer { isLoading = false }
        do {
            currentSession = try await supabaseService.createWorkoutSession(userId: profile.id, workoutType: "freeform")
            currentPlan = nil
        } catch {
            print("❌ [startFreeformWorkout] error: \(error)")
            self.error = "Couldn’t start freeform workout. Please try again."
        }
    }

    private func determineMuscleGroups(for workoutType: String) -> [String] {
        let t = workoutType.lowercased()
        if t.contains("push") { return ["chest","shoulders","triceps"] }
        if t.contains("pull") { return ["back","biceps"] }
        if t.contains("leg") { return ["quads","hamstrings","glutes"] }
        if t.contains("upper") { return ["chest","back","shoulders"] }
        if t.contains("lower") { return ["quads","hamstrings","glutes","calves"] }
        if t.contains("full") { return ["chest","back","shoulders","quads","hamstrings","biceps","triceps"] }
        return [t]
    }

    func adaptPlan(exerciseId: UUID, reason: SessionAdaptation.AdaptationReason, action: SessionAdaptation.AdaptationAction, notes: String) async {
        guard currentSession != nil else { return }
        let ad = SessionAdaptation(timestamp: Date(), exerciseId: exerciseId, reason: reason, action: action, notes: notes)
        adaptations.append(ad)
        print("🔄 Local plan adapted: \(action.rawValue) - \(reason.rawValue)")
    }

    func getNextPlannedExercise() -> SessionPlan.PlannedExercise? { currentPlan?.exercises.first { !$0.isCompleted } }

    func markExerciseCompleteInPlan(exerciseId: UUID) async {
        // Backward compatibility: find by exercise id match in plan or fallback by name match if needed
        guard var plan = currentPlan else { return }
        if let idx = plan.exercises.firstIndex(where: { $0.exerciseId == exerciseId }) {
            var arr = plan.exercises
            var ex = arr[idx]
            let actual = completedSets.filter { $0.exerciseId == ex.exerciseId }.count
            ex = SessionPlan.PlannedExercise(id: ex.id, exerciseName: ex.exerciseName, exerciseId: ex.exerciseId, muscleGroup: ex.muscleGroup, orderIndex: ex.orderIndex, isCompound: ex.isCompound, targetSets: ex.targetSets, targetRepsMin: ex.targetRepsMin, targetRepsMax: ex.targetRepsMax, restSeconds: ex.restSeconds, intensityTechnique: ex.intensityTechnique, rationale: ex.rationale, safetyModification: ex.safetyModification, isCompleted: true, actualSets: actual)
            arr[idx] = ex
            plan = SessionPlan(id: plan.id, sessionId: plan.sessionId, userId: plan.userId, workoutType: plan.workoutType, muscleGroups: plan.muscleGroups, generatedAt: plan.generatedAt, exercises: arr, volumeTargets: plan.volumeTargets, safetyNotes: plan.safetyNotes, estimatedDuration: plan.estimatedDuration)
            currentPlan = plan
            // Local-only plan: no remote persistence
        }
    }

    func markExerciseCompleteInPlan(for exercise: Exercise) async {
        guard var plan = currentPlan else { return }
        func norm(_ s: String) -> String {
            var t = s.lowercased()
            if let r = t.range(of: #"\(.*\)"#, options: .regularExpression) { t.removeSubrange(r) }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let eName = norm(exercise.name)
        if let idx = plan.exercises.firstIndex(where: { $0.exerciseId == exercise.id }) ?? plan.exercises.firstIndex(where: {
            $0.muscleGroup.lowercased() == exercise.muscleGroup.lowercased() &&
            (norm($0.exerciseName) == eName || norm($0.exerciseName).contains(eName) || eName.contains(norm($0.exerciseName))) &&
            !$0.isCompleted
        }) {
            var arr = plan.exercises
            var ex = arr[idx]
            let actual = completedSets.filter { $0.exerciseId == exercise.id }.count
            ex = SessionPlan.PlannedExercise(id: ex.id, exerciseName: ex.exerciseName, exerciseId: exercise.id, muscleGroup: ex.muscleGroup, orderIndex: ex.orderIndex, isCompound: ex.isCompound, targetSets: ex.targetSets, targetRepsMin: ex.targetRepsMin, targetRepsMax: ex.targetRepsMax, restSeconds: ex.restSeconds, intensityTechnique: ex.intensityTechnique, rationale: ex.rationale, safetyModification: ex.safetyModification, isCompleted: true, actualSets: actual)
            arr[idx] = ex
            plan = SessionPlan(id: plan.id, sessionId: plan.sessionId, userId: plan.userId, workoutType: plan.workoutType, muscleGroups: plan.muscleGroups, generatedAt: plan.generatedAt, exercises: arr, volumeTargets: plan.volumeTargets, safetyNotes: plan.safetyNotes, estimatedDuration: plan.estimatedDuration)
            currentPlan = plan
            // Local-only plan: no remote persistence
        }
    }

    func replaceNextPlannedExercise(group: String, with newExercise: Exercise) async {
        guard var plan = currentPlan else { return }
        if let idx = plan.exercises.firstIndex(where: { $0.muscleGroup.lowercased() == group.lowercased() && !$0.isCompleted }) {
            var arr = plan.exercises
            var ex = arr[idx]
            ex = SessionPlan.PlannedExercise(id: ex.id, exerciseName: newExercise.name, exerciseId: newExercise.id, muscleGroup: ex.muscleGroup, orderIndex: ex.orderIndex, isCompound: newExercise.isCompound, targetSets: ex.targetSets, targetRepsMin: ex.targetRepsMin, targetRepsMax: ex.targetRepsMax, restSeconds: ex.restSeconds, intensityTechnique: ex.intensityTechnique, rationale: ex.rationale, safetyModification: ex.safetyModification, isCompleted: ex.isCompleted, actualSets: ex.actualSets)
            arr[idx] = ex
            plan = SessionPlan(id: plan.id, sessionId: plan.sessionId, userId: plan.userId, workoutType: plan.workoutType, muscleGroups: plan.muscleGroups, generatedAt: plan.generatedAt, exercises: arr, volumeTargets: plan.volumeTargets, safetyNotes: plan.safetyNotes, estimatedDuration: plan.estimatedDuration)
            currentPlan = plan
            // Local-only plan: no remote persistence
        }
    }

    // Replace a specific planned exercise with a chosen database exercise
    func replaceExerciseInPlan(old: SessionPlan.PlannedExercise, new: Exercise) async -> Bool {
        guard var plan = currentPlan else {
            print("❌ [replaceExerciseInPlan] failed: currentPlan is nil")
            return false
        }
        if let idx = plan.exercises.firstIndex(where: { $0.id == old.id }) {
            let replacement = SessionPlan.PlannedExercise(
                id: UUID(),
                exerciseName: new.name,
                exerciseId: new.id,
                muscleGroup: old.muscleGroup,
                orderIndex: old.orderIndex,
                isCompound: new.isCompound,
                targetSets: old.targetSets,
                targetRepsMin: old.targetRepsMin,
                targetRepsMax: old.targetRepsMax,
                restSeconds: old.restSeconds,
                intensityTechnique: old.intensityTechnique,
                rationale: "Swapped: \(new.name) — \(old.rationale)",
                safetyModification: old.safetyModification,
                isCompleted: false,
                actualSets: 0
            )
            var arr = plan.exercises
            arr[idx] = replacement
            plan = SessionPlan(
                id: plan.id,
                sessionId: plan.sessionId,
                userId: plan.userId,
                workoutType: plan.workoutType,
                muscleGroups: plan.muscleGroups,
                generatedAt: plan.generatedAt,
                exercises: arr,
                volumeTargets: plan.volumeTargets,
                safetyNotes: plan.safetyNotes,
                estimatedDuration: plan.estimatedDuration
            )
            currentPlan = plan
            saveWorkoutState()
            print("✅ Replaced \(old.exerciseName) with \(new.name)")
            return true
        }
        print("❌ [replaceExerciseInPlan] failed: old exercise not found in plan")
        return false
    }

    // Reorder a planned exercise within its muscle group
    func movePlannedExercise(plannedId: UUID, inGroup group: String, moveUp: Bool) async -> Bool {
        guard var plan = currentPlan else {
            print("❌ [movePlannedExercise] failed: currentPlan is nil")
            return false
        }
        var arr = plan.exercises
        // Collect indices of this group's exercises in current order
        let groupIndices = arr.enumerated().filter { $0.element.muscleGroup.lowercased() == group.lowercased() }.map { $0.offset }
        guard !groupIndices.isEmpty else { return false }
        // Find position of targeted exercise within the group's sequence
        guard let posInGroup = groupIndices.firstIndex(where: { arr[$0].id == plannedId }) else {
            print("❌ [movePlannedExercise] failed: exercise not found in group")
            return false
        }
        let targetArrayIndex = groupIndices[posInGroup]
        let neighborPos = moveUp ? posInGroup - 1 : posInGroup + 1
        guard neighborPos >= 0 && neighborPos < groupIndices.count else { return false }
        let neighborArrayIndex = groupIndices[neighborPos]
        // Swap elements in the global array
        arr.swapAt(targetArrayIndex, neighborArrayIndex)
        // Normalize orderIndex within the group after swap
        var nextOrder = 0
        for i in arr.indices where arr[i].muscleGroup.lowercased() == group.lowercased() {
            var e = arr[i]
            e = SessionPlan.PlannedExercise(
                id: e.id,
                exerciseName: e.exerciseName,
                exerciseId: e.exerciseId,
                muscleGroup: e.muscleGroup,
                orderIndex: nextOrder,
                isCompound: e.isCompound,
                targetSets: e.targetSets,
                targetRepsMin: e.targetRepsMin,
                targetRepsMax: e.targetRepsMax,
                restSeconds: e.restSeconds,
                intensityTechnique: e.intensityTechnique,
                rationale: e.rationale,
                safetyModification: e.safetyModification,
                isCompleted: e.isCompleted,
                actualSets: e.actualSets
            )
            arr[i] = e
            nextOrder += 1
        }
        plan = SessionPlan(
            id: plan.id,
            sessionId: plan.sessionId,
            userId: plan.userId,
            workoutType: plan.workoutType,
            muscleGroups: plan.muscleGroups,
            generatedAt: plan.generatedAt,
            exercises: arr,
            volumeTargets: plan.volumeTargets,
            safetyNotes: plan.safetyNotes,
            estimatedDuration: plan.estimatedDuration
        )
        currentPlan = plan
        saveWorkoutState()
        return true
    }

    func getExerciseRecommendations(for muscleGroup: String) async {
        guard let profile, let session = currentSession else { error = "Session not started"; return }
        isLoading = true; defer { isLoading = false }
        do {
            // Fetch live exercises from Supabase for this group
            let exercises = try await supabaseService.getExercisesByMuscleGroup(workoutType: session.workoutType, muscleGroup: muscleGroup)
            availableExercises = exercises
            // Preferences surfaced to AI: favorites and avoids by name for this group
            let favIds = Set(exercisePreferences.filter { $0.preferenceLevel == .favorite }.map { $0.exerciseId })
            let avoidIds = Set(exercisePreferences.filter { $0.preferenceLevel == .avoid }.map { $0.exerciseId })
            let favorites = exercises.filter { favIds.contains($0.id) }.map { $0.name }
            let avoids = exercises.filter { avoidIds.contains($0.id) }.map { $0.name }
            // Build AI ordering
            let aiResponse = try await openAIService.getExerciseRecommendations(
                profile: profile,
                workoutType: session.workoutType,
                muscleGroup: muscleGroup,
                availableExercises: exercises,
                recentSets: [],
                favorites: favorites,
                avoids: avoids
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
            print("❌ [getExerciseRecommendations] error: \(error)")
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
            self.error = "Couldn’t load exercises. Showing best available options."
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
        } catch {
            print("❌ [loadSessionsForMonth] error: \(error)")
            self.error = "Couldn’t load history. Please try again later."
        }
    }

    func sessions(on day: Date) -> [WorkoutSession] {
        let key = Calendar.current.startOfDay(for: day)
        return sessionsByDay[key] ?? []
    }

    // MARK: - Helpers
    func defaultPriority(for workoutType: String) -> [String] {
        switch workoutType.lowercased() {
        case "push": return ["chest", "shoulders", "triceps"]
        case "pull": return ["back", "biceps", "rear_delts"]
        case "legs": return ["quads", "hamstrings", "glutes", "calves"]
        case "upper": return ["chest", "back", "shoulders", "biceps", "triceps"]
        case "lower": return ["quads", "hamstrings", "glutes", "calves"]
        case "full body", "full": return ["chest", "back", "quads", "hamstrings"]
        default: return determineMuscleGroups(for: workoutType)
        }
    }

    func allowedGroups(for workoutType: String) -> [String] {
        switch workoutType.lowercased() {
        case "push": return ["chest", "shoulders", "triceps"]
        case "pull": return ["back", "biceps", "rear_delts"]
        case "legs": return ["quads", "hamstrings", "glutes", "calves"]
        case "upper": return ["chest", "back", "shoulders", "biceps", "triceps"]
        case "lower": return ["quads", "hamstrings", "glutes", "calves"]
        case "full body", "full": return ["chest", "back", "shoulders", "quads", "hamstrings", "biceps", "triceps"]
        default: return determineMuscleGroups(for: workoutType)
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
    // Instant-start navigation target
    @Published var selectedMuscleGroup: String? = nil
    // Preferred tab for SessionPlanView (0 = Plan, 1 = Current)
    @Published var sessionPlanPreferredTab: Int = 0

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

    func selectExercise(_ exercise: Exercise) async { currentExercise = exercise; saveWorkoutState(); await getSetRepRecommendation(for: exercise) }

    func getSetRepRecommendation(for exercise: Exercise) async {
        guard let profile else { error = "Profile missing"; return }
        isLoading = true; defer { isLoading = false }
        do { setRepRecommendation = try await openAIService.getSetRepRecommendation(profile: profile, exercise: exercise, previousSets: []) }
        catch {
            print("❌ [getSetRepRecommendation] error: \(error)")
            self.error = "Couldn’t load set/rep guidance. You can still log manually."
        }
    }

    func completeWorkout(notes: String?) async {
        guard let session = currentSession else { return }
        isLoading = true; defer { isLoading = false }
        do {
            try await supabaseService.completeWorkoutSession(sessionId: session.id, notes: notes)
            currentSession = nil
            clearSavedWorkoutState()
            currentPlan = nil
            completedSets.removeAll()
            currentExercise = nil
        } catch {
            print("❌ [completeWorkout] error: \(error)")
            self.error = "Couldn’t complete workout. Please try again."
        }
    }

    // MARK: - Preferences
    func loadExercisePreferences() async {
        guard let profile else { return }
        // Fast cached load, then background refresh
        let cached = await supabaseService.getExercisePreferencesCached(userId: profile.id)
        exercisePreferences = cached
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let fresh = try await self.supabaseService.getExercisePreferences(userId: profile.id)
                await MainActor.run { self.exercisePreferences = fresh }
            } catch { print("❌ [loadExercisePreferences.refresh] \(error)") }
        }
    }

    func setExercisePreference(exerciseId: UUID, level: ExercisePreference.PreferenceLevel, reason: String?) async {
        print("💾 Setting preference:")
        print("  - Exercise ID: \(exerciseId)")
        print("  - Level: \(level.rawValue)")
        guard let profile else {
            print("❌ No profile found")
            showError("Profile not loaded. Please restart app.")
            return
        }
        do {
            try await supabaseService.setExercisePreference(userId: profile.id, exerciseId: exerciseId, level: level, reason: reason)
            await loadExercisePreferences()
        } catch {
            print("❌ [setExercisePreference] failed: \(error)")
            self.error = "Failed to save preference. Please try again."
        }
    }

    func removeExercisePreference(exerciseId: UUID) async {
        guard let profile else { return }
        do {
            try await supabaseService.removeExercisePreference(userId: profile.id, exerciseId: exerciseId)
            await loadExercisePreferences()
        } catch {
            print("❌ [removeExercisePreference] failed: \(error)")
            self.error = "Failed to remove preference. Please try again."
        }
    }

    func isFavorite(_ exerciseId: UUID) -> Bool {
        exercisePreferences.first(where: { $0.exerciseId == exerciseId })?.preferenceLevel == .favorite
    }

    func isAvoided(_ exerciseId: UUID) -> Bool {
        exercisePreferences.first(where: { $0.exerciseId == exerciseId })?.preferenceLevel == .avoid
    }

    // Update / Delete logged sets during active workout
    func updateLoggedSet(setId: UUID, reps: Int, weight: Double, rpe: Int?) async {
        if let idx = completedSets.firstIndex(where: { $0.id == setId }) {
            var s = completedSets[idx]
            s = ExerciseSet(id: s.id, sessionId: s.sessionId, exerciseId: s.exerciseId, setNumber: s.setNumber, reps: reps, weight: weight, rpe: rpe, restSeconds: s.restSeconds, completedAt: s.completedAt)
            completedSets[idx] = s
            do { try await supabaseService.updateExerciseSet(setId: setId, reps: reps, weight: weight, rpe: rpe) } catch {
                print("❌ [updateLoggedSet] failed: \(error)")
                self.error = "Failed to update set remotely. Updated locally."
            }
            saveWorkoutState()
        }
    }

    // MARK: - Coach Helpers
    func profileSnapshot() -> (goal: Goal, fitness: FitnessLevel, gym: GymType, injuries: [String])? {
        guard let profile else { return nil }
        return (goal: profile.primaryGoal, fitness: profile.fitnessLevel, gym: profile.gymType, injuries: profile.injuriesLimitations)
    }

    func recommendedIncrementStep(for exercise: Exercise) -> Int {
        // Mirror logic from analyzeSetPerformance
        let eq = (exercise.equipment.first ?? "").lowercased()
        if eq.contains("machine") { return 10 }
        if eq.contains("barbell") { return 5 }
        if eq.contains("dumbbell") { return 5 }
        if eq.contains("cable") { return 5 }
        if eq.contains("kettlebell") { return 5 }
        return 5
    }

    func deleteLoggedSet(setId: UUID) async {
        if let idx = completedSets.firstIndex(where: { $0.id == setId }) {
            let s = completedSets.remove(at: idx)
            do { try await supabaseService.deleteExerciseSet(setId: setId) } catch {
                print("❌ [deleteLoggedSet] failed: \(error)")
                // keep local deletion even if remote fails
            }
            // If we removed the last set for a planned exercise, mark it not completed
            if var plan = currentPlan {
                if let pidx = plan.exercises.firstIndex(where: { $0.exerciseId == s.exerciseId }) {
                    let stillHas = completedSets.contains(where: { $0.exerciseId == s.exerciseId })
                    if !stillHas {
                        var ex = plan.exercises[pidx]
                        ex = SessionPlan.PlannedExercise(id: ex.id, exerciseName: ex.exerciseName, exerciseId: ex.exerciseId, muscleGroup: ex.muscleGroup, orderIndex: ex.orderIndex, isCompound: ex.isCompound, targetSets: ex.targetSets, targetRepsMin: ex.targetRepsMin, targetRepsMax: ex.targetRepsMax, restSeconds: ex.restSeconds, intensityTechnique: ex.intensityTechnique, rationale: ex.rationale, safetyModification: ex.safetyModification, isCompleted: false, actualSets: 0)
                        var arr = plan.exercises
                        arr[pidx] = ex
                        plan = SessionPlan(id: plan.id, sessionId: plan.sessionId, userId: plan.userId, workoutType: plan.workoutType, muscleGroups: plan.muscleGroups, generatedAt: plan.generatedAt, exercises: arr, volumeTargets: plan.volumeTargets, safetyNotes: plan.safetyNotes, estimatedDuration: plan.estimatedDuration)
                        currentPlan = plan
                    }
                }
            }
            saveWorkoutState()
        }
    }
}

// MARK: - Error helper
extension WorkoutManager {
    fileprivate func showError(_ message: String) {
        self.error = message
    }
}

// MARK: - Real-time Set Recommendations
extension WorkoutManager {
    struct SetRecommendation {
        let message: String
        let icon: String
        let color: Color
        let actionable: Bool
        let suggestedAdjustment: String?
    }

    private func equipmentCategory(for exercise: Exercise) -> String {
        // Try DB field first; fallback to research detail
        if let eq = exercise.equipment.first?.lowercased(), !eq.isEmpty { return eq }
        if let detail = TrainingKnowledgeService.shared.findExercise(named: exercise.name) {
            return detail.equipment.lowercased()
        }
        return ""
    }

    private func defaultStep(for exercise: Exercise) -> Int {
        let eq = equipmentCategory(for: exercise)
        if eq.contains("machine") { return 10 }
        if eq.contains("barbell") { return 5 }
        if eq.contains("dumbbell") { return 5 }
        if eq.contains("cable") { return 5 }
        if eq.contains("kettlebell") { return 5 }
        return 5
    }

    private func roundToStep(_ value: Double, step: Int) -> Int {
        let s = Double(step)
        return max(step, Int((value / s).rounded() * s))
    }

    func analyzeSetPerformance(
        exercise: Exercise,
        setNumber: Int,
        weight: Double,
        reps: Int,
        rpe: Int?,
        targetRepsMin: Int,
        targetRepsMax: Int
    ) -> SetRecommendation? {
        guard let profile else { return nil }

        // Volume landmarks available for future tuning if needed
        _ = TrainingKnowledgeService.shared.getVolumeLandmarks(
            for: exercise.muscleGroup,
            goal: profile.primaryGoal,
            experience: profile.fitnessLevel
        )

        let step = defaultStep(for: exercise)
        let surplus = max(0, reps - targetRepsMax)
        let deficit = max(0, targetRepsMin - reps)

        // 1. Reps too high for goal (hypertrophy target generally ~6-12)
        if profile.primaryGoal == .bulk && reps > 15 {
            // Scale increase by how far above target and user experience; round to equipment step
            var pct: Double = 0.10
            if surplus >= 8 { pct = profile.fitnessLevel == .advanced ? 0.25 : 0.20 }
            else if surplus >= 4 { pct = 0.15 }
            let raw = weight * pct
            let delta = roundToStep(raw, step: step)
            return SetRecommendation(
                message: "That was \(reps) reps - too light for muscle building. Try +10-15 lbs next set to hit 8-12 reps.",
                icon: "arrow.up.circle.fill",
                color: SAIFColors.accent,
                actionable: true,
                suggestedAdjustment: "+\(delta) lbs"
            )
        }

        // 2. Reps too low for goal (on isolations aim for higher reps)
        if profile.primaryGoal == .bulk && reps < 6 && !exercise.isCompound {
            var pct: Double = 0.10
            if deficit >= 4 { pct = 0.15 }
            let raw = weight * pct
            let delta = roundToStep(raw, step: step)
            return SetRecommendation(
                message: "Only \(reps) reps on an isolation exercise. Consider dropping 5-10 lbs to reach 10-15 reps for better hypertrophy.",
                icon: "arrow.down.circle.fill",
                color: .orange,
                actionable: true,
                suggestedAdjustment: "-\(delta) lbs"
            )
        }

        // 3. High RPE early in workout
        if let rpe = rpe, rpe >= 9 && setNumber <= 2 {
            return SetRecommendation(
                message: "RPE \(rpe) on set \(setNumber) - you're working very hard early. Consider resting 3+ minutes or reducing weight to maintain quality for remaining sets.",
                icon: "exclamationmark.triangle.fill",
                color: .orange,
                actionable: true,
                suggestedAdjustment: "Rest 3+ min"
            )
        }

        // 4. Perfect execution in target range, manageable RPE
        if reps >= targetRepsMin && reps <= targetRepsMax && (rpe ?? 7) <= 8 {
            return SetRecommendation(
                message: "Perfect! Right in the target rep range with good form reserve. Keep this weight for next set.",
                icon: "checkmark.circle.fill",
                color: .green,
                actionable: false,
                suggestedAdjustment: nil
            )
        }

        // 5. Ready for progression if well above range with low perceived exertion
        if reps > targetRepsMax && (rpe ?? 10) <= 7 {
            // Smaller bump than the "too light" case; within-range overperformance
            var pct: Double = exercise.isCompound ? 0.10 : 0.07
            if surplus >= 4 { pct += 0.05 }
            let delta = roundToStep(weight * pct, step: step)
            return SetRecommendation(
                message: "You hit \(reps) reps and had more in the tank (RPE \(rpe ?? 7)). Time to increase weight! Try +5-10 lbs next workout.",
                icon: "flame.fill",
                color: SAIFColors.primary,
                actionable: true,
                suggestedAdjustment: "+\(delta) lbs"
            )
        }

        // 6. Rest reminder for compounds (early sets)
        if exercise.isCompound && setNumber < 4 {
            return SetRecommendation(
                message: "Compound lift - rest 2-3 minutes before your next set to maintain strength.",
                icon: "timer",
                color: SAIFColors.mutedText,
                actionable: false,
                suggestedAdjustment: nil
            )
        }

        return nil
    }
}

// MARK: - Workout Summary
extension WorkoutManager {
    struct WorkoutSummaryData {
        // Plan metrics
        let plannedExercises: Int
        let plannedSets: Int
        let plannedDuration: Int
        let plannedVolume: Int

        // Actual metrics
        let actualExercises: Int
        let actualSets: Int
        let actualDuration: Int
        let actualVolume: Int

        // Performance
        let overachievement: Double
        let efficiency: String
        let prCount: Int
        let volumePRMuscleGroups: [String]

        // Highlights
        let topExercises: [ExerciseHighlight]
        let insights: [String]
        let nextWorkoutSuggestion: String
    }

    struct ExerciseHighlight: Identifiable {
        let id = UUID()
        let exerciseName: String
        let achievement: String
        let metric: String
    }

    func generateWorkoutSummary() async -> WorkoutSummaryData {
        guard let plan = currentPlan, let session = currentSession else {
            return WorkoutSummaryData(
                plannedExercises: 0,
                plannedSets: 0,
                plannedDuration: 0,
                plannedVolume: 0,
                actualExercises: Set(completedSets.map { $0.exerciseId }).count,
                actualSets: completedSets.count,
                actualDuration: 0,
                actualVolume: completedSets.reduce(0) { $0 + $1.reps },
                overachievement: 0,
                efficiency: "",
                prCount: 0,
                volumePRMuscleGroups: [],
                topExercises: [],
                insights: [],
                nextWorkoutSuggestion: "Rest and recover!"
            )
        }

        // Planned metrics
        let plannedSets = plan.exercises.reduce(0) { $0 + $1.targetSets }
        // Approximate planned volume using planned target reps midpoint
        let plannedVolume = plan.exercises.reduce(0) { acc, ex in
            let avgReps = (ex.targetRepsMin + ex.targetRepsMax) / 2
            return acc + (avgReps * ex.targetSets)
        }

        // Actual metrics
        let actualSets = completedSets.count
        let actualVolume = completedSets.reduce(0) { $0 + $1.reps }
        let actualDuration = Int(Date().timeIntervalSince(session.startedAt) / 60)
        let actualExercises = Set(completedSets.map { $0.exerciseId }).count

        // Performance comparisons
        let overachievement = Double(actualSets - plannedSets) / Double(max(plannedSets, 1))
        let efficiency: String = {
            if actualDuration < plan.estimatedDuration { return "\(plan.estimatedDuration - actualDuration) min faster" }
            if actualDuration > plan.estimatedDuration { return "\(actualDuration - plan.estimatedDuration) min longer" }
            return "Right on schedule"
        }()

        // PRs and highlights
        let prCount = await detectNewPRs()
        let volumePRGroups = await detectVolumePRs()
        let highlights = await generateHighlights()
        let insights = generateInsights(overachievement: overachievement, duration: actualDuration, prCount: prCount)
        let nextSuggestion = await suggestNextWorkout()

        return WorkoutSummaryData(
            plannedExercises: plan.exercises.count,
            plannedSets: plannedSets,
            plannedDuration: plan.estimatedDuration,
            plannedVolume: plannedVolume,
            actualExercises: actualExercises,
            actualSets: actualSets,
            actualDuration: actualDuration,
            actualVolume: actualVolume,
            overachievement: overachievement,
            efficiency: efficiency,
            prCount: prCount,
            volumePRMuscleGroups: volumePRGroups,
            topExercises: highlights,
            insights: insights,
            nextWorkoutSuggestion: nextSuggestion
        )
    }

    private func detectNewPRs() async -> Int {
        guard let profile else { return 0 }
        var prCount = 0
        var seen: Set<UUID> = []
        for set in completedSets {
            if !seen.insert(set.exerciseId).inserted { continue }
            if let historical = try? await supabaseService.getExerciseHistory(userId: profile.id, exerciseId: set.exerciseId, limit: 200) {
                let previousMax = historical.max(by: { $0.weight < $1.weight })?.weight ?? 0
                if let bestToday = completedSets.filter({ $0.exerciseId == set.exerciseId }).max(by: { $0.weight < $1.weight }), bestToday.weight > previousMax {
                    prCount += 1
                }
            }
        }
        return prCount
    }

    private func detectVolumePRs() async -> [String] {
        guard let profile, let session = currentSession else { return [] }
        // Today's volume per muscle group (reps)
        var volumeToday: [String:Int] = [:]
        do {
            let exIds = Array(Set(completedSets.map { $0.exerciseId }))
            let exercises = try await supabaseService.getExercisesByIds(exIds)
            var byId: [UUID: Exercise] = [:]
            for e in exercises { byId[e.id] = e }
            for set in completedSets {
                if let ex = byId[set.exerciseId] {
                    let key = ex.muscleGroup.lowercased()
                    volumeToday[key, default: 0] += set.reps
                }
            }
        } catch { /* ignore */ }

        // Historical max per group (last ~30 days)
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -30, to: session.startedAt) ?? session.startedAt
        var volumeMax: [String:Int] = [:]
        do {
            let sessions = try await supabaseService.getSessionsBetween(userId: profile.id, start: start, end: Date())
            for s in sessions {
                if let sets = try? await supabaseService.getExerciseSetsForSession(sessionId: s.id), !sets.isEmpty {
                    let ids = Array(Set(sets.map { $0.exerciseId }))
                    if let exs = try? await supabaseService.getExercisesByIds(ids) {
                        var byId: [UUID: Exercise] = [:]
                        for e in exs { byId[e.id] = e }
                        var volByGroup: [String:Int] = [:]
                        for st in sets {
                            if let ex = byId[st.exerciseId] {
                                volByGroup[ex.muscleGroup.lowercased(), default: 0] += st.reps
                            }
                        }
                        for (g, v) in volByGroup { volumeMax[g] = max(volumeMax[g] ?? 0, v) }
                    }
                }
            }
        } catch { /* ignore */ }

        var prs: [String] = []
        for (g, v) in volumeToday { if v > (volumeMax[g] ?? 0) { prs.append(g) } }
        return prs
    }

    private func generateHighlights() async -> [ExerciseHighlight] {
        guard let profile else { return [] }
        var highlights: [ExerciseHighlight] = []
        let groups = Dictionary(grouping: completedSets, by: { $0.exerciseId })
        for (exerciseId, sets) in groups {
            guard let exercise = try? await supabaseService.getExerciseById(exerciseId) else { continue }
            if let bestSet = sets.max(by: { $0.weight < $1.weight }) {
                let historical = try? await supabaseService.getExerciseHistory(userId: profile.id, exerciseId: exerciseId, limit: 200)
                let isPR = historical?.allSatisfy { $0.weight < bestSet.weight } ?? false
                highlights.append(ExerciseHighlight(
                    exerciseName: exercise.name,
                    achievement: isPR ? "New PR! 🔥" : "Best set",
                    metric: "\(Int(bestSet.weight)) lbs × \(bestSet.reps)"
                ))
            }
        }
        return Array(highlights.prefix(3))
    }

    private func generateInsights(overachievement: Double, duration: Int, prCount: Int) -> [String] {
        var insights: [String] = []
        if overachievement > 0.1 { insights.append("💪 You exceeded your plan by \(Int(overachievement * 100))%!") }
        if prCount > 0 { insights.append("🎯 \(prCount) new personal record\(prCount == 1 ? "" : "s") hit today!") }
        if duration < (currentPlan?.estimatedDuration ?? 60) - 10 { insights.append("⚡ Efficient workout - you finished ahead of schedule!") }
        if completedSets.allSatisfy({ ($0.rpe ?? 10) <= 8 }) { insights.append("📈 Great form reserve - you're leaving room to grow!") }
        return insights
    }

    private func suggestNextWorkout() async -> String {
        guard let session = currentSession else { return "Rest and recover!" }
        let type = session.workoutType.lowercased()
        if type.contains("push") { return "Next up: Pull day (Back & Biceps) to balance your training" }
        if type.contains("pull") { return "Next up: Legs day to complete the cycle" }
        if type.contains("leg") { return "Next up: Push day to restart the rotation" }
        return "Recover and get ready for your next session"
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

// MARK: - Smart Substitute
extension WorkoutManager {
    func getSmartSubstitute(for exercise: SessionPlan.PlannedExercise) async -> (exercise: Exercise, reasoning: String)? {
        guard let profile = profile, let session = currentSession else { return nil }

        // 1) Knowledge candidates in same group
        let ranked = TrainingKnowledgeService.shared.getExercisesRanked(for: exercise.muscleGroup, goal: profile.primaryGoal)
        // 2) Match compound/isolation
        let patternMatched = ranked.filter { $0.isCompound == exercise.isCompound }
        // 3) Exclude exercises already in plan for this group
        let plannedNamesLower = Set((currentPlan?.exercises
            .filter { $0.muscleGroup.lowercased() == exercise.muscleGroup.lowercased() }
            .map { $0.exerciseName.lowercased() } ?? []))
        let filtered = patternMatched.filter { !plannedNamesLower.contains($0.name.lowercased()) && !$0.name.lowercased().contains(exercise.exerciseName.lowercased()) }

        // 4) Avoid recent usage (last 3 sessions or ~14 days)
        var recentExerciseNamesLower: Set<String> = []
        do {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
            let sessions = try await supabaseService.getSessionsBetween(userId: profile.id, start: start, end: Date())
            let last = Array(sessions.sorted(by: { $0.startedAt > $1.startedAt }).prefix(3))
            for s in last {
                if let sets = try? await supabaseService.getExerciseSetsForSession(sessionId: s.id), !sets.isEmpty {
                    let ids = Array(Set(sets.map { $0.exerciseId }))
                    if let exs = try? await supabaseService.getExercisesByIds(ids) {
                        for e in exs { recentExerciseNamesLower.insert(e.name.lowercased()) }
                    }
                }
            }
        } catch {
            print("❌ [getSmartSubstitute.sessions] error: \(error)")
        }

        func sanitize(_ s: String) -> String {
            var t = s.lowercased()
            if let r = t.range(of: "(") { t.removeSubrange(r.lowerBound..<t.endIndex) }
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // DB exercises available for this group
        let dbExercises: [Exercise]
        if !availableExercises.isEmpty {
            dbExercises = availableExercises.filter { $0.muscleGroup.lowercased() == exercise.muscleGroup.lowercased() }
        } else {
            do {
                dbExercises = try await supabaseService.getExercisesByMuscleGroup(workoutType: session.workoutType, muscleGroup: exercise.muscleGroup)
            } catch {
                print("❌ [getSmartSubstitute.dbExercises] error: \(error)")
                dbExercises = []
            }
        }

        let oldDetail = TrainingKnowledgeService.shared.findExercise(named: exercise.exerciseName)
        var best: (Exercise, ExerciseDetail, Int)? = nil
        for detail in filtered {
            guard let match = dbExercises.first(where: { ex in
                let a = sanitize(ex.name), b = sanitize(detail.name)
                return a == b || a.contains(b) || b.contains(a)
            }) else { continue }
            if recentExerciseNamesLower.contains(match.name.lowercased()) { continue }
            var score = TrainingKnowledgeService.shared.effectivenessScore(for: detail, goal: profile.primaryGoal)
            if let old = oldDetail {
                let eqOld = old.equipment.lowercased(), eqNew = detail.equipment.lowercased()
                if (eqOld.contains("barbell") && eqNew.contains("dumbbell")) || (eqOld.contains("dumbbell") && eqNew.contains("cable")) || (eqOld.contains("machine") != eqNew.contains("machine")) { score += 1 }
                let on = old.name.lowercased(), nn = detail.name.lowercased()
                if (on.contains("flat") && nn.contains("incline")) || (on.contains("incline") && nn.contains("flat")) { score += 1 }
            }
            if best == nil || score > (best?.2 ?? 0) { best = (match, detail, score) }
        }

        guard let (newExercise, newDetail, _) = best else { return nil }
        let reason: String = {
            var parts: [String] = []
            if let old = oldDetail {
                parts.append("similar activation (\(old.effectiveness.hypertrophy) → \(newDetail.effectiveness.hypertrophy))")
                let eqOld = old.equipment.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let eqNew = newDetail.equipment.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !eqOld.isEmpty && !eqNew.isEmpty && eqOld.lowercased() != eqNew.lowercased() { parts.append("equipment variety (\(eqOld) → \(eqNew))") }
                let from = exercise.exerciseName.lowercased(), to = newExercise.name.lowercased()
                if (from.contains("flat") && to.contains("incline")) || (from.contains("incline") && to.contains("flat")) { parts.append("different angle for variety") }
            }
            let joined = parts.joined(separator: ", ")
            return joined.isEmpty ? "Similar movement pattern with useful variety" : joined.capitalized
        }()

        return (newExercise, reason)
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
            var ex = await getSuggestedExercises(for: groups.first ?? oldest.key, isDeload: isDeload)
            // Injury-aware filtering
            let injuriesText = (profile.injuriesLimitations).joined(separator: ", ")
            let injuries = InjuryRuleEngine.shared.parseInjuries(from: injuriesText)
            if !injuries.isEmpty {
                let details = TrainingKnowledgeService.shared.getExercises(for: groups.first ?? oldest.key)
                let safe = InjuryRuleEngine.shared.filterExercises(details, injuries: injuries)
                    .filter { $0.status != .avoid }
                    .map { $0.exercise.name.lowercased() }
                let filtered = ex.filter { safe.contains($0.name.lowercased()) }
                if !filtered.isEmpty { ex = filtered }
            }
            let reasoning: String
            if daysSince >= 3 { reasoning = "✅ Optimal recovery window (\(daysSince) days since last \(oldest.key) workout)" }
            else if daysSince >= 2 { reasoning = "⚠️ Adequate recovery (\(daysSince) days rest)" }
            else { reasoning = "Consider training different muscle groups (only \(daysSince) days since last \(oldest.key) workout)" }
            var finalReason = isDeload ? reasoning + " — last session was a deload, so volume is reduced today." : reasoning
            if !injuriesText.isEmpty { finalReason += "\n✅ Exercises selected are adapted for: \(injuries.joined(separator: ", "))" }
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

        // Fetch only relevant DB exercises for this muscle + workout type
        let workoutType = determineWorkoutType(primaryGroup: muscleGroup).type
        guard let dbExercises = try? await SupabaseService.shared.getExercisesByMuscleGroup(workoutType: workoutType, muscleGroup: muscleGroup) else {
            // Fallback simple distribution
            return rankedDetails.enumerated().map { idx, ex in (ex.name, idx == 0 ? 4 : 3) }
        }
        var dbExerciseMap: [String: Exercise] = [:]
        for ex in dbExercises { dbExerciseMap[ex.name.lowercased()] = ex }

        struct Hist { let name: String; let avgSets: Double }
        var history: [Hist] = []
        let firstName = rankedDetails.first?.name

        // Fetch histories in parallel for matched exercises
        await withTaskGroup(of: (String, Double?).self) { group in
            for (idx, ex) in rankedDetails.enumerated() {
                let key = ex.name.lowercased()
                if let match = dbExerciseMap[key], let uid = profile?.id {
                    group.addTask {
                        if let sets = try? await SupabaseService.shared.getExerciseHistory(userId: uid, exerciseId: match.id, limit: 50) {
                            let grouped = Dictionary(grouping: sets, by: { $0.sessionId })
                            let perSessionCounts = grouped.values.map { $0.count }
                            if !perSessionCounts.isEmpty {
                                let avg = Double(perSessionCounts.reduce(0, +)) / Double(perSessionCounts.count)
                                return (ex.name, max(avg, 2.0))
                            }
                        }
                        return (ex.name, nil)
                    }
                } else {
                    // No match in DB - fallback now
                    let base = (idx == 0) ? 4.0 : 3.0
                    history.append(Hist(name: ex.name, avgSets: base))
                }
            }
            for await (name, avgSets) in group {
                if let avg = avgSets { history.append(Hist(name: name, avgSets: avg)) }
                else { history.append(Hist(name: name, avgSets: name == firstName ? 4.0 : 3.0)) }
            }
        }

        // Ensure all candidates present
        if history.count < rankedDetails.count {
            for (idx, ex) in rankedDetails.enumerated() where !history.contains(where: { $0.name == ex.name }) {
                history.append(Hist(name: ex.name, avgSets: idx == 0 ? 4.0 : 3.0))
            }
        }

        // Scale to targetPerSession
        let baseSum = history.reduce(0.0) { $0 + $1.avgSets }
        var allocated: [(String, Int)] = []
        if baseSum > 0 {
            var total = 0
            for h in history {
                let raw = Double(targetPerSession) * (h.avgSets / baseSum)
                let sets = max(Int(round(raw)), h.name == firstName ? 3 : 2)
                allocated.append((h.name, sets))
                total += sets
            }
            // Adjust to exact target with safety cap
            var diff = targetPerSession - total
            var i = 0
            while diff != 0 && !allocated.isEmpty && i < 100 {
                let idx = i % allocated.count
                if diff > 0 { allocated[idx].1 += 1; diff -= 1 }
                else if diff < 0 {
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
                    let joined = plan.safetyNotes.joined(separator: " ").lowercased()
                    if joined.contains("deload") || joined.contains("recovery week") { return true }
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

// MARK: - Timeout helper
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

struct TimeoutError: Error {}

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
