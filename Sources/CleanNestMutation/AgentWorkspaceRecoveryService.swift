import CleanNestCore
import CryptoKit
import Darwin
import Foundation

public enum AgentWorkspaceRecoveryStatus: String, Codable, Equatable, Sendable {
    case preparing
    case backupVerified
    case movingOriginals
    case removingOriginals
    case available
    case interrupted
    case restored

    public var displayName: String {
        switch self {
        case .preparing: return "正在准备备份"
        case .backupVerified: return "备份已校验"
        case .movingOriginals: return "正在隔离原文件"
        case .removingOriginals: return "正在释放原文件"
        case .available: return "可以恢复"
        case .interrupted: return "需要恢复检查"
        case .restored: return "已恢复"
        }
    }
}

public struct AgentWorkspaceRecoveryItem: Codable, Equatable, Sendable {
    public let candidate: AgentWorkspaceActionCandidate
    public let archiveRelativePath: String
    public let pendingFileName: String

    public init(
        candidate: AgentWorkspaceActionCandidate,
        archiveRelativePath: String,
        pendingFileName: String
    ) {
        self.candidate = candidate
        self.archiveRelativePath = archiveRelativePath
        self.pendingFileName = pendingFileName
    }
}

public struct AgentWorkspaceRecoveryRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var completedAt: Date?
    public var restoredAt: Date?
    public var status: AgentWorkspaceRecoveryStatus
    public let items: [AgentWorkspaceRecoveryItem]
    public let originalAllocatedBytes: Int64
    public let originalLogicalBytes: Int64
    public var archiveAllocatedBytes: Int64
    public var archiveSHA256: String?
    public var removedOriginalBytes: Int64
    public var pendingOriginalBytes: Int64
    public let apfsFreeBefore: Int64
    public var apfsFreeAfter: Int64?
    public var apfsFreeAfterRestore: Int64?
    public var diagnostic: String

    public init(
        id: UUID,
        createdAt: Date,
        completedAt: Date? = nil,
        restoredAt: Date? = nil,
        status: AgentWorkspaceRecoveryStatus,
        items: [AgentWorkspaceRecoveryItem],
        originalAllocatedBytes: Int64,
        originalLogicalBytes: Int64,
        archiveAllocatedBytes: Int64 = 0,
        archiveSHA256: String? = nil,
        removedOriginalBytes: Int64 = 0,
        pendingOriginalBytes: Int64 = 0,
        apfsFreeBefore: Int64,
        apfsFreeAfter: Int64? = nil,
        apfsFreeAfterRestore: Int64? = nil,
        diagnostic: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.restoredAt = restoredAt
        self.status = status
        self.items = items
        self.originalAllocatedBytes = originalAllocatedBytes
        self.originalLogicalBytes = originalLogicalBytes
        self.archiveAllocatedBytes = archiveAllocatedBytes
        self.archiveSHA256 = archiveSHA256
        self.removedOriginalBytes = removedOriginalBytes
        self.pendingOriginalBytes = pendingOriginalBytes
        self.apfsFreeBefore = apfsFreeBefore
        self.apfsFreeAfter = apfsFreeAfter
        self.apfsFreeAfterRestore = apfsFreeAfterRestore
        self.diagnostic = diagnostic
    }

    public var apfsDeltaBytes: Int64? {
        guard let apfsFreeAfter else { return nil }
        return apfsFreeAfter - apfsFreeBefore
    }

    public var providers: [AgentWorkspaceProvider] {
        Array(Set(items.map(\.candidate.provider))).sorted { $0.rawValue < $1.rawValue }
    }
}

public struct AgentWorkspaceRecoveryResult: Equatable, Sendable {
    public let record: AgentWorkspaceRecoveryRecord
    public let operationDirectory: URL

    public init(record: AgentWorkspaceRecoveryRecord, operationDirectory: URL) {
        self.record = record
        self.operationDirectory = operationDirectory
    }
}

public enum AgentWorkspaceRecoveryError: LocalizedError, Equatable {
    case emptySelection
    case selectionTooLarge(Int)
    case dataTooLarge(Int64)
    case unsupportedCategory
    case outsideAllowedRoot
    case symbolicLinkBoundary
    case fileChanged
    case fileRecentlyModified
    case fileOpen
    case activityProbeUnavailable
    case ownerMismatch
    case duplicateFileIdentity
    case insufficientBackupCapacity(required: Int64, available: Int64)
    case crossVolumeRecovery
    case backupFailed(String)
    case backupVerificationFailed
    case operationMissing
    case archiveMissing
    case restoreConflict(String)
    case rollbackIncomplete

