import Foundation

struct RecoveryGeneral: Codable {
    let recovery_windows: [String:String]
    let frequency_optimization: [String:String]
    let volume_landmarks: [String:[String:[String:String]]]
    let split_optimization: [String:String]
    let individual_variation_factors: [String:String]
}

final class RecoveryKnowledgeService {
    static let shared = RecoveryKnowledgeService()

    private var loaded: Bool = false
    private var general: RecoveryGeneral?
    private init() { load() }

    private func load() {
        // Load and keep for future expansion; currently we rely on simple numeric heuristics.
        if let url = Bundle.main.url(forResource: "recovery_guidelines", withExtension: "json", subdirectory: "Knowledge/Data") { loaded = (try? Data(contentsOf: url)) != nil }
        if let gURL = Bundle.main.url(forResource: "recovery_general", withExtension: "json", subdirectory: "Knowledge/Data"),
           let data = try? Data(contentsOf: gURL) {
            let decoder = JSONDecoder()
            self.general = try? decoder.decode(RecoveryGeneral.self, from: data)
        }
    }

    // Normalize group keys to canonical names
    func normalize(_ raw: String) -> String {
        let g = raw.lowercased()
        if g.contains("leg") { return "legs" }
        if g.contains("quad") { return "quads" }
        if g.contains("ham") { return "hamstrings" }
        if g.contains("glute") { return "glutes" }
        if g.contains("back") { return "back" }
        if g.contains("chest") { return "chest" }
        if g.contains("shoulder") || g.contains("delts") { return "shoulders" }
        if g.contains("calf") { return "calves" }
        return g
    }

    // Simple numeric guidance derived from research narrative
    func recommendedRestDays(for group: String) -> Int {
        switch normalize(group) {
        case "quads", "hamstrings", "glutes", "legs": return 2
        case "back": return 2
        case "chest": return 2
        case "shoulders": return 2
        case "calves": return 1
        default: return 2
        }
    }

    func getGeneral() -> RecoveryGeneral? { general }
}
