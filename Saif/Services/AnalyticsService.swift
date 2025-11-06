import Foundation

enum OverviewRange: String, CaseIterable {
    case week
    case month
    case year
}

class AnalyticsService {
    static let shared = AnalyticsService()
    private init() {}
    
    func getAnalyticsData(userId: UUID, userProfile: UserProfile) async throws -> AnalyticsData {
        let cal = Calendar.current
        let now = Date()
        let threeMonthsAgo = cal.date(byAdding: .month, value: -3, to: now) ?? now
        let sessions = try await SupabaseService.shared.getWorkoutSessions(userId: userId, from: threeMonthsAgo, to: now).filter { $0.completedAt != nil }
        let overview = calculateOverviewStats(sessions: sessions, range: .month)
        let strength: [ExerciseProgress] = [] // TODO: implement
        let volume = try await calculateVolumeByMuscle(sessions: sessions, userProfile: userProfile)
        let dates = sessions.map { $0.startedAt }
        let prs: [PersonalRecord] = [] // TODO: implement
        let balance = calculateSplitBalance(sessions: sessions, userProfile: userProfile, range: .month)
        return AnalyticsData(overview: overview, strengthProgress: strength, volumeByMuscle: volume, workoutDates: dates, personalRecords: prs, splitBalance: balance)
    }
    
    private func rangeStart(for range: OverviewRange, now: Date) -> Date {
        let cal = Calendar.current
        switch range {
        case .week: return cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: return cal.date(byAdding: .month, value: -1, to: now) ?? now
        case .year: return cal.date(byAdding: .year, value: -1, to: now) ?? now
        }
    }

    func getOverviewStats(userId: UUID, userProfile: UserProfile, range: OverviewRange) async throws -> OverviewStats {
        let now = Date()
        let start = rangeStart(for: range, now: now)
        let sessions = try await SupabaseService.shared.getWorkoutSessions(userId: userId, from: start, to: now).filter { $0.completedAt != nil }
        return try await calculateOverviewStatsDetailed(sessions: sessions)
    }

    private func calculateOverviewStats(sessions: [WorkoutSession], range: OverviewRange) -> OverviewStats {
        let cal = Calendar.current
        let now = Date()
        let start = rangeStart(for: range, now: now)
        let inRange = sessions.filter { $0.startedAt >= start }
        // Streak (consecutive days from today with workouts)
        var streak = 0
        var cursor = cal.startOfDay(for: now)
        while inRange.contains(where: { cal.isDate($0.startedAt, inSameDayAs: cursor) }) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return OverviewStats(totalWorkouts: inRange.count, totalSets: 0, currentStreak: streak, personalRecordsThisMonth: 0, averageStrengthIncrease: 0)
    }

