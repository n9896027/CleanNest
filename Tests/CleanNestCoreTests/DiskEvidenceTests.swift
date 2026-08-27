import Foundation
import XCTest
import CleanNestCore

final class DiskEvidenceTests: XCTestCase {
    func testIndexerExplainsCacheProvenanceWithoutExposingHome() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let cache = home.appendingPathComponent("Library/Caches/npm/_cacache/content-v2", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let archive = cache.appendingPathComponent("package.tgz")
        let log = cache.appendingPathComponent("download.log")
        try Data(repeating: 1, count: 2_048).write(to: archive)
        try Data(repeating: 2, count: 1_024).write(to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-100 * 86_400)],
            ofItemAtPath: archive.path
        )

        let entry = DiskEntry(name: "content-v2", url: cache, bytes: 3_072, isDirectory: true)
        let report = DiskReport(root: home, entries: [entry], largeFiles: [], totalBytes: 3_072, totalFiles: 2)
        let evidence = try await DiskEvidenceIndexer().build(report: report, homeDirectory: home)
        let item = try XCTUnwrap(evidence.entries.first)

        XCTAssertEqual(item.category, .cache)
        XCTAssertEqual(item.cleanupBoundary, .reviewable)
        XCTAssertEqual(item.minimumRisk, .low)
        XCTAssertTrue(item.provenance.contains("运行") || item.provenance.contains("下载"))
        XCTAssertTrue(item.regeneration.contains("重新"))
        XCTAssertEqual(item.observedFileCount, 2)
        XCTAssertFalse(item.relativeHint.contains(home.path))
        XCTAssertTrue(item.typeDistribution.contains { $0.kind == .archive })
        XCTAssertTrue(item.typeDistribution.contains { $0.kind == .log })
        XCTAssertGreaterThan(item.ageDistribution.olderBytes, 0)
        XCTAssertEqual(item.cleanupDecision.disposition, .reviewCandidate)
        XCTAssertTrue(item.cleanupDecision.whyLarge.contains("下载"))
        XCTAssertTrue(item.cleanupDecision.impact.contains("重新"))
        XCTAssertFalse(item.cleanupDecision.evidence.isEmpty)

        let snapshotURL = home.appendingPathComponent("evidence.json")
        try DiskEvidencePersistence.save(evidence, to: snapshotURL)
        XCTAssertEqual(try DiskEvidencePersistence.load(from: snapshotURL), evidence)
    }

    func testGrowthAndScanLimitAreExplicit() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("Caches/example", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<120 {
            try Data([UInt8(index % 255)]).write(to: directory.appendingPathComponent("\(index).bin"))
        }
        let entry = DiskEntry(name: "example", url: directory, bytes: 120, isDirectory: true)
        let report = DiskReport(root: root, entries: [entry], largeFiles: [], totalBytes: 120, totalFiles: 120)
        let initial = try await DiskEvidenceIndexer(options: .init(maximumFilesPerEntry: 100))
            .build(report: report, homeDirectory: root)
        let changedEntry = DiskEntry(name: "example", url: directory, bytes: 180, isDirectory: true)
        let changed = try await DiskEvidenceIndexer(options: .init(maximumFilesPerEntry: 100))
            .build(
                report: DiskReport(root: root, entries: [changedEntry], largeFiles: [], totalBytes: 180, totalFiles: 120),
                previous: initial,
                homeDirectory: root
            )
        XCTAssertEqual(changed.entries.first?.growthBytes, 60)
        XCTAssertEqual(changed.entries.first?.scanWasLimited, true)
    }

    func testGeneratedProjectDirectoryRequiresManifestEvidence() async throws {
        let home = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: home) }
        let project = home.appendingPathComponent("Documents/Example", isDirectory: true)
        let generated = project.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: generated, withIntermediateDirectories: true)
        try "// package".write(to: project.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: generated.appendingPathComponent("artifact.o"))

        let report = DiskReport(
            root: project,
            entries: [DiskEntry(name: ".build", url: generated, bytes: 1, isDirectory: true)],
            largeFiles: [],
            totalBytes: 1,
            totalFiles: 1
        )
        let evidence = try await DiskEvidenceIndexer().build(report: report, homeDirectory: home)
        XCTAssertEqual(evidence.entries.first?.category, .developerArtifacts)
        XCTAssertEqual(evidence.entries.first?.cleanupBoundary, .reviewable)
        XCTAssertEqual(evidence.entries.first?.minimumRisk, .low)

        try FileManager.default.removeItem(at: project.appendingPathComponent("Package.swift"))
        let withoutManifest = DiskAISafetyPolicy.policy(for: generated, homeDirectory: home)
        XCTAssertEqual(withoutManifest.category, .userContent)
        XCTAssertEqual(withoutManifest.boundary, .protected)
    }

    func testDecisionCenterKeepsProtectedUnknownContent() {
        let entry = DiskEvidenceEntry(
            id: "unknown",
            name: "Private",
            relativeHint: "~/Private",
            allocatedBytes: 1_024,
            isDirectory: true,
            observedFileCount: 0,
            observedBytes: 0,
            scanWasLimited: false,
            latestModificationDate: nil,
            ageDistribution: DiskEvidenceAgeDistribution(),
            typeDistribution: [],
            category: .unknown,
            cleanupBoundary: .protected,
            minimumRisk: .high,
            purpose: "当前规则无法可靠确认用途。",
            likelyOwner: nil,
            provenance: "缺少稳定证据。",
            regeneration: "未知内容不可自动重建。",
            growthBytes: nil
        )

        let decision = entry.cleanupDecision
        XCTAssertEqual(decision.disposition, .keep)
        XCTAssertEqual(decision.confidence, .low)
        XCTAssertTrue(decision.nextStep.contains("保持"))
    }

    func testManualDiskDecisionPersistsAndCanReturnToSystemAdvice() throws {
        let entry = makeEvidenceEntry(
            id: "fingerprint-cache",
            category: .cache,
            boundary: .reviewable,
            risk: .low
        )
        var store = DiskManualDecisionStore()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try store.set(.reviewForCleanup, for: entry, now: updatedAt)
        XCTAssertEqual(store.decision(for: entry), .reviewForCleanup)

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("manual-decisions.json")
        try DiskManualDecisionPersistence.save(store, to: url)
        let restored = try DiskManualDecisionPersistence.load(from: url)
        XCTAssertEqual(restored, store)
        XCTAssertEqual(restored.decision(for: entry), .reviewForCleanup)

        let encoded = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(encoded.contains("/Users/"))
        XCTAssertFalse(encoded.contains(entry.relativeHint))

        var reset = restored
        try reset.set(nil, for: entry)
        XCTAssertNil(reset.decision(for: entry))
        XCTAssertTrue(reset.records.isEmpty)
    }

    func testManualDiskDecisionCannotBypassProtectedBoundary() throws {
        let protected = makeEvidenceEntry(
            id: "fingerprint-protected",
            category: .userContent,
            boundary: .protected,
            risk: .high
        )
        var store = DiskManualDecisionStore()

        XCTAssertThrowsError(try store.set(.reviewForCleanup, for: protected)) { error in
            XCTAssertEqual(error as? DiskManualDecisionError, .cleanupReviewNotAllowed)
        }
        XCTAssertNil(store.decision(for: protected))

        try store.set(.keep, for: protected)
        XCTAssertEqual(store.decision(for: protected), .keep)
        try store.set(.decideLater, for: protected)
        XCTAssertEqual(store.decision(for: protected), .decideLater)
    }

    func testOldCleanupReviewRecordIsIgnoredWhenEvidenceBecomesProtected() {
        let protected = makeEvidenceEntry(
            id: "fingerprint-changed",
            category: .systemData,
            boundary: .protected,
            risk: .high
        )
        let record = DiskManualDecisionRecord(
            id: protected.id,
            decision: .reviewForCleanup,
            updatedAt: Date()
        )
        let store = DiskManualDecisionStore(records: [protected.id: record])

        XCTAssertNil(store.decision(for: protected))
    }

    func testHistoryKeepsTwoSnapshotsPerRootAndSkipsPartialGrowthBaseline() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("root", isDirectory: true)
        let other = directory.appendingPathComponent("other", isDirectory: true)
        var store = DiskEvidenceHistoryStore()
        let complete = DiskScanCoverage(
            rootEnumerationErrorCount: 0,
            topLevelEntryCount: 1,
            hiddenTopLevelEntryCount: 0,
            visitedEntryCount: 10,
            regularFileCount: 9,
            unreadableEntryCount: 0,
            crossVolumeEntryCount: 0,
            symbolicLinkCount: 0,
            limitedSubtreeCount: 0,
            unknownCachedSubtreeCount: 0,
            unboundedTraversal: false
        )
        let partial = DiskScanCoverage(
            rootEnumerationErrorCount: 0,
            topLevelEntryCount: 1,
            hiddenTopLevelEntryCount: 0,
            visitedEntryCount: 5,
            regularFileCount: 4,
            unreadableEntryCount: 0,
            crossVolumeEntryCount: 0,
            symbolicLinkCount: 0,
            limitedSubtreeCount: 1,
            unknownCachedSubtreeCount: 0,
            unboundedTraversal: false
        )
        for index in 0..<3 {
            let evidence = DiskEvidenceReport(
                generatedAt: Date(timeIntervalSince1970: TimeInterval(index + 1)),
                rootHint: "root",
                entries: []
            )
            store.append(
                DiskEvidenceHistorySnapshot(
                    evidence: evidence,
                    coverage: index == 2 ? partial : complete,
                    classifiedBytes: Int64(index + 1) * 100
                ),
                for: root
            )
        }
        store.append(
            DiskEvidenceHistorySnapshot(
                evidence: DiskEvidenceReport(rootHint: "other", entries: []),
                coverage: complete,
                classifiedBytes: 50
            ),
            for: other
        )

        XCTAssertEqual(store.snapshots(for: root).count, 2)
        XCTAssertEqual(store.latestReliable(for: root)?.classifiedBytes, 200)
        XCTAssertEqual(store.snapshots(for: other).count, 1)

        let url = directory.appendingPathComponent("history.json")
        try DiskEvidenceHistoryPersistence.save(store, to: url)
        let restored = try DiskEvidenceHistoryPersistence.load(from: url)
        XCTAssertEqual(restored, store)
        XCTAssertFalse(try String(contentsOf: url).contains(directory.path))
    }

    private func makeEvidenceEntry(
        id: String,
        category: DiskAIContentCategory,
        boundary: DiskAICleanupBoundary,
        risk: DiskAIRisk
    ) -> DiskEvidenceEntry {
        DiskEvidenceEntry(
            id: id,
            name: "Example",
            relativeHint: "~/Library/Caches/Example",
            allocatedBytes: 1_024,
            isDirectory: true,
            observedFileCount: 1,
            observedBytes: 1_024,
            scanWasLimited: false,
            latestModificationDate: nil,
            ageDistribution: DiskEvidenceAgeDistribution(),
            typeDistribution: [],
            category: category,
            cleanupBoundary: boundary,
            minimumRisk: risk,
            purpose: "测试用途",
            likelyOwner: "Example",
            provenance: "测试来源",
            regeneration: "可以重新生成。",
            growthBytes: nil
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestEvidenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
