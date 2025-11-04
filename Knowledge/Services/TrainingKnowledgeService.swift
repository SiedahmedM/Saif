import Foundation

final class TrainingKnowledgeService {
    static let shared = TrainingKnowledgeService()

    private var knowledge: ExerciseSelectionKnowledge?
    private let queue = DispatchQueue(label: "com.saif.trainingknowledge", attributes: .concurrent)
    private var usedFallback = false

    private init() {
        loadKnowledge()
    }

    // MARK: - Loading
    private func loadKnowledge() {
        // Try bundled JSON first
        if let url = Bundle.main.url(forResource: "exercise_selection", withExtension: "json", subdirectory: "Knowledge/Data"),
           let data = try? Data(contentsOf: url) {
            do {
                let decoder = JSONDecoder()
                let parsed = try decoder.decode(ExerciseSelectionKnowledge.self, from: data)
                queue.async(flags: .barrier) { self.knowledge = parsed }
                print("✅ TrainingKnowledgeService: Loaded exercise selection knowledge")
                return
            } catch {
                print("⚠️ TrainingKnowledgeService: JSON invalid, using fallback dataset")
                // Fall through to fallback data
            }
        } else {
            print("⚠️ TrainingKnowledgeService: Failed to locate exercise_selection.json in bundle")
        }

        // Fallback to a minimal, valid in-memory dataset to keep the app functional
        let fallback = self.defaultKnowledge()
        queue.async(flags: .barrier) {
            self.knowledge = fallback
            self.usedFallback = true
        }
        print("✅ TrainingKnowledgeService: Loaded exercise selection knowledge")
    }

    // Minimal safe dataset if JSON is invalid or missing
    private func defaultKnowledge() -> ExerciseSelectionKnowledge {
        func exercises(_ names: [String], compound: Bool) -> [ExerciseDetail] {
            names.map { name in
                ExerciseDetail(
                    name: name,
                    emgActivation: compound ? "High prime mover activation" : "Moderate activation",
                    effectiveness: Effectiveness(hypertrophy: "High", strength: compound ? "High" : "Medium", power: compound ? "Medium" : "Low"),
                    injuryRisk: compound ? "Medium" : "Low",
                    equipment: compound ? "Barbell, Dumbbell" : "Dumbbell, Cable, Bodyweight",
                    prerequisites: compound ? "Basic technique proficiency" : "None",
                    progressionPath: compound ? "Increase load progressively" : "Increase reps then load",
                    whenToPrioritize: compound ? "When fresh" : "After compounds"
                )
            }
        }

        let chest = MuscleGroupExercises(
            topCompoundExercises: exercises(["Barbell Bench Press", "Incline Dumbbell Press"], compound: true),
            topAccessoryExercises: exercises(["Chest Fly", "Push-Up"], compound: false),
            exerciseSubstitutions: [ExerciseSubstitution(scenario: "No bench", substitute: "Push-Ups", notes: "Elevate feet to increase difficulty")]
        )

        let back = MuscleGroupExercises(
            topCompoundExercises: exercises(["Barbell Row", "Pull-Up"], compound: true),
            topAccessoryExercises: exercises(["Lat Pulldown", "Cable Row"], compound: false),
            exerciseSubstitutions: [ExerciseSubstitution(scenario: "No pull-up bar", substitute: "Inverted Row", notes: "Use a sturdy table or bar")]
        )

        let shoulders = MuscleGroupExercises(
            topCompoundExercises: exercises(["Overhead Press", "Push Press"], compound: true),
            topAccessoryExercises: exercises(["Lateral Raise", "Rear Delt Fly"], compound: false),
            exerciseSubstitutions: [ExerciseSubstitution(scenario: "No dumbbells", substitute: "Pike Push-Up", notes: "Elevate feet for difficulty")]
        )

        let quads = MuscleGroupExercises(
            topCompoundExercises: exercises(["Back Squat", "Front Squat"], compound: true),
            topAccessoryExercises: exercises(["Leg Press", "Lunge"], compound: false),
            exerciseSubstitutions: [ExerciseSubstitution(scenario: "No barbell", substitute: "Goblet Squat", notes: "Hold kettlebell or dumbbell")]
        )

        let ordering = ExerciseOrderingResearch(
            optimalSequence: "Compound lifts first, then accessories",
            fatigueManagement: "Prioritize high-skill movements while fresh",
            compoundVsIsolationTiming: "Isolation after compounds for focused fatigue"
        )

        return ExerciseSelectionKnowledge(chest: chest, back: back, shoulders: shoulders, quads: quads, hamstrings: nil, glutes: nil, biceps: nil, triceps: nil, calves: nil, core: nil, exerciseOrderingResearch: ordering)
    }

    // Testing/debug helper
    var isUsingFallback: Bool { queue.sync { usedFallback } }

