import Foundation
import XCTest
import CleanNestCore

final class DiskPerspectiveTests: XCTestCase {
    func testDirectoryPerspectivePreservesEveryScannedEntryAndCoverage() {
        let complete = traversal(reachedLimit: false)
        let partial = traversal(reachedLimit: true)
        let entries = [
            DiskEntry(name: "Models", url: URL(fileURLWithPath: "/Users/test/Models"), bytes: 28_000, isDirectory: true, traversal: complete),
            DiskEntry(name: "Library", url: URL(fileURLWithPath: "/Users/test/Library"), bytes: 50_000, isDirectory: true, traversal: partial)
        ]
        let report = DiskReport(root: URL(fileURLWithPath: "/Users/test"), entries: entries, largeFiles: [], totalBytes: 78_000, totalFiles: 10)

        let ledger = DiskPerspectiveBuilder.make(
            report: report,
            evidenceReport: nil,
            perspective: .directory,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )

        XCTAssertEqual(ledger.rows.map(\.title), ["Library", "Models"])
        XCTAssertEqual(ledger.accountedBytes, report.totalBytes)
        XCTAssertTrue(ledger.containsPartialCoverage)
        XCTAssertEqual(ledger.rows.first?.coverage, .partial)
    }

    func testApplicationPerspectiveGroupsOnlyPathConfirmedOwners() {
        let home = URL(fileURLWithPath: "/Users/test")
        let dockerContainer = DiskEntry(
            name: "com.docker.docker",
            url: home.appendingPathComponent("Library/Containers/com.docker.docker"),
            bytes: 30_000,
            isDirectory: true,
            traversal: traversal(reachedLimit: false)
        )
        let dockerCache = DiskEntry(
            name: "com.docker.docker",
            url: home.appendingPathComponent("Library/Caches/com.docker.docker"),
            bytes: 2_000,
            isDirectory: true,
            traversal: traversal(reachedLimit: false)
        )
        let unknown = DiskEntry(
            name: "Documents",
            url: home.appendingPathComponent("Documents"),
            bytes: 8_000,
            isDirectory: true,
            traversal: traversal(reachedLimit: false)
        )
        let report = DiskReport(root: home, entries: [dockerContainer, dockerCache, unknown], largeFiles: [], totalBytes: 40_000, totalFiles: 3)

        let ledger = DiskPerspectiveBuilder.make(
            report: report,
            evidenceReport: nil,
            perspective: .application,
            homeDirectory: home
        )

        XCTAssertEqual(ledger.accountedBytes, report.totalBytes)
        XCTAssertEqual(ledger.rows.first?.title, "Docker")
        XCTAssertEqual(ledger.rows.first?.bytes, 32_000)
        XCTAssertEqual(ledger.rows.first?.members.count, 2)
        XCTAssertEqual(ledger.unresolvedBytes, 8_000)
        XCTAssertEqual(ledger.rows.last?.title, "归属待确认")
    }

    func testFunctionalPerspectiveSeparatesModelsVMsAgentsAndPersonalFiles() {
        let home = URL(fileURLWithPath: "/Users/test")
        let entries = [
            DiskEntry(name: "MLX", url: home.appendingPathComponent("Models/MLX"), bytes: 28_000, isDirectory: true, traversal: traversal(reachedLimit: false)),
            DiskEntry(name: "Docker.raw", url: home.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"), bytes: 31_000, isDirectory: false),
            DiskEntry(name: ".codex", url: home.appendingPathComponent(".codex"), bytes: 17_000, isDirectory: true, traversal: traversal(reachedLimit: false)),
            DiskEntry(name: "Pictures", url: home.appendingPathComponent("Pictures"), bytes: 12_000, isDirectory: true, traversal: traversal(reachedLimit: false))
        ]
        let report = DiskReport(root: home, entries: entries, largeFiles: [], totalBytes: 88_000, totalFiles: 4)

        let ledger = DiskPerspectiveBuilder.make(
            report: report,
            evidenceReport: nil,
            perspective: .function,
            homeDirectory: home
        )

        XCTAssertEqual(ledger.accountedBytes, report.totalBytes)
        XCTAssertEqual(bytes(in: .localAIModels, ledger: ledger), 28_000)
        XCTAssertEqual(bytes(in: .virtualMachinesAndContainers, ledger: ledger), 31_000)
        XCTAssertEqual(bytes(in: .developmentAndAgents, ledger: ledger), 17_000)
        XCTAssertEqual(bytes(in: .personalContent, ledger: ledger), 12_000)
        XCTAssertEqual(ledger.unresolvedBytes, 0)
    }

    func testRootFunctionalPerspectiveDoesNotCallApplicationsOrSystemUnknown() {
        let root = URL(fileURLWithPath: "/")
        let entries = [
            DiskEntry(name: "Applications", url: URL(fileURLWithPath: "/Applications"), bytes: 40, isDirectory: true, traversal: traversal(reachedLimit: false)),
            DiskEntry(name: "System", url: URL(fileURLWithPath: "/System"), bytes: 20, isDirectory: true, traversal: traversal(reachedLimit: false)),
            DiskEntry(name: "Users", url: URL(fileURLWithPath: "/Users"), bytes: 200, isDirectory: true, traversal: traversal(reachedLimit: false))
        ]
        let report = DiskReport(root: root, entries: entries, largeFiles: [], totalBytes: 260, totalFiles: 3)

        let ledger = DiskPerspectiveBuilder.make(
            report: report,
            evidenceReport: nil,
            perspective: .function,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        )

        XCTAssertEqual(bytes(in: .applicationsAndData, ledger: ledger), 40)
        XCTAssertEqual(bytes(in: .systemAndShared, ledger: ledger), 20)
        XCTAssertEqual(bytes(in: .personalContent, ledger: ledger), 200)
        XCTAssertEqual(ledger.unresolvedBytes, 0)
    }

    private func bytes(in group: DiskLedgerFunctionalGroup, ledger: DiskPerspectiveLedger) -> Int64? {
        ledger.rows.first { $0.functionalGroup == group }?.bytes
    }

    private func traversal(reachedLimit: Bool) -> FileTreeTraversalEvidence {
        FileTreeTraversalEvidence(
            rootWasReadable: true,
            visitedEntryCount: reachedLimit ? 100 : 10,
            regularFileCount: reachedLimit ? 90 : 9,
            unreadableEntryCount: 0,
            crossVolumeEntryCount: 0,
            symbolicLinkCount: 0,
            reachedEntryLimit: reachedLimit,
            entryLimit: reachedLimit ? 100 : 500_000
        )
    }
}
