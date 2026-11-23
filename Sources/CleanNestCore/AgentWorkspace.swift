import Darwin
import Foundation

public enum AgentWorkspaceProvider: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case codex
    case claude
    case piAgent
    case kimi
    case workBuddy
    case hermes
    case openClaw
    case trae
    case miniMaxHub
    case xiaoyunque

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: return "Codex"
        case .claude: return "Claude"
        case .piAgent: return "Pi Agent"
        case .kimi: return "Kimi"
        case .workBuddy: return "WorkBuddy"
        case .hermes: return "Hermes"
        case .openClaw: return "OpenClaw"
        case .trae: return "Trae"
        case .miniMaxHub: return "MiniMax Hub"
        case .xiaoyunque: return "小云雀"
        }
    }

    /// A downloadable metadata catalog can never broaden this boundary.
    public var supportsBackupFirstRecovery: Bool {
        self == .codex || self == .claude
    }
}

public enum AgentArtifactKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case activeSessions
    case archivedSessions
    case backups
    case installerLeftovers
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
        case .installerLeftovers: return "安装包残留"
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

/// Shared per-kind age gates for backup-first mutation. The scanner uses this
/// to emit candidates; the mutation service re-validates the same gate against
/// a freshly captured file identity before anything leaves its original path.
/// A `nil` gate means the kind stays read-only regardless of age.
public enum AgentWorkspaceMutationPolicy {
    public static func minimumSettleInterval(
        for kind: AgentArtifactKind,
        recentInterval: TimeInterval,
        oldInterval: TimeInterval,
        sessionCandidateInterval: TimeInterval
    ) -> TimeInterval? {
        switch kind {
        case .caches, .temporaryFiles, .logs, .installerLeftovers:
            return max(60, recentInterval)
        case .backups, .archivedSessions, .virtualMachines:
            return max(recentInterval, oldInterval)
        case .activeSessions:
            return max(recentInterval, sessionCandidateInterval)
        case .generatedMedia, .memoryAndPlans, .stateAndIndexes, .credentials, .runtime, .unknown:
            return nil
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

    /// 大白话主显示；displayName（技术术语）降级为悬浮说明。
    public var plainDisplayName: String {
        switch self {
        case .protected: return "在用·先别动"
        case .keep: return "建议保留"
        case .review: return "看一眼再定"
        case .regenerable: return "可安全清理"
        case .unknown: return "仅查看"
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

public enum AgentWorkspaceFileIdentityError: LocalizedError, Equatable {
    case missing
    case notRegularFile
    case metadataUnavailable

    public var errorDescription: String? {
        switch self {
        case .missing: return "候选文件已经不存在。"
        case .notRegularFile: return "只允许处理普通文件；目录和符号链接不会进入 Agent 安全处置。"
        case .metadataUnavailable: return "无法读取候选文件的完整身份，操作已停止。"
        }
    }
}

/// Exact scan-time identity used by the GUI-only mutation layer.
/// Paths alone are never sufficient authorization: the mutation service
/// recaptures all values immediately before backup and again before mutation.
public struct AgentWorkspaceFileIdentity: Codable, Equatable, Hashable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let ownerUserID: UInt32
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64

    public init(
        deviceID: UInt64,
        fileID: UInt64,
        ownerUserID: UInt32,
        logicalBytes: Int64,
        allocatedBytes: Int64,
        modificationSeconds: Int64,
        modificationNanoseconds: Int64
    ) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.ownerUserID = ownerUserID
        self.logicalBytes = logicalBytes
        self.allocatedBytes = allocatedBytes
        self.modificationSeconds = modificationSeconds
        self.modificationNanoseconds = modificationNanoseconds
    }

    public static func capture(at url: URL) throws -> Self {
        var value = stat()
        let path = url.standardizedFileURL.path
        guard path.withCString({ lstat($0, &value) }) == 0 else {
            if errno == ENOENT { throw AgentWorkspaceFileIdentityError.missing }
            throw AgentWorkspaceFileIdentityError.metadataUnavailable
        }
        guard value.st_mode & S_IFMT == S_IFREG else {
            throw AgentWorkspaceFileIdentityError.notRegularFile
        }
        return Self(fileStat: value)
    }

    fileprivate init(fileStat: stat) {
        deviceID = UInt64(fileStat.st_dev)
        fileID = UInt64(fileStat.st_ino)
        ownerUserID = fileStat.st_uid
        logicalBytes = max(0, Int64(fileStat.st_size))
        allocatedBytes = max(0, Int64(fileStat.st_blocks) * 512)
        modificationSeconds = Int64(fileStat.st_mtimespec.tv_sec)
        modificationNanoseconds = Int64(fileStat.st_mtimespec.tv_nsec)
    }

    public var modificationDate: Date {
        Date(
            timeIntervalSince1970: TimeInterval(modificationSeconds)
                + TimeInterval(modificationNanoseconds) / 1_000_000_000
        )
    }
}

/// A bounded, file-level action token emitted by the read-only scanner.
/// Eligible kinds and their per-kind age gates live in
/// `AgentWorkspaceMutationPolicy`; the mutation service re-checks the same
/// policy before any file leaves its original path.
public struct AgentWorkspaceActionCandidate: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let provider: AgentWorkspaceProvider
    public let kind: AgentArtifactKind
    public let path: String
    public let identity: AgentWorkspaceFileIdentity
    public let scannedAt: Date

    public init(
        id: String,
        provider: AgentWorkspaceProvider,
        kind: AgentArtifactKind,
        path: String,
        identity: AgentWorkspaceFileIdentity,
        scannedAt: Date
    ) {
        self.id = id
        self.provider = provider
        self.kind = kind
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.identity = identity
        self.scannedAt = scannedAt
    }

    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
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
    public let actionCandidates: [AgentWorkspaceActionCandidate]
    public let actionCandidateLimitReached: Bool
    public let configurationReferenceReport: ModelConfigurationReferenceReport?

    public var actionableBytes: Int64 {
        actionCandidates.saturatingSum(of: \AgentWorkspaceActionCandidate.identity.allocatedBytes)
    }

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
        diagnostic: String?,
        actionCandidates: [AgentWorkspaceActionCandidate] = [],
        actionCandidateLimitReached: Bool = false,
        configurationReferenceReport: ModelConfigurationReferenceReport? = nil
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
        self.actionCandidates = actionCandidates
        self.actionCandidateLimitReached = actionCandidateLimitReached
        self.configurationReferenceReport = configurationReferenceReport
    }

    public func withoutActionCandidates() -> AgentWorkspaceArtifact {
        AgentWorkspaceArtifact(
            id: id,
            provider: provider,
            kind: kind,
            sourcePaths: sourcePaths,
            allocatedBytes: allocatedBytes,
            logicalBytes: logicalBytes,
            fileCount: fileCount,
            directoryCount: directoryCount,
            activeFileCount: activeFileCount,
            recentlyModifiedFileCount: recentlyModifiedFileCount,
            oldFileCount: oldFileCount,
            previewBytes: previewBytes,
            largestFileBytes: largestFileBytes,
            largestFilePath: largestFilePath,
            latestModificationDate: latestModificationDate,
            disposition: disposition,
            protectionReasons: protectionReasons,
            isComplete: isComplete,
            diagnostic: diagnostic,
            actionCandidates: [],
            actionCandidateLimitReached: false,
            configurationReferenceReport: configurationReferenceReport
        )
    }
}

public struct AgentWorkspaceAgentSnapshot: Identifiable, Codable, Equatable, Sendable {
    public let provider: AgentWorkspaceProvider
    public let detected: Bool
    public let artifacts: [AgentWorkspaceArtifact]
    public let diagnostics: [String]
    public let previousAllocatedBytes: Int64?

