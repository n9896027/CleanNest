import AppKit
import SwiftUI
import CleanNestCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var localAIEndpointDraft = ""
    @State private var localAIModelPathDraft = ""
    @State private var localAIExecutablePathDraft = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "设置",
                    subtitle: "引擎、权限与扫描范围都由你掌控。"
                )

                engineCard
                localAICard
                permissionCard
                scanningCard
                aboutCard
            }
            .padding(CNTheme.pagePadding)
        }
        .onAppear { syncLocalAIDrafts() }
        .onChange(of: localAIEndpointDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIModelPathDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIExecutablePathDraft) { store.clearLocalAIConfigurationError() }
    }

    private var engineCard: some View {
        SurfaceCard(title: "本地引擎", symbol: "gearshape.2") {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(store.engine == nil ? CNTheme.warning : CNTheme.success)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.engine == nil ? "Mole CLI 尚未连接" : "Mole CLI 已就绪")
                            .font(.subheadline.weight(.semibold))
                        Text(store.engine?.executable.path ?? store.engineDiagnostic)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if let version = store.engine?.version {
                        StatusPill(text: version, symbol: "checkmark", style: .success)
                    }
                }

                Divider()

                HStack(spacing: 9) {
                    TextField("自定义 mo / mole 路径", text: $store.customEnginePath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task { await store.setCustomEnginePath(store.customEnginePath) }
                        }
                    Button("选择…") { chooseEngine() }
                    Button("重新检测") { Task { await store.refreshEngine() } }
                }

                HStack {
                    Text("保持 CLI 为独立本地进程，方便以后更新或替换引擎。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if store.engine == nil {
                        Button("通过 Homebrew 免费安装") {
                            Task { await store.installEngine() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isWorking)
                    } else if store.engineCanUpdateWithHomebrew {
                        Button("检查更新") {
                            Task { await store.updateEngine() }
                        }
                        .disabled(store.isWorking)
                    } else {
                        StatusPill(text: "自定义管理", symbol: "person.crop.circle", style: .neutral)
                    }
                }
            }
        }
    }

    private var permissionCard: some View {
        SurfaceCard(title: "安全与权限", symbol: "lock.shield") {
            VStack(spacing: 0) {
                settingsRow(
                    symbol: "externaldrive.badge.checkmark",
                    title: "完全磁盘访问",
                    detail: fullDiskAccessStatusDetail
                ) {
                    HStack(spacing: 8) {
                        if store.fullDiskAccessProbeIsRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            StatusPill(
                                text: fullDiskAccessStatusText,
                                symbol: fullDiskAccessStatusSymbol,
                                style: fullDiskAccessStatusStyle
                            )
                        }
                        Button("重新检测") {
                            Task { await store.refreshFullDiskAccessProbe() }
                        }
                        .disabled(store.fullDiskAccessProbeIsRunning)
                        Button(store.waitingForFullDiskAccessReturn ? "等待返回…" : "打开系统设置") {
                            store.openFullDiskAccessSettings()
                        }
                        .disabled(
                            store.waitingForFullDiskAccessReturn
                                || store.fullDiskAccessProbeIsRunning
                        )
                    }
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "trash",
                    title: "恢复策略",
                    detail: "当前所有原生清理与卸载操作只移到废纸篓。"
                ) {
                    StatusPill(text: "不可关闭", symbol: "lock.fill", style: .success)
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "link.badge.plus",
                    title: "符号链接保护",
                    detail: "为避免越过允许目录，符号链接目标一律跳过。"
                ) {
                    StatusPill(text: "已开启", symbol: "checkmark", style: .success)
                }
            }
        }
    }

    private var fullDiskAccessStatusDetail: String {
        if store.waitingForFullDiskAccessReturn {
            return "系统设置已由你手动打开；打开成功不等于已授权。确实离开并返回 CleanNest 后只会重新测试一次。"
        }
        if store.fullDiskAccessProbeIsRunning {
            return "CleanNest 正在由自身做一次轻量访问测试，不会启动 Mole 或 du。"
        }
        switch store.fullDiskAccessProbeResult {
        case .accessible:
            return "CleanNest 自身的访问测试已通过。这是当前实际读取结果，不是“打开系统设置”的成功回执。"
        case .permissionDenied:
            return "CleanNest 自身的访问测试收到权限拒绝。受保护目录的扫描与 AI 采样会先被阻止。"
        case .indeterminate:
            return "本次访问测试无法得出结论。为避免连续授权弹窗，受保护目录仍默认不扫描。"
        }
    }

    private var fullDiskAccessStatusText: String {
        if store.waitingForFullDiskAccessReturn { return "等待返回" }
        switch store.fullDiskAccessProbeResult {
        case .accessible: return "访问测试通过"
        case .permissionDenied: return "访问测试未通过"
        case .indeterminate: return "状态待确认"
        }
    }

    private var fullDiskAccessStatusSymbol: String {
        if store.waitingForFullDiskAccessReturn { return "arrow.uturn.backward" }
        switch store.fullDiskAccessProbeResult {
        case .accessible: return "checkmark"
        case .permissionDenied: return "lock.fill"
        case .indeterminate: return "questionmark"
        }
    }

    private var fullDiskAccessStatusStyle: StatusPill.Style {
        if store.waitingForFullDiskAccessReturn { return .neutral }
        switch store.fullDiskAccessProbeResult {
        case .accessible: return .success
        case .permissionDenied: return .warning
        case .indeterminate: return .neutral
        }
    }

    private var localAICard: some View {
        SurfaceCard(title: "本机 AI 分析", symbol: "brain.head.profile") {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(localAIStatusColor)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localAIStatusTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(localAIStatusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 12)
                    if localAIDraftIsDirty {
                        StatusPill(text: "待保存", symbol: "pencil", style: .warning)
                    } else if store.localAIServiceState.isBusy {
                        ProgressView().controlSize(.small)
                    } else if store.localAIIsReady {
                        StatusPill(
                            text: store.localAIProcessOwned ? "App 管理" : "复用本机服务",
                            symbol: "checkmark",
                            style: .success
                        )
                    }
                    Toggle("", isOn: Binding(
                        get: { store.localAIEnabled },
                        set: { store.setLocalAIEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("启用本机 AI 分析")
                    .help("关闭后普通规则扫描仍可使用；只会停止由 CleanNest 自己启动的模型进程。")
                }

                Divider()

                VStack(spacing: 10) {
                    HStack(spacing: 9) {
                        Text("服务地址")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)
                        TextField("http://127.0.0.1:8080/v1", text: $localAIEndpointDraft)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 9) {
                        Text("模型目录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)
                        TextField("本机 MLX 模型目录", text: $localAIModelPathDraft)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1)
                        Button("选择…") { chooseLocalAIModel() }
                    }

                    HStack(spacing: 9) {
                        Text("运行程序")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 62, alignment: .leading)
                        TextField("mlx_lm.server 可执行文件", text: $localAIExecutablePathDraft)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1)
                        Button("选择…") { chooseLocalAIExecutable() }
                    }
                }
                .disabled(!store.localAIEnabled || store.localAIServiceState.isBusy)

                if let configurationError = store.localAIConfigurationError {
                    Label(configurationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(CNTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(alignment: .center, spacing: 12) {
                    Label("只发送名称、脱敏路径、大小、类型、时间和扫描说明；不读取文件内容，AI 也不能勾选或删除。", systemImage: "lock.shield")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Button("诊断详情") { store.showLocalAIDiagnostic() }
                    Button("保存并检测") {
                        Task {
                            _ = await applyLocalAIDrafts()
                        }
                    }
                    .disabled(!store.localAIEnabled || store.localAIServiceState.isBusy)
                    if store.localAIProcessOwned {
                        Button("停止模型") {
                            Task { await store.stopLocalAI() }
                        }
                        .disabled(store.localAIServiceState.isBusy)
                    } else if store.localAIEnabled && !store.localAIIsReady {
                        Button("启动本机模型") {
                            Task {
                                if await applyLocalAIDrafts(), !store.localAIIsReady {
                                    await store.startLocalAI()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.localAIServiceState.isBusy)
                    }
                }
            }
        }
    }

    private var localAIStatusTitle: String {
        switch store.localAIServiceState {
        case .disabled: return "本机 AI 已关闭"
        case .unchecked: return "尚未检测本机模型"
        case .checking: return "正在检测本机模型…"
        case .starting: return "正在载入本机模型…"
        case .stopping: return "正在停止本机模型…"
        case .ready: return "\(store.localAIModelDisplayName) 已连接"
        case .unavailable: return "本机模型尚未连接"
        }
    }

    private var localAIStatusDetail: String {
        switch store.localAIServiceState {
        case .disabled:
            return "普通扫描仍可继续使用。"
        case .unchecked:
            return "保存设置后即可检测，无需打开终端。"
        case .checking:
            return "正在检查回环服务与所选模型。"
        case .starting:
            return "大型模型首次载入可能需要几十秒，界面仍可继续使用。"
        case .stopping:
            return "正在安全结束由 CleanNest 启动的模型进程。"
        case .ready(let modelID):
            return modelID
        case .unavailable(let detail):
            return detail
        }
    }

    private var localAIStatusColor: Color {
        switch store.localAIServiceState {
        case .ready: return CNTheme.success
        case .checking, .starting, .stopping: return CNTheme.accent
        case .disabled, .unchecked: return Color.secondary
        case .unavailable: return CNTheme.warning
        }
    }

    private var localAIDraftIsDirty: Bool {
        localAIEndpointDraft != store.localAIEndpoint
            || localAIModelPathDraft != store.localAIModelPath
            || localAIExecutablePathDraft != store.localAIExecutablePath
    }

    private var scanningCard: some View {
        SurfaceCard(title: "扫描范围", symbol: "scope") {
            VStack(spacing: 0) {
                settingsRow(
                    symbol: "hammer",
                    title: "开发者模式",
                    detail: "扫描 Xcode、Homebrew、npm 与 pip 的可再生成缓存。"
                ) {
                    Toggle("", isOn: Binding(
                        get: { store.developerMode },
                        set: { store.setDeveloperMode($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "square.stack.3d.up",
                    title: "应用缓存",
                    detail: "默认关闭；开启后只展示，不会自动勾选。"
                ) {
                    Toggle("", isOn: $store.includeApplicationCaches).labelsHidden().toggleStyle(.switch)
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "externaldrive",
                    title: "外接磁盘",
                    detail: "磁盘浏览可以手动选择外接卷；后台自动扫描保持关闭。"
                ) {
                    StatusPill(text: "手动选择", symbol: "cursorarrow.click", style: .neutral)
                }
            }
        }
    }

    private var aboutCard: some View {
        SurfaceCard(title: "关于 CleanNest", symbol: "leaf") {
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(CNTheme.accent)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                VStack(alignment: .leading, spacing: 5) {
                    Text("CleanNest \(appVersion)")
                        .font(.headline)
                    Text("独立、可修改的原生 macOS 客户端。不是 Mole 官方 App，也不使用官方图标。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("可选引擎：Mole CLI，由 tw93 与贡献者维护，GPL-3.0。CleanNest 不捆绑其二进制。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("查看 Mole 开源项目与许可证") { store.openMoleProject() }
                        .buttonStyle(.link)
                        .padding(.top, 3)
                }
                Spacer()
            }
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "开发版"
    }

    private func settingsRow<Accessory: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(CNTheme.accent)
                .frame(width: 30, height: 30)
                .background(CNTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            accessory()
        }
        .padding(.vertical, 11)
    }

    private func chooseEngine() {
        let panel = NSOpenPanel()
        panel.title = "选择 mo 或 mole 可执行文件"
        panel.prompt = "使用此引擎"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.setCustomEnginePath(url.path) }
    }

    private func chooseLocalAIModel() {
        let panel = NSOpenPanel()
        panel.title = "选择 MLX 模型目录"
        panel.prompt = "使用此模型"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localAIModelPathDraft = url.path
    }

    private func chooseLocalAIExecutable() {
        let panel = NSOpenPanel()
        panel.title = "选择 mlx_lm.server"
        panel.prompt = "使用此程序"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localAIExecutablePathDraft = url.path
    }

    private func syncLocalAIDrafts() {
        localAIEndpointDraft = store.localAIEndpoint
        localAIModelPathDraft = store.localAIModelPath
        localAIExecutablePathDraft = store.localAIExecutablePath
    }

    private func applyLocalAIDrafts() async -> Bool {
        let applied = await store.applyLocalAISettings(
            endpoint: localAIEndpointDraft,
            modelPath: localAIModelPathDraft,
            executablePath: localAIExecutablePathDraft
        )
        if applied { syncLocalAIDrafts() }
        return applied
    }
}
