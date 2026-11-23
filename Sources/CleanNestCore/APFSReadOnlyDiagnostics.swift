import Darwin
import Foundation

public enum SparseFileSizeEvidenceError: LocalizedError {
    case metadataUnavailable
    case notRegularFile

    public var errorDescription: String? {
        switch self {
        case .metadataUnavailable: return "无法读取文件逻辑大小与分配块。"
        case .notRegularFile: return "稀疏文件诊断只读取普通文件，不跟随符号链接或目录。"
        }
    }
}

public struct SparseFileSizeEvidence: Codable, Equatable, Identifiable, Sendable {
    public let url: URL
    public let logicalBytes: Int64
    public let allocatedBytes: Int64

    public var id: String { url.path }
    public var isSparse: Bool { allocatedBytes < logicalBytes }
    public var unallocatedLogicalBytes: Int64 { max(0, logicalBytes - allocatedBytes) }

    public init(url: URL, logicalBytes: Int64, allocatedBytes: Int64) {
        self.url = url.standardizedFileURL
        self.logicalBytes = max(0, logicalBytes)
        self.allocatedBytes = max(0, allocatedBytes)
    }

    public static func capture(at url: URL) throws -> SparseFileSizeEvidence {
        let url = url.standardizedFileURL
        var information = stat()
        guard url.path.withCString({ lstat($0, &information) }) == 0 else {
            throw SparseFileSizeEvidenceError.metadataUnavailable
        }
        guard information.st_mode & S_IFMT == S_IFREG else {
            throw SparseFileSizeEvidenceError.notRegularFile
        }
        return SparseFileSizeEvidence(
            url: url,
            logicalBytes: Int64(information.st_size),
            allocatedBytes: Int64(information.st_blocks) * 512
        )
    }
}

public struct APFSVolumeEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let role: String?
    public let capacityBytes: Int64?
    public let usedBytes: Int64?

    public init(id: String, name: String, role: String?, capacityBytes: Int64?, usedBytes: Int64?) {
        self.id = id
        self.name = name
        self.role = role
        self.capacityBytes = capacityBytes.map { max(0, $0) }
        self.usedBytes = usedBytes.map { max(0, $0) }
    }
}

public struct APFSCommandEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let succeeded: Bool
    public let exitCode: Int32?
    public let diagnostic: String

    public init(id: String, succeeded: Bool, exitCode: Int32?, diagnostic: String) {
        self.id = id
        self.succeeded = succeeded
        self.exitCode = exitCode
        self.diagnostic = diagnostic
    }
}

public struct APFSTrashSizeEvidence: Codable, Equatable, Sendable {
    public let logicalBytes: Int64?
    public let allocatedBytes: Int64?
    public let visitedEntryCount: Int
    public let unreadableEntryCount: Int
    public let isComplete: Bool

    public init(
        logicalBytes: Int64?,
        allocatedBytes: Int64?,
        visitedEntryCount: Int,
        unreadableEntryCount: Int,
        isComplete: Bool
    ) {
        self.logicalBytes = logicalBytes.map { max(0, $0) }
        self.allocatedBytes = allocatedBytes.map { max(0, $0) }
        self.visitedEntryCount = max(0, visitedEntryCount)
        self.unreadableEntryCount = max(0, unreadableEntryCount)
        self.isComplete = isComplete
    }
}

public struct APFSDiagnosticReport: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let volume: DiskVolumeSnapshot?
    public let trash: APFSTrashSizeEvidence
    public let apfsVolumes: [APFSVolumeEvidence]
    public let localSnapshots: [String]
    public let commands: [APFSCommandEvidence]
    public let diagnostics: [String]

    public init(
        capturedAt: Date = Date(),
        volume: DiskVolumeSnapshot?,
        trash: APFSTrashSizeEvidence,
        apfsVolumes: [APFSVolumeEvidence],
        localSnapshots: [String],
        commands: [APFSCommandEvidence],
        diagnostics: [String]
    ) {
        self.capturedAt = capturedAt
        self.volume = volume
        self.trash = trash
        self.apfsVolumes = apfsVolumes
        self.localSnapshots = localSnapshots
        self.commands = commands
        self.diagnostics = diagnostics
    }

    public var hasUnknownEvidence: Bool {
        volume == nil || volume?.availableForImportantUsageBytes == nil
            || !trash.isComplete || commands.contains { !$0.succeeded } || !diagnostics.isEmpty
    }
}

public typealias APFSReadOnlyCommandExecutor = @Sendable (
    _ executable: URL,
    _ arguments: [String],
    _ timeout: TimeInterval
) async throws -> CommandResult

/// Bounded APFS evidence collection. It has no purge, deletion or snapshot
/// mutation operation and retains parsed summaries instead of raw command logs.
public struct APFSReadOnlyDiagnostics: Sendable {
    public let trashDirectory: URL
    public let maximumTrashEntries: Int
    private let commandExecutor: APFSReadOnlyCommandExecutor

