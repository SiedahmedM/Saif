import Foundation

struct ExercisePreference: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseId: UUID
    let preferenceLevel: PreferenceLevel
    let reason: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseId = "exercise_id"
        case preferenceLevel = "preference_level"
        case reason
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum PreferenceLevel: String, Codable { case favorite, neutral, avoid }
}

