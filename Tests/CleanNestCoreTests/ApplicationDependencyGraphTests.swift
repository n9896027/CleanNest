import Foundation
import Security
import XCTest
@testable import CleanNestCore

final class ApplicationDependencyGraphTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    func testGraphSeparatesOwnedManagedEmbeddedAndUnverifiedItems() async throws {
        let sandbox = try temporaryDirectory()
        let home = sandbox.appendingPathComponent("Home", isDirectory: true)
        let systemLibrary = sandbox.appendingPathComponent("SystemLibrary", isDirectory: true)
        let application = sandbox.appendingPathComponent("Fixture.app", isDirectory: true)
        try makeApplication(at: application, bundleIdentifier: "com.example.fixture")

        let cache = home.appendingPathComponent("Library/Caches/com.example.fixture", isDirectory: true)
        let container = home.appendingPathComponent("Library/Containers/com.example.fixture", isDirectory: true)
        let unverified = home.appendingPathComponent("Library/Application Support/Fixture Legacy", isDirectory: true)
        for directory in [cache, container, unverified] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 4_096).write(to: directory.appendingPathComponent("sample.bin"))
        }

        let loginItem = application.appendingPathComponent(
            "Contents/Library/LoginItems/FixtureAgent.app",
            isDirectory: true
        )
        let appExtension = application.appendingPathComponent(
            "Contents/PlugIns/FixtureShare.appex",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: loginItem, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appExtension, withIntermediateDirectories: true)

        let launchAgent = home.appendingPathComponent(
            "Library/LaunchAgents/com.example.fixture.agent.plist",
            isDirectory: false
        )
        try FileManager.default.createDirectory(
            at: launchAgent.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "com.example.fixture.agent",
                "ProgramArguments": [application.appendingPathComponent("Contents/MacOS/Fixture").path],
                "KeepAlive": true
            ],
            format: .xml,
            options: 0
        ).write(to: launchAgent)

        let installed = InstalledApplication(
            name: "Fixture",
            bundleIdentifier: "com.example.fixture",
            version: "1.0",
            url: application,
            allocatedBytes: FileTree.allocatedSize(of: application),
            modifiedAt: nil,
            fileIdentity: try ApplicationFileIdentity.capture(at: application)
        )
        let graph = await ApplicationDependencyGraphBuilder(
            homeDirectory: home,
            systemLibraryDirectory: systemLibrary
        ).build(
            for: installed,
            includeProtectedAppData: true,
            applicationIsRunning: false
        )

        XCTAssertTrue(graph.nodes.contains {
            $0.url == cache.standardizedFileURL
                && $0.ownership == .applicationOwned
                && $0.action == .removeAfterApplication
        })
        XCTAssertTrue(graph.nodes.contains {
            $0.url == container.standardizedFileURL
                && $0.ownership == .systemManaged
                && $0.action == .readOnly
                && $0.evidence.contains("退出状态：已确认未运行")
                && $0.evidence.contains("本报告只提供归属与状态证据，永不授权删除容器")
        })
        XCTAssertTrue(graph.nodes.contains {
            $0.url == loginItem.standardizedFileURL
                && $0.kind == .loginItem
                && $0.action == .includedInApplication
        })
        XCTAssertTrue(graph.nodes.contains {
            $0.url == appExtension.standardizedFileURL
                && $0.kind == .appExtension
                && $0.action == .includedInApplication
        })
        XCTAssertTrue(graph.nodes.contains {
            $0.url == launchAgent.standardizedFileURL
                && $0.kind == .userDaemon
                && $0.action == .readOnly
        })
        XCTAssertTrue(graph.nodes.contains {
            $0.url == unverified.standardizedFileURL
                && $0.ownership == .unverified
                && $0.action == .readOnly
        })
        XCTAssertEqual(graph.separatelyRemovableNodes.map(\.url), [cache.standardizedFileURL])
        XCTAssertFalse(graph.registration.scannedPathIsRegistered)
    }

    func testFiveAppOutcomesKeepDependenciesAtZeroUntilTrashIsConfirmed() throws {
        let sandbox = try temporaryDirectory()
        let related = sandbox.appendingPathComponent("related", isDirectory: true)
        try FileManager.default.createDirectory(at: related, withIntermediateDirectories: true)
        let node = ApplicationDependencyNode(
            name: "related",
            url: related,
            kind: .relatedFile,
            ownership: .applicationOwned,
            action: .removeAfterApplication,
            allocatedBytes: 0,
            evidence: ["test"],
            identity: try ApplicationDependencyIdentity.capture(at: related)
        )

        let failures: [TrashFailureKind] = [
            .authorizationCancelled,
            .authorizationDenied,
            .targetChanged,
            .automationDenied
        ]
        for failure in failures {
            let outcome = TrashOutcome(
                source: sandbox.appendingPathComponent("Fixture.app"),
                trashedURL: nil,
                errorDescription: "failed",
                failureKind: failure
            )
            XCTAssertTrue(
                ApplicationUninstallSafetyPolicy.approvedDependencies(
                    from: [node],
                    after: outcome
                ).isEmpty
            )
        }

        let confirmed = TrashOutcome(
            source: sandbox.appendingPathComponent("Fixture.app"),
            trashedURL: sandbox.appendingPathComponent(".Trash/Fixture.app"),
            errorDescription: nil
        )
        XCTAssertEqual(
            ApplicationUninstallSafetyPolicy.approvedDependencies(from: [node], after: confirmed).map(\.id),
            [node.id]
        )
    }

    func testAuthorizationAndFinderAutomationFailuresRemainDistinct() async throws {
        let fixture = try applicationFixture(name: "Auth.app")
        let identity = try ApplicationFileIdentity.capture(at: fixture.application)

        let denied = TrashService(policy: fixture.policy, applicationRecycler: { _ in
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAuthorizationDenied))
        })
        let deniedOutcome = await denied.trashApplication(
            fixture.application,
            expectedIdentity: identity,
            expectedBundleIdentifier: fixture.bundleIdentifier
        )
        XCTAssertEqual(deniedOutcome.failureKind, .authorizationDenied)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.application.path))

        let automation = TrashService(policy: fixture.policy, applicationRecycler: { _ in
            throw NSError(domain: NSOSStatusErrorDomain, code: -1743)
        })
        let automationOutcome = await automation.trashApplication(
            fixture.application,
            expectedIdentity: identity,
            expectedBundleIdentifier: fixture.bundleIdentifier
        )
        XCTAssertEqual(automationOutcome.failureKind, .automationDenied)
        XCTAssertTrue(automationOutcome.errorDescription?.contains("Finder") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.application.path))
    }

    func testDependencyTrashRevalidatesIdentityAndUsesOnlyTemporaryTrash() async throws {
        let sandbox = try temporaryDirectory()
        let home = sandbox.appendingPathComponent("Home", isDirectory: true)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let target = cacheRoot.appendingPathComponent("com.example.fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 1_024).write(to: target.appendingPathComponent("cache.bin"))
        let identity = try ApplicationDependencyIdentity.capture(at: target)
        let policy = SafePathPolicy(
            homeDirectory: home,
            systemApplicationsDirectory: sandbox.appendingPathComponent("Applications"),
            protectedApplicationURLs: []
        )
        let testTrash = sandbox.appendingPathComponent("TestTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: testTrash, withIntermediateDirectories: true)
        let service = TrashService(
            policy: policy,
            applicationRecycler: { _ in nil },
            dependencyRecycler: { source in
                let destination = testTrash.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination)
                return destination
            }
        )
        let node = ApplicationDependencyNode(
            name: target.lastPathComponent,
            url: target,
            kind: .relatedFile,
            ownership: .applicationOwned,
            action: .removeAfterApplication,
            allocatedBytes: FileTree.allocatedSize(of: target),
            evidence: ["test"],
            identity: identity
        )

        try FileManager.default.removeItem(at: target)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let changed = await service.trashApplicationDependencies([node])
        XCTAssertEqual(changed.first?.failureKind, .targetChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))

        let refreshed = ApplicationDependencyNode(
            name: target.lastPathComponent,
            url: target,
            kind: .relatedFile,
            ownership: .applicationOwned,
            action: .removeAfterApplication,
            allocatedBytes: 0,
            evidence: ["test"],
            identity: try ApplicationDependencyIdentity.capture(at: target)
        )
        let moved = await service.trashApplicationDependencies([refreshed])
        XCTAssertTrue(moved.first?.succeeded == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(moved.first?.trashedURL.map { FileManager.default.fileExists(atPath: $0.path) } == true)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestApplicationDependencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func applicationFixture(
        name: String,
        bundleIdentifier: String = "com.example.fixture"
    ) throws -> (
        application: URL,
        bundleIdentifier: String,
        policy: SafePathPolicy
    ) {
        let sandbox = try temporaryDirectory()
        let home = sandbox.appendingPathComponent("Home", isDirectory: true)
        let applications = sandbox.appendingPathComponent("Applications", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let application = applications.appendingPathComponent(name, isDirectory: true)
        try makeApplication(at: application, bundleIdentifier: bundleIdentifier)
        return (
            application,
            bundleIdentifier,
            SafePathPolicy(
                homeDirectory: home,
                systemApplicationsDirectory: applications,
                protectedApplicationURLs: []
            )
        )
    }

    private func makeApplication(at url: URL, bundleIdentifier: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0"
        ]
        try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ).write(to: contents.appendingPathComponent("Info.plist"))
    }
}
