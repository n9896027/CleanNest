import XCTest
@testable import CleanNestCore

final class AgentWorkspaceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }

    func testLsofParserAssociatesProcessCommandAndAbsolutePath() {
        let output = """
        p42
        ccodex
        f12
        n/Users/test/.codex/sessions/live.jsonl
        n127.0.0.1:8080
        p71
        cClaude
        n/Users/test/.claude/projects/current.jsonl (deleted)
        """

        let records = AgentWorkspaceOpenFileProbe.parseLsofFieldOutput(output)

        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].processID, 71)
        XCTAssertEqual(records[0].commandName, "Claude")
        XCTAssertEqual(records[0].path, "/Users/test/.claude/projects/current.jsonl")
        XCTAssertEqual(records[1].processID, 42)
        XCTAssertEqual(records[1].commandName, "codex")
    }

    func testActiveCodexSessionIsProtectedAndExcludedFromPreview() async throws {
        let home = try makeHome()
        let session = home.appendingPathComponent(".codex/sessions/2026/live.jsonl")
        try writeFile(session, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-40 * 86_400))
        let scanner = AgentWorkspaceScanner(configuration: testConfiguration())

        let result = try await scanner.scan(
            homeDirectory: home,
            openFiles: [
                AgentWorkspaceOpenFile(processID: 99, commandName: "codex", path: session.path)
            ]
        )
        let codex = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .codex })
        let sessions = try XCTUnwrap(codex.artifacts.first { $0.kind == .activeSessions })

        XCTAssertTrue(codex.detected)
        XCTAssertEqual(sessions.activeFileCount, 1)
        XCTAssertEqual(sessions.disposition, .protected)
        XCTAssertEqual(sessions.previewBytes, 0)
        XCTAssertTrue(result.snapshot.alerts.contains { $0.id == "codex:active" })
    }

    func testClosedOldSessionEntersArchivePreviewWithoutBeingCalledDeleted() async throws {
        let home = try makeHome()
        let session = home.appendingPathComponent(".codex/sessions/2025/closed.jsonl")
        try writeFile(session, bytes: 16_384, modifiedAt: Date().addingTimeInterval(-45 * 86_400))
        let scanner = AgentWorkspaceScanner(configuration: testConfiguration())

        let result = try await scanner.scan(homeDirectory: home, openFiles: [])
        let sessions = try XCTUnwrap(
            result.snapshot.agents
                .first { $0.provider == .codex }?
                .artifacts.first { $0.kind == .activeSessions }
        )

        XCTAssertEqual(sessions.disposition, .review)
        XCTAssertEqual(sessions.oldFileCount, 1)
        XCTAssertGreaterThan(sessions.previewBytes, 0)
        XCTAssertTrue(sessions.protectionReasons.isEmpty)
    }

    func testClaudeCacheIsRegenerableButCredentialsRemainProtectedByPolicy() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent("Library/Application Support/Claude/Cache/data.bin")
        let credentials = home.appendingPathComponent("Library/Application Support/Claude/Cookies")
        let oldDate = Date().addingTimeInterval(-60 * 86_400)
        try writeFile(cache, bytes: 12_288, modifiedAt: oldDate)
        try writeFile(credentials, bytes: 4_096, modifiedAt: oldDate)
        let scanner = AgentWorkspaceScanner(configuration: testConfiguration())

        let result = try await scanner.scan(homeDirectory: home, openFiles: [])
        let claude = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .claude })
        let cacheArtifact = try XCTUnwrap(claude.artifacts.first { $0.kind == .caches })
        let credentialArtifact = try XCTUnwrap(claude.artifacts.first { $0.kind == .credentials })

        XCTAssertEqual(cacheArtifact.disposition, .regenerable)
        XCTAssertGreaterThan(cacheArtifact.previewBytes, 0)
        XCTAssertEqual(credentialArtifact.disposition, .keep)
        XCTAssertEqual(credentialArtifact.previewBytes, 0)
        XCTAssertTrue(credentialArtifact.protectionReasons.contains { $0.contains("令牌") })
    }

    func testSecondObservationDetectsMeaningfulGrowth() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/first.bin")
        let baselineDate = Date().addingTimeInterval(-120)
        try writeFile(cache, bytes: 4_096, modifiedAt: baselineDate.addingTimeInterval(-3_600))
        let scanner = AgentWorkspaceScanner(configuration: testConfiguration(
            growthWarningBytes: 1,
            growthCriticalBytes: 1_000_000
        ))
        let baseline = try await scanner.scan(
            homeDirectory: home,
            openFiles: [],
            now: baselineDate
        )

        let added = home.appendingPathComponent(".codex/cache/second.bin")
        try writeFile(added, bytes: 12_288, modifiedAt: baselineDate.addingTimeInterval(-3_000))
        let current = try await scanner.scan(
            homeDirectory: home,
            previous: baseline.observation,
            openFiles: [],
            now: baselineDate.addingTimeInterval(120)
        )

        XCTAssertTrue(current.snapshot.alerts.contains {
            $0.id == "codex:growth" && $0.level == .warning
        })
    }

    func testRecentFileIsProtectedEvenWhenOpenFileProbeHasNoRecord() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/recent.bin")
        try writeFile(cache, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-30))
        let scanner = AgentWorkspaceScanner(configuration: testConfiguration())

        let result = try await scanner.scan(homeDirectory: home, openFiles: [])
        let artifact = try XCTUnwrap(
            result.snapshot.agents
                .first { $0.provider == .codex }?
                .artifacts.first { $0.kind == .caches }
        )

        XCTAssertEqual(artifact.disposition, .protected)
        XCTAssertEqual(artifact.previewBytes, 0)
        XCTAssertTrue(artifact.protectionReasons.contains { $0.contains("15 分钟") })
    }

    func testUnavailableOpenFileProbeFailsClosedAndDoesNotPublishPreview() async throws {
        let home = try makeHome()
        let payload = home.appendingPathComponent(".codex/cache/old-cache.bin")
        try writeFile(payload, bytes: 16_384, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: [],
            suppliedOpenFileProbeSucceeded: false,
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertFalse(result.snapshot.openFileProbeSucceeded)
        XCTAssertFalse(result.snapshot.isComplete)
        XCTAssertEqual(result.snapshot.previewBytes, 0)
        XCTAssertEqual(result.snapshot.detectedAgents.first?.artifacts.first?.disposition, .protected)
        XCTAssertTrue(result.snapshot.alerts.contains { $0.id == "activity-probe-unavailable" })
    }

    func testHardLinkedArtifactsCountAllocatedBlocksOnlyOnceAcrossCategories() async throws {
        let home = try makeHome()
        let original = home.appendingPathComponent(".codex/backups/shared.bin")
        let linked = home.appendingPathComponent(".codex/cache/shared.bin")
        try writeFile(original, bytes: 32_768, modifiedAt: Date().addingTimeInterval(-40 * 86_400))
        try FileManager.default.createDirectory(
            at: linked.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.linkItem(at: original, to: linked)

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let codex = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .codex })

        XCTAssertEqual(codex.fileCount, 1)
        XCTAssertGreaterThan(codex.allocatedBytes, 0)
        XCTAssertLessThanOrEqual(codex.allocatedBytes, 32_768)
    }

    private func makeHome() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNest-AgentWorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func writeFile(_ url: URL, bytes: Int, modifiedAt: Date) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(repeating: 0x41, count: bytes).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    private func testConfiguration(
        growthWarningBytes: Int64 = Int64.max / 4,
        growthCriticalBytes: Int64 = Int64.max / 2
    ) -> AgentWorkspaceScanner.Configuration {
        AgentWorkspaceScanner.Configuration(
            recentInterval: 15 * 60,
            oldInterval: 30 * 86_400,
            largeFileWarningBytes: Int64.max / 4,
            largeFileCriticalBytes: Int64.max / 2,
            agentSizeWarningBytes: Int64.max / 4,
            agentSizeCriticalBytes: Int64.max / 2,
            growthWarningBytes: growthWarningBytes,
            growthCriticalBytes: growthCriticalBytes,
            maximumEntriesPerAgent: 10_000
        )
    }
}
