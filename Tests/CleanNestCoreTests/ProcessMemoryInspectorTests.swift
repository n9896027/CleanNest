import Darwin
import XCTest
@testable import CleanNestCore

final class ProcessMemoryInspectorTests: XCTestCase {
    func testInspectorTerminatesOnlyTheExactChildIdentity() throws {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["30"]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.nullDevice
        child.standardError = FileHandle.nullDevice
        try child.run()
        defer {
            if child.isRunning {
                Darwin.kill(child.processIdentifier, SIGKILL)
                child.waitUntilExit()
            }
        }

        let inspector = ProcessMemoryInspector()
        let snapshot = try XCTUnwrap(inspector.process(pid: child.processIdentifier))
        XCTAssertNil(snapshot.protectionReason)
        let result = inspector.terminate(snapshot)
        if child.isRunning { child.terminate() }
        child.waitUntilExit()
        XCTAssertEqual(result, .terminated)
        XCTAssertFalse(child.isRunning)
    }
}
