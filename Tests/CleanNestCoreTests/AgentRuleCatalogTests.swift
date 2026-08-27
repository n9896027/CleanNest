import Darwin
import XCTest
@testable import CleanNestCore
import CleanNestMutation

final class AgentRuleCatalogTests: XCTestCase {
    func testBuiltInCatalogCoversEveryProviderAndKeepsMutationBoundaryHardCoded() throws {
        let catalog = AgentRuleCatalog.builtIn

        XCTAssertNoThrow(try catalog.validate())
        XCTAssertEqual(Set(catalog.providers.map(\.provider)), Set(AgentWorkspaceProvider.allCases))
        XCTAssertTrue(AgentWorkspaceProvider.codex.supportsBackupFirstRecovery)
        XCTAssertTrue(AgentWorkspaceProvider.claude.supportsBackupFirstRecovery)
        XCTAssertTrue(AgentWorkspaceProvider.allCases
            .filter { ![.codex, .claude].contains($0) }
            .allSatisfy { !$0.supportsBackupFirstRecovery })
        let pi = try XCTUnwrap(catalog.rule(for: .piAgent))
        XCTAssertEqual(pi.bundleIdentifiers, ["com.abcwyc.pi-agent"])
        XCTAssertTrue(pi.roots.contains { $0.base == .home && $0.relativePath == ".pi/agent" })
        XCTAssertEqual(catalog.rule(for: .xiaoyunque)?.verification, .detectionOnly)
        XCTAssertEqual(catalog.rule(for: .xiaoyunque)?.roots, [])
    }

    func testCatalogRejectsParentTraversalBeforeItCanReachScanner() throws {
        let builtIn = AgentRuleCatalog.builtIn
        let providers = builtIn.providers.map { rule -> AgentProviderRule in
            guard rule.provider == .kimi else { return rule }
            return AgentProviderRule(
                provider: rule.provider,
                verification: rule.verification,
                roots: [.init(base: .home, relativePath: "../Documents")],
                bundleIdentifiers: rule.bundleIdentifiers,
                applicationNames: rule.applicationNames,
                processMarkers: rule.processMarkers,
                supervisorMarkers: rule.supervisorMarkers,
                artifactRules: rule.artifactRules
            )
        }

        XCTAssertThrowsError(try AgentRuleCatalog(
            revision: "invalid-traversal",
            issuedAt: Date(),
            providers: providers
        )) { error in
            XCTAssertEqual(error as? AgentRuleCatalogError, .invalidPath("../Documents"))
        }
    }

