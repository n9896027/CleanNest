import Foundation
import XCTest
@testable import CleanNestCore

final class CleanupExecutionLedgerTests: XCTestCase {
    func testMixedExecutionPersistsExactSourceDestinationAndFailure() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let success = try fixture.makeCandidate(name: "success", bytes: 100)
        let failure = try fixture.makeCandidate(name: "failure", bytes: 200)
        let pending = CleanupExecutionRecord(
            id: "execution-mixed",
            candidates: [success, failure],
            freeBytesBefore: 1_000
        )
        let destination = fixture.trash.appendingPathComponent(success.name)
        try FileManager.default.moveItem(at: success.url, to: destination)
        let outcomes = [
            TrashOutcome(source: success.url, trashedURL: destination, errorDescription: nil),
            TrashOutcome(source: failure.url, trashedURL: fixture.trash.appendingPathComponent("fake"), errorDescription: "fixture denied", failureKind: .permissionDenied)
        ]

        let completed = pending.applying(
            outcomes: outcomes,
            trashDirectory: fixture.trash,
            freeBytesAfter: 1_010,
            now: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(completed.id, "execution-mixed")
        XCTAssertEqual(completed.candidateBytes, 300)
        XCTAssertEqual(completed.movedBytes, 100)
        XCTAssertEqual(completed.immediateAPFSFreeBytesDelta, 10)
        XCTAssertNil(completed.finalAPFSFreeBytesDelta)
        XCTAssertEqual(completed.items[0].status, .movedToTrash)
        XCTAssertEqual(completed.items[0].sourceURL, success.url)
        XCTAssertEqual(completed.items[0].trashURL, destination)
        XCTAssertNotNil(completed.items[0].sourceIdentity)
        XCTAssertEqual(completed.items[0].sourceIdentity, completed.items[0].trashIdentity)
        XCTAssertEqual(completed.items[1].status, .failed)
        XCTAssertNil(completed.items[1].trashURL)
        XCTAssertEqual(completed.items[1].errorDescription, "fixture denied")

        var snapshot = CleanupExecutionLedgerSnapshot()
        snapshot.insert(pending)
        snapshot.update(completed)
        let url = fixture.root.appendingPathComponent("state/ledger.json")
        try CleanupExecutionLedgerPersistence.save(snapshot, to: url)
        let loaded = try CleanupExecutionLedgerPersistence.load(from: url)
        XCTAssertNil(loaded.diagnostic)
        XCTAssertEqual(loaded.snapshot.records, [completed])
    }

    func testPendingRecordSurvivesRestartAndCorruptionFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let candidate = try fixture.makeCandidate(name: "pending", bytes: 50)
        let record = CleanupExecutionRecord(
            id: "interrupted",
            candidates: [candidate],
            freeBytesBefore: 500
        )
        var snapshot = CleanupExecutionLedgerSnapshot(records: [record])
        let url = fixture.root.appendingPathComponent("ledger.json")
        try CleanupExecutionLedgerPersistence.save(snapshot, to: url)

        var loaded = try CleanupExecutionLedgerPersistence.load(from: url)
        XCTAssertEqual(loaded.snapshot.records.first?.items.first?.status, .pending)
        XCTAssertFalse(loaded.snapshot.records.first?.isComplete ?? true)