    public init(
        trashDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true),
        maximumTrashEntries: Int = 50_000,
        commandExecutor: APFSReadOnlyCommandExecutor? = nil
    ) {
        self.trashDirectory = trashDirectory.standardizedFileURL
        self.maximumTrashEntries = max(1_000, min(maximumTrashEntries, 200_000))
        self.commandExecutor = commandExecutor ?? { executable, arguments, timeout in
            try await CommandRunner().run(executable: executable, arguments: arguments, timeout: timeout)
        }
    }

    public func capture(selectedRoot: URL) async -> APFSDiagnosticReport {
        let trash = inspectTrash()
        var commands: [APFSCommandEvidence] = []
        var diagnostics: [String] = []
        if !trash.isComplete {
            diagnostics.append("当前用户废纸篓存在不可读项目或触及遍历上限，占用量保持未知。")
        }

        let diskutil = URL(fileURLWithPath: "/usr/sbin/diskutil")
        let tmutil = URL(fileURLWithPath: "/usr/bin/tmutil")
        let diskutilResult = await run(executable: diskutil, arguments: ["apfs", "list"])
        commands.append(diskutilResult.evidence)
        let volumes: [APFSVolumeEvidence]
        if let output = diskutilResult.output {
            let parsed = Self.parseAPFSVolumes(output)
            volumes = parsed.volumes
            diagnostics.append(contentsOf: parsed.diagnostics)
        } else {
            volumes = []
        }

        let tmutilResult = await run(executable: tmutil, arguments: ["listlocalsnapshots", "/"])
        commands.append(tmutilResult.evidence)
        let snapshots: [String]
        if let output = tmutilResult.output {
            let parsed = Self.parseLocalSnapshots(output)
            snapshots = parsed.snapshots
            diagnostics.append(contentsOf: parsed.diagnostics)
        } else {
            snapshots = []
        }

        return APFSDiagnosticReport(
            volume: DiskVolumeSnapshot.capture(for: selectedRoot),
            trash: trash,
            apfsVolumes: volumes,
            localSnapshots: snapshots,
            commands: commands,
            diagnostics: Array(diagnostics.prefix(16))
        )
    }

    private struct CommandOutcome {
        let evidence: APFSCommandEvidence
        let output: String?
    }

    private func run(executable: URL, arguments: [String]) async -> CommandOutcome {
        let id = [executable.lastPathComponent] + arguments
        let commandID = id.joined(separator: " ")
        do {
            let result = try await commandExecutor(executable, arguments, 8)
            guard result.exitCode == 0 else {
                return CommandOutcome(
                    evidence: APFSCommandEvidence(
                        id: commandID,
                        succeeded: false,
                        exitCode: result.exitCode,
                        diagnostic: "命令返回非零状态；未保留原始输出，相关证据未知。"
                    ),
                    output: nil
                )
            }
            guard !result.standardOutput.isEmpty, result.standardOutput.utf8.count <= 1_048_576 else {
                return CommandOutcome(
                    evidence: APFSCommandEvidence(
                        id: commandID,
                        succeeded: false,
                        exitCode: result.exitCode,
                        diagnostic: "命令输出为空或超过 1 MiB；相关证据未知。"
                    ),
                    output: nil
                )
            }
            return CommandOutcome(
                evidence: APFSCommandEvidence(
                    id: commandID,
                    succeeded: true,
                    exitCode: result.exitCode,
                    diagnostic: "只读命令完成；仅保留有界解析摘要。"
                ),
                output: result.standardOutput
            )
        } catch {
            return CommandOutcome(
                evidence: APFSCommandEvidence(
                    id: commandID,
                    succeeded: false,
                    exitCode: nil,
                    diagnostic: "命令不存在、无法启动、已取消或超时；相关证据未知。"
                ),
                output: nil
            )
        }
    }

    private func inspectTrash() -> APFSTrashSizeEvidence {
        var rootInformation = stat()
        guard trashDirectory.path.withCString({ lstat($0, &rootInformation) }) == 0,
              rootInformation.st_mode & S_IFMT == S_IFDIR else {
            return APFSTrashSizeEvidence(
                logicalBytes: nil,
                allocatedBytes: nil,
                visitedEntryCount: 0,
                unreadableEntryCount: 1,
                isComplete: false
            )
        }
        var logicalBytes: Int64 = 0
        var allocatedBytes: Int64 = 0
        var visited = 0
        var unreadable = 0
        var complete = true
        guard let enumerator = FileManager.default.enumerator(
            at: trashDirectory,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in
                unreadable += 1
                complete = false
                return true
            }
        ) else {
            return APFSTrashSizeEvidence(
                logicalBytes: nil,
                allocatedBytes: nil,
                visitedEntryCount: 0,
                unreadableEntryCount: 1,
                isComplete: false
            )
        }
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            guard visited <= maximumTrashEntries else {
                complete = false
                break
            }
            var information = stat()
            guard url.path.withCString({ lstat($0, &information) }) == 0 else {
                unreadable += 1
                complete = false
                continue
            }
            let allocated = Int64(information.st_blocks) * 512
            allocatedBytes = saturatingAdd(allocatedBytes, max(0, allocated))
            if information.st_mode & S_IFMT == S_IFREG {
                logicalBytes = saturatingAdd(logicalBytes, max(0, Int64(information.st_size)))
            }
        }
        return APFSTrashSizeEvidence(
            logicalBytes: complete ? logicalBytes : nil,
            allocatedBytes: complete ? allocatedBytes : nil,
            visitedEntryCount: visited,
            unreadableEntryCount: unreadable,
            isComplete: complete
        )
    }

    private func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }

    public static func parseAPFSVolumes(_ output: String) -> (volumes: [APFSVolumeEvidence], diagnostics: [String]) {
        var volumes: [APFSVolumeEvidence] = []
        var diagnostics: [String] = []
        var identifier: String?
        var name: String?
        var role: String?
        var capacity: Int64?
        var used: Int64?

        func finishVolume() {
            guard let identifier else { return }
            let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            volumes.append(APFSVolumeEvidence(
                id: identifier,
                name: resolvedName?.isEmpty == false ? resolvedName! : identifier,
                role: role?.trimmingCharacters(in: .whitespacesAndNewlines),
                capacityBytes: capacity,
                usedBytes: used
            ))
            if name == nil || used == nil {
                diagnostics.append("卷 \(identifier) 的名称、容量或已用量未能完整解析，缺失项保持未知。")
            }
        }

        for sourceLine in output.components(separatedBy: .newlines) {
            var line = sourceLine.trimmingCharacters(in: .whitespaces)
            // diskutil prefixes every child of a non-final APFS container with
            // a tree bar. The final child (often VM) has no bar; treating that
            // layout as plain text used to retain only the final volume.
            if line.hasPrefix("|") {
                line = line.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            if line.hasPrefix("APFS Volume ") {
                finishVolume()
                if line.hasPrefix("APFS Volume Disk (Role):") {
                    let header = value(after: "APFS Volume Disk (Role):", in: line)
                    identifier = header.components(separatedBy: .whitespaces).first
                    role = parenthesizedValue(in: line)
                } else {
                    identifier = String(line.dropFirst("APFS Volume ".count))
                        .components(separatedBy: .whitespaces).first
                    role = nil
                }
                name = nil
                capacity = nil
                used = nil
                if volumes.count >= 64 {
                    diagnostics.append("APFS 卷摘要达到 64 项上限，其余卷未显示。")
                    break
                }
                continue
            }
            guard identifier != nil else { continue }
            if line.hasPrefix("Name:") {
                name = value(after: "Name:", in: line)
            } else if line.hasPrefix("Role:") {
                role = value(after: "Role:", in: line)
            } else if line.hasPrefix("Capacity Consumed:") {
                used = byteValue(in: line)
            } else if line.hasPrefix("Capacity:") {
                capacity = byteValue(in: line)
            } else if line.hasPrefix("Used:") {
                used = byteValue(in: line)
            }
        }
        if volumes.count < 64 { finishVolume() }
        if volumes.isEmpty { diagnostics.append("diskutil 输出中未解析到 APFS 卷；卷明细保持未知。") }
        return (volumes, Array(diagnostics.prefix(8)))
    }

    public static func parseLocalSnapshots(_ output: String) -> (snapshots: [String], diagnostics: [String]) {
        var snapshots: [String] = []
        var diagnostics: [String] = []
        for sourceLine in output.components(separatedBy: .newlines) {
            let name = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            if (name.hasPrefix("Snapshots for disk ") || name.hasPrefix("Snapshots for volume ")),
               name.hasSuffix(":") {
                continue
            }
            guard name.utf8.count <= 256 else {
                diagnostics.append("存在异常长的快照名称，已丢弃该文本证据。")
                continue
            }
            if snapshots.count < 128 {
                snapshots.append(name)
            } else {
                diagnostics.append("本地快照摘要达到 128 项上限，其余项目未显示。")
                break
            }
        }
        return (snapshots, diagnostics)
    }

    private static func parenthesizedValue(in line: String) -> String? {
        guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else {
            return nil
        }
        let value = line[line.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private static func value(after key: String, in line: String) -> String {
        String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func byteValue(in line: String) -> Int64? {
        if let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close {
            let inside = line[line.index(after: open)..<close]
            for component in inside.split(separator: " ") {
                let digits = component.replacingOccurrences(of: ",", with: "")
                if let value = Int64(digits) { return value }
            }
        }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let components = line[line.index(after: colon)...].split(separator: " ")
        guard components.count >= 2, components[1] == "B" else { return nil }
        return Int64(components[0].replacingOccurrences(of: ",", with: ""))
    }
}
