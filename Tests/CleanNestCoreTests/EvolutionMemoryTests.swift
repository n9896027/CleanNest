import Foundation
import XCTest
@testable import CleanNestCore

final class EvolutionMemoryTests: XCTestCase {
    func testExplicitPreferenceWinsAndCanBeCleared() {
        let candidate = fixture()
        var memory = EvolutionMemory()

        memory.recordCleanup(candidate, decision: .preferKeep)
        memory.recordCleanup(candidate, decision: .cleaned)
        XCTAssertEqual(memory.cleanupPreference(for: candidate), .preferKeep)
        XCTAssertEqual(memory.successfulCleanupCount, 1)

        memory.clearExplicitPreference(for: candidate)
        XCTAssertEqual(memory.cleanupPreference(for: candidate), .preferCleanup)
        XCTAssertEqual(memory.events.first?.title, "已撤销清理偏好")
    }

    func testSameDisplayNameAtDifferentPathsDoesNotSharePreference() {
        let first = fixture(root: URL(fileURLWithPath: "/private/first"))
        let second = fixture(root: URL(fileURLWithPath: "/private/second"))
        var memory = EvolutionMemory()

        memory.recordCleanup(first, decision: .preferKeep)
        XCTAssertEqual(memory.cleanupPreference(for: first), .preferKeep)
        XCTAssertNil(memory.cleanupPreference(for: second))
    }

    func testPersistenceExcludesCandidateAndModelPaths() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestEvolutionTests-\(UUID().uuidString)", isDirectory: true)
        let url = root.appendingPathComponent("memory.json")
        defer { try? FileManager.default.removeItem(at: root) }

        let candidate = fixture(root: root)
        var memory = EvolutionMemory()
        memory.recordCleanup(candidate, decision: .preferCleanup)
        memory.recordModelFeedback(
            modelID: "/Users/private/models/Qwen-27B",
            displayName: "Qwen 27B",
            helpful: true,
            scope: "清理建议"
        )

        try EvolutionMemoryPersistence.save(memory, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains(root.path))
        XCTAssertFalse(text.contains("/Users/private"))

        let loaded = try EvolutionMemoryPersistence.load(from: url)
        XCTAssertEqual(loaded.cleanupPreference(for: candidate), .preferCleanup)
        XCTAssertEqual(loaded.modelFeedbackCount, 1)
    }

    func testModelFeedbackIsAggregatedByPrivateStableIdentity() {
        var memory = EvolutionMemory()
        memory.recordModelFeedback(modelID: "/models/qwen", displayName: "Qwen", helpful: true, scope: "清理建议")
        memory.recordModelFeedback(modelID: "/models/qwen", displayName: "Qwen", helpful: false, scope: "磁盘解读")

        XCTAssertEqual(memory.modelFeedbackCount, 2)
        XCTAssertEqual(memory.sortedModelSignals.count, 1)
        XCTAssertEqual(memory.sortedModelSignals[0].helpfulRatio, 0.5)
        XCTAssertFalse(memory.sortedModelSignals[0].id.contains("/models/qwen"))
    }

    private func fixture(root: URL = URL(fileURLWithPath: "/private/home")) -> CleanupCandidate {
        CleanupCandidate(
            name: "content-v2",
            url: root.appendingPathComponent("Library/Caches/content-v2", isDirectory: true),
            kind: .packageManager,
            allocatedBytes: 5_330_000_000,
            modifiedAt: Date(),
            isRecommended: false,
            detail: "npm 下载内容缓存"
        )
    }
}
