import Foundation
import XCTest
@testable import CleanNestCore

final class SystemDataInventoryTests: XCTestCase {
    private func home() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanNest-SystemData-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func location(_ id: String = "test", path: String = "cache", protected: Bool = false,
                          disposition: SystemDataDisposition = .rebuildable) -> SystemDataLocation {
        SystemDataLocation(id: id, relativePath: path, name: "测试缓存", owner: "Example",
            purpose: "下载并使用过的副本", impact: "以后可能重新下载", disposition: disposition,
            requiresProtectedAccess: protected)
    }

    private func file(_ path: String, in root: URL, count: Int = 8192) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x31, count: count).write(to: url)
        return url
    }

    func testCatalogIsDisjointBoundedAndHasConsequencesForEveryLocation() {
        XCTAssertTrue(SystemDataCatalog.isValid(SystemDataCatalog.locations))
        XCTAssertEqual(SystemDataCatalog.locations.count, 25)
        for item in SystemDataCatalog.locations {
            XCTAssertFalse(item.purpose.isEmpty)
            XCTAssertFalse(item.impact.isEmpty)
        }
        let models = SystemDataCatalog.locations.filter { ["ollama", "huggingface", "lmstudio"].contains($0.id) }
        XCTAssertTrue(models.allSatisfy { $0.disposition == .ownerManaged })
        XCTAssertEqual(SystemDataCatalog.locations.first { $0.id == "ios-backups" }?.disposition, .review)
    }

    func testCatalogRejectsTraversalDuplicateAndParentOverlap() {
        for path in ["", "/tmp/cache", "../cache", "a/../cache", "a//b", "a/./b", "a\0b", "a\nb"] {
            XCTAssertFalse(SystemDataCatalog.isValid([location(path: path)]), path)
        }
        XCTAssertFalse(SystemDataCatalog.isValid([location(), location()]))
        XCTAssertFalse(SystemDataCatalog.isValid([location("a", path: "cache"), location("b", path: "cache/pip")]))
        XCTAssertFalse(SystemDataCatalog.isValid([location("a", path: "Cache"), location("b", path: "cache/Pip")]))
        XCTAssertTrue(SystemDataCatalog.isValid([location("a", path: "cache"), location("b", path: "cache-old")]))
    }

    func testScannerMeasuresMetadataAndDoesNotChangeFiles() async throws {
        let root = try home()
        let url = try file("cache/archive.bin", in: root)
        let before = try Data(contentsOf: url)
        let report = try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: false,
                                                      locations: [location()])
        let item = try XCTUnwrap(report.items.first)
        XCTAssertEqual(item.status, .measured)
        XCTAssertEqual(item.traversal?.regularFileCount, 1)
        XCTAssertEqual(item.allocatedBytes, FileTree.allocatedSize(of: url))
        XCTAssertNotNil(item.latestModificationDate)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testProtectedLocationIsSkippedBeforeLookingForIt() async throws {
        let root = try home()
        let report = try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: false,
                                                      locations: [location(path: "not-created", protected: true)])
        XCTAssertEqual(report.items.first?.status, .protectedLocation)
        XCTAssertNil(report.items.first?.allocatedBytes)
        XCTAssertEqual(report.incompleteCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("not-created").path))
    }

    func testMissingUserPermissionSentinelDoesNotHideARealAccessResult() {
        XCTAssertEqual(FullDiskAccessProbeResult.classifyProbeResults([ENOENT, 0]), .accessible)
        XCTAssertEqual(FullDiskAccessProbeResult.classifyProbeResults([ENOENT, EPERM]), .permissionDenied)
        XCTAssertEqual(FullDiskAccessProbeResult.classifyProbeResults([ENOENT, ENOENT]), .indeterminate)
        XCTAssertEqual(FullDiskAccessProbeResult.classifyProbeResults([EIO]), .indeterminate)
        XCTAssertEqual(FullDiskAccessProbeResult.classifyProbeResults([]), .indeterminate)
    }

    func testMissingIsNotReportedAsZeroAndEmptyIsNotReportedMissing() async throws {
        let root = try home()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("empty"), withIntermediateDirectories: true)
        let report = try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: true,
            locations: [location("missing", path: "missing"), location("empty", path: "empty")])
        XCTAssertEqual(report.items[0].status, .notFound)
        XCTAssertNil(report.items[0].allocatedBytes)
        XCTAssertEqual(report.items[1].status, .measured)
        XCTAssertEqual(report.items[1].allocatedBytes, 0)
    }

    func testSymlinkAtRootOrIntermediateComponentNeverEscapesHome() async throws {
        let root = try home()
        let outside = try home()
        _ = try file("cache/private.bin", in: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        for path in ["linked", "linked/cache"] {
            let report = try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: true,
                                                          locations: [location(path: path)])
            XCTAssertEqual(report.items.first?.status, .symbolicLink)
            XCTAssertNil(report.items.first?.allocatedBytes)
        }
    }

    func testNestedSymlinkIsSkippedAndCoverageIsPartial() async throws {
        let root = try home()
        let outside = try home()
        _ = try file("secret.bin", in: outside)
        _ = try file("cache/local.bin", in: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cache/link"), withDestinationURL: outside)
        let report = try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: true, locations: [location()])
        XCTAssertEqual(report.items.first?.status, .partial)
        XCTAssertEqual(report.items.first?.traversal?.regularFileCount, 1)
        XCTAssertEqual(report.items.first?.traversal?.symbolicLinkCount, 1)
    }

    func testUnreadableDirectoryNeverLooksLikeAnEmptyCache() async throws {
        let root = try home()
        _ = try file("cache/retained.bin", in: root)
        let directory = root.appendingPathComponent("cache")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        let report = try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: true, locations: [location()])
        XCTAssertEqual(report.items.first?.status, .unreadable)
        XCTAssertNil(report.items.first?.allocatedBytes)
    }

    func testTraversalLimitIsExplicitAndClamped() async throws {
        let root = try home()
        for index in 0..<8 { _ = try file("cache/\(index).bin", in: root) }
        let report = try await SystemDataScanner(maximumEntriesPerLocation: 2).scan(
            homeDirectory: root, protectedAccessConfirmed: true, locations: [location()])
        XCTAssertEqual(report.items.first?.status, .partial)
        XCTAssertEqual(report.items.first?.traversal?.reachedEntryLimit, true)
        XCTAssertEqual(report.items.first?.traversal?.visitedEntryCount, 2)
        XCTAssertEqual(SystemDataScanner(maximumEntriesPerLocation: .max).maximumEntriesPerLocation, 100_000)
    }

    func testCancelledParentNeverPublishesCompletedReport() async throws {
        let root = try home()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SystemDataScanner().scan(homeDirectory: root, protectedAccessConfirmed: true)
        }
        do { _ = try await task.value; XCTFail("Cancelled scan returned a report") }
        catch is CancellationError { }
    }

    func testChangeRequiresSameLocationAndTwoCompleteMeasurements() {
        let entry = location()
        let url = URL(fileURLWithPath: "/Users/Demo/cache")
        let old = SystemDataItem(location: entry, url: url, status: .measured, allocatedBytes: 900)
        let new = SystemDataItem(location: entry, url: url, status: .measured, allocatedBytes: 1200)
        XCTAssertEqual(new.change(from: old), 300)
        for status: SystemDataMeasurementStatus in [.partial, .unreadable, .protectedLocation, .notFound, .symbolicLink, .otherVolume] {
            let partial = SystemDataItem(location: entry, url: url, status: status, allocatedBytes: 1)
            XCTAssertNil(partial.change(from: old))
            XCTAssertNil(new.change(from: partial))
        }
        XCTAssertNil(new.change(from: SystemDataItem(location: entry, url: URL(fileURLWithPath: "/different"), status: .measured, allocatedBytes: 1)))
    }

    func testSearchFiltersAndClearedRowsHaveRealConsequences() {
        let url = URL(fileURLWithPath: "/Users/Demo")
        let cache = SystemDataItem(location: location("cache"), url: url, status: .measured, allocatedBytes: 0)
        let old = SystemDataItem(location: cache.location, url: url, status: .measured, allocatedBytes: 800)
        let model = SystemDataItem(location: location("model", path: "models", disposition: .ownerManaged), url: url, status: .measured, allocatedBytes: 1200)
        let blocked = SystemDataItem(location: location("blocked", path: "blocked", protected: true, disposition: .review), url: url, status: .protectedLocation)
        let report = SystemDataReport(items: [cache, model, blocked], volume: nil)
        let previous = SystemDataReport(items: [old], volume: nil)
        XCTAssertEqual(report.visibleItems(query: "", filter: .all, previous: nil).count, 2)
        XCTAssertEqual(report.visibleItems(query: "", filter: .all, previous: previous).count, 3)
        XCTAssertEqual(report.visibleItems(query: "", filter: .managed, previous: previous).count, 2)
        XCTAssertEqual(report.visibleItems(query: "", filter: .gaps, previous: previous).map(\.id), ["blocked"])
        XCTAssertEqual(report.visibleItems(query: "MODELS", filter: .managed, previous: previous).map(\.id), ["model"])
        XCTAssertTrue(report.visibleItems(query: "unknown", filter: .all, previous: previous).isEmpty)
    }

    func testWorkerTransportPreservesMetadataAndMissingAccess() async throws {
        let root = try home()
        _ = try file(".npm/_cacache/package.bin", in: root)
        let request = SystemDataScannerRequest(homeDirectory: root, protectedAccessConfirmed: false)
        let decoded = try ScannerServiceCodec.decode(SystemDataScannerRequest.self, from: ScannerServiceCodec.encode(request))
        let response = try await ScannerWorker().scanSystemData(decoded)
        let result = try ScannerServiceCodec.decode(SystemDataScannerResponse.self, from: ScannerServiceCodec.encode(response))
        XCTAssertEqual(result, response)
        XCTAssertEqual(result.requestID, request.requestID)
        XCTAssertEqual(result.report.items.first { $0.id == "npm" }?.status, .measured)
        XCTAssertEqual(result.report.items.first { $0.id == "docker" }?.status, .protectedLocation)
    }
}