    func testKimiCacheIsVisibleButNeverBecomesActionCandidate() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/kimi-code/http/old.bin")
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 8_192).write(to: cache)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-3_600)],
            ofItemAtPath: cache.path
        )

        let result = try await AgentWorkspaceScanner().scan(
            homeDirectory: home,
            openFiles: [],
            catalog: .builtIn
        )
        let kimi = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .kimi })
        let artifact = try XCTUnwrap(kimi.artifacts.first { $0.kind == .caches })

        XCTAssertTrue(kimi.detected)
        XCTAssertGreaterThan(artifact.allocatedBytes, 0)
        XCTAssertEqual(artifact.previewBytes, 0)
        XCTAssertTrue(artifact.actionCandidates.isEmpty)
        XCTAssertTrue(artifact.protectionReasons.contains { $0.contains("只读适配") })
    }

    func testPiAgentFootprintsAreClassifiedButRemainReadOnly() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let session = home.appendingPathComponent(".pi/agent/sessions/project/session.jsonl")
        let auth = home.appendingPathComponent(".pi/agent/auth.json")
        let cache = home.appendingPathComponent("Library/Caches/com.abcwyc.pi-agent/WebKit/cache.bin")
        for file in [session, auth, cache] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 0x50, count: 4_096).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-3_600)],
                ofItemAtPath: file.path
            )
        }

        let result = try await AgentWorkspaceScanner().scan(
            homeDirectory: home,
            openFiles: [],
            catalog: .builtIn
        )
        let pi = try XCTUnwrap(result.snapshot.agents.first { $0.provider == .piAgent })

        XCTAssertTrue(pi.detected)
        XCTAssertNotNil(pi.artifacts.first { $0.kind == .activeSessions })
        XCTAssertNotNil(pi.artifacts.first { $0.kind == .credentials })
        XCTAssertNotNil(pi.artifacts.first { $0.kind == .caches })
        XCTAssertEqual(pi.previewBytes, 0)
        XCTAssertTrue(pi.artifacts.flatMap(\.actionCandidates).isEmpty)
        XCTAssertTrue(pi.artifacts.allSatisfy { artifact in
            artifact.protectionReasons.contains { $0.contains("只读适配") }
        })
    }

    func testRecoveryRejectsNonCodexProviderBeforeFilesystemMutation() async throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent(".kimi/cache.bin")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("cache".utf8).write(to: file)
        let identity = try AgentWorkspaceFileIdentity.capture(at: file)
        let candidate = AgentWorkspaceActionCandidate(
            id: "synthetic-kimi",
            provider: .kimi,
            kind: .caches,
            path: file.path,
            identity: identity,
            scannedAt: Date()
        )
        let service = AgentWorkspaceRecoveryService(
            homeDirectory: home,
            recoveryRoot: home.appendingPathComponent("recovery")
        )

        do {
            _ = try await service.createRecovery(candidates: [candidate])
            XCTFail("Expected unsupported provider")
        } catch let error as AgentWorkspaceRecoveryError {
            XCTAssertEqual(error, .unsupportedCategory)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: home.appendingPathComponent("recovery").path))
    }

    func testGraphLinksAgentToModelOnlyWithEstablishedTCPPeerEvidence() async throws {
        let workspace = AgentWorkspaceSnapshot(
            capturedAt: Date(),
            previousCapturedAt: nil,
            agents: [.init(provider: .kimi, detected: true, artifacts: [])],
            alerts: [],
            openFileProbeSucceeded: true,
            diagnostic: "test"
        )
        let model = LocalModelRuntimeInstance(
            id: "omlx-8080",
            platform: .omlx,
            phase: .runningHealthy,
            modelIDs: ["Qwen3.8-27B-Uncensored-8bit"],
            defaultModelID: "Qwen3.8-27B-Uncensored-8bit",
            process: .init(pid: 900, commandName: "omlx", executablePath: "/usr/local/bin/omlx", residentMemoryBytes: nil, startedAt: nil),
            listeners: [.init(host: "127.0.0.1", port: 8080)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .listener, .platformAPI],
            diagnostic: "test"
        )
        let ps = "101 1 \(getuid()) 4096 /Applications/Kimi.app/Contents/MacOS/Kimi"
        let builder = AgentDependencyGraphBuilder()
        let withoutConnection = await builder.build(
            workspace: workspace,
            catalog: .builtIn,
            localModels: .init(instances: [model], diagnostic: "test"),
            suppliedProcessOutput: ps,
            suppliedLaunchctlOutput: "",
            suppliedConnectionOutput: "",
            suppliedApplications: []
        )
        XCTAssertEqual(withoutConnection.confirmedModelConnectionCount, 0)

        let withConnection = await builder.build(
            workspace: workspace,
            catalog: .builtIn,
            localModels: .init(instances: [model], diagnostic: "test"),
            suppliedProcessOutput: ps,
            suppliedLaunchctlOutput: "",
            suppliedConnectionOutput: "p101\ncKimi\nn127.0.0.1:50123->127.0.0.1:8080",
            suppliedApplications: []
        )
        XCTAssertEqual(withConnection.confirmedModelConnectionCount, 1)
        XCTAssertTrue(withConnection.edges.contains {
            $0.sourceID == "process:101"
                && $0.relation == .connectsToModel
                && $0.evidence == .establishedTCPConnection
        })
    }

    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNest-AgentRules-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
