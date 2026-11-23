import Darwin
import Foundation

public struct CleanupExecutionIdentity: Codable, Equatable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let fileType: UInt32
    public let logicalBytes: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64

    public init(
        deviceID: UInt64,
        fileID: UInt64,
        fileType: UInt32,
        logicalBytes: Int64,
        modificationSeconds: Int64,
        modificationNanoseconds: Int64
    ) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.fileType = fileType
        self.logicalBytes = max(0, logicalBytes)
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
    }

    public static func capture(at url: URL) throws -> CleanupExecutionIdentity {
        var information = stat()
        guard url.path.withCString({ lstat($0, &information) }) == 0 else {
            throw CocoaError(.fileReadUnknown)
        }
        let type = information.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFDIR else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        return CleanupExecutionIdentity(
            deviceID: UInt64(information.st_dev),
            fileID: UInt64(information.st_ino),
            fileType: UInt32(type),
            logicalBytes: max(0, Int64(information.st_size)),
            modificationSeconds: Int64(information.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(information.st_mtimespec.tv_nsec)
        )
    }
}

public enum CleanupExecutionItemStatus: String, Codable, Equatable, Sendable {
    case pending
    case movedToTrash
    case failed
    case indeterminate
    case restored
    case restoreFailed
}

public struct CleanupExecutionItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let candidateID: String
    public let name: String
    public let sourceURL: URL
    public let candidateAllocatedBytes: Int64
    public let candidateFileIdentity: CleanupFileIdentity?
    public let sourceIdentity: CleanupExecutionIdentity?
    public private(set) var status: CleanupExecutionItemStatus
    public private(set) var trashURL: URL?
    public private(set) var trashIdentity: CleanupExecutionIdentity?
    public private(set) var errorDescription: String?
    public private(set) var technicalDescription: String?
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public private(set) var restoredAt: Date?

    public init(
        id: String = UUID().uuidString,
        candidate: CleanupCandidate,
        status: CleanupExecutionItemStatus = .pending,
        now: Date = Date()
    ) {
        self.id = id
        candidateID = candidate.id
        name = candidate.name
        sourceURL = candidate.url.standardizedFileURL
        candidateAllocatedBytes = max(0, candidate.allocatedBytes)
        candidateFileIdentity = candidate.fileIdentity
        sourceIdentity = try? CleanupExecutionIdentity.capture(at: candidate.url)
        self.status = status
        trashURL = nil
        trashIdentity = nil
        errorDescription = nil
        technicalDescription = nil
        createdAt = now
        updatedAt = now
        restoredAt = nil
    }

    fileprivate mutating func apply(_ outcome: TrashOutcome, trashDirectory: URL, now: Date) {
        updatedAt = now
        restoredAt = nil
        guard outcome.succeeded else {
            status = .failed
            trashURL = nil
            trashIdentity = nil
            errorDescription = outcome.errorDescription ?? "移动失败，原项目未处理。"
            technicalDescription = outcome.technicalDescription
            return
        }
        guard let destination = outcome.trashedURL?.standardizedFileURL,
              !FileManager.default.fileExists(atPath: sourceURL.path),
              Self.isDirectChild(destination, of: trashDirectory),
              FileManager.default.fileExists(atPath: destination.path),
              let identity = try? CleanupExecutionIdentity.capture(at: destination),
              sourceIdentity == nil || sourceIdentity == identity else {
            status = .indeterminate
            trashURL = outcome.trashedURL?.standardizedFileURL
            trashIdentity = nil
            errorDescription = "系统返回成功，但源路径、废纸篓位置或文件身份未能完整确认；不会生成可恢复成功记录。"
            technicalDescription = outcome.technicalDescription
            return
        }
        status = .movedToTrash
        trashURL = destination
        trashIdentity = identity
        errorDescription = nil
        technicalDescription = outcome.technicalDescription
    }

    fileprivate mutating func applyRestoreResult(
        status: CleanupExecutionItemStatus,
        error: String?,
        now: Date
    ) {
        self.status = status
        updatedAt = now
        restoredAt = status == .restored ? now : restoredAt
        errorDescription = error
        if status == .restored {
            trashIdentity = nil
            technicalDescription = nil
        }
    }

    private static func isDirectChild(_ url: URL, of directory: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            == directory.resolvingSymlinksInPath().standardizedFileURL
    }
}

