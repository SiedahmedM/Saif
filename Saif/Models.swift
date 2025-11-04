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
