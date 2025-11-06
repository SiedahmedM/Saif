import Foundation

struct WorkoutState: Codable {
    let session: WorkoutSession
    let plan: SessionPlan?
    let completedSets: [ExerciseSet]
    let currentExerciseId: UUID?
    let savedAt: Date

    var isStale: Bool { Date().timeIntervalSince(savedAt) > 24 * 60 * 60 }
}

