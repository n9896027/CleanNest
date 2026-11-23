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
    @State private var localAIAdvancedExpanded = false
    @State private var alertThresholdsExpanded = false
    @State private var nativeMonitorSample: NativeMonitorSample? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "设置",
                    subtitle: ""
                )
                HStack(alignment: .top, spacing: 20) {
                    sectionNavigation.frame(width: 148)
                    Divider()
                    ScrollView {
                        selectedSectionContent
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 16)
                    }
                }
        }
        .padding(CNTheme.pagePadding)
        .onAppear {
            syncLocalAIDrafts()
            store.refreshLaunchAtLoginStatus()
            localAIAdvancedExpanded = !store.localAIIsReady
        }
        .task(id: store.selectedSettingsSection) {
            if store.selectedSettingsSection == .localAI {
                syncLocalAIDrafts()
            }
            await store.activateSettingsSection(store.selectedSettingsSection)
        }
        .onChange(of: localAIEndpointDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIServiceModelIDDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIModelPathDraft) { store.clearLocalAIConfigurationError() }
        .onChange(of: localAIExecutablePathDraft) { store.clearLocalAIConfigurationError() }
        .onReceive(store.nativeMonitorSamplePublisher) { nativeMonitorSample = $0 }
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
            Text("会关闭由 CleanNest 启动的本机模型并重置模型连接、扫描开关和指标保留期限；不会清除活动、扫描结果、学习规则、历史指标或 macOS 授权。")
        }
    }

    private var sectionNavigation: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(CleanNestSettingsSection.allCases) { section in
                    Button {
                        store.selectedSettingsSection = section
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: section.symbol).frame(width: 20)
                            Text(CNL10n.string(section.title)).font(.subheadline)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(store.selectedSettingsSection == section ? CNTheme.accent : Color.primary)
                        .padding(.horizontal, 9).padding(.vertical, 11)
                        .background(store.selectedSettingsSection == section ? CNTheme.accent.opacity(0.10) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(store.selectedSettingsSection == section ? CNL10n.string("已选中") : "")
                }
            }
        }
        .accessibilityLabel("设置分栏")
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch store.selectedSettingsSection {
            case .general:
                engineCard
                CNDetailSection(title: "连接状态", summary: "引擎、AI 与文件访问", symbol: "checkmark.shield") {
                    readinessDeck
                }
            case .menuBar:
                menuBarCard
            case .scanAndPrivacy:
                permissionCard
                scanningCard
            case .localAI:
                localAICard
            case .historyAndStorage:
                metricsCard
                activityStorageCard
            case .advanced:
                mcpCard
            case .about:
                aboutCard
            }
        }
        .id(store.selectedSettingsSection)
    }

    private var readinessDeck: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                readinessItem(
                    title: "本地引擎",
                    status: store.builtInEngineStatusText,
                    detail: store.builtInEngineDetailText,
                    symbol: "gearshape.2",
                    tint: CNTheme.success,
                    section: .general
                )
                readinessItem(
                    title: "本机 AI 分析",
                    status: store.localAIIsReady ? "模型已连接" : "等待设置",
                    detail: store.localAIIsReady ? store.localAIModelDisplayName : "普通扫描仍可继续使用。",
                    symbol: "brain.head.profile",
                    tint: store.localAIIsReady ? CNTheme.cyan : CNTheme.warning,
                    section: .localAI
                )
                readinessItem(
                    title: "文件访问",
                    status: fullDiskAccessStatusText,
                    detail: "由 CleanNest 自身实测",
                    symbol: "lock.shield",
                    tint: store.fullDiskAccessProbeResult == .accessible ? CNTheme.success : CNTheme.warning,
                    section: .scanAndPrivacy
                )
            }
            VStack(spacing: 10) {
                readinessItem(title: "本地引擎", status: store.builtInEngineStatusText, detail: store.builtInEngineDetailText, symbol: "gearshape.2", tint: CNTheme.success, section: .general)
                readinessItem(title: "本机 AI 分析", status: store.localAIIsReady ? "模型已连接" : "等待设置", detail: store.localAIIsReady ? store.localAIModelDisplayName : "普通扫描仍可继续使用。", symbol: "brain.head.profile", tint: store.localAIIsReady ? CNTheme.cyan : CNTheme.warning, section: .localAI)
                readinessItem(title: "文件访问", status: fullDiskAccessStatusText, detail: "由 CleanNest 自身实测", symbol: "lock.shield", tint: store.fullDiskAccessProbeResult == .accessible ? CNTheme.success : CNTheme.warning, section: .scanAndPrivacy)
            }
        }
    }

    private func readinessItem(
        title: String,
        status: String,
        detail: String,
        symbol: String,
        tint: Color,
        section: CleanNestSettingsSection
    ) -> some View {
        Button {
            store.selectedSettingsSection = section
        } label: {
            HStack(spacing: 12) {
                CNIconTile(symbol: symbol, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(CNL10n.string(title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CNL10n.string(status))
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(CNL10n.string(detail))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.085), lineWidth: 0.65)
        )
        .accessibilityLabel(CNL10n.format("%@：%@。%@", title, status, detail))
        .accessibilityHint("打开" + section.title + "设置")
    }

    private var engineCard: some View {
        SurfaceCard(title: "内置原生引擎", symbol: "gearshape.2", tint: CNTheme.cyan) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Circle()
                        .fill(CNTheme.success)
                        .frame(width: 9, height: 9)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.builtInEngineDisplayName)
                            .font(.subheadline.weight(.semibold))
                        Text(store.builtInEngineDetailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: store.builtInEngineStatusText, symbol: "checkmark", style: .success)
                }

                Divider()

                Text("清理、磁盘、系统数据、Agent 与系统状态均由随 App 安装的原生组件完成，不需要下载额外引擎。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                            text: CNL10n.format("%@ 秒刷新", String(describing: store.menuBarConfiguration.refreshInterval.rawValue)),
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
                                Text(CNL10n.format("%d 秒", interval.rawValue)).tag(interval)
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
                                    ?? nativeMonitorSample?.availableNetworkInterfaces.first
                                    ?? ""
                            },
                            set: { store.setMenuBarNetworkInterface($0.isEmpty ? nil : $0) }
                        )) {
                            if nativeMonitorSample?.availableNetworkInterfaces.isEmpty != false {
                                Text("未找到活动接口").tag("")
                            }
                            ForEach(nativeMonitorSample?.availableNetworkInterfaces ?? [], id: \.self) {
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
                    kind: store.menuBarVisibilityDiagnostic.contains("隐藏")
                        || store.menuBarVisibilityDiagnostic.contains("收进")
                        ? .warning
                        : .success
                )

                InlineBanner(
                    title: "异常状态会自动高亮",
                    detail: "橙色与 ! 表示需要留意，红色与 !! 表示严重。判定结合 macOS 热状态、CPU/电池温度、内存压力、磁盘容量、低电量和风扇相对转速；CPU、GPU 或网络繁忙本身不会被当成故障。",
                    kind: .info
                )

                alertThresholdSettings

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

    private var alertThresholdSettings: some View {
        DisclosureGroup(isExpanded: $alertThresholdsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 10, alignment: .top)],
                    spacing: 10
                ) {
                    thresholdPair(
                        title: "CPU 温度",
                        detail: "传感器值；macOS 热状态仍可独立触发。",
                        warning: alertThresholdBinding(\.cpuTemperatureWarningCelsius),
                        critical: alertThresholdBinding(\.cpuTemperatureCriticalCelsius),
                        range: 60...110,
                        suffix: "°C"
                    )
                    thresholdPair(
                        title: "电池温度",
                        detail: "只在硬件返回电池传感器时生效。",
                        warning: alertThresholdBinding(\.batteryTemperatureWarningCelsius),
                        critical: alertThresholdBinding(\.batteryTemperatureCriticalCelsius),
                        range: 30...60,
                        suffix: "°C"
                    )
                    thresholdPair(
                        title: "磁盘剩余",
                        detail: "剩余比例低于阈值时提醒。",
                        warning: alertThresholdBinding(\.diskFreeWarningPercent),
                        critical: alertThresholdBinding(\.diskFreeCriticalPercent),
                        range: 1...30,
                        suffix: "%"
                    )
                    thresholdPair(
                        title: "电池余量",
                        detail: "连接电源或充电时不告警。",
                        warning: alertThresholdBinding(\.batteryLowWarningPercent),
                        critical: alertThresholdBinding(\.batteryLowCriticalPercent),
                        range: 2...40,
                        suffix: "%"
                    )
                    singleThreshold(
                        title: "风扇相对负载",
                        detail: "按该机型报告的最大转速比例，不使用通用 RPM。",
                        value: alertThresholdBinding(\.fanLoadWarningPercent),
                        range: 60...100,
                        suffix: "%"
                    )
                    VStack(alignment: .leading, spacing: 8) {
                        Text("内存压力")
                            .font(.caption.weight(.semibold))
                        Text("macOS 只提供正常、警告、严重等级，不伪造百分比阈值。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Toggle("警告等级就提醒", isOn: Binding(
                            get: { store.menuBarConfiguration.alertThresholds.memoryPressureWarningEnabled },
                            set: { value in
                                store.updateNativeAlertThresholds {
                                    $0.memoryPressureWarningEnabled = value
                                }
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
                }

                HStack {
                    Text("菜单栏、弹出面板、系统状态页和告警时间线共用这一份设置。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("恢复保守预设") { store.resetNativeAlertThresholds() }
                        .controlSize(.small)
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 10) {
                CNIconTile(symbol: "gauge.with.dots.needle.67percent", tint: CNTheme.warning, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("异常阈值")
                        .font(.subheadline.weight(.semibold))
                    Text("保守预设可调整；每次变色都能回到同一条规则。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(CNTheme.warning.opacity(0.18), lineWidth: 0.7)
        )
    }

    private func alertThresholdBinding(
        _ keyPath: WritableKeyPath<NativeAlertThresholds, Double>
    ) -> Binding<Double> {
        Binding(
            get: { store.menuBarConfiguration.alertThresholds[keyPath: keyPath] },
            set: { value in
                store.updateNativeAlertThresholds { $0[keyPath: keyPath] = value }
            }
        )
    }

    private func thresholdPair(
        title: String,
        detail: String,
        warning: Binding<Double>,
        critical: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Stepper(value: warning, in: range, step: 1) {
                    Text(CNL10n.format("提醒 %d%@", Int(warning.wrappedValue.rounded()), suffix))
                        .font(.caption.monospacedDigit())
                }
                Stepper(value: critical, in: range, step: 1) {
                    Text(CNL10n.format("严重 %d%@", Int(critical.wrappedValue.rounded()), suffix))
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
    }

    private func singleThreshold(
        title: String,
        detail: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.semibold))
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Stepper(value: value, in: range, step: 1) {
                Text(CNL10n.format("提醒 %d%@", Int(value.wrappedValue.rounded()), suffix))
                    .font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
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
        nativeMonitorSample?.isAvailable(metric) == true
    }

    private func menuBarMetricAvailability(_ metric: MenuBarMetric) -> String {
        guard let sample = nativeMonitorSample else { return "等待首个样本" }
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
            return "CleanNest 正在由自身做一次轻量访问测试，不会启动任何外部引擎或递归扫描。"
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

                InlineBanner(
                    title: "启停与运行诊断已经归到本地模型中心",
                    detail: "设置页只保存 CleanNest 要连接的回环地址、API 短名和自启程序；启动、停止、守护、端口与客户端实连请在运行中心处理。",
                    kind: .info
                )

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
                        .buttonStyle(.borderedProminent)
                    Button("诊断详情") { store.showLocalAIDiagnostic() }
                    Button("仅保存并检测") {
                        Task {
                            _ = await applyLocalAIDrafts()
                        }
                    }
                    .accessibilityIdentifier("localAI.saveAndProbe")
                    .disabled(!store.localAIEnabled || store.localAIServiceState.isBusy)
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
        case .ready: return CNL10n.format("%@ 已连接", String(describing: store.localAIModelDisplayName))
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

    private var activityStorageCard: some View {
        SurfaceCard(title: "活动与累计成果", symbol: "clock.arrow.circlepath", tint: CNTheme.mint) {
            VStack(spacing: 0) {
                settingsRow(
                    symbol: "list.bullet.rectangle",
                    title: "活动明细",
                    detail: CNL10n.format("保留最近 %@ 条，可搜索、筛选、导出或单独清空。", String(describing: store.activities.count))
                ) {
                    Button("管理明细") { store.selection = .activity }
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "chart.bar.xaxis",
                    title: "累计成果",
                    detail: CNL10n.format("已处理 %@；清空活动明细不会让这些计数归零。", String(describing: CleanNestFormatting.bytes(store.activityLifetimeTotals.processedBytes)))
                ) {
                    StatusPill(text: "独立保存", symbol: "checkmark", style: .success)
                }
                Divider().padding(.leading, 43)
                settingsRow(
                    symbol: "folder",
                    title: "本机存储边界",
                    detail: "活动明细、累计成果与历史指标分别保存；删除其中一种不会连带删除另外两种。"
                ) {
                    StatusPill(text: "只在本机", symbol: "lock.shield", style: .success)
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
                        Text("独立的原生 macOS 清理与系统维护客户端。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("内置原生引擎，无需安装 Homebrew 或任何外部清理引擎。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

private struct SettingsSectionTab: View {
    let section: CleanNestSettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(section.title)
                    .font(.caption.weight(.semibold))
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(isSelected ? section.tint : Color.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(tabBackground, in: Capsule())
        .overlay(Capsule().stroke(tabBorder, lineWidth: 0.7))
        .accessibilityLabel(section.title + "设置")
        .accessibilityValue(isSelected ? "当前分栏" : "未选中")
        .accessibilityHint("仅显示" + section.title + "设置")
    }

    private var tabBackground: Color {
        isSelected ? section.tint.opacity(0.14) : Color.primary.opacity(0.045)
    }

    private var tabBorder: Color {
        isSelected ? section.tint.opacity(0.30) : Color.white.opacity(0.07)
    }
}

private extension CleanNestSettingsSection {
    var title: String {
        switch self {
        case .general: return "常规"
        case .menuBar: return "菜单栏"
        case .scanAndPrivacy: return "扫描与隐私"
        case .localAI: return "本机 AI"
        case .historyAndStorage: return "历史与存储"
        case .advanced: return "高级"
        case .about: return "关于"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "内置原生引擎开箱即用；普通使用不需要终端。"
        case .menuBar: return "控制常驻指标、排版、刷新频率、登录启动和快捷键。"
        case .scanAndPrivacy: return "明确扫描范围、完全磁盘访问实测与不可关闭的安全保护。"
        case .localAI: return "保存回环连接和模型短名；日常启停回到本地模型运行中心。"
        case .historyAndStorage: return "分别管理指标、活动明细和不会随明细清空的累计成果。"
        case .advanced: return "面向 AI 客户端的只读 MCP 与可审计集成边界。"
        case .about: return "版本、更新、开源归属和恢复安全默认设置。"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .menuBar: return "menubar.rectangle"
        case .scanAndPrivacy: return "lock.shield"
        case .localAI: return "brain.head.profile"
        case .historyAndStorage: return "externaldrive.badge.clock"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general: return CNTheme.cyan
        case .menuBar: return CNTheme.accent
        case .scanAndPrivacy: return CNTheme.success
        case .localAI: return CNTheme.violet
        case .historyAndStorage: return CNTheme.mint
        case .advanced: return CNTheme.warning
        case .about: return CNTheme.mint
        }
    }
}