    private func calculateOverviewStatsDetailed(sessions: [WorkoutSession]) async throws -> OverviewStats {
        // Total sets
        var totalSets = 0
        for s in sessions {
            let sets = try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id)
            totalSets += sets?.count ?? 0
        }
        // Average strength increase across exercises using estimated 1RM (Epley)
        // Build per-exercise time series of best set per session
        var exerciseToPoints: [UUID: [(date: Date, est1rm: Double)]] = [:]
        for s in sessions {
            if let sets = try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id), !sets.isEmpty {
                // group by exerciseId
                let grouped = Dictionary(grouping: sets, by: { $0.exerciseId })
                for (exId, setsForEx) in grouped {
                    // best set by estimated 1RM within this session
                    let best = setsForEx.max(by: { a, b in est1rm(a) < est1rm(b) })
                    if let best {
                        exerciseToPoints[exId, default: []].append((date: s.startedAt, est1rm: est1rm(best)))
                    }
                }
            }
        }
        var pctIncreases: [Double] = []
        for (_, pts) in exerciseToPoints {
            let sorted = pts.sorted(by: { $0.date < $1.date })
            guard let first = sorted.first?.est1rm, let last = sorted.last?.est1rm, first > 0 else { continue }
            let inc = ((last - first) / first) * 100.0
            pctIncreases.append(inc)
        }
        let avgStrength = pctIncreases.isEmpty ? 0.0 : (pctIncreases.reduce(0, +) / Double(pctIncreases.count))
        // Personal records: count sessions where an exercise exceeds previous best within this period
        var exBest: [UUID: Double] = [:]
        var prCount = 0
        for s in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            if let sets = try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id) {
                let grouped = Dictionary(grouping: sets, by: { $0.exerciseId })
                for (exId, setsForEx) in grouped {
                    if let best = setsForEx.max(by: { est1rm($0) < est1rm($1) }) {
                        let val = est1rm(best)
                        let prev = exBest[exId] ?? -Double.infinity
                        if val > prev && prev > 0 { prCount += 1 }
                        exBest[exId] = max(prev, val)
                    }
                }
            }
        }
        return OverviewStats(totalWorkouts: sessions.count, totalSets: totalSets, currentStreak: 0, personalRecordsThisMonth: prCount, averageStrengthIncrease: avgStrength)
    }

    private func est1rm(_ set: ExerciseSet) -> Double { set.weight * (1.0 + Double(max(set.reps, 1)) / 30.0) }

    // Weekly volume by muscle over last 7 days
    private func calculateVolumeByMuscle(sessions: [WorkoutSession], userProfile: UserProfile) async throws -> [MuscleVolumeData] {
        let cal = Calendar.current
        let now = Date()
        let weekAgo = cal.date(byAdding: .day, value: -7, to: now) ?? now
        let thisWeek = sessions.filter { $0.startedAt >= weekAgo }
        var volume: [String: Int] = [:]
        for s in thisWeek {
            if let sets = try? await SupabaseService.shared.getExerciseSetsForSession(sessionId: s.id), !sets.isEmpty {
                let exIds = Array(Set(sets.map { $0.exerciseId }))
                let exercises = try? await SupabaseService.shared.getExercisesByIds(exIds)
                let exMap = Dictionary(uniqueKeysWithValues: (exercises ?? []).map { ($0.id, $0) })
                for set in sets {
                    if let ex = exMap[set.exerciseId] {
                        let group = TrainingKnowledgeService.shared.normalizeMuscleGroup(ex.muscleGroup)
                        volume[group, default: 0] += 1
                    }
                }
            }
        }
        let groups = ["chest","back","shoulders","quads","hamstrings","glutes","biceps","triceps","calves","core"]
        var result: [MuscleVolumeData] = []
        for g in groups {
            let setsThisWeek = volume[g] ?? 0
            guard setsThisWeek > 0 else { continue }
            if let lm = TrainingKnowledgeService.shared.getVolumeLandmarks(for: g, goal: userProfile.primaryGoal, experience: userProfile.fitnessLevel) {
                result.append(MuscleVolumeData(muscleGroup: g, sets: setsThisWeek, targetMin: lm.setsPerWeekRange.lowerBound, targetMax: lm.setsPerWeekRange.upperBound))
            } else {
                result.append(MuscleVolumeData(muscleGroup: g, sets: setsThisWeek, targetMin: 10, targetMax: 20))
            }
        }
        return result.sorted { $0.sets > $1.sets }
    }

    // Training Split Balance for range
    func calculateSplitBalance(sessions: [WorkoutSession], userProfile: UserProfile, range: OverviewRange) -> [SplitBalanceData] {
        let cal = Calendar.current
        let now = Date()
        let start = rangeStart(for: range, now: now)
        let recent = sessions.filter { $0.startedAt >= start }
        var push = 0, pull = 0, legs = 0
        for s in recent {
            let t = s.workoutType.lowercased()
            if t.contains("push") || t.contains("chest") || t.contains("shoulder") { push += 1 }
            else if t.contains("pull") || t.contains("back") || t.contains("bicep") { pull += 1 }
            else if t.contains("leg") || t.contains("quad") || t.contains("ham") || t.contains("glute") || t.contains("lower") { legs += 1 }
        }
        // Recommended per category scales with range length and weekly frequency
        let days = max(cal.dateComponents([.day], from: start, to: now).day ?? 0, 1)
        let weeks = Double(days) / 7.0
        let recommendedTotal = max(Int(round(Double(userProfile.workoutFrequency) * weeks)), 1)
        // Load user tuning multipliers (defaults to 1.0)
        let defaults = UserDefaults.standard
        let mPush = max(defaults.double(forKey: "splitTune_push"), 0.0) == 0 ? 1.0 : defaults.double(forKey: "splitTune_push")
        let mPull = max(defaults.double(forKey: "splitTune_pull"), 0.0) == 0 ? 1.0 : defaults.double(forKey: "splitTune_pull")
        let mLegs = max(defaults.double(forKey: "splitTune_legs"), 0.0) == 0 ? 1.0 : defaults.double(forKey: "splitTune_legs")
        // Base equal split
        let basePer = Double(recommendedTotal) / 3.0
        let recPush = max(Int(round(basePer * mPush)), 1)
        let recPull = max(Int(round(basePer * mPull)), 1)
        let recLegs = max(Int(round(basePer * mLegs)), 1)
        return [
            SplitBalanceData(category: "Push (Chest/Shoulders/Triceps)", muscleGroups: ["chest","shoulders","triceps"], workoutCount: push, recommendedCount: recPush),
            SplitBalanceData(category: "Pull (Back/Biceps)", muscleGroups: ["back","biceps"], workoutCount: pull, recommendedCount: recPull),
            SplitBalanceData(category: "Legs (Quads/Hams/Glutes)", muscleGroups: ["quads","hamstrings","glutes"], workoutCount: legs, recommendedCount: recLegs)
        ]
    }

    func getSplitBalance(userId: UUID, userProfile: UserProfile, range: OverviewRange) async throws -> [SplitBalanceData] {
        let now = Date()
        let start = rangeStart(for: range, now: now)
        let sessions = try await SupabaseService.shared.getWorkoutSessions(userId: userId, from: start, to: now)
        return calculateSplitBalance(sessions: sessions, userProfile: userProfile, range: range)
    }
}
