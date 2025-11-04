import Foundation
import Supabase

// MARK: - Supabase Configuration
class SupabaseService {
    static let shared = SupabaseService()

    private let client: SupabaseClient

    private init() {
        let supabaseURL = URL(string: Config.supabaseURL)!
        let supabaseKey = Config.supabaseAnonKey

        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )
    }

    // MARK: - Authentication

    func signUp(email: String, password: String) async throws -> User {
        let response = try await client.auth.signUp(
            email: email,
            password: password
        )
        return response.user
    }

    func signIn(email: String, password: String) async throws -> Session {
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )
        return session
    }

    func signOut() async throws { try await client.auth.signOut() }

    func getCurrentUser() async throws -> User? { try await client.auth.session.user }

    // MARK: - Profile Management

    func createProfile(_ profile: UserProfile) async throws {
        try await client.database
            .from("profiles")
            .insert(profile)
            .execute()
    }

    func getProfile(userId: UUID) async throws -> UserProfile {
        let profiles: [UserProfile] = try await client.database
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        guard let profile = profiles.first else { throw SupabaseError.noUser }
        return profile
    }

    struct UpdateProfilePayload: Encodable {
        let full_name: String?
        let fitness_level: String
        let primary_goal: String
        let workout_frequency: Int
        let gym_type: String
        let injuries_limitations: [String]
        let updated_at: Date
    }

    func updateProfile(_ profile: UserProfile) async throws {
        let payload = UpdateProfilePayload(
            full_name: profile.fullName,
            fitness_level: profile.fitnessLevel.rawValue,
            primary_goal: profile.primaryGoal.rawValue,
            workout_frequency: profile.workoutFrequency,
            gym_type: profile.gymType.rawValue,
            injuries_limitations: profile.injuriesLimitations,
            updated_at: Date()
        )
        try await client.database
            .from("profiles")
            .update(payload)
            .eq("id", value: profile.id.uuidString)
            .execute()
    }

    // MARK: - Workout Sessions

    struct NewWorkoutSession: Encodable {
        let user_id: String
        let workout_type: String
        let started_at: Date
    }
    func createWorkoutSession(userId: UUID, workoutType: String) async throws -> WorkoutSession {
        let payload = NewWorkoutSession(user_id: userId.uuidString, workout_type: workoutType, started_at: Date())
        let response: WorkoutSession = try await client.database
            .from("workout_sessions")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    struct CompleteSessionPayload: Encodable { let completed_at: Date; let notes: String? }
    func completeWorkoutSession(sessionId: UUID, notes: String? = nil) async throws {
        let payload = CompleteSessionPayload(completed_at: Date(), notes: notes)
        try await client.database
            .from("workout_sessions")
            .update(payload)
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    func getRecentWorkoutSessions(userId: UUID, limit: Int = 10) async throws -> [WorkoutSession] {
        let response: [WorkoutSession] = try await client.database
            .from("workout_sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return response
    }

    func getLastCompletedSession(userId: UUID) async throws -> WorkoutSession? {
        let sessions: [WorkoutSession] = try await client.database
            .from("workout_sessions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("completed_at", ascending: false)
            .limit(10)
            .execute()
            .value
        return sessions.first(where: { $0.completedAt != nil })
    }

    // MARK: - Exercise Sets

    struct NewExerciseSet: Encodable {
        let session_id: String
        let exercise_id: String
        let set_number: Int
        let reps: Int
        let weight: Double
        let rpe: Int?
        let rest_seconds: Int?
        let completed_at: Date
    }
    func logExerciseSet(_ set: ExerciseSet) async throws -> ExerciseSet {
        let payload = NewExerciseSet(
            session_id: set.sessionId.uuidString,
            exercise_id: set.exerciseId.uuidString,
            set_number: set.setNumber,
            reps: set.reps,
            weight: set.weight,
            rpe: set.rpe,
            rest_seconds: set.restSeconds,
            completed_at: set.completedAt
        )
        let response: ExerciseSet = try await client.database
            .from("exercise_sets")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func getExerciseSetsForSession(sessionId: UUID) async throws -> [ExerciseSet] {
        let response: [ExerciseSet] = try await client.database
            .from("exercise_sets")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .order("completed_at", ascending: true)
            .execute()
            .value
        return response
    }

    func getExercisesByIds(_ ids: [UUID]) async throws -> [Exercise] {
        guard !ids.isEmpty else { return [] }
        let idStrings = ids.map { $0.uuidString }
        let response: [Exercise] = try await client.database
            .from("exercises")
            .select()
            .in("id", values: idStrings)
            .execute()
            .value
        return response
    }

    func getExerciseHistory(userId: UUID, exerciseId: UUID, limit: Int = 20) async throws -> [ExerciseSet] {
        let sessions = try await getRecentWorkoutSessions(userId: userId, limit: 50)
        let sessionIds = sessions.map { $0.id.uuidString }

        let response: [ExerciseSet] = try await client.database
            .from("exercise_sets")
            .select()
            .in("session_id", values: sessionIds)
            .eq("exercise_id", value: exerciseId.uuidString)
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return response
    }

    // MARK: - Exercise Library

    func getAllExercises() async throws -> [Exercise] {
        let response: [Exercise] = try await client.database
            .from("exercises")
            .select()
            .execute()
            .value
        return response
    }

    func getExercisesByWorkoutType(_ workoutType: String) async throws -> [Exercise] {
        let response: [Exercise] = try await client.database
            .from("exercises")
            .select()
            .eq("workout_type", value: workoutType)
            .execute()
            .value
        return response
    }

    func getExercisesByMuscleGroup(workoutType: String, muscleGroup: String) async throws -> [Exercise] {
        // Try multiple case/spacing variants to be resilient to stored data
        let variants = muscleGroupSearchVariants(muscleGroup)
        let wVariants = workoutTypeSearchVariants(workoutType)
        var aggregated: [UUID: Exercise] = [:]
        for wt in wVariants {
            for v in variants {
                let items: [Exercise] = try await client.database
                    .from("exercises")
                    .select()
                    .ilike("workout_type", value: "%\(wt)%")
                    .ilike("muscle_group", value: "%\(v)%")
                    .execute()
                    .value
                for ex in items { aggregated[ex.id] = ex }
            }
        }
        // If still nothing, fetch all for workout type so the UI can show a helpful message
        if aggregated.isEmpty {
            var allForType: [Exercise] = []
            for wt in wVariants {
                let items: [Exercise] = try await client.database
                    .from("exercises")
                    .select()
                    .ilike("workout_type", value: "%\(wt)%")
                    .execute()
                    .value
                allForType.append(contentsOf: items)
            }
            return allForType
        }
        return Array(aggregated.values)
    }

    private func muscleGroupSearchVariants(_ raw: String) -> [String] {
        let base = raw.lowercased()
        var s: Set<String> = [base]
        s.insert(base.replacingOccurrences(of: "_", with: " "))
        s.insert(base.replacingOccurrences(of: " ", with: "_"))
        if base.contains("rear") && base.contains("delt") {
            s.insert("rear delts"); s.insert("rear_delts"); s.insert("rear deltoids"); s.insert("rear_deltoids")
        }
        return Array(s)
    }

    private func workoutTypeSearchVariants(_ raw: String) -> [String] {
        let base = raw.lowercased()
        var s: Set<String> = [base]
        s.insert(base.capitalized)
        return Array(s)
    }

    // Fuzzy by workout type only
    func getExercisesByWorkoutTypeFuzzy(_ workoutType: String) async throws -> [Exercise] {
        let vars = workoutTypeSearchVariants(workoutType)
        var res: [Exercise] = []
        for wt in vars {
            let items: [Exercise] = try await client.database
                .from("exercises")
                .select()
                .ilike("workout_type", value: "%\(wt)%")
                .execute()
                .value
            res.append(contentsOf: items)
        }
        return res
    }

    func getExercisesByDifficulty(_ difficulty: FitnessLevel, workoutType: String) async throws -> [Exercise] {
        let response: [Exercise] = try await client.database
            .from("exercises")
            .select()
            .eq("workout_type", value: workoutType)
            .eq("difficulty", value: difficulty.rawValue)
            .execute()
            .value
        return response
    }

    // MARK: - Stretches

    func getStretchesForWorkoutType(_ workoutType: String) async throws -> [Stretch] {
        let response: [Stretch] = try await client.database
            .from("stretches")
            .select()
            .eq("workout_type", value: workoutType)
            .execute()
            .value
        return response
    }

    // Optional convenience: fetch sessions between dates by client-side filtering
    func getSessionsBetween(userId: UUID, start: Date, end: Date) async throws -> [WorkoutSession] {
        let recent = try await getRecentWorkoutSessions(userId: userId, limit: 200)
        return recent.filter { $0.startedAt >= start && $0.startedAt < end }
    }

    // MARK: - Session Plans

    struct SessionPlanCreate: Encodable {
        let session_id: String
        let user_id: String
        let workout_type: String
        let target_sets_min: Int
        let target_sets_max: Int
        let total_sets_planned: Int
        let volume_context: VolumeContext
        let exercises: [PlanExercise]
        let notes: String?
    }

    struct SessionPlanUpdate: Encodable {
        let target_sets_min: Int?
        let target_sets_max: Int?
        let total_sets_planned: Int?
        let volume_context: VolumeContext?
        let exercises: [PlanExercise]?
        let notes: String?
        let updated_at: Date = Date()
    }

    func upsertSessionPlan(
        sessionId: UUID,
        userId: UUID,
        workoutType: String,
        targetMin: Int,
        targetMax: Int,
        totalSets: Int,
        volume: VolumeContext,
        items: [PlanExercise],
        notes: String?
    ) async throws -> SessionPlan {
        let payload = SessionPlanCreate(
            session_id: sessionId.uuidString,
            user_id: userId.uuidString,
            workout_type: workoutType,
            target_sets_min: targetMin,
            target_sets_max: targetMax,
            total_sets_planned: totalSets,
            volume_context: volume,
            exercises: items,
            notes: notes
        )
        let response: SessionPlan = try await client.database
            .from("session_plans")
            .upsert(payload, onConflict: "session_id")
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func getSessionPlan(sessionId: UUID) async throws -> SessionPlan? {
        let rows: [SessionPlan] = try await client.database
            .from("session_plans")
            .select()
            .eq("session_id", value: sessionId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func updateSessionPlan(sessionId: UUID, update: SessionPlanUpdate) async throws -> SessionPlan {
        let response: SessionPlan = try await client.database
            .from("session_plans")
            .update(update)
            .eq("session_id", value: sessionId.uuidString)
            .select()
            .single()
            .execute()
            .value
        return response
    }
}

// MARK: - Custom Errors

enum SupabaseError: Error, LocalizedError {
    case noUser
    case sessionExpired
    case invalidData

    var errorDescription: String? {
        switch self {
        case .noUser: return "Profile not found. Please complete onboarding."
        case .sessionExpired: return "Your session has expired. Please sign in again."
        case .invalidData: return "Received invalid data from the server."
        }
    }
}