public struct CleanupExecutionRecord: Codable, Equatable, Identifiable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let id: String
    public let startedAt: Date
    public private(set) var completedAt: Date?
    public private(set) var items: [CleanupExecutionItem]
    public let freeBytesBefore: Int64
    public private(set) var freeBytesAfter: Int64?
    public private(set) var immediateAPFSFreeBytesDelta: Int64?
    public private(set) var finalAPFSFreeBytesDelta: Int64?
    public private(set) var finalAPFSObservedAt: Date?

    public init(
        id: String = UUID().uuidString,
        candidates: [CleanupCandidate],
        freeBytesBefore: Int64,
        now: Date = Date()
    ) {
        schemaVersion = Self.schemaVersion
        self.id = id
        startedAt = now
        completedAt = nil
        items = candidates.map { CleanupExecutionItem(candidate: $0, now: now) }
        self.freeBytesBefore = freeBytesBefore
        freeBytesAfter = nil
        immediateAPFSFreeBytesDelta = nil
        finalAPFSFreeBytesDelta = nil
        finalAPFSObservedAt = nil
    }

    public var candidateBytes: Int64 {
        items.reduce(0) { Self.saturatingAdd($0, $1.candidateAllocatedBytes) }
    }

    public var movedBytes: Int64 {
        items.filter { $0.status == .movedToTrash || $0.status == .restored || $0.status == .restoreFailed }
            .reduce(0) { Self.saturatingAdd($0, $1.candidateAllocatedBytes) }
    }

    public var isComplete: Bool { completedAt != nil && !items.contains { $0.status == .pending } }

    public func applying(
        outcomes: [TrashOutcome],
        trashDirectory: URL,
        freeBytesAfter: Int64?,
        now: Date = Date()
    ) -> CleanupExecutionRecord {
        var copy = self
        let outcomesBySource = Dictionary(
            outcomes.map { ($0.source.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for index in copy.items.indices {
            let source = copy.items[index].sourceURL.path
            if let outcome = outcomesBySource[source] {
                copy.items[index].apply(outcome, trashDirectory: trashDirectory, now: now)
            } else {
                copy.items[index].applyRestoreResult(
                    status: .indeterminate,
                    error: "执行没有返回该项目的确定结果；请核对原路径和废纸篓。",
                    now: now
                )
            }
        }
        copy.completedAt = now
        copy.freeBytesAfter = freeBytesAfter
        if let freeBytesAfter {
            copy.immediateAPFSFreeBytesDelta = Self.signedDelta(
                after: freeBytesAfter,
                before: freeBytesBefore
            )
        } else {
            copy.immediateAPFSFreeBytesDelta = nil
        }
        // Moving to Trash is not proof that APFS space was finally reclaimed.
        copy.finalAPFSFreeBytesDelta = nil
        copy.finalAPFSObservedAt = nil
        return copy
    }

    public func confirmingFinalObservation(
        currentFreeBytes: Int64,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) -> CleanupExecutionRecord {
        var copy = self
        let trashItems = items.filter {
            $0.status == .movedToTrash || $0.status == .restoreFailed
        }
        guard trashItems.allSatisfy({ item in
            guard let url = item.trashURL else { return false }
            return !fileManager.fileExists(atPath: url.path)
        }) else {
            copy.finalAPFSFreeBytesDelta = nil
            copy.finalAPFSObservedAt = nil
            return copy
        }
        copy.finalAPFSFreeBytesDelta = Self.signedDelta(
            after: currentFreeBytes,
            before: freeBytesBefore
        )
        copy.finalAPFSObservedAt = now
        return copy
    }

    public func updatingItem(_ item: CleanupExecutionItem) -> CleanupExecutionRecord {
        var copy = self
        guard let index = copy.items.firstIndex(where: { $0.id == item.id }) else { return copy }
        copy.items[index] = item
        copy.finalAPFSFreeBytesDelta = nil
        copy.finalAPFSObservedAt = nil
        return copy
    }

    private static func signedDelta(after: Int64, before: Int64) -> Int64 {
        after >= before ? after - before : -(before - after)
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}

public struct CleanupExecutionLedgerSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public var records: [CleanupExecutionRecord]

    public init(schemaVersion: Int = Self.schemaVersion, records: [CleanupExecutionRecord] = []) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public mutating func insert(_ record: CleanupExecutionRecord) {
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        records = Array(records.prefix(100))
    }

    public mutating func update(_ record: CleanupExecutionRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else {
            insert(record)
            return
        }
        records[index] = record
    }
}

public struct CleanupExecutionLedgerLoadResult: Equatable, Sendable {
    public let snapshot: CleanupExecutionLedgerSnapshot
    public let diagnostic: String?

    public init(snapshot: CleanupExecutionLedgerSnapshot, diagnostic: String?) {
        self.snapshot = snapshot
        self.diagnostic = diagnostic
    }
}

public enum CleanupExecutionLedgerPersistence {
    public static func load(from url: URL) throws -> CleanupExecutionLedgerLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return CleanupExecutionLedgerLoadResult(snapshot: .init(), diagnostic: nil)
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            let snapshot = try JSONDecoder().decode(CleanupExecutionLedgerSnapshot.self, from: data)
            guard snapshot.schemaVersion == CleanupExecutionLedgerSnapshot.schemaVersion else {
                return CleanupExecutionLedgerLoadResult(
                    snapshot: .init(),
                    diagnostic: "执行账本版本不受支持；旧记录不会被用于恢复。"
                )
            }
            return CleanupExecutionLedgerLoadResult(snapshot: snapshot, diagnostic: nil)
        } catch {
            return CleanupExecutionLedgerLoadResult(
                snapshot: .init(),
                diagnostic: "执行账本已损坏或无法解码；为避免错误恢复，本次不加载其中记录。\(error.localizedDescription)"
            )
        }
    }

    public static func save(_ snapshot: CleanupExecutionLedgerSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}

public enum CleanupRestoreError: LocalizedError, Equatable, Sendable {
    case notRestorable
    case alreadyRestored
    case missingTrashItem
    case outsideCurrentUserTrash
    case trashIdentityChanged
    case unsafeRestoreSource
    case sourceAlreadyExists
    case moveFailed(String)
    case resultIndeterminate

    public var errorDescription: String? {
        switch self {
        case .notRestorable: return "只有已确认移入当前用户废纸篓的项目才能恢复。"
        case .alreadyRestored: return "该项目已经恢复，不会重复移动或覆盖文件。"
        case .missingTrashItem: return "废纸篓中的原项目已不存在，无法恢复。"
        case .outsideCurrentUserTrash: return "目标不在当前用户废纸篓的直接子项中，已停止恢复。"
        case .trashIdentityChanged: return "废纸篓项目的身份已变化，已停止恢复。"
        case .unsafeRestoreSource: return "原位置不在允许的清理范围内，或父目录不安全，已停止恢复。"
        case .sourceAlreadyExists: return "原位置已经存在同名项目；不会覆盖，已停止恢复。"
        case .moveFailed(let message): return "系统未能恢复项目：\(message)"
        case .resultIndeterminate: return "恢复后的最终位置或身份无法确认，请手动核对；不会记录为成功。"
        }
    }
}

public struct CleanupRestoreService: Sendable {
    public typealias Mover = @Sendable (URL, URL) throws -> Void

    public let homeDirectory: URL
    public let trashDirectory: URL
    private let mover: Mover

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        trashDirectory: URL? = nil,
        mover: @escaping Mover = { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
        }
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.trashDirectory = (trashDirectory ?? homeDirectory.appendingPathComponent(".Trash", isDirectory: true))
            .standardizedFileURL
        self.mover = mover
    }

    public func restore(_ item: CleanupExecutionItem, now: Date = Date()) -> CleanupExecutionItem {
        var item = item
        do {
            guard item.status == .movedToTrash || item.status == .restoreFailed else {
                throw item.status == .restored ? CleanupRestoreError.alreadyRestored : CleanupRestoreError.notRestorable
            }
            guard let destination = item.trashURL?.standardizedFileURL,
                  let expectedIdentity = item.trashIdentity else {
                throw CleanupRestoreError.notRestorable
            }
            guard isDirectChild(destination, of: trashDirectory) else {
                throw CleanupRestoreError.outsideCurrentUserTrash
            }
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw CleanupRestoreError.missingTrashItem
            }
            guard try CleanupExecutionIdentity.capture(at: destination) == expectedIdentity else {
                throw CleanupRestoreError.trashIdentityChanged
            }
            let source = item.sourceURL.standardizedFileURL
            try validateRestoreSource(source)
            guard !lexists(source) else { throw CleanupRestoreError.sourceAlreadyExists }

            try mover(destination, source)
            guard !lexists(destination),
                  try CleanupExecutionIdentity.capture(at: source) == expectedIdentity else {
                throw CleanupRestoreError.resultIndeterminate
            }
            item.applyRestoreResult(status: .restored, error: nil, now: now)
        } catch {
            let restoreError = error as? CleanupRestoreError
                ?? CleanupRestoreError.moveFailed(error.localizedDescription)
            let status: CleanupExecutionItemStatus
            switch restoreError {
            case .resultIndeterminate: status = .indeterminate
            case .alreadyRestored: status = .restored
            default: status = .restoreFailed
            }
            item.applyRestoreResult(
                status: status,
                error: restoreError.localizedDescription,
                now: now
            )
        }
        return item
    }

    private func validateRestoreSource(_ source: URL) throws {
        let policy = SafePathPolicy(homeDirectory: homeDirectory)
        let roots = policy.cleanupRoots + policy.personalFileRoots
        let rootPaths = roots.map { $0.standardizedFileURL.path }
        guard rootPaths.contains(where: { source.path.hasPrefix($0 + "/") }) else {
            throw CleanupRestoreError.unsafeRestoreSource
        }
        let parent = source.deletingLastPathComponent()
        var information = stat()
        guard parent.path.withCString({ lstat($0, &information) }) == 0,
              information.st_mode & S_IFMT == S_IFDIR else {
            throw CleanupRestoreError.unsafeRestoreSource
        }
        let resolvedParent = parent.resolvingSymlinksInPath().standardizedFileURL
        let resolvedRoots = roots.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        guard resolvedRoots.contains(where: { resolvedParent.path.hasPrefix($0 + "/") || resolvedParent.path == $0 }) else {
            throw CleanupRestoreError.unsafeRestoreSource
        }
    }

    private func isDirectChild(_ url: URL, of directory: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
            == directory.resolvingSymlinksInPath().standardizedFileURL
    }

    private func lexists(_ url: URL) -> Bool {
        var information = stat()
        return url.path.withCString { lstat($0, &information) } == 0
    }
}
