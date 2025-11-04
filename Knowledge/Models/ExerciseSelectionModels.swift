import Foundation

// MARK: - Root Structure
struct ExerciseSelectionKnowledge: Codable {
    let chest: MuscleGroupExercises
    let back: MuscleGroupExercises
    let shoulders: MuscleGroupExercises
    let quads: MuscleGroupExercises
    let exerciseOrderingResearch: ExerciseOrderingResearch

    enum CodingKeys: String, CodingKey {
        case chest, back, shoulders, quads
        case exerciseOrderingResearch = "exercise_ordering_research"
    }
}

// MARK: - Muscle Group Exercises
struct MuscleGroupExercises: Codable {
    let topCompoundExercises: [ExerciseDetail]
    let topAccessoryExercises: [ExerciseDetail]
    let exerciseSubstitutions: [ExerciseSubstitution]

    enum CodingKeys: String, CodingKey {
        case topCompoundExercises = "top_compound_exercises"
        case topAccessoryExercises = "top_accessory_exercises"
        case exerciseSubstitutions = "exercise_substitutions"
    }
}

// MARK: - Exercise Detail
struct ExerciseDetail: Codable, Identifiable {
    var id: String { name }

    let name: String
    let emgActivation: String
    let effectiveness: Effectiveness
    let injuryRisk: String
    let equipment: String
    let prerequisites: String
    let progressionPath: String
    let whenToPrioritize: String?

    enum CodingKeys: String, CodingKey {
        case name
        case emgActivation = "EMG_activation"
        case effectiveness
        case injuryRisk = "injury_risk"
        case equipment
        case prerequisites
        case progressionPath = "progression_path"
        case whenToPrioritize = "when_to_prioritize"
    }

    var isCompound: Bool {
        let kws = ["squat", "press", "deadlift", "row", "pull-up", "chin-up", "dip", "lunge", "clean"]
        return kws.contains { name.lowercased().contains($0) }
    }

    var safetyLevel: SafetyLevel {
        let r = injuryRisk.lowercased()
        if r.contains("very low") || r == "low" { return .low }
        if r.contains("low/medium") || r.contains("medium") { return .medium }
        return .high
    }
}

enum SafetyLevel: String, Codable { case low = "Low", medium = "Medium", high = "High" }

// MARK: - Effectiveness
struct Effectiveness: Codable {
    let hypertrophy: String
    let strength: String
    let power: String

    var hypertrophyScore: Int { parseEffectivenessScore(hypertrophy) }
    var strengthScore: Int { parseEffectivenessScore(strength) }
    var powerScore: Int { parseEffectivenessScore(power) }

    private func parseEffectivenessScore(_ text: String) -> Int {
        let t = text.lowercased()
        if t.contains("very high") { return 4 }
        if t.contains("high") { return 3 }
        if t.contains("medium") { return 2 }
        return 1
    }
}

// MARK: - Exercise Substitution
struct ExerciseSubstitution: Codable, Identifiable {
    var id: String { scenario }
    let scenario: String
    let substitute: String
    let notes: String
}

// MARK: - Exercise Ordering Research
struct ExerciseOrderingResearch: Codable {
    let optimalSequence: String
    let fatigueManagement: String
    let compoundVsIsolationTiming: String

    enum CodingKeys: String, CodingKey {
        case optimalSequence = "optimal_sequence"
        case fatigueManagement = "fatigue_management"
        case compoundVsIsolationTiming = "compound_vs_isolation_timing"
    }
}

// MARK: - Supporting Types
enum ExerciseType { case compound, accessory, all }

