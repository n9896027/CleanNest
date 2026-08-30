import XCTest
@testable import CleanNestCore
import CleanNestMutation

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
        // 45 天未达到活跃会话 60 天处置门槛：进入归档建议，但不产生执行候选。
        XCTAssertTrue(sessions.actionCandidates.isEmpty)
    }

    func testActiveSessionsBecomeCandidatesOnlyAfterSixtyDays() async throws {
        let home = try makeHome()
        let mid = home.appendingPathComponent(".codex/sessions/2026/07/mid.jsonl")
        let old = home.appendingPathComponent(".codex/sessions/2026/06/old.jsonl")
        try writeFile(mid, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-45 * 86_400))
        try writeFile(old, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-61 * 86_400))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let sessions = try XCTUnwrap(
            result.snapshot.agents
                .first { $0.provider == .codex }?
                .artifacts.first { $0.kind == .activeSessions }
        )

        XCTAssertEqual(sessions.actionCandidates.map(\.path), [old.standardizedFileURL.path])
        XCTAssertGreaterThan(sessions.previewBytes, 0)
    }

    func testArchivedSessionsAndBackupsBecomeCandidatesAfterThirtyDays() async throws {
        let home = try makeHome()
        let archived = home.appendingPathComponent(".codex/archived_sessions/archived.jsonl")
        let oldBackup = home.appendingPathComponent(".codex/backups/logs_2_pre_vacuum/snapshot.bin")
        let recentBackup = home.appendingPathComponent(".codex/backups/logs_2_recent/recent.bin")
        try writeFile(archived, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-35 * 86_400))
        try writeFile(oldBackup, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-40 * 86_400))
        try writeFile(recentBackup, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-10 * 86_400))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let codex = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .codex })
        let archivedArtifact = try XCTUnwrap(codex.artifacts.first { $0.kind == .archivedSessions })
        let backupsArtifact = try XCTUnwrap(codex.artifacts.first { $0.kind == .backups })

        XCTAssertEqual(archivedArtifact.actionCandidates.map(\.path), [archived.standardizedFileURL.path])
        XCTAssertEqual(backupsArtifact.disposition, .review)
        XCTAssertEqual(backupsArtifact.actionCandidates.map(\.path), [oldBackup.standardizedFileURL.path])
    }

    func testGeneratedMediaStaysReadOnlyEvenWhenVeryOld() async throws {
        let home = try makeHome()
        let image = home.appendingPathComponent(".codex/generated_images/abc/img.png")
        try writeFile(image, bytes: 16_384, modifiedAt: Date().addingTimeInterval(-120 * 86_400))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let media = try XCTUnwrap(
            result.snapshot.agents
                .first { $0.provider == .codex }?
                .artifacts.first { $0.kind == .generatedMedia }
        )

        XCTAssertEqual(media.disposition, .review)
        XCTAssertGreaterThan(media.previewBytes, 0)
        XCTAssertTrue(media.actionCandidates.isEmpty)
        XCTAssertTrue(media.protectionReasons.contains { $0.contains("产出资产") })
    }

    func testInstallerLeftoverWithExtractedSiblingIsReclassifiedAndActionable() async throws {
        let home = try makeHome()
        let bundle = home.appendingPathComponent(
            "Library/Application Support/Claude/vm_bundles/claudevm.bundle"
        )
        let rootfs = bundle.appendingPathComponent("rootfs.img")
        let archive = bundle.appendingPathComponent("rootfs.img.zst")
        let oldDate = Date().addingTimeInterval(-45 * 86_400)
        try writeFile(rootfs, bytes: 32_768, modifiedAt: oldDate)
        try writeFile(archive, bytes: 8_192, modifiedAt: oldDate)

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let claude = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .claude })
        let leftovers = try XCTUnwrap(claude.artifacts.first { $0.kind == .installerLeftovers })
        let virtualMachines = try XCTUnwrap(claude.artifacts.first { $0.kind == .virtualMachines })

        XCTAssertEqual(leftovers.disposition, .regenerable)
        XCTAssertEqual(leftovers.actionCandidates.map(\.path), [archive.standardizedFileURL.path])
        XCTAssertTrue(leftovers.protectionReasons.contains { $0.contains("已解压") })
        // 整组 45 天未写入的虚拟机进入复核层，并释放组内文件为候选。
        XCTAssertEqual(virtualMachines.disposition, .review)
        XCTAssertTrue(virtualMachines.actionCandidates.contains {
            $0.path == rootfs.standardizedFileURL.path
        })
        XCTAssertTrue(virtualMachines.protectionReasons.contains { $0.contains("未写入") })
    }

    func testArchiveWithoutExtractedSiblingStaysInOriginalKind() async throws {
        let home = try makeHome()
        let bundle = home.appendingPathComponent(
            "Library/Application Support/Claude/vm_bundles/claudevm.bundle"
        )
        let archive = bundle.appendingPathComponent("rootfs.img.zst")
        try writeFile(archive, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-45 * 86_400))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let claude = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .claude })

        XCTAssertNil(claude.artifacts.first { $0.kind == .installerLeftovers })
        let virtualMachines = try XCTUnwrap(claude.artifacts.first { $0.kind == .virtualMachines })
        XCTAssertEqual(virtualMachines.actionCandidates.map(\.kind), [.virtualMachines])
    }

    func testActiveVirtualMachineGroupStaysKeepButStillShedsInstallerLeftovers() async throws {
        let home = try makeHome()
        let bundle = home.appendingPathComponent(
            "Library/Application Support/Claude/vm_bundles/claudevm.bundle"
        )
        let rootfs = bundle.appendingPathComponent("rootfs.img")
        let archive = bundle.appendingPathComponent("rootfs.img.zst")
        try writeFile(rootfs, bytes: 32_768, modifiedAt: Date().addingTimeInterval(-2 * 86_400))
        try writeFile(archive, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-45 * 86_400))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let claude = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .claude })
        let virtualMachines = try XCTUnwrap(claude.artifacts.first { $0.kind == .virtualMachines })
        let leftovers = try XCTUnwrap(claude.artifacts.first { $0.kind == .installerLeftovers })

        // 活跃虚拟机整组保持保留，组内文件不产生候选；
        // 已解压就位的陈旧安装包仍单独进入可再生态。
        XCTAssertEqual(virtualMachines.disposition, .keep)
        XCTAssertTrue(virtualMachines.actionCandidates.isEmpty)
        XCTAssertEqual(leftovers.actionCandidates.map(\.path), [archive.standardizedFileURL.path])
    }

    func testArchiveBelowInstallerFloorKeepsOriginalKind() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache")
        let payload = cache.appendingPathComponent("setup.pkg")
        let sibling = cache.appendingPathComponent("setup")
        let oldDate = Date().addingTimeInterval(-45 * 86_400)
        try writeFile(payload, bytes: 8_192, modifiedAt: oldDate)
        try writeFile(sibling, bytes: 8_192, modifiedAt: oldDate)

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration(
            installerLeftoverMinimumBytes: 1_000_000
        )).scan(homeDirectory: home, openFiles: [])
        let codex = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .codex })

        XCTAssertNil(codex.artifacts.first { $0.kind == .installerLeftovers })
        let caches = try XCTUnwrap(codex.artifacts.first { $0.kind == .caches })
        XCTAssertEqual(caches.actionCandidates.count, 2)
    }

    func testRecoveryAcceptsOldBackupCandidate() async throws {
        let home = try makeHome()
        let backup = home.appendingPathComponent(".codex/backups/logs_2_sqlite/dump.bin")
        let payload = Data("old maintenance snapshot".utf8)
        try FileManager.default.createDirectory(
            at: backup.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: backup)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-40 * 86_400)],
            ofItemAtPath: backup.path
        )
        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let candidate = try XCTUnwrap(result.snapshot.actionCandidates.first)
        XCTAssertEqual(candidate.kind, .backups)
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: home.appendingPathComponent("Library/Application Support/CleanNest/AgentRecovery")
        )

        let recovered = try await service.createRecovery(candidates: [candidate])

        XCTAssertEqual(recovered.record.status, .available)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))

        let restored = try await service.restore(operationID: recovered.record.id)

        XCTAssertEqual(restored.record.status, .restored)
        XCTAssertEqual(try Data(contentsOf: backup), payload)
    }

    func testRecoveryRejectsSessionBelowPolicyAgeGate() async throws {
        let home = try makeHome()
        let session = home.appendingPathComponent(".codex/sessions/2026/08/recent.jsonl")
        try writeFile(session, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-2 * 3_600))
        // 扫描配置把会话门槛压到 1 小时以产出候选；执行侧仍按默认 60 天复核，
        // 验证扫描门与执行门是同一策略的两道独立检查。
        let scan = try await AgentWorkspaceScanner(configuration: testConfiguration(
            sessionCandidateInterval: 3_600
        )).scan(homeDirectory: home, openFiles: [])
        let candidate = try XCTUnwrap(scan.snapshot.actionCandidates.first)
        XCTAssertEqual(candidate.kind, .activeSessions)
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: home.appendingPathComponent("Library/Application Support/CleanNest/AgentRecovery")
        )

        do {
            _ = try await service.createRecovery(candidates: [candidate])
            XCTFail("Expected session below the 60-day gate to be rejected")
        } catch let error as AgentWorkspaceRecoveryError {
            XCTAssertEqual(error, .fileRecentlyModified)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: session.path))
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
        XCTAssertEqual(cacheArtifact.actionCandidates.count, 1)
        XCTAssertEqual(cacheArtifact.actionCandidates.first?.path, cache.standardizedFileURL.path)
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
        XCTAssertGreaterThan(try XCTUnwrap(
            current.snapshot.agents.first { $0.provider == .codex }?.allocatedBytesChange
        ), 0)
    }

    func testSummaryScanDoesNotBuildFileActionCandidates() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/settled.bin")
        try writeFile(cache, bytes: 8_192, modifiedAt: Date().addingTimeInterval(-3_600))

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: [],
            actionCandidateProviders: []
        )

        XCTAssertEqual(result.snapshot.detectedAgents.map(\.provider), [.codex])
        XCTAssertTrue(result.snapshot.actionCandidates.isEmpty)
        XCTAssertGreaterThan(result.snapshot.allocatedBytes, 0)
    }

    func testScopedDetailScanBuildsCandidatesOnlyForRequestedProvider() async throws {
        let home = try makeHome()
        try writeFile(
            home.appendingPathComponent(".codex/cache/codex.bin"),
            bytes: 8_192,
            modifiedAt: Date().addingTimeInterval(-3_600)
        )
        try writeFile(
            home.appendingPathComponent("Library/Application Support/Claude/Cache/claude.bin"),
            bytes: 8_192,
            modifiedAt: Date().addingTimeInterval(-3_600)
        )

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: [],
            providers: [.claude],
            actionCandidateProviders: [.claude]
        )

        XCTAssertEqual(result.snapshot.agents.map(\.provider), [.claude])
        XCTAssertEqual(Set(result.snapshot.actionCandidates.map(\.provider)), [.claude])
    }

    func testReadOnlyProviderCannotGainCandidatesFromScopedDetailRequest() async throws {
        let home = try makeHome()
        try writeFile(
            home.appendingPathComponent(".pi/agent/cache/settled.bin"),
            bytes: 8_192,
            modifiedAt: Date().addingTimeInterval(-3_600)
        )

        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: [],
            providers: [.piAgent],
            actionCandidateProviders: [.piAgent]
        )

        XCTAssertTrue(result.snapshot.actionCandidates.isEmpty)
    }

    func testMergingDetailPreservesOtherProviderSummaryWithoutActionTokens() async throws {
        let home = try makeHome()
        try writeFile(
            home.appendingPathComponent(".codex/cache/codex.bin"),
            bytes: 8_192,
            modifiedAt: Date().addingTimeInterval(-3_600)
        )
        try writeFile(
            home.appendingPathComponent("Library/Application Support/Claude/Cache/claude.bin"),
            bytes: 8_192,
            modifiedAt: Date().addingTimeInterval(-3_600)
        )
        let scanner = AgentWorkspaceScanner(configuration: testConfiguration())
        let summary = try await scanner.scan(
            homeDirectory: home,
            openFiles: [],
            actionCandidateProviders: []
        )
        let detail = try await scanner.scan(
            homeDirectory: home,
            openFiles: [],
            providers: [.codex],
            actionCandidateProviders: [.codex]
        )

        let merged = summary.snapshot.mergingDetail(detail.snapshot, for: .codex)

        XCTAssertEqual(merged.detectedAgents.count, 2)
        XCTAssertFalse(merged.actionCandidates.isEmpty)
        XCTAssertTrue(merged.actionCandidates.allSatisfy { $0.provider == .codex })
        XCTAssertTrue(
            merged.agents.first { $0.provider == .claude }?
                .artifacts.flatMap(\.actionCandidates).isEmpty == true
        )
        XCTAssertTrue(merged.withoutActionCandidates().actionCandidates.isEmpty)
        XCTAssertEqual(
            merged.withoutActionCandidates().allocatedBytes,
            merged.allocatedBytes
        )
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

    func testBackupFirstRecoveryRemovesAndRestoresSettledCacheFile() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/recoverable.log")
        let payload = Data("recover me".utf8)
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: cache)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3_600)],
            ofItemAtPath: cache.path
        )
        let result = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let candidate = try XCTUnwrap(result.snapshot.actionCandidates.first)
        let recoveryRoot = home.appendingPathComponent("Library/Application Support/CleanNest/AgentRecovery")
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: recoveryRoot,
            recentInterval: 15 * 60
        )

        let recovered = try await service.createRecovery(candidates: [candidate])

        XCTAssertEqual(recovered.record.status, .available)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recovered.operationDirectory.appendingPathComponent("backup.zip").path
        ))
        let manifestPermissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: recovered.operationDirectory.appendingPathComponent("manifest.json").path
            )[.posixPermissions] as? NSNumber
        ).intValue
        XCTAssertEqual(manifestPermissions & 0o777, 0o600)
        XCTAssertEqual(try service.listRecords().map(\.id), [recovered.record.id])

        let restored = try await service.restore(operationID: recovered.record.id)

        XCTAssertEqual(restored.record.status, .restored)
        XCTAssertEqual(try Data(contentsOf: cache), payload)
    }

    func testRestoreRefusesToOverwriteAgentRecreatedFile() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/recreated.bin")
        try writeFile(cache, bytes: 4_096, modifiedAt: Date().addingTimeInterval(-3_600))
        let scan = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let candidate = try XCTUnwrap(scan.snapshot.actionCandidates.first)
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: home.appendingPathComponent("Library/Application Support/CleanNest/AgentRecovery")
        )
        let operation = try await service.createRecovery(candidates: [candidate])
        try Data("new agent data".utf8).write(to: cache)

        do {
            _ = try await service.restore(operationID: operation.record.id)
            XCTFail("Expected restore conflict")
        } catch let error as AgentWorkspaceRecoveryError {
            guard case .restoreConflict = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: cache), Data("new agent data".utf8))
    }

    func testRestoreRejectsArchiveChangedAfterVerifiedBackup() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/archive-tamper.bin")
        let payload = Data("verified payload".utf8)
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: cache)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3_600)],
            ofItemAtPath: cache.path
        )
        let scan = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let candidate = try XCTUnwrap(scan.snapshot.actionCandidates.first)
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: home.appendingPathComponent("Library/Application Support/CleanNest/AgentRecovery")
        )
        let operation = try await service.createRecovery(candidates: [candidate])
        let archive = operation.operationDirectory.appendingPathComponent("backup.zip")
        let handle = try FileHandle(forWritingTo: archive)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("tampered".utf8))
        try handle.close()

        do {
            _ = try await service.restore(operationID: operation.record.id)
            XCTFail("Expected archive verification failure")
        } catch let error as AgentWorkspaceRecoveryError {
            XCTAssertEqual(error, .backupVerificationFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
    }

    func testRestoreRetryAfterCrashRecognizesOwnExtractedFiles() async throws {
        let home = try makeHome()
        let cache = home.appendingPathComponent(".codex/cache/retry.bin")
        let payload = Data("resume me after crash".utf8)
        try FileManager.default.createDirectory(
            at: cache.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: cache)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3_600)],
            ofItemAtPath: cache.path
        )
        let scan = try await AgentWorkspaceScanner(configuration: testConfiguration()).scan(
            homeDirectory: home,
            openFiles: []
        )
        let candidate = try XCTUnwrap(scan.snapshot.actionCandidates.first)
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: home.appendingPathComponent("Library/Application Support/CleanNest/AgentRecovery")
        )
        let operation = try await service.createRecovery(candidates: [candidate])
        let firstRestore = try await service.restore(operationID: operation.record.id)
        XCTAssertEqual(firstRestore.record.status, .restored)
        XCTAssertEqual(try Data(contentsOf: cache), payload)

        // 模拟崩溃后遗留的旧式清单：逐项恢复标记全部缺失（等价于 0.8.0 之前的记录）。
        // 此时原位置的文件是上次恢复解压出的新身份文件。
        let manifestURL = operation.operationDirectory.appendingPathComponent("manifest.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var record = try decoder.decode(
            AgentWorkspaceRecoveryRecord.self,
            from: Data(contentsOf: manifestURL)
        )
        for index in record.items.indices { record.items[index].restoredAt = nil }
        record.status = .available
        record.restoredAt = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(record).write(to: manifestURL, options: .atomic)

        // 重试恢复：内容与权威副本一致 → 识别为自身产物，不再误报 restoreConflict。
        let retry = try await service.restore(operationID: operation.record.id)
        XCTAssertEqual(retry.record.status, .restored)
        XCTAssertEqual(try Data(contentsOf: cache), payload)

        // 全部项已标记后再次恢复是空操作。
        let third = try await service.restore(operationID: operation.record.id)
        XCTAssertEqual(third.record.status, .restored)
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
        growthCriticalBytes: Int64 = Int64.max / 2,
        sessionCandidateInterval: TimeInterval = 60 * 86_400,
        installerLeftoverMinimumBytes: Int64 = 1_024
    ) -> AgentWorkspaceScanner.Configuration {
        AgentWorkspaceScanner.Configuration(
            recentInterval: 15 * 60,
            oldInterval: 30 * 86_400,
            sessionCandidateInterval: sessionCandidateInterval,
            installerLeftoverMinimumBytes: installerLeftoverMinimumBytes,
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
