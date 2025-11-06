import Foundation

// MARK: - Goals / Presets (UI)
enum Goal: String, CaseIterable, Identifiable, Hashable, Codable {
    case bulk = "bulk"
    case cut = "cut"
    case maintain = "maintain"
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum Preset: String, CaseIterable, Identifiable, Hashable, Codable {
    case push = "push"
    case pull = "pull"
    case legs = "legs"
    var id: String { rawValue }
    var displayName: String {
        switch self { case .push: return "Push Day"; case .pull: return "Pull Day"; case .legs: return "Legs" }
    }
}

// MARK: - Supabase-mapped Models

// User Profile -> profiles table
struct UserProfile: Codable, Identifiable {
    let id: UUID
    var fullName: String?
    var fitnessLevel: FitnessLevel
    var primaryGoal: Goal
    var workoutFrequency: Int
    var gymType: GymType
    var injuriesLimitations: [String]
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case fitnessLevel = "fitness_level"
        case primaryGoal = "primary_goal"
        case workoutFrequency = "workout_frequency"
        case gymType = "gym_type"
        case injuriesLimitations = "injuries_limitations"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum FitnessLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }
}

enum GymType: String, Codable, CaseIterable, Identifiable {
    case commercial
    case home
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .commercial: return "Full Gym Access"
        case .home: return "Home Gym"
        case .minimal: return "Minimal Equipment"
        }
    }
}

// Exercise Library -> exercises table
struct Exercise: Codable, Identifiable {
    let id: UUID
    let name: String
    let muscleGroup: String
    let workoutType: String
    let equipment: [String]
    let difficulty: FitnessLevel
    let isCompound: Bool
    let description: String
    let formCues: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, equipment, difficulty, description
        case muscleGroup = "muscle_group"
        case workoutType = "workout_type"
        case isCompound = "is_compound"
        case formCues = "form_cues"
    }
}

// Workout Session -> workout_sessions table
struct WorkoutSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let workoutType: String
    let startedAt: Date
    var completedAt: Date?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, notes
        case userId = "user_id"
        case workoutType = "workout_type"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

// Exercise Set -> exercise_sets table
struct ExerciseSet: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let exerciseId: UUID
    var setNumber: Int
    var reps: Int
    var weight: Double
    var rpe: Int?
    var restSeconds: Int?
    let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, reps, weight, rpe
        case sessionId = "session_id"
        case exerciseId = "exercise_id"
        case setNumber = "set_number"
        case restSeconds = "rest_seconds"
        case completedAt = "completed_at"
    }
}

// MARK: - Analytics Models
struct AnalyticsData {
    let overview: OverviewStats
    let strengthProgress: [ExerciseProgress]
    let volumeByMuscle: [MuscleVolumeData]
    let workoutDates: [Date]
    let personalRecords: [PersonalRecord]
    let splitBalance: [SplitBalanceData]
}

// MARK: - Session Planning
// Complete session plan with all exercises and targets
struct SessionPlan: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let userId: UUID
    let workoutType: String
    let muscleGroups: [String]
    let generatedAt: Date
    let exercises: [PlannedExercise]
    let volumeTargets: [MuscleVolumeTarget]
    let safetyNotes: [String]
    let estimatedDuration: Int // minutes

    struct PlannedExercise: Codable, Identifiable {
        let id: UUID
        let exerciseName: String
        let exerciseId: UUID?
        let muscleGroup: String
        let orderIndex: Int
        let isCompound: Bool
        let targetSets: Int
        let targetRepsMin: Int
        let targetRepsMax: Int
        let restSeconds: Int
        let intensityTechnique: IntensityTechnique?
        let rationale: String // Why this exercise was chosen
        let safetyModification: String? // Any injury-related modifications
        let isCompleted: Bool
        let actualSets: Int
    }

    struct MuscleVolumeTarget: Codable, Identifiable {
        let id = UUID()
        let muscleGroup: String
        let targetSetsToday: Int
        let weeklyTarget: Int
        let completedThisWeek: Int
        let reasoning: String
    }
}

// Intensity techniques
enum IntensityTechnique: String, Codable {
    case dropSets = "Drop Sets"
    case restPause = "Rest-Pause"
    case supersets = "Supersets"
    case none = "None"

    var description: String {
        switch self {
        case .dropSets:
            return "After reaching failure, reduce weight 20-30% and continue for 4-6 more reps. Repeat 2-3 times."
        case .restPause:
            return "After reaching failure, rest 15-20 seconds, then continue for 3-5 more reps. Repeat 2 times."
        case .supersets:
            return "Perform two exercises back-to-back with minimal rest between them."
        case .none:
            return "Standard straight sets with normal rest periods."
        }
    }
}

// Session adaptation tracking
struct SessionAdaptation: Codable {
    let timestamp: Date
    let exerciseId: UUID
    let reason: AdaptationReason
    let action: AdaptationAction
    let notes: String

    enum AdaptationReason: String, Codable {
        case failedSet = "Failed Set"
        case painReported = "Pain Reported"
        case equipmentUnavailable = "Equipment Unavailable"
        case userRequest = "User Request"
        case fatigue = "Excessive Fatigue"
    }

    enum AdaptationAction: String, Codable {
        case reducedWeight = "Reduced Weight"
        case reducedSets = "Reduced Sets"
        case substitutedExercise = "Substituted Exercise"
        case addedRest = "Extended Rest"
        case removedTechnique = "Removed Intensity Technique"
    }
}

struct OverviewStats {
    let totalWorkouts: Int
    let totalSets: Int
    let currentStreak: Int
    let personalRecordsThisMonth: Int
    let averageStrengthIncrease: Double
}

struct ExerciseProgress {
    let exerciseName: String
    let dataPoints: [ProgressDataPoint]
    struct ProgressDataPoint {
        let date: Date
        let weight: Double
        let estimatedOneRM: Double
    }
}

struct MuscleVolumeData: Identifiable {
    let id = UUID()
    let muscleGroup: String
    let sets: Int
    let targetMin: Int
    let targetMax: Int
    var percentage: Double {
        let midpoint = Double(targetMin + targetMax) / 2.0
        return midpoint > 0 ? min(Double(sets) / midpoint, 1.0) : 0
    }
}

struct PersonalRecord: Identifiable {
    let id = UUID()
    let exerciseName: String
    let weight: Double
    let reps: Int
    let date: Date
    let isNewRecord: Bool
}

struct SplitBalanceData: Identifiable {
    let id = UUID()
    let category: String // e.g., "Push (Chest/Shoulders/Triceps)"
    let muscleGroups: [String]
    let workoutCount: Int
    let recommendedCount: Int
    var percentage: Double {
        let denom = max(Double(recommendedCount), 1.0)
        return min(Double(workoutCount) / denom, 1.0)
    }
    var isLow: Bool { workoutCount < recommendedCount }
}

// Stretch -> stretches table
struct Stretch: Codable, Identifiable {
    let id: UUID
    let name: String
    let workoutType: String
    let durationSeconds: Int
    let description: String
    let formCues: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case workoutType = "workout_type"
        case durationSeconds = "duration_seconds"
        case formCues = "form_cues"
    }
}

// (Removed legacy SessionPlan/PlanExercise/VolumeContext definitions)
