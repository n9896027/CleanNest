import Foundation
import XCTest
@testable import CleanNestCore

final class ApplicationContainerReadOnlyInspectorTests: XCTestCase {
    func testExactPrivateContainerRecordsIdentitySignatureAndNotRunningWithoutGrantingMutation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let container = fixture.home.appendingPathComponent("Library/Containers/com.example.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let report = ApplicationContainerReadOnlyInspector(homeDirectory: fixture.home).inspect(
            container: container,
            expectedBundleIdentifier: "com.example.fixture",
            declaredApplicationGroups: [],
            signatureMatchesApplication: true,
            applicationIsRunning: false
        )

        XCTAssertEqual(report.ownership, .systemManaged)
        XCTAssertTrue(report.bundleIdentifierMatched)
        XCTAssertTrue(report.signatureMatched)
        XCTAssertTrue(report.identityVerified)
        XCTAssertEqual(report.activityStatus, .notRunning)
        XCTAssertTrue(report.isReadOnly)
        XCTAssertTrue(report.evidence.contains("退出状态：已确认未运行"))
        XCTAssertTrue(report.evidence.contains("本报告只提供归属与状态证据，永不授权删除容器"))
    }

    func testRunningOrUnknownExitStateAlwaysStaysReadOnly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let container = fixture.home.appendingPathComponent("Library/Containers/com.example.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        let inspector = ApplicationContainerReadOnlyInspector(homeDirectory: fixture.home)

        for (running, status) in [(true, ApplicationContainerActivityStatus.running), (nil, .unknown)] {
            let report = inspector.inspect(
                container: container,
                expectedBundleIdentifier: "com.example.fixture",
                declaredApplicationGroups: [],
                signatureMatchesApplication: false,
                applicationIsRunning: running
            )
            XCTAssertEqual(report.activityStatus, status)
            XCTAssertTrue(report.isReadOnly)
            XCTAssertFalse(report.signatureMatched)
        }
    }

    func testDeclaredGroupContainerRemainsSharedEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let container = fixture.home.appendingPathComponent("Library/Group Containers/TEAM.com.example.shared", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)

        let report = ApplicationContainerReadOnlyInspector(homeDirectory: fixture.home).inspect(
            container: container,
            expectedBundleIdentifier: "com.example.fixture",
            declaredApplicationGroups: ["TEAM.com.example.shared"],
            signatureMatchesApplication: true,
            applicationIsRunning: false
        )

        XCTAssertEqual(report.ownership, .sharedGroup)
        XCTAssertFalse(report.bundleIdentifierMatched)
        XCTAssertTrue(report.signatureMatched)
        XCTAssertTrue(report.isReadOnly)
    }

    func testMismatchedLocationAndSymbolicLinkFailClosed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let outside = fixture.root.appendingPathComponent("Outside/com.example.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let inspector = ApplicationContainerReadOnlyInspector(homeDirectory: fixture.home)
        let outsideReport = inspector.inspect(
            container: outside,
            expectedBundleIdentifier: "com.example.fixture",
            declaredApplicationGroups: [],
            signatureMatchesApplication: false,
            applicationIsRunning: nil
        )
        XCTAssertEqual(outsideReport.ownership, .unverified)
        XCTAssertFalse(outsideReport.bundleIdentifierMatched)
        XCTAssertTrue(outsideReport.isReadOnly)

        let link = fixture.home.appendingPathComponent("Library/Containers/com.example.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let linkReport = inspector.inspect(
            container: link,
            expectedBundleIdentifier: "com.example.fixture",
            declaredApplicationGroups: [],
            signatureMatchesApplication: true,
            applicationIsRunning: false
        )
        XCTAssertFalse(linkReport.identityVerified)
        XCTAssertTrue(linkReport.isReadOnly)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    private struct Fixture {
        let root: URL
        let home: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("CleanNestContainerTests-\(UUID().uuidString)", isDirectory: true)
            home = root.appendingPathComponent("Home", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
