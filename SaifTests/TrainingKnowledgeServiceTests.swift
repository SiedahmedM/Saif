import Testing
@testable import Saif

struct TrainingKnowledgeServiceTests {

    @Test func loadsRealDatasetFromBundle() async throws {
        // Force initialize
        _ = TrainingKnowledgeService.shared
        // Give the async barrier write a moment
        try await Task.sleep(nanoseconds: 200_000_000)

        // Should not be using fallback after JSON cleanup
        #expect(!TrainingKnowledgeService.shared.isUsingFallback, "Expected real JSON dataset to load from bundle; fallback was used instead.")

        // Sanity check: find a known exercise from the JSON
        let ex = TrainingKnowledgeService.shared.findExercise(named: "Barbell Bench Press")
        #expect(ex != nil, "Expected to find Barbell Bench Press in knowledge data")
    }
}

