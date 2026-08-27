import Foundation
import XCTest
@testable import CleanNestCore

final class ScannerWorkerTests: XCTestCase {
    func testCleanupWorkerReturnsTransportableResult() async throws {
        let home = try temporaryDirectory(named: "CleanNestScannerCleanup")
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let installer = downloads.appendingPathComponent("Example.dmg")
        try Data(repeating: 0x61, count: 4_096).write(to: installer)

        let request = CleanupScannerRequest(
            requestID: "cleanup-test",
            homeDirectory: home,
            includeApplicationCaches: false,
            includeMediaAndDuplicates: false,
            developerMode: false
        )
        let recorder = ScannerProgressRecorder()
        let response = try await ScannerWorker().scanCleanup(request) {
            recorder.append($0)
        }

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.candidates.count, 1)
        XCTAssertEqual(response.candidates.first?.url, installer)
        XCTAssertEqual(response.candidates.first?.kind, .installer)
        XCTAssertEqual(response.insights.installerCount, 1)
        XCTAssertEqual(response.session.requestID, request.requestID)
        XCTAssertEqual(response.session.candidateCount, 1)
        XCTAssertEqual(response.session.examinedFileCount, 1)
        XCTAssertEqual(response.session.roots.map(\.name).suffix(2), ["桌面", "下载"])
        XCTAssertTrue(response.session.roots.contains { $0.name == "下载" && $0.status == .checked })
        XCTAssertTrue(recorder.values.contains { $0.stage == .cleanupCaches })
        XCTAssertTrue(recorder.values.contains { $0.stage == .cleanupPersonalFiles })
        XCTAssertEqual(recorder.values.last?.stage, .completed)

        let encoded = try ScannerServiceCodec.encode(response)
        let decoded = try ScannerServiceCodec.decode(CleanupScannerResponse.self, from: encoded)
        XCTAssertEqual(decoded, response)
    }

    func testDiskWorkerBuildsReportEvidenceAndCacheAcrossTransportBoundary() async throws {
        let home = try temporaryDirectory(named: "CleanNestScannerDisk")
        defer { try? FileManager.default.removeItem(at: home) }
        let root = home.appendingPathComponent("Library", isDirectory: true)
        let cacheDirectory = root.appendingPathComponent("Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x31, count: 16_384)
            .write(to: cacheDirectory.appendingPathComponent("payload.bin"))

        let request = DiskScannerRequest(
            requestID: "disk-test",
            root: root,
            homeDirectory: home,
            cache: DiskScanCacheStore(),
            mode: .bypassCache,
            previousEvidence: nil
        )
        let recorder = ScannerProgressRecorder()
        let response = try await ScannerWorker().scanDisk(request) {
            recorder.append($0)
        }

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.outcome.report.root, root)
        XCTAssertEqual(response.outcome.report.entries.map(\.name), ["Caches"])
        XCTAssertEqual(response.outcome.scannedCount, 1)
        XCTAssertNotNil(response.outcome.updatedCache.root(for: root))
        XCTAssertEqual(response.evidence.entries.count, 1)
        XCTAssertTrue(recorder.values.contains { $0.stage == .diskContents })
        XCTAssertTrue(recorder.values.contains { $0.stage == .diskEvidence })
        XCTAssertEqual(recorder.values.last?.stage, .completed)

        let encoded = try ScannerServiceCodec.encode(response)
        let decoded = try ScannerServiceCodec.decode(DiskScannerResponse.self, from: encoded)
        XCTAssertEqual(decoded, response)
    }

    func testCancelledCleanupWorkerDoesNotPublishCompletedResponse() async throws {
        let home = try temporaryDirectory(named: "CleanNestScannerCancellation")
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        for index in 0..<2_000 {
            try Data(repeating: UInt8(index % 251), count: 64)
                .write(to: downloads.appendingPathComponent("file-\(index).dmg"))
        }
        let request = CleanupScannerRequest(
            homeDirectory: home,
            includeApplicationCaches: false,
            includeMediaAndDuplicates: true,
            developerMode: true
        )
        let task = Task {
            try await ScannerWorker().scanCleanup(request)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("A cancelled worker must not publish a completed response")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testCancellationStormLeavesEveryWorkerCancelledWithoutCompletedProgress() async throws {
        let home = try temporaryDirectory(named: "CleanNestScannerCancellationStorm")
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        for index in 0..<500 {
            try Data(repeating: UInt8(index % 251), count: 64)
                .write(to: downloads.appendingPathComponent("file-\(index).dmg"))
        }

        let worker = ScannerWorker()
        var cancelledCount = 0
        for index in 0..<24 {
            let recorder = ScannerProgressRecorder()
            let request = CleanupScannerRequest(
                requestID: "cancellation-storm-\(index)",
                homeDirectory: home,
                includeApplicationCaches: false,
                includeMediaAndDuplicates: true,
                developerMode: true
            )
            let task = Task {
                try await worker.scanCleanup(request) { recorder.append($0) }
            }
            task.cancel()
            do {
                _ = try await task.value
                XCTFail("Cancellation storm iteration \(index) published a response")
            } catch is CancellationError {
                cancelledCount += 1
            }
            XCTAssertFalse(recorder.values.contains { $0.stage == .completed })
        }
        XCTAssertEqual(cancelledCount, 24)
    }

    func testAgentWorkspaceWorkerReturnsTransportableReadOnlyResult() async throws {
        let home = try temporaryDirectory(named: "CleanNestScannerAgentWorkspace")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try Data(repeating: 0x7b, count: 8_192)
            .write(to: sessions.appendingPathComponent("session.jsonl"))

        let request = AgentWorkspaceScannerRequest(
            requestID: "agent-workspace-test",
            homeDirectory: home,
            previousObservation: nil
        )
        let recorder = ScannerProgressRecorder()
        let response = try await ScannerWorker().scanAgentWorkspace(request) {
            recorder.append($0)
        }

        XCTAssertEqual(response.requestID, request.requestID)
        XCTAssertEqual(response.result.snapshot.detectedAgents.map(\.provider), [.codex])
        XCTAssertEqual(response.result.snapshot.detectedAgents.first?.fileCount, 1)
        XCTAssertTrue(response.result.snapshot.actionCandidates.isEmpty)
        XCTAssertGreaterThanOrEqual(response.elapsedSeconds, 0)
        XCTAssertTrue(recorder.values.contains { $0.stage == .agentWorkspaceMetadata })
        XCTAssertEqual(recorder.values.last?.stage, .completed)

        let encoded = try ScannerServiceCodec.encode(response)
        let decoded = try ScannerServiceCodec.decode(AgentWorkspaceScannerResponse.self, from: encoded)
        XCTAssertEqual(decoded, response)
    }

    private func temporaryDirectory(named prefix: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ScannerProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScannerServiceProgress] = []

    var values: [ScannerServiceProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: ScannerServiceProgress) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
