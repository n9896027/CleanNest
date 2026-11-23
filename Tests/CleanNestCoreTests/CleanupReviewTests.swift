import Foundation
import XCTest
@testable import CleanNestCore

final class CleanupReviewTests: XCTestCase {
    func testTransientFailuresAllowOnlyOrdinaryRetry() {
        for kind in [TrashFailureKind.activeFile, .activityProbeUnavailable, .permissionDenied, .operationFailed] {
            let item = makeItem(kind: kind)
            XCTAssertEqual(item.action, .retry, kind.rawValue)
            XCTAssertFalse(item.guidance.isEmpty)
        }
    }

    func testChangedOrInvalidEvidenceRequiresFreshScan() {
        for kind in [TrashFailureKind.targetChanged, .validation, .missingResult] {
            let item = makeItem(kind: kind)
            XCTAssertEqual(item.action, .rescan, kind.rawValue)
            XCTAssertTrue(item.guidance.contains("重新扫描"))
        }
    }

    func testMixedBatchKeepsOnlyFailedPathForReview() {
        let failed = makeCandidate(name: "failed")
        let succeeded = makeCandidate(name: "succeeded")
        let outcomes = [
            makeOutcome(for: failed, kind: .activeFile),
            TrashOutcome(source: succeeded.url, trashedURL: succeeded.url, errorDescription: nil)
        ]

        let review = CleanupReviewItem.reconciling(
            current: [],
            candidates: [failed, succeeded],
            outcomes: outcomes
        )

        XCTAssertEqual(review.map(\.id), [failed.id])
        XCTAssertEqual(review.first?.failureKind, .activeFile)
    }

    func testSuccessfulSingleRetryClearsOnlyItsOwnRecord() {
        let first = makeCandidate(name: "first")
        let second = makeCandidate(name: "second")
        let current = [
            makeItem(candidate: first, kind: .activeFile),
            makeItem(candidate: second, kind: .permissionDenied)
        ]

        let review = CleanupReviewItem.reconciling(
            current: current,
            candidates: [second],
            outcomes: [TrashOutcome(source: first.url, trashedURL: first.url, errorDescription: nil)]
        )

        XCTAssertEqual(review.map(\.id), [second.id])
        XCTAssertEqual(review.first?.failureKind, .permissionDenied)
    }

    func testFailureFromUnknownPathCannotCreateReviewItem() {
        let known = makeCandidate(name: "known")
        let unknown = makeCandidate(name: "unknown")

        let review = CleanupReviewItem.reconciling(
            current: [],
            candidates: [known],
            outcomes: [makeOutcome(for: unknown, kind: .operationFailed)]
        )

        XCTAssertTrue(review.isEmpty)
    }

    func testFailedSingleRetryReplacesReasonWithoutDuplicatingPath() {
        let candidate = makeCandidate(name: "cache")
        let current = [makeItem(candidate: candidate, kind: .activeFile)]

        let review = CleanupReviewItem.reconciling(
            current: current,
            candidates: [candidate],
            outcomes: [makeOutcome(for: candidate, kind: .targetChanged)]
        )

        XCTAssertEqual(review.count, 1)
        XCTAssertEqual(review.first?.failureKind, .targetChanged)
        XCTAssertEqual(review.first?.action, .rescan)
    }

    func testRetainedCopyChangeKeepsSpecificReasonAndRequiresRescan() {
        let candidate = makeCandidate(name: "duplicate")
        let outcome = TrashOutcome(
            source: candidate.url,
            trashedURL: nil,
            errorDescription: CleanupEvidenceError.retainedCopyChanged.localizedDescription,
            failureKind: .targetChanged,
            technicalDescription: "retained identity mismatch"
        )

        let item = CleanupReviewItem(candidate: candidate, outcome: outcome)

        XCTAssertEqual(item?.failureKind, .targetChanged)
        XCTAssertEqual(item?.action, .rescan)
        XCTAssertTrue(item?.detail.contains("保留的重复副本") == true)
        XCTAssertTrue(item?.guidance.contains("重新扫描") == true)
    }

    func testOutcomeOutsideCandidateScopeCannotBecomeExecutableReviewItem() {
        let candidate = CleanupCandidate(
            name: "inside",
            url: URL(fileURLWithPath: "/tmp/CleanNestReviewTests/root/inside"),
            kind: .appCache,
            allocatedBytes: 4,
            modifiedAt: nil,
            isRecommended: true,
            detail: "fixture"
        )
        let outside = URL(fileURLWithPath: "/etc/passwd")
        let outcome = TrashOutcome(
            source: outside,
            trashedURL: nil,
            errorDescription: "outside fixture",
            failureKind: .operationFailed
        )

        let review = CleanupReviewItem.reconciling(
            current: [],
            candidates: [candidate],
            outcomes: [outcome]
        )

        XCTAssertTrue(review.isEmpty)
    }

    private func makeItem(
        candidate: CleanupCandidate? = nil,
        kind: TrashFailureKind
    ) -> CleanupReviewItem {
        let candidate = candidate ?? makeCandidate()
        return CleanupReviewItem(
            candidate: candidate,
            outcome: makeOutcome(for: candidate, kind: kind)
        )!
    }

    private func makeCandidate(name: String = "cache") -> CleanupCandidate {
        CleanupCandidate(
            name: name,
            url: URL(fileURLWithPath: "/tmp/CleanNestReviewTests/\(name)"),
            kind: .appCache,
            allocatedBytes: 4,
            modifiedAt: nil,
            isRecommended: true,
            detail: "测试"
        )
    }

    private func makeOutcome(
        for candidate: CleanupCandidate,
        kind: TrashFailureKind
    ) -> TrashOutcome {
        TrashOutcome(
            source: candidate.url,
            trashedURL: nil,
            errorDescription: "测试失败",
            failureKind: kind,
            technicalDescription: "fixture"
        )
    }
}
