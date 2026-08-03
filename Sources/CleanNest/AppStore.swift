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
    case activity = "活动记录"
    case settings = "设置"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .cleanup: return "sparkles"
        case .applications: return "app.dashed"
        case .analyze: return "chart.pie"
        case .status: return "waveform.path.ecg"
        case .maintenance: return "wrench.and.screwdriver"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }

    static let spaceItems: [SidebarItem] = [.cleanup, .applications, .analyze]
    static let systemItems: [SidebarItem] = [.status, .maintenance]
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
    @Published var diskTotalBytes: Int64 = 0
    @Published var diskFreeBytes: Int64 = 0

    @Published var cleanupCandidates: [CleanupCandidate] = []
    @Published var selectedCleanupIDs = Set<String>()
    @Published var includeApplicationCaches = false
    @Published var developerMode = true
    @Published var cleanupHasScanned = false
    @Published var localAIEnabled = true
    @Published var localAIEndpoint = "http://127.0.0.1:8080/v1"
    @Published var localAIModelPath = ""
    @Published var localAIExecutablePath = ""
    @Published private(set) var localAIServiceState: LocalAIServiceState = .unchecked
    @Published private(set) var localAIProcessOwned = false
    @Published private(set) var cleanupAIPhase: CleanupAIPhase = .idle
    @Published private(set) var cleanupAIAnalysis: CleanupAIAnalysis?
    @Published private(set) var localAIDiagnostic = "尚未检测"
    @Published private(set) var localAIConfigurationError: String?

    @Published var applications: [InstalledApplication] = []
    @Published var applicationSearch = ""
    @Published var selectedApplication: InstalledApplication?
    @Published var selectedApplicationLeftovers: [CleanupCandidate] = []
    @Published var applicationsHaveScanned = false

    @Published var diskReport: DiskReport?
    @Published var diskRoot = FileManager.default.homeDirectoryForCurrentUser
    @Published var diskHasScanned = false
    @Published private(set) var diskAIPhase: DiskAIPhase = .idle
    @Published private(set) var diskAIAnalysis: DiskAIAnalysis?
    @Published private(set) var diskAIChildContexts: [String: DiskAIChildContext] = [:]
    @Published private(set) var fullDiskAccessProbeResult: FullDiskAccessProbeResult = .indeterminate
    @Published private(set) var fullDiskAccessProbeIsRunning = false
    @Published private(set) var waitingForFullDiskAccessReturn = false
    @Published private(set) var diskPrivacyBlockMessage: String?

    @Published var activities: [ActivityEntry] = []
    @Published var customEnginePath = ""
    @Published var lastTechnicalDetail = ""
    @Published var showingTechnicalDetail = false

    let demoMode: Bool

    private let commandRunner = CommandRunner()
    private let cleanupScanner = CleanupScanner()
    private let applicationScanner = ApplicationScanner()
    private let diskAnalyzer = NativeDiskAnalyzer()
    private let processMemoryInspector = ProcessMemoryInspector()
    private let trashService = TrashService()
    private let localAIRuntime = LocalMLXRuntime()
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

    init() {
        demoMode = ProcessInfo.processInfo.environment["CLEANNEST_DEMO"] == "1"
        customEnginePath = settings.string(forKey: "customEnginePath") ?? ""
        if settings.object(forKey: "developerMode") != nil {
            developerMode = settings.bool(forKey: "developerMode")
        }
        if settings.object(forKey: "localAIEnabled") != nil {
            localAIEnabled = settings.bool(forKey: "localAIEnabled")
        }
        localAIEndpoint = settings.string(forKey: "localAIEndpoint") ?? "http://127.0.0.1:8080/v1"
        localAIModelPath = settings.string(forKey: "localAIModelPath")
            ?? Self.preferredLocalModelPath(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
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
        loadActivities()

        if demoMode {
            seedDemoData()
        }

        refreshDiskCapacity()
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
        let trimmed = localAIModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未选择模型" }
        return URL(fileURLWithPath: trimmed).lastPathComponent
    }

    var engineCanUpdateWithHomebrew: Bool {
        guard let path = engine?.executable.path else { return false }
        return path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/")
    }

    func bootstrap() async {
        if demoMode { return }
        await refreshFullDiskAccessProbe()
        await refreshEngine()
        if engine != nil {
            await refreshSystemStatus(silent: true)
        }
        if localAIEnabled {
            await probeLocalAI()
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
        customEnginePath = path
        settings.set(path, forKey: "customEnginePath")
        await refreshEngine()
    }

    func setLocalAIEnabled(_ enabled: Bool) {
        localAIEnabled = enabled
        settings.set(enabled, forKey: "localAIEnabled")
        localAIProbeID = UUID()
        invalidateCleanupAI()
        invalidateDiskAI()

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

    func applyLocalAISettings(endpoint: String, modelPath: String, executablePath: String) async -> Bool {
        let validatedEndpoint: LocalAIEndpoint
        let validatedModelURL: URL
        let normalizedExecutablePath: String
        do {
            validatedEndpoint = try LocalAIEndpoint(rawValue: endpoint)
            validatedModelURL = try Self.validatedLocalModelURL(path: modelPath)
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
        let nextModelPath = validatedModelURL.path
        let previousConfiguration = [localAIEndpoint, localAIModelPath, localAIExecutablePath]
        let nextConfiguration = [nextEndpoint, nextModelPath, normalizedExecutablePath]
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
        localAIModelPath = nextModelPath
        localAIExecutablePath = normalizedExecutablePath
        persistLocalAISettings()
        localAIConfigurationError = nil
        if configurationChanged {
            invalidateCleanupAI()
            invalidateDiskAI()
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
        do {
            let (modelID, _) = try await probeConfiguredLocalAI()
            guard localAIProbeID == probeID else { return }
            localAIProcessOwned = localAIRuntime.ownsRunningProcess
            localAIServiceState = .ready(modelID: modelID)
            localAIDiagnostic = "已连接本机回环服务；文件内容不会发送给模型。"
        } catch {
            guard localAIProbeID == probeID else { return }
            localAIProcessOwned = localAIRuntime.ownsRunningProcess
            localAIServiceState = .unavailable(error.localizedDescription)
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
            let modelURL = try configuredLocalModelURL()

            let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
            if let runningService = try? await client.probe() {
                guard localAIEnabled, localAIProbeID == startupID else { return }
                if service(runningService, contains: modelURL.path) {
                    localAIServiceState = .ready(modelID: modelURL.path)
                    localAIProcessOwned = localAIRuntime.ownsRunningProcess
                    localAIDiagnostic = "已复用正在运行的本机模型服务。"
                    return
                }
                throw LocalAIError.serviceUnavailable("端口 \(endpoint.port) 已被另一模型服务占用，请更换端口")
            }
            guard localAIEnabled, localAIProbeID == startupID else { return }

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
                    guard service(result, contains: modelURL.path) else {
                        throw LocalAIError.modelUnavailable("服务未列出所选模型")
                    }
                    localAIServiceState = .ready(modelID: modelURL.path)
                    localAIProcessOwned = true
                    localAIDiagnostic = "模型已由 CleanNest 在本机启动。"
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

    func shutdownLocalAI() {
        localAIRuntime.stopOwnedProcess()
        localAIProcessOwned = false
    }

    func shutdownForTermination() {
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
        guard let engine else {
            let nativeMemory = await nativeMemoryTask.value
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
            phase = .idle
        } catch {
            let nativeMemory = await nativeMemoryTask.value
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

        cleanupCandidates.removeAll { succeededPaths.contains($0.url.standardizedFileURL.path) }
        selectedCleanupIDs.subtract(selected.map(\.id))
        invalidateCleanupAI()
        refreshDiskCapacity()

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
        guard let bundleID = application.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    func askApplicationToQuit(_ application: InstalledApplication) {
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

        phase = .executing("正在将 \(application.name) 移到废纸篓…")
        let appOutcome = await trashService.trashApplication(application.url)
        guard appOutcome.succeeded else {
            phase = .failed("未能卸载 \(application.name)，没有处理相关文件")
            lastTechnicalDetail = appOutcome.errorDescription ?? "未知错误"
            addActivity(title: "卸载 \(application.name)", detail: lastTechnicalDetail, outcome: .failed)
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
            addActivity(
                title: "卸载 \(application.name)",
                detail: includeLeftovers ? "App 与精确匹配的相关文件已移到废纸篓。" : "App 已移到废纸篓，相关文件已保留。",
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

    func analyze(_ root: URL? = nil) async {
        guard !isWorking else { return }
        let cancelledCollectionTask = invalidateDiskAI()
        let target = (root ?? diskRoot).standardizedFileURL
        let previousRoot = diskReport?.root.standardizedFileURL.path
        diskRoot = target
        if previousRoot != nil, previousRoot != target.path {
            diskReport = nil
            diskHasScanned = false
        }

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
        if let cancelledCollectionTask {
            _ = await cancelledCollectionTask.value
            pendingDiskAICancellationTask = nil
        }
        guard !Task.isCancelled else {
            phase = .idle
            return
        }

        if !demoMode, let engine {
            do {
                let result = try await commandRunner.runChecked(
                    executable: engine.executable,
                    arguments: ["analyze", "--json", target.path],
                    environment: commandEnvironment
                )
                guard !Self.containsPermissionFailure(result.standardError) else {
                    recordDiskPermissionFailure(
                        target: target,
                        detail: result.standardError,
                        source: "Mole"
                    )
                    return
                }
                guard let data = result.standardOutput.data(using: .utf8) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                diskReport = try MoleJSONDecoder.diskReport(from: data, fallbackRoot: target)
                lastTechnicalDetail = result.standardError
                diskHasScanned = true
                phase = .idle
                return
            } catch is CancellationError {
                phase = .idle
                return
            } catch {
                if Self.isPermissionFailure(error) {
                    recordDiskPermissionFailure(
                        target: target,
                        detail: error.localizedDescription,
                        source: "Mole"
                    )
                    return
                }
                if diskTraversalMayRequireFullDiskAccess(target) {
                    diskPrivacyBlockMessage = "Mole 未能完成受保护目录的分析。CleanNest 已阻止随后的原生递归扫描，避免对同一批应用数据再次发起访问。"
                    lastTechnicalDetail = "\(diskPrivacyBlockMessage ?? "")\n\nMole 错误：\(error.localizedDescription)"
                    phase = .idle
                    return
                }
                lastTechnicalDetail = "Mole 分析不可用，已回退到原生扫描：\(error.localizedDescription)"
            }
        }

        diskReport = await diskAnalyzer.analyze(root: target)
        diskHasScanned = true
        phase = .idle
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
        settings.set(enabled, forKey: "developerMode")
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
        localAIModelPath = localAIModelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        localAIExecutablePath = localAIExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.set(localAIEndpoint, forKey: "localAIEndpoint")
        settings.set(localAIModelPath, forKey: "localAIModelPath")
        settings.set(localAIExecutablePath, forKey: "localAIExecutablePath")
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
            .resolvingSymlinksInPath()
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

    private func probeConfiguredLocalAI() async throws -> (String, LocalAIProbeResult) {
        let modelID = try configuredLocalModelURL().path
        let client = try MLXOpenAIClient(endpoint: localAIEndpoint)
        let result = try await client.probe()
        guard service(result, contains: modelID) else {
            throw LocalAIError.modelUnavailable("服务已响应，但没有列出所选模型")
        }
        return (modelID, result)
    }

    private func service(_ result: LocalAIProbeResult, contains modelID: String) -> Bool {
        let expected = URL(fileURLWithPath: modelID).standardizedFileURL.path
        return result.modelIDs.contains { listed in
            guard (listed as NSString).isAbsolutePath else { return listed == modelID }
            return URL(fileURLWithPath: listed).standardizedFileURL.path == expected
        }
    }

    private func invalidateCleanupAI() {
        cleanupRevision &+= 1
        activeAIRequestID = UUID()
        cleanupAIAnalysis = nil
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
        diskAIChildContexts = [:]
        diskAIPhase = .idle
        return collectionTask
    }

    private static func preferredLocalModelPath(homeDirectory: URL) -> String {
        let root = homeDirectory.appendingPathComponent("Models/MLX", isDirectory: true)
        let preferred = root.appendingPathComponent("gemma-4-26b-a4b-it-8bit", isDirectory: true)
        if FileManager.default.fileExists(atPath: preferred.path) { return preferred.path }

        let candidates = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        if let model = candidates
            .filter({ $0.lastPathComponent.localizedCaseInsensitiveContains("gemma") })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            .first {
            return model.path
        }
        return preferred.path
    }

    private var commandEnvironment: [String: String] {
        let original = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + original]
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

    private var activityFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("CleanNest", isDirectory: true).appendingPathComponent("activity.json")
    }

    private func loadActivities() {
        guard let url = activityFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([ActivityEntry].self, from: data) else { return }
        activities = decoded
    }

    private func saveActivities() {
        guard let url = activityFileURL,
              let data = try? JSONEncoder().encode(activities) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private func seedDemoData() {
        let home = FileManager.default.homeDirectoryForCurrentUser
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
        if let systemSnapshot {
            memoryAnalysis = MemoryAnalyzer.analyze(snapshot: systemSnapshot, processes: [])
        }
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
        localAIModelPath = home.appendingPathComponent("Models/MLX/gemma-4-26b-a4b-it-8bit").path
        localAIExecutablePath = home.appendingPathComponent(".mlx-env/bin/mlx_lm.server").path
        localAIServiceState = .ready(modelID: localAIModelPath)
        localAIDiagnostic = "演示模式：本机模型已连接"
        cleanupAIAnalysis = CleanupAIAnalysis(
            modelID: localAIModelPath,
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
        if let entries = diskReport?.entries {
            diskAIAnalysis = DiskAIAnalysis(
                modelID: localAIModelPath,
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
