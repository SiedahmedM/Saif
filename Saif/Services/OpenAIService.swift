import Foundation

// MARK: - OpenAI Service for GPT-4 Integration
class OpenAIService {
    static let shared = OpenAIService()

    private let apiKey = Config.openAIKey
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    private init() {}

    // MARK: - Workout Recommendation

    func getWorkoutTypeRecommendation(
        profile: UserProfile,
        recentWorkouts: [WorkoutSession]
    ) async throws -> WorkoutRecommendation {
        let prompt = buildWorkoutTypePrompt(profile: profile, recentWorkouts: recentWorkouts)

        let response = try await callGPT4(
            systemPrompt: "You are an expert personal trainer and workout coach. Provide workout recommendations in JSON format.",
            userPrompt: prompt
        )

        return try parseWorkoutRecommendation(from: response)
    }

    // MARK: - Exercise Recommendation

    func getExerciseRecommendations(
        profile: UserProfile,
        workoutType: String,
        muscleGroup: String,
        availableExercises: [Exercise],
        recentSets: [ExerciseSet]
    ) async throws -> [ExerciseRecommendation] {
        let prompt = buildExerciseRecommendationPrompt(
            profile: profile,
            workoutType: workoutType,
            muscleGroup: muscleGroup,
            availableExercises: availableExercises,
            recentSets: recentSets
        )

        let response = try await callGPT4(
            systemPrompt: "You are an expert strength coach. Recommend exercises based on the user's profile, goals, and workout history. Return recommendations as JSON.",
            userPrompt: prompt
        )

        return try parseExerciseRecommendations(from: response)
    }

    // MARK: - Set/Rep Recommendation

    func getSetRepRecommendation(
        profile: UserProfile,
        exercise: Exercise,
        previousSets: [ExerciseSet]
    ) async throws -> SetRepRecommendation {
        let prompt = buildSetRepPrompt(
            profile: profile,
            exercise: exercise,
            previousSets: previousSets
        )

        let response = try await callGPT4(
            systemPrompt: "You are a strength and conditioning coach. Recommend sets, reps, and weight based on progressive overload principles. Return as JSON.",
            userPrompt: prompt
        )

        return try parseSetRepRecommendation(from: response)
    }

    // MARK: - Muscle Group Priority

    func getMuscleGroupPriority(
        profile: UserProfile,
        workoutType: String,
        recentWorkouts: [WorkoutSession]
    ) async throws -> [String] {
        let prompt = buildMuscleGroupPriorityPrompt(
            profile: profile,
            workoutType: workoutType,
            recentWorkouts: recentWorkouts
        )

        let response = try await callGPT4(
            systemPrompt: "You are a workout programming expert. Recommend the order of muscle groups to train for optimal results. Return as JSON array.",
            userPrompt: prompt
        )

        return try parseMuscleGroupPriority(from: response)
    }

    // MARK: - Private Helper Methods

    private func callGPT4(systemPrompt: String, userPrompt: String) async throws -> String {
        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": 0.7,
            "response_format": ["type": "json_object"]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard httpResponse.statusCode == 200 else { throw OpenAIError.apiError(statusCode: httpResponse.statusCode) }

        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else { throw OpenAIError.invalidResponse }
        return content
    }

    // MARK: - Prompt Builders
    private func buildWorkoutTypePrompt(profile: UserProfile, recentWorkouts: [WorkoutSession]) -> String {
        let recentWorkoutSummary = recentWorkouts.prefix(5).map { w in
            "\(w.workoutType) on \(w.startedAt.formatted(date: .abbreviated, time: .omitted))"
        }.joined(separator: ", ")
        return """
        You are an expert strength coach.

        \(FitnessKnowledge.workoutSplitPrinciples)
        \(FitnessKnowledge.recoveryGuidelines)

        USER PROFILE:
        - Goal: \(profile.primaryGoal.rawValue)
        - Experience: \(profile.fitnessLevel.rawValue)
        - Frequency: \(profile.workoutFrequency) days/week
        - Recent workouts: \(recentWorkoutSummary.isEmpty ? "None" : recentWorkoutSummary)

        TASK: Recommend the best workout type for today (push, pull, or legs).

        Return JSON format:
        {
            "recommended_workout": "push|pull|legs",
            "reasoning": "Brief explanation",
            "confidence": 0.0,
            "alternatives": ["type1", "type2"]
        }
        """
    }

    private func buildExerciseRecommendationPrompt(
        profile: UserProfile,
        workoutType: String,
        muscleGroup: String,
        availableExercises: [Exercise],
        recentSets: [ExerciseSet]
    ) -> String {
        let exerciseList = availableExercises.prefix(10).map { "\($0.name) (\($0.muscleGroup))" }.joined(separator: ", ")
        return """
        You are an expert strength coach selecting exercises.

        \(FitnessKnowledge.exerciseSelectionRules)
        \(FitnessKnowledge.progressiveOverloadRules)

        USER PROFILE:
        - Goal: \(profile.primaryGoal.rawValue)
        - Experience: \(profile.fitnessLevel.rawValue)
        - Workout Type: \(workoutType)
        - Target Muscle Group: \(muscleGroup)

        Available Exercises: \(exerciseList)

        Recommend 3 exercises for this muscle group, ordered by priority. Consider the user's goal and experience level.

        Return JSON format:
        {
            "recommendations": [
                {
                    "exercise_name": "Exercise name",
                    "priority": 1,
                    "reasoning": "Why this exercise"
                }
            ]
        }
        """
    }

