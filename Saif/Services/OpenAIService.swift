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
        recentSets: [ExerciseSet],
        favorites: [String] = [],
        avoids: [String] = []
    ) async throws -> ExerciseRecommendationResponse {
        // Query research knowledge; gracefully fallback if unavailable
        let researchExercises = TrainingKnowledgeService.shared.getExercisesRanked(
            for: muscleGroup,
            goal: profile.primaryGoal
        )
        let equipmentFiltered = TrainingKnowledgeService.shared.getExercises(
            for: muscleGroup,
            availableEquipment: profile.gymType
        )
        let orderingPrinciples = TrainingKnowledgeService.shared.getOrderingPrinciples()

        let useEnhanced = !researchExercises.isEmpty || !equipmentFiltered.isEmpty || orderingPrinciples != nil

        let prompt: String
        if useEnhanced {
            prompt = buildEnhancedExercisePrompt(
                profile: profile,
                workoutType: workoutType,
                muscleGroup: muscleGroup,
                availableExercises: availableExercises,
                researchExercises: researchExercises,
                equipmentFiltered: equipmentFiltered,
                orderingPrinciples: orderingPrinciples,
                recentSets: recentSets,
                favorites: favorites,
                avoids: avoids
            )
        } else {
            // Fallback to existing simpler prompt
            prompt = buildExerciseRecommendationPrompt(
                profile: profile,
                workoutType: workoutType,
                muscleGroup: muscleGroup,
                availableExercises: availableExercises,
                recentSets: recentSets,
                favorites: favorites,
                avoids: avoids
            )
        }

        let response = try await callGPT4(
            systemPrompt: "You are an expert strength coach with deep knowledge of exercise science. Recommend exercises based on evidence (EMG data, effectiveness research) and user context. Return JSON.",
            userPrompt: prompt
        )

        return try parseExerciseRecommendationResponse(from: response)
    }

    // MARK: - Set/Rep Recommendation

    func getSetRepRecommendation(
        profile: UserProfile,
        exercise: Exercise,
        previousSets: [ExerciseSet]
    ) async throws -> SetRepRecommendation {
        // Lookup research for this specific exercise, if available
        let researchData = TrainingKnowledgeService.shared.findExercise(named: exercise.name)

        let prompt = buildSetRepPrompt(
            profile: profile,
            exercise: exercise,
            previousSets: previousSets,
            researchData: researchData
        )

        let response = try await callGPT4(
            systemPrompt: "You are a strength and conditioning coach. Recommend sets, reps, and weight based on progressive overload principles and evidence-based training. Return JSON.",
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
            systemPrompt: "You are a workout programming expert. Recommend the order of muscle groups to train for optimal results. Return JSON object exactly with {\"priorityOrder\": [\"group1\", \"group2\", ...] }.",
            userPrompt: prompt
        )

        return try parseMuscleGroupPriority(from: response)
    }

    // MARK: - Private Helper Methods

    private func callGPT4(systemPrompt: String, userPrompt: String) async throws -> String {
        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAIError.missingAPIKey }

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
#if DEBUG
        print("OpenAI: sending request to chat/completions (model=gpt-4o-mini), userPrompt chars: \(userPrompt.count)")
#endif

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        let session = URLSession(configuration: config)
        let start = Date()
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("OpenAI API error (status \(httpResponse.statusCode)): \(body)")
            throw OpenAIError.apiError(statusCode: httpResponse.statusCode, body: body)
        }

        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else { throw OpenAIError.invalidResponse }
#if DEBUG
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("OpenAI: 200 OK (\(ms)ms). Content chars: \(content.count)")
#else
        let ms = Int(Date().timeIntervalSince(start) * 1000)
