import XCTest
@testable import CleanNestCore

final class LocalModelSupervisorTests: XCTestCase {
    func testLaunchctlParsersKeepExactLabelsAndDisabledState() {
        let jobs = LocalModelSupervisorDiscovery.parseLaunchctlList("""
        PID\tStatus\tLabel
        11394\t-15\thomebrew.mxcl.omlx
        -\t0\thomebrew.mxcl.ollama
        99\t0\tbad/label
        """)
        XCTAssertEqual(
            jobs,
            [
                LocalModelLaunchdJob(label: "homebrew.mxcl.omlx", processID: 11_394),
                LocalModelLaunchdJob(label: "homebrew.mxcl.ollama", processID: nil)
            ]
        )

        let disabled = LocalModelSupervisorDiscovery.parseDisabledServices("""
        disabled services = {
            "homebrew.mxcl.omlx" => enabled
            "com.example.mlx" => disabled
        }
        """)
        XCTAssertEqual(disabled, ["com.example.mlx"])
    }

    func testSupervisorPolicyRequiresExactCurrentUserLaunchAgent() {
        let process = LocalModelProcessSnapshot(
            pid: 222,
            commandName: "omlx-server",
            executablePath: "/opt/homebrew/bin/omlx-server",
            residentMemoryBytes: nil,
            startedAt: Date(timeIntervalSince1970: 100)
        )
        let supervisor = makeSupervisor(processID: 222)
        let runtime = LocalModelRuntimeInstance(
            id: "omlx:222:8080",
            platform: .omlx,
            phase: .runningHealthy,
            modelIDs: ["short-id"],
            defaultModelID: "short-id",
            process: process,
            supervisor: supervisor,
            listeners: [LocalModelListener(host: "127.0.0.1", port: 8080)],
            exposure: .localOnly,
            localNetworkAddresses: [],
            evidence: [.process, .supervisor, .listener, .platformAPI],
            diagnostic: "healthy"
        )
        XCTAssertNil(LocalModelSupervisorControlPolicy.disableRefusalReason(runtime: runtime))

        let otherPID = makeSupervisor(processID: 333)
        let mismatched = LocalModelRuntimeInstance(
            id: runtime.id,
            platform: runtime.platform,
            phase: runtime.phase,
            modelIDs: runtime.modelIDs,
            defaultModelID: runtime.defaultModelID,
            process: process,
            supervisor: otherPID,
            listeners: runtime.listeners,
            exposure: runtime.exposure,
            localNetworkAddresses: [],
            evidence: runtime.evidence,
            diagnostic: runtime.diagnostic
        )
        XCTAssertNotNil(LocalModelSupervisorControlPolicy.disableRefusalReason(runtime: mismatched))
    }

    func testSupervisorIdentityRejectsReplacedPlist() {
        let original = makeSupervisor(processID: 222, fileID: 10)
        let replaced = makeSupervisor(processID: 222, fileID: 11)
        XCTAssertNotNil(
            LocalModelSupervisorControlPolicy.identityMismatchReason(
                expected: original,
                observed: replaced
            )
        )
    }

    func testSupervisorEnableRequiresDisabledAndFullyStoppedJob() {
        let stopped = makeSupervisor(processID: nil)
        XCTAssertTrue(stopped.canEnable)
        XCTAssertNil(LocalModelSupervisorControlPolicy.enableRefusalReason(supervisor: stopped))

        let staleActive = makeSupervisor(processID: 222, isDisabled: true)
        XCTAssertFalse(staleActive.canEnable)
        XCTAssertNotNil(LocalModelSupervisorControlPolicy.enableRefusalReason(supervisor: staleActive))

        let staleLoaded = makeSupervisor(processID: nil, isLoaded: true, isDisabled: true)
        XCTAssertFalse(staleLoaded.canEnable)
        XCTAssertNotNil(LocalModelSupervisorControlPolicy.enableRefusalReason(supervisor: staleLoaded))
    }

    private func makeSupervisor(
        processID: Int32?,
        fileID: UInt64 = 10,
        isLoaded: Bool? = nil,
        isDisabled: Bool? = nil
    ) -> LocalModelSupervisorSnapshot {
        LocalModelSupervisorSnapshot(
            label: "homebrew.mxcl.omlx",
            domain: "gui/501",
            kind: .userLaunchAgent,
            sourcePath: "/Users/test/Library/LaunchAgents/homebrew.mxcl.omlx.plist",
            sourceDeviceID: 1,
            sourceFileID: fileID,
            programName: "omlx",
            keepAlive: true,
            runAtLoad: true,
            isLoaded: isLoaded ?? (processID != nil),
            isDisabled: isDisabled ?? (processID == nil),
            processID: processID,
            isOwnedByCurrentUser: true,
            platform: .omlx
        )
    }
}
