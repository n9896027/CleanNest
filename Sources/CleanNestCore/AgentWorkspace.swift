import Darwin
import Foundation

public enum AgentWorkspaceProvider: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case codex
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        }
    }
}

public enum AgentArtifactKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case activeSessions
    case archivedSessions
    case backups
    case generatedMedia
    case caches
    case temporaryFiles
    case logs
    case runtime
    case virtualMachines
    case memoryAndPlans
    case stateAndIndexes
    case credentials
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .activeSessions: return "会话与工具输出"
        case .archivedSessions: return "已归档会话"
        case .backups: return "备份"
        case .generatedMedia: return "生成图片与交互资源"
        case .caches: return "可再生缓存"
        case .temporaryFiles: return "临时文件"
        case .logs: return "日志"
        case .runtime: return "插件与运行时"
        case .virtualMachines: return "虚拟机与隔离环境"
        case .memoryAndPlans: return "记忆、计划与项目资料"
        case .stateAndIndexes: return "状态与索引"
        case .credentials: return "账号与凭据"
        case .unknown: return "尚未识别"
        }
    }
}

public enum AgentArtifactDisposition: String, Codable, Equatable, Sendable {
    case protected
    case keep
    case review
    case regenerable
    case unknown

    public var displayName: String {
        switch self {
        case .protected: return "正在使用·已保护"
        case .keep: return "默认保留"
        case .review: return "可归档复核"
        case .regenerable: return "可再生复核"
        case .unknown: return "只读查看"
        }
    }
}

public enum AgentWorkspaceAlertLevel: Int, Codable, Comparable, Sendable {
    case info = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct AgentWorkspaceOpenFile: Codable, Equatable, Hashable, Sendable {
    public let processID: Int32
    public let commandName: String
    public let path: String

    public init(processID: Int32, commandName: String, path: String) {
        self.processID = processID
        self.commandName = commandName
        self.path = path
    }
}

public struct AgentWorkspaceArtifact: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let provider: AgentWorkspaceProvider
    public let kind: AgentArtifactKind
    public let sourcePaths: [String]
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let fileCount: Int
    public let directoryCount: Int
    public let activeFileCount: Int
    public let recentlyModifiedFileCount: Int
    public let oldFileCount: Int
    public let previewBytes: Int64
    public let largestFileBytes: Int64
    public let largestFilePath: String?
    public let latestModificationDate: Date?
    public let disposition: AgentArtifactDisposition
    public let protectionReasons: [String]
    public let isComplete: Bool
    public let diagnostic: String?

    public init(
        id: String,
        provider: AgentWorkspaceProvider,
        kind: AgentArtifactKind,
        sourcePaths: [String],
        allocatedBytes: Int64,
        logicalBytes: Int64,
        fileCount: Int,
        directoryCount: Int,
        activeFileCount: Int,
        recentlyModifiedFileCount: Int,
        oldFileCount: Int,
        previewBytes: Int64,
        largestFileBytes: Int64,
        largestFilePath: String?,
        latestModificationDate: Date?,
        disposition: AgentArtifactDisposition,
        protectionReasons: [String],
        isComplete: Bool,
        diagnostic: String?
    ) {
        self.id = id
        self.provider = provider
        self.kind = kind
        self.sourcePaths = sourcePaths
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.activeFileCount = activeFileCount
        self.recentlyModifiedFileCount = recentlyModifiedFileCount
        self.oldFileCount = oldFileCount
        self.previewBytes = previewBytes
        self.largestFileBytes = largestFileBytes
        self.largestFilePath = largestFilePath
        self.latestModificationDate = latestModificationDate
        self.disposition = disposition
        self.protectionReasons = protectionReasons
        self.isComplete = isComplete
        self.diagnostic = diagnostic
    }
}

public struct AgentWorkspaceAgentSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let provider: AgentWorkspaceProvider
    public let detected: Bool
    public let artifacts: [AgentWorkspaceArtifact]
    public let diagnostics: [String]

    public var id: String { provider.rawValue }
    public var allocatedBytes: Int64 { artifacts.saturatingSum(of: \.allocatedBytes) }
    public var logicalBytes: Int64 { artifacts.saturatingSum(of: \.logicalBytes) }
    public var previewBytes: Int64 { artifacts.saturatingSum(of: \.previewBytes) }
    public var fileCount: Int { artifacts.reduce(0) { $0 + $1.fileCount } }
    public var activeFileCount: Int { artifacts.reduce(0) { $0 + $1.activeFileCount } }
    public var isComplete: Bool { diagnostics.isEmpty && artifacts.allSatisfy(\.isComplete) }

    public init(
        provider: AgentWorkspaceProvider,
        detected: Bool,
        artifacts: [AgentWorkspaceArtifact],
        diagnostics: [String] = []
    ) {
        self.provider = provider
        self.detected = detected
        self.artifacts = artifacts
        self.diagnostics = diagnostics
    }
}

public struct AgentWorkspaceAlert: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let level: AgentWorkspaceAlertLevel
    public let provider: AgentWorkspaceProvider?
    public let title: String
    public let detail: String

    public init(
        id: String,
        level: AgentWorkspaceAlertLevel,
        provider: AgentWorkspaceProvider?,
        title: String,
        detail: String
    ) {
        self.id = id
        self.level = level
        self.provider = provider
        self.title = title
        self.detail = detail
    }
}

public struct AgentWorkspaceSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let previousCapturedAt: Date?
    public let agents: [AgentWorkspaceAgentSnapshot]
    public let alerts: [AgentWorkspaceAlert]
    public let openFileProbeSucceeded: Bool
    public let diagnostic: String

    public var detectedAgents: [AgentWorkspaceAgentSnapshot] { agents.filter(\.detected) }
    public var allocatedBytes: Int64 { detectedAgents.saturatingSum(of: \.allocatedBytes) }
    public var logicalBytes: Int64 { detectedAgents.saturatingSum(of: \.logicalBytes) }
    public var previewBytes: Int64 { detectedAgents.saturatingSum(of: \.previewBytes) }
    public var activeFileCount: Int { detectedAgents.reduce(0) { $0 + $1.activeFileCount } }
    public var isComplete: Bool {
        openFileProbeSucceeded && detectedAgents.allSatisfy(\.isComplete)
    }

    public init(
        capturedAt: Date,
        previousCapturedAt: Date?,
        agents: [AgentWorkspaceAgentSnapshot],
        alerts: [AgentWorkspaceAlert],
        openFileProbeSucceeded: Bool,
        diagnostic: String
    ) {
        self.capturedAt = capturedAt
        self.previousCapturedAt = previousCapturedAt
        self.agents = agents
        self.alerts = alerts
        self.openFileProbeSucceeded = openFileProbeSucceeded
        self.diagnostic = diagnostic
    }
}

public struct AgentWorkspaceObservation: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let allocatedBytesByAgent: [String: Int64]
    public let allocatedBytesByArtifact: [String: Int64]

    public init(
        capturedAt: Date,
        allocatedBytesByAgent: [String: Int64],
        allocatedBytesByArtifact: [String: Int64]
    ) {
        self.capturedAt = capturedAt
        self.allocatedBytesByAgent = allocatedBytesByAgent
        self.allocatedBytesByArtifact = allocatedBytesByArtifact
    }
}

public struct AgentWorkspaceScanResult: Codable, Equatable, Sendable {
    public let snapshot: AgentWorkspaceSnapshot
    public let observation: AgentWorkspaceObservation

    public init(snapshot: AgentWorkspaceSnapshot, observation: AgentWorkspaceObservation) {
        self.snapshot = snapshot
        self.observation = observation
    }
}

public struct AgentWorkspaceScanner: Sendable {
    public struct Configuration: Sendable {
        public var recentInterval: TimeInterval
        public var oldInterval: TimeInterval
        public var largeFileWarningBytes: Int64
        public var largeFileCriticalBytes: Int64
        public var agentSizeWarningBytes: Int64
        public var agentSizeCriticalBytes: Int64
        public var growthWarningBytes: Int64
        public var growthCriticalBytes: Int64
        public var maximumEntriesPerAgent: Int

