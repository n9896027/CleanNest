import Charts
import SwiftUI
import CleanNestCore

struct SystemStatusView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showsAllMemoryProcesses = false
    @State private var pendingMemoryTermination: PendingMemoryTermination?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "系统状态",
                    subtitle: "本机采样；不上传指标，只在你确认后结束所选进程。"
                ) {
                    Button {
                        Task { await store.refreshSystemStatus() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking || store.engine == nil)
                }

                if store.engine == nil {
                    EmptyPanel(
                        symbol: "waveform.path.ecg",
                        title: "连接引擎后查看实时状态",
                        detail: "Mole CLI 提供结构化的 CPU、内存、磁盘、电池和温度数据。可在 App 内免费安装。",
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
                            value: snapshot.diskUsedPercent,
                            detail: snapshot.diskFreeBytes.map { CNL10n.format("可用 %@", CleanNestFormatting.bytes($0)) } ?? "可用空间未知",
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

                if let temperature = snapshot.temperatureCelsius {
                    InlineBanner(
                        title: "\(snapshot.temperatureSource ?? "当前温度") \(String(format: "%.0f", temperature))°C",
                        detail: snapshot.temperatureSource == "电池温度"
                            ? "这是电池传感器的单次采样，不是 CPU 温度；CleanNest 不会只凭这个数值判断硬件故障。"
                            : "这是当前单次采样，不代表硬件故障；持续异常时再结合活动监视器判断。",
                        kind: snapshot.temperatureSource == "电池温度"
                            ? .info
                            : (temperature > 85 ? .warning : .success)
                    )
                    }
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
        let processes = showsAllMemoryProcesses
            ? store.memoryProcesses
            : Array(store.memoryProcesses.prefix(10))

        return SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("内存占用较高的应用与进程", systemImage: "list.number")
                            .font(.headline)
                        Text("按近似内存足迹排序；系统或受保护进程只展示，不会提供结束按钮。")
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

                if processes.isEmpty {
                    InlineBanner(
                        title: "还没有进程数据",
                        detail: "点击页面右上角的“刷新”，重新探测当前内存占用。",
                        kind: .info
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(processes.enumerated()), id: \.element.id) { index, process in
                            memoryProcessRow(process)
                            if index < processes.count - 1 {
                                Divider().padding(.leading, 48)
                            }
                        }
                    }

                    if store.memoryProcesses.count > 10 {
                        Button(showsAllMemoryProcesses ? "只显示前 10 项" : "显示全部 \(store.memoryProcesses.count) 项") {
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "系统维护",
                    subtitle: "每项任务独立说明影响；这里没有含糊的“一键加速”。"
                )

                InlineBanner(
                    title: "当前任务不需要管理员密码",
                    detail: "首版只开放重建快速预览、重启 Finder 和重启 Dock。涉及网络、索引或系统缓存的任务暂不自动执行。",
                    kind: .success
                )

                VStack(spacing: 12) {
                    ForEach(MaintenanceAction.allCases) { action in
                        maintenanceCard(action)
                    }
                }

                SurfaceCard(title: "后续可扩展", symbol: "slider.horizontal.3") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("维护任务使用独立动作模型，可以继续添加 Spotlight 重建、网络诊断、启动项管理等能力。")
                            .font(.subheadline)
                        Text("需要管理员权限的任务会使用 macOS 原生认证流程，不会让 App 读取或保存密码。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(CNTheme.pagePadding)
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text("执行“\(action.rawValue)”？"),
                message: Text(action.explanation),
                primaryButton: .default(Text("执行")) {
                    Task { await store.runMaintenance(action) }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private func maintenanceCard(_ action: MaintenanceAction) -> some View {
        HStack(spacing: 15) {
            Image(systemName: action.symbolName)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(CNTheme.accent)
                .frame(width: 42, height: 42)
                .background(CNTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(action.rawValue).font(.headline)
                    StatusPill(text: "可安全重试", symbol: "arrow.clockwise", style: .success)
                }
                Text(action.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("运行") { pendingAction = action }
                .disabled(store.isWorking)
        }
        .cnCard()
    }
}
