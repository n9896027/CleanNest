import Charts
import SwiftUI
import CleanNestCore

struct SystemStatusView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showsAllMemoryProcesses = false
    @State private var expandedMemoryGroupIDs = Set<String>()
    @State private var pendingMemoryTermination: PendingMemoryTermination?
    @State private var realtimeSample: NativeMonitorSample? = nil

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "系统状态",
                    subtitle: "\(store.menuBarConfiguration.refreshInterval.rawValue) 秒原生采样与长期历史彼此独立；不上传指标。"
                ) {
                    Button {
                        Task {
                            await store.refreshNativeMonitorNow()
                            if store.engine != nil {
                                await store.refreshSystemStatus()
                            }
                        }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking || !store.menuBarConfiguration.isEnabled)
                }

                nativeRealtimeCard
                systemAlertTimelineCard

                if store.engine == nil {
                    EmptyPanel(
                        symbol: "waveform.path.ecg",
                        title: "原生实时监测已可用",
                        detail: "上方 CPU、内存、网络、磁盘、GPU、温度、风扇与电池都不依赖 Mole。连接 Mole 后再补充健康评分与长期历史。",
                        actionTitle: "打开引擎设置"
                    ) {
                        store.selection = .settings
                    }
                } else if let snapshot = store.systemSnapshot {
                    HStack(alignment: .top, spacing: 14) {
                        healthCard(snapshot)
                        VStack(spacing: 14) {
                            statusSummaryRow(label: "设备", value: snapshot.host, symbol: "laptopcomputer")
                            statusSummaryRow(label: "运行时间", value: snapshot.uptime ?? "—", symbol: "clock")
                            statusSummaryRow(label: "采样时间", value: snapshot.sampledAt.formatted(date: .omitted, time: .standard), symbol: "dot.radiowaves.left.and.right")
                        }
                        .frame(maxWidth: .infinity)
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ResourceCard(
                            title: "CPU",
                            symbol: "cpu",
                            value: snapshot.cpuUsage,
                            detail: snapshot.logicalCPUCount.map { CNL10n.format("%d 个逻辑核心", $0) } ?? "核心数未知",
                            tint: CNTheme.accent
                        )
                        ResourceCard(
                            title: "内存",
                            symbol: "memorychip",
                            value: snapshot.memoryUsedPercent,
                            detail: memoryDetail(snapshot),
                            tint: memoryTint(snapshot.memoryPressureLevel)
                        )
                        ResourceCard(
                            title: "磁盘",
                            symbol: "internaldrive",
                            value: realtimeSample?.diskUsedPercent ?? snapshot.diskUsedPercent,
                            detail: (realtimeSample?.diskFreeBytes ?? snapshot.diskFreeBytes)
                                .map { CNL10n.format("可用 %@", CleanNestFormatting.bytes($0)) }
                                ?? "可用空间未知",
                            tint: CNTheme.success
                        )
                        BatteryDiagnosticCard(
                            snapshotLevel: snapshot.batteryLevel,
                            snapshotStatus: snapshot.batteryStatus,
                            probe: store.batteryProbeResult
                        )
                    }

                    metricHistoryCard
                    memoryAnalysisCard(snapshot)
                    memoryProcessesCard(snapshot)
                } else {
                    EmptyPanel(
                        symbol: "waveform.path.ecg",
                        title: "还没有状态采样",
                        detail: "点击刷新读取一次当前状态。",
                        actionTitle: "读取系统状态"
                    ) {
                        Task { await store.refreshSystemStatus() }
                    }
                }
            }
            .padding(CNTheme.pagePadding)
        }
        .onReceive(store.nativeMonitorSamplePublisher) { realtimeSample = $0 }
        .alert(item: $pendingMemoryTermination) { pending in
            if pending.force {
                return Alert(
                    title: Text("强制结束“\(processDisplayName(pending.process))”？"),
                    message: Text("该进程没有在正常请求后退出。强制结束不会给它保存状态的机会，未保存的内容可能丢失。\n\n\(pending.process.terminationImpact)"),
                    primaryButton: .destructive(Text("强制结束")) {
                        Task { await store.terminateMemoryProcess(pending.process, force: true) }
                    },
                    secondaryButton: .cancel(Text("继续等待"))
                )
            }

            return Alert(
                title: Text("退出“\(processDisplayName(pending.process))”？"),
                message: Text("CleanNest 会先发送正常退出请求；是否保存状态由所属 App 决定。\n\n\(pending.process.terminationImpact)\n\n未保存的内容可能丢失。"),
                primaryButton: .default(Text("发送退出请求")) {
                    Task { await store.terminateMemoryProcess(pending.process, force: false) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var nativeRealtimeCard: some View {
        SurfaceCard(title: "实时仪表", symbol: "menubar.rectangle", tint: CNTheme.cyan) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.nativeMonitorDiagnostic)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sampledAt = realtimeSample?.sampledAt {
                            Text("最新样本 " + sampledAt.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    StatusPill(
                        text: store.nativeMonitorIsActive ? "原生采样中" : "已停止",
                        symbol: store.nativeMonitorIsActive ? "dot.radiowaves.left.and.right" : "pause",
                        style: store.nativeMonitorIsActive ? .success : .neutral
                    )
                }

                if let sample = realtimeSample {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 195), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(MenuBarMetric.allCases) { metric in
                            realtimeMetricCell(metric, sample: sample)
                        }
                    }
                } else if store.menuBarConfiguration.isEnabled {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在等待第一个本机样本…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70)
                } else {
                    InlineBanner(
                        title: "菜单栏监测已关闭",
                        detail: "在设置中重新开启后，这里会恢复原生采样。",
                        kind: .info
                    )
                }
            }
        }
    }

    private func realtimeMetricCell(
        _ metric: MenuBarMetric,
        sample: NativeMonitorSample
    ) -> some View {
        let healthLevel = sample.healthLevel(
            for: metric,
            thresholds: store.menuBarConfiguration.alertThresholds
        )
        let assessment = sample.healthAssessment(
            for: metric,
            thresholds: store.menuBarConfiguration.alertThresholds
        )
        let tint = healthLevel.highlightColor ?? metric.tint

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: metric.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(metric.displayName)
                    .font(.caption.weight(.semibold))
                if let badgeText = healthLevel.badgeText {
                    HStack(spacing: 3) {
                        Image(systemName: healthLevel.badgeSymbol ?? "exclamationmark")
                        Text(CNL10n.string(badgeText))
                    }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Spacer()
                MiniTrend(
                    values: store.nativeMonitorHistory.compactMap { $0.value(for: metric) },
                    range: metric.normalizedGraphRange,
                    tint: tint
                )
                .frame(width: 50, height: 19)
            }
            NativeMetricReadingView(
                reading: sample.metricReading(
                    metric,
                    temperatureUnit: store.menuBarConfiguration.temperatureUnit
                ),
                font: .system(size: 17, weight: .semibold, design: .rounded)
            )
            .foregroundStyle(healthLevel.highlightColor ?? Color.primary)
            Text(sample.sourceDescription(metric))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let assessment, assessment.level != .normal {
                Text(assessment.reason)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    tint.opacity(
                        healthLevel == .normal
                            ? (sample.isAvailable(metric) ? 0.16 : 0.05)
                            : 0.48
                    ),
                    lineWidth: healthLevel == .normal ? 0.7 : 1
                )
        )
        .accessibilityElement(children: .combine)
    }

    private var metricHistoryCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("资源趋势", systemImage: "chart.xyaxis.line")
                            .font(.headline)
                        Text(CNL10n.metricsDiagnostic(store.metricsDiagnostic))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        text: store.metricsSamplingIsActive ? "持续采样" : "等待引擎",
                        symbol: store.metricsSamplingIsActive ? "dot.radiowaves.left.and.right" : "pause",
                        style: store.metricsSamplingIsActive ? .success : .neutral
                    )
                    Picker("时间范围", selection: $store.metricHistoryRange) {
                        Text("1 小时").tag(MetricHistoryRange.hour)
                        Text("24 小时").tag(MetricHistoryRange.day)
                        Text("7 天").tag(MetricHistoryRange.week)
                        Text("30 天").tag(MetricHistoryRange.month)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 290)
                    .onChange(of: store.metricHistoryRange) {
                        Task { await store.refreshMetricHistory() }
                    }
                }

                if store.metricHistory.isEmpty {
                    InlineBanner(
                        title: "等待连续样本",
                        detail: "CleanNest 每 60 秒在本机记录一次 CPU、内存与磁盘占用。首次启动后稍等片刻即可看到趋势。",
                        kind: .info
                    )
                } else {
                    Chart(store.metricHistory) { sample in
                        if let value = sample.cpuUsage {
                            LineMark(
                                x: .value(CNL10n.string("时间"), sample.sampledAt),
                                y: .value(CNL10n.string("占用"), value),
                                series: .value(CNL10n.string("指标"), "CPU")
                            )
                            .foregroundStyle(by: .value(CNL10n.string("指标"), "CPU"))
                            .interpolationMethod(.catmullRom)
                        }
                        if let value = sample.memoryUsedPercent {
                            LineMark(
                                x: .value(CNL10n.string("时间"), sample.sampledAt),
                                y: .value(CNL10n.string("占用"), value),
                                series: .value(CNL10n.string("指标"), CNL10n.string("内存"))
                            )
                            .foregroundStyle(by: .value(CNL10n.string("指标"), CNL10n.string("内存")))
                            .interpolationMethod(.catmullRom)
                        }
                        if let value = sample.diskUsedPercent {
                            LineMark(
                                x: .value(CNL10n.string("时间"), sample.sampledAt),
                                y: .value(CNL10n.string("占用"), value),
                                series: .value(CNL10n.string("指标"), CNL10n.string("磁盘"))
                            )
                            .foregroundStyle(by: .value(CNL10n.string("指标"), CNL10n.string("磁盘")))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxisLabel(CNL10n.string("占用 %"))
                    .chartLegend(position: .top, alignment: .leading, spacing: 14)
                    .frame(height: 220)
                    .accessibilityLabel(CNL10n.string("CPU、内存与磁盘历史趋势图"))

                    Text("数据仅保存在这台 Mac 的 CleanNest 数据目录中，不包含文件内容，也不会上传。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var systemAlertTimelineCard: some View {
        SurfaceCard(title: "告警时间线", symbol: "bell.and.waves.left.and.right", tint: CNTheme.warning) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text("只记录温度、电池、内存压力、磁盘余量和风扇相对负载的异常、峰值与恢复；CPU、GPU 和网络繁忙不会被当成故障。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    StatusPill(
                        text: store.systemAlertEvents.contains(where: \.isActive)
                            ? "有持续异常"
                            : "当前无异常",
                        symbol: store.systemAlertEvents.contains(where: \.isActive)
                            ? "exclamationmark"
                            : "checkmark",
                        style: store.systemAlertEvents.contains(where: \.isActive)
                            ? .warning
                            : .success
                    )
                }

                if store.systemAlertEvents.isEmpty {
                    InlineBanner(
                        title: "还没有告警记录",
                        detail: "这是正常状态。达到你在设置中保存的阈值后，这里才会开始计时并说明变色原因。",
                        kind: .success
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(store.systemAlertEvents.prefix(8).enumerated()), id: \.element.id) { index, event in
                            systemAlertRow(event)
                            if index < min(8, store.systemAlertEvents.count) - 1 {
                                Divider().padding(.leading, 45)
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(CNTheme.success)
                    Text("历史只保存在本机，不记录网络地址、访问内容或流量正文；睡眠和退出期间不会虚增持续时间。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func systemAlertRow(_ event: SystemAlertEvent) -> some View {
        let tint = event.level.highlightColor ?? event.metric.tint
        return HStack(alignment: .top, spacing: 11) {
            CNIconTile(symbol: event.metric.symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(event.metric.displayName)
                        .font(.subheadline.weight(.semibold))
                    StatusPill(
                        text: event.isActive ? "持续中" : "已恢复",
                        symbol: event.isActive ? "waveform.path" : "checkmark",
                        style: event.isActive ? event.level.badgeStyle : .success
                    )
                    .controlSize(.mini)
                }
                Text(event.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("峰值：\(event.peakDescription) · 持续 \(alertDuration(event.duration(at: realtimeSample?.sampledAt ?? Date())))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Text(event.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private func alertDuration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds.rounded()))
        if value >= 3_600 { return "\(value / 3_600) 小时 \((value % 3_600) / 60) 分" }
        if value >= 60 { return "\(value / 60) 分 \(value % 60) 秒" }
        return "\(value) 秒"
    }

    private func memoryAnalysisCard(_ snapshot: SystemSnapshot) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Label("内存解读", systemImage: "memorychip")
                        .font(.headline)
                        .foregroundStyle(CNTheme.accent)
                    Spacer()
                    if let analysis = store.memoryAnalysis {
                        StatusPill(
                            text: analysis.title,
                            symbol: memoryStatusSymbol(analysis.level),
                            style: memoryStatusStyle(analysis.level)
                        )
                    } else {
                        StatusPill(text: "等待解读", symbol: "questionmark", style: .neutral)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                    spacing: 10
                ) {
                    memoryMetric("已使用", bytes: snapshot.memoryUsedBytes)
                    memoryMetric("可用", bytes: snapshot.memoryAvailableBytes)
                    memoryMetric("系统缓存", bytes: snapshot.memoryCachedBytes)
                    memoryMetric("已压缩", bytes: snapshot.memoryCompressedBytes)
                    memoryMetric(
                        "交换空间",
                        bytes: snapshot.memorySwapUsedBytes,
                        detail: memoryTotalDetail(snapshot.memorySwapTotalBytes)
                    )
                }

                if let analysis = store.memoryAnalysis {
                    Text(CNL10n.memoryAnalysisText(analysis.detail))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)

                    if !analysis.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(analysis.notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .foregroundStyle(CNTheme.accent)
                                        .padding(.top, 1)
                                    Text(CNL10n.memoryAnalysisText(note))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } else {
                    Text("已读取内存容量，但还没有足够数据判断当前压力。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 5) {
                    Label("“已使用”较高不等于故障", systemImage: "checkmark.shield")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CNTheme.success)
                    Text("macOS 会主动使用空闲内存做缓存，需要时会自动释放。交换空间已有占用，也不等于此刻仍在频繁换页；应结合内存压力和连续采样判断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func memoryProcessesCard(_ snapshot: SystemSnapshot) -> some View {
        let allGroups = store.memoryApplicationGroups
        let groups = showsAllMemoryProcesses
            ? allGroups
            : Array(allGroups.prefix(10))

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("内存占用较高的应用", systemImage: "square.stack.3d.up")
                            .font(.headline)
                        Text("先按所属 App 汇总，再按需展开辅助进程；退出风险仍逐个确认，不提供整组强制结束。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let count = snapshot.processCount {
                        StatusPill(text: CNL10n.format("已探测 %d 个进程", count), symbol: "dot.radiowaves.left.and.right", style: .neutral)
                    }
                }

                if let message = store.memoryProcessMessage,
                   store.forceTerminationProcessID == nil {
                    InlineBanner(
                        title: store.memoryProcessMessageIsWarning ? "操作没有完成" : "进程状态已更新",
                        detail: message,
                        kind: store.memoryProcessMessageIsWarning ? .warning : .success
                    )
                }

                if groups.isEmpty {
                    InlineBanner(
                        title: "还没有进程数据",
                        detail: "点击页面右上角的“刷新”，重新探测当前内存占用。",
                        kind: .info
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            memoryApplicationGroupRow(group)
                            if index < groups.count - 1 {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }

                    if allGroups.count > 10 {
                        Button(showsAllMemoryProcesses ? "只显示前 10 个 App" : "显示全部 \(allGroups.count) 个 App") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                showsAllMemoryProcesses.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CNTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private func memoryApplicationGroupRow(_ group: MemoryApplicationGroup) -> some View {
        let isExpanded = expandedMemoryGroupIDs.contains(group.id)
        let footprint = group.physicalFootprintBytes > 0
            ? group.physicalFootprintBytes
            : group.residentBytes

        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded {
                        expandedMemoryGroupIDs.remove(group.id)
                    } else {
                        expandedMemoryGroupIDs.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "app.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CNTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(CNTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text("\(group.processes.count) 个进程"
                             + (group.protectedProcessCount > 0 ? " · \(group.protectedProcessCount) 个受保护" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Text(CleanNestFormatting.bytes(footprint))
                        .font(.subheadline.weight(.semibold))
                        .monospacedMetric()
                        .foregroundStyle(.primary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.displayName)，\(group.processes.count) 个进程，近似内存足迹 \(CleanNestFormatting.bytes(footprint))")
            .accessibilityHint(isExpanded ? "收起进程" : "展开进程并逐个查看退出风险")

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.processes.enumerated()), id: \.element.id) { index, process in
                        memoryProcessRow(process)
                            .padding(.leading, 18)
                        if index < group.processes.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
    }

    private func memoryProcessRow(_ process: MemoryProcessSnapshot) -> some View {
        let identifier = process.id
        let isTerminating = store.terminatingMemoryProcessID == identifier
        let requiresForce = store.forceTerminationProcessID == identifier

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: process.applicationName == nil ? "gearshape.2.fill" : "app.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(process.canTerminate ? CNTheme.accent : .secondary)
                    .frame(width: 34, height: 34)
                    .background(
                        (process.canTerminate ? CNTheme.accent : Color.secondary).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(processDisplayName(process))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(processIdentity(process))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(CNL10n.processPurpose(process.purpose))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(approximateFootprint(process))
                        .font(.subheadline.weight(.semibold))
                        .monospacedMetric()
                    Text(CNL10n.string("近似内存足迹"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 90, alignment: .trailing)

                memoryProcessAction(process, isTerminating: isTerminating, requiresForce: requiresForce)
                    .frame(minWidth: 104, alignment: .trailing)
            }

            if requiresForce {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(CNTheme.warning)
                        .padding(.top, 1)
                    Text(store.memoryProcessMessage ?? "进程没有在正常请求后退出。它可能正在保存数据、没有响应，或已被所属 App 重新启动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.leading, 46)
            }
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func memoryProcessAction(
        _ process: MemoryProcessSnapshot,
        isTerminating: Bool,
        requiresForce: Bool
    ) -> some View {
        if let reason = process.protectionReason ?? (process.canTerminate ? nil : "受保护进程") {
            StatusPill(text: reason, symbol: "lock.fill", style: .neutral)
                .help(CNL10n.string(reason))
        } else if isTerminating {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(requiresForce ? "正在强制结束…" : "正在请求退出…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if requiresForce {
            Button("强制结束…", role: .destructive) {
                pendingMemoryTermination = PendingMemoryTermination(process: process, force: true)
            }
            .controlSize(.small)
            .disabled(store.isWorking || store.terminatingMemoryProcessID != nil)
        } else {
            Button("退出…") {
                pendingMemoryTermination = PendingMemoryTermination(process: process, force: false)
            }
            .controlSize(.small)
            .disabled(store.isWorking || store.terminatingMemoryProcessID != nil)
        }
    }

    private func memoryMetric(_ title: String, bytes: Int64?, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CNL10n.string(title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(bytes.map(CleanNestFormatting.bytes) ?? "—")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedMetric()
            Text(CNL10n.string(detail ?? (bytes == nil ? "未能读取" : "当前采样")))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(10)
        .background(CNTheme.surfaceSubtle.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CNTheme.divider, lineWidth: 0.6))
    }

    private func memoryTotalDetail(_ total: Int64?) -> String {
        total.map { CNL10n.format("总计 %@", CleanNestFormatting.bytes($0)) } ?? "总量未能读取"
    }

    private func processDisplayName(_ process: MemoryProcessSnapshot) -> String {
        guard let applicationName = process.applicationName,
              !applicationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return process.name
        }
        return applicationName
    }

    private func processIdentity(_ process: MemoryProcessSnapshot) -> String {
        let name = processDisplayName(process)
        if name == process.name {
            return "PID \(process.pid)"
        }
        return "\(process.name) · PID \(process.pid)"
    }

    private func approximateFootprint(_ process: MemoryProcessSnapshot) -> String {
        let bytes = process.physicalFootprintBytes > 0
            ? process.physicalFootprintBytes
            : process.residentBytes
        return CleanNestFormatting.bytes(bytes)
    }

    private func memoryTint(_ level: MemoryPressureLevel) -> Color {
        switch level {
        case .normal: return CNTheme.success
        case .warning: return CNTheme.warning
        case .critical: return CNTheme.danger
        case .unknown: return CNTheme.accent
        }
    }

    private func memoryStatusStyle(_ level: MemoryPressureLevel) -> StatusPill.Style {
        switch level {
        case .normal: return .success
        case .warning: return .warning
        case .critical: return .danger
        case .unknown: return .neutral
        }
    }

    private func memoryStatusSymbol(_ level: MemoryPressureLevel) -> String {
        switch level {
        case .normal: return "checkmark"
        case .warning: return "exclamationmark"
        case .critical: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark"
        }
    }

    private func healthCard(_ snapshot: SystemSnapshot) -> some View {
        SurfaceCard {
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: CGFloat(min(100, max(0, snapshot.healthScore ?? 0))) / 100)
                        .stroke(CNTheme.success, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(snapshot.healthScore.map(String.init) ?? "—")
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                            .monospacedMetric()
                        Text("参考")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)

                VStack(alignment: .leading, spacing: 7) {
                    Text(CNL10n.string(healthSummary(snapshot.healthScore)))
                        .font(.title3.weight(.semibold))
                    Text("状态分数只是资源占用的即时参考，不等同于硬件健康诊断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    StatusPill(text: "只读检查", symbol: "lock.shield", style: .success)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func statusSummaryRow(label: String, value: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(CNTheme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(CNL10n.string(label)).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            Spacer()
        }
        .padding(13)
        .frame(maxWidth: .infinity)
        .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CNTheme.divider, lineWidth: 0.7))
    }

    private func memoryDetail(_ snapshot: SystemSnapshot) -> String {
        guard let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes else { return "容量未知" }
        return "\(CleanNestFormatting.bytes(used)) / \(CleanNestFormatting.bytes(total))"
    }

    private func healthSummary(_ score: Int?) -> String {
        guard let score else { return "状态数据不完整" }
        if score >= 80 { return "整体运行平稳" }
        if score >= 60 { return "资源占用值得留意" }
        return "当前负载较高"
    }
}

private struct PendingMemoryTermination: Identifiable {
    let id = UUID()
    let process: MemoryProcessSnapshot
    let force: Bool
}

private struct ResourceCard: View {
    let title: String
    let symbol: String
    let value: Double?
    let detail: String
    let tint: Color

    private var fraction: Double {
        min(1, max(0, (value ?? 0) / 100))
    }

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(CNL10n.string(title), systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(CleanNestFormatting.percent(value))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedMetric()
                    Text(CNL10n.string(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule().fill(tint).frame(width: max(5, proxy.size.width * fraction))
                }
            }
            .frame(height: 7)
        }
    }
}

private struct BatteryDiagnosticCard: View {
    let snapshotLevel: Double?
    let snapshotStatus: String?
    let probe: BatteryProbeResult

    private var level: Double? {
        if probe.availability == .present { return probe.level ?? snapshotLevel }
        if probe.availability == .unreadable { return snapshotLevel }
        return nil
    }

    private var title: String {
        switch probe.availability {
        case .present: return probe.status
        case .noInternalBattery: return "没有内置电池"
        case .unreadable:
            return snapshotStatus.map(CNL10n.batteryStatus) ?? "读取失败"
        }
    }

    private var detail: String {
        if probe.availability == .unreadable, snapshotLevel != nil {
            return "系统接口读取失败；当前数值来自 Mole。"
        }
        return probe.detail
    }

    private var tint: Color {
        switch probe.availability {
        case .present: return CNTheme.accent
        case .noInternalBattery: return CNTheme.success
        case .unreadable: return CNTheme.warning
        }
    }

    var body: some View {
        SurfaceCard {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("电池", systemImage: probe.availability == .noInternalBattery ? "desktopcomputer" : "battery.75percent")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(level.map { CleanNestFormatting.percent($0) } ?? "—")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedMetric()
                    Text(title)
                        .font(.caption.weight(.medium))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            if let level {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.12))
                        Capsule().fill(tint).frame(width: max(5, proxy.size.width * min(1, max(0, level / 100))))
                    }
                }
                .frame(height: 7)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("电池，\(title)，\(detail)")
    }
}

struct MaintenanceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var pendingAction: MaintenanceAction?

    private var latestMaintenanceActivity: ActivityEntry? {
        let titles = Set(MaintenanceAction.allCases.map(\.rawValue))
        return store.activities.first { titles.contains($0.title) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "系统维护",
                    subtitle: "只在出现具体异常时运行一项；执行前先看影响，执行后验证结果。"
                ) {
                    StatusPill(
                        text: CNL10n.format("%d 项本机任务", MaintenanceAction.allCases.count),
                        symbol: "checkmark.shield",
                        style: .success
                    )
                }

                scopePanel

                VStack(alignment: .leading, spacing: 12) {
                    ContentSectionHeader(
                        "选择你遇到的问题",
                        detail: "不需要全部运行，也没有一键优化",
                        symbol: "stethoscope",
                        tint: CNTheme.accent
                    )

                    SurfaceCard {
                        VStack(spacing: 0) {
                            ForEach(Array(MaintenanceAction.allCases.enumerated()), id: \.element.id) { index, action in
                                maintenanceRow(action)
                                if index < MaintenanceAction.allCases.count - 1 {
                                    Divider().padding(.leading, 53)
                                }
                            }
                        }
                    }
                }

                if let latestMaintenanceActivity {
                    latestResult(latestMaintenanceActivity)
                }
            }
            .padding(CNTheme.pagePadding)
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text("执行“\(CNL10n.string(action.rawValue))”？"),
                message: Text(CNL10n.format(
                    "适用于：%@\n\n会发生：%@\n\n安全边界：%@\n\n如果未恢复：%@",
                    CNL10n.string(action.symptom),
                    CNL10n.string(action.effect),
                    CNL10n.string(action.safetyNote),
                    CNL10n.string(action.recovery)
                )),
                primaryButton: .default(Text("确认运行")) {
                    Task { await store.runMaintenance(action) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var scopePanel: some View {
        SurfaceCard(prominence: .prominent, tint: CNTheme.mint) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    CNIconTile(symbol: "wrench.and.screwdriver.fill", tint: CNTheme.mint, size: 46)
                    scopeText
                    Spacer(minLength: 12)
                    scopeFacts
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 13) {
                        CNIconTile(symbol: "wrench.and.screwdriver.fill", tint: CNTheme.mint, size: 42)
                        scopeText
                    }
                    scopeFacts
                }
            }
        }
    }

    private var scopeText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("这不是加速器")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("只重建预览缓存，或重启出现异常的 macOS 界面服务。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeFacts: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                scopeFact("不删除文件", symbol: "trash.slash")
                scopeFact("不需要管理员密码", symbol: "person.badge.key")
                scopeFact("每次只运行一项", symbol: "1.circle")
            }
            VStack(alignment: .leading, spacing: 8) {
                scopeFact("不删除文件", symbol: "trash.slash")
                scopeFact("不需要管理员密码", symbol: "person.badge.key")
                scopeFact("每次只运行一项", symbol: "1.circle")
            }
        }
    }

    private func scopeFact(_ text: String, symbol: String) -> some View {
        Label(CNL10n.string(text), systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private func maintenanceRow(_ action: MaintenanceAction) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 13) {
                maintenanceIcon(action)
                maintenanceDetails(action)
                    .frame(minWidth: 360, maxWidth: .infinity, alignment: .leading)
                maintenanceControls(action)
                    .frame(width: 154, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    maintenanceIcon(action)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(CNL10n.string(action.rawValue))
                                .font(.headline)
                            interruptionStatus(action)
                        }
                        Text(CNL10n.string(action.symptom))
                            .font(.subheadline.weight(.medium))
                    }
                }
                maintenanceDetails(action, includesTitle: false)
                maintenanceControls(action, horizontal: true)
            }
        }
        .padding(.vertical, 13)
    }

    private func maintenanceIcon(_ action: MaintenanceAction) -> some View {
        CNIconTile(symbol: action.symbolName, tint: CNTheme.accent, size: 40)
    }

    private func maintenanceDetails(
        _ action: MaintenanceAction,
        includesTitle: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if includesTitle {
                HStack(spacing: 8) {
                    Text(CNL10n.string(action.rawValue))
                        .font(.headline)
                    interruptionStatus(action)
                }
                Text(CNL10n.string(action.symptom))
                    .font(.subheadline.weight(.medium))
            }
            maintenanceDetailLine(symbol: "arrow.triangle.2.circlepath", text: action.effect)
            maintenanceDetailLine(symbol: "checkmark.shield", text: action.safetyNote)
        }
    }

    @ViewBuilder
    private func interruptionStatus(_ action: MaintenanceAction) -> some View {
        switch action {
        case .quickLook:
            StatusPill(
                text: CNL10n.string(action.interruptionSummary),
                symbol: "checkmark.circle",
                style: .success
            )
        case .finder, .dock, .menuBar:
            StatusPill(
                text: CNL10n.string(action.interruptionSummary),
                symbol: "rectangle.2.swap",
                style: .warning
            )
        }
    }

    private func maintenanceDetailLine(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(CNTheme.accent)
                .frame(width: 14, height: 16)
            Text(CNL10n.string(text))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func maintenanceControls(
        _ action: MaintenanceAction,
        horizontal: Bool = false
    ) -> some View {
        let last = store.activities.first { $0.title == action.rawValue }
        return Group {
            if horizontal {
                HStack(spacing: 9) {
                    lastStatus(last)
                    Spacer()
                    runButton(action)
                }
            } else {
                VStack(alignment: .trailing, spacing: 8) {
                    lastStatus(last)
                    runButton(action)
                }
            }
        }
    }

    private func lastStatus(_ entry: ActivityEntry?) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let entry {
                StatusPill(
                    text: entry.outcome == .success ? "最近已完成" : "上次未完成",
                    symbol: entry.outcome.symbol,
                    style: entry.outcome == .success ? .success : .danger
                )
                Text(entry.date, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                StatusPill(text: "尚未运行", symbol: "clock", style: .neutral)
            }
        }
    }

    private func runButton(_ action: MaintenanceAction) -> some View {
        Button {
            pendingAction = action
        } label: {
            Label("运行此任务…", systemImage: "play.fill")
        }
        .buttonStyle(.bordered)
        .disabled(store.isWorking)
        .accessibilityLabel(CNL10n.format("运行 %@", action.rawValue))
    }

    private func latestResult(_ entry: ActivityEntry) -> some View {
        SurfaceCard(
            title: "最近一次维护",
            symbol: "clock.arrow.circlepath",
            prominence: .quiet,
            tint: Color.outcome(entry.outcome)
        ) {
            HStack(alignment: .top, spacing: 12) {
                CNIconTile(symbol: entry.outcome.symbol, tint: Color.outcome(entry.outcome), size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(CNL10n.string(entry.title))
                            .font(.subheadline.weight(.semibold))
                        StatusPill(
                            text: entry.outcome.rawValue,
                            symbol: nil,
                            style: entry.outcome == .success ? .success : .danger
                        )
                    }
                    Text(CNL10n.string(entry.detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("查看全部记录") {
                    store.selection = .activity
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