    public var id: String { provider.rawValue }
    public var allocatedBytes: Int64 { artifacts.saturatingSum(of: \.allocatedBytes) }
    public var logicalBytes: Int64 { artifacts.saturatingSum(of: \.logicalBytes) }
    public var previewBytes: Int64 { artifacts.saturatingSum(of: \.previewBytes) }
    public var fileCount: Int { artifacts.reduce(0) { $0 + $1.fileCount } }
    public var activeFileCount: Int { artifacts.reduce(0) { $0 + $1.activeFileCount } }
    public var isComplete: Bool { diagnostics.isEmpty && artifacts.allSatisfy(\.isComplete) }
    public var allocatedBytesChange: Int64? {
        guard let previousAllocatedBytes else { return nil }
        return allocatedBytes - previousAllocatedBytes
    }

    public init(
        provider: AgentWorkspaceProvider,
        detected: Bool,
        artifacts: [AgentWorkspaceArtifact],
        diagnostics: [String] = [],
        previousAllocatedBytes: Int64? = nil
    ) {
        self.provider = provider
        self.detected = detected
        self.artifacts = artifacts
        self.diagnostics = diagnostics
        self.previousAllocatedBytes = previousAllocatedBytes.map { max(0, $0) }
    }

    public func withoutActionCandidates() -> AgentWorkspaceAgentSnapshot {
        AgentWorkspaceAgentSnapshot(
            provider: provider,
            detected: detected,
            artifacts: artifacts.map { $0.withoutActionCandidates() },
            diagnostics: diagnostics,
            previousAllocatedBytes: previousAllocatedBytes
        )
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
    public var actionCandidates: [AgentWorkspaceActionCandidate] {
        detectedAgents.flatMap(\.artifacts).flatMap(\.actionCandidates)
    }
    public var actionableBytes: Int64 {
        actionCandidates.saturatingSum(of: \AgentWorkspaceActionCandidate.identity.allocatedBytes)
    }
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

    /// Replaces one provider's aggregate row with a freshly scanned detail row.
    /// Other providers remain summary-only and cannot inherit file action tokens.
    public func mergingDetail(
        _ detail: AgentWorkspaceSnapshot,
        for provider: AgentWorkspaceProvider
    ) -> AgentWorkspaceSnapshot {
        guard let replacement = detail.agents.first(where: { $0.provider == provider }) else {
            return self
        }
        let mergedAgents = agents.map { agent in
            agent.provider == provider ? replacement : agent
        }
        let retainedAlerts = alerts.filter { $0.provider != provider }
        let providerAlerts = detail.alerts.filter { $0.provider == provider }
        return AgentWorkspaceSnapshot(
            capturedAt: detail.capturedAt,
            previousCapturedAt: previousCapturedAt,
            agents: mergedAgents,
            alerts: (retainedAlerts + providerAlerts).sorted {
                if $0.level != $1.level { return $0.level > $1.level }
                return $0.id < $1.id
            },
            openFileProbeSucceeded: openFileProbeSucceeded && detail.openFileProbeSucceeded,
            diagnostic: "聚合账本保持不变；已重新验证 \(provider.displayName) 的类别与逐文件处置证据。"
        )
    }

    public func withoutActionCandidates() -> AgentWorkspaceSnapshot {
        AgentWorkspaceSnapshot(
            capturedAt: capturedAt,
            previousCapturedAt: previousCapturedAt,
            agents: agents.map { $0.withoutActionCandidates() },
            alerts: alerts,
            openFileProbeSucceeded: openFileProbeSucceeded,
            diagnostic: diagnostic
        )
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
        public var sessionCandidateInterval: TimeInterval
        public var installerLeftoverMinimumBytes: Int64
        public var largeFileWarningBytes: Int64
        public var largeFileCriticalBytes: Int64
        public var agentSizeWarningBytes: Int64
        public var agentSizeCriticalBytes: Int64
        public var growthWarningBytes: Int64
        public var growthCriticalBytes: Int64
        public var maximumEntriesPerAgent: Int
        public var maximumActionCandidatesPerAgent: Int

        public init(
            recentInterval: TimeInterval = 15 * 60,
            oldInterval: TimeInterval = 30 * 86_400,
            sessionCandidateInterval: TimeInterval = 60 * 86_400,
            installerLeftoverMinimumBytes: Int64 = 16 * 1_024 * 1_024,
            largeFileWarningBytes: Int64 = 256 * 1_024 * 1_024,
            largeFileCriticalBytes: Int64 = 2 * 1_024 * 1_024 * 1_024,
            agentSizeWarningBytes: Int64 = 10 * 1_024 * 1_024 * 1_024,
            agentSizeCriticalBytes: Int64 = 50 * 1_024 * 1_024 * 1_024,
            growthWarningBytes: Int64 = 512 * 1_024 * 1_024,
            growthCriticalBytes: Int64 = 4 * 1_024 * 1_024 * 1_024,
            maximumEntriesPerAgent: Int = 600_000,
            maximumActionCandidatesPerAgent: Int = 5_000
        ) {
            self.recentInterval = max(60, recentInterval)
            self.oldInterval = max(recentInterval, oldInterval)
            self.sessionCandidateInterval = max(recentInterval, sessionCandidateInterval)
            self.installerLeftoverMinimumBytes = max(0, installerLeftoverMinimumBytes)
            self.largeFileWarningBytes = max(1, largeFileWarningBytes)
            self.largeFileCriticalBytes = max(largeFileWarningBytes, largeFileCriticalBytes)
            self.agentSizeWarningBytes = max(1, agentSizeWarningBytes)
            self.agentSizeCriticalBytes = max(agentSizeWarningBytes, agentSizeCriticalBytes)
            self.growthWarningBytes = max(1, growthWarningBytes)
            self.growthCriticalBytes = max(growthWarningBytes, growthCriticalBytes)
            self.maximumEntriesPerAgent = max(1_000, maximumEntriesPerAgent)
            self.maximumActionCandidatesPerAgent = max(100, maximumActionCandidatesPerAgent)
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
        var actionCandidates: [AgentWorkspaceActionCandidate] = []
        var actionCandidateLimitReached = false

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
            actionCandidates.append(contentsOf: other.actionCandidates)
            actionCandidateLimitReached = actionCandidateLimitReached || other.actionCandidateLimitReached
        }

        private static func add(_ lhs: Int64, _ rhs: Int64) -> Int64 {
            guard rhs > 0 else { return lhs }
            return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
        }
    }

    /// Per-kind walk output. Most files stay in their group kind; installer
    /// archives with an extracted sibling are reclassified into
    /// `.installerLeftovers` so a keep-tier group (for example a VM bundle)
    /// can still shed its dead staging payload.
    private struct WalkResult: Sendable {
        var byKind: [AgentArtifactKind: WalkMetrics] = [:]
        var installerLeftoverDirectories: Set<String> = []

        static let maximumInstallerLeftoverDirectories = 16

        mutating func absorb(_ file: FileMetric) {
            byKind[file.kind, default: WalkMetrics()].merge(file.metrics)
            if file.kind == .installerLeftovers,
               installerLeftoverDirectories.count < Self.maximumInstallerLeftoverDirectories {
                installerLeftoverDirectories.insert(
                    URL(fileURLWithPath: file.path).deletingLastPathComponent().path
                )
            }
        }

        mutating func merge(_ other: Self) {
            for (kind, metrics) in other.byKind {
                byKind[kind, default: WalkMetrics()].merge(metrics)
            }
            for directory in other.installerLeftoverDirectories
            where installerLeftoverDirectories.count < Self.maximumInstallerLeftoverDirectories {
                installerLeftoverDirectories.insert(directory)
            }
        }
    }

    /// One scanned file plus the kind it was finally classified as.
    private struct FileMetric: Sendable {
        var kind: AgentArtifactKind
        var metrics: WalkMetrics
        var path: String
    }

    /// Kinds whose archive-shaped files may be reclassified as installer
    /// leftovers. Sessions, generated media, memory, state and credentials
    /// never change kind: a misleading name must not grant mutation rights.
    private static let installerLeftoverSourceKinds: Set<AgentArtifactKind> = [
        .virtualMachines, .runtime, .caches, .temporaryFiles, .logs, .backups, .unknown
    ]

    private static let installerArchiveSuffixes = [
        ".tar.gz", ".tar.zst", ".tar.xz", ".tgz", ".zip", ".zst", ".dmg", ".pkg", ".tar", ".gz"
    ]

    /// An archive counts as a leftover only when the same directory already
    /// holds the payload it unpacks to (for example `rootfs.img` sitting next
    /// to `rootfs.img.zst`). Without that sibling the archive may be the only
    /// copy and stays in its original kind.
    private static func installerLeftoverSiblingExists(
        for path: String,
        allocatedBytes: Int64,
        configuration: Configuration
    ) -> Bool {
        guard allocatedBytes >= configuration.installerLeftoverMinimumBytes else { return false }
        let lowercased = path.lowercased()
        guard let suffix = installerArchiveSuffixes.first(where: { lowercased.hasSuffix($0) }) else {
            return false
        }
        let sibling = String(path.dropLast(suffix.count))
        guard !sibling.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: sibling)
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
        catalog: AgentRuleCatalog = .builtIn,
        providers: [AgentWorkspaceProvider]? = nil,
        actionCandidateProviders: Set<AgentWorkspaceProvider>? = nil,
        now: Date = Date()
    ) async throws -> AgentWorkspaceScanResult {
        try catalog.validate()
        let requestedProviders = providers ?? AgentWorkspaceProvider.allCases
        let uniqueProviders = requestedProviders.reduce(into: [AgentWorkspaceProvider]()) { result, provider in
            if !result.contains(provider) { result.append(provider) }
        }
        let candidateProviders = actionCandidateProviders
            ?? Set(uniqueProviders.filter(\.supportsBackupFirstRecovery))
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
            configuration: configuration,
            catalog: catalog,
            providers: uniqueProviders,
            actionCandidateProviders: candidateProviders
        )
    }

