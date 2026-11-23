import Foundation
import XCTest
@testable import CleanNestCore

final class CleanupPresentationTests: XCTestCase {
    func testLogDisplayNameDoesNotChangePersistedRawValue() throws {
        XCTAssertEqual(CleanupKind.logs.displayName, "应用日志")
        XCTAssertEqual(CleanupKind.logs.rawValue, "旧日志")

        let legacy = try XCTUnwrap("\"旧日志\"".data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode(CleanupKind.self, from: legacy), .logs)
    }

    func testIssueGroupsPreserveEveryPathAndPrioritizeActionableItems() {
        let issues = [
            CleanupScanIssue(url: URL(fileURLWithPath: "/tmp/link"), reason: .symbolicLink),
            CleanupScanIssue(url: URL(fileURLWithPath: "/tmp/deep"), reason: .depthLimit),
            CleanupScanIssue(url: URL(fileURLWithPath: "/tmp/private"), reason: .unreadable),
            CleanupScanIssue(url: URL(fileURLWithPath: "/tmp/app.bundle"), reason: .packageBoundary)
        ]

        let groups = CleanupScanIssuePresentation.groups(for: issues)

        XCTAssertEqual(groups.map(\.reason), [.unreadable, .depthLimit, .symbolicLink, .packageBoundary])
        XCTAssertEqual(groups.flatMap(\.issues).count, issues.count)
        XCTAssertEqual(Set(groups.flatMap { $0.issues.map(\.id) }), Set(issues.map(\.id)))
        XCTAssertEqual(groups[0].disposition, .needsAttention)
        XCTAssertEqual(groups[2].disposition, .safetyBoundary)
        XCTAssertEqual(groups[3].disposition, .safetyBoundary)
    }

    func testOnlyUnreadableGroupOffersAuthorizationAndRescan() {
        for reason in CleanupScanSkipReason.allCases {
            let group = CleanupScanIssueGroup(
                reason: reason,
                issues: [CleanupScanIssue(url: URL(fileURLWithPath: "/tmp/\(reason.rawValue)"), reason: reason)]
            )
            XCTAssertEqual(
                group.allowsAuthorizationAndRescan,
                reason == .unreadable,
                "Unexpected rescan action for \(reason.rawValue)"
            )
        }
    }

    func testLargeDiagnosticCollectionLosesNoEvidence() {
        let issues = (0..<203).map { index in
            CleanupScanIssue(
                url: URL(fileURLWithPath: "/tmp/link-\(index)"),
                reason: .symbolicLink
            )
        }

        let groups = CleanupScanIssuePresentation.groups(for: issues)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.issues.count, 203)
        XCTAssertFalse(groups[0].allowsAuthorizationAndRescan)
        XCTAssertTrue(groups[0].summary.contains("重新扫描也不会改变"))
    }

    func testLogPresentationExplainsEvidenceImpactAndRecoveryWithoutGuesses() {
        let log = candidate(kind: .logs)
        let presentation = log.logPresentation

        XCTAssertEqual(presentation?.rowSummary, "应用或服务日志 · 用于运行记录与故障排查")
        XCTAssertEqual(presentation?.what.contains("没有读取日志内容"), true)
        XCTAssertEqual(presentation?.what.contains("不等于已核验的应用归属"), true)
        XCTAssertEqual(presentation?.impact.contains("不会卸载应用"), true)
        XCTAssertEqual(presentation?.impact.contains("是否生成新日志取决于"), true)
        XCTAssertEqual(presentation?.recovery.contains("清空后 CleanNest 无法恢复"), true)
        XCTAssertEqual(presentation?.impact.contains("一定会重新生成"), false)
    }

    func testLogPresentationIsOnlyAttachedToLogCandidates() {
        XCTAssertNil(candidate(kind: .developer).logPresentation)
        XCTAssertNotNil(candidate(kind: .logs).logPresentation)
    }

    private func candidate(kind: CleanupKind) -> CleanupCandidate {
        CleanupCandidate(
            name: "Example",
            url: URL(fileURLWithPath: "/tmp/Example"),
            kind: kind,
            allocatedBytes: 1024,
            modifiedAt: Date(timeIntervalSince1970: 0),
            isRecommended: false,
            detail: "旧日志，仅在不再排查问题时选择"
        )
    }
}