        public init(
            recentInterval: TimeInterval = 15 * 60,
            oldInterval: TimeInterval = 30 * 86_400,
            largeFileWarningBytes: Int64 = 256 * 1_024 * 1_024,
            largeFileCriticalBytes: Int64 = 2 * 1_024 * 1_024 * 1_024,
            agentSizeWarningBytes: Int64 = 10 * 1_024 * 1_024 * 1_024,
            agentSizeCriticalBytes: Int64 = 50 * 1_024 * 1_024 * 1_024,
            growthWarningBytes: Int64 = 512 * 1_024 * 1_024,
            growthCriticalBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
            maximumEntriesPerAgent: Int = 600_000
        ) {
            self.recentInterval = max(60, recentInterval)
            self.oldInterval = max(recentInterval, oldInterval)
            self.largeFileWarningBytes = max(1, largeFileWarningBytes)
            self.largeFileCriticalBytes = max(largeFileWarningBytes, largeFileCriticalBytes)
            self.agentSizeWarningBytes = max(1, agentSizeWarningBytes)
            self.agentSizeCriticalBytes = max(agentSizeWarningBytes, agentSizeCriticalBytes)
            self.growthWarningBytes = max(1, growthWarningBytes)
            self.growthCriticalBytes = max(growthWarningBytes, growthCriticalBytes)
            self.maximumEntriesPerAgent = max(1_000, maximumEntriesPerAgent)
        }

        public static let defaults = Configuration()
    }

    private struct SourceGroup: Sendable {
        let provider: AgentWorkspaceProvider
        let kind: AgentArtifactKind
        let urls: [URL]
    }

    private struct WalkMetrics: Sendable {
        var allocatedBytes: Int64 = 0
        var logicalBytes: Int64 = 0
        var fileCount = 0
        var directoryCount = 0
        var activeFileCount = 0
        var recentlyModifiedFileCount = 0
        var oldFileCount = 0
        var settledBytes: Int64 = 0
        var oldBytes: Int64 = 0
        var largestFileBytes: Int64 = 0
        var largestFilePath: String?
        var latestModificationDate: Date?
        var isComplete = true
        var diagnostics: [String] = []

        mutating func merge(_ other: Self) {
            allocatedBytes = Self.add(allocatedBytes, other.allocatedBytes)
            logicalBytes = Self.add(logicalBytes, other.logicalBytes)
            fileCount += other.fileCount
            directoryCount += other.directoryCount
            activeFileCount += other.activeFileCount
            recentlyModifiedFileCount += other.recentlyModifiedFileCount
            oldFileCount += other.oldFileCount
            settledBytes = Self.add(settledBytes, other.settledBytes)
            oldBytes = Self.add(oldBytes, other.oldBytes)
            if other.largestFileBytes > largestFileBytes {
                largestFileBytes = other.largestFileBytes
                largestFilePath = other.largestFilePath
            }
            if let date = other.latestModificationDate {
                latestModificationDate = latestModificationDate.map { max($0, date) } ?? date
            }
            isComplete = isComplete && other.isComplete
            diagnostics.append(contentsOf: other.diagnostics)
        }

