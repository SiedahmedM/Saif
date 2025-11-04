import Foundation

final class TrainingKnowledgeService {
    static let shared = TrainingKnowledgeService()

    private var knowledge: ExerciseSelectionKnowledge?
    private let queue = DispatchQueue(label: "com.saif.trainingknowledge", attributes: .concurrent)

    private init() {
        loadKnowledge()
    }

    // MARK: - Loading
    private func loadKnowledge() {
        guard let url = Bundle.main.url(forResource: "exercise_selection", withExtension: "json", subdirectory: "Knowledge/Data"),
              let data = try? Data(contentsOf: url) else {
            print("⚠️ TrainingKnowledgeService: Failed to locate exercise_selection.json in bundle")
            return
        }
        do {
            let decoder = JSONDecoder()
            let parsed = try decoder.decode(ExerciseSelectionKnowledge.self, from: data)
            queue.async(flags: .barrier) { self.knowledge = parsed }
            print("✅ TrainingKnowledgeService: Loaded exercise selection knowledge")
        } catch {
            print("❌ TrainingKnowledgeService: Decode error: \(error)")
        }
    }

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
        let groups = [k.chest, k.back, k.shoulders, k.quads]
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

