import Foundation

struct InjuryRule {
    let normalizedInjury: String // "shoulder", "lower_back", "knee", "elbow", "wrist"
    let avoidExercises: [String]
    let cautionExercises: [String]
    let preferredSubstitutes: [String]
    let modificationNotes: String
}

class InjuryRuleEngine {
    static let shared = InjuryRuleEngine()
    
    private init() {}
    
    private let rules: [InjuryRule] = [
        InjuryRule(
            normalizedInjury: "shoulder",
            avoidExercises: [
                "Barbell Overhead Press",
                "Behind-the-Neck Press",
                "Upright Rows",
                "Wide-Grip Bench Press",
                "Dips",
                "Muscle-Ups"
            ],
            cautionExercises: [
                "Barbell Bench Press",
                "Incline Dumbbell Press",
                "Lateral Raises",
                "Face Pulls"
            ],
            preferredSubstitutes: [
                "Landmine Press",
                "Neutral-Grip Dumbbell Press",
                "Cable Lateral Raises",
                "Machine Shoulder Press"
            ],
            modificationNotes: "Use neutral grips, limit overhead pressing, emphasize scapular stability"
        ),
        InjuryRule(
            normalizedInjury: "lower_back",
            avoidExercises: [
                "Conventional Deadlift",
                "Barbell Row",
                "Good Mornings",
                "Barbell Squats",
                "Weighted Hyperextensions"
            ],
            cautionExercises: [
                "Romanian Deadlift",
                "Leg Press",
                "Front Squats"
            ],
            preferredSubstitutes: [
                "Chest-Supported Row",
                "Machine Row",
                "Trap Bar Deadlift",
                "Goblet Squat",
                "Leg Press"
            ],
            modificationNotes: "Limit spinal loading, prefer supported positions, maintain neutral spine"
        ),
        InjuryRule(
            normalizedInjury: "knee",
            avoidExercises: [
                "Deep Squats",
                "Leg Press",
                "Walking Lunges",
                "Bulgarian Split Squats",
                "Box Jumps"
            ],
            cautionExercises: [
                "Barbell Squats",
                "Leg Extensions",
                "Hack Squats"
            ],
            preferredSubstitutes: [
                "Leg Press",
                "Hip Thrusts",
                "Glute Bridges",
                "Romanian Deadlift",
                "Hamstring Curls"
            ],
            modificationNotes: "Limit knee flexion under load, prefer hip-dominant movements, control ROM"
        ),
        InjuryRule(
            normalizedInjury: "elbow",
            avoidExercises: [
                "Heavy Barbell Curls",
                "Skull Crushers",
                "Close-Grip Bench Press",
                "Overhead Tricep Extensions"
            ],
            cautionExercises: [
                "Dumbbell Curls",
                "Tricep Dips",
                "Chin-Ups"
            ],
            preferredSubstitutes: [
                "Hammer Curls",
                "Cable Curls",
                "Cable Tricep Pushdowns",
                "Machine Curls"
            ],
            modificationNotes: "Use lighter weights, avoid full lockout, prefer cables and machines"
        ),
        InjuryRule(
            normalizedInjury: "wrist",
            avoidExercises: [
                "Barbell Bench Press",
                "Barbell Overhead Press",
                "Barbell Curls",
                "Push-Ups",
                "Front Squats"
            ],
            cautionExercises: [
                "Dumbbell Press",
                "Dumbbell Curls"
            ],
            preferredSubstitutes: [
                "Machine Press",
                "Cable Exercises",
                "Neutral-Grip Exercises",
                "Goblet Squat",
                "Safety Bar Squats"
            ],
            modificationNotes: "Use neutral grips, prefer machines/cables, consider wrist wraps"
        )
    ]
    
    func parseInjuries(from text: String?) -> [String] {
        guard let text = text?.lowercased(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var injuries: [String] = []
        if text.contains("shoulder") || text.contains("rotator") { injuries.append("shoulder") }
        if text.contains("back") || text.contains("spine") || text.contains("disc") { injuries.append("lower_back") }
        if text.contains("knee") || text.contains("acl") || text.contains("mcl") || text.contains("meniscus") { injuries.append("knee") }
        if text.contains("elbow") || text.contains("tennis elbow") || text.contains("golfer") { injuries.append("elbow") }
        if text.contains("wrist") || text.contains("carpal") { injuries.append("wrist") }
        return Array(Set(injuries))
    }
    
    func filterExercises(_ exercises: [ExerciseDetail], injuries: [String]) -> [FilteredExercise] {
        guard !injuries.isEmpty else { return exercises.map { FilteredExercise(exercise: $0, status: .safe, note: nil) } }
        var filtered: [FilteredExercise] = []
        for exercise in exercises {
            var status: ExerciseSafetyStatus = .safe
            var note: String? = nil
            for injury in injuries {
                guard let rule = rules.first(where: { $0.normalizedInjury == injury }) else { continue }
                let name = exercise.name.lowercased()
                if rule.avoidExercises.contains(where: { name.contains($0.lowercased()) }) {
                    status = .avoid
                    note = "Not recommended with \(injury.replacingOccurrences(of: "_", with: " ")) issues"
                    break
                }
                if rule.cautionExercises.contains(where: { name.contains($0.lowercased()) }) {
                    if status != .avoid {
                        status = .caution
                        note = "Use with caution: \(rule.modificationNotes)"
                    }
                }
            }
            if status != .avoid {
                filtered.append(FilteredExercise(exercise: exercise, status: status, note: note))
            }
        }
        return filtered
    }
    
    func getSafeSubstitutes(for muscleGroup: String, injuries: [String]) -> [String] {
        var subs: [String] = []
        for injury in injuries {
            if let rule = rules.first(where: { $0.normalizedInjury == injury }) {
                subs.append(contentsOf: rule.preferredSubstitutes)
            }
        }
        return Array(Set(subs))
    }
    
    func getModificationNotes(for injuries: [String]) -> [String] {
        injuries.compactMap { inj in
            rules.first(where: { $0.normalizedInjury == inj })?.modificationNotes
        }
    }
}

enum ExerciseSafetyStatus { case safe, caution, avoid }

struct FilteredExercise {
    let exercise: ExerciseDetail
    let status: ExerciseSafetyStatus
    let note: String?
}
