import Darwin
import XCTest
@testable import CleanNestCore

final class LocalModelRuntimeTopologyTests: XCTestCase {
    func testAdapterRegistryCoversSupportedPlatformsAndAPIStyles() throws {
        XCTAssertEqual(
            Set(LocalModelPlatformAdapterRegistry.adapters.map(\.platform)),
            Set([.omlx, .mlxLM, .mlxServe, .ollama, .lmStudio, .llamaCPP])
        )
        XCTAssertEqual(
            LocalModelPlatformAdapterRegistry.adapter(for: .ollama)?.apiStyle,
            .ollama
        )
        XCTAssertEqual(
            LocalModelPlatformAdapterRegistry.adapter(for: .omlx)?.defaultPorts,
            [8_080]
        )
        XCTAssertEqual(
            LocalModelPlatformAdapterRegistry.adapter(for: .mlxServe)?.defaultPorts,
            [11_234]
        )
        XCTAssertEqual(
            LocalModelPlatformAdapterRegistry.adapter(for: .mlxServe)?.apiStyle,
            .openAICompatible
        )
        XCTAssertTrue(LocalModelPlatformAdapterRegistry.defaultPorts.contains(11_434))
        XCTAssertTrue(LocalModelPlatformAdapterRegistry.defaultPorts.contains(11_234))
    }

    func testEstablishedConnectionsAreParsedAndLinkedToServerPort() throws {
        let output = """
        p101
        cCodex
        f12
        n127.0.0.1:53456->127.0.0.1:8080 (ESTABLISHED)
        p202
        comlx-server
        f14
        n127.0.0.1:8080->127.0.0.1:53456 (ESTABLISHED)
        """
        let records = LocalModelRuntimeDiscovery.parseEstablishedFieldOutput(output)
        XCTAssertEqual(records.count, 2)

        let clients = LocalModelRuntimeDiscovery.clientConnections(
            forPort: 8_080,
            serverProcessID: 202,
            connections: records
        )
        XCTAssertEqual(clients, [
            LocalModelClientConnection(
                processID: 101,
                commandName: "Codex",
                endpoint: LocalModelListener(host: "127.0.0.1", port: 53_456)
            )
        ])
    }

    func testControlLevelsKeepOtherUsersReadOnly() {
        let currentUserRuntime = runtime(
            id: "ollama:42:11434",
            platform: .ollama,
            pid: 42,
            ownerUserID: UInt32(getuid())
        )
        XCTAssertEqual(currentUserRuntime.controlLevel, .currentUserProcess)
        XCTAssertTrue(currentUserRuntime.canRequestExternalStop)

        let otherUserRuntime = runtime(
            id: "ollama:43:11434",
            platform: .ollama,
            pid: 43,
            ownerUserID: UInt32(getuid()) &+ 1
        )
        XCTAssertEqual(otherUserRuntime.controlLevel, .protectedReadOnly)
        XCTAssertFalse(otherUserRuntime.canRequestExternalStop)
    }

    func testCurrentUserLaunchAgentGetsDedicatedControlLevel() {
        let supervisor = LocalModelSupervisorSnapshot(
            label: "com.example.omlx",
            domain: "gui/\(getuid())",
            kind: .userLaunchAgent,
            sourcePath: "/Users/example/Library/LaunchAgents/com.example.omlx.plist",
            sourceDeviceID: 1,
            sourceFileID: 2,
            programName: "omlx",
            keepAlive: true,
            runAtLoad: true,
            isLoaded: true,
            isDisabled: false,
            processID: 44,
            isOwnedByCurrentUser: true,
            platform: .omlx
        )
        let value = runtime(
            id: "omlx:44:8080",
            platform: .omlx,
            pid: 44,
            ownerUserID: UInt32(getuid()),
            supervisor: supervisor
        )
        XCTAssertEqual(value.controlLevel, .currentUserLaunchAgent)
        XCTAssertTrue(value.issues.contains(where: { $0.kind == .automaticRestart }))
    }

    func testStartPolicyExplainsMissingConfigurationUnsupportedEngineAndPortConflict() {
        XCTAssertEqual(
            LocalModelStartPolicy.evaluate(
                modelIsComplete: false,
                executablePath: "/opt/homebrew/bin/omlx",
                configuredPort: 8_080,
                runtimes: [],
                isBusy: false
            ),
            .configurationMissing("本机模型目录不完整，或尚未选择模型。")
        )
        XCTAssertEqual(
            LocalModelStartPolicy.evaluate(
                modelIsComplete: true,
                executablePath: "/opt/homebrew/bin/ollama",
                configuredPort: 11_434,
                runtimes: [],
                isBusy: false
            ),
            .unsupportedExecutable("CleanNest 自启目前只支持 oMLX 与 MLX-LM；其他平台保持发现和确认后控制。")
        )

        let occupied = runtime(
            id: "ollama:55:8080",
            platform: .ollama,
            pid: 55,
            ownerUserID: UInt32(getuid()),
            port: 8_080
        )
        XCTAssertEqual(
            LocalModelStartPolicy.evaluate(
                modelIsComplete: true,
                executablePath: "/opt/homebrew/bin/omlx",
                configuredPort: 8_080,
                runtimes: [occupied],
                isBusy: false
            ),
            .portOccupied(occupied)
        )
        XCTAssertEqual(
            LocalModelStartPolicy.evaluate(
                modelIsComplete: true,
                executablePath: "/opt/homebrew/bin/omlx",
                configuredPort: 8_080,
                runtimes: [],
                isBusy: false
            ),
            .ready
        )
    }

