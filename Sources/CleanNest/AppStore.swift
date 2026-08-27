import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement
import CleanNestCore
import CleanNestMutation

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "总览"
    case cleanup = "清理空间"
    case applications = "应用卸载"
    case analyze = "磁盘浏览"
    case status = "系统状态"
    case maintenance = "系统维护"
    case agentWorkspace = "Agent 工作区"
    case models = "本地模型"
    case evolution = "本机学习"
    case activity = "活动记录"
    case settings = "设置"

    var id: String { rawValue }
    var displayName: String { CNL10n.string(rawValue) }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cleanup: return "sparkles"
        case .applications: return "app.dashed"
        case .analyze: return "chart.pie"
        case .status: return "waveform.path.ecg"
        case .maintenance: return "wrench.and.screwdriver"
        case .agentWorkspace: return "folder.badge.gearshape"
        case .models: return "rectangle.stack.badge.play"
        case .evolution: return "sparkles.rectangle.stack"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    static let spaceItems: [SidebarItem] = [.cleanup, .applications, .analyze]
    static let systemItems: [SidebarItem] = [.status, .maintenance]
    static let intelligenceItems: [SidebarItem] = [.agentWorkspace, .models, .evolution]

    var lifecycleSurface: CleanNestSurface {
        switch self {
        case .overview: return .overview
        case .cleanup: return .cleanup
        case .applications: return .applications
        case .analyze: return .disk
        case .status: return .systemStatus
        case .maintenance: return .maintenance
        case .agentWorkspace: return .agentWorkspace
        case .models: return .localModels
        case .evolution: return .learning
        case .activity: return .activity
        case .settings: return .settings
        }
    }
}

enum OperationPhase: Equatable {
    case idle
    case checking
    case scanning(String)
    case executing(String)
    case success(String)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .checking, .scanning, .executing: return true
        default: return false
        }
    }

    var message: String? {
        switch self {
        case .idle: return nil
        case .checking: return "正在检查本地引擎…"
        case .scanning(let value), .executing(let value), .success(let value), .failed(let value): return value
        }
    }
}

enum LocalAIServiceState: Equatable {
    case disabled
    case unchecked
    case checking
    case starting
    case stopping
    case ready(modelID: String)
    case unavailable(String)

    var isBusy: Bool {
        switch self {
        case .checking, .starting, .stopping: return true
        default: return false
        }
    }
}

enum CleanupAIPhase: Equatable {
    case idle
    case analyzing
    case completed
    case failed(String)

    var isBusy: Bool { self == .analyzing }
}

enum DiskAIPhase: Equatable {
    case idle
    case collecting
    case analyzing
    case completed
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .collecting, .analyzing: return true
        default: return false
        }
    }
}

enum LocalAIBenchmarkPhase: Equatable {
    case idle
    case running
    case completed
    case failed(String)

    var isRunning: Bool { self == .running }
}

enum AgentWorkspaceScanPhase: Equatable {
    case idle
    case scanning
    case ready
    case failed(String)

    var isScanning: Bool { self == .scanning }
}

enum AgentWorkspaceRecoveryPhase: Equatable {
    case idle
    case creatingBackup
    case restoring(UUID)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .creatingBackup, .restoring: return true
        case .idle, .failed: return false
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var selection: SidebarItem? = .overview
    @Published var phase: OperationPhase = .idle
    @Published var engine: EngineInstallation?
    @Published var engineDiagnostic = "尚未检查"
    @Published var systemSnapshot: SystemSnapshot?
    @Published private(set) var memoryAnalysis: MemoryAnalysis?
    @Published private(set) var memoryProcesses: [MemoryProcessSnapshot] = []
    @Published private(set) var terminatingMemoryProcessID: String?
    @Published private(set) var forceTerminationProcessID: String?
    @Published private(set) var memoryProcessMessage: String?
    @Published private(set) var memoryProcessMessageIsWarning = false
    @Published private(set) var batteryProbeResult = BatteryProbeResult(
        availability: .unreadable,
        level: nil,
        status: "等待检测",
        detail: "尚未读取系统电源接口。"
    )
    @Published var diskTotalBytes: Int64 = 0
    @Published var diskFreeBytes: Int64 = 0
    @Published private(set) var metricHistory: [MetricSample] = []
    @Published var metricHistoryRange: MetricHistoryRange = .hour
    @Published private(set) var metricsDiagnostic = "正在准备本机历史记录…"
    @Published private(set) var metricsRetentionDays = 30
    @Published private(set) var metricsSamplingIsActive = false
    @Published private(set) var menuBarConfiguration = MenuBarMonitorConfiguration.defaults
    @Published private(set) var nativeMonitorSample: NativeMonitorSample?
    private(set) var nativeMonitorHistory: [NativeMonitorSample] = []
    @Published private(set) var nativeMonitorIsActive = false
    @Published private(set) var nativeMonitorDiagnostic = "正在准备菜单栏实时监测…"
    @Published private(set) var menuBarVisibilityDiagnostic = "正在确认菜单栏显示状态…"
    @Published private(set) var globalHotKeyDiagnostic = "正在注册 ⌘⌥M…"
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginRequiresApproval = false
    @Published private(set) var launchAtLoginDiagnostic = "正在读取登录启动状态…"

    @Published var cleanupCandidates: [CleanupCandidate] = []
    @Published var selectedCleanupIDs = Set<String>()
    @Published var includeApplicationCaches = false
    @Published var includeMediaAndDuplicates = true
    @Published private(set) var cleanupScanInsights = CleanupScanInsights.empty
    @Published private(set) var cleanupScanIncludedMediaAndDuplicates = false
    @Published var developerMode = true
    @Published var cleanupHasScanned = false
    @Published private(set) var cleanupScanIsActive = false
    @Published private(set) var mountedInstallerVolumes: [MountedInstallerVolume] = []
    @Published private(set) var ejectingMountedInstallerID: String?
    @Published private(set) var mountedInstallerMessage: String?
    @Published private(set) var mountedInstallerMessageIsWarning = false
    @Published var localAIEnabled = true
    @Published var localAIEndpoint = "http://127.0.0.1:8080/v1"
    @Published var localAIServiceModelID = ""
    @Published var localAIModelPath = ""
    @Published var localAIExecutablePath = ""
    @Published private(set) var localAIAvailableModels: [LocalModelDescriptor] = []
    @Published private(set) var localAIAvailableServiceModelIDs: [String] = []
    @Published private(set) var localAIDefaultServiceModelID: String?
    @Published private(set) var localAIModelCatalogIsRefreshing = false
    @Published private(set) var localAIModelCatalogDiagnostic = "尚未扫描本机模型"
    @Published private(set) var localAIServiceState: LocalAIServiceState = .unchecked
    @Published private(set) var localAIProcessOwned = false
    @Published private(set) var cleanupAIPhase: CleanupAIPhase = .idle
    @Published private(set) var cleanupAIAnalysis: CleanupAIAnalysis?
    @Published private(set) var cleanupAIFeedback: Bool?
    @Published private(set) var localAIDiagnostic = "尚未检测"
    @Published private(set) var localAIConfigurationError: String?
    @Published private(set) var localAIProbeLatencyMilliseconds: Double?
    @Published private(set) var localAIBenchmarkPhase: LocalAIBenchmarkPhase = .idle
    @Published private(set) var localAIBenchmarkResult: LocalAIBenchmarkResult?
    @Published private(set) var localModelRuntimeSnapshot = LocalModelRuntimeSnapshot.empty
    @Published private(set) var localModelDiscoveryPhase: LocalModelRuntimePhase = .unknown
    @Published private(set) var localModelDiscoveryIsRunning = false
    @Published private(set) var localModelRuntimeDiagnostic = "尚未检查本地模型运行时"
    @Published private(set) var localModelMenuBarEnabled = true
    @Published private(set) var stoppingExternalLocalModelRuntimeID: String?
    @Published private(set) var externalLocalModelStopMessage: String?
    @Published private(set) var externalLocalModelStopMessageIsWarning = false
    @Published private(set) var externalLocalModelForceCandidateID: String?

    @Published var applications: [InstalledApplication] = []
    @Published var applicationSearch = ""
    @Published var selectedApplication: InstalledApplication?
    @Published var selectedApplicationLeftovers: [CleanupCandidate] = []
    @Published var applicationsHaveScanned = false

    @Published var diskReport: DiskReport?
    @Published var diskRoot = FileManager.default.homeDirectoryForCurrentUser
    @Published var diskHasScanned = false
    @Published private(set) var diskScanProgress: DiskScanProgress?
    @Published private(set) var diskPartialReport: DiskReport?
    @Published private(set) var diskScanCacheHitCount = 0
    @Published private(set) var diskScanScannedCount = 0
    @Published private(set) var diskScanElapsedSeconds: Double?
    @Published private(set) var diskScanCompletedAt: Date?
    @Published private(set) var diskEvidenceProgress: DiskEvidenceProgress?
    @Published private(set) var diskEvidenceReport: DiskEvidenceReport?
    @Published private(set) var diskManualDecisions = DiskManualDecisionStore()
    @Published private(set) var diskAIPhase: DiskAIPhase = .idle
    @Published private(set) var diskAIAnalysis: DiskAIAnalysis?
    @Published private(set) var diskAIFeedback: Bool?
    @Published private(set) var diskAIChildContexts: [String: DiskAIChildContext] = [:]
    @Published private(set) var fullDiskAccessProbeResult: FullDiskAccessProbeResult = .indeterminate
    @Published private(set) var fullDiskAccessProbeIsRunning = false
    @Published private(set) var waitingForFullDiskAccessReturn = false
    @Published private(set) var diskPrivacyBlockMessage: String?

    @Published var activities: [ActivityEntry] = []
    @Published private(set) var evolutionMemory = EvolutionMemory()
    let agentWorkspaceState = AgentWorkspacePresentationState()

    private(set) var agentWorkspaceSummary: AgentWorkspaceSummary? {
        get { agentWorkspaceState.cachedSummary }
        set { agentWorkspaceState.cachedSummary = newValue }
    }
    private(set) var agentWorkspaceSnapshot: AgentWorkspaceSnapshot? {
        get { agentWorkspaceState.snapshot }
        set { agentWorkspaceState.snapshot = newValue }
    }
    private(set) var agentWorkspacePhase: AgentWorkspaceScanPhase {
        get { agentWorkspaceState.phase }
        set { agentWorkspaceState.phase = newValue }
    }
    private(set) var agentWorkspaceDiagnostic: String {
        get { agentWorkspaceState.diagnostic }
        set { agentWorkspaceState.diagnostic = newValue }
    }
    private(set) var selectedAgentWorkspaceCandidateIDs: Set<String> {
        get { agentWorkspaceState.selectedCandidateIDs }
        set { agentWorkspaceState.selectedCandidateIDs = newValue }
    }
    private(set) var agentWorkspaceRecoveryRecords: [AgentWorkspaceRecoveryRecord] {
        get { agentWorkspaceState.recoveryRecords }
        set { agentWorkspaceState.recoveryRecords = newValue }
    }
    private(set) var agentWorkspaceRecoveryPhase: AgentWorkspaceRecoveryPhase {
        get { agentWorkspaceState.recoveryPhase }
        set { agentWorkspaceState.recoveryPhase = newValue }
    }
    private(set) var agentWorkspaceRecoveryMessage: String? {
        get { agentWorkspaceState.recoveryMessage }
        set { agentWorkspaceState.recoveryMessage = newValue }
    }
    private(set) var agentWorkspaceRecoveryMessageIsWarning: Bool {
        get { agentWorkspaceState.recoveryMessageIsWarning }
        set { agentWorkspaceState.recoveryMessageIsWarning = newValue }
    }
    private(set) var agentRuleCatalog: AgentRuleCatalog {
        get { agentWorkspaceState.ruleCatalog }
        set { agentWorkspaceState.ruleCatalog = newValue }
    }
    private(set) var agentRuleCatalogSource: AgentRuleCatalogSource {
        get { agentWorkspaceState.ruleCatalogSource }
        set { agentWorkspaceState.ruleCatalogSource = newValue }
    }
    private(set) var agentRuleCatalogDiagnostic: String {
        get { agentWorkspaceState.ruleCatalogDiagnostic }
        set { agentWorkspaceState.ruleCatalogDiagnostic = newValue }
    }
    private(set) var agentDependencyGraph: AgentDependencyGraphSnapshot {
        get { agentWorkspaceState.dependencyGraph }
        set { agentWorkspaceState.dependencyGraph = newValue }
    }
    private(set) var agentDependencyGraphIsRefreshing: Bool {
        get { agentWorkspaceState.dependencyGraphIsRefreshing }
        set { agentWorkspaceState.dependencyGraphIsRefreshing = newValue }
    }
    private(set) var nativeDeveloperStorageSnapshot: NativeDeveloperStorageSnapshot? {
        get { agentWorkspaceState.nativeDeveloperStorageSnapshot }
        set { agentWorkspaceState.nativeDeveloperStorageSnapshot = newValue }
    }
    private(set) var nativeDeveloperStorageIsRefreshing: Bool {
        get { agentWorkspaceState.nativeDeveloperStorageIsRefreshing }
        set { agentWorkspaceState.nativeDeveloperStorageIsRefreshing = newValue }
    }
    private(set) var nativeDeveloperStorageActionTool: NativeDeveloperStorageTool? {
        get { agentWorkspaceState.nativeDeveloperStorageActionTool }
        set { agentWorkspaceState.nativeDeveloperStorageActionTool = newValue }
    }
    private(set) var nativeDeveloperStorageMessage: String? {
        get { agentWorkspaceState.nativeDeveloperStorageMessage }
        set { agentWorkspaceState.nativeDeveloperStorageMessage = newValue }
    }
    private(set) var nativeDeveloperStorageMessageIsWarning: Bool {
        get { agentWorkspaceState.nativeDeveloperStorageMessageIsWarning }
        set { agentWorkspaceState.nativeDeveloperStorageMessageIsWarning = newValue }
    }
    private(set) var nativeGitRepository: URL? {
        get { agentWorkspaceState.nativeGitRepository }
        set { agentWorkspaceState.nativeGitRepository = newValue }
    }
    @Published var customEnginePath = ""
    @Published var lastTechnicalDetail = ""
    @Published var showingTechnicalDetail = false
    @Published var showingUpdateChecker = false
    @Published private(set) var appUpdateState: AppUpdateState = .idle

    let demoMode: Bool

    private let commandRunner = CommandRunner()
    private let applicationScanner = ApplicationScanner()
    private let scannerServiceClient = ScannerServiceClient()
    private let agentWorkspaceScannerServiceClient = ScannerServiceClient()
    private let agentWorkspaceRecoveryService = AgentWorkspaceRecoveryService()
    private let agentRuleCatalogStore = AgentRuleCatalogStore()
    private let agentDependencyGraphBuilder = AgentDependencyGraphBuilder()
    private let nativeDeveloperStorageInspector = NativeDeveloperStorageInspector()
    private let processMemoryInspector = ProcessMemoryInspector()
    private let metricsStore = MetricsStore()
    private let nativeSystemMonitor = NativeSystemMonitor()
    private let trashService = TrashService(
        applicationRecycler: WorkspaceApplicationRecycler.recycle
    )
    private let localAIRuntime = LocalModelOwnedRuntime()
    private let localModelCatalog = LocalModelCatalog()
    private let localModelRuntimeDiscovery = LocalModelRuntimeDiscovery()
    private let appUpdateClient = GitHubAppUpdateClient()
    private let loginItemService = SMAppService.loginItem(
        identifier: "com.zone.cleannest.loginitem"
    )
    private let settings = UserDefaults.standard
    private var leftoverRequestID = UUID()
    private var localAIProbeID = UUID()
    private var activeAIRequestID = UUID()
    private var cleanupRevision = 0
    private var activeDiskAIRequestID = UUID()
    private var diskRevision = 0
    private var activeDiskAICollectionTask: Task<[String: DiskAIChildContext], Never>?
    private var pendingDiskAICancellationTask: Task<[String: DiskAIChildContext], Never>?
    private var fullDiskAccessProbeID = UUID()
    private var didResignAfterOpeningFullDiskAccessSettings = false
    private var lastFullDiskAccessSettingsOpenAttempt = Date.distantPast
    private var metricsSamplingTask: Task<Void, Never>?
    private var nativeMonitorTask: Task<Void, Never>?
    private var nativeMonitorSamplingID = UUID()
    private var activeCleanupScanTask: Task<Void, Never>?
    private var activeDiskScanTask: Task<Void, Never>?
    private var appUpdateCheckID = UUID()
    private var localModelDiscoveryID = UUID()
    private var localModelRuntimeMonitorTask: Task<Void, Never>?
    private var agentWorkspaceMonitorTask: Task<Void, Never>?
    private var activeAgentWorkspaceScanTask: Task<AgentWorkspaceScannerResponse, Error>?
    private var agentWorkspaceReleaseTask: Task<Void, Never>?
    private var systemStatusReleaseTask: Task<Void, Never>?
    private var agentWorkspaceScanID = UUID()
    private var applicationIsActive = true
    private var activeLifecyclePage: SidebarItem?
    private var hasLoadedEvolutionMemory = false
    private var hasLoadedDiskManualDecisions = false
    private var hasLoadedAgentWorkspaceRecoveryRecords = false

