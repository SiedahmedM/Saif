import Foundation

class SessionPlanGenerator {
    static let shared = SessionPlanGenerator()
    private init() {}

    func generatePlan(
        workoutType: String,
        muscleGroups: [String],
        userProfile: UserProfile,
        recentSessions: [WorkoutSession],
        sessionId: UUID,
        userId: UUID
    ) async throws -> SessionPlan {
        // Load preferences and map to exercise names for prioritization
        var favoriteNames: Set<String> = []
        var avoidNames: Set<String> = []
        do {
            let prefs = try await SupabaseService.shared.getExercisePreferences(userId: userId)
            let favIds = prefs.filter { $0.preferenceLevel == .favorite }.map { $0.exerciseId }
            let avoidIds = prefs.filter { $0.preferenceLevel == .avoid }.map { $0.exerciseId }
            if !favIds.isEmpty, let favEx = try? await SupabaseService.shared.getExercisesByIds(favIds) {
                favoriteNames = Set(favEx.map { $0.name.lowercased() })
            }
            if !avoidIds.isEmpty, let avoidEx = try? await SupabaseService.shared.getExercisesByIds(avoidIds) {
                avoidNames = Set(avoidEx.map { $0.name.lowercased() })
            }
        } catch {
            print("❌ [SessionPlanGenerator.generatePlan] preferences load failed: \(error)")
        }
        let recovery = calculateRecoveryStatus(muscleGroups: muscleGroups, recentSessions: recentSessions)
        let volumeTargets = try await calculateVolumeTargets(muscleGroups: muscleGroups, userProfile: userProfile, recentSessions: recentSessions)
        let injuries = InjuryRuleEngine.shared.parseInjuries(from: userProfile.injuriesLimitations.joined(separator: ", "))

        var planned: [SessionPlan.PlannedExercise] = []
        var order = 0
        for group in muscleGroups {
            let groupTarget = volumeTargets.first { $0.muscleGroup == group }
            let targetSets = groupTarget?.targetSetsToday ?? 12
            let ranked = TrainingKnowledgeService.shared.getExercisesRanked(for: group, goal: userProfile.primaryGoal)
            var safeList = InjuryRuleEngine.shared.filterExercises(ranked, injuries: injuries)

            // Preferences-aware prioritization: favorites first, neutral next, avoid last (unless no alternatives)
            func weight(_ name: String) -> Int { favoriteNames.contains(name.lowercased()) ? 2 : (avoidNames.contains(name.lowercased()) ? 0 : 1) }
            let sorted = safeList.sorted { weight($0.exercise.name) > weight($1.exercise.name) }
            // Keep recommendations concise (max ~2 short lines) sourced from volume guidelines
            // Rationale strings are generated elsewhere; keep length under control when assembling below.
            // If everything is avoided, keep original order to avoid empty plans
            safeList = sorted

            // Skip avoid-tier unless no alternatives exist
            let anyNonAvoid = safeList.contains { weight($0.exercise.name) > 0 && $0.status != .avoid }
            let filteredForSelection = anyNonAvoid ? safeList.filter { weight($0.exercise.name) > 0 && $0.status != .avoid } : safeList
            let compounds = filteredForSelection.filter { $0.exercise.isCompound }
            let isolations = filteredForSelection.filter { !$0.exercise.isCompound }

            // Compounds (1-2)
            let cCount = min(2, compounds.count)
            for i in 0..<cCount {
                let item = compounds[i]
                let ex = item.exercise
                let rr = determineRepRange(goal: userProfile.primaryGoal, isCompound: true)
                planned.append(SessionPlan.PlannedExercise(
                    id: UUID(),
                    exerciseName: ex.name,
                    exerciseId: nil,
                    muscleGroup: group,
                    orderIndex: order,
                    isCompound: true,
                    targetSets: i == 0 ? 4 : 3,
                    targetRepsMin: rr.min,
                    targetRepsMax: rr.max,
                    restSeconds: 180,
                    intensityTechnique: nil,
                    rationale: generateRationale(exercise: ex, position: i == 0 ? "primary" : "secondary", muscleGroup: group, technique: nil),
                    safetyModification: item.note,
                    isCompleted: false,
                    actualSets: 0
                ))
                order += 1
            }

            // Accessories to fill target
            let baseSetsDone = cCount == 0 ? 0 : (cCount == 1 ? 4 : 7)
            let remaining = max(targetSets - baseSetsDone, 0)
            let aCount = min(2, isolations.count)
            let setsPerAccessory = max(remaining / max(aCount, 1), 2)
            for i in 0..<aCount {
                let item = isolations[i]
                let ex = item.exercise
                let rr = determineRepRange(goal: userProfile.primaryGoal, isCompound: false)
                let technique: IntensityTechnique? = {
                    guard userProfile.fitnessLevel != .beginner, i == aCount - 1 else { return nil }
                    let equip = ex.equipment.lowercased()
                    if equip.contains("machine") || equip.contains("cable") { return .dropSets }
                    if equip.contains("dumbbell") || equip.contains("barbell") { return .restPause }
                    return .dropSets
                }()
                planned.append(SessionPlan.PlannedExercise(
                    id: UUID(),
                    exerciseName: ex.name,
                    exerciseId: nil,
                    muscleGroup: group,
                    orderIndex: order,
                    isCompound: false,
                    targetSets: setsPerAccessory,
                    targetRepsMin: rr.min,
                    targetRepsMax: rr.max,
                    restSeconds: 90,
                    intensityTechnique: technique,
                    rationale: generateRationale(exercise: ex, position: "accessory", muscleGroup: group, technique: technique),
                    safetyModification: item.note,
                    isCompleted: false,
                    actualSets: 0
                ))
                order += 1
            }
        }

        let notes = generateSafetyNotes(injuries: injuries, exercises: planned)
        let duration = estimateSessionDuration(exercises: planned)

        return SessionPlan(
            id: UUID(),
            sessionId: sessionId,
            userId: userId,
            workoutType: workoutType,
            muscleGroups: muscleGroups,
            generatedAt: Date(),
            exercises: planned,
            volumeTargets: volumeTargets,
            safetyNotes: notes,
            estimatedDuration: duration
        )
    }

