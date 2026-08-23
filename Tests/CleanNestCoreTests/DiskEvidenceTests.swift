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

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestEvidenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