    init() {
        demoMode = ProcessInfo.processInfo.environment["CLEANNEST_DEMO"] == "1"
        let ruleState = agentRuleCatalogStore.load()
        agentRuleCatalog = ruleState.0
        agentRuleCatalogSource = ruleState.1
        agentRuleCatalogDiagnostic = ruleState.2
        customEnginePath = settings.string(forKey: "customEnginePath") ?? ""
        if settings.object(forKey: "developerMode") != nil {
            developerMode = settings.bool(forKey: "developerMode")
        }
        if settings.object(forKey: "localAIEnabled") != nil {
            localAIEnabled = settings.bool(forKey: "localAIEnabled")
        }
        if settings.object(forKey: "localModelMenuBarEnabled") != nil {
            localModelMenuBarEnabled = settings.bool(forKey: "localModelMenuBarEnabled")
        }
        if settings.object(forKey: "metricsRetentionDays") != nil {
            metricsRetentionDays = Self.validMetricsRetentionDays(
                settings.integer(forKey: "metricsRetentionDays")
            )
        }
        if let data = settings.data(forKey: "menuBarMonitorConfiguration"),
           let saved = try? JSONDecoder().decode(MenuBarMonitorConfiguration.self, from: data) {
            menuBarConfiguration = saved.normalized
        }
        refreshLaunchAtLoginStatus()
        localAIEndpoint = settings.string(forKey: "localAIEndpoint") ?? "http://127.0.0.1:8080/v1"
        localAIServiceModelID = settings.string(forKey: "localAIServiceModelID") ?? ""
        // A model is a user-replaceable runtime dependency. Never silently
        // prefer a vendor or architecture when no model has been selected.
        localAIModelPath = settings.string(forKey: "localAIModelPath") ?? ""
        localAIExecutablePath = settings.string(forKey: "localAIExecutablePath")
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".mlx-env/bin/mlx_lm.server")
                .path
        if !localAIEnabled { localAIServiceState = .disabled }
        localAIRuntime.onTermination = { [weak self] status in
            guard let self else { return }
            self.localAIProcessOwned = false
            guard self.localAIEnabled else { return }
            switch self.localAIServiceState {
            case .disabled, .stopping:
                break
            default:
                // A probe can finish just before the process-exit callback. Invalidate
                // that result so a dead owned service cannot be restored as ready.
                self.localAIProbeID = UUID()
                let detail = "CleanNest 启动的模型进程已退出（状态 \(status)）"
                self.localAIServiceState = .unavailable(detail)
                self.localAIDiagnostic = detail
            }
            Task { await self.refreshLocalModelRuntimes() }
        }
        if demoMode {
            // Demo and screenshot runs must never inherit a user's persisted
            // activity, learning, model catalog, or disk-capacity data.
            activities = []
            evolutionMemory = EvolutionMemory()
            seedDemoData()
            hasLoadedEvolutionMemory = true
            hasLoadedDiskManualDecisions = true
            hasLoadedAgentWorkspaceRecoveryRecords = true
        } else {
            loadActivities()
            loadAgentWorkspaceSummary()
            refreshDiskCapacity()
        }
        Task { await bootstrap() }
    }

    var selectedCleanupBytes: Int64 {
        cleanupCandidates
            .filter { selectedCleanupIDs.contains($0.id) }
            .reduce(0) { $0 + $1.allocatedBytes }
    }

    var selectedCleanupCount: Int {
        cleanupCandidates.reduce(0) { $0 + (selectedCleanupIDs.contains($1.id) ? 1 : 0) }
    }

    var selectedAgentWorkspaceCandidates: [AgentWorkspaceActionCandidate] {
        guard let snapshot = agentWorkspaceSnapshot else { return [] }
        return snapshot.actionCandidates.filter { selectedAgentWorkspaceCandidateIDs.contains($0.id) }
    }

    var selectedAgentWorkspaceBytes: Int64 {
        selectedAgentWorkspaceCandidates.reduce(0) { partial, candidate in
            let bytes = max(0, candidate.identity.allocatedBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
    }

    var cleanupScreenshotCount: Int {
        cleanupCandidates.reduce(0) { $0 + ($1.kind == .screenshot ? 1 : 0) }
    }

    var selectedPersonalCleanupCount: Int {
        cleanupCandidates.reduce(0) {
            $0 + (selectedCleanupIDs.contains($1.id) && $1.kind.isPersonalFile ? 1 : 0)
        }
    }

    var selectedDuplicateCleanupCount: Int {
        cleanupCandidates.reduce(0) {
            $0 + (selectedCleanupIDs.contains($1.id) && $1.duplicateEvidence != nil ? 1 : 0)
        }
    }

    var filteredApplications: [InstalledApplication] {
        let query = applicationSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return applications }
        return applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.bundleIdentifier?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var cleanupPotentialBytes: Int64 {
        cleanupCandidates.reduce(0) { $0 + $1.allocatedBytes }
    }

    var isWorking: Bool { phase.isBusy }

    var fullDiskAccessProbePassed: Bool {
        fullDiskAccessProbeResult == .accessible
    }

    var currentDiskTraversalMayRequireFullDiskAccess: Bool {
        diskTraversalMayRequireFullDiskAccess(diskRoot)
    }

    var currentDiskTraversalIsBlocked: Bool {
        currentDiskTraversalMayRequireFullDiskAccess && !fullDiskAccessProbePassed
    }

    var diskPrivacyNoticeDetail: String? {
        if let diskPrivacyBlockMessage { return diskPrivacyBlockMessage }
        guard currentDiskTraversalIsBlocked else { return nil }
        if fullDiskAccessProbeIsRunning {
            return "正在由 CleanNest 自身做一次轻量访问测试；完成前不会启动 Mole 或原生递归扫描。"
        }
        return "这个位置会遍历受 macOS 保护的应用数据。访问测试未通过前，CleanNest 不会启动 Mole、du 或原生递归扫描。"
    }

    var diskPrivacyNoticeWasBlocked: Bool {
        diskPrivacyBlockMessage != nil
    }

    var localAIIsReady: Bool {
        if case .ready = localAIServiceState { return true }
        return false
    }

    var localAIModelDisplayName: String {
        if case .ready(let modelID) = localAIServiceState { return modelID }
        let preferredServiceModel = localAIServiceModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !preferredServiceModel.isEmpty { return preferredServiceModel }
        let trimmed = localAIModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未选择模型" }
        return localAIModelDescriptor(path: trimmed)?.displayName
            ?? URL(fileURLWithPath: trimmed).lastPathComponent
    }

    var primaryLocalModelRuntime: LocalModelRuntimeInstance? {
        localModelRuntimeSnapshot.primaryInstance
    }

    var localModelRuntimeStatusTitle: String {
        switch localModelDiscoveryPhase {
        case .discovering:
            return "正在发现本地模型"
        case .runningHealthy:
            let count = localModelRuntimeSnapshot.healthyInstances.count
            return count == 1 ? "1 个模型服务健康运行" : "\(count) 个模型服务健康运行"
        case .runningUnverified:
            return "发现运行迹象，等待确认"
        case .failed:
            return "运行时检查没有完成"
        case .stopped:
            return "当前没有模型在运行"
        case .unknown:
            return "尚未检查本地模型"
        }
    }

    var configuredLocalModelCanStart: Bool {
        let modelPath = localAIModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let executablePath = localAIExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelPath.isEmpty,
              !executablePath.isEmpty,
              FileManager.default.isExecutableFile(atPath: executablePath),
              localModelRuntimeSnapshot.healthyInstances.isEmpty,
              !localAIServiceState.isBusy else { return false }
        let executableName = URL(fileURLWithPath: executablePath).lastPathComponent.lowercased()
        guard executableName == "omlx"
                || executableName.hasPrefix("omlx-")
                || executableName.contains("mlx_lm.server")
                || executableName.contains("mlx-lm-server") else { return false }
        if let configuredPort = (try? LocalAIEndpoint(rawValue: localAIEndpoint))?.port,
           localModelRuntimeSnapshot.instances.contains(where: { instance in
               instance.listeners.contains { $0.port == configuredPort }
           }) {
            return false
        }
        return localModelCatalog.descriptor(
            at: URL(fileURLWithPath: modelPath, isDirectory: true)
        ) != nil
    }

    func localAIModelDescriptor(path: String) -> LocalModelDescriptor? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, (trimmed as NSString).isAbsolutePath else { return nil }
        let standardized = URL(fileURLWithPath: trimmed, isDirectory: true).standardizedFileURL.path
        return localAIAvailableModels.first { $0.path == standardized }
            ?? localModelCatalog.descriptor(at: URL(fileURLWithPath: standardized, isDirectory: true))
    }

    var engineCanUpdateWithHomebrew: Bool {
        guard let path = engine?.executable.path else { return false }
        return path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/")
    }

    func bootstrap() async {
        if demoMode { return }
        let workloads = AppLifecyclePolicy.bootstrapWorkloads(
            menuBarMonitoringEnabled: menuBarConfiguration.isEnabled,
            localModelMenuBarEnabled: localModelMenuBarEnabled
        )
        if workloads.contains(.nativeMenuBarMonitor) {
            startNativeMonitoring()
        }
        if workloads.contains(.metricsStorage) {
            await prepareMetricsStorage()
        }
        if workloads.contains(.engineProbe) {
            await refreshEngine()
        }
        if engine != nil {
            startMetricsSampling()
        }
        if workloads.contains(.localModelRuntimeDiscovery) {
            startLocalModelRuntimeMonitoring()
        }
    }

    func activatePage(_ page: SidebarItem) async {
        if activeLifecyclePage != page {
            deactivatePage(activeLifecyclePage)
            activeLifecyclePage = page
        }

        let workloads = AppLifecyclePolicy.foregroundWorkloads(for: page.lifecycleSurface)
        switch page.lifecycleSurface {
        case .overview, .maintenance, .activity:
            break
        case .cleanup:
            ensureEvolutionMemoryLoaded()
            if workloads.contains(.fullDiskAccessProbe) {
                await refreshFullDiskAccessProbe()
            }
        case .applications:
            if workloads.contains(.fullDiskAccessProbe) {
                await refreshFullDiskAccessProbe()
            }
        case .disk:
            ensureDiskManualDecisionsLoaded()
            if workloads.contains(.fullDiskAccessProbe) {
                await refreshFullDiskAccessProbe()
            }
        case .systemStatus:
            systemStatusReleaseTask?.cancel()
            systemStatusReleaseTask = nil
            if workloads.contains(.metricHistory) {
                await refreshMetricHistory()
            }
            guard !Task.isCancelled else { return }
            if workloads.contains(.processInspection) {
                await refreshSystemStatus()
            }
        case .agentWorkspace:
            agentWorkspaceReleaseTask?.cancel()
            agentWorkspaceReleaseTask = nil
            ensureAgentWorkspaceRecoveryRecordsLoaded()
            if workloads.contains(.agentWorkspaceScan), agentWorkspaceSnapshot == nil {
                await refreshAgentWorkspace()
            }
            guard !Task.isCancelled, selection == .agentWorkspace else { return }
            if workloads.contains(.nativeDeveloperStorage), nativeDeveloperStorageSnapshot == nil {
                await refreshNativeDeveloperStorage()
            }
            guard !Task.isCancelled, selection == .agentWorkspace else { return }
            startAgentWorkspaceMonitoring()
        case .localModels:
            if workloads.contains(.localModelCatalog) {
                await refreshLocalModelCatalog()
            }
            guard !Task.isCancelled else { return }
            if workloads.contains(.localModelRuntimeDiscovery) {
                await refreshLocalModelRuntimes(force: true)
            }
            guard !Task.isCancelled else { return }
            if workloads.contains(.localAIProbe), localAIEnabled { await probeLocalAI() }
        case .learning:
            ensureEvolutionMemoryLoaded()
        case .settings:
            if workloads.contains(.fullDiskAccessProbe) {
                await refreshFullDiskAccessProbe()
            }
            guard !Task.isCancelled else { return }
            if workloads.contains(.localModelCatalog) {
                await refreshLocalModelCatalog()
            }
        }
    }

    private func deactivatePage(_ page: SidebarItem?) {
        guard let page else { return }
        guard AppLifecyclePolicy.releasesHeavyPresentationData(whenLeaving: page.lifecycleSurface) else {
            return
        }
        switch page.lifecycleSurface {
        case .agentWorkspace:
            activeAgentWorkspaceScanTask?.cancel()
            agentWorkspaceMonitorTask?.cancel()
            agentWorkspaceMonitorTask = nil
            scheduleAgentWorkspaceRelease()
        case .systemStatus:
            scheduleSystemStatusRelease()
        default:
            break
        }
    }

    private func scheduleAgentWorkspaceRelease() {
        agentWorkspaceReleaseTask?.cancel()
        agentWorkspaceReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self, self.selection != .agentWorkspace,
                  !self.agentWorkspaceRecoveryPhase.isBusy else { return }
            self.agentWorkspaceState.releaseHeavyDetails()
            self.scheduleAgentWorkspaceAllocatorRelief()
        }
    }

    private func scheduleSystemStatusRelease() {
        systemStatusReleaseTask?.cancel()
        systemStatusReleaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
            guard let self, self.selection != .status else { return }
            self.memoryProcesses.removeAll(keepingCapacity: false)
            self.memoryAnalysis = nil
            self.metricHistory.removeAll(keepingCapacity: false)
            self.forceTerminationProcessID = nil
            self.systemStatusReleaseTask = nil
            self.scheduleAgentWorkspaceAllocatorRelief()
        }
    }

    func refreshAgentWorkspace() async {
        guard !demoMode, !agentWorkspacePhase.isScanning else { return }
        let scanID = UUID()
        agentWorkspaceScanID = scanID
        agentWorkspacePhase = .scanning
        agentWorkspaceDiagnostic = "正在按 \(agentRuleCatalog.providers.count) 个有界适配器统计文件元数据和活跃写入…"
        let previous = loadAgentWorkspaceObservation()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let request = AgentWorkspaceScannerRequest(
            requestID: scanID.uuidString,
            homeDirectory: home,
            previousObservation: previous,
            ruleCatalog: agentRuleCatalog
        )
        let client = agentWorkspaceScannerServiceClient
        let scanTask = Task<AgentWorkspaceScannerResponse, Error> {
            try await client.scanAgentWorkspace(request)
        }
        activeAgentWorkspaceScanTask = scanTask
        do {
            let response = try await withTaskCancellationHandler {
                try await scanTask.value
            } onCancel: {
                scanTask.cancel()
            }
            let result = response.result
            guard response.requestID == scanID.uuidString,
                  agentWorkspaceScanID == scanID else { return }
            activeAgentWorkspaceScanTask = nil
            agentWorkspaceSnapshot = result.snapshot
            selectedAgentWorkspaceCandidateIDs.formIntersection(
                Set(result.snapshot.actionCandidates.map(\.id))
            )
            agentWorkspaceDiagnostic = "\(result.snapshot.diagnostic) 耗时 \(String(format: "%.1f", response.elapsedSeconds)) 秒。"
            agentWorkspacePhase = .ready
            if result.snapshot.isComplete {
                saveAgentWorkspaceObservation(result.observation)
                saveAgentWorkspaceSummary(AgentWorkspaceSummary(snapshot: result.snapshot))
            }
            if selection == .agentWorkspace {
                await refreshAgentDependencyGraph()
            }
            scheduleAgentWorkspaceAllocatorRelief()
        } catch is CancellationError {
            guard agentWorkspaceScanID == scanID else { return }
            activeAgentWorkspaceScanTask = nil
            agentWorkspacePhase = agentWorkspaceSnapshot == nil ? .idle : .ready
            agentWorkspaceDiagnostic = agentWorkspaceSummary == nil
                ? "Agent 工作区扫描已取消；没有发布不完整结果。"
                : "Agent 工作区扫描已取消；上次聚合结果仍保留，文件级明细需要重新验证。"
        } catch {
            guard agentWorkspaceScanID == scanID else { return }
            activeAgentWorkspaceScanTask = nil
            let message = "Agent 工作区扫描没有完成：\(error.localizedDescription)"
            agentWorkspacePhase = .failed(message)
            agentWorkspaceDiagnostic = message
        }
    }

    private func scheduleAgentWorkspaceAllocatorRelief() {
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1))
            _ = malloc_zone_pressure_relief(nil, 0)
        }
    }

    func refreshAgentDependencyGraph() async {
        guard !demoMode, !agentDependencyGraphIsRefreshing else { return }
        agentDependencyGraphIsRefreshing = true
        let builder = agentDependencyGraphBuilder
        let workspace = agentWorkspaceSnapshot
        let catalog = agentRuleCatalog
        let models = localModelRuntimeSnapshot
        let graph = await builder.build(
            workspace: workspace,
            catalog: catalog,
            localModels: models
        )
        agentDependencyGraph = graph
        agentDependencyGraphIsRefreshing = false
    }

    func importAgentRuleCatalog(from url: URL) async {
        do {
            let catalog = try agentRuleCatalogStore.install(from: url)
            agentRuleCatalog = catalog
            agentRuleCatalogSource = .signedBundle(agentRuleCatalogStore.installedBundleURL)
            agentRuleCatalogDiagnostic = "规则 \(catalog.revision) 的代码签名、签名者和内容边界均已通过校验。"
            agentWorkspaceSnapshot = nil
            selectedAgentWorkspaceCandidateIDs.removeAll()
            await refreshAgentWorkspace()
        } catch {
            agentRuleCatalogDiagnostic = "规则没有导入：\(error.localizedDescription)"
        }
    }

    func resetAgentRuleCatalog() async {
        do {
            try agentRuleCatalogStore.reset()
            agentRuleCatalog = .builtIn
            agentRuleCatalogSource = .builtIn
            agentRuleCatalogDiagnostic = "已恢复随 App 发布并经过测试的内置规则。"
            agentWorkspaceSnapshot = nil
            selectedAgentWorkspaceCandidateIDs.removeAll()
            await refreshAgentWorkspace()
        } catch {
            agentRuleCatalogDiagnostic = "未能恢复内置规则：\(error.localizedDescription)"
        }
    }

    func setAgentWorkspaceCandidate(_ id: String, selected: Bool) {
        guard agentWorkspaceSnapshot?.actionCandidates.contains(where: { $0.id == id }) == true else {
            selectedAgentWorkspaceCandidateIDs.remove(id)
            return
        }
        if selected {
            selectedAgentWorkspaceCandidateIDs.insert(id)
        } else {
            selectedAgentWorkspaceCandidateIDs.remove(id)
        }
    }

    func setAgentWorkspaceCandidates(
        _ candidates: [AgentWorkspaceActionCandidate],
        selected: Bool
    ) {
        let ids = Set(candidates.map(\.id))
        if selected {
            selectedAgentWorkspaceCandidateIDs.formUnion(ids)
        } else {
            selectedAgentWorkspaceCandidateIDs.subtract(ids)
        }
    }

    func createAgentWorkspaceRecovery() async {
        guard !demoMode, !agentWorkspaceRecoveryPhase.isBusy else { return }
        guard agentWorkspaceSnapshot?.isComplete == true else {
            agentWorkspaceRecoveryMessage = "本次扫描或活跃文件确认不完整，不能执行安全处置。"
            agentWorkspaceRecoveryMessageIsWarning = true
            return
        }
        let candidates = selectedAgentWorkspaceCandidates
        guard !candidates.isEmpty else {
            agentWorkspaceRecoveryMessage = "请先选择至少一个静置缓存、临时文件或日志。"
            agentWorkspaceRecoveryMessageIsWarning = true
            return
        }
        agentWorkspaceRecoveryPhase = .creatingBackup
        agentWorkspaceRecoveryMessage = "正在创建并校验本机压缩备份；完成前不会移动原文件。"
        agentWorkspaceRecoveryMessageIsWarning = false
        do {
            let result = try await agentWorkspaceRecoveryService.createRecovery(candidates: candidates)
            selectedAgentWorkspaceCandidateIDs.subtract(candidates.map(\.id))
            loadAgentWorkspaceRecoveryRecords()
            let delta = result.record.apfsDeltaBytes ?? 0
            let deltaText: String
            if delta > 0 {
                deltaText = "APFS 可用空间实测增加 \(CleanNestFormatting.bytes(delta))。"
            } else if delta < 0 {
                deltaText = "APFS 可用空间实测减少 \(CleanNestFormatting.bytes(-delta))；压缩备份当前大于释放收益。"
            } else {
                deltaText = "APFS 可用空间实测没有可确认变化。"
            }
            agentWorkspaceRecoveryMessage = "已处理 \(result.record.items.count) 个文件，Agent 目录减少 \(CleanNestFormatting.bytes(result.record.originalAllocatedBytes))；\(deltaText) 可随时从本页恢复。"
            agentWorkspaceRecoveryMessageIsWarning = delta <= 0
            addActivity(
                title: "Agent 安全处置",
                detail: "压缩备份已校验并保存在本机恢复区；\(deltaText)",
                outcome: result.record.pendingOriginalBytes == 0 ? .success : .partial,
                affectedItems: result.record.items.count,
                bytes: max(0, delta),
                category: .cleanup
            )
            agentWorkspaceRecoveryPhase = .idle
            await refreshAgentWorkspace()
            refreshDiskCapacity()
        } catch {
            let message = error.localizedDescription
            agentWorkspaceRecoveryPhase = .failed(message)
            agentWorkspaceRecoveryMessage = message
            agentWorkspaceRecoveryMessageIsWarning = true
            addActivity(
                title: "Agent 安全处置",
                detail: "没有完成：\(message)",
                outcome: .failed,
                affectedItems: candidates.count,
                category: .cleanup
            )
        }
    }

    func restoreAgentWorkspaceRecovery(_ record: AgentWorkspaceRecoveryRecord) async {
        guard !demoMode, !agentWorkspaceRecoveryPhase.isBusy, record.status != .restored else { return }
        agentWorkspaceRecoveryPhase = .restoring(record.id)
        agentWorkspaceRecoveryMessage = "正在核对原位置；如果 Agent 已新建同名文件，恢复会停止而不会覆盖。"
        agentWorkspaceRecoveryMessageIsWarning = false
        do {
            let result = try await agentWorkspaceRecoveryService.restore(operationID: record.id)
            loadAgentWorkspaceRecoveryRecords()
            agentWorkspaceRecoveryMessage = "已恢复 \(result.record.items.count) 个文件；压缩备份仍保留在本机恢复区。"
            agentWorkspaceRecoveryMessageIsWarning = false
            addActivity(
                title: "恢复 Agent 文件",
                detail: "已从校验过的本机备份恢复；未覆盖 Agent 后来生成的文件。",
                outcome: .success,
                affectedItems: result.record.items.count,
                category: .other
            )
            agentWorkspaceRecoveryPhase = .idle
            await refreshAgentWorkspace()
            refreshDiskCapacity()
        } catch {
            let message = error.localizedDescription
            agentWorkspaceRecoveryPhase = .failed(message)
            agentWorkspaceRecoveryMessage = message
            agentWorkspaceRecoveryMessageIsWarning = true
            addActivity(
                title: "恢复 Agent 文件",
                detail: "没有完成：\(message)",
                outcome: .failed,
                affectedItems: record.items.count,
                category: .other
            )
        }
    }

    func openAgentWorkspaceRecoveryFolder() {
        let url = CleanNestDataPaths.agentWorkspaceRecoveryDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func loadAgentWorkspaceRecoveryRecords() {
        guard !demoMode else {
            agentWorkspaceRecoveryRecords = []
            hasLoadedAgentWorkspaceRecoveryRecords = true
            return
        }
        do {
            agentWorkspaceRecoveryRecords = try agentWorkspaceRecoveryService.listRecords()
        } catch {
            agentWorkspaceRecoveryRecords = []
            lastTechnicalDetail = "Agent 恢复记录无法读取：\(error.localizedDescription)"
        }
        hasLoadedAgentWorkspaceRecoveryRecords = true
    }

    private func ensureAgentWorkspaceRecoveryRecordsLoaded() {
        guard !hasLoadedAgentWorkspaceRecoveryRecords else { return }
        loadAgentWorkspaceRecoveryRecords()
    }

    func setNativeGitRepository(_ url: URL?) async {
        nativeGitRepository = url?.standardizedFileURL
        await refreshNativeDeveloperStorage()
    }

    func refreshNativeDeveloperStorage() async {
        guard !demoMode, !nativeDeveloperStorageIsRefreshing else { return }
        nativeDeveloperStorageIsRefreshing = true
        let repository = nativeGitRepository
        nativeDeveloperStorageSnapshot = await nativeDeveloperStorageInspector.inspect(
            gitRepository: repository
        )
        nativeDeveloperStorageIsRefreshing = false
    }

    func runNativeDeveloperStorageCleanup(_ requestedTool: NativeDeveloperStorageTool) async {
        guard !demoMode,
              nativeDeveloperStorageActionTool == nil,
              [.gitWorktree, .huggingFace].contains(requestedTool) else { return }
        nativeDeveloperStorageActionTool = requestedTool
        nativeDeveloperStorageMessage = "正在重新生成原生 dry-run，执行范围不会沿用过期预览。"
        nativeDeveloperStorageMessageIsWarning = false

        let refreshed = await nativeDeveloperStorageInspector.inspect(gitRepository: nativeGitRepository)
        nativeDeveloperStorageSnapshot = refreshed
        guard let entry = refreshed.entries.first(where: { $0.tool == requestedTool }),
              entry.state == .ready,
              entry.supportsNativeCleanup,
              let executablePath = entry.executablePath else {
            nativeDeveloperStorageActionTool = nil
            nativeDeveloperStorageMessage = "原生预演已变化或不再可用，没有执行清理。"
            nativeDeveloperStorageMessageIsWarning = true
            return
        }

        let arguments: [String]
        switch requestedTool {
        case .gitWorktree:
            guard let scope = entry.scopePath else {
                nativeDeveloperStorageActionTool = nil
                nativeDeveloperStorageMessage = "Git 仓库范围已经丢失，没有执行 prune。"
                nativeDeveloperStorageMessageIsWarning = true
                return
            }
            arguments = ["-C", scope, "worktree", "prune", "--verbose"]
        case .huggingFace:
            arguments = ["cache", "prune", "--yes"]
        case .docker, .npm, .pip:
            nativeDeveloperStorageActionTool = nil
            return
        }

        let before = diskFreeSpaceBytes()
        do {
            let result = try await commandRunner.run(
                executable: URL(fileURLWithPath: executablePath),
                arguments: arguments,
                environment: requestedTool == .huggingFace ? [
                    "HF_HUB_OFFLINE": "1",
                    "HF_HUB_DISABLE_TELEMETRY": "1",
                    "DO_NOT_TRACK": "1"
                ] : [:],
                timeout: requestedTool == .huggingFace ? 120 : 20
            )
            guard result.exitCode == 0 else {
                throw CommandRunnerError.nonZeroExit(result)
            }
            let after = diskFreeSpaceBytes()
            let delta = max(0, after - before)
            nativeDeveloperStorageMessage = "\(requestedTool.displayName) 原生清理已完成；APFS 可用空间实测增加 \(CleanNestFormatting.bytes(delta))。"
            nativeDeveloperStorageMessageIsWarning = false
            addActivity(
                title: "\(requestedTool.displayName) 原生清理",
                detail: "执行前重新通过官方 dry-run；APFS 前后实测增加 \(CleanNestFormatting.bytes(delta))。",
                outcome: .success,
                affectedItems: 1,
                bytes: delta,
                category: .cleanup
            )
            nativeDeveloperStorageSnapshot = await nativeDeveloperStorageInspector.inspect(
                gitRepository: nativeGitRepository
            )
            refreshDiskCapacity()
        } catch {
            let message = error.localizedDescription
            nativeDeveloperStorageMessage = "\(requestedTool.displayName) 没有完成：\(message)"
            nativeDeveloperStorageMessageIsWarning = true
            addActivity(
                title: "\(requestedTool.displayName) 原生清理",
                detail: "没有完成：\(message)",
                outcome: .failed,
                category: .cleanup
            )
        }
        nativeDeveloperStorageActionTool = nil
    }

    private func diskFreeSpaceBytes() -> Int64 {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path)
        return max(0, (attributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0)
    }

    private func startAgentWorkspaceMonitoring() {
        guard !demoMode, applicationIsActive,
              selection == .agentWorkspace,
              activeLifecyclePage == .agentWorkspace else { return }
        agentWorkspaceMonitorTask?.cancel()
        agentWorkspaceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    return
                }
                guard let self, !Task.isCancelled,
                      self.applicationIsActive,
                      self.selection == .agentWorkspace,
                      self.activeLifecyclePage == .agentWorkspace else { return }
                await self.refreshAgentWorkspace()
            }
        }
    }

    func refreshLocalModelCatalog() async {
        guard !demoMode else {
            localAIModelCatalogIsRefreshing = false
            localAIModelCatalogDiagnostic = "演示模式：1 个合成模型，不读取本机模型目录。"
            return
        }
        guard !localAIModelCatalogIsRefreshing else { return }
        localAIModelCatalogIsRefreshing = true
        localAIModelCatalogDiagnostic = "正在扫描常用模型目录…"

        let catalog = localModelCatalog
        let home = FileManager.default.homeDirectoryForCurrentUser
        let currentPath = localAIModelPath
        let recentPaths = settings.stringArray(forKey: "recentLocalAIModelPaths") ?? []
        let models = await Task.detached(priority: .utility) {
            catalog.discover(
                homeDirectory: home,
                additionalPaths: [currentPath] + recentPaths
            )
        }.value

        localAIAvailableModels = models
        localAIModelCatalogIsRefreshing = false
        localAIModelCatalogDiagnostic = models.isEmpty
            ? "未发现完整模型，可手动选择包含 config.json 与 safetensors 的目录。"
            : "发现 \(models.count) 个可用的 MLX 模型。"
    }

    func refreshLocalModelRuntimes(force: Bool = false) async {
        guard !demoMode else { return }
        guard force || !localModelDiscoveryIsRunning else { return }
        let discoveryID = UUID()
        localModelDiscoveryID = discoveryID
        localModelDiscoveryIsRunning = true
        localModelDiscoveryPhase = .discovering
        localModelRuntimeDiagnostic = "正在交叉检查进程、监听端口与平台 API…"
        let discovery = localModelRuntimeDiscovery
        let endpoint = localAIEndpoint
        let snapshot = await Task.detached(priority: .utility) {
            await discovery.discover(configuredEndpoint: endpoint)
        }.value
        guard localModelDiscoveryID == discoveryID else { return }
        let verified = snapshot.markingOwned(processID: localAIRuntime.ownedProcessIdentifier)
        localModelRuntimeSnapshot = verified
        localModelDiscoveryPhase = verified.phase
        localModelRuntimeDiagnostic = verified.diagnostic
        localModelDiscoveryIsRunning = false
        if selection == .agentWorkspace {
            await refreshAgentDependencyGraph()
        }
    }

    func setLocalModelMenuBarEnabled(_ enabled: Bool) {
        localModelMenuBarEnabled = enabled
        guard !demoMode else { return }
        settings.set(enabled, forKey: "localModelMenuBarEnabled")
    }

    func startConfiguredLocalModelRuntime() async {
        guard configuredLocalModelCanStart else {
            localModelRuntimeDiagnostic = localAIModelPath.isEmpty
                ? "请先在设置中选择本机模型与服务程序。"
                : "当前启动配置不完整，或已有健康服务占用该端点。"
            return
        }
        if !localAIEnabled {
            localAIEnabled = true
            if !demoMode { settings.set(true, forKey: "localAIEnabled") }
            localAIServiceState = .unchecked
        }
        await startLocalAI()
        await refreshLocalModelRuntimes()
    }

    func stopOwnedLocalModelRuntime() async {
        guard localAIRuntime.ownsRunningProcess else {
            localModelRuntimeDiagnostic = "这不是 CleanNest 启动的进程；请使用带风险确认的外部服务关闭流程。"
            return
        }
        await stopLocalAI()
        await refreshLocalModelRuntimes()
    }

    func stopExternalLocalModelRuntime(
        _ requestedRuntime: LocalModelRuntimeInstance,
        force: Bool = false
    ) async {
        guard !demoMode else {
            externalLocalModelStopMessage = "演示模式不会结束任何外部进程。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        guard stoppingExternalLocalModelRuntimeID == nil else { return }
        guard let requestedProcess = requestedRuntime.process else {
            externalLocalModelStopMessage = "外部模型服务没有可验证的进程身份。"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            return
        }
        if let refusal = LocalModelExternalControlPolicy.refusalReason(for: requestedRuntime) {
            externalLocalModelStopMessage = refusal
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            return
        }

        stoppingExternalLocalModelRuntimeID = requestedRuntime.id
        externalLocalModelStopMessage = force
            ? "正在重新核对进程身份，准备强制结束…"
            : "正在重新核对进程身份，准备正常关闭…"
        externalLocalModelStopMessageIsWarning = false
        if !force { externalLocalModelForceCandidateID = nil }
        defer { stoppingExternalLocalModelRuntimeID = nil }

        await refreshLocalModelRuntimes(force: true)
        guard let currentRuntime = localModelRuntimeSnapshot.instances.first(where: {
            $0.process?.pid == requestedProcess.pid
                && $0.platform == requestedRuntime.platform
        }),
        let currentProcess = currentRuntime.process else {
            externalLocalModelStopMessage = "原服务已退出或身份已改变；CleanNest 没有向新进程发送信号。"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            addActivity(
                title: "关闭外部模型服务",
                detail: "\(requestedRuntime.platform.displayName) · PID \(requestedProcess.pid) · 身份已变化",
                outcome: .failed
            )
            return
        }
        if let mismatch = LocalModelExternalControlPolicy.identityMismatchReason(
            expected: requestedProcess,
            observed: currentProcess
        ) {
            externalLocalModelStopMessage = "身份复核未通过：\(mismatch) CleanNest 没有发送信号。"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            addActivity(
                title: "关闭外部模型服务",
                detail: "\(requestedRuntime.platform.displayName) · PID \(requestedProcess.pid) · 身份复核失败",
                outcome: .failed
            )
            return
        }

        let inspector = processMemoryInspector
        guard let observedProcess = await Task.detached(priority: .userInitiated, operation: {
            inspector.process(pid: currentProcess.pid)
        }).value else {
            externalLocalModelStopMessage = "原服务已退出，无需再次关闭。"
            externalLocalModelStopMessageIsWarning = false
            externalLocalModelForceCandidateID = nil
            await refreshLocalModelRuntimes(force: true)
            return
        }
        if let mismatch = LocalModelExternalControlPolicy.identityMismatchReason(
            expected: currentProcess,
            observed: observedProcess
        ) {
            externalLocalModelStopMessage = "系统身份复核未通过：\(mismatch) CleanNest 没有发送信号。"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            addActivity(
                title: "关闭外部模型服务",
                detail: "\(requestedRuntime.platform.displayName) · PID \(requestedProcess.pid) · 系统身份复核失败",
                outcome: .failed
            )
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            inspector.terminate(observedProcess, force: force)
        }.value
        let actionTitle = force ? "强制结束外部模型服务" : "关闭外部模型服务"
        let activityDetail = "\(currentRuntime.platform.displayName) · PID \(currentProcess.pid)"

        switch result {
        case .terminated:
            externalLocalModelStopMessage = force
                ? "\(currentRuntime.platform.displayName) · PID \(currentProcess.pid) 已被强制结束。模型文件和平台设置没有删除。"
                : "\(currentRuntime.platform.displayName) · PID \(currentProcess.pid) 已正常退出。模型文件和平台设置没有删除。"
            externalLocalModelStopMessageIsWarning = false
            externalLocalModelForceCandidateID = nil
            addActivity(title: actionTitle, detail: activityDetail, outcome: .success, affectedItems: 1)
            if localAIIsReady {
                invalidateCleanupAI()
                _ = invalidateDiskAI()
                localAIServiceState = .unavailable("外部模型服务已关闭")
                localAIDiagnostic = "外部模型服务已关闭"
            }

        case .stillRunning:
            externalLocalModelStopMessage = force
                ? "\(currentRuntime.platform.displayName) · PID \(currentProcess.pid) 仍在运行。它可能已被所属平台自动重启。"
                : "\(currentRuntime.platform.displayName) · PID \(currentProcess.pid) 没有在 3 秒内退出。它可能正在保存状态；如确有需要，可再次确认后强制结束。"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = force ? nil : currentRuntime.id
            addActivity(title: actionTitle, detail: "\(activityDetail) · 仍在运行", outcome: .partial)

        case .alreadyExited:
            externalLocalModelStopMessage = "原服务已退出，无需再次关闭。"
            externalLocalModelStopMessageIsWarning = false
            externalLocalModelForceCandidateID = nil

        case .identityChanged:
            externalLocalModelStopMessage = "进程身份在关闭期间发生变化；CleanNest 没有向替换进程发送信号。"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            addActivity(title: actionTitle, detail: "\(activityDetail) · 身份已变化", outcome: .failed)

        case .refused(let reason):
            externalLocalModelStopMessage = reason
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            addActivity(title: actionTitle, detail: "\(activityDetail) · \(reason)", outcome: .failed)

        case .failed(let reason):
            externalLocalModelStopMessage = "没有关闭 \(currentRuntime.platform.displayName)：\(reason)"
            externalLocalModelStopMessageIsWarning = true
            externalLocalModelForceCandidateID = nil
            addActivity(title: actionTitle, detail: "\(activityDetail) · \(reason)", outcome: .failed)
        }

        await refreshLocalModelRuntimes(force: true)
        if case .terminated = result,
           let replacement = localModelRuntimeSnapshot.instances.first(where: {
               $0.platform == currentRuntime.platform
                   && $0.process?.pid != currentProcess.pid
                   && !$0.listeners.filter { listener in
                       currentRuntime.listeners.contains { $0.port == listener.port }
                   }.isEmpty
           }) {
            externalLocalModelStopMessage = "原进程已退出，但所属平台已自动重启服务为 PID \(replacement.process?.pid ?? 0)。"
            externalLocalModelStopMessageIsWarning = true
        }
    }

    func disableExternalLocalModelSupervisor(
        _ requestedRuntime: LocalModelRuntimeInstance
    ) async {
        guard !demoMode else {
            externalLocalModelStopMessage = "演示模式不会停用任何守护服务。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        guard stoppingExternalLocalModelRuntimeID == nil else { return }
        guard let requestedProcess = requestedRuntime.process,
              let requestedSupervisor = requestedRuntime.supervisor else {
            externalLocalModelStopMessage = "没有取得模型进程与守护服务的精确对应关系。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        if let refusal = LocalModelSupervisorControlPolicy.disableRefusalReason(
            runtime: requestedRuntime
        ) {
            externalLocalModelStopMessage = refusal
            externalLocalModelStopMessageIsWarning = true
            return
        }

        stoppingExternalLocalModelRuntimeID = requestedRuntime.id
        externalLocalModelStopMessage = "正在重新核对进程、守护标签与配置文件…"
        externalLocalModelStopMessageIsWarning = false
        externalLocalModelForceCandidateID = nil
        defer { stoppingExternalLocalModelRuntimeID = nil }

        await refreshLocalModelRuntimes(force: true)
        guard let currentRuntime = localModelRuntimeSnapshot.instances.first(where: {
            $0.process?.pid == requestedProcess.pid
                && $0.platform == requestedRuntime.platform
        }),
        let currentProcess = currentRuntime.process,
        let currentSupervisor = currentRuntime.supervisor else {
            externalLocalModelStopMessage = "模型服务或守护关系已经改变；CleanNest 没有修改 launchd。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        if let mismatch = LocalModelExternalControlPolicy.identityMismatchReason(
            expected: requestedProcess,
            observed: currentProcess
        ) ?? LocalModelSupervisorControlPolicy.identityMismatchReason(
            expected: requestedSupervisor,
            observed: currentSupervisor
        ) {
            externalLocalModelStopMessage = "身份复核未通过：\(mismatch) CleanNest 没有修改 launchd。"
            externalLocalModelStopMessageIsWarning = true
            addActivity(
                title: "停用模型守护服务",
                detail: "\(requestedRuntime.platform.displayName) · \(requestedSupervisor.label) · 身份复核失败",
                outcome: .failed
            )
            return
        }
        if let refusal = LocalModelSupervisorControlPolicy.disableRefusalReason(
            runtime: currentRuntime
        ) {
            externalLocalModelStopMessage = refusal
            externalLocalModelStopMessageIsWarning = true
            return
        }

        do {
            let launchctl = URL(fileURLWithPath: "/bin/launchctl")
            let disableResult = try await commandRunner.run(
                executable: launchctl,
                arguments: ["disable", currentSupervisor.serviceTarget],
                timeout: 5
            )
            guard disableResult.exitCode == 0 else {
                externalLocalModelStopMessage = "launchd 没有接受停用请求（退出码 \(disableResult.exitCode)）；当前进程未被关闭。"
                externalLocalModelStopMessageIsWarning = true
                addActivity(
                    title: "停用模型守护服务",
                    detail: "\(currentRuntime.platform.displayName) · \(currentSupervisor.label) · 停用失败",
                    outcome: .failed
                )
                return
            }

            let bootoutResult = try await commandRunner.run(
                executable: launchctl,
                arguments: ["bootout", currentSupervisor.serviceTarget],
                timeout: 8
            )
            try? await Task.sleep(for: .milliseconds(450))
            await refreshLocalModelRuntimes(force: true)

            let stillRunning = localModelRuntimeSnapshot.instances.contains { instance in
                instance.supervisor?.label == currentSupervisor.label
                    && instance.process != nil
            }
            let disabledSupervisor = localModelRuntimeSnapshot.instances
                .compactMap(\.supervisor)
                .first { $0.id == currentSupervisor.id && $0.isDisabled }

            if !stillRunning, disabledSupervisor != nil {
                externalLocalModelStopMessage = "\(currentSupervisor.label) 已停用，PID \(currentProcess.pid) 已退出；launchd 不会再次自动拉起。可在本页重新启用。"
                externalLocalModelStopMessageIsWarning = false
                addActivity(
                    title: "停用模型守护服务",
                    detail: "\(currentRuntime.platform.displayName) · \(currentSupervisor.label)",
                    outcome: .success,
                    affectedItems: 1
                )
                if localAIIsReady {
                    invalidateCleanupAI()
                    _ = invalidateDiskAI()
                    localAIServiceState = .unavailable("模型守护服务已停用")
                    localAIDiagnostic = "模型守护服务已停用"
                }
            } else {
                let bootoutDetail = bootoutResult.exitCode == 0
                    ? "launchd 尚未确认服务完全退出"
                    : "bootout 返回退出码 \(bootoutResult.exitCode)"
                externalLocalModelStopMessage = "自动启动已标记为停用，但 \(bootoutDetail)。请重新发现后再决定是否关闭残留进程。"
                externalLocalModelStopMessageIsWarning = true
                addActivity(
                    title: "停用模型守护服务",
                    detail: "\(currentRuntime.platform.displayName) · \(currentSupervisor.label) · 部分完成",
                    outcome: .partial
                )
            }
        } catch is CancellationError {
            externalLocalModelStopMessage = "停用守护服务已取消；请重新发现当前状态。"
            externalLocalModelStopMessageIsWarning = true
            await refreshLocalModelRuntimes(force: true)
        } catch {
            externalLocalModelStopMessage = "没有停用守护服务：\(error.localizedDescription)"
            externalLocalModelStopMessageIsWarning = true
            await refreshLocalModelRuntimes(force: true)
        }
    }

    func enableLocalModelSupervisor(
        _ requestedRuntime: LocalModelRuntimeInstance
    ) async {
        guard !demoMode else {
            externalLocalModelStopMessage = "演示模式不会启用任何守护服务。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        guard stoppingExternalLocalModelRuntimeID == nil else { return }
        guard let requestedSupervisor = requestedRuntime.supervisor else {
            externalLocalModelStopMessage = "没有找到可重新启用的守护服务。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        if let refusal = LocalModelSupervisorControlPolicy.enableRefusalReason(
            supervisor: requestedSupervisor
        ) {
            externalLocalModelStopMessage = refusal
            externalLocalModelStopMessageIsWarning = true
            return
        }

        stoppingExternalLocalModelRuntimeID = requestedRuntime.id
        externalLocalModelStopMessage = "正在重新核对守护配置并启用…"
        externalLocalModelStopMessageIsWarning = false
        externalLocalModelForceCandidateID = nil
        defer { stoppingExternalLocalModelRuntimeID = nil }

        await refreshLocalModelRuntimes(force: true)
        guard let currentRuntime = localModelRuntimeSnapshot.instances.first(where: {
            $0.supervisor?.id == requestedSupervisor.id
        }),
        let currentSupervisor = currentRuntime.supervisor,
        let sourcePath = currentSupervisor.sourcePath else {
            externalLocalModelStopMessage = "守护配置已经消失或改变；CleanNest 没有启用服务。"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        if let mismatch = LocalModelSupervisorControlPolicy.identityMismatchReason(
            expected: requestedSupervisor,
            observed: currentSupervisor
        ) {
            externalLocalModelStopMessage = "守护配置复核未通过：\(mismatch)"
            externalLocalModelStopMessageIsWarning = true
            return
        }
        if let refusal = LocalModelSupervisorControlPolicy.enableRefusalReason(
            supervisor: currentSupervisor
        ) {
            externalLocalModelStopMessage = refusal
            externalLocalModelStopMessageIsWarning = true
            return
        }

        do {
            let launchctl = URL(fileURLWithPath: "/bin/launchctl")
            let enableResult = try await commandRunner.run(
                executable: launchctl,
                arguments: ["enable", currentSupervisor.serviceTarget],
                timeout: 5
            )
            guard enableResult.exitCode == 0 else {
                externalLocalModelStopMessage = "launchd 没有接受启用请求（退出码 \(enableResult.exitCode)）。"
                externalLocalModelStopMessageIsWarning = true
                return
            }
            let bootstrapResult = try await commandRunner.run(
                executable: launchctl,
                arguments: ["bootstrap", currentSupervisor.domain, sourcePath],
                timeout: 8
            )
            try? await Task.sleep(for: .milliseconds(650))
            await refreshLocalModelRuntimes(force: true)
            let running = localModelRuntimeSnapshot.instances.first { instance in
                instance.supervisor?.label == currentSupervisor.label
                    && instance.process != nil
            }
            if let running {
                externalLocalModelStopMessage = "\(currentSupervisor.label) 已重新启用，当前 PID 为 \(running.process?.pid ?? 0)。"
                externalLocalModelStopMessageIsWarning = running.phase != .runningHealthy
                addActivity(
                    title: "启用模型守护服务",
                    detail: "\(currentRuntime.platform.displayName) · \(currentSupervisor.label)",
                    outcome: running.phase == .runningHealthy ? .success : .partial,
                    affectedItems: 1
                )
                if localAIEnabled { await probeLocalAI() }
            } else {
                externalLocalModelStopMessage = bootstrapResult.exitCode == 0
                    ? "守护服务已启用，但尚未发现运行进程；它可能仍在启动或启动失败。"
                    : "启用状态已恢复，但 bootstrap 返回退出码 \(bootstrapResult.exitCode)。"
                externalLocalModelStopMessageIsWarning = true
                addActivity(
                    title: "启用模型守护服务",
                    detail: "\(currentRuntime.platform.displayName) · \(currentSupervisor.label) · 等待启动",
                    outcome: .partial
                )
            }
        } catch is CancellationError {
            externalLocalModelStopMessage = "启用守护服务已取消；请重新发现当前状态。"
            externalLocalModelStopMessageIsWarning = true
            await refreshLocalModelRuntimes(force: true)
        } catch {
            externalLocalModelStopMessage = "没有启用守护服务：\(error.localizedDescription)"
            externalLocalModelStopMessageIsWarning = true
            await refreshLocalModelRuntimes(force: true)
        }
    }

    func clearExternalLocalModelStopMessage() {
        externalLocalModelStopMessage = nil
        externalLocalModelStopMessageIsWarning = false
        externalLocalModelForceCandidateID = nil
    }

    private func startLocalModelRuntimeMonitoring() {
        localModelRuntimeMonitorTask?.cancel()
        localModelRuntimeMonitorTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshLocalModelRuntimes()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: .seconds(self.localModelRuntimePollingIntervalSeconds)
                    )
                } catch {
                    break
                }
                await self.refreshLocalModelRuntimes()
            }
        }
    }

    private var localModelRuntimePollingIntervalSeconds: Int {
        guard applicationIsActive else { return 60 }
        if selection == .models { return 10 }
        guard localModelMenuBarEnabled else { return 60 }
        switch localModelDiscoveryPhase {
        case .runningHealthy, .runningUnverified:
            return 15
        case .unknown, .discovering, .stopped, .failed:
            return 30
        }
    }

    func refreshMetricHistory() async {
        guard !demoMode else { return }
        do {
            metricHistory = try await metricsStore.samples(range: metricHistoryRange)
            metricsDiagnostic = metricHistory.isEmpty
                ? "历史记录已开启，等待首次采样。"
                : "每 60 秒本机采样；当前显示 \(metricHistory.count) 个数据点。"
        } catch {
            metricHistory = []
            metricsDiagnostic = "暂时无法读取历史记录：\(error.localizedDescription)"
        }
    }

    func setMetricHistoryRange(_ range: MetricHistoryRange) async {
        metricHistoryRange = range
        await refreshMetricHistory()
    }

    func setMetricsRetentionDays(_ days: Int) async {
        let validDays = Self.validMetricsRetentionDays(days)
        metricsRetentionDays = validDays
        guard !demoMode else {
            metricsDiagnostic = "演示模式：保留期只更新当前合成界面。"
            return
        }
        settings.set(validDays, forKey: "metricsRetentionDays")
        do {
            _ = try await metricsStore.prune(retainingDays: validDays)
            await refreshMetricHistory()
        } catch {
            metricsDiagnostic = "无法更新保留期限：\(error.localizedDescription)"
        }
    }

    func clearMetricHistory() async {
        guard !demoMode else {
            metricHistory = []
            metricsDiagnostic = "演示模式：合成历史已从当前界面清空。"
            return
        }
        do {
            try await metricsStore.clear()
            metricHistory = []
            metricsDiagnostic = "本机历史记录已清空；后续采样会重新开始。"
        } catch {
            metricsDiagnostic = "无法清空历史记录：\(error.localizedDescription)"
        }
    }

    private func prepareMetricsStorage() async {
        do {
            try await metricsStore.prepare()
            _ = try await metricsStore.prune(retainingDays: metricsRetentionDays)
            metricsDiagnostic = "历史记录已开启；进入系统状态时加载图表。"
        } catch {
            metricsDiagnostic = "历史记录未能启用：\(error.localizedDescription)"
        }
    }

    private func startMetricsSampling() {
        metricsSamplingTask?.cancel()
        metricsSamplingIsActive = true
        metricsSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
                guard let self, !self.isWorking, self.engine != nil else { continue }
                await self.refreshSystemStatus(
                    silent: true,
                    includeProcesses: self.selection == .status
                )
            }
            self?.metricsSamplingIsActive = false
        }
    }

    private func recordMetric(_ snapshot: SystemSnapshot) async {
        do {
            try await metricsStore.append(
                MetricSample(
                    snapshot: snapshot,
                    diskUsedPercent: nativeMonitorSample?.diskUsedPercent,
                    diskFreeBytes: nativeMonitorSample?.diskFreeBytes,
                    batteryLevel: nativeMonitorSample?.batteryLevel,
                    temperatureCelsius: nativeMonitorSample?.temperatureCelsius
                )
            )
            _ = try await metricsStore.prune(retainingDays: metricsRetentionDays)
            if selection == .status {
                metricHistory = try await metricsStore.samples(range: metricHistoryRange)
            }
            metricsDiagnostic = "每 60 秒本机采样；保留 \(metricsRetentionDays) 天，不上传。"
        } catch {
            metricsDiagnostic = "本次历史采样未保存：\(error.localizedDescription)"
        }
    }

    func setMenuBarMonitoringEnabled(_ enabled: Bool) {
        menuBarConfiguration.isEnabled = enabled
        persistMenuBarConfiguration()
        if enabled {
            startNativeMonitoring()
        } else {
            nativeMonitorSamplingID = UUID()
            nativeMonitorTask?.cancel()
            nativeMonitorTask = nil
            nativeMonitorIsActive = false
            nativeMonitorDiagnostic = "菜单栏监测已关闭；CleanNest 不再进行 2 秒采样。"
        }
    }

    func setMenuBarMetricEnabled(_ enabled: Bool, metric: MenuBarMetric) {
        menuBarConfiguration.setEnabled(enabled, for: metric)
        menuBarConfiguration = menuBarConfiguration.normalized
        persistMenuBarConfiguration()
    }

    func setMenuBarMetricStyle(_ style: MenuBarMetricStyle, metric: MenuBarMetric) {
        menuBarConfiguration.setStyle(style, for: metric)
        persistMenuBarConfiguration()
    }

    func setMenuBarPresentationMode(_ mode: MenuBarPresentationMode) {
        menuBarConfiguration.presentationMode = mode
        persistMenuBarConfiguration()
    }

    func setMenuBarCompactMetric(_ metric: MenuBarMetric) {
        menuBarConfiguration.compactMetric = metric
        persistMenuBarConfiguration()
    }

    func setMenuBarTemperatureUnit(_ unit: MenuBarTemperatureUnit) {
        menuBarConfiguration.temperatureUnit = unit
        persistMenuBarConfiguration()
    }

    func setMenuBarRefreshInterval(_ interval: MenuBarRefreshInterval) {
        menuBarConfiguration.refreshInterval = interval
        persistMenuBarConfiguration()
        startNativeMonitoring()
    }

    func setMenuBarNetworkMode(_ mode: MenuBarNetworkMode) {
        menuBarConfiguration.networkMode = mode
        persistMenuBarConfiguration()
        startNativeMonitoring()
    }

    func setMenuBarNetworkInterface(_ name: String?) {
        menuBarConfiguration.selectedNetworkInterface = name
        persistMenuBarConfiguration()
        startNativeMonitoring()
    }

    func setMenuBarGlobalHotKeyEnabled(_ enabled: Bool) {
        menuBarConfiguration.globalHotKeyEnabled = enabled
        persistMenuBarConfiguration()
    }

    func moveMenuBarMetric(_ metric: MenuBarMetric, by offset: Int) {
        menuBarConfiguration.move(metric, by: offset)
        persistMenuBarConfiguration()
    }

    func setMenuBarVisibilityDiagnostic(_ value: String) {
        menuBarVisibilityDiagnostic = value
    }

    func setGlobalHotKeyDiagnostic(_ value: String) {
        globalHotKeyDiagnostic = value
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
        } catch {
            launchAtLoginDiagnostic = "登录启动设置未生效：" + error.localizedDescription
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        switch loginItemService.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginRequiresApproval = false
            launchAtLoginDiagnostic = "已由 macOS 登录项管理；下次登录后只在菜单栏安静启动。"
        case .requiresApproval:
            launchAtLoginEnabled = true
            launchAtLoginRequiresApproval = true
            launchAtLoginDiagnostic = "已注册，但 macOS 需要你在“登录项”中允许 CleanNest。"
        case .notRegistered:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginDiagnostic = "未设为登录时启动。"
        case .notFound:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginDiagnostic = "尚未注册登录项；首次开启后会由 macOS 接管。"
        @unknown default:
            launchAtLoginEnabled = false
            launchAtLoginRequiresApproval = false
            launchAtLoginDiagnostic = "macOS 返回了未知的登录启动状态。"
        }
    }

    func openLoginItemsSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func refreshNativeMonitorNow() async {
        guard menuBarConfiguration.isEnabled else { return }
        let sample = await nativeSystemMonitor.sample(configuration: menuBarConfiguration)
        applyNativeMonitorSample(sample)
    }

    private func startNativeMonitoring() {
        nativeMonitorSamplingID = UUID()
        nativeMonitorTask?.cancel()
        guard menuBarConfiguration.isEnabled else {
            nativeMonitorIsActive = false
            return
        }

        let samplingID = nativeMonitorSamplingID
        nativeMonitorIsActive = true
        let refreshSeconds = menuBarConfiguration.refreshInterval.rawValue
        nativeMonitorDiagnostic = "每 \(refreshSeconds) 秒本机采样；不需要 Mole，不上传。"
        nativeMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let configuration = self.menuBarConfiguration
                let sample = await self.nativeSystemMonitor.sample(configuration: configuration)
                guard !Task.isCancelled, self.nativeMonitorSamplingID == samplingID else { break }
                self.applyNativeMonitorSample(sample)
                do {
                    try await Task.sleep(for: .seconds(configuration.refreshInterval.rawValue))
                } catch {
                    break
                }
            }
            guard let self, self.nativeMonitorSamplingID == samplingID else { return }
            self.nativeMonitorIsActive = false
        }
    }

    private func applyNativeMonitorSample(_ sample: NativeMonitorSample) {
        if let free = sample.diskFreeBytes {
            let minimumMeaningfulChange: Int64 = 16 * 1_048_576
            if abs(free - diskFreeBytes) >= minimumMeaningfulChange {
                diskFreeBytes = free
            }
        }
        nativeMonitorHistory.append(sample)
        if nativeMonitorHistory.count > 90 {
            nativeMonitorHistory.removeFirst(nativeMonitorHistory.count - 90)
        }

        var available = 0
        for metric in MenuBarMetric.allCases where sample.value(for: metric) != nil {
            available += 1
        }
        let unavailableSensors = [
            sample.temperatureCelsius == nil ? "温度" : nil,
            sample.gpuUsage == nil ? "GPU" : nil,
            sample.fanCount == nil ? "风扇" : nil,
            sample.batteryStatus == nil ? "电池" : nil
        ].compactMap { $0 }
        let diagnostic: String
        if unavailableSensors.isEmpty {
            diagnostic = "已读取 " + String(available) + " 项本机指标；每 "
                + String(menuBarConfiguration.refreshInterval.rawValue) + " 秒刷新，不上传。"
        } else {
            diagnostic = "已读取 " + String(available) + " 项；"
                + unavailableSensors.joined(separator: "、") + "本次未取得有效值。"
        }
        if nativeMonitorDiagnostic != diagnostic {
            nativeMonitorDiagnostic = diagnostic
        }
        // Publish one coherent UI update after the sample, history and diagnostics agree.
        nativeMonitorSample = sample
    }

    private func persistMenuBarConfiguration() {
        guard !demoMode,
              let data = try? JSONEncoder().encode(menuBarConfiguration.normalized) else { return }
        settings.set(data, forKey: "menuBarMonitorConfiguration")
    }

    func refreshFullDiskAccessProbe() async {
        waitingForFullDiskAccessReturn = false
        didResignAfterOpeningFullDiskAccessSettings = false
        guard !demoMode else {
            fullDiskAccessProbeResult = .accessible
            fullDiskAccessProbeIsRunning = false
            return
        }

        let requestID = UUID()
        fullDiskAccessProbeID = requestID
        fullDiskAccessProbeIsRunning = true
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let result = await Task.detached(priority: .utility) {
            Self.performFullDiskAccessProbe(homeDirectory: homeDirectory)
        }.value
        guard fullDiskAccessProbeID == requestID else { return }

        fullDiskAccessProbeResult = result
        fullDiskAccessProbeIsRunning = false
        if result == .accessible {
            diskPrivacyBlockMessage = nil
        }
        if let selectedApplication {
            await loadLeftovers(for: selectedApplication)
        }
    }

    func applicationDidResignActive() {
        applicationIsActive = false
        agentWorkspaceMonitorTask?.cancel()
        agentWorkspaceMonitorTask = nil
        guard waitingForFullDiskAccessReturn else { return }
        didResignAfterOpeningFullDiskAccessSettings = true
    }

    func applicationDidBecomeActive() async {
        applicationIsActive = true
        if selection == .agentWorkspace, activeLifecyclePage == .agentWorkspace {
            startAgentWorkspaceMonitoring()
        }
        if !demoMode,
           Date().timeIntervalSince(localModelRuntimeSnapshot.capturedAt) >= 15 {
            await refreshLocalModelRuntimes()
        }
        guard waitingForFullDiskAccessReturn,
              didResignAfterOpeningFullDiskAccessSettings else { return }
        waitingForFullDiskAccessReturn = false
        didResignAfterOpeningFullDiskAccessSettings = false
        await refreshFullDiskAccessProbe()
    }

    func diskTraversalMayRequireFullDiskAccess(_ root: URL) -> Bool {
        DiskPrivacyPolicy.assessTraversal(
            root: root,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ).mayRequireFullDiskAccess
    }

    nonisolated private static func performFullDiskAccessProbe(
        homeDirectory: URL
    ) -> FullDiskAccessProbeResult {
        let probeURL = homeDirectory
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db", isDirectory: false)
            .standardizedFileURL
        let descriptor = probeURL.path.withCString { path in
            Darwin.open(path, O_RDONLY | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            return FullDiskAccessProbeResult.classify(errno: errno)
        }
        Darwin.close(descriptor)
        return .accessible
    }

    func refreshEngine() async {
        phase = .checking
        guard let executable = EngineLocator.locate(customPath: customEnginePath) else {
            engine = nil
            engineDiagnostic = EngineLocator.locateHomebrew() == nil
                ? "未找到 Mole CLI，且未检测到 Homebrew。"
                : "未找到 Mole CLI，可以直接在 App 内安装。"
            phase = .idle
            return
        }

        do {
            let result = try await commandRunner.runChecked(executable: executable, arguments: ["--version"])
            let version = result.standardOutput
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: "\n")
                .first
                .map(String.init)
            engine = EngineInstallation(executable: executable, version: version)
            engineDiagnostic = "引擎已就绪"
            phase = .idle
        } catch {
            engine = nil
            engineDiagnostic = error.localizedDescription
            phase = .failed("引擎检查未通过")
            lastTechnicalDetail = error.localizedDescription
        }
    }

    func installEngine() async {
        guard !demoMode else { return }
        guard let brew = EngineLocator.locateHomebrew() else {
            phase = .failed("这台 Mac 尚未安装 Homebrew")
            lastTechnicalDetail = "CleanNest 当前通过 Homebrew 安装 Mole CLI。可在设置中选择已经存在的 mo/mole 可执行文件。"
            return
        }

        phase = .executing("正在安装本地清理引擎…")
        do {
            let result = try await commandRunner.runChecked(
                executable: brew,
                arguments: ["install", "mole"],
                environment: commandEnvironment
            )
            lastTechnicalDetail = result.standardOutput + result.standardError
            addActivity(title: "安装清理引擎", detail: "Mole CLI 已通过 Homebrew 安装。", outcome: .success)
            await refreshEngine()
        } catch {
            phase = .failed("安装没有完成，尚未更改任何清理项目")
            lastTechnicalDetail = error.localizedDescription
            addActivity(title: "安装清理引擎", detail: error.localizedDescription, outcome: .failed)
        }
    }

    func updateEngine() async {
        guard !demoMode else { return }
        guard engineCanUpdateWithHomebrew else {
            phase = .failed("自定义引擎不由 Homebrew 管理")
            lastTechnicalDetail = "请使用你选择的安装方式更新该引擎，然后在 CleanNest 中重新检测。"
            return
        }
        guard let brew = EngineLocator.locateHomebrew() else {
            phase = .failed("未检测到 Homebrew")
            return
        }
        phase = .executing("正在检查引擎更新…")
        do {
            let result = try await commandRunner.run(
                executable: brew,
                arguments: ["upgrade", "mole"],
                environment: commandEnvironment
            )
            lastTechnicalDetail = result.standardOutput + result.standardError
            guard result.exitCode == 0 else { throw CommandRunnerError.nonZeroExit(result) }
            addActivity(title: "更新清理引擎", detail: "Mole CLI 已检查并更新。", outcome: .success)
            await refreshEngine()
        } catch {
            phase = .failed("更新没有完成")
            lastTechnicalDetail = error.localizedDescription
            addActivity(title: "更新清理引擎", detail: error.localizedDescription, outcome: .failed)
        }
    }

    func setCustomEnginePath(_ path: String) async {
        guard !demoMode else { return }
        customEnginePath = path
        settings.set(path, forKey: "customEnginePath")
        await refreshEngine()
    }

    func setLocalAIEnabled(_ enabled: Bool) {
        localAIEnabled = enabled
        if !demoMode { settings.set(enabled, forKey: "localAIEnabled") }
        localAIProbeID = UUID()
        invalidateCleanupAI()
        invalidateDiskAI()
        localAIBenchmarkPhase = .idle
        localAIBenchmarkResult = nil
        localAIProbeLatencyMilliseconds = nil

        if enabled {
            localAIServiceState = .unchecked
            Task { await probeLocalAI() }
        } else {
            localAIRuntime.stopOwnedProcess()
            localAIProcessOwned = false
            localAIServiceState = .disabled
            localAIDiagnostic = "本机 AI 已关闭"
        }
    }

    func applyLocalAISettings(
        endpoint: String,
        serviceModelID: String,
        modelPath: String,
        executablePath: String
    ) async -> Bool {
        let validatedEndpoint: LocalAIEndpoint
        let validatedModelURL: URL?
        let normalizedServiceModelID: String
        let normalizedExecutablePath: String
        do {
            validatedEndpoint = try LocalAIEndpoint(rawValue: endpoint)
            let trimmedModelPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
            validatedModelURL = trimmedModelPath.isEmpty
                ? nil
                : try Self.validatedLocalModelURL(path: trimmedModelPath)
            normalizedServiceModelID = try Self.validatedServiceModelID(serviceModelID)
            let executable = executablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard executable.isEmpty || (executable as NSString).isAbsolutePath else {
                throw LocalAIError.requestFailed("mlx_lm.server 必须使用完整路径")
            }
            normalizedExecutablePath = executable.isEmpty
                ? ""
                : URL(fileURLWithPath: executable).standardizedFileURL.path
        } catch {
            localAIConfigurationError = error.localizedDescription
            localAIDiagnostic = error.localizedDescription
            return false
        }

        let nextEndpoint = validatedEndpoint.baseURL.absoluteString
        let nextModelPath = validatedModelURL?.path ?? ""
        let previousConfiguration = [
            localAIEndpoint,
            localAIServiceModelID,
            localAIModelPath,
            localAIExecutablePath
        ]
        let nextConfiguration = [
            nextEndpoint,
            normalizedServiceModelID,
            nextModelPath,
            normalizedExecutablePath
        ]
        let configurationChanged = previousConfiguration != nextConfiguration
        let runtimeConfigurationChanged = localAIEndpoint != nextEndpoint || localAIModelPath != nextModelPath
        let configurationID = UUID()
        localAIProbeID = configurationID

        if runtimeConfigurationChanged, localAIRuntime.ownsRunningProcess {
            localAIServiceState = .stopping
            localAIDiagnostic = "正在停止旧的本机模型进程…"
            let stopped = await localAIRuntime.stopOwnedProcessAndWait()
            localAIProcessOwned = localAIRuntime.ownsRunningProcess
            guard localAIProbeID == configurationID else { return false }
            guard stopped else {
                let detail = "旧模型进程未能及时停止，设置尚未更改"
                localAIConfigurationError = detail
                localAIServiceState = .unavailable(detail)
                return false
            }
        }

        localAIEndpoint = nextEndpoint
        localAIServiceModelID = normalizedServiceModelID
        localAIModelPath = nextModelPath
        localAIExecutablePath = normalizedExecutablePath
        persistLocalAISettings()
        if let validatedModelURL,
           !localAIAvailableModels.contains(where: { $0.path == nextModelPath }),
           let model = localModelCatalog.descriptor(at: validatedModelURL) {
            localAIAvailableModels = (localAIAvailableModels + [model]).sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        }
        localAIConfigurationError = nil
        if configurationChanged {
            invalidateCleanupAI()
            invalidateDiskAI()
            localAIBenchmarkPhase = .idle
            localAIBenchmarkResult = nil
            localAIProbeLatencyMilliseconds = nil
        }

        if localAIEnabled {
            await probeLocalAI()
        } else {
            localAIServiceState = .disabled
        }
        await refreshLocalModelRuntimes()
        return true
    }

    func stopLocalAI() async {
        defer { Task { await self.refreshLocalModelRuntimes() } }
        guard localAIRuntime.ownsRunningProcess else { return }
        let stopID = UUID()
        localAIProbeID = stopID
        invalidateCleanupAI()
        invalidateDiskAI()
        localAIServiceState = .stopping
        localAIDiagnostic = "正在停止 CleanNest 启动的模型进程…"
        let stopped = await localAIRuntime.stopOwnedProcessAndWait()
        localAIProcessOwned = localAIRuntime.ownsRunningProcess
        guard localAIEnabled, localAIProbeID == stopID else { return }
        if stopped {
            localAIServiceState = .unavailable("本机模型已停止，可随时重新启动")
            localAIDiagnostic = "本机模型已停止"
        } else {
            localAIServiceState = .unavailable("模型进程未能及时停止，请稍后重试")
            localAIDiagnostic = "模型进程仍在退出"
        }
    }

    func probeLocalAI() async {
        guard !demoMode else { return }
        guard localAIEnabled else {
            localAIServiceState = .disabled
            return
        }

        let probeID = UUID()
        localAIProbeID = probeID
        localAIServiceState = .checking
        localAIProbeLatencyMilliseconds = nil
        localAIAvailableServiceModelIDs = []
        localAIDefaultServiceModelID = nil
        let probeStartedAt = Date()
        do {
            let (modelID, result) = try await probeConfiguredLocalAI()
            guard localAIProbeID == probeID else { return }
            updateServiceModelCatalog(from: result)
            localAIProcessOwned = localAIRuntime.ownsRunningProcess
            localAIServiceState = .ready(modelID: modelID)
            localAIProbeLatencyMilliseconds = max(0, Date().timeIntervalSince(probeStartedAt) * 1_000)
            localAIDiagnostic = "已连接本机回环服务；API 模型为 \(modelID)。文件内容不会发送给模型。"
        } catch {
            guard localAIProbeID == probeID else { return }
            localAIProcessOwned = localAIRuntime.ownsRunningProcess
            localAIServiceState = .unavailable(error.localizedDescription)
            localAIDiagnostic = error.localizedDescription
        }
    }

    func runLocalAIBenchmark() async {
        guard !demoMode else { return }
        guard case .ready(let modelID) = localAIServiceState,
              !localAIBenchmarkPhase.isRunning else { return }
        localAIBenchmarkPhase = .running
        localAIBenchmarkResult = nil
        do {
            let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
            let result = try await client.benchmark(modelID: modelID)
            guard case .ready(let currentModelID) = localAIServiceState,
                  currentModelID == modelID else {
                localAIBenchmarkPhase = .idle
                return
            }
            localAIBenchmarkResult = result
            localAIBenchmarkPhase = .completed
            localAIDiagnostic = "最小推理测速完成：首字 \(Int(result.firstTokenMilliseconds.rounded())) ms，总耗时 \(Int(result.totalMilliseconds.rounded())) ms。"
        } catch is CancellationError {
            localAIBenchmarkPhase = .idle
        } catch {
            localAIBenchmarkPhase = .failed(error.localizedDescription)
            localAIDiagnostic = error.localizedDescription
        }
    }

    func startLocalAI() async {
        defer { Task { await self.refreshLocalModelRuntimes() } }
        guard !demoMode, localAIEnabled, !localAIServiceState.isBusy else { return }
        persistLocalAISettings()
        let startupID = UUID()
        localAIProbeID = startupID
        localAIServiceState = .starting

        do {
            let endpoint = try LocalAIEndpoint(rawValue: localAIEndpoint)

            let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
            if let runningService = try? await client.probe() {
                guard localAIEnabled, localAIProbeID == startupID else { return }
                updateServiceModelCatalog(from: runningService)
                let modelID = try resolvedServiceModelID(from: runningService)
                localAIServiceState = .ready(modelID: modelID)
                localAIProcessOwned = localAIRuntime.ownsRunningProcess
                localAIDiagnostic = "已复用正在运行的本机模型服务；API 模型为 \(modelID)。"
                return
            }
            guard localAIEnabled, localAIProbeID == startupID else { return }

            let modelURL = try configuredLocalModelURL()
            let executable = URL(
                fileURLWithPath: localAIExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
            ).standardizedFileURL
            try localAIRuntime.start(executable: executable, modelDirectory: modelURL, port: endpoint.port)
            localAIProcessOwned = true

            var lastError: Error = LocalAIError.serviceUnavailable("模型仍在载入")
            let startupDeadline = Date().addingTimeInterval(90)
            while Date() < startupDeadline {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 500_000_000)
                guard localAIEnabled, localAIProbeID == startupID else {
                    localAIRuntime.stopOwnedProcess()
                    localAIProcessOwned = false
                    return
                }
                do {
                    let result = try await client.probe()
                    guard localAIEnabled, localAIProbeID == startupID else {
                        localAIRuntime.stopOwnedProcess()
                        localAIProcessOwned = false
                        return
                    }
                    updateServiceModelCatalog(from: result)
                    let modelID = try resolvedServiceModelID(from: result)
                    localAIServiceState = .ready(modelID: modelID)
                    localAIProcessOwned = true
                    localAIDiagnostic = "模型已由 CleanNest 在本机启动；API 模型为 \(modelID)。"
                    return
                } catch {
                    lastError = error
                    if !localAIRuntime.ownsRunningProcess { break }
                }
            }

            localAIRuntime.stopOwnedProcess()
            localAIProcessOwned = false
            let log = localAIRuntime.recentLog.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = log.isEmpty ? "" : "\n\n模型日志：\n\(log)"
            throw LocalAIError.serviceUnavailable(lastError.localizedDescription + suffix)
        } catch is CancellationError {
            localAIRuntime.stopOwnedProcess()
            localAIProcessOwned = false
            guard localAIEnabled, localAIProbeID == startupID else { return }
            localAIServiceState = .unavailable("模型启动已取消")
        } catch {
            guard localAIEnabled, localAIProbeID == startupID else { return }
            localAIProcessOwned = localAIRuntime.ownsRunningProcess
            localAIServiceState = .unavailable(error.localizedDescription)
            localAIDiagnostic = error.localizedDescription
        }
    }

    func analyzeCleanupWithLocalAI() async {
        guard !demoMode else {
            cleanupAIPhase = .completed
            return
        }
        guard localAIEnabled, !cleanupCandidates.isEmpty, !cleanupAIPhase.isBusy else { return }

        let requestID = UUID()
        activeAIRequestID = requestID
        let revision = cleanupRevision
        cleanupAIPhase = .analyzing
        cleanupAIAnalysis = nil

        await probeLocalAI()
        guard activeAIRequestID == requestID, cleanupRevision == revision else { return }
        guard case .ready(let readyModelID) = localAIServiceState else {
            cleanupAIPhase = .failed("本机模型尚未连接，可在设置中检测或启动。")
            return
        }

        do {
            let snapshot = try CleanupAIRequestBuilder.makeSnapshot(
                candidates: cleanupCandidates,
                diskTotalBytes: diskTotalBytes,
                diskFreeBytes: diskFreeBytes,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
            let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
            let analysis = try await client.analyzeCleanup(snapshot: snapshot, modelID: readyModelID)
            guard activeAIRequestID == requestID, cleanupRevision == revision else { return }

            let currentIDs = Set(cleanupCandidates.map(\.id))
            guard analysis.advice.allSatisfy({ currentIDs.contains($0.candidateID) }) else {
                throw LocalAIError.invalidResponse("结果与当前扫描不一致")
            }
            cleanupAIAnalysis = analysis
            cleanupAIPhase = .completed
            localAIDiagnostic = "已用 \(localAIModelDisplayName) 分析 \(analysis.requestedCount) 项元数据。"
        } catch is CancellationError {
            guard activeAIRequestID == requestID else { return }
            cleanupAIPhase = .idle
        } catch {
            guard activeAIRequestID == requestID, cleanupRevision == revision else { return }
            cleanupAIPhase = .failed(error.localizedDescription)
            localAIDiagnostic = error.localizedDescription
            if let localError = error as? LocalAIError,
               case .serviceUnavailable = localError {
                localAIServiceState = .unavailable(error.localizedDescription)
            }
        }
    }

    func aiAdvice(for candidate: CleanupCandidate) -> CleanupAIAdvice? {
        cleanupAIAnalysis?.advice.first { $0.candidateID == candidate.id }
    }

    func learnedCleanupPreference(for candidate: CleanupCandidate) -> LearnedCleanupPreference? {
        evolutionMemory.cleanupPreference(for: candidate)
    }

    func cleanupLearningSignal(for candidate: CleanupCandidate) -> CleanupLearningSignal? {
        evolutionMemory.cleanupSignal(for: candidate)
    }

    func cleanupRuleProposal(for candidate: CleanupCandidate) -> CleanupRuleProposal? {
        evolutionMemory.ruleProposal(for: candidate)
    }

    func cleanupLearningRank(for candidate: CleanupCandidate) -> Int {
        switch learnedCleanupPreference(for: candidate) {
        case .preferCleanup: return 0
        case nil: return 1
        case .preferKeep: return 2
        }
    }

    func rememberCleanupPreference(
        _ candidate: CleanupCandidate,
        preference: LearnedCleanupPreference
    ) {
        ensureEvolutionMemoryLoaded()
        evolutionMemory.proposeCleanupPreference(
            for: candidate,
            preference: preference,
            reason: preference == .preferCleanup
                ? "你明确提出以后优先复核这个项目。"
                : "你明确提出以后优先保留这个项目。"
        )
        saveEvolutionMemory()
    }

    func forgetCleanupPreference(_ candidate: CleanupCandidate) {
        ensureEvolutionMemoryLoaded()
        evolutionMemory.removeRuleProposal(id: EvolutionMemory.cleanupKey(for: candidate))
        saveEvolutionMemory()
    }

    func enableCleanupRule(_ id: String) {
        ensureEvolutionMemoryLoaded()
        evolutionMemory.enableRuleProposal(id: id)
        saveEvolutionMemory()
    }

    func pauseCleanupRule(_ id: String) {
        ensureEvolutionMemoryLoaded()
        evolutionMemory.pauseRuleProposal(id: id)
        saveEvolutionMemory()
    }

    func removeCleanupRule(_ id: String) {
        ensureEvolutionMemoryLoaded()
        evolutionMemory.removeRuleProposal(id: id)
        saveEvolutionMemory()
    }

    func recordCleanupAIFeedback(helpful: Bool) {
        ensureEvolutionMemoryLoaded()
        guard cleanupAIFeedback == nil, let analysis = cleanupAIAnalysis else { return }
        cleanupAIFeedback = helpful
        evolutionMemory.recordModelFeedback(
            modelID: analysis.modelID,
            displayName: localAIModelDisplayName,
            helpful: helpful,
            scope: "清理建议"
        )
        saveEvolutionMemory()
    }

    func recordDiskAIFeedback(helpful: Bool) {
        ensureEvolutionMemoryLoaded()
        guard diskAIFeedback == nil, let analysis = diskAIAnalysis else { return }
        diskAIFeedback = helpful
        evolutionMemory.recordModelFeedback(
            modelID: analysis.modelID,
            displayName: localAIModelDisplayName,
            helpful: helpful,
            scope: "磁盘解读"
        )
        saveEvolutionMemory()
    }

    func resetEvolutionMemory() {
        evolutionMemory = EvolutionMemory()
        hasLoadedEvolutionMemory = true
        cleanupAIFeedback = nil
        diskAIFeedback = nil
        saveEvolutionMemory()
    }

    func shutdownLocalAI() {
        localAIRuntime.stopOwnedProcess()
        localAIProcessOwned = false
    }

    func shutdownForTermination() {
        metricsSamplingTask?.cancel()
        metricsSamplingTask = nil
        nativeMonitorSamplingID = UUID()
        nativeMonitorTask?.cancel()
        nativeMonitorTask = nil
        localModelDiscoveryID = UUID()
        localModelRuntimeMonitorTask?.cancel()
        localModelRuntimeMonitorTask = nil
        localModelDiscoveryIsRunning = false
        agentWorkspaceScanID = UUID()
        activeAgentWorkspaceScanTask?.cancel()
        activeAgentWorkspaceScanTask = nil
        agentWorkspaceMonitorTask?.cancel()
        agentWorkspaceMonitorTask = nil
        agentWorkspaceReleaseTask?.cancel()
        agentWorkspaceReleaseTask = nil
        systemStatusReleaseTask?.cancel()
        systemStatusReleaseTask = nil
        activeDiskScanTask?.cancel()
        activeDiskScanTask = nil
        invalidateCleanupAI()
        _ = invalidateDiskAI()
        commandRunner.terminateAll()
        shutdownLocalAI()
    }

    func refreshSystemStatus(
        silent: Bool = false,
        includeProcesses: Bool = true
    ) async {
        guard !demoMode else { return }
        let inspector = processMemoryInspector
        let nativeMemoryTask = Task.detached(priority: .utility) {
            SystemMemoryProbe.sample()
        }
        let processTask: Task<[MemoryProcessSnapshot], Never>? = includeProcesses
            ? Task.detached(priority: .utility) { inspector.topProcesses(limit: 16) }
            : nil
        let batteryTask: Task<BatteryProbeResult, Never>? = includeProcesses
            ? Task.detached(priority: .utility) { PowerSourceProbe.sample() }
            : nil
        guard let engine else {
            _ = await nativeMemoryTask.value
            let processes = await processTask?.value ?? []
            if let batteryTask {
                batteryProbeResult = await batteryTask.value
            }
            if includeProcesses {
                memoryProcesses = processes
            }
            if includeProcesses, let systemSnapshot {
                memoryAnalysis = MemoryAnalyzer.analyze(
                    snapshot: systemSnapshot,
                    processes: processes
                )
            }
            if !silent { phase = .failed("需要先安装或选择 Mole CLI") }
            return
        }
        if !silent { phase = .scanning("正在读取这台 Mac 的状态…") }

        do {
            let result = try await commandRunner.runChecked(
                executable: engine.executable,
                arguments: ["status", "--json"],
                environment: commandEnvironment
            )
            guard let data = result.standardOutput.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let nativeMemory = await nativeMemoryTask.value
            let processes = await processTask?.value ?? []
            if let batteryTask {
                batteryProbeResult = await batteryTask.value
            }
            let snapshot = try MoleJSONDecoder.systemSnapshot(
                from: data,
                memoryProbe: nativeMemory
            )
            systemSnapshot = snapshot
            if includeProcesses {
                memoryProcesses = processes
                memoryAnalysis = MemoryAnalyzer.analyze(
                    snapshot: snapshot,
                    processes: processes
                )
            }
            if let forceID = forceTerminationProcessID,
               includeProcesses,
               !processes.contains(where: { $0.id == forceID }) {
                forceTerminationProcessID = nil
            }
            lastTechnicalDetail = result.standardError
            refreshDiskCapacity()
            await recordMetric(snapshot)
            phase = .idle
        } catch {
            _ = await nativeMemoryTask.value
            let processes = await processTask?.value ?? []
            if let batteryTask {
                batteryProbeResult = await batteryTask.value
            }
            if includeProcesses {
                memoryProcesses = processes
            }
            if includeProcesses, let systemSnapshot {
                memoryAnalysis = MemoryAnalyzer.analyze(
                    snapshot: systemSnapshot,
                    processes: processes
                )
            }
            if !silent { phase = .failed("系统状态暂时不可用") }
            lastTechnicalDetail = error.localizedDescription
        }
    }

    func terminateMemoryProcess(_ process: MemoryProcessSnapshot, force: Bool = false) async {
        guard !demoMode else {
            memoryProcessMessage = "演示模式不会结束任何进程。"
            memoryProcessMessageIsWarning = false
            return
        }
        guard terminatingMemoryProcessID == nil else { return }
        terminatingMemoryProcessID = process.id
        memoryProcessMessage = nil
        memoryProcessMessageIsWarning = false

        let inspector = processMemoryInspector
        let result = await Task.detached(priority: .userInitiated) {
            inspector.terminate(process, force: force)
        }.value
        terminatingMemoryProcessID = nil

        switch result {
        case .terminated:
            forceTerminationProcessID = nil
            memoryProcessMessage = force
                ? "“\(process.name)”已被强制结束。"
                : "“\(process.name)”已正常退出。"
            addActivity(
                title: force ? "强制结束进程" : "结束进程",
                detail: "\(process.name) · PID \(process.pid)",
                outcome: .success,
                affectedItems: 1
            )

        case .stillRunning:
            forceTerminationProcessID = process.id
            memoryProcessMessage = "“\(process.name)”没有退出。它可能正在保存数据、没有响应，或已被所属 App 重新启动；如确有需要，可再次确认后强制结束。"
            memoryProcessMessageIsWarning = true

        case .alreadyExited, .identityChanged:
            forceTerminationProcessID = nil
            memoryProcessMessage = "原进程已经退出或被重新启动，CleanNest 没有向新的进程发送信号。"

        case .refused(let reason):
            forceTerminationProcessID = nil
            memoryProcessMessage = reason
            memoryProcessMessageIsWarning = true

        case .failed(let reason):
            forceTerminationProcessID = nil
            memoryProcessMessage = "没有结束“\(process.name)”：\(reason)"
            memoryProcessMessageIsWarning = true
        }

        let refreshed = await Task.detached(priority: .utility) {
            inspector.topProcesses(limit: 16)
        }.value
        memoryProcesses = refreshed
        if let systemSnapshot {
            memoryAnalysis = MemoryAnalyzer.analyze(snapshot: systemSnapshot, processes: refreshed)
        }
        if let forceID = forceTerminationProcessID,
           !refreshed.contains(where: { $0.id == forceID }) {
            forceTerminationProcessID = nil
        }
    }

    func scanCleanup() async {
        guard !demoMode else { return }
        ensureEvolutionMemoryLoaded()
        guard !isWorking, activeCleanupScanTask == nil else { return }
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.performCleanupScan()
        }
        activeCleanupScanTask = task
        cleanupScanIsActive = true
        await task.value
        activeCleanupScanTask = nil
        cleanupScanIsActive = false
        if case .scanning = phase { phase = .idle }
    }

    func cancelCleanupScan() {
        activeCleanupScanTask?.cancel()
        phase = .scanning("正在取消清理扫描…")
        lastTechnicalDetail = "本次独立扫描已取消；上一次完整结果保持不变。"
    }

    private func performCleanupScan() async {
        invalidateCleanupAI()
        phase = .scanning("正在启动独立扫描服务…")
        let request = CleanupScannerRequest(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            includeApplicationCaches: includeApplicationCaches,
            includeMediaAndDuplicates: includeMediaAndDuplicates,
            developerMode: developerMode
        )
        do {
            let response = try await scannerServiceClient.scanCleanup(request) { [weak self] progress in
                await self?.applyScannerProgress(progress)
            }
            try Task.checkCancellation()
            guard response.requestID == request.requestID else {
                throw ScannerServiceClientError.invalidResponse
            }
            cleanupCandidates = response.candidates
            cleanupScanInsights = response.insights
            cleanupScanIncludedMediaAndDuplicates = includeMediaAndDuplicates
            selectedCleanupIDs = Set(response.candidates.filter(\.isRecommended).map(\.id))
            cleanupHasScanned = true
            await refreshMountedInstallerVolumes(reportFailure: true)
            persistCleanupPreview()
            lastTechnicalDetail = "独立扫描服务已完成 \(response.candidates.count) 项结果，耗时 \(String(format: "%.2f", response.elapsedSeconds)) 秒；高成本文件遍历未在 CleanNest 主进程内执行。"
            phase = .idle
        } catch is CancellationError {
            phase = .idle
            lastTechnicalDetail = "清理扫描已取消；上一次完整结果保持不变。"
        } catch {
            phase = .failed("清理扫描没有完成")
            lastTechnicalDetail = error.localizedDescription
        }
    }

    private func relieveAllocatorPressure() async -> UInt64 {
        await Task.detached(priority: .utility) {
            UInt64(malloc_zone_pressure_relief(nil, 0))
        }.value
    }

    nonisolated private static func reportableByteCount(_ bytes: UInt64) -> Int64 {
        bytes > UInt64(Int64.max) ? Int64.max : Int64(bytes)
    }

    func toggleCleanup(_ candidate: CleanupCandidate) {
        if selectedCleanupIDs.contains(candidate.id) {
            selectedCleanupIDs.remove(candidate.id)
        } else {
            selectedCleanupIDs.insert(candidate.id)
        }
    }

    func selectAllCleanup() {
        selectedCleanupIDs = Set(cleanupCandidates.map(\.id))
    }

    func setCleanupSelection(_ candidates: [CleanupCandidate], selected: Bool) {
        let ids = Set(candidates.map(\.id))
        if selected {
            selectedCleanupIDs.formUnion(ids)
        } else {
            selectedCleanupIDs.subtract(ids)
        }
    }

    func clearCleanupSelection() {
        selectedCleanupIDs.removeAll()
    }

    func refreshMountedInstallerVolumes(reportFailure: Bool = false) async {
        guard !demoMode else {
            mountedInstallerVolumes = []
            return
        }
        do {
            mountedInstallerVolumes = try await MountedInstallerProbe().discover(using: commandRunner)
            mountedInstallerMessage = nil
            mountedInstallerMessageIsWarning = false
        } catch {
            mountedInstallerVolumes = []
            if reportFailure {
                mountedInstallerMessage = CNL10n.format(
                    "已完成文件扫描，但没有读到已挂载的安装介质：%@",
                    error.localizedDescription
                )
                mountedInstallerMessageIsWarning = true
                lastTechnicalDetail += "\n挂载安装介质检测：\(error.localizedDescription)"
            }
        }
    }

    func ejectMountedInstaller(_ candidate: MountedInstallerVolume) async {
        guard !demoMode, ejectingMountedInstallerID == nil else { return }
        ejectingMountedInstallerID = candidate.id
        mountedInstallerMessage = nil
        mountedInstallerMessageIsWarning = false
        phase = .executing(CNL10n.format("正在安全推出 %@…", candidate.displayName))
        defer { ejectingMountedInstallerID = nil }

        do {
            let liveVolumes = try await MountedInstallerProbe().discover(using: commandRunner)
            guard let live = liveVolumes.first(where: {
                MountedInstallerProbe.hasSameLiveIdentity(candidate, $0)
            }) else {
                mountedInstallerVolumes = liveVolumes
                mountedInstallerMessage = CNL10n.string("挂载卷已经消失或身份发生变化，CleanNest 没有发送推出命令。")
                mountedInstallerMessageIsWarning = true
                phase = .failed(CNL10n.string("安装介质状态已变化"))
                return
            }
            guard MountedInstallerProbe.isSafeEjectTarget(live) else {
                mountedInstallerMessage = CNL10n.string("安全校验未通过：目标不是 /Volumes 下的当前用户磁盘映像。")
                mountedInstallerMessageIsWarning = true
                phase = .failed(CNL10n.string("没有推出安装介质"))
                return
            }

            let result = try await commandRunner.run(
                executable: MountedInstallerProbe.hdiutilURL,
                arguments: ["detach", live.mountURL.path],
                timeout: 20
            )
            guard result.exitCode == 0 else {
                let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
                mountedInstallerVolumes = liveVolumes
                mountedInstallerMessage = detail.isEmpty
                    ? CNL10n.string("系统没有接受推出请求，可能仍有安装程序正在使用该卷。")
                    : CNL10n.format("未能推出：%@", detail)
                mountedInstallerMessageIsWarning = true
                phase = .failed(CNL10n.string("未能推出安装介质"))
                return
            }

            let remaining = try await MountedInstallerProbe().discover(using: commandRunner)
            mountedInstallerVolumes = remaining
            if remaining.contains(where: {
                MountedInstallerProbe.hasSameLiveIdentity(candidate, $0)
            }) {
                mountedInstallerMessage = CNL10n.string("系统返回成功，但该挂载卷仍然存在；请重新扫描后再试。")
                mountedInstallerMessageIsWarning = true
                phase = .failed(CNL10n.string("安装介质仍然存在"))
                return
            }

            mountedInstallerMessage = CNL10n.format(
                "已安全推出“%@”；没有删除或移动任何文件。",
                candidate.displayName
            )
            mountedInstallerMessageIsWarning = false
            phase = .success(CNL10n.format("已安全推出 %@", candidate.displayName))
        } catch is CancellationError {
            phase = .idle
        } catch {
            mountedInstallerMessage = CNL10n.format(
                "没有推出“%@”：%@",
                candidate.displayName,
                error.localizedDescription
            )
            mountedInstallerMessageIsWarning = true
            phase = .failed(CNL10n.string("未能推出安装介质"))
        }
    }

    func trashSelectedCleanup() async {
        guard !demoMode else {
            phase = .success("演示模式不会更改任何文件")
            return
        }
        let currentIDs = Set(cleanupCandidates.map(\.id))
        let effectiveIDs = selectedCleanupIDs.intersection(currentIDs)
        let selected = cleanupCandidates.filter { effectiveIDs.contains($0.id) }
        guard !selected.isEmpty else { return }

        phase = .executing("正在把所选内容移到废纸篓…")
        let outcomes = await trashService.trashCleanupCandidates(selected)
        let succeededPaths = Set(outcomes.filter(\.succeeded).map { $0.source.standardizedFileURL.path })
        let failed = outcomes.filter { !$0.succeeded }
        let released = selected
            .filter { succeededPaths.contains($0.url.standardizedFileURL.path) }
            .reduce(0) { $0 + $1.allocatedBytes }
        let succeededCandidates = selected.filter {
            succeededPaths.contains($0.url.standardizedFileURL.path)
        }

        for candidate in succeededCandidates {
            evolutionMemory.recordCleanup(candidate, decision: .cleaned)
        }
        if !succeededCandidates.isEmpty { saveEvolutionMemory() }

        cleanupCandidates.removeAll { succeededPaths.contains($0.url.standardizedFileURL.path) }
        cleanupScanInsights = cleanupScanInsights.updatingCandidateCounts(from: cleanupCandidates)
        selectedCleanupIDs.subtract(selected.map(\.id))
        invalidateCleanupAI()
        refreshDiskCapacity()
        persistCleanupPreview()

        if failed.isEmpty {
            phase = .success("已把 \(succeededPaths.count) 项移到废纸篓")
            addActivity(
                title: "清理空间",
                detail: "所选内容已移到废纸篓，可在清空前恢复。",
                outcome: .success,
                affectedItems: succeededPaths.count,
                bytes: released,
                category: .cleanup
            )
        } else {
            phase = .failed("已完成 \(succeededPaths.count) 项，\(failed.count) 项未成功")
            lastTechnicalDetail = failed.map { "\($0.source.path): \($0.errorDescription ?? "未知错误")" }.joined(separator: "\n")
            addActivity(
                title: "清理空间",
                detail: "部分项目因权限或路径变化被安全跳过。",
                outcome: .partial,
                affectedItems: succeededPaths.count,
                bytes: released,
                category: .cleanup
            )
        }
    }

    func scanApplications() async {
        guard !demoMode else { return }
        guard !isWorking else { return }
        phase = .scanning("正在读取已安装的 App…")
        applications = await applicationScanner.scan()
        applicationsHaveScanned = true
        phase = .idle
        if selectedApplication == nil { selectedApplication = applications.first }
        if let selectedApplication { await loadLeftovers(for: selectedApplication) }
    }

    func chooseApplication(_ application: InstalledApplication) async {
        selectedApplication = application
        await loadLeftovers(for: application)
    }

    func loadLeftovers(for application: InstalledApplication) async {
        guard !demoMode else { return }
        let requestID = UUID()
        leftoverRequestID = requestID
        selectedApplicationLeftovers = []
        let results = await applicationScanner.leftovers(
            for: application,
            includeProtectedAppData: fullDiskAccessProbePassed
        )
        guard leftoverRequestID == requestID, selectedApplication?.id == application.id else { return }
        selectedApplicationLeftovers = results
    }

    func applicationIsRunning(_ application: InstalledApplication) -> Bool {
        guard !demoMode else { return false }
        guard let bundleID = application.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func applicationRemovalRequirement(
        for application: InstalledApplication
    ) -> ApplicationRemovalRequirement? {
        guard !demoMode else { return .standard }
        guard let expectedIdentity = application.fileIdentity else { return nil }
        return try? trashService.applicationRemovalRequirement(
            for: application.url,
            expectedIdentity: expectedIdentity,
            expectedBundleIdentifier: application.bundleIdentifier
        )
    }

    func askApplicationToQuit(_ application: InstalledApplication) {
        guard !demoMode else { return }
        guard let bundleID = application.bundleIdentifier else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }

    func uninstallSelectedApplication(includeLeftovers: Bool) async {
        guard let application = selectedApplication else { return }
        guard !demoMode else {
            phase = .success("演示模式不会卸载 App")
            return
        }
        guard !applicationIsRunning(application) else {
            phase = .failed("请先退出 \(application.name)")
            return
        }
        guard let expectedIdentity = application.fileIdentity else {
            phase = .failed("\(application.name) 缺少扫描身份，请重新扫描后再试")
            lastTechnicalDetail = "扫描时未能记录 App 的设备号、文件号与所有者；为避免卸载错误目标，本次操作已停止。"
            addActivity(
                title: "卸载 \(application.name)",
                detail: "缺少可复核的扫描身份，未改动任何文件。",
                outcome: .failed,
                category: .applicationUninstall
            )
            return
        }

        lastTechnicalDetail = ""
        let removalRequirement = applicationRemovalRequirement(for: application)
        phase = .executing("正在将 \(application.name) 移到废纸篓…")
        let appOutcome = await trashService.trashApplication(
            application.url,
            expectedIdentity: expectedIdentity,
            expectedBundleIdentifier: application.bundleIdentifier
        )
        guard appOutcome.succeeded else {
            if appOutcome.failureKind == .authorizationCancelled {
                phase = .failed("已取消卸载 \(application.name)，没有改动任何文件")
            } else if appOutcome.failureKind == .targetChanged {
                phase = .failed("\(application.name) 已发生变化，请重新扫描后再试")
            } else {
                phase = .failed("未能卸载 \(application.name)，没有处理相关文件")
            }
            let userMessage = appOutcome.errorDescription ?? "未知错误"
            lastTechnicalDetail = [userMessage, appOutcome.technicalDescription]
                .compactMap { $0 }
                .joined(separator: "\n\n")
            addActivity(
                title: "卸载 \(application.name)",
                detail: userMessage,
                outcome: .failed,
                category: .applicationUninstall
            )
            return
        }

        var leftoverOutcomes: [TrashOutcome] = []
        if includeLeftovers {
            leftoverOutcomes = await trashService.trashCleanupTargets(selectedApplicationLeftovers.map(\.url))
        }
        let failedLeftovers = leftoverOutcomes.filter { !$0.succeeded }
        let removedBytes = application.allocatedBytes + selectedApplicationLeftovers
            .filter { item in
                leftoverOutcomes.contains { $0.source.standardizedFileURL == item.url.standardizedFileURL && $0.succeeded }
            }
            .reduce(0) { $0 + $1.allocatedBytes }

        applications.removeAll { $0.id == application.id }
        selectedApplication = applications.first
        selectedApplicationLeftovers = []
        refreshDiskCapacity()

        if failedLeftovers.isEmpty {
            phase = .success("\(application.name) 已移到废纸篓")
            let authenticationDetail = removalRequirement == .administratorAuthentication
                ? "App 已通过 macOS 原生管理员认证移到废纸篓。"
                : "App 已移到废纸篓。"
            addActivity(
                title: "卸载 \(application.name)",
                detail: includeLeftovers
                    ? "\(authenticationDetail) 精确匹配的相关文件也已移到废纸篓。"
                    : "\(authenticationDetail) 相关文件已保留。",
                outcome: .success,
                affectedItems: 1 + leftoverOutcomes.filter(\.succeeded).count,
                bytes: removedBytes,
                category: .applicationUninstall
            )
        } else {
            phase = .failed("App 已卸载，但 \(failedLeftovers.count) 个相关文件未处理")
            lastTechnicalDetail = failedLeftovers.map { "\($0.source.path): \($0.errorDescription ?? "未知错误")" }.joined(separator: "\n")
            addActivity(
                title: "卸载 \(application.name)",
                detail: "App 已移到废纸篓，部分相关文件因权限被保留。",
                outcome: .partial,
                affectedItems: 1 + leftoverOutcomes.filter(\.succeeded).count,
                bytes: removedBytes,
                category: .applicationUninstall
            )
        }
    }

    func analyze(_ root: URL? = nil, deepRefresh: Bool = false) async {
        guard !demoMode else { return }
        ensureDiskManualDecisionsLoaded()
        guard !isWorking, activeDiskScanTask == nil else { return }
        let target = (root ?? diskRoot).standardizedFileURL
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performDiskAnalysis(
                target,
                mode: deepRefresh ? .bypassCache : .reuseFreshCache
            )
        }
        activeDiskScanTask = task
        await task.value
        activeDiskScanTask = nil
        diskScanProgress = nil
        diskEvidenceProgress = nil
        diskPartialReport = nil
        if case .scanning = phase { phase = .idle }
    }

    func cancelDiskAnalysis() {
        activeDiskScanTask?.cancel()
        phase = .scanning("正在取消磁盘分析…")
        lastTechnicalDetail = "本次磁盘分析已取消；已有结果保持不变。"
    }

    func diskEvidence(for entry: DiskEntry) -> DiskEvidenceEntry? {
        let fingerprint = DiskEvidenceIndexer.fingerprint(for: entry.url)
        return diskEvidenceReport?.entries.first { $0.id == fingerprint }
    }

    func manualDiskDecision(for entry: DiskEvidenceEntry) -> DiskManualDecision? {
        ensureDiskManualDecisionsLoaded()
        return diskManualDecisions.decision(for: entry)
    }

    func canMarkForCleanupReview(_ entry: DiskEvidenceEntry) -> Bool {
        DiskManualDecisionPolicy.canReviewForCleanup(entry)
    }

    func setManualDiskDecision(
        _ decision: DiskManualDecision?,
        for entry: DiskEvidenceEntry
    ) {
        ensureDiskManualDecisionsLoaded()
        do {
            var updated = diskManualDecisions
            try updated.set(decision, for: entry)
            diskManualDecisions = updated
            saveDiskManualDecisions()
            switch decision {
            case .reviewForCleanup:
                lastTechnicalDetail = "已把 \(entry.name) 标记为待清理复核；不会自动勾选或删除。"
            case .keep:
                lastTechnicalDetail = "已记住保留 \(entry.name)。"
            case .decideLater:
                lastTechnicalDetail = "已把 \(entry.name) 设为稍后处理。"
            case nil:
                lastTechnicalDetail = "\(entry.name) 已恢复为跟随系统建议。"
            }
        } catch {
            lastTechnicalDetail = error.localizedDescription
        }
    }

    private func performDiskAnalysis(_ target: URL, mode: DiskScanMode) async {
        let cancelledCollectionTask = invalidateDiskAI()
        let previousReport = diskReport
        let previousRoot = previousReport?.root.standardizedFileURL.path
        let previousHasScanned = diskHasScanned
        let previousCacheHitCount = diskScanCacheHitCount
        let previousScannedCount = diskScanScannedCount
        let previousElapsedSeconds = diskScanElapsedSeconds
        let previousCompletedAt = diskScanCompletedAt
        diskRoot = target
        if previousRoot != nil, previousRoot != target.path {
            diskHasScanned = false
        }
        diskPartialReport = nil
        diskScanCacheHitCount = 0
        diskScanScannedCount = 0
        diskScanElapsedSeconds = nil

        guard !diskTraversalMayRequireFullDiskAccess(target) || fullDiskAccessProbePassed else {
            diskPrivacyBlockMessage = "CleanNest 已在扫描前停止：\(target.path) 会遍历受 macOS 保护的应用数据。请到设置页由你手动打开系统设置；访问测试通过前不会启动 Mole 或原生扫描。"
            lastTechnicalDetail = diskPrivacyBlockMessage ?? ""
            phase = .idle
            if let cancelledCollectionTask {
                _ = await cancelledCollectionTask.value
                pendingDiskAICancellationTask = nil
            }
            return
        }

        diskPrivacyBlockMessage = nil
        phase = .scanning("正在分析 \(target.lastPathComponent.isEmpty ? target.path : target.lastPathComponent)…")
        diskScanProgress = DiskScanProgress(completed: 0, total: 0, currentName: target.lastPathComponent)
        if let cancelledCollectionTask {
            _ = await cancelledCollectionTask.value
            pendingDiskAICancellationTask = nil
        }
        guard !Task.isCancelled else {
            phase = .idle
            return
        }

        do {
            let cacheURL = CleanNestDataPaths.diskScanCache()
            let cache: DiskScanCacheStore
            do {
                cache = try DiskScanCachePersistence.load(from: cacheURL)
            } catch {
                cache = DiskScanCacheStore()
                lastTechnicalDetail = "磁盘增量索引无法读取，本次改为完整扫描：\(error.localizedDescription)"
            }
            let previousEvidence = try? DiskEvidencePersistence.load(
                from: CleanNestDataPaths.diskEvidenceSnapshot()
            )
            let request = DiskScannerRequest(
                root: target,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
                cache: cache,
                mode: mode,
                previousEvidence: previousEvidence
            )
            let response = try await scannerServiceClient.scanDisk(
                request
            ) { [weak self] progress in
                await self?.applyScannerProgress(progress)
            }
            try Task.checkCancellation()
            guard response.requestID == request.requestID else {
                throw ScannerServiceClientError.invalidResponse
            }
            let outcome = response.outcome
            try DiskScanCachePersistence.save(outcome.updatedCache, to: cacheURL)
            try DiskEvidencePersistence.save(
                response.evidence,
                to: CleanNestDataPaths.diskEvidenceSnapshot()
            )
            diskReport = outcome.report
            diskEvidenceReport = response.evidence
            diskHasScanned = true
            diskPartialReport = nil
            diskEvidenceProgress = nil
            diskScanProgress = nil
            diskScanCacheHitCount = outcome.cacheHitCount
            diskScanScannedCount = outcome.scannedCount
            diskScanElapsedSeconds = outcome.elapsedSeconds
            diskScanCompletedAt = Date()
            let returnedBytes = await relieveAllocatorPressure()
            let scanDetail = outcome.usedCache
                ? "独立磁盘扫描完成：复用 \(outcome.cacheHitCount) 项，实扫 \(outcome.scannedCount) 项，耗时 \(String(format: "%.2f", outcome.elapsedSeconds)) 秒。缓存只在元数据签名匹配且 15 分钟内复用。"
                : "独立磁盘扫描完成：实扫 \(outcome.scannedCount) 项，耗时 \(String(format: "%.2f", outcome.elapsedSeconds)) 秒。"
            lastTechnicalDetail = scanDetail
                + " 已向系统归还约 \(CleanNestFormatting.bytes(Self.reportableByteCount(returnedBytes))) 的空闲分配页。"
            phase = .idle
        } catch is CancellationError {
            if let previousReport {
                diskRoot = previousReport.root
            }
            diskHasScanned = previousHasScanned
            diskScanCacheHitCount = previousCacheHitCount
            diskScanScannedCount = previousScannedCount
            diskScanElapsedSeconds = previousElapsedSeconds
            diskScanCompletedAt = previousCompletedAt
            diskPartialReport = nil
            phase = .idle
        } catch {
            if let previousReport { diskRoot = previousReport.root }
            diskHasScanned = previousHasScanned
            diskScanCacheHitCount = previousCacheHitCount
            diskScanScannedCount = previousScannedCount
            diskScanElapsedSeconds = previousElapsedSeconds
            diskScanCompletedAt = previousCompletedAt
            diskPartialReport = nil
            phase = .failed("磁盘分析没有完成")
            lastTechnicalDetail = error.localizedDescription
        }
    }

    private func applyScannerProgress(_ progress: ScannerServiceProgress) {
        switch progress.stage {
        case .preparing:
            phase = .scanning("正在连接独立扫描服务…")
        case .cleanupCaches:
            phase = .scanning("独立服务正在检查可重建缓存…")
        case .cleanupPersonalFiles:
            phase = .scanning("独立服务正在检查下载、媒体与重复文件…")
        case .diskContents:
            diskEvidenceProgress = nil
            let value = DiskScanProgress(
                completed: progress.completed,
                total: progress.total,
                currentName: progress.currentName,
                partialReport: progress.partialReport,
                cacheHitCount: progress.cacheHitCount,
                scannedCount: progress.scannedCount
            )
            diskScanProgress = value
            diskPartialReport = value.partialReport
            diskScanCacheHitCount = value.cacheHitCount
            diskScanScannedCount = value.scannedCount
        case .diskEvidence:
            diskScanProgress = nil
            diskEvidenceProgress = DiskEvidenceProgress(
                completed: progress.completed,
                total: progress.total,
                currentName: progress.currentName
            )
            phase = .scanning("独立服务正在生成磁盘证据…")
        case .agentWorkspaceMetadata:
            // Agent 工作区使用独立客户端和独立界面状态，
            // 不覆盖用户正在查看的清理或磁盘扫描进度。
            break
        case .completed:
            break
        }
    }

    func clearDiskScanCache() {
        guard !demoMode else {
            diskScanCacheHitCount = 0
            diskScanScannedCount = 0
            diskScanElapsedSeconds = nil
            lastTechnicalDetail = "演示模式：只重置了当前合成界面的索引状态。"
            return
        }
        do {
            try DiskScanCachePersistence.save(
                DiskScanCacheStore(),
                to: CleanNestDataPaths.diskScanCache()
            )
            diskScanCacheHitCount = 0
            diskScanScannedCount = 0
            diskScanElapsedSeconds = nil
            lastTechnicalDetail = "磁盘增量索引已清空；下次分析会重新读取大小。"
        } catch {
            lastTechnicalDetail = "磁盘增量索引未能清空：\(error.localizedDescription)"
        }
    }

    func analyzeDiskWithLocalAI() async {
        guard !demoMode else {
            diskAIPhase = .completed
            return
        }
        guard localAIEnabled,
              let report = diskReport,
              !report.entries.isEmpty,
              !isWorking,
              !diskAIPhase.isBusy else { return }

        guard !diskTraversalMayRequireFullDiskAccess(report.root) || fullDiskAccessProbePassed else {
            diskPrivacyBlockMessage = "CleanNest 已在 AI 深度采样前停止：\(report.root.path) 会遍历受 macOS 保护的应用数据。访问测试通过前不会启动 Mole 或读取这些条目。"
            lastTechnicalDetail = diskPrivacyBlockMessage ?? ""
            diskAIPhase = .idle
            return
        }
        diskPrivacyBlockMessage = nil

        if let pendingDiskAICancellationTask {
            _ = await pendingDiskAICancellationTask.value
            self.pendingDiskAICancellationTask = nil
        }
        guard localAIEnabled,
              diskReport?.root.standardizedFileURL.path == report.root.standardizedFileURL.path,
              !isWorking,
              !diskAIPhase.isBusy else { return }

        let requestID = UUID()
        activeDiskAIRequestID = requestID
        let revision = diskRevision
        let rootID = report.root.standardizedFileURL.path
        diskAIAnalysis = nil
        diskAIChildContexts = [:]
        diskAIPhase = .collecting

        await probeLocalAI()
        guard activeDiskAIRequestID == requestID,
              diskRevision == revision,
              diskReport?.root.standardizedFileURL.path == rootID else { return }
        guard case .ready(let readyModelID) = localAIServiceState else {
            diskAIPhase = .failed("本机模型尚未连接，可在设置中检测或启动。")
            return
        }

        let collectionTask = Task { await self.collectDiskAIChildContexts(for: report) }
        activeDiskAICollectionTask = collectionTask
        let childContexts = await collectionTask.value
        guard activeDiskAIRequestID == requestID,
              diskRevision == revision,
              diskReport?.root.standardizedFileURL.path == rootID else { return }
        activeDiskAICollectionTask = nil
        diskAIChildContexts = childContexts
        diskAIPhase = .analyzing

        do {
            let snapshot = try DiskAIRequestBuilder.makeSnapshot(
                report: report,
                childContexts: childContexts,
                homeDirectory: FileManager.default.homeDirectoryForCurrentUser
            )
            guard snapshot.sourceRootID == rootID else {
                throw LocalAIError.invalidResponse("磁盘 AI 快照与当前目录不一致")
            }
            let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
            let analysis = try await client.analyzeDisk(snapshot: snapshot, modelID: readyModelID)
            guard activeDiskAIRequestID == requestID,
                  diskRevision == revision,
                  diskReport?.root.standardizedFileURL.path == rootID else { return }

            let currentIDs = Set(diskReport?.entries.map(\.id) ?? [])
            guard analysis.advice.allSatisfy({ currentIDs.contains($0.entryID) }) else {
                throw LocalAIError.invalidResponse("磁盘 AI 结果与当前层级不一致")
            }
            diskAIAnalysis = analysis
            diskAIPhase = .completed
            localAIDiagnostic = "已用 \(localAIModelDisplayName) 深度解读 \(analysis.requestedCount) 个磁盘项目。"
        } catch is CancellationError {
            guard activeDiskAIRequestID == requestID else { return }
            diskAIPhase = .idle
        } catch {
            guard activeDiskAIRequestID == requestID, diskRevision == revision else { return }
            diskAIPhase = .failed(error.localizedDescription)
            localAIDiagnostic = error.localizedDescription
            if let localError = error as? LocalAIError,
               case .serviceUnavailable = localError {
                localAIServiceState = .unavailable(error.localizedDescription)
            }
        }
    }

    func diskAIAdvice(for entry: DiskEntry) -> DiskAIAdvice? {
        diskAIAnalysis?.advice.first { $0.entryID == entry.id }
    }

    func diskAIChildContext(for entry: DiskEntry) -> DiskAIChildContext? {
        diskAIChildContexts[entry.id]
    }

    private func collectDiskAIChildContexts(
        for report: DiskReport
    ) async -> [String: DiskAIChildContext] {
        guard !Task.isCancelled else { return [:] }
        let root = report.root
        let mayReadProtectedAppData = fullDiskAccessProbePassed
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let targets = Array(
            report.entries
                .filter {
                    $0.isDirectory
                        && $0.bytes > 0
                        && Self.isAuthorizedDirectDiskChild($0.url, of: root)
                        && (mayReadProtectedAppData
                            || !DiskPrivacyPolicy.assessTraversal(
                                root: $0.url,
                                homeDirectory: homeDirectory
                            ).mayRequireFullDiskAccess)
                }
                .sorted { $0.bytes > $1.bytes }
                .prefix(DiskAIRequestBuilder.maximumDeepEntries)
        )
        guard !targets.isEmpty else { return [:] }

        let runner = commandRunner
        guard let currentEngine = engine else { return [:] }
        let environment = commandEnvironment
        let scan: @Sendable (DiskEntry) async -> (String, DiskAIChildContext?) = { entry in
            guard !Task.isCancelled else { return (entry.id, nil) }
            do {
                let result = try await runner.runChecked(
                    executable: currentEngine.executable,
                    arguments: ["analyze", "--json", entry.url.path],
                    environment: environment,
                    timeout: 90
                )
                guard !Task.isCancelled,
                      !Self.containsPermissionFailure(result.standardError),
                      let data = result.standardOutput.data(using: .utf8) else {
                    return (entry.id, nil)
                }
                let nestedReport = try MoleJSONDecoder.diskReport(from: data, fallbackRoot: entry.url)
                let safeEntries = nestedReport.entries.filter {
                    Self.isAuthorizedDirectDiskChild($0.url, of: entry.url) && $0.bytes >= 0
                }
                guard !safeEntries.isEmpty else { return (entry.id, nil) }
                let sorted = safeEntries.sorted {
                    if $0.bytes == $1.bytes { return $0.name < $1.name }
                    return $0.bytes > $1.bytes
                }
                return (
                    entry.id,
                    DiskAIChildContext(
                        entries: Array(sorted.prefix(DiskAIRequestBuilder.maximumChildSamples)),
                        totalEntryCount: safeEntries.count,
                        totalBytes: safeEntries.reduce(0) { $0 + $1.bytes }
                    )
                )
            } catch {
                return (entry.id, nil)
            }
        }

        return await withTaskGroup(of: (String, DiskAIChildContext?).self) { group in
            var iterator = targets.makeIterator()
            for _ in 0..<min(2, targets.count) {
                if let entry = iterator.next() {
                    group.addTask { await scan(entry) }
                }
            }

            var contexts: [String: DiskAIChildContext] = [:]
            while let (entryID, context) = await group.next() {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return [:]
                }
                if let context { contexts[entryID] = context }
                if let entry = iterator.next() {
                    group.addTask { await scan(entry) }
                }
            }
            return contexts
        }
    }

    nonisolated private static func isAuthorizedDirectDiskChild(_ child: URL, of parent: URL) -> Bool {
        let lexicalChild = child.standardizedFileURL
        let lexicalParent = parent.standardizedFileURL
        guard lexicalChild.deletingLastPathComponent().path == lexicalParent.path else { return false }

        let resolvedParent = lexicalParent.resolvingSymlinksInPath().path
        let resolvedChild = lexicalChild.resolvingSymlinksInPath().path
        return resolvedChild != resolvedParent && resolvedChild.hasPrefix(resolvedParent + "/")
    }

    private func recordDiskPermissionFailure(target: URL, detail: String, source: String) {
        if diskTraversalMayRequireFullDiskAccess(target) {
            fullDiskAccessProbeID = UUID()
            fullDiskAccessProbeResult = .permissionDenied
            fullDiskAccessProbeIsRunning = false
        }
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        diskPrivacyBlockMessage = "\(source) 报告权限不足，CleanNest 已终止本次分析，不会再回退到原生扫描，避免连续触发系统授权弹窗。"
        lastTechnicalDetail = normalizedDetail.isEmpty
            ? diskPrivacyBlockMessage ?? ""
            : "\(diskPrivacyBlockMessage ?? "")\n\n\(normalizedDetail)"
        phase = .idle
    }

    nonisolated private static func isPermissionFailure(_ error: Error) -> Bool {
        if FullDiskAccessProbeResult.classify(error: error) == .permissionDenied {
            return true
        }
        return containsPermissionFailure(error.localizedDescription)
    }

    nonisolated private static func containsPermissionFailure(_ detail: String) -> Bool {
        let normalized = detail.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        return [
            "operation not permitted",
            "permission denied",
            "access denied",
            "full disk access",
            "not authorized",
            "权限不足",
            "没有权限",
            "拒绝访问",
            "完全磁盘访问"
        ].contains { normalized.contains($0) }
    }

    func runMaintenance(_ action: MaintenanceAction) async {
        guard !demoMode else {
            phase = .success("演示模式：\(action.rawValue) 未实际执行")
            return
        }
        guard !isWorking else { return }
        phase = .executing("正在\(action.rawValue)…")
        let previousProcessIDs = if let processName = action.verificationProcessName {
            await maintenanceProcessIDs(named: processName)
        } else {
            Set<Int32>()
        }

        if let processName = action.verificationProcessName,
           previousProcessIDs.isEmpty {
            let detail = "CleanNest 无法确认当前的 \(processName) 进程，因此没有执行 \(action.rawValue)，避免把未验证的操作显示成成功。"
            phase = .failed("\(action.rawValue)未执行")
            lastTechnicalDetail = detail
            addActivity(title: action.rawValue, detail: detail, outcome: .failed)
            return
        }

        do {
            let result = try await commandRunner.runChecked(
                executable: action.executable,
                arguments: action.arguments,
                timeout: 15
            )

            if let processName = action.verificationProcessName {
                let restarted = await waitForMaintenanceProcessRestart(
                    named: processName,
                    excluding: previousProcessIDs
                )
                guard restarted else {
                    let detail = "\(action.rawValue)命令已返回，但 CleanNest 没有在 4 秒内验证 \(processName) 以新进程恢复运行。\(action.recovery)"
                    phase = .failed("\(action.rawValue)尚未验证完成")
                    lastTechnicalDetail = detail
                    addActivity(title: action.rawValue, detail: detail, outcome: .failed)
                    return
                }
            }

            let output = (result.standardOutput + result.standardError)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            lastTechnicalDetail = [
                "已执行：\(action.executable.path) \(action.arguments.joined(separator: " "))",
                action.verificationProcessName.map { "已验证：\($0) 以新进程恢复运行。" },
                output.isEmpty ? nil : output
            ]
            .compactMap { $0 }
            .joined(separator: "\n")
            phase = .success("\(action.rawValue)已完成")
            addActivity(title: action.rawValue, detail: action.explanation, outcome: .success, affectedItems: 1)
        } catch {
            phase = .failed("\(action.rawValue)没有完成")
            let detail = "\(error.localizedDescription) \(action.recovery)"
            lastTechnicalDetail = detail
            addActivity(title: action.rawValue, detail: detail, outcome: .failed)
        }
    }

    private func waitForMaintenanceProcessRestart(
        named processName: String,
        excluding previousProcessIDs: Set<Int32>
    ) async -> Bool {
        for attempt in 0..<16 {
            let currentProcessIDs = await maintenanceProcessIDs(named: processName)
            if !currentProcessIDs.subtracting(previousProcessIDs).isEmpty {
                return true
            }
            if attempt < 15 {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        return false
    }

    private func maintenanceProcessIDs(named processName: String) async -> Set<Int32> {
        guard let result = try? await commandRunner.runChecked(
            executable: URL(fileURLWithPath: "/usr/bin/pgrep"),
            arguments: ["-x", processName],
            timeout: 2
        ) else {
            return []
        }
        return Set(
            result.standardOutput
                .split(whereSeparator: \.isNewline)
                .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccessSettings() {
        let now = Date()
        guard !waitingForFullDiskAccessReturn,
              now.timeIntervalSince(lastFullDiskAccessSettingsOpenAttempt) >= 1.5,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }

        lastFullDiskAccessSettingsOpenAttempt = now
        waitingForFullDiskAccessReturn = true
        didResignAfterOpeningFullDiskAccessSettings = false
        guard NSWorkspace.shared.open(url) else {
            waitingForFullDiskAccessReturn = false
            lastTechnicalDetail = "未能打开 macOS 的完全磁盘访问设置。请手动打开“系统设置 > 隐私与安全性 > 完全磁盘访问”。"
            return
        }
        // Opening System Settings only starts a user-controlled flow. The
        // access state changes solely after a later probe succeeds.
    }

    func openMoleProject() {
        if let url = URL(string: "https://github.com/tw93/Mole") { NSWorkspace.shared.open(url) }
    }

    func presentUpdateChecker() {
        showingUpdateChecker = true
        guard !appUpdateState.isChecking else { return }
        Task { await checkForUpdates() }
    }

    func checkForUpdates() async {
        guard !appUpdateState.isChecking else { return }
        guard let currentVersion = AppMetadata.shortVersion, !currentVersion.isEmpty else {
            appUpdateState = .failed(
                currentVersion: CNL10n.string("开发构建"),
                message: CNL10n.string("当前构建没有可比较的版本号。请使用打包后的 CleanNest.app 检查更新。")
            )
            return
        }

        let checkID = UUID()
        appUpdateCheckID = checkID
        appUpdateState = .checking(currentVersion: currentVersion)

        do {
            guard let release = try await appUpdateClient.latestRelease() else {
                guard appUpdateCheckID == checkID else { return }
                appUpdateState = .noPublishedRelease(currentVersion: currentVersion)
                return
            }

            let decision = try AppUpdatePolicy.decision(
                localVersion: currentVersion,
                release: release
            )
            guard appUpdateCheckID == checkID else { return }
            switch decision {
            case .updateAvailable:
                appUpdateState = .updateAvailable(currentVersion: currentVersion, release: release)
            case .upToDate:
                appUpdateState = .upToDate(currentVersion: currentVersion, release: release)
            case .localVersionAhead:
                appUpdateState = .localVersionAhead(currentVersion: currentVersion, release: release)
            }
        } catch {
            guard appUpdateCheckID == checkID else { return }
            appUpdateState = .failed(
                currentVersion: currentVersion,
                message: localizedAppUpdateError(error)
            )
        }
    }

    func openLatestCleanNestRelease() {
        let url = appUpdateState.release?.pageURL ?? GitHubAppUpdateClient.releasesPageURL
        guard NSWorkspace.shared.open(url) else {
            appUpdateState = .failed(
                currentVersion: AppMetadata.shortVersion ?? CNL10n.string("未知"),
                message: CNL10n.string("未能在浏览器中打开 CleanNest 发布页。")
            )
            return
        }
    }

    func openTrash() {
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
    }

    func showMainWindow(selection: SidebarItem) {
        self.selection = selection
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let window = NSApp.windows.first { window in
            window.canBecomeMain && !(window is NSPanel)
        } ?? NSApp.windows.first
        window?.makeKeyAndOrderFront(nil)
    }

    func showTechnicalDetail() {
        showingTechnicalDetail = true
    }

    func showLocalAIDiagnostic() {
        lastTechnicalDetail = localAIDiagnostic
        showingTechnicalDetail = true
    }

    func clearLocalAIConfigurationError() {
        localAIConfigurationError = nil
    }

    func setDeveloperMode(_ enabled: Bool) {
        developerMode = enabled
        if !demoMode { settings.set(enabled, forKey: "developerMode") }
    }

    func resetPreferencesToSafeDefaults() async {
        guard !demoMode else {
            lastTechnicalDetail = "演示模式不会改写本机偏好设置。"
            return
        }
        let keys = [
            "customEnginePath",
            "developerMode",
            "localAIEnabled",
            "localAIEndpoint",
            "localAIServiceModelID",
            "localAIModelPath",
            "localAIExecutablePath",
            "recentLocalAIModelPaths",
            "localModelMenuBarEnabled",
            "metricsRetentionDays",
            "menuBarMonitorConfiguration"
        ]
        for key in keys { settings.removeObject(forKey: key) }

        customEnginePath = ""
        developerMode = true
        includeApplicationCaches = false
        includeMediaAndDuplicates = true
        cleanupScanInsights = .empty
        cleanupScanIncludedMediaAndDuplicates = false
        metricsRetentionDays = 30
        menuBarConfiguration = .defaults
        persistMenuBarConfiguration()
        startNativeMonitoring()
        if loginItemService.status == .enabled || loginItemService.status == .requiresApproval {
            try? await loginItemService.unregister()
        }
        refreshLaunchAtLoginStatus()
        localAIRuntime.stopOwnedProcess()
        localAIProcessOwned = false
        localAIEnabled = false
        localAIEndpoint = "http://127.0.0.1:8080/v1"
        localAIServiceModelID = ""
        localAIModelPath = ""
        localAIExecutablePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".mlx-env/bin/mlx_lm.server")
            .path
        localAIAvailableServiceModelIDs = []
        localAIDefaultServiceModelID = nil
        localAIServiceState = .disabled
        localAIProbeLatencyMilliseconds = nil
        localAIBenchmarkResult = nil
        localAIBenchmarkPhase = .idle
        localAIConfigurationError = nil
        localModelMenuBarEnabled = true
        stoppingExternalLocalModelRuntimeID = nil
        externalLocalModelStopMessage = nil
        externalLocalModelStopMessageIsWarning = false
        externalLocalModelForceCandidateID = nil
        settings.set(true, forKey: "localModelMenuBarEnabled")
        invalidateCleanupAI()
        _ = invalidateDiskAI()
        cleanupHasScanned = false
        await refreshEngine()
        lastTechnicalDetail = "设置已恢复为安全默认值。本机活动、扫描结果、学习规则、历史指标和 macOS 授权均未清除。"
    }

    func dismissPhase() {
        if !phase.isBusy { phase = .idle }
    }

    private func persistLocalAISettings() {
        if let endpoint = try? LocalAIEndpoint(rawValue: localAIEndpoint) {
            localAIEndpoint = endpoint.baseURL.absoluteString
        } else {
            localAIEndpoint = localAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        localAIServiceModelID = localAIServiceModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        localAIModelPath = localAIModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        localAIExecutablePath = localAIExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !demoMode else { return }
        settings.set(localAIEndpoint, forKey: "localAIEndpoint")
        settings.set(localAIServiceModelID, forKey: "localAIServiceModelID")
        settings.set(localAIModelPath, forKey: "localAIModelPath")
        settings.set(localAIExecutablePath, forKey: "localAIExecutablePath")

        if !localAIModelPath.isEmpty,
           localModelCatalog.descriptor(
               at: URL(fileURLWithPath: localAIModelPath, isDirectory: true)
           ) != nil {
            var recent = settings.stringArray(forKey: "recentLocalAIModelPaths") ?? []
            recent.removeAll { $0 == localAIModelPath }
            recent.insert(localAIModelPath, at: 0)
            settings.set(Array(recent.prefix(8)), forKey: "recentLocalAIModelPaths")
        }
    }

    private func configuredLocalModelURL() throws -> URL {
        try Self.validatedLocalModelURL(path: localAIModelPath)
    }

    private static func validatedLocalModelURL(path rawPath: String) throws -> URL {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, (path as NSString).isAbsolutePath else {
            throw LocalAIError.modelUnavailable("请选择本机的完整模型目录")
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        guard exists,
              isDirectory.boolValue,
              files.contains("config.json"),
              files.contains(where: { $0.hasSuffix(".safetensors") }) else {
            throw LocalAIError.modelUnavailable("模型目录不完整或不存在")
        }
        return url
    }

    private static func validatedServiceModelID(_ rawModelID: String) throws -> String {
        let modelID = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelID.count <= 512,
              !(modelID as NSString).isAbsolutePath,
              !modelID.lowercased().hasPrefix("file://"),
              modelID.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw LocalAIError.modelUnavailable("API 模型必须使用 oMLX 列出的短名，不能使用文件路径")
        }
        return modelID
    }

    private func probeConfiguredLocalAI() async throws -> (String, LocalAIProbeResult) {
        let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
        let result = try await client.probe()
        updateServiceModelCatalog(from: result)
        let modelID = try resolvedServiceModelID(from: result)
        return (modelID, result)
    }

    private func updateServiceModelCatalog(from result: LocalAIProbeResult) {
        localAIAvailableServiceModelIDs = result.modelIDs
        localAIDefaultServiceModelID = result.defaultModelID
    }

    private func resolvedServiceModelID(from result: LocalAIProbeResult) throws -> String {
        let preferred = localAIServiceModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedLocalModel = localAIModelDescriptor(path: localAIModelPath)
        if let modelID = result.resolvedModelID(
            preferredModelID: preferred,
            selectedLocalModel: selectedLocalModel
        ) {
            return modelID
        }

        if !preferred.isEmpty {
            throw LocalAIError.modelUnavailable(
                "oMLX 没有列出“\(preferred)”。请从 API 模型列表重新选择；不要填写文件路径。"
            )
        }
        guard !result.modelIDs.isEmpty else {
            throw LocalAIError.modelUnavailable("服务已响应，但没有列出可用的模型短名")
        }
        throw LocalAIError.modelUnavailable(
            "服务列出了多个模型，但无法确定要调用哪一个。请在 API 模型中选择短名。"
        )
    }

    private func invalidateCleanupAI() {
        cleanupRevision &+= 1
        activeAIRequestID = UUID()
        cleanupAIAnalysis = nil
        cleanupAIFeedback = nil
        cleanupAIPhase = .idle
    }

    @discardableResult
    private func invalidateDiskAI() -> Task<[String: DiskAIChildContext], Never>? {
        let collectionTask = activeDiskAICollectionTask ?? pendingDiskAICancellationTask
        diskRevision &+= 1
        activeDiskAIRequestID = UUID()
        collectionTask?.cancel()
        activeDiskAICollectionTask = nil
        pendingDiskAICancellationTask = collectionTask
        diskAIAnalysis = nil
        diskAIFeedback = nil
        diskAIChildContexts = [:]
        diskAIPhase = .idle
        return collectionTask
    }

    private var commandEnvironment: [String: String] {
        let original = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + original]
    }

    private static func validMetricsRetentionDays(_ days: Int) -> Int {
        [7, 30, 90, 365].min { abs($0 - days) < abs($1 - days) } ?? 30
    }

    private func persistCleanupPreview() {
        guard !demoMode else { return }
        let snapshot = CleanupPreviewSnapshot.make(candidates: cleanupCandidates)
        do {
            try CleanupPreviewPersistence.save(
                snapshot,
                to: CleanNestDataPaths.cleanupPreviewSnapshot()
            )
        } catch {
            lastTechnicalDetail = "清理预览索引未能保存：\(error.localizedDescription)"
        }
    }

    private func loadEvolutionMemory() {
        do {
            evolutionMemory = try EvolutionMemoryPersistence.load(
                from: CleanNestDataPaths.evolutionMemory()
            )
        } catch {
            evolutionMemory = EvolutionMemory()
            lastTechnicalDetail = "本机学习记录无法读取，已使用空白记忆：\(error.localizedDescription)"
        }
        hasLoadedEvolutionMemory = true
    }

    private func ensureEvolutionMemoryLoaded() {
        guard !demoMode, !hasLoadedEvolutionMemory else { return }
        loadEvolutionMemory()
    }

    private func saveEvolutionMemory() {
        guard !demoMode else { return }
        do {
            try EvolutionMemoryPersistence.save(
                evolutionMemory,
                to: CleanNestDataPaths.evolutionMemory()
            )
        } catch {
            lastTechnicalDetail = "本机学习记录无法保存：\(error.localizedDescription)"
        }
    }

    private func loadAgentWorkspaceObservation() -> AgentWorkspaceObservation? {
        let url = CleanNestDataPaths.agentWorkspaceObservation()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AgentWorkspaceObservation.self, from: data)
    }

    private func loadAgentWorkspaceSummary() {
        do {
            agentWorkspaceSummary = try AgentWorkspaceSummaryPersistence.load(
                from: CleanNestDataPaths.agentWorkspaceSummary()
            )
        } catch {
            agentWorkspaceSummary = nil
            lastTechnicalDetail = "Agent 聚合摘要无法读取；文件级扫描尚未运行：\(error.localizedDescription)"
        }
    }

    private func saveAgentWorkspaceSummary(_ summary: AgentWorkspaceSummary) {
        guard !demoMode else { return }
        do {
            try AgentWorkspaceSummaryPersistence.save(
                summary,
                to: CleanNestDataPaths.agentWorkspaceSummary()
            )
            agentWorkspaceSummary = summary
        } catch {
            lastTechnicalDetail = "Agent 聚合摘要未能保存：\(error.localizedDescription)"
        }
    }

    private func saveAgentWorkspaceObservation(_ observation: AgentWorkspaceObservation) {
        guard !demoMode else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(observation)
            let url = CleanNestDataPaths.agentWorkspaceObservation()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        } catch {
            lastTechnicalDetail = "Agent 工作区基线未能保存：\(error.localizedDescription)"
        }
    }

    private func loadDiskManualDecisions() {
        do {
            diskManualDecisions = try DiskManualDecisionPersistence.load(
                from: CleanNestDataPaths.diskManualDecisions()
            )
        } catch {
            diskManualDecisions = DiskManualDecisionStore()
            lastTechnicalDetail = "手动清理决策无法读取，已使用空白记录：\(error.localizedDescription)"
        }
        hasLoadedDiskManualDecisions = true
    }

    private func ensureDiskManualDecisionsLoaded() {
        guard !demoMode, !hasLoadedDiskManualDecisions else { return }
        loadDiskManualDecisions()
    }

    private func saveDiskManualDecisions() {
        guard !demoMode else { return }
        do {
            try DiskManualDecisionPersistence.save(
                diskManualDecisions,
                to: CleanNestDataPaths.diskManualDecisions()
            )
        } catch {
            lastTechnicalDetail = "手动清理决策无法保存：\(error.localizedDescription)"
        }
    }

    private func refreshDiskCapacity() {
        let path = FileManager.default.homeDirectoryForCurrentUser.path
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else { return }
        diskTotalBytes = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        diskFreeBytes = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    private func addActivity(
        title: String,
        detail: String,
        outcome: ActivityEntry.Outcome,
        affectedItems: Int = 0,
        bytes: Int64 = 0,
        category: ActivityEntry.Category? = nil
    ) {
        activities.insert(
            ActivityEntry(
                title: title,
                detail: detail,
                outcome: outcome,
                affectedItems: affectedItems,
                bytes: bytes,
                category: category
            ),
            at: 0
        )
        activities = Array(activities.prefix(100))
        saveActivities()
    }

    func exportActivities(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(activities).write(to: url, options: .atomic)
    }

    func clearActivities() {
        activities = []
        saveActivities()
        lastTechnicalDetail = "CleanNest 活动记录已清空；废纸篓和 Mole 自身日志未改变。"
    }

    private var activityFileURL: URL {
        CleanNestDataPaths.activityLog()
    }

    private func loadActivities() {
        let url = activityFileURL
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ActivityEntry].self, from: data) else { return }
        activities = decoded
    }

    private func saveActivities() {
        guard !demoMode else { return }
        let url = activityFileURL
        guard let data = try? JSONEncoder().encode(activities) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func seedDemoAgentWorkspace(home: URL) {
        let now = Date()
        func candidate(
            provider: AgentWorkspaceProvider,
            kind: AgentArtifactKind,
            relativePath: String,
            bytes: Int64,
            fileID: UInt64
        ) -> AgentWorkspaceActionCandidate {
            AgentWorkspaceActionCandidate(
                id: "demo:\(provider.rawValue):\(kind.rawValue):\(fileID)",
                provider: provider,
                kind: kind,
                path: home.appendingPathComponent(relativePath).path,
                identity: AgentWorkspaceFileIdentity(
                    deviceID: 1,
                    fileID: fileID,
                    ownerUserID: UInt32(getuid()),
                    logicalBytes: bytes,
                    allocatedBytes: bytes,
                    modificationSeconds: Int64(now.addingTimeInterval(-7_200).timeIntervalSince1970),
                    modificationNanoseconds: 0
                ),
                scannedAt: now
            )
        }
        func artifact(
            provider: AgentWorkspaceProvider,
            kind: AgentArtifactKind,
            path: String,
            bytes: Int64,
            files: Int,
            active: Int = 0,
            recent: Int = 0,
            old: Int = 0,
            preview: Int64 = 0,
            largest: Int64,
            disposition: AgentArtifactDisposition,
            protections: [String] = [],
            candidates: [AgentWorkspaceActionCandidate] = []
        ) -> AgentWorkspaceArtifact {
            AgentWorkspaceArtifact(
                id: "\(provider.rawValue):\(kind.rawValue)",
                provider: provider,
                kind: kind,
                sourcePaths: [home.appendingPathComponent(path).path],
                allocatedBytes: bytes,
                logicalBytes: bytes,
                fileCount: files,
                directoryCount: max(1, files / 8),
                activeFileCount: active,
                recentlyModifiedFileCount: recent,
                oldFileCount: old,
                previewBytes: preview,
                largestFileBytes: largest,
                largestFilePath: home.appendingPathComponent(path).appendingPathComponent("example.jsonl").path,
                latestModificationDate: now.addingTimeInterval(recent > 0 ? -80 : -5 * 86_400),
                disposition: disposition,
                protectionReasons: protections,
                isComplete: true,
                diagnostic: nil,
                actionCandidates: candidates
            )
        }

        let codex = AgentWorkspaceAgentSnapshot(
            provider: .codex,
            detected: true,
            artifacts: [
                artifact(
                    provider: .codex,
                    kind: .logs,
                    path: ".codex/logs",
                    bytes: 184_000_000,
                    files: 312,
                    old: 210,
                    preview: 172_000_000,
                    largest: 72_000_000,
                    disposition: .regenerable,
                    candidates: [
                        candidate(provider: .codex, kind: .logs, relativePath: ".codex/logs/agent-2026-07.log", bytes: 72_000_000, fileID: 11),
                        candidate(provider: .codex, kind: .logs, relativePath: ".codex/logs/tool-output.log", bytes: 46_000_000, fileID: 12)
                    ]
                ),
                artifact(
                    provider: .codex,
                    kind: .activeSessions,
                    path: ".codex/sessions",
                    bytes: 13_548_000_000,
                    files: 903,
                    active: 3,
                    recent: 7,
                    old: 368,
                    preview: 2_362_000_000,
                    largest: 655_000_000,
                    disposition: .protected,
                    protections: ["3 个会话文件正被 Codex 打开", "近 15 分钟仍有写入"]
                ),
                artifact(
                    provider: .codex,
                    kind: .backups,
                    path: ".codex/backups",
                    bytes: 1_746_000_000,
                    files: 44,
                    old: 18,
                    preview: 740_000_000,
                    largest: 210_000_000,
                    disposition: .review
                ),
                artifact(
                    provider: .codex,
                    kind: .generatedMedia,
                    path: ".codex/generated_images",
                    bytes: 424_000_000,
                    files: 86,
                    old: 21,
                    preview: 118_000_000,
                    largest: 38_000_000,
                    disposition: .review
                ),
                artifact(
                    provider: .codex,
                    kind: .stateAndIndexes,
                    path: ".codex/state_5.sqlite",
                    bytes: 162_000_000,
                    files: 19,
                    active: 4,
                    recent: 4,
                    largest: 92_000_000,
                    disposition: .protected,
                    protections: ["状态数据库正在使用", "直接删除会造成索引不一致"]
                )
            ]
        )
        let claude = AgentWorkspaceAgentSnapshot(
            provider: .claude,
            detected: true,
            artifacts: [
                artifact(
                    provider: .claude,
                    kind: .virtualMachines,
                    path: "Library/Application Support/Claude/vm_bundles",
                    bytes: 7_451_000_000,
                    files: 2_190,
                    largest: 1_180_000_000,
                    disposition: .keep,
                    protections: ["这是 Claude 的隔离运行环境，删除后可能需要重新下载"]
                ),
                artifact(
                    provider: .claude,
                    kind: .backups,
                    path: "Library/Application Support/Claude/cache-backup-20260605_002356",
                    bytes: 1_461_000_000,
                    files: 6_840,
                    old: 6_840,
                    preview: 1_461_000_000,
                    largest: 164_000_000,
                    disposition: .review
                ),
                artifact(
                    provider: .claude,
                    kind: .caches,
                    path: "Library/Application Support/Claude/Cache",
                    bytes: 552_000_000,
                    files: 4_620,
                    old: 2_410,
                    preview: 504_000_000,
                    largest: 58_000_000,
                    disposition: .regenerable,
                    candidates: [
                        candidate(provider: .claude, kind: .caches, relativePath: "Library/Application Support/Claude/Cache/data_0", bytes: 58_000_000, fileID: 21),
                        candidate(provider: .claude, kind: .caches, relativePath: "Library/Application Support/Claude/Cache/data_1", bytes: 41_000_000, fileID: 22),
                        candidate(provider: .claude, kind: .caches, relativePath: "Library/Application Support/Claude/Cache/data_2", bytes: 29_000_000, fileID: 23)
                    ]
                ),
                artifact(
                    provider: .claude,
                    kind: .activeSessions,
                    path: ".claude/projects",
                    bytes: 318_000_000,
                    files: 412,
                    active: 1,
                    recent: 3,
                    old: 94,
                    preview: 82_000_000,
                    largest: 71_000_000,
                    disposition: .protected,
                    protections: ["1 个会话文件正被 Claude 打开"]
                )
            ]
        )
        agentWorkspaceSnapshot = AgentWorkspaceSnapshot(
            capturedAt: now,
            previousCapturedAt: now.addingTimeInterval(-3600),
            agents: [codex, claude],
            alerts: [
                AgentWorkspaceAlert(
                    id: "codex:large-file",
                    level: .warning,
                    provider: .codex,
                    title: "Codex 出现超大单文件",
                    detail: "会话与工具输出中最大文件约 655 MB；已确认当前活跃会话并锁定。"
                ),
                AgentWorkspaceAlert(
                    id: "codex:active",
                    level: .info,
                    provider: .codex,
                    title: "Codex 存在正在使用的文件",
                    detail: "已确认 7 个文件被本机进程打开，相关项目不会进入回收执行。"
                )
            ],
            openFileProbeSucceeded: true,
            diagnostic: "演示模式：只展示合成的 Agent 元数据，不读取本机文件。"
        )
        agentWorkspacePhase = .ready
        agentWorkspaceDiagnostic = agentWorkspaceSnapshot?.diagnostic ?? "演示 Agent 工作区已就绪"
        let demoRecoveryID = UUID(uuidString: "77F8C956-52D0-41E0-A5EF-A41E5FB33D01")!
        let demoRecoveryItems = Array(claude.artifacts.flatMap(\.actionCandidates).prefix(2)).enumerated().map {
            AgentWorkspaceRecoveryItem(
                candidate: $0.element,
                archiveRelativePath: "staging/00000\($0.offset)",
                pendingFileName: "00000\($0.offset)"
            )
        }
        agentWorkspaceRecoveryRecords = [AgentWorkspaceRecoveryRecord(
            id: demoRecoveryID,
            createdAt: now.addingTimeInterval(-2_800),
            completedAt: now.addingTimeInterval(-2_760),
            status: .available,
            items: demoRecoveryItems,
            originalAllocatedBytes: 99_000_000,
            originalLogicalBytes: 99_000_000,
            archiveAllocatedBytes: 18_000_000,
            removedOriginalBytes: 99_000_000,
            apfsFreeBefore: 147_900_000_000,
            apfsFreeAfter: 147_978_000_000,
            diagnostic: "演示记录：备份已校验，可恢复。"
        )]
        var demoGraphNodes = AgentWorkspaceProvider.allCases.map { provider in
            AgentDependencyNode(
                id: "agent:\(provider.rawValue)",
                provider: provider,
                kind: .agent,
                title: provider.displayName,
                detail: provider == .xiaoyunque ? "仅检测·规则待验证" : "已验证只读适配",
                state: provider == .codex ? .running
                    : provider == .xiaoyunque ? .unverified
                    : [.claude, .kimi, .workBuddy, .openClaw].contains(provider) ? .detected : .notDetected
            )
        }
        demoGraphNodes += [
            AgentDependencyNode(id: "process:4242", provider: .codex, kind: .process, title: "Codex · PID 4242", detail: "内存 286 MB", state: .running),
            AgentDependencyNode(id: "data:codex", provider: .codex, kind: .data, title: "7 类本机数据", detail: "15.3 GB", state: .detected),
            AgentDependencyNode(id: "data:claude", provider: .claude, kind: .data, title: "4 类本机数据", detail: "9.8 GB", state: .detected),
            AgentDependencyNode(id: "app:kimi", provider: .kimi, kind: .application, title: "Kimi", detail: "com.moonshot.kimichat", state: .detected),
            AgentDependencyNode(id: "app:workbuddy", provider: .workBuddy, kind: .application, title: "WorkBuddy", detail: "com.workbuddy.workbuddy", state: .detected),
            AgentDependencyNode(id: "supervisor:openclaw", provider: .openClaw, kind: .supervisor, title: "ai.openclaw.gateway", detail: "用户 launchd 服务", state: .running),
            AgentDependencyNode(id: "model:qwen", provider: nil, kind: .localModel, title: "Qwen3.8-27B-Uncensored-8bit", detail: "oMLX", state: .running)
        ]
        agentDependencyGraph = AgentDependencyGraphSnapshot(
            capturedAt: now,
            nodes: demoGraphNodes,
            edges: [
                AgentDependencyEdge(sourceID: "agent:codex", destinationID: "process:4242", relation: .runsAs, evidence: .exactProcess),
                AgentDependencyEdge(sourceID: "agent:codex", destinationID: "data:codex", relation: .storesDataIn, evidence: .verifiedDataRoot),
                AgentDependencyEdge(sourceID: "agent:claude", destinationID: "data:claude", relation: .storesDataIn, evidence: .verifiedDataRoot),
                AgentDependencyEdge(sourceID: "agent:kimi", destinationID: "app:kimi", relation: .installedAs, evidence: .exactBundleIdentifier),
                AgentDependencyEdge(sourceID: "agent:workBuddy", destinationID: "app:workbuddy", relation: .installedAs, evidence: .exactBundleIdentifier),
                AgentDependencyEdge(sourceID: "agent:openClaw", destinationID: "supervisor:openclaw", relation: .keptAliveBy, evidence: .launchdLabel),
                AgentDependencyEdge(sourceID: "process:4242", destinationID: "model:qwen", relation: .connectsToModel, evidence: .establishedTCPConnection)
            ],
            diagnostic: "演示模式：1 条 Agent 到本地模型关系由已建立 TCP 连接确认。"
        )
        nativeDeveloperStorageSnapshot = NativeDeveloperStorageSnapshot(
            capturedAt: now,
            entries: [
                NativeDeveloperStorageEntry(
                    tool: .gitWorktree,
                    state: .needsSelection,
                    executablePath: "/usr/bin/git",
                    summary: "选择一个 Git 仓库后再预演",
                    detail: "不会遍历整台 Mac 猜测仓库。",
                    supportsNativeCleanup: true,
                    cleanupRisk: "只清理 Git 判定失效的管理记录。"
                ),
                NativeDeveloperStorageEntry(
                    tool: .docker,
                    state: .ready,
                    executablePath: "/usr/local/bin/docker",
                    summary: "Docker 磁盘账本已读取",
                    detail: "4.8 GB 可回收；官方没有 system prune dry-run，保持只读。",
                    preview: "Images 12.4 GB · Reclaimable 3.1 GB\nBuild cache 2.2 GB · Reclaimable 1.7 GB",
                    supportsNativeCleanup: false,
                    cleanupRisk: "不会删除停止容器、网络或镜像。"
                ),
                NativeDeveloperStorageEntry(
                    tool: .huggingFace,
                    state: .ready,
                    executablePath: "/Users/demo/.local/bin/hf",
                    summary: "hf cache prune dry-run 已完成",
                    detail: "2 个未引用修订，预计 1.26 GB。",
                    preview: "Dry run: 2 revisions · 1.26 GB",
                    supportsNativeCleanup: true,
                    cleanupRisk: "移除后可能需要重新下载。"
                ),
                NativeDeveloperStorageEntry(
                    tool: .npm,
                    state: .ready,
                    executablePath: "/opt/homebrew/bin/npm",
                    scopePath: "/Users/demo/.npm",
                    summary: "npm 已返回当前缓存位置",
                    detail: "没有内容级只读预演，使用备份优先通道。",
                    supportsNativeCleanup: false,
                    cleanupRisk: "不调用 cache clean --force。"
                ),
                NativeDeveloperStorageEntry(
                    tool: .pip,
                    state: .ready,
                    executablePath: "/opt/homebrew/bin/python3",
                    summary: "pip 缓存账本已读取",
                    detail: "734 MB · 128 个文件；purge 没有 dry-run。",
                    supportsNativeCleanup: false,
                    cleanupRisk: "保持只读。"
                )
            ]
        )
    }

    private func seedDemoData() {
        let demoHealthState = ProcessInfo.processInfo.environment["CLEANNEST_DEMO_HEALTH"]
        let demoShowsCriticalHealth = demoHealthState == "critical"
        let demoShowsWarningHealth = demoHealthState == "warning"
        let home = URL(fileURLWithPath: "/Users/demo", isDirectory: true)
        diskRoot = home
        fullDiskAccessProbeResult = .accessible
        localAIEnabled = true
        engine = EngineInstallation(executable: URL(fileURLWithPath: "/opt/homebrew/bin/mole"), version: "Mole 1.48.1")
        engineDiagnostic = "演示引擎已就绪"
        systemSnapshot = SystemSnapshot(
            host: "MacBook Pro",
            healthScore: 92,
            cpuUsage: 24,
            logicalCPUCount: 12,
            memoryUsedBytes: 18_400_000_000,
            memoryTotalBytes: 36_000_000_000,
            memoryUsedPercent: 51,
            memoryAvailableBytes: 17_600_000_000,
            memoryCachedBytes: 8_100_000_000,
            memoryCompressedBytes: 2_300_000_000,
            memorySwapUsedBytes: 640_000_000,
            memorySwapTotalBytes: 4_000_000_000,
            memoryPressureLevel: .normal,
            processCount: 612,
            diskUsedPercent: 68,
            diskFreeBytes: 148_000_000_000,
            batteryLevel: 86,
            batteryStatus: "正常 · 使用电池",
            temperatureCelsius: 43,
            temperatureSource: "CPU 温度",
            uptime: "3 天 12 小时"
        )
        batteryProbeResult = BatteryProbeResult(
            availability: .present,
            level: 86,
            status: "使用电池",
            detail: "演示数据：系统电源接口检测到内置电池。"
        )
        memoryProcesses = [
            MemoryProcessSnapshot(
                pid: 4_201,
                parentPID: 1,
                name: "oMLX",
                applicationName: "oMLX",
                executablePath: "/Applications/oMLX.app/Contents/MacOS/oMLX",
                physicalFootprintBytes: 7_420_000_000,
                residentBytes: 7_180_000_000,
                ownerUserID: UInt32(getuid()),
                startSeconds: 1_774_000_001,
                startMicroseconds: 120_000,
                purpose: "本机模型服务，为 CleanNest 和其他客户端提供推理。",
                terminationImpact: "退出后，正在进行的本机 AI 分析会中断，但不会删除模型文件。",
                protectionReason: nil
            ),
            MemoryProcessSnapshot(
                pid: 4_520,
                parentPID: 1,
                name: "Figma",
                applicationName: "Figma",
                executablePath: "/Applications/Figma.app/Contents/MacOS/Figma",
                physicalFootprintBytes: 1_360_000_000,
                residentBytes: 1_210_000_000,
                ownerUserID: UInt32(getuid()),
                startSeconds: 1_774_000_101,
                startMicroseconds: 80_000,
                purpose: "正在运行的 Figma 桌面应用。",
                terminationImpact: "退出后应用会关闭，未保存的本地编辑可能丢失。",
                protectionReason: nil
            ),
            MemoryProcessSnapshot(
                pid: 188,
                parentPID: 1,
                name: "WindowServer",
                applicationName: nil,
                executablePath: "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer",
                physicalFootprintBytes: 940_000_000,
                residentBytes: 880_000_000,
                ownerUserID: 0,
                startSeconds: 1_773_990_000,
                startMicroseconds: 0,
                purpose: "macOS 窗口与显示服务。",
                terminationImpact: "受系统保护，不提供结束操作。",
                protectionReason: "系统进程"
            )
        ]
        if let systemSnapshot {
            memoryAnalysis = MemoryAnalyzer.analyze(snapshot: systemSnapshot, processes: memoryProcesses)
        }
        metricHistory = (0..<60).map { offset in
            let wave = Double(offset % 12)
            return MetricSample(
                sampledAt: Date().addingTimeInterval(TimeInterval(offset - 59) * 60),
                healthScore: 88 + offset % 5,
                cpuUsage: 16 + wave * 2.1,
                memoryUsedPercent: 48 + wave * 0.35,
                memoryPressureLevel: .normal,
                memoryUsedBytes: 18_400_000_000,
                memoryAvailableBytes: 17_600_000_000,
                memoryCompressedBytes: 2_300_000_000,
                memorySwapUsedBytes: 640_000_000,
                diskUsedPercent: 68,
                diskFreeBytes: 148_000_000_000,
                batteryLevel: 86,
                temperatureCelsius: 43,
                processCount: 612
            )
        }
        metricsSamplingIsActive = true
        metricsDiagnostic = "演示模式：每 60 秒本机采样；保留 30 天，不上传。"
        nativeMonitorIsActive = true
        nativeMonitorDiagnostic = "演示模式：合成菜单栏指标，不读取本机硬件。"
        nativeMonitorHistory = (0..<40).map { offset in
            let phase = Double(offset) / 5
            return NativeMonitorSample(
                sampledAt: Date().addingTimeInterval(TimeInterval(offset - 39) * 2),
                cpuUsage: 28 + sin(phase) * 13,
                memoryUsedPercent: 56 + cos(phase * 0.7) * 3,
                memoryUsedBytes: 20_100_000_000,
                memoryTotalBytes: 36_000_000_000,
                memoryPressureLevel: .normal,
                diskUsedPercent: 68,
                diskFreeBytes: 148_000_000_000,
                networkDownloadBytesPerSecond: max(0, 1_900_000 + sin(phase * 1.6) * 1_500_000),
                networkUploadBytesPerSecond: max(0, 180_000 + cos(phase * 1.2) * 140_000),
                networkInterfaceName: "en0",
                gpuUsage: 22 + cos(phase) * 15,
                gpuRendererUsage: 18,
                gpuTilerUsage: 12,
                temperatureCelsius: demoShowsCriticalHealth
                    ? 97 + sin(phase * 0.5)
                    : (demoShowsWarningHealth ? 87 + sin(phase * 0.5) : 58 + sin(phase * 0.5) * 4),
                temperatureSource: "演示 CPU 核心",
                batteryTemperatureCelsius: 31 + sin(phase * 0.2),
                batteryTemperatureSource: "演示电池传感器",
                fanRPM: demoShowsCriticalHealth
                    ? 5_800 + sin(phase) * 80
                    : (demoShowsWarningHealth ? 4_900 + sin(phase) * 80 : 1_850 + sin(phase) * 220),
                fanCount: 2,
                fanLoadPercent: demoShowsCriticalHealth
                    ? 96 + sin(phase)
                    : (demoShowsWarningHealth ? 88 + sin(phase) : 31 + sin(phase) * 4),
                thermalState: demoShowsCriticalHealth
                    ? .critical
                    : (demoShowsWarningHealth ? .fair : .nominal)
            )
        }
        nativeMonitorSample = nativeMonitorHistory.last
        diskTotalBytes = 494_000_000_000
        diskFreeBytes = 148_000_000_000
        seedDemoAgentWorkspace(home: home)

        cleanupCandidates = [
            CleanupCandidate(name: "DerivedData", url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Demo"), kind: .developer, allocatedBytes: 4_820_000_000, modifiedAt: Date().addingTimeInterval(-1_900_000), isRecommended: true, detail: "Xcode 会在需要时重新生成"),
            CleanupCandidate(name: "Homebrew 下载缓存", url: home.appendingPathComponent("Library/Caches/Homebrew/downloads"), kind: .packageManager, allocatedBytes: 2_360_000_000, modifiedAt: Date().addingTimeInterval(-1_200_000), isRecommended: true, detail: "安装包可重新下载"),
            CleanupCandidate(name: "DesignTool.dmg", url: home.appendingPathComponent("Downloads/DesignTool.dmg"), kind: .installer, allocatedBytes: 1_430_000_000, modifiedAt: Date().addingTimeInterval(-2_800_000), isRecommended: false, detail: "下载的安装介质 · 个人文件，默认不勾选"),
            CleanupCandidate(name: CleanupScanner.npmCacheDisplayName, url: home.appendingPathComponent(".npm/_cacache/content-v2"), kind: .packageManager, allocatedBytes: 890_000_000, modifiedAt: Date().addingTimeInterval(-3 * 86_400), isRecommended: false, detail: CleanupScanner.npmCacheDetail),
            CleanupCandidate(name: "旧诊断日志", url: home.appendingPathComponent("Library/Logs/DiagnosticReports"), kind: .logs, allocatedBytes: 124_000_000, modifiedAt: Date().addingTimeInterval(-7_800_000), isRecommended: false, detail: "排查问题时可能有用"),
            CleanupCandidate(name: "素材归档.zip", url: home.appendingPathComponent("Downloads/素材归档.zip"), kind: .archive, allocatedBytes: 760_000_000, modifiedAt: Date().addingTimeInterval(-1_600_000), isRecommended: false, detail: "普通 ZIP 资料归档；不能仅凭扩展名判断可删除"),
            CleanupCandidate(name: "访谈原片.mov", url: home.appendingPathComponent("Movies/访谈原片.mov"), kind: .video, allocatedBytes: 2_640_000_000, modifiedAt: Date().addingTimeInterval(-4_200_000), isRecommended: false, detail: "较大的视频文件 · 来自影片 · 仅供手动复核"),
            CleanupCandidate(name: "访谈原片 副本.mov", url: home.appendingPathComponent("Downloads/访谈原片 副本.mov"), kind: .duplicate, allocatedBytes: 2_640_000_000, modifiedAt: Date().addingTimeInterval(-3_900_000), isRecommended: false, detail: "与“访谈原片.mov”字节完全相同；保留该副本，执行前会重新核验 SHA-256")
        ]
        cleanupScanInsights = CleanupScanInsights(
            examinedFileCount: 1_284,
            installerCount: 1,
            archiveCount: 1,
            videoCount: 1,
            duplicateGroupCount: 1,
            duplicateFileCount: 1,
            duplicateBytes: 2_640_000_000
        )
        cleanupScanIncludedMediaAndDuplicates = true
        selectedCleanupIDs = Set(cleanupCandidates.filter(\.isRecommended).map(\.id))
        cleanupHasScanned = true
        let demoModelID = "Qwen3.8-27B-Uncensored-8bit"
        let demoModelPath = home
            .appendingPathComponent("Models/MLX/Qwen3.8-27B-Uncensored-8bit", isDirectory: true)
            .path
        localAIEndpoint = "http://127.0.0.1:8080/v1"
        localAIModelPath = demoModelPath
        localAIExecutablePath = home.appendingPathComponent(".mlx-env/bin/mlx_lm.server").path
        localAIAvailableModels = [
            LocalModelDescriptor(
                path: demoModelPath,
                canonicalPath: demoModelPath,
                displayName: demoModelID,
                architecture: "Qwen3_5ForConditionalGeneration",
                modelType: "qwen3_5",
                quantization: "8-bit",
                weightBytes: 29_500_000_000,
                serviceAliases: [demoModelID]
            )
        ]
        localAIModelCatalogDiagnostic = "演示模式：1 个合成模型，不读取本机模型目录。"
        localAIServiceModelID = demoModelID
        localAIAvailableServiceModelIDs = [demoModelID]
        localAIDefaultServiceModelID = demoModelID
        localAIServiceState = .ready(modelID: demoModelID)
        localAIProbeLatencyMilliseconds = 18
        localAIBenchmarkResult = LocalAIBenchmarkResult(
            modelID: demoModelID,
            firstTokenMilliseconds: 412,
            totalMilliseconds: 680,
            outputTokens: 2,
            outputCharacters: 2
        )
        localAIBenchmarkPhase = .completed
        localAIDiagnostic = "演示模式：本机模型已连接"
        cleanupAIAnalysis = CleanupAIAnalysis(
            modelID: demoModelID,
            summary: "主要空间来自可重新生成的开发与包管理器缓存；安装包和诊断日志仍建议逐项确认。",
            advice: [
                CleanupAIAdvice(candidateID: cleanupCandidates[0].id, verdict: .reclaimable, risk: .low, priority: 1, reason: "超过三周未修改，Xcode 会在下次构建时按需重建。"),
                CleanupAIAdvice(candidateID: cleanupCandidates[1].id, verdict: .reclaimable, risk: .low, priority: 1, reason: "属于可重新下载的安装缓存，体积较大。"),
                CleanupAIAdvice(candidateID: cleanupCandidates[2].id, verdict: .review, risk: .medium, priority: 2, reason: "删除前应确认不再需要离线重装这个版本。"),
                CleanupAIAdvice(candidateID: cleanupCandidates[3].id, verdict: .review, risk: .medium, priority: 2, reason: "可重新生成，但下一次安装依赖会增加下载时间。"),
                CleanupAIAdvice(candidateID: cleanupCandidates[4].id, verdict: .keep, risk: .high, priority: 3, reason: "近期若在排查崩溃问题，这些诊断日志可能仍有价值。")
            ],
            cautions: ["AI 只分析元数据；最终处理仍以你的勾选和安全规则为准。"],
            requestedCount: cleanupCandidates.count
        )
        cleanupAIPhase = .completed
        evolutionMemory.proposeCleanupPreference(
            for: cleanupCandidates[0],
            preference: .preferCleanup,
            reason: "你明确提出以后优先复核这个项目。"
        )
        if let proposal = evolutionMemory.ruleProposal(for: cleanupCandidates[0]) {
            evolutionMemory.enableRuleProposal(id: proposal.id)
        }
        evolutionMemory.proposeCleanupPreference(
            for: cleanupCandidates[4],
            preference: .preferKeep,
            reason: "你明确提出以后优先保留这个项目。"
        )
        evolutionMemory.recordModelFeedback(
            modelID: demoModelID,
            displayName: demoModelID,
            helpful: true,
            scope: "磁盘解读"
        )

        applications = [
            InstalledApplication(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", version: "1.102", url: URL(fileURLWithPath: "/Applications/Arc.app"), allocatedBytes: 690_000_000, modifiedAt: Date().addingTimeInterval(-86_400)),
            InstalledApplication(name: "Figma", bundleIdentifier: "com.figma.Desktop", version: "126.4", url: URL(fileURLWithPath: "/Applications/Figma.app"), allocatedBytes: 440_000_000, modifiedAt: Date().addingTimeInterval(-172_800)),
            InstalledApplication(name: "Visual Studio Code", bundleIdentifier: "com.microsoft.VSCode", version: "1.109", url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), allocatedBytes: 620_000_000, modifiedAt: Date().addingTimeInterval(-43_200)),
            InstalledApplication(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", version: "26.4", url: URL(fileURLWithPath: "/Applications/Xcode.app"), allocatedBytes: 11_800_000_000, modifiedAt: Date().addingTimeInterval(-604_800))
        ]
        selectedApplication = applications[1]
        selectedApplicationLeftovers = [
            CleanupCandidate(name: "com.figma.Desktop", url: home.appendingPathComponent("Library/Caches/com.figma.Desktop"), kind: .leftover, allocatedBytes: 310_000_000, modifiedAt: Date().addingTimeInterval(-172_800), isRecommended: true, detail: "按 Bundle ID 精确匹配"),
            CleanupCandidate(name: "com.figma.Desktop.plist", url: home.appendingPathComponent("Library/Preferences/com.figma.Desktop.plist"), kind: .leftover, allocatedBytes: 42_000, modifiedAt: Date().addingTimeInterval(-172_800), isRecommended: true, detail: "偏好设置")
        ]
        applicationsHaveScanned = true

        diskReport = DiskReport(
            root: home,
            entries: [
                DiskEntry(name: "Library", url: home.appendingPathComponent("Library"), bytes: 78_400_000_000, isDirectory: true),
                DiskEntry(name: "Documents", url: home.appendingPathComponent("Documents"), bytes: 42_700_000_000, isDirectory: true),
                DiskEntry(name: "Movies", url: home.appendingPathComponent("Movies"), bytes: 31_200_000_000, isDirectory: true),
                DiskEntry(name: "Downloads", url: home.appendingPathComponent("Downloads"), bytes: 18_600_000_000, isDirectory: true),
                DiskEntry(name: "Pictures", url: home.appendingPathComponent("Pictures"), bytes: 12_900_000_000, isDirectory: true)
            ],
            largeFiles: [],
            totalBytes: 183_800_000_000,
            totalFiles: 148_220
        )
        diskHasScanned = true
        diskScanCacheHitCount = 3
        diskScanScannedCount = 2
        diskScanElapsedSeconds = 0.42
        diskScanCompletedAt = Date()
        if let diskReport {
            diskEvidenceReport = DiskEvidenceReport(
                rootHint: "~",
                entries: diskReport.entries.map { entry in
                    let policy = DiskAISafetyPolicy.policy(for: entry.url, homeDirectory: home)
                    let purpose: String
                    let provenance: String
                    let regeneration: String
                    switch entry.name {
                    case "Downloads":
                        purpose = "浏览器、聊天工具和其他 App 下载到本机的文件。"
                        provenance = "来自用户主动下载或应用导出的内容。"
                        regeneration = "其中可能有可重新下载的安装包，也可能有唯一文件，必须逐项确认。"
                    case "Documents":
                        purpose = "用户创建或保存的文档与项目文件。"
                        provenance = "主要来自用户编辑、保存或同步。"
                        regeneration = "通常不可自动重建，默认保留。"
                    case "Movies", "Pictures":
                        purpose = "用户的视频、照片、截图或创作素材。"
                        provenance = "来自拍摄、导入、下载或创作。"
                        regeneration = "通常不可自动重建，默认保留。"
                    default:
                        purpose = "应用设置、数据库、模型、缓存与系统支持数据的混合目录。"
                        provenance = "由 macOS 和已安装应用共同产生。"
                        regeneration = "不能整体清理；应继续下钻并按所属应用管理。"
                    }
                    return DiskEvidenceEntry(
                        id: DiskEvidenceIndexer.fingerprint(for: entry.url),
                        name: entry.name,
                        relativeHint: "~/\(entry.name)",
                        allocatedBytes: entry.bytes,
                        isDirectory: entry.isDirectory,
                        observedFileCount: 0,
                        observedBytes: 0,
                        scanWasLimited: false,
                        latestModificationDate: nil,
                        ageDistribution: DiskEvidenceAgeDistribution(),
                        typeDistribution: [],
                        category: policy.category,
                        cleanupBoundary: policy.boundary,
                        minimumRisk: policy.minimumRisk,
                        purpose: purpose,
                        likelyOwner: nil,
                        provenance: provenance,
                        regeneration: regeneration,
                        growthBytes: nil
                    )
                }
            )
        }
        if let entries = diskReport?.entries {
            diskAIAnalysis = DiskAIAnalysis(
                modelID: demoModelID,
                summary: "基于目录名称、层级和体积推断，主要空间来自个人文件与应用数据；这些顶层目录都不适合直接整体清理，应继续进入查看。",
                advice: [
                    DiskAIAdvice(entryID: entries[0].id, category: .systemData, confidence: .high, verdict: .keep, risk: .high, priority: 1, suggestion: .inspectFurther, explanation: "通常包含应用沙盒、支持数据与缓存等混合内容。应继续进入，优先检查具体缓存目录，不要整体处理。"),
                    DiskAIAdvice(entryID: entries[1].id, category: .userContent, confidence: .high, verdict: .keep, risk: .high, priority: 3, suggestion: .keep, explanation: "通常是用户创建或保存的文档。内容具有唯一性，建议保留并由你逐项确认。"),
                    DiskAIAdvice(entryID: entries[2].id, category: .userContent, confidence: .high, verdict: .keep, risk: .high, priority: 3, suggestion: .keep, explanation: "通常是视频和剪辑素材，可能体积很大但不可自动重建，应由你逐项确认。"),
                    DiskAIAdvice(entryID: entries[3].id, category: .userContent, confidence: .medium, verdict: .review, risk: .medium, priority: 2, suggestion: .inspectFurther, explanation: "通常包含安装包、归档和临时下载，也可能有仍需保留的文件。适合进入后按文件逐项检查。"),
                    DiskAIAdvice(entryID: entries[4].id, category: .userContent, confidence: .high, verdict: .keep, risk: .high, priority: 3, suggestion: .keep, explanation: "通常是照片、截图及图库数据，属于用户内容，不应仅凭体积判断为可清理。")
                ],
                cautions: ["演示结果只依据元数据，不代表读取过文件内容，也不会产生任何清理动作。"],
                requestedCount: entries.count,
                coveredBytes: entries.reduce(0) { $0 + $1.bytes },
                deepSampledCount: 0
            )
            diskAIPhase = .completed
        }
        activities = [
            ActivityEntry(date: Date().addingTimeInterval(-7_200), title: "清理空间", detail: "14 项已移到废纸篓，可在清空前恢复。", outcome: .success, affectedItems: 14, bytes: 3_820_000_000, category: .cleanup),
            ActivityEntry(date: Date().addingTimeInterval(-86_400), title: "卸载 Sample App", detail: "App 与精确匹配的相关文件已移到废纸篓。", outcome: .success, affectedItems: 3, bytes: 430_000_000, category: .applicationUninstall),
            ActivityEntry(date: Date().addingTimeInterval(-172_800), title: "重建快速预览缓存", detail: "系统维护任务已完成。", outcome: .success, affectedItems: 1)
        ]
    }
}
