import Foundation
import XCTest
import CleanNestCore

final class DiskCapacityTruthTests: XCTestCase {
    func testReconciliationKeepsAPFSUsedFreeAndClassifiedBytesSeparate() {
        let volume = DiskVolumeSnapshot(
            selectedRoot: URL(fileURLWithPath: "/"),
            volumeRoot: URL(fileURLWithPath: "/"),
            volumeName: "Macintosh HD",
            totalBytes: 994_000_000_000,
            availableBytes: 126_000_000_000,
            availableForImportantUsageBytes: 153_000_000_000,
            selectedRootIsVolumeRoot: true
        )
        let result = DiskCapacityReconciliation(
            volume: volume,
            classifiedBytes: 314_000_000_000
        )

        XCTAssertEqual(volume.usedBytes, 868_000_000_000)
        XCTAssertEqual(volume.reclaimableCapacityBytes, 27_000_000_000)
        XCTAssertEqual(result.accountingDifferenceBytes, 554_000_000_000)
        XCTAssertEqual(result.classifiedShareOfUsed ?? 0, 314.0 / 868.0, accuracy: 0.000_001)
    }

    func testFolderScanDoesNotInventWholeVolumeDifference() {
        let volume = DiskVolumeSnapshot(
            selectedRoot: URL(fileURLWithPath: "/Users/example"),
            volumeRoot: URL(fileURLWithPath: "/"),
            volumeName: "Macintosh HD",
            totalBytes: 1_000,
            availableBytes: 200,
            availableForImportantUsageBytes: nil,
            selectedRootIsVolumeRoot: false
        )
        let result = DiskCapacityReconciliation(volume: volume, classifiedBytes: 300)

        XCTAssertFalse(result.isComparable)
        XCTAssertNil(result.accountingDifferenceBytes)
        XCTAssertNil(result.classifiedShareOfUsed)
    }

    func testCurrentVolumeSnapshotUsesMacOSCapacityLedger() throws {
        let snapshot = try XCTUnwrap(
            DiskVolumeSnapshot.capture(for: FileManager.default.homeDirectoryForCurrentUser)
        )
        XCTAssertGreaterThan(snapshot.totalBytes, 0)
        XCTAssertGreaterThan(snapshot.availableBytes, 0)
        XCTAssertEqual(snapshot.usedBytes, snapshot.totalBytes - snapshot.availableBytes)
        XCTAssertFalse(snapshot.selectedRootIsVolumeRoot)
    }
}
