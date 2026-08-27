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
    @State private var showsResetPreferencesConfirmation = false
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
                menuBarCard
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
            store.refreshLaunchAtLoginStatus()
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
        .confirmationDialog(
            "恢复安全默认设置？",
            isPresented: $showsResetPreferencesConfirmation,
            titleVisibility: .visible
        ) {
            Button("恢复默认设置", role: .destructive) {
                Task {
                    await store.resetPreferencesToSafeDefaults()
                    syncLocalAIDrafts()
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("会关闭由 CleanNest 启动的本机模型并重置引擎路径、模型连接、扫描开关和指标保留期限；不会清除活动、扫描结果、学习规则、历史指标或 macOS 授权。")
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

    private var menuBarCard: some View {
        SurfaceCard(
            title: "菜单栏实时监测",
            symbol: "menubar.rectangle",
            prominence: .prominent,
            tint: CNTheme.cyan
        ) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("在其他 App 里也能直接看到这台 Mac 的负载")
                            .font(.subheadline.weight(.semibold))
                        Text(store.nativeMonitorDiagnostic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    if store.nativeMonitorIsActive {
                        StatusPill(
                            text: "\(store.menuBarConfiguration.refreshInterval.rawValue) 秒刷新",
                            symbol: "dot.radiowaves.left.and.right",
                            style: .success
                        )
                    }
                    Toggle("", isOn: Binding(
                        get: { store.menuBarConfiguration.isEnabled },
                        set: { store.setMenuBarMonitoringEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("启用菜单栏实时监测")
                }

                Divider()

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 235), spacing: 12, alignment: .top)],
                    spacing: 12
                ) {
                    menuBarChoice(
                        title: "排版",
                        detail: "双层紧凑会把数值和短标签叠放，宽度接近 State。"
                    ) {
                        Picker("", selection: Binding(
                            get: { store.menuBarConfiguration.presentationMode },
                            set: { store.setMenuBarPresentationMode($0) }
                        )) {
                            Text("双层紧凑").tag(MenuBarPresentationMode.compact)
                            Text("展开文字").tag(MenuBarPresentationMode.separate)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    menuBarChoice(title: "刷新频率", detail: "越快越灵敏，也会略增加后台开销。") {
                        Picker("", selection: Binding(
                            get: { store.menuBarConfiguration.refreshInterval },
                            set: { store.setMenuBarRefreshInterval($0) }
                        )) {
                            ForEach(MenuBarRefreshInterval.allCases, id: \.self) { interval in
                                Text("\(interval.rawValue) 秒").tag(interval)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    menuBarChoice(title: "温度单位", detail: "只改变显示，不改变传感器原始值。") {
                        Picker("", selection: Binding(
                            get: { store.menuBarConfiguration.temperatureUnit },
                            set: { store.setMenuBarTemperatureUnit($0) }
                        )) {
                            Text("摄氏 °C").tag(MenuBarTemperatureUnit.celsius)
                            Text("华氏 °F").tag(MenuBarTemperatureUnit.fahrenheit)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                    }

                    menuBarChoice(title: "网络口径", detail: networkModeDetail) {
                        Picker("", selection: Binding(
                            get: { store.menuBarConfiguration.networkMode },
                            set: { store.setMenuBarNetworkMode($0) }
                        )) {
                            Text("物理网卡合计").tag(MenuBarNetworkMode.physicalAggregate)
                            Text("系统主接口").tag(MenuBarNetworkMode.automatic)
                            Text("手动指定").tag(MenuBarNetworkMode.specific)
                        }
                        .labelsHidden()
                    }
                }
                .disabled(!store.menuBarConfiguration.isEnabled)

                if store.menuBarConfiguration.networkMode == .specific {
                    HStack(spacing: 10) {
                        Label("选择网络接口", systemImage: "network")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Picker("", selection: Binding(
                            get: {
                                store.menuBarConfiguration.selectedNetworkInterface
                                    ?? store.nativeMonitorSample?.availableNetworkInterfaces.first
                                    ?? ""
                            },
                            set: { store.setMenuBarNetworkInterface($0.isEmpty ? nil : $0) }
                        )) {
                            if store.nativeMonitorSample?.availableNetworkInterfaces.isEmpty != false {
                                Text("未找到活动接口").tag("")
                            }
                            ForEach(store.nativeMonitorSample?.availableNetworkInterfaces ?? [], id: \.self) {
                                Text($0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 180)
                    }
                    .padding(12)
                    .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 13))
                }

                InlineBanner(
                    title: "菜单栏空间检查",
                    detail: store.menuBarVisibilityDiagnostic,
                    kind: store.menuBarVisibilityDiagnostic.contains("隐藏") ? .warning : .success
                )

                InlineBanner(
                    title: "异常状态会自动高亮",
                    detail: "橙色与 ! 表示需要留意，红色与 !! 表示严重。判定结合 macOS 热状态、CPU/电池温度、内存压力、磁盘容量、低电量和风扇相对转速；CPU、GPU 或网络繁忙本身不会被当成故障。",
                    kind: .info
                )

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230), spacing: 10, alignment: .top)],
                    spacing: 10
                ) {
                    ForEach(MenuBarMetric.allCases) { metric in
                        menuBarMetricTile(metric)
                    }
                }
                .disabled(!store.menuBarConfiguration.isEnabled)
                .opacity(store.menuBarConfiguration.isEnabled ? 1 : 0.55)

                Divider()

                VStack(spacing: 0) {
                    settingsRow(
                        symbol: "person.badge.clock",
                        title: "登录后常驻菜单栏",
                        detail: store.launchAtLoginDiagnostic
                    ) {
                        HStack(spacing: 8) {
                            if store.launchAtLoginRequiresApproval {
                                Button("在系统设置中允许") { store.openLoginItemsSettings() }
                            }
                            Toggle("", isOn: Binding(
                                get: { store.launchAtLoginEnabled },
                                set: { store.setLaunchAtLoginEnabled($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .accessibilityLabel("登录后常驻菜单栏")
                        }
                    }
                    Divider().padding(.leading, 43)
                    settingsRow(
                        symbol: "keyboard",
                        title: "全局快捷键",
                        detail: store.globalHotKeyDiagnostic
                    ) {
                        Toggle("", isOn: Binding(
                            get: { store.menuBarConfiguration.globalHotKeyEnabled },
                            set: { store.setMenuBarGlobalHotKeyEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("启用全局快捷键")
                    }
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(CNTheme.success)
                        .padding(.top, 1)
                    Text("指标按你选定的频率在本机读取，不保存网络地址，不上传；退出 CleanNest 后采样立即停止。温度、GPU 和风扇取决于当前硬件是否提供可读计数；CleanNest 不控制风扇，也不要求管理员密码。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("立即刷新") {
                        Task { await store.refreshNativeMonitorNow() }
                    }
                    .disabled(!store.menuBarConfiguration.isEnabled)
                }
            }
        }
    }

    @ViewBuilder
    private func menuBarChoice<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 13))
    }

    private var networkModeDetail: String {
        switch store.menuBarConfiguration.networkMode {
        case .physicalAggregate:
            return "合计 en 系列物理网卡，避免把 VPN 隧道重复计数。"
        case .automatic:
            return "跟随 macOS 当前主路由，开启 VPN 时可能显示 utun。"
        case .specific:
            return "只计算你指定的一个活动接口。"
        }
    }

    private func menuBarMetricTile(_ metric: MenuBarMetric) -> some View {
        let preference = store.menuBarConfiguration.preference(for: metric)
        let index = store.menuBarConfiguration.metrics.firstIndex(where: { $0.metric == metric }) ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CNIconTile(symbol: metric.symbol, tint: metric.tint, size: 32)
                Text(metric.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                VStack(spacing: 1) {
                    Button { store.moveMenuBarMetric(metric, by: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)
                    .accessibilityLabel("向前移动" + metric.displayName)
                    Button { store.moveMenuBarMetric(metric, by: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= store.menuBarConfiguration.metrics.count - 1)
                    .accessibilityLabel("向后移动" + metric.displayName)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                Toggle("", isOn: Binding(
                    get: { preference.isEnabled },
                    set: { store.setMenuBarMetricEnabled($0, metric: metric) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("在菜单栏显示" + metric.displayName)
            }

            Text(menuBarMetricAvailability(metric))
                .font(.caption2)
                .foregroundStyle(menuBarMetricIsAvailable(metric) ? CNTheme.success : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("显示方式", selection: Binding(
                get: { preference.style },
                set: { store.setMenuBarMetricStyle($0, metric: metric) }
            )) {
                Text("数值").tag(MenuBarMetricStyle.text)
                Text("曲线").tag(MenuBarMetricStyle.graph)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!preference.isEnabled)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(metric.tint.opacity(preference.isEnabled ? 0.20 : 0.07), lineWidth: 0.7)
        )
    }

    private func menuBarMetricIsAvailable(_ metric: MenuBarMetric) -> Bool {
        store.nativeMonitorSample?.isAvailable(metric) == true
    }

    private func menuBarMetricAvailability(_ metric: MenuBarMetric) -> String {
        guard let sample = store.nativeMonitorSample else { return "等待首个样本" }
        if metric == .fan, sample.fanCount == 0 { return "本机为无风扇设计" }
        guard sample.isAvailable(metric) else { return "当前硬件未返回有效值" }
        return sample.detailedValue(metric)
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
                                "oMLX 调用必须使用 /v1/models 返回的短名；下方模型与程序只用于 CleanNest 自己启动 oMLX 或 MLX-LM。",
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
                                TextField("omlx 或 mlx_lm.server 可执行文件", text: $localAIExecutablePathDraft)
                                    .textFieldStyle(.roundedBorder)
                                    .lineLimit(1)
                                Button("选择…") { chooseLocalAIExecutable() }
                                if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/omlx") {
                                    Button("使用 oMLX") {
                                        localAIExecutablePathDraft = "/opt/homebrew/bin/omlx"
                                    }
                                }
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

                localAIWorkbench

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
                    Button("打开运行中心") { store.selection = .models }
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
                            Task { await store.stopOwnedLocalModelRuntime() }
                        }
                        .disabled(store.localAIServiceState.isBusy)
                    } else if store.primaryLocalModelRuntime?.supervisor?.canDisableAndStop == true {
                        Button("管理自动重启…") {
                            store.selection = .models
                        }
                    } else if store.primaryLocalModelRuntime?.supervisor?.canEnable == true {
                        Button("重新启用守护…") {
                            store.selection = .models
                        }
                    } else if store.primaryLocalModelRuntime?.canRequestExternalStop == true {
                        Button("管理外部服务…") {
                            store.selection = .models
                        }
                    } else if store.localAIEnabled && (!store.localAIIsReady || localAIDraftIsDirty) {
                        Button(CNL10n.string(localAIModelSelectionChanged ? "切换并启动" : "启动所选模型")) {
                            Task {
                                if await applyLocalAIDrafts(), !store.localAIIsReady {
                                    await store.startConfiguredLocalModelRuntime()
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

    private var localAIWorkbench: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("模型工作台", systemImage: "gauge.with.dots.needle.67percent")
                        .font(.subheadline.weight(.semibold))
                    Text("只对当前短 ID 发出一个“OK”最小请求；不发送扫描或文件元数据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if store.localAIBenchmarkPhase.isRunning {
                    ProgressView().controlSize(.small)
                }
                Button(store.localAIBenchmarkResult == nil ? "运行最小测速" : "重新测速") {
                    Task { await store.runLocalAIBenchmark() }
                }
                .disabled(!store.localAIIsReady || store.localAIBenchmarkPhase.isRunning || localAIDraftIsDirty)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    modelFact(
                        "健康检查",
                        store.localAIProbeLatencyMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—",
                        store.localAIIsReady ? "回环服务可达" : "等待连接"
                    )
                    modelFact(
                        "首字延迟",
                        store.localAIBenchmarkResult.map { "\(Int($0.firstTokenMilliseconds.rounded())) ms" } ?? "—",
                        "真实流式首个输出"
                    )
                    modelFact(
                        "完整响应",
                        benchmarkTotalValue,
                        benchmarkThroughputDetail
                    )
                }
                VStack(spacing: 10) {
                    modelFact("健康检查", store.localAIProbeLatencyMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—", store.localAIIsReady ? "回环服务可达" : "等待连接")
                    modelFact("首字延迟", store.localAIBenchmarkResult.map { "\(Int($0.firstTokenMilliseconds.rounded())) ms" } ?? "—", "真实流式首个输出")
                    modelFact("完整响应", benchmarkTotalValue, benchmarkThroughputDetail)
                }
            }

            if let model = selectedLocalAIModel {
                Label(modelMemoryGuidance(model), systemImage: "memorychip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch store.localAIBenchmarkPhase {
            case .failed(let detail):
                InlineBanner(
                    title: "最小推理测速未完成",
                    detail: detail,
                    kind: .warning
                )
            case .completed:
                if let result = store.localAIBenchmarkResult {
                    Text("本次实测对象：\(result.modelID)。结果只代表当前机器、当前负载和这次极短输出，不等同于长文本吞吐。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            case .idle, .running:
                EmptyView()
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [CNTheme.violet.opacity(0.12), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(CNTheme.violet.opacity(0.16), lineWidth: 0.7)
        )
    }

    private func modelFact(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedMetric()
            Text(detail).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var benchmarkTotalValue: String {
        store.localAIBenchmarkResult.map { "\(Int($0.totalMilliseconds.rounded())) ms" } ?? "—"
    }

    private var benchmarkThroughputDetail: String {
        guard let result = store.localAIBenchmarkResult else { return "等待用户主动测速" }
        if let rate = result.tokensPerSecond {
            return String(format: "%.1f token/s · %d token", rate, result.outputTokens ?? 0)
        }
        return "\(result.outputCharacters) 个输出字符"
    }

    private func modelMemoryGuidance(_ model: LocalModelDescriptor) -> String {
        let physical = store.systemSnapshot?.memoryTotalBytes
            ?? Int64(clamping: ProcessInfo.processInfo.physicalMemory)
        guard model.weightBytes > 0, physical > 0 else {
            return "未取得完整权重或物理内存数据；是否可运行仍以实际载入结果为准。"
        }
        let ratio = Double(model.weightBytes) / Double(physical)
        let verdict: String
        if ratio <= 0.55 {
            verdict = "权重仍为系统、KV 缓存和其他 App 留有较明显空间"
        } else if ratio <= 0.75 {
            verdict = "可用余量有限，长上下文或同时运行多个重型 App 时应观察内存压力"
        } else {
            verdict = "权重已接近本机物理内存，实际载入和长上下文可能出现明显压力"
        }
        return "模型权重约 \(CleanNestFormatting.bytes(model.weightBytes))，本机物理内存 \(CleanNestFormatting.bytes(physical))：\(verdict)。这不是峰值内存承诺。"
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
        SurfaceCard(title: "关于 CleanNest", brandMark: true, tint: CNTheme.mint) {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    CNNestMark(size: 58)
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

                Divider()
                    .padding(.vertical, 15)

                HStack(spacing: 12) {
                    CNIconTile(symbol: "arrow.counterclockwise", tint: CNTheme.warning, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("恢复安全默认设置")
                            .font(.subheadline.weight(.medium))
                        Text("只重置偏好；活动、学习、扫描索引、历史指标和系统授权分别保留。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("恢复…", role: .destructive) {
                        showsResetPreferencesConfirmation = true
                    }
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
        panel.title = CNL10n.string("选择 oMLX 或 mlx_lm.server")
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
