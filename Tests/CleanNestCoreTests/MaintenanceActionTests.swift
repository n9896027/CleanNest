import XCTest
@testable import CleanNestCore

final class MaintenanceActionTests: XCTestCase {
    func testMaintenanceActionsUseOnlyExplicitUnprivilegedCommands() {
        XCTAssertEqual(
            MaintenanceAction.allCases,
            [.quickLook, .finder, .dock, .menuBar]
        )
        XCTAssertEqual(MaintenanceAction.quickLook.executable.path, "/usr/bin/qlmanage")
        XCTAssertEqual(MaintenanceAction.quickLook.arguments, ["-r", "cache"])
        XCTAssertNil(MaintenanceAction.quickLook.verificationProcessName)

        let restartActions: [(MaintenanceAction, String)] = [
            (.finder, "Finder"),
            (.dock, "Dock"),
            (.menuBar, "SystemUIServer")
        ]
        for (action, processName) in restartActions {
            XCTAssertEqual(action.executable.path, "/usr/bin/killall")
            XCTAssertEqual(action.arguments, [processName])
            XCTAssertEqual(action.verificationProcessName, processName)
        }
    }

    func testEveryMaintenanceActionExplainsSymptomImpactSafetyAndRecovery() {
        for action in MaintenanceAction.allCases {
            XCTAssertFalse(action.symptom.isEmpty)
            XCTAssertFalse(action.effect.isEmpty)
            XCTAssertFalse(action.safetyNote.isEmpty)
            XCTAssertFalse(action.recovery.isEmpty)
            XCTAssertFalse(action.explanation.isEmpty)
            XCTAssertFalse(action.interruptionSummary.isEmpty)
        }
    }

    func testEveryMaintenanceActionHasNoAnomalyAndAnomalyPreflightPaths() {
        for action in MaintenanceAction.allCases {
            let normal = MaintenanceDiagnosticPolicy.assess(
                action: action,
                processIDs: action == .quickLook ? [] : [101],
                readOnlyProbeSucceeded: true
            )
            XCTAssertEqual(normal.state, .noAnomalyDetected, action.rawValue)
            XCTAssertFalse(normal.headline.isEmpty)
            XCTAssertFalse(normal.detail.isEmpty)

            let abnormal = MaintenanceDiagnosticPolicy.assess(
                action: action,
                processIDs: [],
                readOnlyProbeSucceeded: false
            )
            XCTAssertEqual(abnormal.state, .anomalyDetected, action.rawValue)
            XCTAssertFalse(abnormal.headline.isEmpty)
        }
    }

    func testEveryMaintenanceActionHasVerifiedExecutionPath() {
        for action in MaintenanceAction.allCases {
            let before = MaintenanceDiagnosticPolicy.assess(
                action: action,
                processIDs: action == .quickLook ? [] : [101],
                readOnlyProbeSucceeded: true
            )
            let after = MaintenanceDiagnosticPolicy.assess(
                action: action,
                processIDs: action == .quickLook ? [] : [202],
                readOnlyProbeSucceeded: true
            )
            let record = MaintenanceDiagnosticPolicy.verify(
                action: action,
                startedAt: Date(timeIntervalSince1970: 100),
                before: before,
                after: after,
                commandSucceeded: true,
                finishedAt: Date(timeIntervalSince1970: 101)
            )

            let expected: MaintenanceRunOutcome = action == .quickLook
                ? .basicVerificationPassed
                : .verifiedRecovered
            XCTAssertEqual(record.outcome, expected, action.rawValue)
            XCTAssertTrue(record.outcome.isSuccessful)
            XCTAssertFalse(record.summary.isEmpty)
        }
    }

    func testEveryMaintenanceActionRefusesToCallMissingRecoverySuccess() {
        for action in MaintenanceAction.allCases {
            let before = MaintenanceDiagnosticPolicy.assess(
                action: action,
                processIDs: action == .quickLook ? [] : [101],
                readOnlyProbeSucceeded: true
            )
            let after = MaintenanceDiagnosticPolicy.assess(
                action: action,
                processIDs: [],
                readOnlyProbeSucceeded: false
            )
            let record = MaintenanceDiagnosticPolicy.verify(
                action: action,
                startedAt: Date(timeIntervalSince1970: 100),
                before: before,
                after: after,
                commandSucceeded: true,
                finishedAt: Date(timeIntervalSince1970: 101)
            )

            XCTAssertEqual(record.outcome, .notRecovered, action.rawValue)
            XCTAssertFalse(record.outcome.isSuccessful)
        }
    }

    func testUnknownPreflightAndCommandFailureStayHonest() {
        for action in MaintenanceAction.allCases {
            let unknown = MaintenanceDiagnosticPolicy.assess(
                action: action,
                readOnlyProbeSucceeded: nil
            )
            XCTAssertEqual(unknown.state, .uncertain)

            let record = MaintenanceDiagnosticPolicy.verify(
                action: action,
                startedAt: Date(timeIntervalSince1970: 100),
                before: unknown,
                after: unknown,
                commandSucceeded: false,
                finishedAt: Date(timeIntervalSince1970: 101)
            )
            XCTAssertEqual(record.outcome, .commandFailed)
        }
    }

    func testMaintenanceHistoryRoundTripsAndCapsRecords() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("maintenance.json")
        let evidence = MaintenanceDiagnosticPolicy.assess(
            action: .finder,
            processIDs: [101],
            readOnlyProbeSucceeded: true,
            checkedAt: Date(timeIntervalSince1970: 100)
        )
        var records: [MaintenanceRunRecord] = []
        for index in 0..<45 {
            let after = MaintenanceDiagnosticPolicy.assess(
                action: .finder,
                processIDs: [Int32(200 + index)],
                readOnlyProbeSucceeded: true,
                checkedAt: Date(timeIntervalSince1970: TimeInterval(200 + index))
            )
            let record = MaintenanceDiagnosticPolicy.verify(
                action: .finder,
                startedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                before: evidence,
                after: after,
                commandSucceeded: true,
                finishedAt: Date(timeIntervalSince1970: TimeInterval(300 + index))
            )
            records.append(record)
        }

        try MaintenanceHistoryPersistence.save(records, to: url)
        let loaded = try MaintenanceHistoryPersistence.load(from: url)
        XCTAssertEqual(loaded.count, MaintenanceHistoryPersistence.maximumRecords)
        XCTAssertEqual(loaded.first?.action, .finder)
        XCTAssertEqual(loaded.first?.outcome, .verifiedRecovered)
    }
}