#endif
        print("OpenAI chat completion ok: \(ms)ms, chars=\(content.count)")
        return content
    }

    // MARK: - Contextual Chat (Coach)
    func chatWithContext(message: String, context: String, conversationHistory: [ChatMessage]) async throws -> String {
        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAIError.missingAPIKey }

        // Build messages with system context and prior conversation
        var msgs: [[String: Any]] = [["role": "system", "content": "You are a knowledgeable personal trainer helping a user during their workout. Keep answers concise and actionable.\n\n" + context]]
        for m in conversationHistory {
            msgs.append(["role": m.role == .user ? "user" : "assistant", "content": m.content])
        }
        msgs.append(["role": "user", "content": message])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": msgs,
            "max_tokens": 300,
            "temperature": 0.7
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        let session = URLSession(configuration: cfg)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("OpenAI chat error (status \(http.statusCode)): \(body)")
            throw OpenAIError.apiError(statusCode: http.statusCode, body: body)
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else { throw OpenAIError.invalidResponse }
        return content
    }

    // Strict JSON-driven coach with richer context and few-shots
    func chatWithContextJSON(message: String, context: String, conversationHistory: [ChatMessage], tone: String = "brief") async throws -> CoachResponse {
        guard let url = URL(string: baseURL) else { throw OpenAIError.invalidURL }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenAIError.missingAPIKey }

        let system = """
        You are an evidence-based strength coach. Respect injuries and constraints. Keep answers ≤ 100 words, use short bullets, include one clear action, and ask 1 clarifying question if uncertain. Verify any load change is within 3–25% clamps and rounded to available equipment increments.

        CONTEXT:\n\n\(context)

        Return ONLY JSON with this schema:
        {
          "summary": "string",
          "cues": ["string"],
          "action": { "type": "increase_load|decrease_load|keep|rest|substitute", "delta_lb": 0, "seconds": 0 },
          "risk_flags": ["string"],
          "next_question": "string",
          "tool_call": { "name": "swapExercise|setRestTimer|logSet|updatePreference", "params": { } }
        }

        FEW-SHOTS (examples):
        - Too light: 18 reps in 8–12 range → suggest +5–10 lb, rounded to step.
        - Too heavy early: RPE 9 on set 1–2 → suggest 3–5 min rest or -5–10% load.
        - Pain flag: if elbow pain on skull crushers → suggest safer substitute and caution.
        - Substitution: if equipment not available → suggest close variant.
        """

        var msgs: [[String: Any]] = [["role": "system", "content": system]]
        for m in conversationHistory {
            msgs.append(["role": m.role == .user ? "user" : "assistant", "content": m.content])
        }
        msgs.append(["role": "user", "content": message])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": msgs,
            "temperature": 0.5,
            "max_tokens": 350,
            "response_format": ["type": "json_object"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // simple retry for 429/5xx
        let start = Date()
        for attempt in 0..<2 {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw OpenAIError.invalidResponse }
            if http.statusCode == 200 {
                let text = try Self.extractContent(from: data)
                if let decoded = try? JSONDecoder().decode(CoachResponse.self, from: Data(text.utf8)) {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    print("OpenAI coach JSON ok: \(ms)ms, len=\(text.count)")
                    return decoded
                } else {
                    // Fallback: wrap plain text
                    return CoachResponse(summary: text, cues: [], action: nil, riskFlags: [], nextQuestion: "", toolCall: nil)
                }
            }
            if http.statusCode == 429 || http.statusCode >= 500 { try await Task.sleep(nanoseconds: 400_000_000) ; continue }
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("OpenAI chat JSON error (status \(http.statusCode)): \(body)")
            throw OpenAIError.apiError(statusCode: http.statusCode, body: body)
        }
        throw OpenAIError.apiError(statusCode: 429, body: "rate limited after retries")
    }

    private static func extractContent(from data: Data) throws -> String {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let first = choices.first,
              let msg = first["message"] as? [String: Any],
              let content = msg["content"] as? String else { throw OpenAIError.invalidResponse }
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
        recentSets: [ExerciseSet],
        favorites: [String],
        avoids: [String]
    ) -> String {
        let exerciseList = availableExercises.prefix(10).map { "\($0.name) (\($0.muscleGroup))" }.joined(separator: ", ")
        let preferences = preferencesText(favorites: favorites, avoids: avoids)
        return """
        You are an expert strength coach selecting exercises.

        \(FitnessKnowledge.exerciseSelectionRules)
        \(FitnessKnowledge.progressiveOverloadRules)

        USER PROFILE:
        - Goal: \(profile.primaryGoal.rawValue)
        - Experience: \(profile.fitnessLevel.rawValue)
        - Workout Type: \(workoutType)
        - Target Muscle Group: \(muscleGroup)
        \(preferences)

        Available Exercises: \(exerciseList)

        Recommend 3 exercises for this muscle group, ordered by priority. Consider the user's goal and experience level.
        Strictly prioritize FAVORITES and avoid AVOID unless there are no safe alternatives.

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
        previousSets: [ExerciseSet],
        researchData: ExerciseDetail?
    ) -> String {
        let lastPerformance = previousSets.last.map { "+\($0.setNumber) sets of \($0.reps) reps at \(Int($0.weight))lbs".replacingOccurrences(of: "+", with: "") } ?? "No previous data"

        var researchContext = ""
        if let research = researchData {
            let progressionSnippet = TextSanitizer.sanitizedResearchText(research.progressionPath)
                .components(separatedBy: ". ")
                .prefix(3)
                .joined(separator: ". ")

            researchContext = """

            RESEARCH DATA FOR \(exercise.name):
            - Effectiveness: Hypertrophy (\(research.effectiveness.hypertrophy)), Strength (\(research.effectiveness.strength))
            - Safety Level: \(research.safetyLevel.rawValue)
            - Evidence-Based Progression: \(progressionSnippet)
            """
        }

        // NEW: Add volume landmarks for rep/rest guidance
        var volumeContext = ""
        if let landmarks = TrainingKnowledgeService.shared.getVolumeLandmarks(
            for: exercise.muscleGroup,
            goal: profile.primaryGoal,
            experience: profile.fitnessLevel
        ) {
            let repRange = TextSanitizer.sanitizedResearchText(landmarks.repRange)
            let rest = TextSanitizer.sanitizedResearchText(landmarks.restBetweenSets)
            let intensity = TextSanitizer.sanitizedResearchText(landmarks.intensityGuidance)
            let mav = TextSanitizer.sanitizedResearchText(landmarks.mav)
            volumeContext = """

            VOLUME GUIDANCE FOR \(exercise.muscleGroup.capitalized):
            - Target Rep Range: \(repRange)
            - Rest Between Sets: \(rest)
            - Intensity: \(intensity)
            - Weekly Volume Target: \(mav)
            """
        }

        let goalGuidance = profile.primaryGoal == .bulk ? "Focus on progressive overload with 6-12 rep range for hypertrophy" :
                           profile.primaryGoal == .cut ? "Maintain strength with moderate volume, 8-12 reps" :
                           "Balanced approach, 8-10 reps"

        return """
        USER PROFILE:
        - Goal: \(profile.primaryGoal.displayName) (\(goalGuidance))
        - Experience: \(profile.fitnessLevel.displayName)

        EXERCISE: \(exercise.name)
        LAST PERFORMANCE: \(lastPerformance)
        \(researchContext)
        \(volumeContext)

        Recommend sets, reps, and weight for today based on:
        1. Progressive overload principles for \(profile.fitnessLevel.rawValue) lifters
        2. User's \(profile.primaryGoal.rawValue) goal
        3. Evidence-based volume and intensity guidance
        4. Last performance data (if available)

        Apply appropriate progression:
        - Beginner: 2.5-5% weight increases when all reps completed with good form
        - Intermediate: Smaller increments (2.5%), vary rep ranges within target
        - Advanced: Periodization, auto-regulation, listen to recovery signals

        Ensure recommendations align with the rep range and rest periods from research.

        Return JSON format:
        {
            "sets": 3,
            "reps": 10,
            "weight": 135.0,
            "rest_seconds": 90,
            "notes": "Brief evidence-based coaching tip"
        }
        """
    }

    private func buildEnhancedExercisePrompt(
        profile: UserProfile,
        workoutType: String,
        muscleGroup: String,
        availableExercises: [Exercise],
        researchExercises: [ExerciseDetail],
        equipmentFiltered: [ExerciseDetail],
        orderingPrinciples: ExerciseOrderingResearch?,
        recentSets: [ExerciseSet],
        favorites: [String],
        avoids: [String]
    ) -> String {
        // Existing research exercise formatting...
        let researchContext = researchExercises.prefix(5).map { ex in
            let safetyEmoji = ex.safetyLevel == .low ? "✅" : ex.safetyLevel == .medium ? "⚠️" : "⚠️⚠️"
            return """
            • \(ex.name) \(safetyEmoji):
              - Activation: \(ex.emgActivation.components(separatedBy: ".").first ?? "High muscle activation")
              - Hypertrophy: \(ex.effectiveness.hypertrophy)
              - Strength: \(ex.effectiveness.strength)
              - Safety: \(ex.injuryRisk)
              - Best for: \(ex.effectiveness.hypertrophy.contains("High") ? "muscle growth" : "maintenance")
            """
        }.joined(separator: "\n\n")

        let availableList = availableExercises.map { ex in
            "- \(ex.name) (\(ex.isCompound ? "compound" : "isolation"))"
        }.joined(separator: "\n")

        let orderingGuidance = orderingPrinciples?.optimalSequence.components(separatedBy: ".").prefix(2).joined(separator: ". ") ?? "Prioritize compound exercises first, then isolation."
        let preferences = preferencesText(favorites: favorites, avoids: avoids)

        // NEW: Add volume landmarks guidance
        let volumeGuidance: String
        if let landmarks = TrainingKnowledgeService.shared.getVolumeLandmarks(
            for: muscleGroup,
            goal: profile.primaryGoal,
            experience: profile.fitnessLevel
        ) {
            let mav = TextSanitizer.sanitizedResearchText(landmarks.mav)
            let sps = TextSanitizer.sanitizedResearchText(landmarks.setsPerSessionRange)
            let eps = TextSanitizer.sanitizedResearchText(landmarks.exercisesPerSession)
            let freq = TextSanitizer.sanitizedResearchText(landmarks.frequencyRecommendation)
            let rep = TextSanitizer.sanitizedResearchText(landmarks.repRange)
            let rest = TextSanitizer.sanitizedResearchText(landmarks.restBetweenSets)
            let intensity = TextSanitizer.sanitizedResearchText(landmarks.intensityGuidance)
            let notes = TextSanitizer.sanitizedResearchText(landmarks.notes)
            volumeGuidance = """

            VOLUME TARGETS (Evidence-Based - Mike Israetel Framework):
            • Weekly Volume Range: \(mav) (Maximum Adaptive Volume for optimal growth)
            • Sets Per Session: \(sps)
            • Recommended Exercises: \(eps)
            • Training Frequency: \(freq)
            • Rep Range: \(rep)
            • Rest Between Sets: \(rest)
            • Intensity: \(intensity)

            Context: \(notes)
            """
        } else {
            volumeGuidance = """

            VOLUME TARGETS (General Guidelines):
            • Aim for 10-20 sets per muscle group per week
            • 2-4 exercises per session
            • 8-12 reps for hypertrophy, 60-120 seconds rest
            """
        }

        let goalContext = profile.primaryGoal == .bulk ? "maximize hypertrophy" :
                          profile.primaryGoal == .cut ? "maintain muscle while managing fatigue" :
                          "maintain strength and muscle"

        return """
        EVIDENCE-BASED EXERCISE RESEARCH
        Top exercises for \(muscleGroup.capitalized) based on EMG studies and effectiveness research:

        \(researchContext)

        EXERCISE ORDERING PRINCIPLE:
        \(orderingGuidance)
        \(volumeGuidance)

        USER PROFILE:
        - Primary Goal: \(profile.primaryGoal.displayName) (\(goalContext))
        - Experience Level: \(profile.fitnessLevel.displayName)
        - Equipment Access: \(profile.gymType.displayName)
        - Training Frequency: \(profile.workoutFrequency)x/week

        AVAILABLE EXERCISES IN DATABASE:
        \(availableList)

        TASK:
        Recommend exercises from the AVAILABLE DATABASE, ordered by priority, with SET COUNTS for each.

        Your recommendation should:
        1. Match the recommended exercise count from volume targets
        2. Distribute sets across exercises to reach the target sets per session
        3. Prioritize FAVORITES first; avoid AVOID unless no feasible alternatives; then respect exercise ordering principles
        4. Match user's equipment and experience level
        5. Reference research data (EMG, effectiveness) in your reasoning

        Example format:
        - Exercise 1 (compound): 4 sets - because [research reasoning]
        - Exercise 2 (compound/accessory): 3 sets - because [research reasoning]
        - Exercise 3 (isolation): 2 sets - because [research reasoning]
        Total: 9 sets (within target range for optimal adaptation)

        CRITICAL: 
        - Only recommend exercises from the "AVAILABLE EXERCISES IN DATABASE" list
        - Specify set count for each exercise
        - Explain how the total sets fit within the volume guidance

        Return JSON format:
        {
            "recommendations": [
                {
                    "exercise_name": "Exact name from database",
                    "priority": 1,
                    "sets": 4,
                    "reasoning": "Evidence-based explanation with EMG/effectiveness reference"
                }
            ],
            "total_sets": 9,
            "target_sets_range": "8-10"
        }
        """
    }

    private func preferencesText(favorites: [String], avoids: [String]) -> String {
        var lines: [String] = []
        if !favorites.isEmpty { lines.append("FAVORITES: \(favorites.joined(separator: ", "))") }
        if !avoids.isEmpty { lines.append("AVOID: \(avoids.joined(separator: ", "))") }
        return lines.isEmpty ? "" : ("\nUSER PREFERENCES:\n" + lines.joined(separator: "\n"))
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
            "priorityOrder": ["muscle_group_1", "muscle_group_2", "muscle_group_3"]
        }
        """
    }

    // MARK: - Response Parsers
    private func parseWorkoutRecommendation(from json: String) throws -> WorkoutRecommendation {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        return try JSONDecoder().decode(WorkoutRecommendation.self, from: data)
    }
    private func parseExerciseRecommendationResponse(from json: String) throws -> ExerciseRecommendationResponse {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        let response = try JSONDecoder().decode(ExerciseRecommendationResponse.self, from: data)
        return response
    }
    private func parseSetRepRecommendation(from json: String) throws -> SetRepRecommendation {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        return try JSONDecoder().decode(SetRepRecommendation.self, from: data)
    }
    private func parseMuscleGroupPriority(from json: String) throws -> [String] {
        guard let data = json.data(using: .utf8) else { throw OpenAIError.parseError }
        // Try robust parsing: object (camelCase or snake_case) or raw array fallback
        let decoder = JSONDecoder()
        if let obj = try? decoder.decode(MuscleGroupPriorityResponse.self, from: data) {
            return obj.priorityOrder
        }
        if let arr = try? decoder.decode([String].self, from: data) {
            return arr
        }
        // As a last resort, don't throw noisy errors — return empty to allow caller fallback
        print("❌ [parseMuscleGroupPriority] error: missing priorityOrder in response")
        return []
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
struct ExerciseRecommendation: Decodable, Identifiable {
    var id: String { exerciseName }
    let exerciseName: String
    let priority: Int
    let sets: Int?
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case priority
        case sets
        case reasoning
        case exerciseNameCamel = "exerciseName"
    }

    init(exerciseName: String, priority: Int, sets: Int? = nil, reasoning: String) {
        self.exerciseName = exerciseName
        self.priority = priority
        self.sets = sets
        self.reasoning = reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Prefer snake_case, fallback to camelCase, default empty on failure
        let snake = try? c.decode(String.self, forKey: .exerciseName)
        let camel = try? c.decode(String.self, forKey: .exerciseNameCamel)
        self.exerciseName = snake ?? camel ?? ""
        self.priority = (try? c.decode(Int.self, forKey: .priority)) ?? 1
        self.sets = try? c.decode(Int.self, forKey: .sets)
        self.reasoning = (try? c.decode(String.self, forKey: .reasoning)) ?? ""
    }
}
struct ExerciseRecommendationResponse: Decodable {
    let recommendations: [ExerciseRecommendation]
    let totalSets: Int?
    let targetSetsRange: String?

    enum CodingKeys: String, CodingKey {
        case recommendations
        case totalSets = "total_sets"
        case targetSetsRange = "target_sets_range"
    }
}
struct SetRepRecommendation: Decodable { let sets: Int; let reps: Int; let weight: Double; let restSeconds: Int; let notes: String }
struct MuscleGroupPriorityResponse: Decodable {
    let priorityOrder: [String]
    enum CodingKeys: String, CodingKey { case priorityOrder, priority_order }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let camel = try c.decodeIfPresent([String].self, forKey: .priorityOrder) {
            self.priorityOrder = camel
        } else if let snake = try c.decodeIfPresent([String].self, forKey: .priority_order) {
            self.priorityOrder = snake
        } else {
            self.priorityOrder = []
        }
    }
}

// MARK: - Errors
enum OpenAIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, body: String)
    case parseError
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "OpenAI: Invalid URL"
        case .invalidResponse: return "OpenAI: Invalid response"
        case let .apiError(code, body): return "OpenAI: API error (\(code)) — \(body)"
        case .parseError: return "OpenAI: Failed to parse JSON content"
        case .missingAPIKey: return "OpenAI: API key is missing"
        }
    }
}
