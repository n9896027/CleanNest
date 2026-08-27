import Darwin
import Foundation
import XCTest
@testable import CleanNestCore

final class LocalModelRuntimeIntegrationTests: XCTestCase {
    func testOptInInstalledOllamaEmptyServiceLifecycle() async throws {
        guard ProcessInfo.processInfo.environment["CLEANNEST_RUN_OLLAMA_INTEGRATION"] == "1" else {
            throw XCTSkip("Set CLEANNEST_RUN_OLLAMA_INTEGRATION=1 for the bounded local service check.")
        }
        let executable = URL(fileURLWithPath: "/opt/homebrew/bin/ollama")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw XCTSkip("Ollama is not installed at the expected Homebrew path.")
        }

        let initial = await LocalModelRuntimeDiscovery().discover()
        guard !initial.instances.contains(where: {
            $0.listeners.contains { $0.port == 11_434 }
        }) else {
            throw XCTSkip("Port 11434 is already in use; the test will not disturb an existing service.")
        }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNest-Ollama-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "OLLAMA_HOST": "127.0.0.1:11434",
            "OLLAMA_MODELS": temporaryRoot.appendingPathComponent("models").path,
            "OLLAMA_NOHISTORY": "1"
        ]) { _, testValue in testValue }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let expectedPID = process.processIdentifier
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        var discovered: LocalModelRuntimeInstance?
        for _ in 0..<20 {
            let snapshot = await LocalModelRuntimeDiscovery().discover()
            discovered = snapshot.instances.first(where: {
                $0.platform == .ollama && $0.process?.pid == expectedPID
            })
            if discovered != nil { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let runtime = try XCTUnwrap(discovered)
        XCTAssertEqual(runtime.phase, .runningUnverified)
        XCTAssertTrue(runtime.evidence.contains(.platformAPI))
        XCTAssertTrue(runtime.issues.contains(where: { $0.kind == .noLoadedModel }))
        XCTAssertEqual(runtime.process?.ownerUserID, UInt32(getuid()))
        XCTAssertEqual(runtime.controlLevel, .currentUserProcess)

        process.terminate()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationReason, .exit)

        var stillPresent = true
        for _ in 0..<20 {
            let snapshot = await LocalModelRuntimeDiscovery().discover()
            stillPresent = snapshot.instances.contains(where: {
                $0.process?.pid == expectedPID
                    || $0.listeners.contains { $0.port == 11_434 }
            })
            if !stillPresent { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertFalse(stillPresent)
    }
}
