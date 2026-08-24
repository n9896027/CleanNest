import Darwin
import Foundation
import XCTest
import CleanNestCore
import CleanNestMutation

final class CleanNestCoreTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories.reversed() {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testEngineLocatorPrefersExecutableCustomPath() throws {
        let directory = try makeTemporaryDirectory()
        let executable = directory.appendingPathComponent("mole")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o755)],
            ofItemAtPath: executable.path
        )

        XCTAssertEqual(EngineLocator.locate(customPath: executable.path), executable.standardizedFileURL)
        XCTAssertEqual(EngineLocator.candidates(customPath: executable.path).first, executable.standardizedFileURL)
    }

    func testSystemSnapshotDecodesModernStatusAndBatteryFacts() throws {
        let json = #"""
        {
          "host": "Test Mac",
          "health_score": 91,
          "cpu": {"usage": 12.5, "logical_cpu": 10},
          "memory": {"used": 800, "total": 1000, "used_percent": 80, "pressure": "normal"},
          "battery": {"level": 78, "status": "charging", "health": "normal", "capacity": 94, "cycle_count": 42},
          "thermal": {"cpu": 51.5},
          "disk": {"used_percent": 64, "free": 4096},
          "procs": 321
        }
        """#

        let snapshot = try MoleJSONDecoder.systemSnapshot(from: Data(json.utf8))

        XCTAssertEqual(snapshot.host, "Test Mac")
        XCTAssertEqual(snapshot.healthScore, 91)
        XCTAssertEqual(snapshot.memoryUsedPercent, 80)
        XCTAssertEqual(snapshot.batteryLevel, 78)
        XCTAssertEqual(snapshot.batteryStatus, "正在充电 · 健康良好 · 最大容量 94% · 42 次循环")
        XCTAssertEqual(snapshot.temperatureCelsius, 51.5)
        XCTAssertEqual(snapshot.temperatureSource, "CPU 温度")
    }

    func testPrivacyAssessmentIdentifiesOnlyIntersectingSensitiveAreas() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let protectedRoot = home.appendingPathComponent("Library/Containers/com.example.App", isDirectory: true)
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)

        XCTAssertEqual(
            DiskPrivacyPolicy.assessTraversal(root: protectedRoot, homeDirectory: home).sensitiveAreas,
            [.containers]
        )
        XCTAssertFalse(
            DiskPrivacyPolicy.assessTraversal(root: cacheRoot, homeDirectory: home).mayRequireFullDiskAccess
        )
    }

    func testFullDiskAccessProbeClassifiesOnlyActualPermissionErrorsAsDenied() {
        XCTAssertEqual(FullDiskAccessProbeResult.classify(errno: 0), .accessible)
        XCTAssertEqual(FullDiskAccessProbeResult.classify(errno: EACCES), .permissionDenied)
        XCTAssertEqual(FullDiskAccessProbeResult.classify(errno: EPERM), .permissionDenied)
        XCTAssertEqual(FullDiskAccessProbeResult.classify(errno: ENOENT), .indeterminate)
    }

    func testDiskSafetyPolicyProtectsUserAndSandboxData() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

        let containers = DiskAISafetyPolicy.policy(
            for: home.appendingPathComponent("Library/Containers/com.example.App"),
            homeDirectory: home
        )
        XCTAssertEqual(containers.category, .appSandboxData)
        XCTAssertEqual(containers.boundary, .protected)
        XCTAssertEqual(containers.minimumRisk, .high)

        let cache = DiskAISafetyPolicy.policy(
            for: home.appendingPathComponent("Library/Caches/com.example.App"),
            homeDirectory: home
        )
        XCTAssertEqual(cache.category, .cache)
        XCTAssertEqual(cache.boundary, .reviewable)
        XCTAssertEqual(cache.minimumRisk, .low)
    }

    func testDiskAISnapshotRedactsHomeAndExcludesOutOfScopeEntries() throws {
        let home = URL(fileURLWithPath: "/Users/private-owner", isDirectory: true)
        let root = home.appendingPathComponent("Library", isDirectory: true)
        let cache = DiskEntry(
            name: "Caches",
            url: root.appendingPathComponent("Caches", isDirectory: true),
            bytes: 1_024,
            isDirectory: true
        )
        let outside = DiskEntry(
            name: "outside",
            url: URL(fileURLWithPath: "/tmp/outside", isDirectory: true),
            bytes: 8_192,
            isDirectory: true
        )
        let report = DiskReport(
            root: root,
            entries: [outside, cache],
            largeFiles: [],
            totalBytes: 9_216,
            totalFiles: 2
        )

        let snapshot = try DiskAIRequestBuilder.makeSnapshot(report: report, homeDirectory: home)

        XCTAssertEqual(snapshot.requestedCount, 1)
        XCTAssertEqual(snapshot.tokenToEntryID["d0001"], cache.id)
        XCTAssertFalse(snapshot.payloadJSON.contains(home.path))
        XCTAssertFalse(snapshot.payloadJSON.contains("/tmp/outside"))
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(snapshot.payloadJSON.utf8)) as? [String: Any]
        )
        let scope = try XCTUnwrap(payload["scope"] as? [String: Any])
        XCTAssertEqual(scope["root_hint"] as? String, "~/Library")
    }

    func testDiskAIValidatorReconcilesUnsafeModelAdviceWithLocalPolicy() throws {
        let snapshot = DiskAIRequestSnapshot(
            payloadJSON: "{}",
            tokenToEntryID: ["d0001": "/Users/tester/Library/Containers/com.example.App"],
            tokenPolicies: [
                "d0001": DiskAIInputPolicy(
                    category: .appSandboxData,
                    boundary: .protected,
                    minimumRisk: .high
                )
            ],
            sourceRootID: "/Users/tester/Library",
            requestedCount: 1,
            requestedBytes: 2_048,
            deepSampledCount: 0
        )
        let response = #"""
        {"schema_version":1,"summary":"目录分析完成。","items":[{"token":"d0001","category":"cache","confidence":"high","verdict":"likely_reclaimable","risk":"low","priority":1,"suggestion":"review_for_cleanup","explanation":"应用运行数据。"}],"cautions":[]}
        """#

        let analysis = try DiskAIResponseValidator.validate(
            content: response,
            snapshot: snapshot,
            modelID: "local-model"
        )
        let advice = try XCTUnwrap(analysis.advice.first)

        XCTAssertEqual(advice.category, .appSandboxData)
        XCTAssertEqual(advice.confidence, .low)
        XCTAssertEqual(advice.verdict, .keep)
        XCTAssertEqual(advice.risk, .high)
        XCTAssertEqual(advice.suggestion, .keep)
        XCTAssertTrue(analysis.cautions.contains { $0.contains("本机安全规则") })
    }

    func testCleanupAISnapshotRedactsHomeAndValidatorRejectsUnknownTargets() throws {
        let home = URL(fileURLWithPath: "/Users/private-owner", isDirectory: true)
        let candidate = CleanupCandidate(
            name: "DerivedData",
            url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Demo"),
            kind: .developer,
            allocatedBytes: 4_096,
            modifiedAt: nil,
            isRecommended: true,
            detail: "可重新生成"
        )
        let snapshot = try CleanupAIRequestBuilder.makeSnapshot(
            candidates: [candidate],
            diskTotalBytes: 10_000,
            diskFreeBytes: 2_000,
            homeDirectory: home
        )

        XCTAssertFalse(snapshot.payloadJSON.contains(home.path))
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(snapshot.payloadJSON.utf8)) as? [String: Any]
        )
        let payloadCandidates = try XCTUnwrap(payload["candidates"] as? [[String: Any]])
        XCTAssertEqual(
            payloadCandidates.first?["path_hint"] as? String,
            "~/Library/Developer/Xcode/DerivedData/Demo"
        )

        let response = #"""
        {"schema_version":1,"summary":"测试","items":[{"token":"c9999","verdict":"keep","risk":"high","priority":3,"reason":"测试","path":"/tmp/new-target"}],"cautions":[]}
        """#
        XCTAssertThrowsError(
            try CleanupAIResponseValidator.validate(
                content: response,
                snapshot: snapshot,
                modelID: "local-model"
            )
        ) { error in
            guard case LocalAIError.invalidResponse = error else {
                return XCTFail("Expected LocalAIError.invalidResponse, got \(error)")
            }
        }
    }

    func testSafePathPolicyAcceptsOnlyStrictNonSymlinkDescendants() throws {
        let home = try makeTemporaryDirectory()
        let cacheRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let allowed = cacheRoot.appendingPathComponent("com.example.Cache", isDirectory: true)
        let outside = home.appendingPathComponent("Documents/important", isDirectory: true)
        let linked = cacheRoot.appendingPathComponent("linked-cache")
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: allowed)

        let policy = SafePathPolicy(homeDirectory: home)
        XCTAssertNoThrow(try policy.validateCleanupTarget(allowed))
        assertThrows(.outsideAllowedRoots) { try policy.validateCleanupTarget(cacheRoot) }
        assertThrows(.outsideAllowedRoots) { try policy.validateCleanupTarget(outside) }
        assertThrows(.symbolicLink) { try policy.validateCleanupTarget(linked) }
    }

    func testApplicationPolicyAcceptsOnlyDirectNonSymlinkAppsAndProtectsCurrentApp() throws {
        let sandbox = try makeTemporaryDirectory()
        let home = sandbox.appendingPathComponent("Home", isDirectory: true)
        let systemApplications = sandbox.appendingPathComponent("SystemApplications", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemApplications, withIntermediateDirectories: true)

        let directApp = systemApplications.appendingPathComponent("Direct.app", isDirectory: true)
        let nestedApp = systemApplications
            .appendingPathComponent("Folder", isDirectory: true)
            .appendingPathComponent("Nested.app", isDirectory: true)
        let linkedApp = systemApplications.appendingPathComponent("Linked.app", isDirectory: true)
        try makeApplication(at: directApp, bundleIdentifier: "com.example.direct")
        try makeApplication(at: nestedApp, bundleIdentifier: "com.example.nested")
        try FileManager.default.createSymbolicLink(at: linkedApp, withDestinationURL: directApp)

        let policy = SafePathPolicy(
            homeDirectory: home,
            systemApplicationsDirectory: systemApplications,
            protectedApplicationURLs: []
        )
        XCTAssertNoThrow(try policy.validateApplicationTarget(directApp))
        assertThrows(.invalidApplication) { try policy.validateApplicationTarget(nestedApp) }
        assertThrows(.symbolicLink) { try policy.validateApplicationTarget(linkedApp) }

        let protectedPolicy = SafePathPolicy(
            homeDirectory: home,
            systemApplicationsDirectory: systemApplications,
            protectedApplicationURLs: [directApp]
        )
        assertThrows(.currentApplication) { try protectedPolicy.validateApplicationTarget(directApp) }
    }

    func testApplicationRemovalRequirementDetectsDifferentOwnerInSystemApplications() throws {
        let fixture = try makeApplicationFixture()
        let identity = try ApplicationFileIdentity.capture(at: fixture.application)
        let service = TrashService(
            policy: fixture.policy,
            applicationRecycler: { _ in nil },
            applicationMovePermissionProbe: { _, _ in false }
        )

        XCTAssertEqual(
            try service.applicationRemovalRequirement(
                for: fixture.application,
                currentUserID: identity.ownerUserID
            ),
            .standard
        )
        XCTAssertEqual(
            try service.applicationRemovalRequirement(
                for: fixture.application,
                currentUserID: identity.ownerUserID &+ 1
            ),
            .administratorAuthentication
        )

        let directlyWritableService = TrashService(
            policy: fixture.policy,
            applicationRecycler: { _ in nil },
            applicationMovePermissionProbe: { _, _ in true }
        )
        XCTAssertEqual(
            try directlyWritableService.applicationRemovalRequirement(
                for: fixture.application,
                currentUserID: identity.ownerUserID &+ 1
            ),
            .standard
        )

        let changedIdentity = ApplicationFileIdentity(
            deviceID: identity.deviceID,
            fileID: identity.fileID &+ 1,
            ownerUserID: identity.ownerUserID
        )
        assertThrows(.applicationChanged) {
            _ = try service.applicationRemovalRequirement(
                for: fixture.application,
                expectedIdentity: changedIdentity
            )
        }
        assertThrows(.applicationChanged) {
            _ = try service.applicationRemovalRequirement(
                for: fixture.application,
                expectedIdentity: identity,
                expectedBundleIdentifier: "com.example.replaced"
            )
        }
    }

    func testApplicationTrashUsesValidatedIdentityAndConfirmsSourceMoved() async throws {
        let fixture = try makeApplicationFixture()
        let identity = try ApplicationFileIdentity.capture(at: fixture.application)
        let trashDirectory = fixture.policy.homeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let destination = trashDirectory.appendingPathComponent(fixture.application.lastPathComponent)
        let service = TrashService(policy: fixture.policy, applicationRecycler: { request in
            try FileManager.default.moveItem(at: request.source, to: destination)
            return destination
        })

        let outcome = await service.trashApplication(
            fixture.application,
            expectedIdentity: identity,
            expectedBundleIdentifier: fixture.bundleIdentifier
        )

        XCTAssertTrue(outcome.succeeded)
        XCTAssertEqual(outcome.trashedURL?.standardizedFileURL, destination.standardizedFileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.application.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testApplicationTrashRejectsPathReplacementBeforeRecyclerRuns() async throws {
        let fixture = try makeApplicationFixture()
        let scannedIdentity = try ApplicationFileIdentity.capture(at: fixture.application)
        let original = fixture.sandbox.appendingPathComponent("Original.app", isDirectory: true)
        try FileManager.default.moveItem(at: fixture.application, to: original)
        try makeApplication(at: fixture.application, bundleIdentifier: fixture.bundleIdentifier)
        XCTAssertNotEqual(try ApplicationFileIdentity.capture(at: fixture.application), scannedIdentity)

        let service = TrashService(policy: fixture.policy, applicationRecycler: { _ in
            throw NSError(domain: "UnexpectedRecyclerInvocation", code: 1)
        })
        let outcome = await service.trashApplication(
            fixture.application,
            expectedIdentity: scannedIdentity,
            expectedBundleIdentifier: fixture.bundleIdentifier
        )

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failureKind, .targetChanged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.application.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testApplicationTrashClassifiesNativeAuthorizationCancellation() async throws {
        let fixture = try makeApplicationFixture()
        let service = TrashService(policy: fixture.policy, applicationRecycler: { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        })

        let outcome = await service.trashApplication(
            fixture.application,
            expectedIdentity: try ApplicationFileIdentity.capture(at: fixture.application),
            expectedBundleIdentifier: fixture.bundleIdentifier
        )

        XCTAssertEqual(outcome.failureKind, .authorizationCancelled)
        XCTAssertTrue(outcome.errorDescription?.contains("已取消") == true)
        XCTAssertTrue(outcome.technicalDescription?.contains(NSCocoaErrorDomain) == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.application.path))
    }

    func testApplicationTrashClassifiesPermissionFailureAndFalseSuccess() async throws {
        let permissionFixture = try makeApplicationFixture(name: "Permission.app")
        let permissionService = TrashService(policy: permissionFixture.policy, applicationRecycler: { _ in
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        })
        let permissionOutcome = await permissionService.trashApplication(
            permissionFixture.application,
            expectedIdentity: try ApplicationFileIdentity.capture(at: permissionFixture.application),
            expectedBundleIdentifier: permissionFixture.bundleIdentifier
        )
        XCTAssertEqual(permissionOutcome.failureKind, .permissionDenied)
        XCTAssertTrue(permissionOutcome.technicalDescription?.contains("\(EACCES)") == true)

        let falseSuccessFixture = try makeApplicationFixture(name: "FalseSuccess.app")
        let falseSuccessService = TrashService(policy: falseSuccessFixture.policy, applicationRecycler: { _ in
            falseSuccessFixture.sandbox.appendingPathComponent("NotActuallyTrash.app")
        })
        let falseSuccessOutcome = await falseSuccessService.trashApplication(
            falseSuccessFixture.application,
            expectedIdentity: try ApplicationFileIdentity.capture(at: falseSuccessFixture.application),
            expectedBundleIdentifier: falseSuccessFixture.bundleIdentifier
        )
        XCTAssertEqual(falseSuccessOutcome.failureKind, .missingResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: falseSuccessFixture.application.path))
    }

    func testApplicationTrashRejectsDestinationOutsideCurrentUsersTrash() async throws {
        let fixture = try makeApplicationFixture(name: "WrongDestination.app")
        let identity = try ApplicationFileIdentity.capture(at: fixture.application)
        let outsideTrash = fixture.sandbox.appendingPathComponent("OutsideTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideTrash, withIntermediateDirectories: true)
        let destination = outsideTrash.appendingPathComponent(fixture.application.lastPathComponent)
        let service = TrashService(policy: fixture.policy, applicationRecycler: { request in
            try FileManager.default.moveItem(at: request.source, to: destination)
            return destination
        })

        let outcome = await service.trashApplication(
            fixture.application,
            expectedIdentity: identity,
            expectedBundleIdentifier: fixture.bundleIdentifier
        )

        XCTAssertFalse(outcome.succeeded)
        XCTAssertEqual(outcome.failureKind, .missingResult)
        XCTAssertTrue(outcome.errorDescription?.contains("已离开原位置") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.application.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testAtomicApplicationTrashMoverMovesExactBundleAndAvoidsCollisions() throws {
        let fixture = try makeApplicationFixture(name: "Atomic.app")
        let trashDirectory = fixture.sandbox.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let collision = trashDirectory.appendingPathComponent("Atomic.app", isDirectory: true)
        try makeApplication(at: collision, bundleIdentifier: "com.example.collision")
        let identity = try ApplicationFileIdentity.capture(at: fixture.application)

        let destination = try AtomicApplicationTrashMover.move(
            ApplicationTrashRequest(
                source: fixture.application,
                expectedIdentity: identity,
                expectedBundleIdentifier: fixture.bundleIdentifier,
                trashDirectory: trashDirectory
            )
        )

        XCTAssertEqual(destination.lastPathComponent, "Atomic 2.app")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.application.path))
        XCTAssertEqual(try ApplicationFileIdentity.capture(at: destination), identity)
        XCTAssertEqual(
            AtomicApplicationTrashMover.findMovedItem(
                in: trashDirectory,
                matching: identity
            )?.resolvingSymlinksInPath(),
            destination.resolvingSymlinksInPath()
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: collision.path))
    }

    func testAtomicApplicationTrashMoverRejectsChangedIdentity() throws {
        let fixture = try makeApplicationFixture(name: "Changed.app")
        let trashDirectory = fixture.sandbox.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        let identity = try ApplicationFileIdentity.capture(at: fixture.application)
        let changed = ApplicationFileIdentity(
            deviceID: identity.deviceID,
            fileID: identity.fileID &+ 1,
            ownerUserID: identity.ownerUserID
        )

        XCTAssertThrowsError(
            try AtomicApplicationTrashMover.move(
                ApplicationTrashRequest(
                    source: fixture.application,
                    expectedIdentity: changed,
                    expectedBundleIdentifier: fixture.bundleIdentifier,
                    trashDirectory: trashDirectory
                )
            )
        ) { error in
            XCTAssertEqual(error as? SafePathError, .applicationChanged)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.application.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func makeApplicationFixture(
        name: String = "Fixture.app",
        bundleIdentifier: String = "com.example.fixture"
    ) throws -> (
        sandbox: URL,
        application: URL,
        bundleIdentifier: String,
        policy: SafePathPolicy
    ) {
        let sandbox = try makeTemporaryDirectory()
        let home = sandbox.appendingPathComponent("Home", isDirectory: true)
        let systemApplications = sandbox.appendingPathComponent("SystemApplications", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: systemApplications, withIntermediateDirectories: true)
        let application = systemApplications.appendingPathComponent(name, isDirectory: true)
        try makeApplication(at: application, bundleIdentifier: bundleIdentifier)
        let policy = SafePathPolicy(
            homeDirectory: home,
            systemApplicationsDirectory: systemApplications,
            protectedApplicationURLs: []
        )
        return (sandbox, application, bundleIdentifier, policy)
    }

    private func makeApplication(at url: URL, bundleIdentifier: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": url.deletingPathExtension().lastPathComponent,
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }

    private func assertThrows(
        _ expected: SafePathError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () throws -> Void
    ) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertEqual(error as? SafePathError, expected, file: file, line: line)
        }
    }
}