    public var errorDescription: String? {
        switch self {
        case .emptySelection: return "还没有选择可处理的 Agent 文件。"
        case .selectionTooLarge(let count): return "一次最多处理 2,000 个文件；当前选择了 \(count) 个。"
        case .dataTooLarge(let bytes): return "单次安全备份上限为 50 GB；当前逻辑体积为 \(CleanNestFormatting.bytes(bytes))。"
        case .unsupportedCategory: return "只处理 Codex/Claude 的可再生缓存、临时文件和日志。其他 Agent、会话、索引、记忆与凭据继续只读。"
        case .outsideAllowedRoot: return "候选路径已经离开已验证的 Codex/Claude 默认目录。"
        case .symbolicLinkBoundary: return "候选路径包含符号链接边界，操作已停止。"
        case .fileChanged: return "文件在扫描后发生了变化；没有处理任何未确认目标。"
        case .fileRecentlyModified: return "文件在近 15 分钟内仍有写入；本次操作已停止。"
        case .fileOpen: return "至少一个候选文件正被进程打开；本次操作已停止。"
        case .activityProbeUnavailable: return "无法确认当前打开文件，安全处置已失败关闭。"
        case .ownerMismatch: return "候选文件不属于当前用户，CleanNest 不会处理。"
        case .duplicateFileIdentity: return "选择中存在同一文件的重复身份，操作已停止。"
        case .insufficientBackupCapacity(let required, let available):
            return "压缩前至少需要 \(CleanNestFormatting.bytes(required)) 可用空间，当前约 \(CleanNestFormatting.bytes(available))。"
        case .crossVolumeRecovery: return "恢复区与 Agent 文件不在同一磁盘卷，无法保证原子回滚。"
        case .backupFailed(let detail): return "压缩备份没有完成：\(detail)"
        case .backupVerificationFailed: return "备份完整性校验没有通过；原文件保持不动。"
        case .operationMissing: return "恢复记录已经不存在。"
        case .archiveMissing: return "恢复压缩包已经不存在，无法继续恢复。"
        case .restoreConflict(let path): return "原位置已经出现新文件，CleanNest 不会覆盖：\(path)"
        case .rollbackIncomplete: return "自动回滚没有完全结束；恢复记录已保留，请不要手动删除恢复区。"
        }
    }
}

public enum AgentWorkspaceBackupCapacityPolicy {
    public static let safetyMarginBytes: Int64 = 512 * 1_024 * 1_024

    public static func requiredFreeBytes(forLogicalBytes logicalBytes: Int64) -> Int64 {
        let safeLogicalBytes = max(0, logicalBytes)
        guard safeLogicalBytes <= Int64.max - safetyMarginBytes else { return Int64.max }
        return safeLogicalBytes + safetyMarginBytes
    }

    public static func hasCapacity(logicalBytes: Int64, availableBytes: Int64) -> Bool {
        max(0, availableBytes) >= requiredFreeBytes(forLogicalBytes: logicalBytes)
    }
}

