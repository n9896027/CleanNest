import Foundation
import XCTest
@testable import CleanNestCore

final class APFSReadOnlyDiagnosticsTests: XCTestCase {
    func testSparseFileSeparatesLogicalAndAllocatedSizes() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sparse.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: url.path, contents: Data([0x41])))
        let handle = try FileHandle(forWritingTo: url)
        let logicalSize: UInt64 = 64 * 1_024 * 1_024 + 1
        try handle.seek(toOffset: logicalSize - 1)
        try handle.write(contentsOf: Data([0x42]))
        try handle.close()

        let evidence = try SparseFileSizeEvidence.capture(at: url)

        XCTAssertEqual(evidence.logicalBytes, Int64(logicalSize))
        XCTAssertGreaterThan(evidence.allocatedBytes, 0)
        XCTAssertLessThan(evidence.allocatedBytes, evidence.logicalBytes)
        XCTAssertTrue(evidence.isSparse)
        XCTAssertEqual(evidence.unallocatedLogicalBytes, evidence.logicalBytes - evidence.allocatedBytes)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber, NSNumber(value: logicalSize))
    }

    func testSparseCaptureRejectsDirectoryAndSymbolicLink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("file.bin")
        try Data("value".utf8).write(to: file)
        let link = root.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertThrowsError(try SparseFileSizeEvidence.capture(at: root)) {
            XCTAssertEqual($0 as? SparseFileSizeEvidenceError, .notRegularFile)
        }
        XCTAssertThrowsError(try SparseFileSizeEvidence.capture(at: link)) {
            XCTAssertEqual($0 as? SparseFileSizeEvidenceError, .notRegularFile)
        }
    }

    func testReadOnlyCaptureParsesVolumeSnapshotsAndTrashWithoutMutationCommands() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let trash = root.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4_096).write(to: trash.appendingPathComponent("item.bin"))
        let calls = RecordedCalls()
        let diagnostics = APFSReadOnlyDiagnostics(trashDirectory: trash) { executable, arguments, _ in
            await calls.record(executable: executable, arguments: arguments)
            if executable.lastPathComponent == "diskutil" {
                return Self.result(executable, arguments, """
                APFS Container (1 found)
                APFS Volume disk3s1
                Name: Macintosh HD (No specific role)
                Role: System
                Capacity: 500.0 GB (500000000000 Bytes)
                Used: 200.0 GB (200000000000 Bytes)
                APFS Volume disk3s2
                Name: Data
                Role: Data
                Capacity: 500.0 GB (500000000000 Bytes)
                Used: 250.0 GB (250000000000 Bytes)
                """)
            }
            return Self.result(executable, arguments, """
            com.apple.TimeMachine.2026-11-23-120000.local
            com.apple.TimeMachine.2026-11-22-120000.local
            """)
        }

        let report = await diagnostics.capture(selectedRoot: root)

        XCTAssertEqual(report.apfsVolumes.count, 2)
        XCTAssertEqual(report.apfsVolumes[0].name, "Macintosh HD (No specific role)")
        XCTAssertEqual(report.apfsVolumes[0].role, "System")
        XCTAssertEqual(report.apfsVolumes[0].capacityBytes, 500_000_000_000)
        XCTAssertEqual(report.apfsVolumes[1].usedBytes, 250_000_000_000)
        XCTAssertEqual(report.localSnapshots.count, 2)
        XCTAssertEqual(report.trash.logicalBytes, 4_096)
        XCTAssertEqual(report.trash.allocatedBytes ?? 0, 4_096)
        XCTAssertTrue(report.trash.isComplete)
        XCTAssertTrue(report.commands.allSatisfy(\.succeeded))
        let recorded = await calls.values()
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded.map(\.arguments), [["apfs", "list"], ["listlocalsnapshots", "/"]])
        XCTAssertFalse(recorded.flatMap(\.arguments).contains { $0.contains("delete") || $0.contains("purge") })
    }

    func testMissingTrashAndCommandFailuresRemainUnknown() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = APFSReadOnlyDiagnostics(
            trashDirectory: root.appendingPathComponent("MissingTrash")
        ) { executable, arguments, _ in
            if executable.lastPathComponent == "diskutil" {
                return CommandResult(
                    executable: executable,
                    arguments: arguments,
                    exitCode: 1,
                    standardOutput: "sensitive raw output must not be retained",
                    standardError: "sensitive error",
                    duration: 0
                )
            }
            throw CommandRunnerError.timedOut(0.01)
        }

        let report = await diagnostics.capture(selectedRoot: root)

        XCTAssertNil(report.trash.logicalBytes)
        XCTAssertNil(report.trash.allocatedBytes)
        XCTAssertFalse(report.trash.isComplete)
        XCTAssertTrue(report.apfsVolumes.isEmpty)
        XCTAssertTrue(report.localSnapshots.isEmpty)
        XCTAssertEqual(report.commands.count, 2)
        XCTAssertTrue(report.commands.allSatisfy { !$0.succeeded })
        XCTAssertTrue(report.hasUnknownEvidence)
        XCTAssertFalse(report.commands.map(\.diagnostic).joined().contains("sensitive"))
    }

    func testCurrentMacOSVolumeHeadersAndCapacityConsumedAreParsed() {
        let parsed = APFSReadOnlyDiagnostics.parseAPFSVolumes("""
        APFS Containers (1 found)
        +-> Volume disk3s1 F0DC0E34-24FA-47DB-8B0F-4507DE1F7516
        |   APFS Volume Disk (Role):   disk3s1 (System)
        |   Name:                      Macintosh HD (Case-insensitive)
        |   Capacity Consumed:         13811732480 B (13.8 GB)
        +-> Volume disk3s2 F0DC0E34-24FA-47DB-8B0F-4507DE1F7517
        |   APFS Volume Disk (Role):   disk3s2 (Preboot)
        |   Name:                      Preboot (Case-insensitive)
        |   Capacity Consumed:         11245420544 B (11.2 GB)
        +-> Volume disk3s3 F0DC0E34-24FA-47DB-8B0F-4507DE1F7518
        |   APFS Volume Disk (Role):   disk3s3 (Recovery)
        |   Name:                      Recovery (Case-insensitive)
        |   Capacity Consumed:         1593655296 B (1.6 GB)
        +-> Volume disk3s5 F0DC0E34-24FA-47DB-8B0F-4507DE1F7519
        |   APFS Volume Disk (Role):   disk3s5 (Data)
        |   Name:                      Macintosh HD - Data (Case-insensitive)
        |   Capacity Consumed:         732968001536 B (733.0 GB)
        +-> Volume disk3s6 9EEFA3B7-09DE-4C37-95FC-4E5E16771496
            APFS Volume Disk (Role):   disk3s6 (VM)
            Name:                      VM (Case-insensitive)
            Capacity Consumed:         4294991872 B (4.3 GB)
        """)

        XCTAssertEqual(parsed.volumes.map(\.id), ["disk3s1", "disk3s2", "disk3s3", "disk3s5", "disk3s6"])
        XCTAssertEqual(parsed.volumes.map(\.role), ["System", "Preboot", "Recovery", "Data", "VM"])
        XCTAssertEqual(parsed.volumes.map(\.usedBytes), [13_811_732_480, 11_245_420_544, 1_593_655_296, 732_968_001_536, 4_294_991_872])
        XCTAssertEqual(parsed.volumes.map(\.capacityBytes), [nil, nil, nil, nil, nil])
        XCTAssertTrue(parsed.diagnostics.isEmpty)
    }

    func testSnapshotCommandHeadersAreNotCountedAsSnapshots() {
        let empty = APFSReadOnlyDiagnostics.parseLocalSnapshots("Snapshots for disk /:\n")
        XCTAssertTrue(empty.snapshots.isEmpty)
        XCTAssertTrue(empty.diagnostics.isEmpty)

        let one = APFSReadOnlyDiagnostics.parseLocalSnapshots("""
        Snapshots for disk /:
        com.apple.TimeMachine.2026-11-23-120000.local
        """)
        XCTAssertEqual(one.snapshots, ["com.apple.TimeMachine.2026-11-23-120000.local"])
        XCTAssertTrue(one.diagnostics.isEmpty)
    }

    func testUnparseableOutputDoesNotInventVolumesOrSnapshots() {
        let volumes = APFSReadOnlyDiagnostics.parseAPFSVolumes("not an APFS listing")
        XCTAssertTrue(volumes.volumes.isEmpty)
        XCTAssertFalse(volumes.diagnostics.isEmpty)

        let snapshots = APFSReadOnlyDiagnostics.parseLocalSnapshots("\n  \n")
        XCTAssertTrue(snapshots.snapshots.isEmpty)
        XCTAssertTrue(snapshots.diagnostics.isEmpty)
    }

    private static func result(_ executable: URL, _ arguments: [String], _ output: String) -> CommandResult {
        CommandResult(
            executable: executable,
            arguments: arguments,
            exitCode: 0,
            standardOutput: output,
            standardError: "",
            duration: 0
        )
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestAPFSTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

private actor RecordedCalls {
    struct Call {
        let executable: URL
        let arguments: [String]
    }

    private var calls: [Call] = []

    func record(executable: URL, arguments: [String]) {
        calls.append(Call(executable: executable, arguments: arguments))
    }

    func values() -> [Call] { calls }
}
