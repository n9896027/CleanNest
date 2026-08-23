import AppKit
import SwiftUI
import CleanNestCore

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var localAIEndpointDraft = ""
    @State private var localAIServiceModelIDDraft = ""
    @State private var localAIModelPathDraft = ""
    @State private var localAIExecutablePathDraft = ""
    @State private var showsClearMetricsConfirmation = false
    @State private var engineAdvancedExpanded = false
    @State private var localAIAdvancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "设置",
                    subtitle: "引擎、权限与扫描范围都由你掌控。"
                )

                readinessDeck
                localAICard

                LazyVGrid(columns: settingsGridColumns, alignment: .leading, spacing: 16) {
                    engineCard
                    permissionCard
                    metricsCard
                    scanningCard
                    mcpCard
                    aboutCard
                }
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
        .onAppear {
            syncLocalAIDrafts()
            if store.localAIAvailableModels.isEmpty {
                Task { await store.refreshLocalModelCatalog() }
            }
            localAIAdvancedExpanded = !store.localAIIsReady
        }
        .onChange(of: localAIEndpointDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIServiceModelIDDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIModelPathDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIExecutablePathDraft) { store.clearLocalAIConfigurationError() }
        .confirmationDialog(
            "清空所有本机历史指标？",
            isPresented: $showsClearMetricsConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空历史记录", role: .destructive) {
                Task { await store.clearMetricHistory() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这只删除 CleanNest 记录的 CPU、内存、磁盘、电池与温度样本；不会删除系统文件。后续采样会重新开始。")
        }
    }

    private var settingsGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 360), spacing: 16, alignment: .top)]
    }

    private var readinessDeck: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                readinessItem(
                    title: "本地引擎",
                    status: store.engine == nil ? "需要连接" : "运行正常",
                    detail: store.engine?.version ?? "Mole CLI",
                    symbol: "gearshape.2",
                    tint: store.engine == nil ? CNTheme.warning : CNTheme.success
                )
                readinessItem(
                    title: "本机 AI 分析",
                    status: store.localAIIsReady ? "模型已连接" : "等待设置",
                    detail: store.localAIIsReady ? store.localAIModelDisplayName : "普通扫描仍可继续使用。",
                    symbol: "brain.head.profile",
                    tint: store.localAIIsReady ? CNTheme.cyan : CNTheme.warning
                )
                readinessItem(
                    title: "文件访问",
                    status: fullDiskAccessStatusText,
                    detail: "由 CleanNest 自身实测",
                    symbol: "lock.shield",
                    tint: store.fullDiskAccessProbeResult == .accessible ? CNTheme.success : CNTheme.warning
                )
            }
            VStack(spacing: 10) {
                readinessItem(title: "本地引擎", status: store.engine == nil ? "需要连接" : "运行正常", detail: store.engine?.version ?? "Mole CLI", symbol: "gearshape.2", tint: store.engine == nil ? CNTheme.warning : CNTheme.success)
                readinessItem(title: "本机 AI 分析", status: store.localAIIsReady ? "模型已连接" : "等待设置", detail: store.localAIIsReady ? store.localAIModelDisplayName : "普通扫描仍可继续使用。", symbol: "brain.head.profile", tint: store.localAIIsReady ? CNTheme.cyan : CNTheme.warning)
                readinessItem(title: "文件访问", status: fullDiskAccessStatusText, detail: "由 CleanNest 自身实测", symbol: "lock.shield", tint: store.fullDiskAccessProbeResult == .accessible ? CNTheme.success : CNTheme.warning)
            }
        }
    }

    private func readinessItem(
        title: String,
        status: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            CNIconTile(symbol: symbol, tint: tint, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(CNL10n.string(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CNL10n.string(status))
                    .font(.system(size: 14.5, weight: .semibold))
                Text(CNL10n.string(detail))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.085), lineWidth: 0.65)
        )
    }

    private var engineCard: some View {
        SurfaceCard(title: "本地引擎", symbol: "gearshape.2", tint: CNTheme.cyan) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(store.engine == nil ? CNTheme.warning : CNTheme.success)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CNL10n.string(store.engine == nil ? "Mole CLI 尚未连接" : "Mole CLI 已就绪"))
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

                Text("保持 CLI 为独立本地进程，方便以后更新或替换引擎。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Button("重新检测") { Task { await store.refreshEngine() } }
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
                    Spacer()
                }

                DisclosureGroup(isExpanded: $engineAdvancedExpanded) {
                    HStack(spacing: 8) {
                        TextField("自定义 mo / mole 路径", text: $store.customEnginePath)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                Task { await store.setCustomEnginePath(store.customEnginePath) }
                            }
                        Button("选择…") { chooseEngine() }
                    }
                    .padding(.top, 10)
                } label: {
                    Label("更换或指定引擎路径", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                }
                .tint(CNTheme.cyan)
            }
        }
    }

    private var permissionCard: some View {
        SurfaceCard(title: "安全与权限", symbol: "lock.shield", tint: CNTheme.success) {
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
        SurfaceCard(
            title: "本机 AI 分析",
            symbol: "brain.head.profile",
            prominence: .prominent,
            tint: CNTheme.violet
        ) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(localAIStatusColor)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(CNL10n.string(localAIStatusTitle))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(CNL10n.string(localAIStatusDetail))
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
                    .accessibilityLabel(CNL10n.string("启用本机 AI 分析"))
                    .help(CNL10n.string("关闭后普通规则扫描仍可使用；只会停止由 CleanNest 自己启动的模型进程。"))
                }

                Divider()

                VStack(spacing: 10) {
                    HStack(spacing: 9) {
                        Text("当前模型")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)
                        Picker("选择本机模型", selection: $localAIModelPathDraft) {
                            if localAIModelPathDraft.isEmpty {
                                Text("请选择一个本机模型").tag("")
                            }
                            ForEach(store.localAIAvailableModels) { model in
                                Text(localAIModelPickerLabel(model)).tag(model.path)
                            }
                            if !localAIModelPathDraft.isEmpty,
                               !store.localAIAvailableModels.contains(where: { $0.path == localAIModelPathDraft }) {
                                Text(URL(fileURLWithPath: localAIModelPathDraft).lastPathComponent)
                                    .tag(localAIModelPathDraft)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("localAI.modelPicker")
                        if store.localAIModelCatalogIsRefreshing {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 70)
                        } else {
                            Button("扫描模型") {
                                Task { await store.refreshLocalModelCatalog() }
                            }
                            .accessibilityIdentifier("localAI.scanModels")
                        }
                        Button("选择其他…") { chooseLocalAIModel() }
                    }

                    if let model = selectedLocalAIModel {
                        HStack(spacing: 11) {
                            CNIconTile(symbol: "cpu", tint: CNTheme.violet, size: 34)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.displayName)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(localAIModelFacts(model))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusPill(text: "本机模型", symbol: "lock.shield", style: .success)
                        }
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.65)
                        )
                    } else {
                        Label(CNL10n.string(store.localAIModelCatalogDiagnostic), systemImage: "magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DisclosureGroup(isExpanded: $localAIAdvancedExpanded) {
                        VStack(spacing: 10) {
                            HStack(spacing: 9) {
                                Text("服务地址")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                TextField("http://127.0.0.1:8080/v1", text: $localAIEndpointDraft)
                                    .textFieldStyle(.roundedBorder)
                            }

                            HStack(spacing: 9) {
                                Text("API 模型")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                Picker("选择服务公布的模型短名", selection: $localAIServiceModelIDDraft) {
                                    Text(serviceModelAutomaticLabel).tag("")
                                    ForEach(store.localAIAvailableServiceModelIDs, id: \.self) { modelID in
                                        Text(serviceModelPickerLabel(modelID)).tag(modelID)
                                    }
                                    if !localAIServiceModelIDDraft.isEmpty,
                                       !store.localAIAvailableServiceModelIDs.contains(where: {
                                           $0.caseInsensitiveCompare(localAIServiceModelIDDraft) == .orderedSame
                                       }) {
                                        Text(localAIServiceModelIDDraft).tag(localAIServiceModelIDDraft)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("localAI.serviceModelPicker")
                            }

                            Label(
                                "oMLX 调用必须使用 /v1/models 返回的短名；下方目录只用于 CleanNest 自己启动 mlx_lm.server。",
                                systemImage: "arrow.triangle.branch"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 9) {
                                Text("目录路径")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                TextField("本机 MLX 模型目录", text: $localAIModelPathDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 9) {
                                Text("运行程序")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 72, alignment: .leading)
                                TextField("mlx_lm.server 可执行文件", text: $localAIExecutablePathDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(1)
                                Button("选择…") { chooseLocalAIExecutable() }
                            }
                        }
                        .padding(.top, 11)
                    } label: {
                        HStack(spacing: 8) {
                            Label("连接与高级设置", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(localAIEndpointDraft)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .tint(CNTheme.violet)
                    .padding(12)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(Color.white.opacity(0.07), lineWidth: 0.65)
                    )
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
                    Button("仅保存并检测") {
                        Task {
                            _ = await applyLocalAIDrafts()
                        }
                    }
                    .accessibilityIdentifier("localAI.saveAndProbe")
                    .disabled(!store.localAIEnabled || store.localAIServiceState.isBusy)
                    if store.localAIProcessOwned {
                        Button("停止模型") {
                            Task { await store.stopLocalAI() }
                        }
                        .disabled(store.localAIServiceState.isBusy)
                    } else if store.localAIEnabled && (!store.localAIIsReady || localAIDraftIsDirty) {
                        Button(CNL10n.string(localAIModelSelectionChanged ? "切换并启动" : "启动所选模型")) {
                            Task {
                                if await applyLocalAIDrafts(), !store.localAIIsReady {
                                    await store.startLocalAI()
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("localAI.switchAndStart")
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
            || localAIServiceModelIDDraft != store.localAIServiceModelID
            || localAIModelPathDraft != store.localAIModelPath
            || localAIExecutablePathDraft != store.localAIExecutablePath
    }

    private var localAIModelSelectionChanged: Bool {
        localAIServiceModelIDDraft != store.localAIServiceModelID
            || localAIModelPathDraft != store.localAIModelPath
    }

    private var serviceModelAutomaticLabel: String {
        if let defaultModelID = store.localAIDefaultServiceModelID, !defaultModelID.isEmpty {
            return CNL10n.format("自动（服务默认：%@）", defaultModelID)
        }
        return CNL10n.string("自动（读取服务默认模型）")
    }

    private func serviceModelPickerLabel(_ modelID: String) -> String {
        let lowered = modelID.lowercased()
        if lowered.contains("dflash") || lowered.contains("draftmodel") {
            return CNL10n.format("%@ · DFlash 加速草稿（不要直接选择）", modelID)
        }
        return modelID
    }

    private var selectedLocalAIModel: LocalModelDescriptor? {
        store.localAIModelDescriptor(path: localAIModelPathDraft)
    }

    private func localAIModelPickerLabel(_ model: LocalModelDescriptor) -> String {
        var details: [String] = []
        if let quantization = model.quantization { details.append(quantization) }
        if model.weightBytes > 0 { details.append(CleanNestFormatting.bytes(model.weightBytes)) }
        guard !details.isEmpty else { return model.displayName }
        return "\(model.displayName) · \(details.joined(separator: " · "))"
    }

    private func localAIModelFacts(_ model: LocalModelDescriptor) -> String {
        var details: [String] = []
        if let architecture = model.architecture { details.append(architecture) }
        else if let modelType = model.modelType { details.append(modelType) }
        if let quantization = model.quantization { details.append(quantization) }
        if model.weightBytes > 0 { details.append(CleanNestFormatting.bytes(model.weightBytes)) }
        return details.isEmpty ? "MLX 模型" : details.joined(separator: " · ")
    }

    private var metricsCard: some View {
        SurfaceCard(title: "历史指标", symbol: "chart.xyaxis.line", tint: CNTheme.accent) {
            VStack(spacing: 0) {
                settingsRow(
                    symbol: "clock.arrow.circlepath",
                    title: "连续本机采样",
                    detail: "每 60 秒记录 CPU、内存、磁盘、电池与温度；使用 SQLite WAL，只保存在这台 Mac。"
                ) {
                    StatusPill(
                        text: store.metricsSamplingIsActive ? "正在采样" : "等待引擎",
                        symbol: store.metricsSamplingIsActive ? "checkmark" : "pause",
                        style: store.metricsSamplingIsActive ? .success : .neutral
                    )
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "calendar.badge.clock",
                    title: "保留期限",
                    detail: "到期样本自动清理，不影响当前系统状态。"
                ) {
                    Picker("保留期限", selection: Binding(
                        get: { store.metricsRetentionDays },
                        set: { days in Task { await store.setMetricsRetentionDays(days) } }
                    )) {
                        Text("7 天").tag(7)
                        Text("30 天").tag(30)
                        Text("90 天").tag(90)
                        Text("1 年").tag(365)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "trash",
                    title: "删除历史指标",
                    detail: CNL10n.metricsDiagnostic(store.metricsDiagnostic)
                ) {
                    Button("清空…", role: .destructive) {
                        showsClearMetricsConfirmation = true
                    }
                }
            }
        }
    }

    private var mcpCard: some View {
        SurfaceCard(title: "只读 MCP", symbol: "terminal", tint: CNTheme.violet) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("把 CleanNest 的本机证据交给你的 AI 客户端读取")
                            .font(.subheadline.weight(.semibold))
                        Text("仅通过本机标准输入/输出运行；没有 HTTP 端口，没有删除、结束进程或修改设置的工具。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "只读", symbol: "lock.shield", style: .success)
                }

                HStack(spacing: 8) {
                    Text(mcpExecutablePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("复制路径") { copyToPasteboard(mcpExecutablePath) }
                    Button("复制配置") { copyToPasteboard(mcpConfiguration) }
                }
                .padding(10)
                .background(CNTheme.surfaceSubtle.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))

                Text("可读取：最新状态、历史趋势、内存进程、磁盘证据、清理预览和活动记录。客户端权限仍由你自己的 MCP 配置控制。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var mcpExecutablePath: String {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/CleanNestMCP", isDirectory: false)
            .path
    }

    private var mcpConfiguration: String {
        """
        {"mcpServers":{"cleannest":{"command":"\(mcpExecutablePath)"}}}
        """
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var scanningCard: some View {
        SurfaceCard(title: "扫描范围", symbol: "scope", tint: CNTheme.warning) {
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
        SurfaceCard(title: "关于 CleanNest", symbol: "leaf", tint: CNTheme.mint) {
            VStack(spacing: 0) {
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
                        Text(AppMetadata.displayVersion)
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

                Divider()
                    .padding(.vertical, 15)

                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CNTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(CNTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("软件更新")
                            .font(.subheadline.weight(.medium))
                        Text(updateStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.presentUpdateChecker()
                    } label: {
                        Text(CNL10n.string(store.appUpdateState.isChecking ? "正在检查…" : "检查更新"))
                    }
                    .disabled(store.appUpdateState.isChecking)
                    .accessibilityLabel(CNL10n.string(store.appUpdateState.isChecking ? "正在检查…" : "检查更新"))
                }
            }
        }
    }

    private var updateStatusText: String {
        switch store.appUpdateState {
        case .idle:
            return CNL10n.string("从 GitHub 获取最新正式版本；不会自动安装。")
        case .checking:
            return CNL10n.string("正在读取 GitHub 最新正式 Release…")
        case .noPublishedRelease:
            return CNL10n.string("GitHub 目前尚未发布正式版本。")
        case .updateAvailable(_, let release):
            return CNL10n.format("可更新到 %@。", release.tagName)
        case .upToDate:
            return CNL10n.string("当前已是最新正式版本。")
        case .localVersionAhead:
            return CNL10n.string("当前构建比最新正式版本更新。")
        case .failed(_, let message):
            return message
        }
    }

    private func settingsRow<Accessory: View>(
        symbol: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                settingsRowLabel(symbol: symbol, title: title, detail: detail)
                Spacer(minLength: 12)
                accessory()
            }
            VStack(alignment: .leading, spacing: 10) {
                settingsRowLabel(symbol: symbol, title: title, detail: detail)
                HStack {
                    Spacer()
                    accessory()
                }
            }
        }
        .padding(.vertical, 11)
    }

    private func settingsRowLabel(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 12) {
            CNIconTile(symbol: symbol, tint: CNTheme.accent, size: 31)
            VStack(alignment: .leading, spacing: 3) {
                Text(CNL10n.string(title)).font(.subheadline.weight(.medium))
                Text(CNL10n.string(detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func chooseEngine() {
        let panel = NSOpenPanel()
        panel.title = CNL10n.string("选择 mo 或 mole 可执行文件")
        panel.prompt = CNL10n.string("使用此引擎")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.setCustomEnginePath(url.path) }
    }

    private func chooseLocalAIModel() {
        let panel = NSOpenPanel()
        panel.title = CNL10n.string("选择 MLX 模型目录")
        panel.prompt = CNL10n.string("使用此模型")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localAIModelPathDraft = url.path
    }

    private func chooseLocalAIExecutable() {
        let panel = NSOpenPanel()
        panel.title = CNL10n.string("选择 mlx_lm.server")
        panel.prompt = CNL10n.string("使用此程序")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        localAIExecutablePathDraft = url.path
    }

    private func syncLocalAIDrafts() {
        localAIEndpointDraft = store.localAIEndpoint
        localAIServiceModelIDDraft = store.localAIServiceModelID
        localAIModelPathDraft = store.localAIModelPath
        localAIExecutablePathDraft = store.localAIExecutablePath
    }

    private func applyLocalAIDrafts() async -> Bool {
        let applied = await store.applyLocalAISettings(
            endpoint: localAIEndpointDraft,
            serviceModelID: localAIServiceModelIDDraft,
            modelPath: localAIModelPathDraft,
            executablePath: localAIExecutablePathDraft
        )
        if applied { syncLocalAIDrafts() }
        return applied
    }
}
