import XCTest
import CleanNestCore

final class PowerSourceProbeTests: XCTestCase {
    func testParsesPresentChargingBattery() {
        let result = PowerSourceProbe.interpret(
            output: "Now drawing from 'AC Power'\n -InternalBattery-0 (id=123)\t86%; charging; 0:24 remaining present: true"
        )
        XCTAssertEqual(result.availability, .present)
        XCTAssertEqual(result.level, 86)
        XCTAssertEqual(result.status, "正在充电")
    }

    func testDesktopWithoutBatteryIsNotReportedAsPermissionFailure() {
        let result = PowerSourceProbe.interpret(output: "Now drawing from 'AC Power'\n")
        XCTAssertEqual(result.availability, .noInternalBattery)
        XCTAssertNil(result.level)
        XCTAssertTrue(result.detail.contains("不需要授予文件访问权限"))
    }

    func testCommandFailureIsDistinctFromNoBattery() {
        let result = PowerSourceProbe.interpret(output: "", error: "unavailable", exitCode: 1)
        XCTAssertEqual(result.availability, .unreadable)
        XCTAssertNil(result.level)
        XCTAssertTrue(result.detail.contains("unavailable"))
    }
}