        try Data("not-json".utf8).write(to: url)
        loaded = try CleanupExecutionLedgerPersistence.load(from: url)
        XCTAssertTrue(loaded.snapshot.records.isEmpty)
        XCTAssertNotNil(loaded.diagnostic)
        snapshot.records = []
        XCTAssertNoThrow(try CleanupExecutionLedgerPersistence.save(snapshot, to: url))
    }

    func testFinalObservationWaitsUntilRecordedTrashItemsAreGone() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let candidate = try fixture.makeCandidate(name: "space", bytes: 100)
        let destination = fixture.trash.appendingPathComponent(candidate.name)
        try FileManager.default.moveItem(at: candidate.url, to: destination)
        let record = CleanupExecutionRecord(candidates: [candidate], freeBytesBefore: 1_000)
            .applying(
                outcomes: [TrashOutcome(source: candidate.url, trashedURL: destination, errorDescription: nil)],
                trashDirectory: fixture.trash,
                freeBytesAfter: 900
            )

        XCTAssertEqual(record.immediateAPFSFreeBytesDelta, -100)
        XCTAssertNil(record.finalAPFSFreeBytesDelta)
        XCTAssertNil(record.confirmingFinalObservation(currentFreeBytes: 1_100).finalAPFSFreeBytesDelta)
        try FileManager.default.removeItem(at: destination)
        let final = record.confirmingFinalObservation(currentFreeBytes: 1_100)
        XCTAssertEqual(final.finalAPFSFreeBytesDelta, 100)
        XCTAssertNotNil(final.finalAPFSObservedAt)
    }

    func testRestoreSuccessAndDuplicateRestoreNeverOverwrite() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let moved = try fixture.makeMovedRecord(name: "restore")
        let service = CleanupRestoreService(homeDirectory: fixture.home, trashDirectory: fixture.trash)

        let restored = service.restore(moved.items[0])
        XCTAssertNil(restored.errorDescription)
        XCTAssertEqual(restored.status, .restored)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.items[0].sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.items[0].trashURL!.path))

        let duplicate = service.restore(restored)
        XCTAssertEqual(duplicate.status, .restored)
        XCTAssertEqual(duplicate.errorDescription, CleanupRestoreError.alreadyRestored.localizedDescription)
    }

    func testRestoreRejectsExistingSourceChangedIdentityAndOutsideTrash() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let service = CleanupRestoreService(homeDirectory: fixture.home, trashDirectory: fixture.trash)

        let conflict = try fixture.makeMovedRecord(name: "conflict")
        try Data("new-content".utf8).write(to: conflict.items[0].sourceURL)
        let conflictResult = service.restore(conflict.items[0])
        XCTAssertEqual(conflictResult.status, .restoreFailed)
        XCTAssertEqual(conflictResult.errorDescription, CleanupRestoreError.sourceAlreadyExists.localizedDescription)
        XCTAssertEqual(try String(contentsOf: conflict.items[0].sourceURL), "new-content")
        XCTAssertTrue(FileManager.default.fileExists(atPath: conflict.items[0].trashURL!.path))

        let changed = try fixture.makeMovedRecord(name: "changed")
        try Data("changed-content".utf8).write(to: changed.items[0].trashURL!)
        let changedResult = service.restore(changed.items[0])
        XCTAssertEqual(changedResult.status, .restoreFailed)
        XCTAssertEqual(changedResult.errorDescription, CleanupRestoreError.trashIdentityChanged.localizedDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: changed.items[0].sourceURL.path))

        let outsideRecord = try fixture.makeMovedRecord(name: "outside")
        let outsideURL = fixture.root.appendingPathComponent("outside")
        try FileManager.default.moveItem(at: outsideRecord.items[0].trashURL!, to: outsideURL)
        var outsideItem = outsideRecord.items[0]
        // Simulate a damaged or externally edited ledger pointing outside Trash.
        let data = try JSONEncoder().encode(outsideItem)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["trashURL"] = outsideURL.absoluteString
        outsideItem = try JSONDecoder().decode(
            CleanupExecutionItem.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        let outsideResult = service.restore(outsideItem)
        XCTAssertEqual(outsideResult.status, .restoreFailed)
        XCTAssertEqual(outsideResult.errorDescription, CleanupRestoreError.outsideCurrentUserTrash.localizedDescription)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideURL.path))
    }

    func testSuccessfulOutcomeWithMissingDestinationBecomesIndeterminate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let candidate = try fixture.makeCandidate(name: "uncertain", bytes: 10)
        try FileManager.default.removeItem(at: candidate.url)
        let record = CleanupExecutionRecord(candidates: [candidate], freeBytesBefore: 10)
            .applying(
                outcomes: [TrashOutcome(source: candidate.url, trashedURL: nil, errorDescription: nil)],
                trashDirectory: fixture.trash,
                freeBytesAfter: nil
            )
        XCTAssertEqual(record.items[0].status, .indeterminate)
        XCTAssertNil(record.items[0].trashIdentity)
        XCTAssertNil(record.immediateAPFSFreeBytesDelta)
    }

    private final class Fixture {
        let root: URL
        let home: URL
        let trash: URL
        private var counter = 0

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CleanNestExecutionLedgerTests-\(UUID().uuidString)", isDirectory: true)
            home = root.appendingPathComponent("home", isDirectory: true)
            trash = home.appendingPathComponent(".Trash", isDirectory: true)
            try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        }

        func makeCandidate(name: String, bytes: Int) throws -> CleanupCandidate {
            counter += 1
            let directory = home.appendingPathComponent("Library/Caches/com.example.\(counter)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try Data(repeating: 0x41, count: bytes).write(to: url)
            return CleanupCandidate(
                name: name,
                url: url,
                kind: .appCache,
                allocatedBytes: Int64(bytes),
                modifiedAt: nil,
                isRecommended: false,
                detail: "temporary fixture",
                fileIdentity: try CleanupFileIdentity.capture(at: url)
            )
        }

        func makeMovedRecord(name: String) throws -> CleanupExecutionRecord {
            let candidate = try makeCandidate(name: name, bytes: 32)
            let pending = CleanupExecutionRecord(candidates: [candidate], freeBytesBefore: 100)
            let destination = trash.appendingPathComponent(name)
            try FileManager.default.moveItem(at: candidate.url, to: destination)
            return pending.applying(
                    outcomes: [TrashOutcome(source: candidate.url, trashedURL: destination, errorDescription: nil)],
                    trashDirectory: trash,
                    freeBytesAfter: 100
                )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
