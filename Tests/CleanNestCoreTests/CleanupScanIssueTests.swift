import Foundation
import XCTest
@testable import CleanNestCore

final class CleanupScanIssueTests: XCTestCase {
    func testPersonalScannerRecordsExactProtectionPathsWithoutCandidates() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let outside = home.appendingPathComponent("outside.dmg")
        let link = downloads.appendingPathComponent("linked.dmg")
        let package = downloads.appendingPathComponent("Example.app", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data(repeating: 0x01, count: 4096).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)

        let result = await DownloadMediaScanner(homeDirectory: home).scan(
            includeMediaAndDuplicates: false,
            now: Date().addingTimeInterval(90 * 86_400)
        )

        XCTAssertEqual(result.issues.first { $0.reason == .symbolicLink }?.url, link)
        XCTAssertEqual(result.issues.first { $0.reason == .packageBoundary }?.url, package)
        XCTAssertFalse(result.candidates.contains { $0.url == link || $0.url == outside })
        XCTAssertFalse(result.issues.contains { $0.reason == .fileLimit })
    }

    func testPersonalScannerBoundsPathEvidenceAtTwoHundred() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        let outside = home.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try Data([0x01]).write(to: outside)
        for index in 0..<205 {
            try FileManager.default.createSymbolicLink(
                at: downloads.appendingPathComponent("link-\(index)"),
                withDestinationURL: outside
            )
        }

        let result = await DownloadMediaScanner(homeDirectory: home).scan(
            includeMediaAndDuplicates: false
        )

        XCTAssertEqual(result.issues.count, CleanupScanIssue.maximumPerScanner)
        XCTAssertEqual(result.insights.skippedSymbolicLinkCount, 205)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testRuleScannerRecordsUnsafeRootAndDepthEvidence() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let logs = home.appendingPathComponent("Library/Logs", isDirectory: true)
        let outside = home.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: logs, withDestinationURL: outside)

        let result = await CleanupScanner(homeDirectory: home).scanWithEvidence()
        let issue = try XCTUnwrap(result.issues.first { $0.reason == .unsafeRoot })
        XCTAssertEqual(issue.url, logs)
        XCTAssertFalse(result.candidates.contains { $0.url.path.hasPrefix(outside.path) })
    }

    func testLegacySessionWithoutIssuesDecodesAsEmpty() throws {
        let now = Date(timeIntervalSince1970: 100)
        let session = CleanupScanSession(
            requestID: "legacy",
            startedAt: now,
            completedAt: now,
            elapsedSeconds: 0,
            roots: [],
            insights: .empty,
            candidates: []
        )
        let encoded = try JSONEncoder().encode(session)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "issues")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CleanupScanSession.self, from: legacy)
        XCTAssertTrue(decoded.issues.isEmpty)
        XCTAssertEqual(decoded.requestID, "legacy")
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestScanIssueTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