    private func buildSetRepPrompt(
        profile: UserProfile,
        exercise: Exercise,
        previousSets: [ExerciseSet]
    ) -> String {
        let lastPerformance = previousSets.last.map { "\($0.setNumber) sets of \($0.reps) reps at \($0.weight)lbs" } ?? "No previous data"
        return """
        User Profile:
        - Goal: \(profile.primaryGoal.rawValue)
        - Experience: \(profile.fitnessLevel.rawValue)

        Exercise: \(exercise.name)
        Last Performance: \(lastPerformance)

        Recommend sets, reps, and weight for today based on progressive overload principles and the user's goal.

        Return JSON format:
        {
            "sets": 3,
            "reps": 10,
            "weight": 135.0,
            "rest_seconds": 90,
            "notes": "Brief coaching tip"
        }
        """
    }

    // Simple chat bridge for the floating chatbot
    func getChatReply(system: String, user: String) async throws -> String {
        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [["role":"system","content":system],["role":"user","content":user]],
            "temperature": 0.7
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { throw OpenAIError.invalidResponse }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let content = (choices?.first?["message"] as? [String: Any])?["content"] as? String
        return content ?? ""
    }

    private func buildMuscleGroupPriorityPrompt(
        profile: UserProfile,
        workoutType: String,
        recentWorkouts: [WorkoutSession]
    ) -> String {
        return """
        User Profile:
        - Goal: \(profile.primaryGoal.rawValue)
        - Experience: \(profile.fitnessLevel.rawValue)
        - Today's Workout: \(workoutType)

        Recommend the order of muscle groups to train for optimal results.
        For example, for push day: chest, shoulders, triceps.

        Return JSON format:
        {
            "priority_order": ["muscle_group_1", "muscle_group_2", "muscle_group_3"]
        }
        """
    }

    // MARK: - Response Parsers
    private func parseWorkoutRecommendation(from json: String) throws -> WorkoutRecommendation {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        return try JSONDecoder().decode(WorkoutRecommendation.self, from: data)
    }
    private func parseExerciseRecommendations(from json: String) throws -> [ExerciseRecommendation] {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        let response = try JSONDecoder().decode(ExerciseRecommendationResponse.self, from: data)
        return response.recommendations
    }
    private func parseSetRepRecommendation(from json: String) throws -> SetRepRecommendation {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        return try JSONDecoder().decode(SetRepRecommendation.self, from: data)
    }
    private func parseMuscleGroupPriority(from json: String) throws -> [String] {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        let response = try JSONDecoder().decode(MuscleGroupPriorityResponse.self, from: data)
        return response.priorityOrder
    }
}

// MARK: - Response Models
struct WorkoutRecommendation: Decodable, Equatable {
    let workoutType: String
    let reasoning: String
    let alternatives: [String]
    let confidence: Double?
    let isFirstWorkout: Bool?
    let educationalNote: String?
    let progressMessage: String?

    enum CodingKeys: String, CodingKey {
        case workoutType = "workout_type"
        case recommendedType = "recommended_type"
        case recommendedWorkout = "recommended_workout"
        case reasoning, alternatives, confidence
        case isFirstWorkout = "is_first_workout"
        case educationalNote = "educational_note"
        case progressMessage = "progress_message"
    }

    init(workoutType: String, reasoning: String, alternatives: [String], confidence: Double? = nil, isFirstWorkout: Bool? = nil, educationalNote: String? = nil, progressMessage: String? = nil) {
        self.workoutType = workoutType
        self.reasoning = reasoning
        self.alternatives = alternatives
        self.confidence = confidence
        self.isFirstWorkout = isFirstWorkout
        self.educationalNote = educationalNote
        self.progressMessage = progressMessage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Support either recommended_type or workout_type
        if let wt = try c.decodeIfPresent(String.self, forKey: .workoutType) {
            workoutType = wt
        } else if let rt = try c.decodeIfPresent(String.self, forKey: .recommendedType) {
            workoutType = rt
        } else if let rw = try c.decodeIfPresent(String.self, forKey: .recommendedWorkout) {
            workoutType = rw
        } else {
            workoutType = "push"
        }
        reasoning = (try? c.decode(String.self, forKey: .reasoning)) ?? ""
        alternatives = (try? c.decode([String].self, forKey: .alternatives)) ?? ["pull", "legs"]
        confidence = try? c.decode(Double.self, forKey: .confidence)
        isFirstWorkout = try? c.decode(Bool.self, forKey: .isFirstWorkout)
        educationalNote = try? c.decode(String.self, forKey: .educationalNote)
        progressMessage = try? c.decode(String.self, forKey: .progressMessage)
    }
}
struct ExerciseRecommendation: Codable, Identifiable { var id: String { exerciseName }; let exerciseName: String; let priority: Int; let reasoning: String }
struct ExerciseRecommendationResponse: Codable { let recommendations: [ExerciseRecommendation] }
struct SetRepRecommendation: Codable { let sets: Int; let reps: Int; let weight: Double; let restSeconds: Int; let notes: String }
struct MuscleGroupPriorityResponse: Codable { let priorityOrder: [String] }

// MARK: - Errors
enum OpenAIError: Error { case invalidURL, invalidResponse, apiError(statusCode: Int), parseError }
