import Foundation
import XCTest
@testable import CleanNestCore

final class CleanupSessionTests: XCTestCase {
    func testRootInspectorFailsClosedForLinksFilesAndMissingRoots() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("safe", isDirectory: true)
        let file = root.appendingPathComponent("file.bin")
        let link = root.appendingPathComponent("linked-root", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x01]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)

        XCTAssertEqual(CleanupScanRootInspector.status(of: directory), .checked)
        XCTAssertEqual(CleanupScanRootInspector.status(of: file), .unsafe)
        XCTAssertEqual(CleanupScanRootInspector.status(of: link), .unsafe)
        XCTAssertEqual(
            CleanupScanRootInspector.status(of: root.appendingPathComponent("missing")),
            .missing
        )

        let unreadable = root.appendingPathComponent("unreadable", isDirectory: true)
        try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        }
        XCTAssertEqual(CleanupScanRootInspector.status(of: unreadable), .unreadable)

        let evidence = CleanupScanRootEvidence(name: "Safe", url: directory, homeDirectory: root)
        XCTAssertEqual(evidence.pathHint, "~/safe")
        XCTAssertFalse(evidence.id.contains(root.path))

        let realParent = root.appendingPathComponent("real-parent", isDirectory: true)
        let realChild = realParent.appendingPathComponent("child", isDirectory: true)
        let linkedParent = root.appendingPathComponent("linked-parent", isDirectory: true)
        try FileManager.default.createDirectory(at: realChild, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: realParent)
        let linkedChildEvidence = CleanupScanRootEvidence(
            name: "Linked child",
            url: linkedParent.appendingPathComponent("child", isDirectory: true),
            homeDirectory: root
        )
        XCTAssertEqual(linkedChildEvidence.status, .unsafe)
    }

    func testBatchSelectionOnlyChangesTheNamedScope() {
        let scope: Set<String> = ["a", "b"]
        let current: Set<String> = ["outside", "a"]

        XCTAssertEqual(
            CleanupSelectionPolicy.applying(.invert, candidateIDs: scope, to: current),
            Set(["outside", "b"])
        )
        XCTAssertEqual(
            CleanupSelectionPolicy.applying(.selectAll, candidateIDs: scope, to: current),
            Set(["outside", "a", "b"])
        )
        XCTAssertEqual(
            CleanupSelectionPolicy.applying(.clear, candidateIDs: scope, to: current),
            Set(["outside"])
        )
    }

    func testBasketSeparatesSelectionRecoveryAndRevalidationEvidence() {
        let retainedIdentity = CleanupFileIdentity(
            deviceID: 1,
            fileID: 10,
            logicalBytes: 150,
            modifiedAt: nil
        )
        let candidates = [
            candidate(id: "cache", kind: .logs, bytes: 100),
            candidate(id: "photo", kind: .image, bytes: 200, identity: retainedIdentity),
            candidate(
                id: "duplicate",
                kind: .duplicate,
                bytes: 300,
                identity: CleanupFileIdentity(deviceID: 1, fileID: 11, logicalBytes: 300, modifiedAt: nil),
                duplicate: DuplicateFileEvidence(
                    groupID: "group",
                    contentSHA256: String(repeating: "a", count: 64),
                    retainedURL: URL(fileURLWithPath: "/tmp/retained"),
                    retainedIdentity: retainedIdentity,
                    groupFileCount: 2
                )
            )
        ]
        let summary = CleanupBasketSummary(
            candidates: candidates,
            selectedIDs: ["cache", "photo", "duplicate"],
            currentFreeBytes: 1_000
        )

        XCTAssertEqual(summary.selectedCount, 3)
        XCTAssertEqual(summary.selectedBytes, 600)
        XCTAssertEqual(summary.projectedFreeBytesAfterEmptyingTrash, 1_600)
        XCTAssertEqual(summary.personalFileCount, 2)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(summary.identityRevalidationCount, 2)
        XCTAssertEqual(summary.pathRevalidationCount, 1)

        let saturated = CleanupBasketSummary(
            candidates: [candidate(id: "large", kind: .logs, bytes: 10)],
            selectedIDs: ["large"],
            currentFreeBytes: Int64.max - 5
        )
        XCTAssertEqual(saturated.projectedFreeBytesAfterEmptyingTrash, Int64.max)
    }

    func testMediaClustersExposeAgeAndSizeWithoutChangingSelection() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let candidates = [
            candidate(id: "recent", kind: .image, bytes: 50 * 1_048_576, modifiedAt: now.addingTimeInterval(-10 * 86_400)),
            candidate(id: "aging", kind: .video, bytes: 500 * 1_048_576, modifiedAt: now.addingTimeInterval(-60 * 86_400)),
            candidate(id: "old", kind: .audio, bytes: 2 * 1_024 * 1_048_576, modifiedAt: now.addingTimeInterval(-120 * 86_400)),
            candidate(id: "unknown", kind: .image, bytes: 1, modifiedAt: nil)
        ]
        let summary = CleanupMediaClusterSummary(candidates: candidates, now: now)

        XCTAssertEqual(summary.timeCounts[.recent], 1)
        XCTAssertEqual(summary.timeCounts[.aging], 1)
        XCTAssertEqual(summary.timeCounts[.old], 1)
        XCTAssertEqual(summary.timeCounts[.unknown], 1)
        XCTAssertEqual(summary.sizeCounts[.under100MB], 2)
        XCTAssertEqual(summary.sizeCounts[.from100MBTo1GB], 1)
        XCTAssertEqual(summary.sizeCounts[.over1GB], 1)
    }

    func testSessionPreservesOriginalCategoriesAndSkipReasons() {
        let candidates = [
            candidate(id: "installer", kind: .installer, bytes: 400),
            candidate(id: "archive", kind: .archive, bytes: 600)
        ]
        let insights = CleanupScanInsights(
            examinedFileCount: 42,
            installerCount: 1,
            archiveCount: 1,
            skippedCloudItemCount: 2,
            skippedSymbolicLinkCount: 3,
            skippedPackageCount: 4,
            reachedHashLimit: true
        )
        let started = Date(timeIntervalSince1970: 100)
        let session = CleanupScanSession(
            requestID: "session",
            startedAt: started,
            completedAt: started.addingTimeInterval(2),
            elapsedSeconds: 2,
            roots: [
                CleanupScanRootEvidence(name: "Downloads", pathHint: "~/Downloads", status: .checked),
                CleanupScanRootEvidence(name: "Unsafe", pathHint: "~/Unsafe", status: .unsafe)
            ],
            insights: insights,
            candidates: candidates
        )

        XCTAssertEqual(session.checkedRootCount, 1)
        XCTAssertEqual(session.candidateCount, 2)
        XCTAssertEqual(session.categories.map(\.kind), [.installer, .archive])
        XCTAssertEqual(session.skips.first { $0.reason == .cloudPlaceholder }?.count, 2)
        XCTAssertEqual(session.skips.first { $0.reason == .symbolicLink }?.count, 3)
        XCTAssertEqual(session.skips.first { $0.reason == .packageBoundary }?.count, 4)
        XCTAssertEqual(session.skips.first { $0.reason == .hashLimit }?.count, 1)
    }

    func testLegacyInsightsDecodeWithNewSkipCountersAtZero() throws {
        let data = #"{"examinedFileCount":12,"installerCount":1,"archiveCount":0,"imageCount":0,"videoCount":0,"audioCount":0,"duplicateGroupCount":0,"duplicateFileCount":0,"duplicateBytes":0,"skippedCloudItemCount":2,"reachedFileLimit":false,"reachedHashLimit":false}"#
            .data(using: .utf8)!

        let insights = try JSONDecoder().decode(CleanupScanInsights.self, from: data)

        XCTAssertEqual(insights.examinedFileCount, 12)
        XCTAssertEqual(insights.skippedCloudItemCount, 2)
        XCTAssertEqual(insights.skippedSymbolicLinkCount, 0)
        XCTAssertEqual(insights.skippedPackageCount, 0)
        XCTAssertEqual(insights.skippedUnreadableItemCount, 0)
    }

    func testInsightsStillRejectMissingOriginalEvidenceFields() throws {
        let incomplete = #"{"examinedFileCount":12}"#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(CleanupScanInsights.self, from: incomplete))
    }

    func testStandardScannerRejectsSymlinkRuleRoot() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let outside = home.appendingPathComponent("OutsideLogs", isDirectory: true)
        let logs = library.appendingPathComponent("Logs", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data(repeating: 0x44, count: 4096).write(to: outside.appendingPathComponent("old.log"))
        try FileManager.default.createSymbolicLink(at: logs, withDestinationURL: outside)

        let result = await CleanupScanner(homeDirectory: home).scanWithEvidence()

        XCTAssertFalse(result.candidates.contains { $0.url.path.hasPrefix(outside.path) })
        XCTAssertEqual(result.roots.first { $0.name == "应用日志" }?.status, .unsafe)
        XCTAssertEqual(result.insights.skippedUnsafeRootCount, 1)
    }

    private func candidate(
        id: String,
        kind: CleanupKind,
        bytes: Int64,
        modifiedAt: Date? = nil,
        identity: CleanupFileIdentity? = nil,
        duplicate: DuplicateFileEvidence? = nil
    ) -> CleanupCandidate {
        CleanupCandidate(
            id: id,
            name: id,
            url: URL(fileURLWithPath: "/tmp/\(id)"),
            kind: kind,
            allocatedBytes: bytes,
            modifiedAt: modifiedAt,
            isRecommended: false,
            detail: "test",
            fileIdentity: identity,
            duplicateEvidence: duplicate
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestCleanupSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
