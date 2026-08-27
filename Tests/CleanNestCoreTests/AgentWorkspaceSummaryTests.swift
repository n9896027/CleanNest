import Foundation
import XCTest
@testable import CleanNestCore

final class AgentWorkspaceSummaryTests: XCTestCase {
    func testSummaryDropsPathsAndActionTokensFromFullSnapshot() throws {
        let privatePath = "/Users/example/.codex/sessions/private.jsonl"
        let artifact = AgentWorkspaceArtifact(
            id: "codex:sessions",
            provider: .codex,
            kind: .activeSessions,
            sourcePaths: [privatePath],
            allocatedBytes: 4_096,
            logicalBytes: 1_024,
            fileCount: 1,
            directoryCount: 1,
            activeFileCount: 1,
            recentlyModifiedFileCount: 1,
            oldFileCount: 0,
            previewBytes: 0,
            largestFileBytes: 1_024,
            largestFilePath: privatePath,
            latestModificationDate: Date(timeIntervalSince1970: 123),
            disposition: .protected,
            protectionReasons: ["正在使用"],
            isComplete: true,
            diagnostic: nil,
            actionCandidates: []
        )
        let snapshot = AgentWorkspaceSnapshot(
            capturedAt: Date(timeIntervalSince1970: 456),
            previousCapturedAt: nil,
            agents: [
                AgentWorkspaceAgentSnapshot(
                    provider: .codex,
                    detected: true,
                    artifacts: [artifact]
                )
            ],
            alerts: [],
            openFileProbeSucceeded: true,
            diagnostic: "完成"
        )

        let summary = AgentWorkspaceSummary(snapshot: snapshot)
        let encoded = try JSONEncoder().encode(summary)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(summary.allocatedBytes, 4_096)
        XCTAssertEqual(summary.fileCount, 1)
        XCTAssertEqual(summary.activeFileCount, 1)
        XCTAssertFalse(text.contains(privatePath))
        XCTAssertFalse(text.contains("sourcePaths"))
        XCTAssertFalse(text.contains("actionCandidates"))
        XCTAssertFalse(text.contains("largestFilePath"))
    }

    func testSummaryPersistenceRoundTripsAtomically() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("summary.json")
        let summary = AgentWorkspaceSummary(
            capturedAt: Date(timeIntervalSince1970: 789),
            providers: [
                .init(
                    provider: .piAgent,
                    allocatedBytes: 7_000,
                    fileCount: 9,
                    activeFileCount: 2,
                    previewBytes: 0,
                    isComplete: true
                )
            ],
            alertCount: 1,
            isComplete: true
        )

        try AgentWorkspaceSummaryPersistence.save(summary, to: url)

        XCTAssertEqual(try AgentWorkspaceSummaryPersistence.load(from: url), summary)
    }
}
