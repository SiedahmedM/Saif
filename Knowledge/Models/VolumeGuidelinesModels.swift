import Foundation

// MARK: - Root Structure
struct VolumeGuidelinesKnowledge: Codable {
    let volumeGuidelines: [String: MuscleGroupVolume]
    let generalPrinciples: GeneralPrinciples
    
    enum CodingKeys: String, CodingKey {
        case volumeGuidelines = "volume_guidelines"
        case generalPrinciples = "general_principles"
    }
}

// MARK: - Muscle Group Volume
struct MuscleGroupVolume: Codable {
    let bulk: GoalVolume
    let cut: GoalVolume
    let maintain: GoalVolume
}

// MARK: - Goal Volume
struct GoalVolume: Codable {
    let beginner: VolumeLandmarks
    let intermediate: VolumeLandmarks
    let advanced: VolumeLandmarks
}

// MARK: - Volume Landmarks (Mike Israetel Framework)
struct VolumeLandmarks: Codable {
    let mv: String  // Maintenance Volume
    let mev: String // Minimum Effective Volume
    let mav: String // Maximum Adaptive Volume
    let mrv: String // Maximum Recoverable Volume
    let setsPerSessionRange: String
    let exercisesPerSession: String
    let frequencyRecommendation: String
    let restBetweenSets: String
    let repRange: String
    let intensityGuidance: String
    let progressionRate: String
    let recoveryNotes: String
    let sources: [String]
    let notes: String
    
    enum CodingKeys: String, CodingKey {
        case mv = "MV"
        case mev = "MEV"
        case mav = "MAV"
        case mrv = "MRV"
        case setsPerSessionRange = "sets_per_session_range"
        case exercisesPerSession = "exercises_per_session"
        case frequencyRecommendation = "frequency_recommendation"
        case restBetweenSets = "rest_between_sets"
        case repRange = "rep_range"
        case intensityGuidance = "intensity_guidance"
        case progressionRate = "progression_rate"
        case recoveryNotes = "recovery_notes"
        case sources
        case notes
    }
    
    // Computed properties for easier access
    var setsPerWeekRange: ClosedRange<Int> {
        // Parse something like "12-18 sets/week" to 12...18; fallback 12...18
        parseRange(from: mav) ?? 12...18
    }
    
    var exerciseCount: Int {
        // Parse "3-4 exercises" to middle value
        if let range = parseRange(from: exercisesPerSession) {
            return (range.lowerBound + range.upperBound) / 2
        }
        return 3
    }
    
    private func parseRange(from text: String) -> ClosedRange<Int>? {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return numbers[0]...numbers[1]
    }
}

// MARK: - General Principles
struct GeneralPrinciples: Codable {
    let volumeProgression: String
    let deloadFrequency: String
    let individualVariation: String
    
    enum CodingKeys: String, CodingKey {
        case volumeProgression = "volume_progression"
        case deloadFrequency = "deload_frequency"
        case individualVariation = "individual_variation"
    }
}

