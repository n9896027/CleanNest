import AppKit
import Combine
import Darwin
import Foundation
import CleanNestCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case overview = "总览"
    case cleanup = "清理空间"
    case applications = "应用卸载"
    case analyze = "磁盘浏览"
    case status = "系统状态"
    case maintenance = "系统维护"
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
        case .evolution: return "sparkles.rectangle.stack"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    static let spaceItems: [SidebarItem] = [.cleanup, .applications, .analyze]
    static let systemItems: [SidebarItem] = [.status, .maintenance]
    static let intelligenceItems: [SidebarItem] = [.evolution]
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

struct ActivityEntry: Identifiable, Codable, Hashable {
    enum Outcome: String, Codable {
        case success = "完成"
        case partial = "部分完成"
        case failed = "未完成"

        var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .partial: return "exclamationmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }

    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let outcome: Outcome
    let affectedItems: Int
    let bytes: Int64

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        detail: String,
        outcome: Outcome,
        affectedItems: Int = 0,
        bytes: Int64 = 0
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.outcome = outcome
        self.affectedItems = affectedItems
        self.bytes = bytes
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

    @Published var cleanupCandidates: [CleanupCandidate] = []
    @Published var selectedCleanupIDs = Set<String>()
    @Published var includeApplicationCaches = false
    @Published var developerMode = true
    @Published var cleanupHasScanned = false
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
    @Published var customEnginePath = ""
    @Published var lastTechnicalDetail = ""
    @Published var showingTechnicalDetail = false
    @Published var showingUpdateChecker = false
    @Published private(set) var appUpdateState: AppUpdateState = .idle

    let demoMode: Bool

    private let commandRunner = CommandRunner()
    private let cleanupScanner = CleanupScanner()
    private let applicationScanner = ApplicationScanner()
    private let diskAnalyzer = NativeDiskAnalyzer()
    private let processMemoryInspector = ProcessMemoryInspector()
    private let metricsStore = MetricsStore()
    private let diskEvidenceIndexer = DiskEvidenceIndexer()
    private let trashService = TrashService(
        applicationRecycler: WorkspaceApplicationRecycler.recycle
    )
    private let localAIRuntime = LocalMLXRuntime()
    private let localModelCatalog = LocalModelCatalog()
    private let appUpdateClient = GitHubAppUpdateClient()
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
    private var activeDiskScanTask: Task<Void, Never>?
    private var appUpdateCheckID = UUID()

