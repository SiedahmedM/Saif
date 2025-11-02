import Foundation

enum Goal: String, CaseIterable, Identifiable, Hashable {
    case bulk = "Bulk"
    case cut = "Cut"
    case maintain = "Maintain"
    var id: String { rawValue }
}

enum Preset: String, CaseIterable, Identifiable, Hashable {
    case push = "Push Day"
    case pull = "Pull Day"
    case legs = "Legs"
    var id: String { rawValue }
}