/// GUI-only, backup-first mutation boundary for Agent cache/log/temp files.
///
/// The read-only MCP and scanner targets do not link this module. Every
/// operation creates and verifies a local ZIP before originals leave their
/// paths. No Trash is emptied and no Agent process or private index is edited.
public struct AgentWorkspaceRecoveryService: Sendable {
    public let homeDirectory: URL
    public let recoveryRoot: URL
    public let recentInterval: TimeInterval
    public let maximumCandidates: Int
    public let maximumLogicalBytes: Int64

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        recoveryRoot: URL = CleanNestDataPaths.agentWorkspaceRecoveryDirectory(),
        recentInterval: TimeInterval = 15 * 60,
        maximumCandidates: Int = 2_000,
        maximumLogicalBytes: Int64 = 50 * 1_024 * 1_024 * 1_024
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.recoveryRoot = recoveryRoot.standardizedFileURL
        self.recentInterval = max(60, recentInterval)
        self.maximumCandidates = max(1, maximumCandidates)
        self.maximumLogicalBytes = max(1_024 * 1_024, maximumLogicalBytes)
    }

    public func listRecords() throws -> [AgentWorkspaceRecoveryRecord] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: recoveryRoot.path) else { return [] }
        let children = try fileManager.contentsOfDirectory(
            at: recoveryRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        return children.compactMap { child in
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { return nil }
            return try? Self.decodeRecord(at: child.appendingPathComponent("manifest.json"))
        }.sorted { $0.createdAt > $1.createdAt }
    }

    public func createRecovery(
        candidates rawCandidates: [AgentWorkspaceActionCandidate],
        now: Date = Date()
    ) async throws -> AgentWorkspaceRecoveryResult {
        let candidates = try normalizedCandidates(rawCandidates)
        let firstProbe = await AgentWorkspaceOpenFileProbe().capture()
        guard firstProbe.succeeded else { throw AgentWorkspaceRecoveryError.activityProbeUnavailable }
        let firstOpenPaths = Self.openPathSet(firstProbe.records)
        let prepared: PreparedOperation
        do {
            prepared = try await Task.detached(priority: .userInitiated) {
                try prepareOperation(candidates: candidates, openPaths: firstOpenPaths, now: now)
            }.value
        } catch {
            throw error
        }

        let secondProbe = await AgentWorkspaceOpenFileProbe().capture()
        guard secondProbe.succeeded else {
            try? Self.removePreparedOperation(prepared.operationDirectory, recoveryRoot: recoveryRoot)
            throw AgentWorkspaceRecoveryError.activityProbeUnavailable
        }
        let secondOpenPaths = Self.openPathSet(secondProbe.records)
        do {
            return try await Task.detached(priority: .userInitiated) {
                try commitPreparedOperation(prepared, openPaths: secondOpenPaths, now: Date())
            }.value
        } catch {
            throw error
        }
    }

    public func restore(
        operationID: UUID,
        now: Date = Date()
    ) async throws -> AgentWorkspaceRecoveryResult {
        try await Task.detached(priority: .userInitiated) {
            try restoreOperation(operationID: operationID, now: now)
        }.value
    }

    private struct PreparedOperation: Sendable {
        let operationDirectory: URL
        let archiveURL: URL
        var record: AgentWorkspaceRecoveryRecord
    }

    private func normalizedCandidates(
        _ candidates: [AgentWorkspaceActionCandidate]
    ) throws -> [AgentWorkspaceActionCandidate] {
        guard !candidates.isEmpty else { throw AgentWorkspaceRecoveryError.emptySelection }
        guard candidates.count <= maximumCandidates else {
            throw AgentWorkspaceRecoveryError.selectionTooLarge(candidates.count)
        }
        let sorted = candidates.sorted { $0.path < $1.path }
        let logicalBytes = sorted.reduce(Int64(0)) { Self.saturatingAdd($0, $1.identity.logicalBytes) }
        guard logicalBytes <= maximumLogicalBytes else {
            throw AgentWorkspaceRecoveryError.dataTooLarge(logicalBytes)
        }
        var identities = Set<String>()
        for candidate in sorted {
            guard candidate.provider.supportsBackupFirstRecovery,
                  [.caches, .temporaryFiles, .logs].contains(candidate.kind) else {
                throw AgentWorkspaceRecoveryError.unsupportedCategory
            }
            let key = "\(candidate.identity.deviceID):\(candidate.identity.fileID)"
            guard identities.insert(key).inserted else {
                throw AgentWorkspaceRecoveryError.duplicateFileIdentity
            }
        }
        return sorted
    }

    private func prepareOperation(
        candidates: [AgentWorkspaceActionCandidate],
        openPaths: Set<String>,
        now: Date
    ) throws -> PreparedOperation {
        let fileManager = FileManager.default
        try ensureRecoveryRoot()
        for candidate in candidates {
            try validateCandidate(candidate, openPaths: openPaths, now: now)
        }

        let freeBefore = try Self.freeBytes(at: recoveryRoot)
        let logicalBytes = candidates.reduce(Int64(0)) { Self.saturatingAdd($0, $1.identity.logicalBytes) }
        let required = AgentWorkspaceBackupCapacityPolicy.requiredFreeBytes(
            forLogicalBytes: logicalBytes
        )
        guard AgentWorkspaceBackupCapacityPolicy.hasCapacity(
            logicalBytes: logicalBytes,
            availableBytes: freeBefore
        ) else {
            throw AgentWorkspaceRecoveryError.insufficientBackupCapacity(
                required: required,
                available: freeBefore
            )
        }

        let id = UUID()
        let operationDirectory = recoveryRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: operationDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let staging = operationDirectory.appendingPathComponent("staging", isDirectory: true)
        let archive = operationDirectory.appendingPathComponent("backup.zip", isDirectory: false)
        do {
            try fileManager.createDirectory(
                at: staging,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            let items = candidates.enumerated().map { index, candidate in
                let name = Self.internalFileName(index: index, original: candidate.name)
                return AgentWorkspaceRecoveryItem(
                    candidate: candidate,
                    archiveRelativePath: "staging/\(name)",
                    pendingFileName: name
                )
            }
            var record = AgentWorkspaceRecoveryRecord(
                id: id,
                createdAt: now,
                status: .preparing,
                items: items,
                originalAllocatedBytes: candidates.reduce(Int64(0)) {
                    Self.saturatingAdd($0, $1.identity.allocatedBytes)
                },
                originalLogicalBytes: logicalBytes,
                apfsFreeBefore: freeBefore,
                diagnostic: "正在创建本机压缩备份；原文件尚未移动。"
            )
            try Self.writeRecord(record, operationDirectory: operationDirectory)

            for item in items {
                let destination = staging.appendingPathComponent(item.pendingFileName, isDirectory: false)
                guard link(item.candidate.path, destination.path) == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
            }
            try Self.run(
                executable: "/usr/bin/ditto",
                arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, archive.path]
            )
            try Self.verifyArchive(archive)
            try fileManager.removeItem(at: staging)
            record.status = .backupVerified
            let archiveIdentity = try AgentWorkspaceFileIdentity.capture(at: archive)
            guard archiveIdentity.ownerUserID == geteuid() else {
                throw AgentWorkspaceRecoveryError.backupVerificationFailed
            }
            record.archiveAllocatedBytes = archiveIdentity.allocatedBytes
            record.archiveSHA256 = try Self.sha256(of: archive)
            record.diagnostic = "压缩备份已通过 CRC 校验；正在重新确认文件身份和活跃状态。"
            try Self.writeRecord(record, operationDirectory: operationDirectory)
            return PreparedOperation(
                operationDirectory: operationDirectory,
                archiveURL: archive,
                record: record
            )
        } catch {
            try? Self.removePreparedOperation(operationDirectory, recoveryRoot: recoveryRoot)
            if let recoveryError = error as? AgentWorkspaceRecoveryError { throw recoveryError }
            throw AgentWorkspaceRecoveryError.backupFailed(error.localizedDescription)
        }
    }

    private func commitPreparedOperation(
        _ prepared: PreparedOperation,
        openPaths: Set<String>,
        now: Date
    ) throws -> AgentWorkspaceRecoveryResult {
        let fileManager = FileManager.default
        var record = prepared.record
        do {
            for item in record.items {
                try validateCandidate(item.candidate, openPaths: openPaths, now: now)
            }
        } catch {
            try? Self.removePreparedOperation(prepared.operationDirectory, recoveryRoot: recoveryRoot)
            throw error
        }
        guard try Self.freeBytes(at: prepared.operationDirectory) >= 0 else {
            throw AgentWorkspaceRecoveryError.crossVolumeRecovery
        }

        let pending = prepared.operationDirectory.appendingPathComponent("pending-originals", isDirectory: true)
        try fileManager.createDirectory(
            at: pending,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        for item in record.items {
            let sourceDevice = item.candidate.identity.deviceID
            guard let destinationDevice = Self.deviceID(at: pending), sourceDevice == destinationDevice else {
                try? fileManager.removeItem(at: pending)
                try? Self.removePreparedOperation(prepared.operationDirectory, recoveryRoot: recoveryRoot)
                throw AgentWorkspaceRecoveryError.crossVolumeRecovery
            }
        }

        record.status = .movingOriginals
        record.diagnostic = "备份已校验；正在把已复核原文件原子移动到事务暂存区。"
        try Self.writeRecord(record, operationDirectory: prepared.operationDirectory)

        var moved: [AgentWorkspaceRecoveryItem] = []
        do {
            for item in record.items {
                let source = URL(fileURLWithPath: item.candidate.path)
                let destination = pending.appendingPathComponent(item.pendingFileName, isDirectory: false)
                try validateCandidate(item.candidate, openPaths: openPaths, now: now)
                try Self.exclusiveRename(source: source, destination: destination)
                guard !fileManager.fileExists(atPath: source.path),
                      try AgentWorkspaceFileIdentity.capture(at: destination) == item.candidate.identity else {
                    throw AgentWorkspaceRecoveryError.fileChanged
                }
                moved.append(item)
            }
        } catch {
            let rollbackComplete = Self.rollbackMovedItems(
                moved.reversed(),
                pendingDirectory: pending
            )
            if rollbackComplete {
                try? Self.removePreparedOperation(prepared.operationDirectory, recoveryRoot: recoveryRoot)
                throw error
            }
            record.status = .interrupted
            record.diagnostic = "移动期间发生错误，自动回滚未完全完成；压缩备份与事务原文件均已保留。"
            try? Self.writeRecord(record, operationDirectory: prepared.operationDirectory)
            throw AgentWorkspaceRecoveryError.rollbackIncomplete
        }

        record.status = .removingOriginals
        record.diagnostic = "所有原文件已离开 Agent 目录且备份可恢复；正在释放事务暂存副本。"
        try Self.writeRecord(record, operationDirectory: prepared.operationDirectory)

        var removedBytes: Int64 = 0
        var pendingBytes: Int64 = 0
        for item in record.items {
            let url = pending.appendingPathComponent(item.pendingFileName, isDirectory: false)
            do {
                try fileManager.removeItem(at: url)
                removedBytes = Self.saturatingAdd(removedBytes, item.candidate.identity.allocatedBytes)
            } catch {
                pendingBytes = Self.saturatingAdd(pendingBytes, item.candidate.identity.allocatedBytes)
            }
        }
        if (try? fileManager.contentsOfDirectory(atPath: pending.path).isEmpty) == true {
            try? fileManager.removeItem(at: pending)
        }
        record.status = .available
        record.completedAt = Date()
        record.removedOriginalBytes = removedBytes
        record.pendingOriginalBytes = pendingBytes
        record.apfsFreeAfter = try? Self.freeBytes(at: prepared.operationDirectory)
        if pendingBytes == 0 {
            record.diagnostic = "已处理 \(record.items.count) 个静置文件；压缩备份保留在本机恢复区。"
        } else {
            record.diagnostic = "原文件已离开 Agent 目录，但有 \(CleanNestFormatting.bytes(pendingBytes)) 事务副本未能释放；仍可完整恢复。"
        }
        try Self.writeRecord(record, operationDirectory: prepared.operationDirectory)
        return AgentWorkspaceRecoveryResult(
            record: record,
            operationDirectory: prepared.operationDirectory
        )
    }

    private func restoreOperation(
        operationID: UUID,
        now: Date
    ) throws -> AgentWorkspaceRecoveryResult {
        let fileManager = FileManager.default
        try ensureRecoveryRoot()
        let operationDirectory = try validatedOperationDirectory(operationID: operationID)
        var record = try Self.decodeRecord(at: operationDirectory.appendingPathComponent("manifest.json"))
        guard record.id == operationID else { throw AgentWorkspaceRecoveryError.operationMissing }
        let archive = operationDirectory.appendingPathComponent("backup.zip", isDirectory: false)
        guard fileManager.fileExists(atPath: archive.path) else {
            throw AgentWorkspaceRecoveryError.archiveMissing
        }
        guard let expectedArchiveSHA256 = record.archiveSHA256 else {
            throw AgentWorkspaceRecoveryError.backupVerificationFailed
        }
        do {
            let archiveIdentity = try AgentWorkspaceFileIdentity.capture(at: archive)
            guard archiveIdentity.ownerUserID == geteuid(),
                  try Self.sha256(of: archive) == expectedArchiveSHA256 else {
                throw AgentWorkspaceRecoveryError.backupVerificationFailed
            }
        } catch let recoveryError as AgentWorkspaceRecoveryError {
            throw recoveryError
        } catch {
            throw AgentWorkspaceRecoveryError.backupVerificationFailed
        }
        try Self.verifyArchive(archive)

        let pending = operationDirectory.appendingPathComponent("pending-originals", isDirectory: true)
        var needsArchiveExtraction = false
        for item in record.items {
            let original = URL(fileURLWithPath: item.candidate.path)
            if fileManager.fileExists(atPath: original.path) {
                guard try AgentWorkspaceFileIdentity.capture(at: original) == item.candidate.identity else {
                    throw AgentWorkspaceRecoveryError.restoreConflict(Self.abbreviatedPath(original.path, home: homeDirectory.path))
                }
                continue
            }
            let pendingURL = pending.appendingPathComponent(item.pendingFileName, isDirectory: false)
            if fileManager.fileExists(atPath: pendingURL.path) {
                guard try AgentWorkspaceFileIdentity.capture(at: pendingURL) == item.candidate.identity else {
                    throw AgentWorkspaceRecoveryError.fileChanged
                }
            } else {
                needsArchiveExtraction = true
            }
            try validateRestoreDestination(original, provider: item.candidate.provider)
        }

        let restoreStaging = operationDirectory.appendingPathComponent("restore-staging-\(UUID().uuidString)", isDirectory: true)
        if needsArchiveExtraction {
            try fileManager.createDirectory(
                at: restoreStaging,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            do {
                try Self.run(
                    executable: "/usr/bin/ditto",
                    arguments: ["-x", "-k", archive.path, restoreStaging.path]
                )
            } catch {
                try? fileManager.removeItem(at: restoreStaging)
                throw AgentWorkspaceRecoveryError.backupFailed(error.localizedDescription)
            }
        }

        struct RestoredMove {
            let original: URL
            let source: URL
            let expectedOriginalIdentity: AgentWorkspaceFileIdentity?
        }
        var restoredMoves: [RestoredMove] = []
        do {
            for item in record.items {
                let original = URL(fileURLWithPath: item.candidate.path)
                if fileManager.fileExists(atPath: original.path) { continue }
                try createRestoreParent(for: original, provider: item.candidate.provider)
                let pendingURL = pending.appendingPathComponent(item.pendingFileName, isDirectory: false)
                let source: URL
                let preservesIdentity: Bool
                if fileManager.fileExists(atPath: pendingURL.path) {
                    source = pendingURL
                    preservesIdentity = true
                } else {
                    source = restoreStaging.appendingPathComponent(item.archiveRelativePath, isDirectory: false)
                    preservesIdentity = false
                    let restoredIdentity = try AgentWorkspaceFileIdentity.capture(at: source)
                    guard restoredIdentity.logicalBytes == item.candidate.identity.logicalBytes else {
                        throw AgentWorkspaceRecoveryError.backupVerificationFailed
                    }
                }
                try Self.exclusiveRename(source: source, destination: original)
                let restoredIdentity = try AgentWorkspaceFileIdentity.capture(at: original)
                if preservesIdentity, restoredIdentity != item.candidate.identity {
                    throw AgentWorkspaceRecoveryError.fileChanged
                }
                if !preservesIdentity, restoredIdentity.logicalBytes != item.candidate.identity.logicalBytes {
                    throw AgentWorkspaceRecoveryError.backupVerificationFailed
                }
                restoredMoves.append(RestoredMove(
                    original: original,
                    source: source,
                    expectedOriginalIdentity: preservesIdentity ? item.candidate.identity : nil
                ))
            }
        } catch {
            var rollbackComplete = true
            for move in restoredMoves.reversed() {
                do {
                    guard !fileManager.fileExists(atPath: move.source.path) else {
                        rollbackComplete = false
                        continue
                    }
                    try Self.exclusiveRename(source: move.original, destination: move.source)
                } catch {
                    rollbackComplete = false
                }
            }
            try? fileManager.removeItem(at: restoreStaging)
            if !rollbackComplete {
                record.status = .interrupted
                record.diagnostic = "恢复遇到冲突且自动回滚不完整；压缩备份仍保留。"
                try? Self.writeRecord(record, operationDirectory: operationDirectory)
                throw AgentWorkspaceRecoveryError.rollbackIncomplete
            }
            throw error
        }

        try? fileManager.removeItem(at: restoreStaging)
        if (try? fileManager.contentsOfDirectory(atPath: pending.path).isEmpty) == true {
            try? fileManager.removeItem(at: pending)
        }
        record.status = .restored
        record.restoredAt = now
        record.apfsFreeAfterRestore = try? Self.freeBytes(at: operationDirectory)
        record.diagnostic = "已恢复 \(record.items.count) 个文件；压缩备份仍保留，CleanNest 未覆盖 Agent 后来新建的文件。"
        try Self.writeRecord(record, operationDirectory: operationDirectory)
        return AgentWorkspaceRecoveryResult(record: record, operationDirectory: operationDirectory)
    }

    private func validateCandidate(
        _ candidate: AgentWorkspaceActionCandidate,
        openPaths: Set<String>,
        now: Date
    ) throws {
        guard [.caches, .temporaryFiles, .logs].contains(candidate.kind) else {
            throw AgentWorkspaceRecoveryError.unsupportedCategory
        }
        let source = URL(fileURLWithPath: candidate.path).standardizedFileURL
        try validateSourceBoundary(source, provider: candidate.provider)
        let identity = try AgentWorkspaceFileIdentity.capture(at: source)
        guard identity == candidate.identity else { throw AgentWorkspaceRecoveryError.fileChanged }
        guard identity.ownerUserID == geteuid() else { throw AgentWorkspaceRecoveryError.ownerMismatch }
        guard now.timeIntervalSince(identity.modificationDate) > recentInterval else {
            throw AgentWorkspaceRecoveryError.fileRecentlyModified
        }
        guard !openPaths.contains(source.path) else { throw AgentWorkspaceRecoveryError.fileOpen }
    }

    private func validateSourceBoundary(_ source: URL, provider: AgentWorkspaceProvider) throws {
        let roots = allowedRoots(for: provider)
        guard roots.contains(where: { Self.path(source.path, isStrictlyInside: $0.path) }) else {
            throw AgentWorkspaceRecoveryError.outsideAllowedRoot
        }
        let resolved = source.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == source.path else {
            throw AgentWorkspaceRecoveryError.symbolicLinkBoundary
        }
        guard roots.contains(where: { root in
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            return Self.path(resolved.path, isStrictlyInside: resolvedRoot.path)
        }) else {
            throw AgentWorkspaceRecoveryError.outsideAllowedRoot
        }
    }

    private func validateRestoreDestination(
        _ destination: URL,
        provider: AgentWorkspaceProvider
    ) throws {
        let roots = allowedRoots(for: provider)
        guard roots.contains(where: { Self.path(destination.path, isStrictlyInside: $0.path) }) else {
            throw AgentWorkspaceRecoveryError.outsideAllowedRoot
        }
        var ancestor = destination.deletingLastPathComponent().standardizedFileURL
        while !FileManager.default.fileExists(atPath: ancestor.path), ancestor.path != "/" {
            ancestor.deleteLastPathComponent()
        }
        let resolvedAncestor = ancestor.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedAncestor.path == ancestor.path else {
            throw AgentWorkspaceRecoveryError.symbolicLinkBoundary
        }
    }

    private func createRestoreParent(
        for destination: URL,
        provider: AgentWorkspaceProvider
    ) throws {
        try validateRestoreDestination(destination, provider: provider)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        try validateRestoreDestination(destination, provider: provider)
    }

    private func allowedRoots(for provider: AgentWorkspaceProvider) -> [URL] {
        switch provider {
        case .codex:
            return [homeDirectory.appendingPathComponent(".codex", isDirectory: true)]
        case .claude:
            return [
                homeDirectory.appendingPathComponent(".claude", isDirectory: true),
                homeDirectory.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            ]
        case .piAgent, .kimi, .workBuddy, .hermes, .openClaw, .trae, .miniMaxHub, .xiaoyunque:
            return []
        }
    }

    private func ensureRecoveryRoot() throws {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: recoveryRoot.path) {
            try fileManager.createDirectory(
                at: recoveryRoot,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
        }
        let values = try recoveryRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw AgentWorkspaceRecoveryError.symbolicLinkBoundary
        }
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o700)],
            ofItemAtPath: recoveryRoot.path
        )
    }

    private func validatedOperationDirectory(operationID: UUID) throws -> URL {
        let operation = recoveryRoot.appendingPathComponent(operationID.uuidString, isDirectory: true)
        guard operation.deletingLastPathComponent().standardizedFileURL.path == recoveryRoot.path,
              Self.path(operation.path, isStrictlyInside: recoveryRoot.path) else {
            throw AgentWorkspaceRecoveryError.operationMissing
        }

        var info = stat()
        guard lstat(operation.path, &info) == 0 else {
            throw AgentWorkspaceRecoveryError.operationMissing
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(),
              operation.resolvingSymlinksInPath().standardizedFileURL.path == operation.path else {
            throw AgentWorkspaceRecoveryError.symbolicLinkBoundary
        }
        return operation
    }

    private static func rollbackMovedItems<S: Sequence>(
        _ items: S,
        pendingDirectory: URL
    ) -> Bool where S.Element == AgentWorkspaceRecoveryItem {
        var complete = true
        for item in items {
            let source = pendingDirectory.appendingPathComponent(item.pendingFileName, isDirectory: false)
            let destination = URL(fileURLWithPath: item.candidate.path)
            do {
                guard !FileManager.default.fileExists(atPath: destination.path),
                      try AgentWorkspaceFileIdentity.capture(at: source) == item.candidate.identity else {
                    complete = false
                    continue
                }
                try exclusiveRename(source: source, destination: destination)
            } catch {
                complete = false
            }
        }
        return complete
    }

    private static func exclusiveRename(source: URL, destination: URL) throws {
        let result = source.path.withCString { sourcePath in
            destination.path.withCString { destinationPath in
                renameatx_np(
                    AT_FDCWD,
                    sourcePath,
                    AT_FDCWD,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard result == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func run(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        let detail = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile().prefix(16_384),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw AgentWorkspaceRecoveryError.backupFailed(
                detail.isEmpty ? "系统工具退出状态 \(process.terminationStatus)" : detail
            )
        }
    }

    private static func verifyArchive(_ archive: URL) throws {
        do {
            try run(executable: "/usr/bin/unzip", arguments: ["-tqq", archive.path])
        } catch {
            throw AgentWorkspaceRecoveryError.backupVerificationFailed
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func writeRecord(
        _ record: AgentWorkspaceRecoveryRecord,
        operationDirectory: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        let url = operationDirectory.appendingPathComponent("manifest.json", isDirectory: false)
        // NSData's iOS file-protection writing flags return EPERM for ordinary
        // macOS directories on macOS 26. The recovery directory is already
        // owner-only (0700); keep the atomic replacement and enforce an
        // owner-only manifest (0600) instead of turning an unsupported flag
        // into a failed backup.
        try data.write(
            to: url,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    private static func decodeRecord(at url: URL) throws -> AgentWorkspaceRecoveryRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentWorkspaceRecoveryRecord.self, from: Data(contentsOf: url))
    }

    private static func removePreparedOperation(_ operation: URL, recoveryRoot: URL) throws {
        guard path(operation.path, isStrictlyInside: recoveryRoot.path),
              operation.deletingLastPathComponent().standardizedFileURL == recoveryRoot.standardizedFileURL else {
            throw AgentWorkspaceRecoveryError.outsideAllowedRoot
        }
        try FileManager.default.removeItem(at: operation)
    }

    private static func freeBytes(at url: URL) throws -> Int64 {
        let anchor = FileManager.default.fileExists(atPath: url.path)
            ? url
            : url.deletingLastPathComponent()
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: anchor.path)
        return max(0, (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
    }

    private static func deviceID(at url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemNumber] as? NSNumber)?.uint64Value
    }

    private static func openPathSet(_ records: [AgentWorkspaceOpenFile]) -> Set<String> {
        Set(records.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
    }

    private static func internalFileName(index: Int, original: String) -> String {
        let ext = URL(fileURLWithPath: original).pathExtension
            .lowercased()
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let safeExtension = String(ext.prefix(12))
        let base = String(format: "%06d", index)
        return safeExtension.isEmpty ? base : "\(base).\(safeExtension)"
    }

    private static func path(_ candidate: String, isStrictlyInside root: String) -> Bool {
        let value = URL(fileURLWithPath: candidate).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return value.hasPrefix(normalizedRoot + "/")
    }

    private static func abbreviatedPath(_ path: String, home: String) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}