    init() {
        demoMode = ProcessInfo.processInfo.environment["CLEANNEST_DEMO"] == "1"
        customEnginePath = settings.string(forKey: "customEnginePath") ?? ""
        if settings.object(forKey: "developerMode") != nil {
            developerMode = settings.bool(forKey: "developerMode")
        }
        if settings.object(forKey: "localAIEnabled") != nil {
            localAIEnabled = settings.bool(forKey: "localAIEnabled")
        }
        if settings.object(forKey: "metricsRetentionDays") != nil {
            metricsRetentionDays = Self.validMetricsRetentionDays(
                settings.integer(forKey: "metricsRetentionDays")
            )
        }
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
        }
        if demoMode {
            // Demo and screenshot runs must never inherit a user's persisted
            // activity, learning, model catalog, or disk-capacity data.
            activities = []
            evolutionMemory = EvolutionMemory()
            seedDemoData()
        } else {
            loadActivities()
            loadEvolutionMemory()
            loadDiskManualDecisions()
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
        await refreshLocalModelCatalog()
        await prepareMetricsHistory()
        await refreshFullDiskAccessProbe()
        await refreshEngine()
        if engine != nil {
            await refreshSystemStatus(silent: true)
            startMetricsSampling()
        }
        if localAIEnabled {
            await probeLocalAI()
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

    private func prepareMetricsHistory() async {
        do {
            try await metricsStore.prepare()
            _ = try await metricsStore.prune(retainingDays: metricsRetentionDays)
            await refreshMetricHistory()
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
                await self.refreshSystemStatus(silent: true)
            }
            self?.metricsSamplingIsActive = false
        }
    }

    private func recordMetric(_ snapshot: SystemSnapshot) async {
        do {
            try await metricsStore.append(MetricSample(snapshot: snapshot))
            _ = try await metricsStore.prune(retainingDays: metricsRetentionDays)
            metricHistory = try await metricsStore.samples(range: metricHistoryRange)
            metricsDiagnostic = "每 60 秒本机采样；保留 \(metricsRetentionDays) 天，不上传。"
        } catch {
            metricsDiagnostic = "本次历史采样未保存：\(error.localizedDescription)"
        }
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
        guard waitingForFullDiskAccessReturn else { return }
        didResignAfterOpeningFullDiskAccessSettings = true
    }

    func applicationDidBecomeActive() async {
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
        return true
    }

    func stopLocalAI() async {
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
        evolutionMemory.removeRuleProposal(id: EvolutionMemory.cleanupKey(for: candidate))
        saveEvolutionMemory()
    }

    func enableCleanupRule(_ id: String) {
        evolutionMemory.enableRuleProposal(id: id)
        saveEvolutionMemory()
    }

    func pauseCleanupRule(_ id: String) {
        evolutionMemory.pauseRuleProposal(id: id)
        saveEvolutionMemory()
    }

    func removeCleanupRule(_ id: String) {
        evolutionMemory.removeRuleProposal(id: id)
        saveEvolutionMemory()
    }

    func recordCleanupAIFeedback(helpful: Bool) {
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
        activeDiskScanTask?.cancel()
        activeDiskScanTask = nil
        invalidateCleanupAI()
        _ = invalidateDiskAI()
        commandRunner.terminateAll()
        shutdownLocalAI()
    }

    func refreshSystemStatus(silent: Bool = false) async {
        guard !demoMode else { return }
        let inspector = processMemoryInspector
        let nativeMemoryTask = Task.detached(priority: .utility) {
            (
                probe: SystemMemoryProbe.sample(),
                processes: inspector.topProcesses(limit: 16)
            )
        }
        let batteryTask = Task.detached(priority: .utility) {
            PowerSourceProbe.sample()
        }
        guard let engine else {
            let nativeMemory = await nativeMemoryTask.value
            batteryProbeResult = await batteryTask.value
            memoryProcesses = nativeMemory.processes
            if let systemSnapshot {
                memoryAnalysis = MemoryAnalyzer.analyze(
                    snapshot: systemSnapshot,
                    processes: nativeMemory.processes
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
            batteryProbeResult = await batteryTask.value
            let snapshot = try MoleJSONDecoder.systemSnapshot(
                from: data,
                memoryProbe: nativeMemory.probe
            )
            systemSnapshot = snapshot
            memoryProcesses = nativeMemory.processes
            memoryAnalysis = MemoryAnalyzer.analyze(
                snapshot: snapshot,
                processes: nativeMemory.processes
            )
            if let forceID = forceTerminationProcessID,
               !nativeMemory.processes.contains(where: { $0.id == forceID }) {
                forceTerminationProcessID = nil
            }
            lastTechnicalDetail = result.standardError
            refreshDiskCapacity()
            await recordMetric(snapshot)
            phase = .idle
        } catch {
            let nativeMemory = await nativeMemoryTask.value
            batteryProbeResult = await batteryTask.value
            memoryProcesses = nativeMemory.processes
            if let systemSnapshot {
                memoryAnalysis = MemoryAnalyzer.analyze(
                    snapshot: systemSnapshot,
                    processes: nativeMemory.processes
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
        guard !isWorking else { return }
        invalidateCleanupAI()
        phase = .scanning("正在检查可清理内容…")
        let scanned = await cleanupScanner.scan(includeApplicationCaches: includeApplicationCaches)
        let results = developerMode
            ? scanned
            : scanned.filter { $0.kind != .developer && $0.kind != .packageManager }
        cleanupCandidates = results
        selectedCleanupIDs = Set(results.filter(\.isRecommended).map(\.id))
        cleanupHasScanned = true
        persistCleanupPreview()
        phase = .idle
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

    func clearCleanupSelection() {
        selectedCleanupIDs.removeAll()
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
        let outcomes = await trashService.trashCleanupTargets(selected.map(\.url))
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
                bytes: released
            )
        } else {
            phase = .failed("已完成 \(succeededPaths.count) 项，\(failed.count) 项未成功")
            lastTechnicalDetail = failed.map { "\($0.source.path): \($0.errorDescription ?? "未知错误")" }.joined(separator: "\n")
            addActivity(
                title: "清理空间",
                detail: "部分项目因权限或路径变化被安全跳过。",
                outcome: .partial,
                affectedItems: succeededPaths.count,
                bytes: released
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
                outcome: .failed
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
            addActivity(title: "卸载 \(application.name)", detail: userMessage, outcome: .failed)
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
                bytes: removedBytes
            )
        } else {
            phase = .failed("App 已卸载，但 \(failedLeftovers.count) 个相关文件未处理")
            lastTechnicalDetail = failedLeftovers.map { "\($0.source.path): \($0.errorDescription ?? "未知错误")" }.joined(separator: "\n")
            addActivity(
                title: "卸载 \(application.name)",
                detail: "App 已移到废纸篓，部分相关文件因权限被保留。",
                outcome: .partial,
                affectedItems: 1 + leftoverOutcomes.filter(\.succeeded).count,
                bytes: removedBytes
            )
        }
    }

    func analyze(_ root: URL? = nil, deepRefresh: Bool = false) async {
        guard !demoMode else { return }
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
        diskManualDecisions.decision(for: entry)
    }

    func canMarkForCleanupReview(_ entry: DiskEvidenceEntry) -> Bool {
        DiskManualDecisionPolicy.canReviewForCleanup(entry)
    }

    func setManualDiskDecision(
        _ decision: DiskManualDecision?,
        for entry: DiskEvidenceEntry
    ) {
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
        let previousRoot = diskReport?.root.standardizedFileURL.path
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
            let outcome = try await diskAnalyzer.analyze(
                root: target,
                cache: cache,
                mode: mode
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.diskScanProgress = progress
                    self?.diskPartialReport = progress.partialReport
                    self?.diskScanCacheHitCount = progress.cacheHitCount
                    self?.diskScanScannedCount = progress.scannedCount
                }
            }
            try Task.checkCancellation()
            try DiskScanCachePersistence.save(outcome.updatedCache, to: cacheURL)
            diskScanCacheHitCount = outcome.cacheHitCount
            diskScanScannedCount = outcome.scannedCount
            diskScanElapsedSeconds = outcome.elapsedSeconds
            diskScanCompletedAt = Date()
            try await finishDiskAnalysis(outcome.report)
            lastTechnicalDetail = outcome.usedCache
                ? "磁盘分析完成：复用 \(outcome.cacheHitCount) 项，实扫 \(outcome.scannedCount) 项，耗时 \(String(format: "%.2f", outcome.elapsedSeconds)) 秒。缓存只在元数据签名匹配且 15 分钟内复用。"
                : "磁盘分析完成：实扫 \(outcome.scannedCount) 项，耗时 \(String(format: "%.2f", outcome.elapsedSeconds)) 秒。"
            phase = .idle
        } catch is CancellationError {
            if let previousReport = diskReport {
                diskRoot = previousReport.root
                diskHasScanned = true
            }
            diskPartialReport = nil
            phase = .idle
        } catch {
            phase = .failed("磁盘分析没有完成")
            lastTechnicalDetail = error.localizedDescription
        }
    }

    private func finishDiskAnalysis(_ report: DiskReport) async throws {
        try Task.checkCancellation()
        diskScanProgress = nil
        diskEvidenceProgress = DiskEvidenceProgress(completed: 0, total: report.entries.count, currentName: "")

        let previous = try? DiskEvidencePersistence.load(from: CleanNestDataPaths.diskEvidenceSnapshot())
        let evidence = try await diskEvidenceIndexer.build(
            report: report,
            previous: previous,
            progress: { [weak self] progress in
                Task { @MainActor in self?.diskEvidenceProgress = progress }
            }
        )
        try Task.checkCancellation()
        try DiskEvidencePersistence.save(evidence, to: CleanNestDataPaths.diskEvidenceSnapshot())
        diskReport = report
        diskEvidenceReport = evidence
        diskHasScanned = true
        diskPartialReport = nil
        diskEvidenceProgress = nil
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
        phase = .executing("正在\(action.rawValue)…")
        do {
            let result = try await commandRunner.runChecked(executable: action.executable, arguments: action.arguments)
            lastTechnicalDetail = result.standardOutput + result.standardError
            phase = .success("\(action.rawValue)已完成")
            addActivity(title: action.rawValue, detail: action.explanation, outcome: .success, affectedItems: 1)
        } catch {
            phase = .failed("\(action.rawValue)没有完成")
            lastTechnicalDetail = error.localizedDescription
            addActivity(title: action.rawValue, detail: error.localizedDescription, outcome: .failed)
        }
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
            "metricsRetentionDays"
        ]
        for key in keys { settings.removeObject(forKey: key) }

        customEnginePath = ""
        developerMode = true
        includeApplicationCaches = false
        metricsRetentionDays = 30
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

    private func loadDiskManualDecisions() {
        do {
            diskManualDecisions = try DiskManualDecisionPersistence.load(
                from: CleanNestDataPaths.diskManualDecisions()
            )
        } catch {
            diskManualDecisions = DiskManualDecisionStore()
            lastTechnicalDetail = "手动清理决策无法读取，已使用空白记录：\(error.localizedDescription)"
        }
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
        bytes: Int64 = 0
    ) {
        activities.insert(
            ActivityEntry(
                title: title,
                detail: detail,
                outcome: outcome,
                affectedItems: affectedItems,
                bytes: bytes
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

    private func seedDemoData() {
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
        diskTotalBytes = 494_000_000_000
        diskFreeBytes = 148_000_000_000

        cleanupCandidates = [
            CleanupCandidate(name: "DerivedData", url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Demo"), kind: .developer, allocatedBytes: 4_820_000_000, modifiedAt: Date().addingTimeInterval(-1_900_000), isRecommended: true, detail: "Xcode 会在需要时重新生成"),
            CleanupCandidate(name: "Homebrew 下载缓存", url: home.appendingPathComponent("Library/Caches/Homebrew/downloads"), kind: .packageManager, allocatedBytes: 2_360_000_000, modifiedAt: Date().addingTimeInterval(-1_200_000), isRecommended: true, detail: "安装包可重新下载"),
            CleanupCandidate(name: "旧版设计工具安装包", url: home.appendingPathComponent("Downloads/DesignTool.dmg"), kind: .installer, allocatedBytes: 1_430_000_000, modifiedAt: Date().addingTimeInterval(-2_800_000), isRecommended: true, detail: "请确认不再需要重新安装"),
            CleanupCandidate(name: CleanupScanner.npmCacheDisplayName, url: home.appendingPathComponent(".npm/_cacache/content-v2"), kind: .packageManager, allocatedBytes: 890_000_000, modifiedAt: Date().addingTimeInterval(-3 * 86_400), isRecommended: false, detail: CleanupScanner.npmCacheDetail),
            CleanupCandidate(name: "旧诊断日志", url: home.appendingPathComponent("Library/Logs/DiagnosticReports"), kind: .logs, allocatedBytes: 124_000_000, modifiedAt: Date().addingTimeInterval(-7_800_000), isRecommended: false, detail: "排查问题时可能有用")
        ]
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
            ActivityEntry(date: Date().addingTimeInterval(-7_200), title: "清理空间", detail: "14 项已移到废纸篓，可在清空前恢复。", outcome: .success, affectedItems: 14, bytes: 3_820_000_000),
            ActivityEntry(date: Date().addingTimeInterval(-172_800), title: "重建快速预览缓存", detail: "系统维护任务已完成。", outcome: .success, affectedItems: 1)
        ]
    }
}