    private func calculateRecoveryStatus(muscleGroups: [String], recentSessions: [WorkoutSession]) -> [String: Int] {
        let cal = Calendar.current
        let now = Date()
        var res: [String: Int] = [:]
        for g in muscleGroups {
            let last = recentSessions.filter { getMuscleGroupsForWorkoutType($0.workoutType).contains(g.lowercased()) }
                .sorted { $0.startedAt > $1.startedAt }
                .first
            if let last { res[g] = cal.dateComponents([.day], from: last.startedAt, to: now).day ?? 0 } else { res[g] = 7 }
        }
        return res
    }

    private func calculateVolumeTargets(muscleGroups: [String], userProfile: UserProfile, recentSessions: [WorkoutSession]) async throws -> [SessionPlan.MuscleVolumeTarget] {
        var targets: [SessionPlan.MuscleVolumeTarget] = []
        let cal = Calendar.current
        let weekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        let weekSessions = recentSessions.filter { $0.startedAt >= weekAgo }
        for g in muscleGroups {
            if let lm = TrainingKnowledgeService.shared.getVolumeLandmarks(for: g, goal: userProfile.primaryGoal, experience: userProfile.fitnessLevel) {
                let weekly = (lm.setsPerWeekRange.lowerBound + lm.setsPerWeekRange.upperBound) / 2
                var completed = 0
                for s in weekSessions {
                    if getMuscleGroupsForWorkoutType(s.workoutType).contains(g.lowercased()) {
                        if let sets = try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id) {
                            let exIds = Array(Set(sets.map { $0.exerciseId }))
                            if let exs = try? await SupabaseService.shared.getExercisesByIds(exIds) {
                                let byGroup = exs.reduce(into: Set<UUID>()) { set, ex in if ex.muscleGroup.lowercased() == g.lowercased() { set.insert(ex.id) } }
                                completed += sets.filter { byGroup.contains($0.exerciseId) }.count
                            }
                        }
                    }
                }
                let sessionsPerWeek = userProfile.workoutFrequency >= 5 ? 2 : 1
                let remaining = max(weekly - completed, 0)
                let targetToday = min(remaining, weekly / sessionsPerWeek + 2)
                targets.append(SessionPlan.MuscleVolumeTarget(muscleGroup: g, targetSetsToday: targetToday, weeklyTarget: weekly, completedThisWeek: completed, reasoning: "You've done \(completed)/\(weekly) sets this week for \(g)"))
            } else {
                targets.append(SessionPlan.MuscleVolumeTarget(muscleGroup: g, targetSetsToday: 12, weeklyTarget: 16, completedThisWeek: 0, reasoning: "Default volume target"))
            }
        }
        return targets
    }

    private func determineRepRange(goal: Goal, isCompound: Bool) -> (min: Int, max: Int) {
        if isCompound {
            switch goal { case .bulk: return (6,10); case .cut: return (8,12); case .maintain: return (6,12) }
        } else {
            switch goal { case .bulk: return (10,15); case .cut: return (12,20); case .maintain: return (10,15) }
        }
    }

    private func generateRationale(exercise: ExerciseDetail, position: String, muscleGroup: String, technique: IntensityTechnique?) -> String {
        var r = ""
        switch position {
        case "primary": r = "Primary compound for \(muscleGroup). High effectiveness (\(exercise.effectiveness.hypertrophy))."
        case "secondary": r = "Secondary compound to hit \(muscleGroup) from a different angle."
        default: r = "Accessory exercise for targeted \(muscleGroup) volume."
        }
        if !exercise.emgActivation.isEmpty { r += " Research: \(exercise.emgActivation.prefix(60))..." }
        if let t = technique { r += " Using \(t.rawValue) on final set." }
        return r
    }

    private func generateSafetyNotes(injuries: [String], exercises: [SessionPlan.PlannedExercise]) -> [String] {
        var notes: [String] = []
        if !injuries.isEmpty { notes.append("⚠️ You have \(injuries.joined(separator: ", ")) considerations. Exercises adjusted accordingly.") }
        let techniques = exercises.filter { $0.intensityTechnique != nil }.count
        if techniques > 0 { notes.append("💪 \(techniques) exercise(s) include intensity techniques. Maintain form.") }
        let compounds = exercises.filter { $0.isCompound }.count
        if compounds >= 3 { notes.append("🏋️ High compound volume — rest 3+ minutes between sets.") }
        return notes
    }

    private func estimateSessionDuration(exercises: [SessionPlan.PlannedExercise]) -> Int {
        var total = 5
        for ex in exercises {
            let setsTime = ex.targetSets * 2
            let rest = (ex.targetSets - 1) * (ex.restSeconds / 60)
            total += setsTime + rest
        }
        total += 5
        return total
    }

    private func getMuscleGroupsForWorkoutType(_ type: String) -> [String] {
        let t = type.lowercased()
        if t.contains("push") { return ["chest","shoulders","triceps"] }
        if t.contains("pull") { return ["back","biceps"] }
        if t.contains("leg") { return ["quads","hamstrings","glutes"] }
        if t.contains("upper") { return ["chest","back","shoulders","biceps","triceps"] }
        if t.contains("lower") { return ["quads","hamstrings","glutes","calves"] }
        if t.contains("full") { return ["chest","back","shoulders","quads","hamstrings","biceps","triceps"] }
        return [t]
    }
}