    // MARK: - Query Methods
    func getExercises(for muscleGroup: String, type: ExerciseType = .all) -> [ExerciseDetail] {
        guard let k = queue.sync(execute: { knowledge }) else { return [] }
        guard let mg = muscleGroupExercises(from: k, group: muscleGroup) else { return [] }
        switch type {
        case .compound: return mg.topCompoundExercises
        case .accessory: return mg.topAccessoryExercises
        case .all: return mg.topCompoundExercises + mg.topAccessoryExercises
        }
    }

    func getExercisesRanked(for muscleGroup: String, goal: Goal) -> [ExerciseDetail] {
        let list = getExercises(for: muscleGroup)
        return list.sorted { effectivenessScore(for: $0, goal: goal) > effectivenessScore(for: $1, goal: goal) }
    }

    func getExercises(for muscleGroup: String, availableEquipment gymType: GymType) -> [ExerciseDetail] {
        let list = getExercises(for: muscleGroup)
        return list.filter { isEquipmentAvailable(exercise: $0, gymType: gymType) }
    }

    func getSubstitutions(for muscleGroup: String) -> [ExerciseSubstitution] {
        guard let k = queue.sync(execute: { knowledge }) else { return [] }
        return muscleGroupExercises(from: k, group: muscleGroup)?.exerciseSubstitutions ?? []
    }

    func getOrderingPrinciples() -> ExerciseOrderingResearch? {
        queue.sync { knowledge?.exerciseOrderingResearch }
    }

    func findExercise(named name: String) -> ExerciseDetail? {
        guard let k = queue.sync(execute: { knowledge }) else { return nil }
        var groups = [k.chest, k.back, k.shoulders, k.quads]
        if let h = k.hamstrings { groups.append(h) }
        if let g1 = k.glutes { groups.append(g1) }
        if let g2 = k.biceps { groups.append(g2) }
        if let g3 = k.triceps { groups.append(g3) }
        if let g4 = k.calves { groups.append(g4) }
        if let g5 = k.core { groups.append(g5) }
        for g in groups {
            if let ex = (g.topCompoundExercises + g.topAccessoryExercises).first(where: { $0.name.lowercased().contains(name.lowercased()) }) {
                return ex
            }
        }
        return nil
    }

    // MARK: - Helpers
    private func muscleGroupExercises(from k: ExerciseSelectionKnowledge, group: String) -> MuscleGroupExercises? {
        switch normalizeMuscleGroup(group) {
        case "chest": return k.chest
        case "back": return k.back
        case "shoulders", "delts": return k.shoulders
        case "quads", "legs": return k.quads
        case "hamstrings", "hams", "posterior chain": return k.hamstrings
        case "glutes", "butt": return k.glutes
        case "biceps", "bis", "arms-biceps": return k.biceps
        case "triceps", "tris", "arms-triceps": return k.triceps
        case "calves", "calf": return k.calves
        case "abs", "core", "abs/core", "abdominals": return k.core
        default: return nil
        }
    }

    func normalizeMuscleGroup(_ group: String) -> String {
        let g = group.lowercased().replacingOccurrences(of: "_", with: " ")
        switch g {
        case "chest", "pecs", "pectorals": return "chest"
        case "back", "lats", "traps": return "back"
        case "shoulders", "delts", "deltoids": return "shoulders"
        case "quads", "legs", "quadriceps", "thighs": return "quads"
        case "hamstrings", "hams", "posterior chain", "hamstring": return "hamstrings"
        case "glutes", "butt", "glute": return "glutes"
        case "biceps", "bis": return "biceps"
        case "triceps", "tris": return "triceps"
        case "calves", "calf": return "calves"
        case "abs", "core", "abs/core", "abdominals": return "core"
        default: return g
        }
    }

    func effectivenessScore(for exercise: ExerciseDetail, goal: Goal) -> Int {
        switch goal {
        case .bulk:
            return exercise.effectiveness.hypertrophyScore
        case .cut:
            return (exercise.effectiveness.hypertrophyScore * 2 + exercise.effectiveness.powerScore) / 3
        case .maintain:
            return (exercise.effectiveness.strengthScore + exercise.effectiveness.hypertrophyScore) / 2
        }
    }

    func isEquipmentAvailable(exercise: ExerciseDetail, gymType: GymType) -> Bool {
        let eq = exercise.equipment.lowercased()
        switch gymType {
        case .commercial:
            return true
        case .home:
            let allow = ["barbell", "dumbbell", "bench", "bodyweight", "band", "kettlebell"]
            return allow.contains { eq.contains($0) }
        case .minimal:
            let allow = ["bodyweight", "band", "dumbbell"]
            let disallow = ["machine", "cable"]
            return allow.contains { eq.contains($0) } && !disallow.contains { eq.contains($0) }
        }
    }
}