        private static func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
            guard rhs > 0 else { return lhs }
            return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
        }
    }

    private let configuration: Configuration

    public init(configuration: Configuration = .defaults) {
        self.configuration = configuration
    }

    public func scan(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        previous: AgentWorkspaceObservation? = nil,
        openFiles suppliedOpenFiles: [AgentWorkspaceOpenFile]? = nil,
        suppliedOpenFileProbeSucceeded: Bool = true,
        now: Date = Date()
    ) async throws -> AgentWorkspaceScanResult {
        let probe: AgentWorkspaceOpenFileProbe.Result
        if let suppliedOpenFiles {
            probe = .init(
                records: suppliedOpenFiles,
                succeeded: suppliedOpenFileProbeSucceeded,
                diagnostic: suppliedOpenFileProbeSucceeded
                    ? "测试提供的打开文件清单"
                    : "测试模拟打开文件表不可用"
            )
        } else {
            probe = await AgentWorkspaceOpenFileProbe().capture()
        }
        try Task.checkCancellation()
        return Self.scanMetadata(
            homeDirectory: homeDirectory,
            previous: previous,
            openFileProbe: probe,
            now: now,
            configuration: configuration
        )
    }

    private static func scanMetadata(
        homeDirectory: URL,
        previous: AgentWorkspaceObservation?,
        openFileProbe: AgentWorkspaceOpenFileProbe.Result,
        now: Date,
        configuration: Configuration
    ) -> AgentWorkspaceScanResult {
        let normalizedHome = homeDirectory.standardizedFileURL
        let roots: [AgentWorkspaceProvider: [URL]] = [
            .codex: [normalizedHome.appendingPathComponent(".codex", isDirectory: true)],
            .claude: [
                normalizedHome.appendingPathComponent(".claude", isDirectory: true),
                normalizedHome.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
            ]
        ]
        let openFiles = openFileProbe.records.filter { record in
            roots.values.flatMap { $0 }.contains { root in
                Self.path(record.path, isInside: root.path)
            }
        }
        let openPathSet = Set(openFiles.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })

        let agents = AgentWorkspaceProvider.allCases.map { provider in
            scanAgent(
                provider: provider,
                roots: roots[provider] ?? [],
                openPaths: openPathSet,
                activityProbeSucceeded: openFileProbe.succeeded,
                now: now,
                configuration: configuration
            )
        }
        let observation = AgentWorkspaceObservation(
            capturedAt: now,
            allocatedBytesByAgent: Dictionary(uniqueKeysWithValues: agents.map {
                ($0.provider.rawValue, $0.allocatedBytes)
            }),
            allocatedBytesByArtifact: Dictionary(uniqueKeysWithValues: agents.flatMap { agent in
                agent.artifacts.map { ($0.id, $0.allocatedBytes) }
            })
        )
        var alerts = buildAlerts(
            agents: agents,
            previous: previous,
            current: observation,
            configuration: configuration
        )
        let detectedCount = agents.filter(\.detected).count
        if !openFileProbe.succeeded, detectedCount > 0 {
            alerts.insert(
                AgentWorkspaceAlert(
                    id: "activity-probe-unavailable",
                    level: .warning,
                    provider: nil,
                    title: "未能确认活跃 Agent 文件",
                    detail: "本次只显示占用账本，所有分组的回收预览已归零。"
                ),
                at: 0
            )
        }
        let partialCount = agents.filter { $0.detected && !$0.isComplete }.count
        let diagnostic: String
        if detectedCount == 0 {
            diagnostic = "未在默认位置发现 Codex 或 Claude 的本机数据。"
        } else if partialCount > 0 {
            diagnostic = "已识别 \(detectedCount) 个 Agent，其中 \(partialCount) 个扫描不完整；不完整数据不会进入回收预览。"
        } else {
            diagnostic = "已识别 \(detectedCount) 个 Agent；仅读取文件元数据，未读取会话正文、代码或凭据内容。"
        }
        let snapshot = AgentWorkspaceSnapshot(
            capturedAt: now,
            previousCapturedAt: previous?.capturedAt,
            agents: agents,
            alerts: alerts,
            openFileProbeSucceeded: openFileProbe.succeeded,
            diagnostic: openFileProbe.succeeded
                ? diagnostic
                : "\(diagnostic) \(openFileProbe.diagnostic) 本次所有分组都不进入回收预览。",
        )
        return AgentWorkspaceScanResult(snapshot: snapshot, observation: observation)
    }

    private static func scanAgent(
        provider: AgentWorkspaceProvider,
        roots: [URL],
        openPaths: Set<String>,
        activityProbeSucceeded: Bool,
        now: Date,
        configuration: Configuration
    ) -> AgentWorkspaceAgentSnapshot {
        let fileManager = FileManager.default
        let existingRoots = roots.filter { root in
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        guard !existingRoots.isEmpty else {
            return AgentWorkspaceAgentSnapshot(provider: provider, detected: false, artifacts: [])
        }

        var groupedURLs: [AgentArtifactKind: [URL]] = [:]
        var diagnostics: [String] = []
        for root in existingRoots {
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                if children.isEmpty {
                    groupedURLs[.unknown, default: []].append(root)
                } else {
                    for child in children {
                        let kind = classify(provider: provider, name: child.lastPathComponent, parent: root)
                        groupedURLs[kind, default: []].append(child)
                    }
                }
            } catch {
                diagnostics.append("无法列出 \(abbreviatedPath(root.path, home: roots.first?.deletingLastPathComponent().path))：\(error.localizedDescription)")
            }
        }

        var remainingEntries = configuration.maximumEntriesPerAgent
        var seenFiles = Set<FileIdentity>()
        let artifacts = AgentArtifactKind.allCases.compactMap { kind -> AgentWorkspaceArtifact? in
            guard let urls = groupedURLs[kind], !urls.isEmpty else { return nil }
            var combined = WalkMetrics()
            for url in urls.sorted(by: { $0.path < $1.path }) {
                guard remainingEntries > 0 else {
                    combined.isComplete = false
                    combined.diagnostics.append("已达到单个 Agent 的元数据扫描上限。")
                    break
                }
                let value = walk(
                    url: url,
                    openPaths: openPaths,
                    now: now,
                    configuration: configuration,
                    remainingEntries: &remainingEntries,
                    seenFiles: &seenFiles
                )
                combined.merge(value)
            }
            let protectedByActivity = !activityProbeSucceeded
                || combined.activeFileCount > 0
                || combined.recentlyModifiedFileCount > 0
            let disposition = disposition(
                kind: kind,
                protectedByActivity: protectedByActivity,
                isComplete: combined.isComplete
            )
            let previewBytes: Int64
            if !combined.isComplete || !activityProbeSucceeded {
                previewBytes = 0
            } else {
                switch kind {
                case .caches, .temporaryFiles, .logs:
                    previewBytes = combined.settledBytes
                case .activeSessions, .archivedSessions, .backups, .generatedMedia:
                    previewBytes = combined.oldBytes
                default:
                    previewBytes = 0
                }
            }
            var protectionReasons: [String] = []
            if combined.activeFileCount > 0 {
                protectionReasons.append("有 \(combined.activeFileCount) 个文件正被进程打开")
            }
            if combined.recentlyModifiedFileCount > 0 {
                protectionReasons.append("有 \(combined.recentlyModifiedFileCount) 个文件在近 15 分钟内写入")
            }
            if !activityProbeSucceeded {
                protectionReasons.append("未能确认打开文件状态，本组不进入回收预览")
            }
            if kind == .credentials {
                protectionReasons.append("可能包含账号、令牌或授权状态")
            }
            if kind == .stateAndIndexes {
                protectionReasons.append("直接删除可能导致会话列表与文件状态不一致")
            }
            if !combined.isComplete {
                protectionReasons.append("扫描不完整，默认禁止进入回收预览")
            }
            return AgentWorkspaceArtifact(
                id: "\(provider.rawValue):\(kind.rawValue)",
                provider: provider,
                kind: kind,
                sourcePaths: urls.map { $0.standardizedFileURL.path }.sorted(),
                allocatedBytes: combined.allocatedBytes,
                logicalBytes: combined.logicalBytes,
                fileCount: combined.fileCount,
                directoryCount: combined.directoryCount,
                activeFileCount: combined.activeFileCount,
                recentlyModifiedFileCount: combined.recentlyModifiedFileCount,
                oldFileCount: combined.oldFileCount,
                previewBytes: previewBytes,
                largestFileBytes: combined.largestFileBytes,
                largestFilePath: combined.largestFilePath,
                latestModificationDate: combined.latestModificationDate,
                disposition: disposition,
                protectionReasons: protectionReasons,
                isComplete: combined.isComplete,
                diagnostic: combined.diagnostics.isEmpty
                    ? nil
                    : Array(Set(combined.diagnostics)).sorted().joined(separator: " ")
            )
        }
        return AgentWorkspaceAgentSnapshot(
            provider: provider,
            detected: true,
            artifacts: artifacts.sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.allocatedBytes > $1.allocatedBytes
            },
            diagnostics: diagnostics
        )
    }

    private static func walk(
        url: URL,
        openPaths: Set<String>,
        now: Date,
        configuration: Configuration,
        remainingEntries: inout Int,
        seenFiles: inout Set<FileIdentity>
    ) -> WalkMetrics {
        let path = url.standardizedFileURL.path
        var rootStat = stat()
        guard path.withCString({ lstat($0, &rootStat) }) == 0 else {
            var result = WalkMetrics()
            result.isComplete = false
            result.diagnostics.append("无法读取元数据：\(path)")
            return result
        }
        let type = rootStat.st_mode & S_IFMT
        if type == S_IFREG {
            remainingEntries -= 1
            let identity = FileIdentity(device: UInt64(rootStat.st_dev), inode: UInt64(rootStat.st_ino))
            guard seenFiles.insert(identity).inserted else { return WalkMetrics() }
            return metrics(for: rootStat, path: path, openPaths: openPaths, now: now, configuration: configuration)
        }
        guard type == S_IFDIR else { return WalkMetrics() }

        guard let rootCString = strdup(path) else {
            var result = WalkMetrics()
            result.isComplete = false
            result.diagnostics.append("无法准备目录扫描：\(path)")
            return result
        }
        defer { free(rootCString) }
        let paths = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        paths.initialize(repeating: nil, count: 2)
        paths[0] = rootCString
        defer { paths.deinitialize(count: 2); paths.deallocate() }
        guard let stream = fts_open(UnsafePointer(paths), FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            var result = WalkMetrics()
            result.isComplete = false
            result.diagnostics.append("无法遍历目录：\(path)")
            return result
        }
        defer { fts_close(stream) }

        var result = WalkMetrics()
        while !Task.isCancelled, remainingEntries > 0, let entry = fts_read(stream) {
            if entry.pointee.fts_level == FTS_ROOTLEVEL { continue }
            remainingEntries -= 1
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D:
                result.directoryCount += 1
            case FTS_F:
                guard let statPointer = entry.pointee.fts_statp else { continue }
                let fileStat = statPointer.pointee
                let identity = FileIdentity(device: UInt64(fileStat.st_dev), inode: UInt64(fileStat.st_ino))
                guard seenFiles.insert(identity).inserted else { continue }
                let filePath = String(cString: entry.pointee.fts_path)
                result.merge(metrics(
                    for: fileStat,
                    path: filePath,
                    openPaths: openPaths,
                    now: now,
                    configuration: configuration
                ))
            case FTS_DNR, FTS_ERR, FTS_NS:
                result.isComplete = false
                result.diagnostics.append("部分路径无法读取：\(String(cString: entry.pointee.fts_path))")
            default:
                break
            }
        }
        if remainingEntries == 0 {
            result.isComplete = false
            result.diagnostics.append("已达到单个 Agent 的元数据扫描上限。")
        }
        if Task.isCancelled {
            result.isComplete = false
            result.diagnostics.append("扫描已取消。")
        }
        return result
    }

    private static func metrics(
        for fileStat: stat,
        path: String,
        openPaths: Set<String>,
        now: Date,
        configuration: Configuration
    ) -> WalkMetrics {
        let allocated = max(0, Int64(fileStat.st_blocks) * 512)
        let logical = max(0, Int64(fileStat.st_size))
        let modified = Date(
            timeIntervalSince1970: TimeInterval(fileStat.st_mtimespec.tv_sec)
                + TimeInterval(fileStat.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        let age = max(0, now.timeIntervalSince(modified))
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let isActive = openPaths.contains(normalizedPath)
        var result = WalkMetrics()
        result.allocatedBytes = allocated
        result.logicalBytes = logical
        result.fileCount = 1
        result.activeFileCount = isActive ? 1 : 0
        result.recentlyModifiedFileCount = age <= configuration.recentInterval ? 1 : 0
        result.oldFileCount = age >= configuration.oldInterval ? 1 : 0
        if !isActive, age > configuration.recentInterval { result.settledBytes = allocated }
        if !isActive, age >= configuration.oldInterval { result.oldBytes = allocated }
        result.largestFileBytes = logical
        result.largestFilePath = normalizedPath
        result.latestModificationDate = modified
        return result
    }

    private static func classify(
        provider: AgentWorkspaceProvider,
        name rawName: String,
        parent: URL
    ) -> AgentArtifactKind {
        let name = rawName.lowercased()
        switch provider {
        case .codex:
            if name == "sessions" { return .activeSessions }
            if name == "archived_sessions" { return .archivedSessions }
            if name == "backups" { return .backups }
            if ["generated_images", "computer-use"].contains(name) { return .generatedMedia }
            if name == ".tmp" || name == "tmp" { return .temporaryFiles }
            if name.contains("cache") { return .caches }
            if name == "plugins" { return .runtime }
            if name == "logs" || name.hasPrefix("logs_") { return .logs }
            if name == "memories" || name == "plans" { return .memoryAndPlans }
            if name == "auth.json" || name.contains("credential") || name.contains("token") { return .credentials }
            if name.contains("sqlite") || name.contains("state") || name.contains("queue")
                || name == "thread-writer-locks" { return .stateAndIndexes }
        case .claude:
            if name == "projects" || name == "local-agent-mode-sessions" || name == "session-env"
                || name == "shell-snapshots" || name == "todos" || name == "history.jsonl" {
                return .activeSessions
            }
            if name.contains("archive") { return .archivedSessions }
            if name.contains("backup") { return .backups }
            if name == "file-history" || name == "plans" || name == "memory" { return .memoryAndPlans }
            if name.contains("cache") || name == "blob_storage" || name == "gpucache"
                || name.hasPrefix("dawn") || name == "service worker" { return .caches }
            if name.contains("tmp") || name == "temp" { return .temporaryFiles }
            if name == "logs" || name.hasSuffix(".log") { return .logs }
            if name == "vm_bundles" || name == "claude-code-vm" { return .virtualMachines }
            if name == "claude-code" || name.contains("runtime") { return .runtime }
            if name.contains("cookie") || name.contains("credential") || name.contains("token")
                || name == "local storage" || name == "web data" { return .credentials }
            if name.contains("state") || name.contains("index") || name.contains("database")
                || name.contains("storage") { return .stateAndIndexes }
        }
        if parent.lastPathComponent.lowercased() == "claude", name.hasSuffix(".jsonl") {
            return .activeSessions
        }
        return .unknown
    }

    private static func disposition(
        kind: AgentArtifactKind,
        protectedByActivity: Bool,
        isComplete: Bool
    ) -> AgentArtifactDisposition {
        guard isComplete else { return .protected }
        guard !protectedByActivity else { return .protected }
        switch kind {
        case .credentials, .stateAndIndexes, .memoryAndPlans, .runtime, .virtualMachines:
            return .keep
        case .caches, .temporaryFiles, .logs:
            return .regenerable
        case .activeSessions, .archivedSessions, .backups, .generatedMedia:
            return .review
        case .unknown:
            return .unknown
        }
    }

    private static func buildAlerts(
        agents: [AgentWorkspaceAgentSnapshot],
        previous: AgentWorkspaceObservation?,
        current: AgentWorkspaceObservation,
        configuration: Configuration
    ) -> [AgentWorkspaceAlert] {
        var alerts: [AgentWorkspaceAlert] = []
        for agent in agents where agent.detected {
            if agent.activeFileCount > 0 {
                alerts.append(AgentWorkspaceAlert(
                    id: "\(agent.provider.rawValue):active",
                    level: .info,
                    provider: agent.provider,
                    title: "\(agent.provider.displayName) 存在正在使用的文件",
                    detail: "已确认 \(agent.activeFileCount) 个文件被本机进程打开，相关分组已锁定，不进入回收预览。"
                ))
            }
            if agent.allocatedBytes >= configuration.agentSizeWarningBytes {
                let critical = agent.allocatedBytes >= configuration.agentSizeCriticalBytes
                alerts.append(AgentWorkspaceAlert(
                    id: "\(agent.provider.rawValue):total-size",
                    level: critical ? .critical : .warning,
                    provider: agent.provider,
                    title: "\(agent.provider.displayName) 本机痕迹占用偏大",
                    detail: "当前分配块口径约 \(CleanNestFormatting.bytes(agent.allocatedBytes))；这不等于可直接删除或最终 APFS 可释放空间。"
                ))
            }
            if let largest = agent.artifacts.max(by: { $0.largestFileBytes < $1.largestFileBytes }),
               largest.largestFileBytes >= configuration.largeFileWarningBytes {
                let critical = largest.largestFileBytes >= configuration.largeFileCriticalBytes
                alerts.append(AgentWorkspaceAlert(
                    id: "\(agent.provider.rawValue):large-file",
                    level: critical ? .critical : .warning,
                    provider: agent.provider,
                    title: "\(agent.provider.displayName) 出现超大单文件",
                    detail: "\(largest.kind.displayName) 中最大文件约 \(CleanNestFormatting.bytes(largest.largestFileBytes))；建议先核对是否仍属于活跃会话。"
                ))
            }

            guard let previous,
                  let oldBytes = previous.allocatedBytesByAgent[agent.provider.rawValue] else { continue }
            let elapsed = current.capturedAt.timeIntervalSince(previous.capturedAt)
            guard elapsed >= 30, elapsed <= 7 * 86_400 else { continue }
            let delta = agent.allocatedBytes - oldBytes
            guard delta >= configuration.growthWarningBytes else { continue }
            let critical = delta >= configuration.growthCriticalBytes
            let perHour = Int64(Double(delta) / elapsed * 3_600)
            alerts.append(AgentWorkspaceAlert(
                id: "\(agent.provider.rawValue):growth",
                level: critical ? .critical : .warning,
                provider: agent.provider,
                title: "\(agent.provider.displayName) 占用正在明显增长",
                detail: "与上次基线相比增加 \(CleanNestFormatting.bytes(delta))，折算约 \(CleanNestFormatting.bytes(perHour))/小时。"
            ))
        }
        return alerts.sorted {
            if $0.level != $1.level { return $0.level > $1.level }
            return $0.id < $1.id
        }
    }

    private static func path(_ candidate: String, isInside root: String) -> Bool {
        let value = URL(fileURLWithPath: candidate).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return value == normalizedRoot || value.hasPrefix(normalizedRoot + "/")
    }

    private static func abbreviatedPath(_ path: String, home: String?) -> String {
        guard let home, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

public struct AgentWorkspaceOpenFileProbe: Sendable {
    public struct Result: Sendable {
        public let records: [AgentWorkspaceOpenFile]
        public let succeeded: Bool
        public let diagnostic: String

        public init(records: [AgentWorkspaceOpenFile], succeeded: Bool, diagnostic: String) {
            self.records = records
            self.succeeded = succeeded
            self.diagnostic = diagnostic
        }
    }

    public init() {}

    public func capture() async -> Result {
        do {
            let command = try await CommandRunner().run(
                executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-nP", "-a", "-u", String(getuid()), "-Fpcn"],
                timeout: 8
            )
            guard command.exitCode == 0 else {
                return Result(
                    records: [],
                    succeeded: false,
                    diagnostic: "无法确认当前打开的 Agent 文件。"
                )
            }
            return Result(
                records: Self.parseLsofFieldOutput(command.standardOutput),
                succeeded: true,
                diagnostic: "已通过本机打开文件表确认活跃写入。"
            )
        } catch {
            return Result(
                records: [],
                succeeded: false,
                diagnostic: "无法确认当前打开的 Agent 文件：\(error.localizedDescription)"
            )
        }
    }

    public static func parseLsofFieldOutput(_ output: String) -> [AgentWorkspaceOpenFile] {
        var processID: Int32?
        var commandName = "未知进程"
        var values = Set<AgentWorkspaceOpenFile>()
        for rawLine in output.split(whereSeparator: \.isNewline) {
            guard let prefix = rawLine.first else { continue }
            let payload = String(rawLine.dropFirst())
            switch prefix {
            case "p":
                processID = Int32(payload)
                commandName = "未知进程"
            case "c":
                commandName = payload.isEmpty ? "未知进程" : payload
            case "n":
                guard let processID, payload.hasPrefix("/") else { continue }
                let path = payload.hasSuffix(" (deleted)")
                    ? String(payload.dropLast(" (deleted)".count))
                    : payload
                values.insert(AgentWorkspaceOpenFile(
                    processID: processID,
                    commandName: commandName,
                    path: URL(fileURLWithPath: path).standardizedFileURL.path
                ))
            default:
                continue
            }
        }
        return values.sorted {
            if $0.path == $1.path { return $0.processID < $1.processID }
            return $0.path < $1.path
        }
    }
}

private struct FileIdentity: Hashable {
    let device: UInt64
    let inode: UInt64
}

private extension Array {
    func saturatingSum(of keyPath: KeyPath<Element, Int64>) -> Int64 {
        reduce(0) { current, value in
            let next = value[keyPath: keyPath]
            guard next > 0 else { return current }
            return current > Int64.max - next ? Int64.max : current + next
        }
    }
}