    func testTopologyKeepsPlatformServiceModelClientAndGuardianChain() throws {
        let client = LocalModelClientConnection(
            processID: 88,
            commandName: "Codex",
            endpoint: LocalModelListener(host: "127.0.0.1", port: 53_456)
        )
        let value = runtime(
            id: "omlx:66:8080",
            platform: .omlx,
            pid: 66,
            ownerUserID: UInt32(getuid()),
            clients: [client]
        )
        let snapshot = LocalModelRuntimeSnapshot(instances: [value], diagnostic: "ok")
        let platform = try XCTUnwrap(snapshot.topology.first)
        let service = try XCTUnwrap(platform.services.first)

        XCTAssertEqual(platform.platform, .omlx)
        XCTAssertEqual(service.address, "127.0.0.1:8080")
        XCTAssertEqual(service.modelIDs, ["Qwen-short-id"])
        XCTAssertEqual(service.clients, [client])
        XCTAssertEqual(service.controlLevel, .currentUserProcess)
    }

    func testTransitionDetectorSeparatesReplacementAndModelChange() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let old = runtime(
            id: "omlx:70:8080",
            platform: .omlx,
            pid: 70,
            ownerUserID: UInt32(getuid())
        )
        let replacement = runtime(
            id: "omlx:71:8080",
            platform: .omlx,
            pid: 71,
            ownerUserID: UInt32(getuid())
        )
        let replacementTransitions = LocalModelRuntimeTransitionDetector.compare(
            previous: LocalModelRuntimeSnapshot(capturedAt: date, instances: [old], diagnostic: "old"),
            current: LocalModelRuntimeSnapshot(capturedAt: date.addingTimeInterval(1), instances: [replacement], diagnostic: "new"),
            date: date.addingTimeInterval(1)
        )
        XCTAssertEqual(replacementTransitions.map(\.kind), [.processReplaced])

        let changedModel = runtime(
            id: old.id,
            platform: .omlx,
            pid: 70,
            ownerUserID: UInt32(getuid()),
            modelIDs: ["Another-short-id"]
        )
        let modelTransitions = LocalModelRuntimeTransitionDetector.compare(
            previous: LocalModelRuntimeSnapshot(capturedAt: date, instances: [old], diagnostic: "old"),
            current: LocalModelRuntimeSnapshot(capturedAt: date.addingTimeInterval(1), instances: [changedModel], diagnostic: "new"),
            date: date.addingTimeInterval(1)
        )
        XCTAssertEqual(modelTransitions.map(\.kind), [.modelChanged])
    }

    func testRepeatedModelUpDownSequenceNeverInventsReplacement() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let stopped = LocalModelRuntimeSnapshot(
            capturedAt: date,
            instances: [],
            diagnostic: "stopped"
        )
        let runningValue = runtime(
            id: "omlx:80:8080",
            platform: .omlx,
            pid: 80,
            ownerUserID: UInt32(getuid())
        )
        let running = LocalModelRuntimeSnapshot(
            capturedAt: date.addingTimeInterval(1),
            instances: [runningValue],
            diagnostic: "running"
        )

        XCTAssertEqual(
            LocalModelRuntimeTransitionDetector.compare(
                previous: stopped,
                current: running,
                date: date.addingTimeInterval(1)
            ).map(\.kind),
            [.appeared]
        )
        XCTAssertEqual(
            LocalModelRuntimeTransitionDetector.compare(
                previous: running,
                current: LocalModelRuntimeSnapshot(
                    capturedAt: date.addingTimeInterval(2),
                    instances: [],
                    diagnostic: "stopped again"
                ),
                date: date.addingTimeInterval(2)
            ).map(\.kind),
            [.disappeared]
        )
    }

    private func runtime(
        id: String,
        platform: LocalModelPlatform,
        pid: Int32,
        ownerUserID: UInt32,
        port: Int = 8_080,
        supervisor: LocalModelSupervisorSnapshot? = nil,
        clients: [LocalModelClientConnection] = [],
        modelIDs: [String] = ["Qwen-short-id"]
    ) -> LocalModelRuntimeInstance {
        var issues: [LocalModelRuntimeIssue] = []
        if let supervisor, supervisor.keepAlive || supervisor.runAtLoad {
            issues.append(.init(
                kind: .automaticRestart,
                title: "关闭 PID 后可能自动重启",
                detail: supervisor.restartDescription,
                isWarning: true
            ))
        }
        return LocalModelRuntimeInstance(
            id: id,
            platform: platform,
            phase: .runningHealthy,
            modelIDs: modelIDs,
            defaultModelID: modelIDs.first,
            process: LocalModelProcessSnapshot(
                pid: pid,
                commandName: platform.shortName,
                executablePath: "/opt/homebrew/bin/\(platform.rawValue)",
                residentMemoryBytes: 1_024,
                startedAt: Date(timeIntervalSince1970: 1_700_000_000),
                ownerUserID: ownerUserID
            ),
            supervisor: supervisor,
            listeners: [LocalModelListener(host: "127.0.0.1", port: port)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .listener, .platformAPI],
            diagnostic: "已确认",
            clients: clients,
            issues: issues
        )
    }
}
