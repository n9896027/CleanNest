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
}