    private static func scanMetadata(
        homeDirectory: URL,
        previous: AgentWorkspaceObservation?,
        openFileProbe: AgentWorkspaceOpenFileProbe.Result,
        now: Date,
        configuration: Configuration,
        catalog: AgentRuleCatalog,
        providers: [AgentWorkspaceProvider],
        actionCandidateProviders: Set<AgentWorkspaceProvider>
    ) -> AgentWorkspaceScanResult {
        let normalizedHome = homeDirectory.standardizedFileURL
        let roots = Dictionary(uniqueKeysWithValues: catalog.providers.map { rule in
            (rule.provider, rule.resolvedRoots(homeDirectory: normalizedHome))
        })
        let openFiles = openFileProbe.records.filter { record in
            roots.values.flatMap { $0 }.contains { root in
                Self.path(record.path, isInside: root.url.path)
            }
        }
        let openPathSet = Set(openFiles.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })

        let agents = providers.map { provider in
            scanAgent(
                provider: provider,
                roots: roots[provider] ?? [],
                rule: catalog.rule(for: provider),
                openPaths: openPathSet,
                activityProbeSucceeded: openFileProbe.succeeded,
                now: now,
                configuration: configuration,
                collectActionCandidates: actionCandidateProviders.contains(provider),
                previousAllocatedBytes: previous?.allocatedBytesByAgent[provider.rawValue]
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
            diagnostic = "未在已验证默认位置发现 Agent 本机数据；未验证适配器不会猜测路径。"
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
        roots: [(url: URL, defaultKind: AgentArtifactKind)],
        rule: AgentProviderRule?,
        openPaths: Set<String>,
        activityProbeSucceeded: Bool,
        now: Date,
        configuration: Configuration,
        collectActionCandidates: Bool,
        previousAllocatedBytes: Int64?
    ) -> AgentWorkspaceAgentSnapshot {
        let fileManager = FileManager.default
        let existingRoots = roots.filter { root in
            var isDirectory = ObjCBool(false)
            return fileManager.fileExists(atPath: root.url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
        guard !existingRoots.isEmpty else {
            return AgentWorkspaceAgentSnapshot(
                provider: provider,
                detected: false,
                artifacts: [],
                previousAllocatedBytes: previousAllocatedBytes
            )
        }

        var groupedURLs: [AgentArtifactKind: [URL]] = [:]
        var diagnostics: [String] = []
        for root in existingRoots {
            do {
                let children = try fileManager.contentsOfDirectory(
                    at: root.url,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                if children.isEmpty {
                    groupedURLs[root.defaultKind, default: []].append(root.url)
                } else {
                    for child in children {
                        let kind = rule?.classify(
                            name: child.lastPathComponent,
                            defaultKind: root.defaultKind
                        ) ?? root.defaultKind
                        groupedURLs[kind, default: []].append(child)
                    }
                }
            } catch {
                diagnostics.append("无法列出 \(root.url.path)：\(error.localizedDescription)")
            }
        }

        var remainingEntries = configuration.maximumEntriesPerAgent
        var remainingActionCandidates = configuration.maximumActionCandidatesPerAgent
        var seenFiles = Set<FileIdentity>()
        var metricsByKind: [AgentArtifactKind: WalkMetrics] = [:]
        var installerLeftoverDirectories: Set<String> = []
        let eligibleCandidateKinds: Set<AgentArtifactKind> = Set(AgentArtifactKind.allCases.filter {
            AgentWorkspaceMutationPolicy.minimumSettleInterval(
                for: $0,
                recentInterval: configuration.recentInterval,
                oldInterval: configuration.oldInterval,
                sessionCandidateInterval: configuration.sessionCandidateInterval
            ) != nil
        })
        // Virtual machine bundles are only disposable as a unit: a single old
        // file next to a live rootfs must never become a candidate. VM files
        // collect candidates in a second pass, only after the whole group
        // proves fully settled.
        let firstPassCandidateKinds = collectActionCandidates
            ? eligibleCandidateKinds.subtracting([.virtualMachines])
            : []

        let groupedKinds = AgentArtifactKind.allCases.filter { groupedURLs[$0]?.isEmpty == false }
        for kind in groupedKinds {
            let urls = groupedURLs[kind] ?? []
            metricsByKind[kind] = WalkMetrics()
            for url in urls.sorted(by: { $0.path < $1.path }) {
                guard remainingEntries > 0 else {
                    metricsByKind[kind]?.isComplete = false
                    metricsByKind[kind]?.diagnostics.append("已达到单个 Agent 的元数据扫描上限。")
                    break
                }
                let value = walk(
                    url: url,
                    provider: provider,
                    kind: kind,
                    openPaths: openPaths,
                    now: now,
                    configuration: configuration,
                    candidateKinds: firstPassCandidateKinds,
                    remainingEntries: &remainingEntries,
                    remainingActionCandidates: &remainingActionCandidates,
                    seenFiles: &seenFiles
                )
                for (fileKind, part) in value.byKind {
                    metricsByKind[fileKind, default: WalkMetrics()].merge(part)
                }
                for directory in value.installerLeftoverDirectories
                where installerLeftoverDirectories.count < WalkResult.maximumInstallerLeftoverDirectories {
                    installerLeftoverDirectories.insert(directory)
                }
            }
        }

        let virtualMachineGroupIsStale = metricsByKind[.virtualMachines].map {
            Self.isVirtualMachineGroupStale($0, now: now, configuration: configuration)
        } ?? false
        if collectActionCandidates, virtualMachineGroupIsStale {
            for url in (groupedURLs[.virtualMachines] ?? []).sorted(by: { $0.path < $1.path }) {
                var passEntries = configuration.maximumEntriesPerAgent
                var passSeen = Set<FileIdentity>()
                let value = walk(
                    url: url,
                    provider: provider,
                    kind: .virtualMachines,
                    openPaths: openPaths,
                    now: now,
                    configuration: configuration,
                    candidateKinds: [.virtualMachines],
                    remainingEntries: &passEntries,
                    remainingActionCandidates: &remainingActionCandidates,
                    seenFiles: &passSeen
                )
                for (fileKind, part) in value.byKind {
                    metricsByKind[fileKind]?.actionCandidates.append(contentsOf: part.actionCandidates)
                    if part.actionCandidateLimitReached {
                        metricsByKind[fileKind]?.actionCandidateLimitReached = true
                    }
                }
            }
        }

        let configurationInspectionKinds: Set<AgentArtifactKind> = [.runtime, .caches, .stateAndIndexes, .unknown]
        let configurationInspector = ModelConfigurationReferenceInspector()
        let artifacts = AgentArtifactKind.allCases.compactMap { kind -> AgentWorkspaceArtifact? in
            guard let combined = metricsByKind[kind] else { return nil }
            let urls = groupedURLs[kind] ?? []
            let sourcePaths: [String] = kind == .installerLeftovers
                ? installerLeftoverDirectories.sorted()
                : urls.map { $0.standardizedFileURL.path }.sorted()
            let configurationReferenceReport: ModelConfigurationReferenceReport? = {
                guard configurationInspectionKinds.contains(kind), !urls.isEmpty else { return nil }
                let reports = urls.map { configurationInspector.inspect(root: $0) }
                return ModelConfigurationReferenceReport(
                    rootURL: urls.count == 1 ? urls[0] : existingRoots[0].url,
                    scannedConfigurationCount: reports.reduce(0) { $0 + $1.scannedConfigurationCount },
                    references: reports.flatMap(\.references),
                    issues: reports.flatMap(\.issues),
                    isComplete: reports.allSatisfy(\.isComplete)
                )
            }()
            let configurationRequiresReview = configurationReferenceReport?.requiresReview ?? false
            let protectedByActivity = !activityProbeSucceeded
                || combined.activeFileCount > 0
                || combined.recentlyModifiedFileCount > 0
            var disposition = disposition(
                kind: kind,
                protectedByActivity: protectedByActivity,
                isComplete: combined.isComplete,
                isStaleGroup: kind == .virtualMachines && virtualMachineGroupIsStale
            )
            if configurationRequiresReview, disposition == .regenerable {
                disposition = .review
            }
            let previewBytes: Int64
            if !combined.isComplete || !activityProbeSucceeded || !provider.supportsBackupFirstRecovery || configurationRequiresReview {
                previewBytes = 0
            } else {
                switch kind {
                case .caches, .temporaryFiles, .logs, .installerLeftovers:
                    previewBytes = combined.settledBytes
                case .activeSessions, .archivedSessions, .backups, .generatedMedia:
                    previewBytes = combined.oldBytes
                case .virtualMachines:
                    previewBytes = virtualMachineGroupIsStale ? combined.oldBytes : 0
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
            if kind == .installerLeftovers {
                protectionReasons.append("存在同名已解压内容，压缩包本身可复核回收")
            }
            if kind == .virtualMachines && virtualMachineGroupIsStale {
                let days = Int(configuration.oldInterval / 86_400)
                protectionReasons.append("整组超过 \(days) 天未写入；如不使用沙箱或隔离会话可复核回收")
            }
            if kind == .generatedMedia {
                protectionReasons.append("生成内容属于产出资产，只复核位置，不提供执行")
            }
            if !combined.isComplete {
                protectionReasons.append("扫描不完整，默认禁止进入回收预览")
            }
            if configurationRequiresReview, let configurationReferenceReport {
                protectionReasons.append(configurationReferenceReport.summary)
            }
            if !provider.supportsBackupFirstRecovery {
                protectionReasons.append("当前版本为只读适配：不会修改该 Agent 的文件或私有索引")
            }
            let actionCandidates = combined.isComplete
                && activityProbeSucceeded
                && provider.supportsBackupFirstRecovery
                && !configurationRequiresReview
                ? combined.actionCandidates
                : []
            return AgentWorkspaceArtifact(
                id: "\(provider.rawValue):\(kind.rawValue)",
                provider: provider,
                kind: kind,
                sourcePaths: sourcePaths,
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
                isComplete: combined.isComplete && (configurationReferenceReport?.isComplete ?? true),
                diagnostic: combined.diagnostics.isEmpty
                    ? nil
                    : Array(Set(combined.diagnostics)).sorted().joined(separator: " "),
                actionCandidates: actionCandidates,
                actionCandidateLimitReached: configurationRequiresReview ? false : combined.actionCandidateLimitReached,
                configurationReferenceReport: configurationReferenceReport
            )
        }
        return AgentWorkspaceAgentSnapshot(
            provider: provider,
            detected: true,
            artifacts: artifacts.sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.allocatedBytes > $1.allocatedBytes
            },
            diagnostics: diagnostics,
            previousAllocatedBytes: previousAllocatedBytes
        )
    }

    private static func walk(
        url: URL,
        provider: AgentWorkspaceProvider,
        kind: AgentArtifactKind,
        openPaths: Set<String>,
        now: Date,
        configuration: Configuration,
        candidateKinds: Set<AgentArtifactKind>,
        remainingEntries: inout Int,
        remainingActionCandidates: inout Int,
        seenFiles: inout Set<FileIdentity>
    ) -> WalkResult {
        let path = url.standardizedFileURL.path
        var rootStat = stat()
        guard path.withCString({ lstat($0, &rootStat) }) == 0 else {
            var metrics = WalkMetrics()
            metrics.isComplete = false
            metrics.diagnostics.append("无法读取元数据：\(path)")
            var result = WalkResult()
            result.byKind[kind] = metrics
            return result
        }
        let type = rootStat.st_mode & S_IFMT
        if type == S_IFREG {
            remainingEntries -= 1
            let identity = FileIdentity(device: UInt64(rootStat.st_dev), inode: UInt64(rootStat.st_ino))
            guard seenFiles.insert(identity).inserted else { return WalkResult() }
            var result = WalkResult()
            result.absorb(metrics(
                for: rootStat,
                path: path,
                provider: provider,
                kind: kind,
                openPaths: openPaths,
                now: now,
                configuration: configuration,
                candidateKinds: candidateKinds,
                remainingActionCandidates: &remainingActionCandidates
            ))
            return result
        }
        guard type == S_IFDIR else { return WalkResult() }

        guard let rootCString = strdup(path) else {
            var metrics = WalkMetrics()
            metrics.isComplete = false
            metrics.diagnostics.append("无法准备目录扫描：\(path)")
            var result = WalkResult()
            result.byKind[kind] = metrics
            return result
        }
        defer { free(rootCString) }
        let paths = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        paths.initialize(repeating: nil, count: 2)
        paths[0] = rootCString
        defer { paths.deinitialize(count: 2); paths.deallocate() }
        guard let stream = fts_open(UnsafePointer(paths), FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            var metrics = WalkMetrics()
            metrics.isComplete = false
            metrics.diagnostics.append("无法遍历目录：\(path)")
            var result = WalkResult()
            result.byKind[kind] = metrics
            return result
        }
        defer { fts_close(stream) }

        var result = WalkResult()
        while !Task.isCancelled, remainingEntries > 0, let entry = fts_read(stream) {
            if entry.pointee.fts_level == FTS_ROOTLEVEL { continue }
            remainingEntries -= 1
            let info = Int32(entry.pointee.fts_info)
            switch info {
            case FTS_D:
                result.byKind[kind, default: WalkMetrics()].directoryCount += 1
            case FTS_F:
                guard let statPointer = entry.pointee.fts_statp else { continue }
                let fileStat = statPointer.pointee
                let identity = FileIdentity(device: UInt64(fileStat.st_dev), inode: UInt64(fileStat.st_ino))
                guard seenFiles.insert(identity).inserted else { continue }
                let filePath = String(cString: entry.pointee.fts_path)
                result.absorb(metrics(
                    for: fileStat,
                    path: filePath,
                    provider: provider,
                    kind: kind,
                    openPaths: openPaths,
                    now: now,
                    configuration: configuration,
                    candidateKinds: candidateKinds,
                    remainingActionCandidates: &remainingActionCandidates
                ))
            case FTS_DNR, FTS_ERR, FTS_NS:
                result.byKind[kind, default: WalkMetrics()].isComplete = false
                result.byKind[kind]?.diagnostics.append("部分路径无法读取：\(String(cString: entry.pointee.fts_path))")
            default:
                break
            }
        }
        if remainingEntries == 0 {
            result.byKind[kind, default: WalkMetrics()].isComplete = false
            result.byKind[kind]?.diagnostics.append("已达到单个 Agent 的元数据扫描上限。")
        }
        if Task.isCancelled {
            result.byKind[kind, default: WalkMetrics()].isComplete = false
            result.byKind[kind]?.diagnostics.append("扫描已取消。")
        }
        return result
    }

    private static func metrics(
        for fileStat: stat,
        path: String,
        provider: AgentWorkspaceProvider,
        kind: AgentArtifactKind,
        openPaths: Set<String>,
        now: Date,
        configuration: Configuration,
        candidateKinds: Set<AgentArtifactKind>,
        remainingActionCandidates: inout Int
    ) -> FileMetric {
        let allocated = max(0, Int64(fileStat.st_blocks) * 512)
        let logical = max(0, Int64(fileStat.st_size))
        let modified = Date(
            timeIntervalSince1970: TimeInterval(fileStat.st_mtimespec.tv_sec)
                + TimeInterval(fileStat.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        let age = max(0, now.timeIntervalSince(modified))
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let isActive = openPaths.contains(normalizedPath)
        let effectiveKind: AgentArtifactKind
        if installerLeftoverSourceKinds.contains(kind),
           age > configuration.recentInterval,
           installerLeftoverSiblingExists(
               for: normalizedPath,
               allocatedBytes: allocated,
               configuration: configuration
           ) {
            effectiveKind = .installerLeftovers
        } else {
            effectiveKind = kind
        }
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
        if candidateKinds.contains(effectiveKind),
           provider.supportsBackupFirstRecovery,
           !isActive,
           let minimumAge = AgentWorkspaceMutationPolicy.minimumSettleInterval(
               for: effectiveKind,
               recentInterval: configuration.recentInterval,
               oldInterval: configuration.oldInterval,
               sessionCandidateInterval: configuration.sessionCandidateInterval
           ),
           age > minimumAge {
            if remainingActionCandidates > 0 {
                let identity = AgentWorkspaceFileIdentity(fileStat: fileStat)
                result.actionCandidates = [AgentWorkspaceActionCandidate(
                    id: "\(provider.rawValue):\(effectiveKind.rawValue):\(identity.deviceID):\(identity.fileID)",
                    provider: provider,
                    kind: effectiveKind,
                    path: normalizedPath,
                    identity: identity,
                    scannedAt: now
                )]
                remainingActionCandidates -= 1
            } else {
                result.actionCandidateLimitReached = true
            }
        }
        return FileMetric(kind: effectiveKind, metrics: result, path: normalizedPath)
    }

    /// A VM bundle counts as stale only when nothing in the group has been
    /// touched for the full old-interval: files like `efivars.fd` keep their
    /// creation mtime even in daily-used bundles, so per-file age alone would
    /// peel pieces off a live VM.
    private static func isVirtualMachineGroupStale(
        _ metrics: WalkMetrics,
        now: Date,
        configuration: Configuration
    ) -> Bool {
        guard metrics.isComplete,
              metrics.fileCount > 0,
              metrics.activeFileCount == 0,
              metrics.recentlyModifiedFileCount == 0,
              let latest = metrics.latestModificationDate else { return false }
        return now.timeIntervalSince(latest) >= configuration.oldInterval
    }

    private static func disposition(
        kind: AgentArtifactKind,
        protectedByActivity: Bool,
        isComplete: Bool,
        isStaleGroup: Bool = false
    ) -> AgentArtifactDisposition {
        guard isComplete else { return .protected }
        guard !protectedByActivity else { return .protected }
        switch kind {
        case .credentials, .stateAndIndexes, .memoryAndPlans, .runtime:
            return .keep
        case .virtualMachines:
            return isStaleGroup ? .review : .keep
        case .caches, .temporaryFiles, .logs, .installerLeftovers:
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
                    diagnostic: "无法读取当前用户的打开文件表。"
                )
            }
            return Result(
                records: Self.parseLsofFieldOutput(command.standardOutput),
                succeeded: true,
                diagnostic: "已读取当前用户的打开文件表。"
            )
        } catch {
            return Result(
                records: [],
                succeeded: false,
                diagnostic: "无法读取当前用户的打开文件表：\(error.localizedDescription)"
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
