import XCTest
@testable import CleanNestCore

final class LocalModelRuntimeDiscoveryTests: XCTestCase {
    func testLsofParserKeepsProcessAndListenerIdentity() throws {
        let output = """
        p46159
        comlx-server
        f4
        n127.0.0.1:8080
        p222
        collama
        f9
        n*:11434
        p333
        cllama-server
        f7
        n[::1]:9000
        """

        let records = LocalModelRuntimeDiscovery.parseLsofFieldOutput(output)
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records[0].pid, 46_159)
        XCTAssertEqual(records[0].commandName, "omlx-server")
        XCTAssertEqual(records[0].listener, LocalModelListener(host: "127.0.0.1", port: 8_080))
        XCTAssertEqual(records[1].listener, LocalModelListener(host: "*", port: 11_434))
        XCTAssertTrue(records[1].listener.isWildcard)
        XCTAssertEqual(records[2].listener, LocalModelListener(host: "::1", port: 9_000))
        XCTAssertTrue(records[2].listener.isLoopback)
    }

    func testPlatformClassifierUsesRuntimeEvidenceWithoutGenericPythonGuess() {
        XCTAssertEqual(LocalModelRuntimeDiscovery.classifyPlatform(text: "omlx-server"), .omlx)
        XCTAssertEqual(
            LocalModelRuntimeDiscovery.classifyPlatform(text: "python -m mlx_lm.server --port 8080"),
            .mlxLM
        )
        XCTAssertEqual(LocalModelRuntimeDiscovery.classifyPlatform(text: "/opt/homebrew/bin/ollama serve"), .ollama)
        XCTAssertEqual(LocalModelRuntimeDiscovery.classifyPlatform(text: "LM Studio"), .lmStudio)
        XCTAssertEqual(LocalModelRuntimeDiscovery.classifyPlatform(text: "llama-server -m model.gguf"), .llamaCPP)
        XCTAssertNil(LocalModelRuntimeDiscovery.classifyPlatform(text: "python app.py"))
    }

    func testRuntimeRequiresAPIEvidenceBeforeHealthyState() {
        let process = LocalModelProcessSnapshot(
            pid: 42,
            commandName: "omlx-server",
            executablePath: nil,
            residentMemoryBytes: 100,
            startedAt: nil
        )
        let unverified = LocalModelRuntimeInstance(
            id: "omlx:42:8080",
            platform: .omlx,
            phase: .runningUnverified,
            modelIDs: [],
            defaultModelID: nil,
            process: process,
            listeners: [LocalModelListener(host: "127.0.0.1", port: 8_080)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .listener],
            diagnostic: "API 未确认"
        )
        let snapshot = LocalModelRuntimeSnapshot(instances: [unverified], diagnostic: "待确认")

        XCTAssertEqual(snapshot.phase, .runningUnverified)
        XCTAssertTrue(snapshot.healthyInstances.isEmpty)
        XCTAssertNil(snapshot.primaryInstance?.primaryModelID)
    }

    func testModelIDsRejectPathsAndOwnershipMatchesExactPID() {
        let process = LocalModelProcessSnapshot(
            pid: 4_615,
            commandName: "omlx-server",
            executablePath: nil,
            residentMemoryBytes: nil,
            startedAt: nil
        )
        let runtime = LocalModelRuntimeInstance(
            id: "omlx:4615:8080",
            platform: .omlx,
            phase: .runningHealthy,
            modelIDs: [
                "/Users/example/Qwen",
                "file:///tmp/model",
                "Qwen3.8-27B-Uncensored-8bit",
                "qwen3.8-27b-uncensored-8bit"
            ],
            defaultModelID: "Qwen3.8-27B-Uncensored-8bit",
            process: process,
            listeners: [LocalModelListener(host: "127.0.0.1", port: 8_080)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .listener, .platformAPI],
            diagnostic: "健康"
        )

        XCTAssertEqual(runtime.modelIDs, ["Qwen3.8-27B-Uncensored-8bit"])
        XCTAssertEqual(runtime.primaryModelID, "Qwen3.8-27B-Uncensored-8bit")
        XCTAssertFalse(runtime.markingOwned(processID: 99).isOwnedByCleanNest)
        XCTAssertTrue(runtime.markingOwned(processID: 4_615).isOwnedByCleanNest)
        XCTAssertTrue(runtime.markingOwned(processID: 4_615).canStopDirectly)
    }

    func testWildcardListenerIsNotMistakenForLoopback() throws {
        let wildcard = try XCTUnwrap(LocalModelRuntimeDiscovery.parseListener("*:8080"))
        XCTAssertTrue(wildcard.isWildcard)
        XCTAssertFalse(wildcard.isLoopback)
        XCTAssertEqual(wildcard.displayAddress, "0.0.0.0:8080")
    }

    func testExternalStopRequiresStrongIdentityAndKnownRuntimeEvidence() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let process = LocalModelProcessSnapshot(
            pid: 4_615,
            commandName: "omlx-server",
            executablePath: "/opt/homebrew/bin/omlx-server",
            residentMemoryBytes: nil,
            startedAt: startedAt
        )
        let external = LocalModelRuntimeInstance(
            id: "omlx:4615:8080",
            platform: .omlx,
            phase: .runningHealthy,
            modelIDs: ["model-short-id"],
            defaultModelID: "model-short-id",
            process: process,
            listeners: [LocalModelListener(host: "127.0.0.1", port: 8_080)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .listener, .platformAPI],
            diagnostic: "健康"
        )

        XCTAssertTrue(external.canRequestExternalStop)
        XCTAssertFalse(external.markingOwned(processID: 4_615).canRequestExternalStop)

        let weakIdentity = LocalModelRuntimeInstance(
            id: "omlx:4615:process",
            platform: .omlx,
            phase: .runningUnverified,
            modelIDs: [],
            defaultModelID: nil,
            process: LocalModelProcessSnapshot(
                pid: 4_615,
                commandName: "omlx-server",
                executablePath: nil,
                residentMemoryBytes: nil,
                startedAt: nil
            ),
            listeners: [],
            exposure: .unknown,
            localNetworkAddresses: [],
            evidence: [.process],
            diagnostic: "只有进程证据"
        )
        XCTAssertFalse(weakIdentity.canRequestExternalStop)

        let unknownWithoutAPI = LocalModelRuntimeInstance(
            id: "openAICompatible:4615:8080",
            platform: .openAICompatible,
            phase: .runningUnverified,
            modelIDs: [],
            defaultModelID: nil,
            process: process,
            listeners: [LocalModelListener(host: "127.0.0.1", port: 8_080)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .listener],
            diagnostic: "API 未确认"
        )
        XCTAssertFalse(unknownWithoutAPI.canRequestExternalStop)
    }

    func testExternalStopIdentityValidationRejectsPIDReuse() {
        let expected = LocalModelProcessSnapshot(
            pid: 42,
            commandName: "ollama",
            executablePath: "/opt/homebrew/bin/ollama",
            residentMemoryBytes: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let matching = LocalModelProcessSnapshot(
            pid: 42,
            commandName: "ollama",
            executablePath: "/opt/homebrew/bin/ollama",
            residentMemoryBytes: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        let reused = LocalModelProcessSnapshot(
            pid: 42,
            commandName: "other",
            executablePath: "/tmp/other",
            residentMemoryBytes: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        XCTAssertNil(
            LocalModelExternalControlPolicy.identityMismatchReason(
                expected: expected,
                observed: matching
            )
        )
        XCTAssertNotNil(
            LocalModelExternalControlPolicy.identityMismatchReason(
                expected: expected,
                observed: reused
            )
        )
    }

    func testRuntimeDiscoveryNeverFollowsHTTPRedirects() throws {
        let proposed = URLRequest(
            url: try XCTUnwrap(URL(string: "http://192.168.1.10:8080/v1/models"))
        )

        XCTAssertNil(LocalModelRuntimeNetworkPolicy.redirectedRequest(proposed))
    }
}
