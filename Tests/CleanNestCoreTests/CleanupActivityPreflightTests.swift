import Foundation
import XCTest
@testable import CleanNestCore

final class CleanupActivityPreflightTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories.reversed() {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
    }

    func testInactiveCandidateCanMoveToTrash() async throws {
        let fixture = try makeCandidateFixture()
        let trash = fixture.home.appendingPathComponent(".Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let service = makeService(home: fixture.home) { .success([]) }

        let outcomes = await service.trashCleanupCandidates([fixture.candidate])

        let outcome = try XCTUnwrap(outcomes.only)
        XCTAssertTrue(outcome.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.target.path))
        let trashedURL = try XCTUnwrap(outcome.trashedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path))
        XCTAssertEqual(trashedURL.deletingLastPathComponent().standardizedFileURL, trash.standardizedFileURL)
    }

    func testOpenTargetFileIsRejectedWithoutMovingIt() async throws {
        let fixture = try makeCandidateFixture()
        let service = makeService(home: fixture.home) {
            .success([self.openFile(fixture.target, processID: 42, command: "CacheWriter")])
        }

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupCandidates([fixture.candidate]).only
        )

        XCTAssertEqual(outcome.failureKind, .activeFile)
        XCTAssertEqual(outcome.errorDescription?.contains("CacheWriter"), true)
        XCTAssertEqual(outcome.errorDescription?.contains("42"), true)
        XCTAssertEqual(outcome.errorDescription?.contains("未移动"), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.path))
    }

    func testOpenDescendantProtectsWholeCandidateDirectory() async throws {
        let fixture = try makeCandidateFixture(isDirectory: true)
        let descendant = fixture.target.appendingPathComponent("nested/live.cache")
        try writeFile(descendant)
        let service = makeService(home: fixture.home) {
            .success([self.openFile(descendant, processID: 73, command: "IndexBuilder")])
        }

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupCandidates([fixture.candidate]).only
        )

        XCTAssertEqual(outcome.failureKind, .activeFile)
        XCTAssertEqual(outcome.errorDescription?.contains(descendant.path), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: descendant.path))
    }

    func testSimilarPrefixAndSiblingPathsDoNotMatch() {
        let root = URL(fileURLWithPath: "/tmp/CleanNest-fixture/Cache", isDirectory: true)
        let records = [
            openFile(URL(fileURLWithPath: "/tmp/CleanNest-fixture/Cache-copy/live.cache")),
            openFile(URL(fileURLWithPath: "/tmp/CleanNest-fixture/Sibling/live.cache")),
            openFile(URL(fileURLWithPath: "/tmp/CleanNest-fixture/Cache-other"))
        ]

        XCTAssertNoThrow(
            try CleanupActivityPreflight.validate(target: root, snapshot: .success(records))
        )
        XCTAssertThrowsError(
            try CleanupActivityPreflight.validate(
                target: root,
                snapshot: .success([openFile(root.appendingPathComponent("live.cache"))])
            )
        ) { error in
            XCTAssertEqual(
                error as? CleanupActivityError,
                .activeFile(path: root.appendingPathComponent("live.cache").path, processName: "TestProcess", processID: 99)
            )
        }
    }

    func testUnavailableProbeFailsClosedWithoutMovingAnything() async throws {
        let fixture = try makeCandidateFixture()
        let service = makeService(home: fixture.home) {
            .failure("fixture: lsof exited 1")
        }

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupCandidates([fixture.candidate]).only
        )

        XCTAssertEqual(outcome.failureKind, .activityProbeUnavailable)
        XCTAssertEqual(outcome.errorDescription?.contains("无法确认"), true)
        XCTAssertEqual(outcome.errorDescription?.contains("未移动"), true)
        XCTAssertEqual(outcome.technicalDescription?.contains("fixture: lsof exited 1"), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.path))
    }

    func testFreshPerItemProbeRejectsActivityAppearingAfterBatchPreflight() async throws {
        let fixture = try makeCandidateFixture()
        let counter = ProbeCounter()
        let service = makeService(home: fixture.home) {
            let invocation = counter.next()
            if invocation == 1 { return .success([]) }
            return .success([self.openFile(fixture.target, processID: 88, command: "LateWriter")])
        }

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupCandidates([fixture.candidate]).only
        )

        XCTAssertEqual(counter.value, 2)
        XCTAssertEqual(outcome.failureKind, .activeFile)
        XCTAssertEqual(outcome.errorDescription?.contains("LateWriter"), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.path))
    }

    func testMixedBatchRejectsOnlyActiveItem() async throws {
        let active = try makeCandidateFixture()
        let inactiveURL = active.home.appendingPathComponent("Library/Caches/com.example.inactive/cache.dat")
        try writeFile(inactiveURL)
        let inactive = CleanupCandidate(
            name: inactiveURL.lastPathComponent,
            url: inactiveURL,
            kind: .appCache,
            allocatedBytes: 4,
            modifiedAt: nil,
            isRecommended: true,
            detail: "可丢弃测试文件"
        )
        let service = makeService(home: active.home) {
            .success([self.openFile(active.target, processID: 51, command: "ActiveOnly")])
        }

        let outcomes = await service.trashCleanupCandidates([active.candidate, inactive])

        XCTAssertEqual(outcomes.count, 2)
        let activeOutcome = try XCTUnwrap(outcomes.first { $0.source == active.target })
        let inactiveOutcome = try XCTUnwrap(outcomes.first { $0.source == inactiveURL })
        XCTAssertEqual(activeOutcome.failureKind, .activeFile)
        XCTAssertEqual(activeOutcome.errorDescription?.contains(active.target.path), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.target.path))
        XCTAssertTrue(inactiveOutcome.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inactiveURL.path))
        XCTAssertEqual(inactiveOutcome.trashedURL?.deletingLastPathComponent().lastPathComponent, ".Trash")
    }

    func testChangedPersonalFileIdentityKeepsExistingRejectionPriority() async throws {
        let fixture = try makeCandidateFixture(personalFile: true)
        var identity = try XCTUnwrap(fixture.candidate.fileIdentity)
        identity = CleanupFileIdentity(
            deviceID: identity.deviceID,
            fileID: identity.fileID &+ 1,
            logicalBytes: identity.logicalBytes,
            modifiedAt: identity.modifiedAt
        )
        let changed = CleanupCandidate(
            name: fixture.candidate.name,
            url: fixture.candidate.url,
            kind: fixture.candidate.kind,
            allocatedBytes: fixture.candidate.allocatedBytes,
            modifiedAt: fixture.candidate.modifiedAt,
            isRecommended: false,
            detail: fixture.candidate.detail,
            fileIdentity: identity
        )
        let counter = ProbeCounter()
        let service = makeService(home: fixture.home) {
            counter.next()
            return .success([])
        }

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupCandidates([changed]).only
        )

        XCTAssertEqual(outcome.failureKind, .targetChanged)
        XCTAssertEqual(counter.value, 0, "静态身份已经失效时不应再依赖活跃探测来决定结果")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.path))
    }

    func testCleanupTargetsAlsoUseActivityGate() async throws {
        let fixture = try makeCandidateFixture()
        let service = makeService(home: fixture.home) {
            .success([self.openFile(fixture.target)])
        }

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupTargets([fixture.target]).only
        )

        XCTAssertEqual(outcome.failureKind, .activeFile)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.path))
    }

    func testPermissionFailureIsSpecificAndLeavesSourceInPlace() async throws {
        let fixture = try makeCandidateFixture()
        let service = TrashService(
            policy: SafePathPolicy(homeDirectory: fixture.home),
            applicationRecycler: { _ in nil },
            dependencyRecycler: { _ in nil },
            cleanupActivityProbe: { .success([]) },
            cleanupRecycler: { _ in
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
            }
        )

        let outcome = try await XCTUnwrapAsync(
            await service.trashCleanupCandidates([fixture.candidate]).only
        )

        XCTAssertEqual(outcome.failureKind, .permissionDenied)
        XCTAssertEqual(outcome.errorDescription?.contains("未移动"), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.target.path))
    }

    private func makeService(
        home: URL,
        probe: @escaping @Sendable () async -> AgentWorkspaceOpenFileProbe.Result
    ) -> TrashService {
        TrashService(
            policy: SafePathPolicy(homeDirectory: home),
            applicationRecycler: { _ in nil },
            dependencyRecycler: { _ in nil },
            cleanupActivityProbe: probe,
            cleanupRecycler: { source in
                let trash = home.appendingPathComponent(".Trash", isDirectory: true)
                try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
                let destination = trash.appendingPathComponent(source.lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination)
                return destination
            }
        )
    }

    private func makeCandidateFixture(
        isDirectory: Bool = false,
        personalFile: Bool = false
    ) throws -> (home: URL, target: URL, candidate: CleanupCandidate) {
        let home = try makeTemporaryDirectory()
        let target = personalFile
            ? home.appendingPathComponent("Downloads/old-download.dat")
            : home.appendingPathComponent("Library/Caches/com.example.tests/cache.dat")
        if isDirectory {
            let directory = personalFile
                ? home.appendingPathComponent("Downloads/OldCache", isDirectory: true)
                : home.appendingPathComponent("Library/Caches/com.example.tests", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeFile(directory.appendingPathComponent("cache.dat"))
            let candidate = CleanupCandidate(
                name: directory.lastPathComponent,
                url: directory,
                kind: personalFile ? .archive : .appCache,
                allocatedBytes: 4,
                modifiedAt: nil,
                isRecommended: true,
                detail: "可丢弃测试目录"
            )
            return (home, directory, candidate)
        }

        try writeFile(target)
        let identity = personalFile ? try CleanupFileIdentity.capture(at: target) : nil
        let candidate = CleanupCandidate(
            name: target.lastPathComponent,
            url: target,
            kind: personalFile ? .archive : .appCache,
            allocatedBytes: 4,
            modifiedAt: nil,
            isRecommended: true,
            detail: "可丢弃测试文件",
            fileIdentity: identity
        )
        return (home, target, candidate)
    }

    private func openFile(
        _ url: URL,
        processID: Int32 = 99,
        command: String = "TestProcess"
    ) -> AgentWorkspaceOpenFile {
        AgentWorkspaceOpenFile(processID: processID, commandName: command, path: url.path)
    }

    private func writeFile(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("test".utf8).write(to: url)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestActivityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private final class ProbeCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var invocation = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return invocation
    }

    @discardableResult
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        invocation += 1
        return invocation
    }
}

private extension AgentWorkspaceOpenFileProbe.Result {
    static func success(_ records: [AgentWorkspaceOpenFile]) -> Self {
        self.init(records: records, succeeded: true, diagnostic: "fixture: complete open-file table")
    }

    static func failure(_ diagnostic: String) -> Self {
        self.init(records: [], succeeded: false, diagnostic: diagnostic)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}

private func XCTUnwrapAsync<T>(
    _ value: @autoclosure () async -> T?,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) async throws -> T {
    let unwrapped = await value()
    return try XCTUnwrap(unwrapped, message(), file: file, line: line)
}
