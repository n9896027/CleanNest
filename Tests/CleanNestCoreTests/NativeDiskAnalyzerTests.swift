import Foundation
import XCTest
import CleanNestCore

final class NativeDiskAnalyzerTests: XCTestCase {
    func testIncrementalResultsReuseFreshCacheAndDetectChangedFile() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestIncrementalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let firstFile = root.appendingPathComponent("first.bin")
        let secondFile = root.appendingPathComponent("second.bin")
        try Data(repeating: 1, count: 8_192).write(to: firstFile)
        try Data(repeating: 2, count: 4_096).write(to: secondFile)

        let recorder = DiskProgressRecorder()
        let analyzer = NativeDiskAnalyzer(cacheMaximumAge: 600)
        let initial = try await analyzer.analyze(
            root: root,
            cache: DiskScanCacheStore(),
            progress: { recorder.append($0) }
        )
        XCTAssertEqual(initial.cacheHitCount, 0)
        XCTAssertEqual(initial.scannedCount, 2)
        XCTAssertEqual(initial.report.entries.count, 2)
        XCTAssertTrue(recorder.values.contains { $0.partialReport?.entries.isEmpty == false })

        let repeated = try await analyzer.analyze(root: root, cache: initial.updatedCache)
        XCTAssertEqual(repeated.cacheHitCount, 2)
        XCTAssertEqual(repeated.scannedCount, 0)
        XCTAssertEqual(repeated.report, initial.report)

        try Data(repeating: 3, count: 16_384).write(to: firstFile)
        let changed = try await analyzer.analyze(root: root, cache: repeated.updatedCache)
        XCTAssertEqual(changed.cacheHitCount, 1)
        XCTAssertEqual(changed.scannedCount, 1)
        XCTAssertGreaterThan(
            changed.report.entries.first(where: { $0.name == "first.bin" })?.bytes ?? 0,
            initial.report.entries.first(where: { $0.name == "first.bin" })?.bytes ?? 0
        )
    }

    func testDeepRefreshBypassesCacheAndCachePersistenceOmitsAbsoluteRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestCachePersistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 4, count: 2_048).write(to: root.appendingPathComponent("sample.bin"))

        let analyzer = NativeDiskAnalyzer(cacheMaximumAge: 600)
        let initial = try await analyzer.analyze(root: root, cache: DiskScanCacheStore())
        let refreshed = try await analyzer.analyze(
            root: root,
            cache: initial.updatedCache,
            mode: .bypassCache
        )
        XCTAssertEqual(refreshed.cacheHitCount, 0)
        XCTAssertEqual(refreshed.scannedCount, 1)

        let cacheURL = root.appendingPathComponent("cache.json")
        try DiskScanCachePersistence.save(refreshed.updatedCache, to: cacheURL)
        let loaded = try DiskScanCachePersistence.load(from: cacheURL)
        XCTAssertEqual(loaded.schemaVersion, refreshed.updatedCache.schemaVersion)
        XCTAssertEqual(Set(loaded.roots.keys), Set(refreshed.updatedCache.roots.keys))
        let originalRoot = try XCTUnwrap(refreshed.updatedCache.root(for: root))
        let loadedRoot = try XCTUnwrap(loaded.root(for: root))
        XCTAssertEqual(loadedRoot.id, originalRoot.id)
        XCTAssertEqual(loadedRoot.entries.map(\.id), originalRoot.entries.map(\.id))
        XCTAssertEqual(loadedRoot.entries.map(\.metadataSignature), originalRoot.entries.map(\.metadataSignature))
        XCTAssertEqual(loadedRoot.entries.map(\.allocatedBytes), originalRoot.entries.map(\.allocatedBytes))
        XCTAssertLessThan(abs(loadedRoot.generatedAt.timeIntervalSince(originalRoot.generatedAt)), 0.002)
        let raw = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertFalse(raw.contains(root.path))
    }

    func testCancellationPropagatesIntoDetachedScanner() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestCancellationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<80 {
            let directory = root.appendingPathComponent("directory-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for fileIndex in 0..<20 {
                try Data(repeating: UInt8(fileIndex), count: 32)
                    .write(to: directory.appendingPathComponent("file-\(fileIndex)"))
            }
        }

        let task = Task {
            try await NativeDiskAnalyzer().analyze(root: root, progress: nil)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled disk analysis must not return a completed report")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testBoundedScanDisclosesPartialSubtreeAndDeepRefreshRemovesLimit() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestCoverageTests-\(UUID().uuidString)", isDirectory: true)
        let crowded = root.appendingPathComponent("crowded", isDirectory: true)
        try FileManager.default.createDirectory(at: crowded, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<20 {
            try Data(repeating: UInt8(index), count: 128)
                .write(to: crowded.appendingPathComponent("item-\(index).bin"))
        }

        let analyzer = NativeDiskAnalyzer(
            cacheMaximumAge: 600,
            maximumTraversalEntriesPerItem: 5
        )
        let bounded = try await analyzer.analyze(
            root: root,
            cache: DiskScanCacheStore(),
            mode: .reuseFreshCache
        )
        XCTAssertEqual(bounded.coverage.limitedSubtreeCount, 1)
        XCTAssertTrue(bounded.coverage.hasKnownLimitOrReadGap)
        XCTAssertEqual(bounded.report.entries.first?.traversal?.entryLimit, 5)

        let exhaustive = try await analyzer.analyze(
            root: root,
            cache: bounded.updatedCache,
            mode: .bypassCache
        )
        XCTAssertTrue(exhaustive.coverage.unboundedTraversal)
        XCTAssertEqual(exhaustive.coverage.limitedSubtreeCount, 0)
        XCTAssertEqual(exhaustive.coverage.regularFileCount, 20)
        XCTAssertGreaterThan(exhaustive.report.totalBytes, bounded.report.totalBytes)
    }
}

private final class DiskProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DiskScanProgress] = []

    var values: [DiskScanProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: DiskScanProgress) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
