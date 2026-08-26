import SwiftUI
import CleanNestCore

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    private enum FocusAction {
        case scanCleanup
        case openCleanup
        case openSystemStatus
    }

    private struct FocusState {
        let title: String
        let detail: String
        let actionTitle: String
        let action: FocusAction
        let symbol: String
        let tint: Color
        let pillText: String
        let pillStyle: StatusPill.Style
        let safetyHint: String
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "总览",
                    subtitle: "查看这台 Mac 当前状态，并从一项明确任务开始。"
                ) {
                    StatusPill(
                        text: store.demoMode ? "演示数据" : (store.engine == nil ? "部分功能待设置" : "本地运行"),
                        symbol: store.demoMode ? "sparkles" : (store.engine == nil ? "exclamationmark.triangle" : "lock.shield"),
                        style: store.demoMode || store.engine == nil ? .warning : .success
                    )
                }

                if store.engine == nil {
                    InlineBanner(
                        title: "连接开源清理引擎",
                        detail: "系统健康评估与部分磁盘分析需要 Mole CLI；清理扫描、App 卸载和原生实时状态仍可使用。",
                        kind: .warning,
                        actionTitle: "去设置"
                    ) {
                        store.selection = .settings
                    }
                }

                currentStatePanel
                commonTasks
                recentResults
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
    }

    private var usedBytes: Int64 {
        max(0, store.diskTotalBytes - store.diskFreeBytes)
    }

    private var diskUsedFraction: Double? {
        guard store.diskTotalBytes > 0 else { return nil }
        return min(1, max(0, Double(usedBytes) / Double(store.diskTotalBytes)))
    }

    private var focusState: FocusState {
        if store.nativeMonitorSample?.memoryPressureLevel == .critical {
            return FocusState(
                title: "内存压力较高",
                detail: "macOS 已报告严重内存压力。先查看占用进程，再决定是否退出。",
                actionTitle: "查看内存进程",
                action: .openSystemStatus,
                symbol: "memorychip.fill",
                tint: CNTheme.danger,
                pillText: "需要处理",
                pillStyle: .danger,
                safetyHint: "只读查看，不会自动结束进程"
            )
        }

        if let diskUsedFraction, diskUsedFraction >= 0.90 {
            return FocusState(
                title: "可用空间偏低",
                detail: CNL10n.format(
                    "启动磁盘只剩 %@（%@ 已使用）。建议先扫描，再逐项确认。",
                    CleanNestFormatting.bytes(store.diskFreeBytes),
                    CleanNestFormatting.percent(diskUsedFraction * 100)
                ),
                actionTitle: store.cleanupHasScanned ? "查看清理清单" : "扫描可清理内容",
                action: store.cleanupHasScanned ? .openCleanup : .scanCleanup,
                symbol: "internaldrive.fill",
                tint: CNTheme.warning,
                pillText: "需要处理",
                pillStyle: .warning,
                safetyHint: "扫描与预览不会删除文件"
            )
        }

        if store.nativeMonitorSample?.memoryPressureLevel == .warning {
            return FocusState(
                title: "内存压力正在升高",
                detail: "macOS 已报告内存压力警告。查看连续采样和占用进程，再决定是否退出。",
                actionTitle: "查看内存进程",
                action: .openSystemStatus,
                symbol: "memorychip",
                tint: CNTheme.warning,
                pillText: "建议查看",
                pillStyle: .warning,
                safetyHint: "只读查看，不会自动结束进程"
            )
        }

        if store.cleanupHasScanned, !store.cleanupCandidates.isEmpty {
            return FocusState(
                title: "扫描结果等待确认",
                detail: CNL10n.format(
                    "发现 %d 项内容，合计 %@；其中 %d 项已按低风险规则预选。",
                    store.cleanupCandidates.count,
                    CleanNestFormatting.bytes(store.cleanupPotentialBytes),
                    store.selectedCleanupCount
                ),
                actionTitle: "查看清理清单",
                action: .openCleanup,
                symbol: "checklist",
                tint: CNTheme.accent,
                pillText: "等待你决定",
                pillStyle: .neutral,
                safetyHint: "移到废纸篓前仍需要你确认"
            )
        }

        if !store.cleanupHasScanned {
            return FocusState(
                title: "还没有清理清单",
                detail: "先扫描缓存、下载中的安装包与归档，以及按设置启用的媒体与重复文件。",
                actionTitle: "扫描可清理内容",
                action: .scanCleanup,
                symbol: "sparkle.magnifyingglass",
                tint: CNTheme.accent,
                pillText: "未扫描",
                pillStyle: .neutral,
                safetyHint: "扫描只读，不会删除文件"
            )
        }

        return FocusState(
            title: "当前没有需要立即处理的项目",
            detail: "磁盘余量和内存压力正常，本轮清理扫描也没有发现候选项。",
            actionTitle: "查看系统状态",
            action: .openSystemStatus,
            symbol: "checkmark.shield.fill",
            tint: CNTheme.success,
            pillText: "状态正常",
            pillStyle: .success,
            safetyHint: "系统状态为只读采样"
        )
    }

    private var currentStatePanel: some View {
        let focus = focusState
        return VStack(alignment: .leading, spacing: 21) {
            ContentSectionHeader(
                "当前状态",
                detail: "实时本机数据",
                symbol: "gauge.with.dots.needle.67percent",
                tint: focus.tint
            ) {
                StatusPill(text: focus.pillText, symbol: focus.symbol, style: focus.pillStyle)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 34) {
                    focusContent(focus)
                    Spacer(minLength: 12)
                    StorageRing(used: usedBytes, total: store.diskTotalBytes)
                }
                VStack(alignment: .leading, spacing: 18) {
                    focusContent(focus)
                    StorageRing(used: usedBytes, total: store.diskTotalBytes)
                }
            }

            Divider().opacity(0.65)
            summaryMetrics
        }
        .cnHeroPanel()
    }

    private func focusContent(_ focus: FocusState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(CNL10n.string(focus.title))
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(-0.45)
                .fixedSize(horizontal: false, vertical: true)
            Text(CNL10n.string(focus.detail))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 650, alignment: .leading)
            HStack(spacing: 11) {
                Button {
                    perform(focus.action)
                } label: {
                    Label(CNL10n.string(focus.actionTitle), systemImage: focus.symbol)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isWorking)

                Text(CNL10n.string(focus.safetyHint))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summaryMetrics: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { summaryMetricTiles }
            VStack(spacing: 10) { summaryMetricTiles }
        }
    }

    @ViewBuilder
    private var summaryMetricTiles: some View {
        summaryMetric(
            title: "可用空间",
            value: store.diskTotalBytes > 0 ? CleanNestFormatting.bytes(store.diskFreeBytes) : "等待读取",
            detail: diskUsedFraction.map { CNL10n.format("已使用 %@", CleanNestFormatting.percent($0 * 100)) } ?? "启动磁盘",
            symbol: "internaldrive",
            tint: diskUsedFraction.map { $0 >= 0.90 ? CNTheme.warning : CNTheme.cyan } ?? CNTheme.cyan
        )
        summaryMetric(
            title: "清理扫描",
            value: store.cleanupHasScanned ? CNL10n.format("%d 项待查看", store.cleanupCandidates.count) : "尚未扫描",
            detail: store.cleanupHasScanned ? CNL10n.format("候选内容合计 %@", CleanNestFormatting.bytes(store.cleanupPotentialBytes)) : "扫描不会删除文件",
            symbol: "checklist",
            tint: CNTheme.accent
        )
        summaryMetric(
            title: "内存压力",
            value: memoryPressureLabel,
            detail: memoryUsageDetail,
            symbol: "memorychip",
            tint: memoryPressureTint
        )
    }

    private func summaryMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            CNIconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(CNL10n.string(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CNL10n.string(value))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedMetric()
                    .fixedSize(horizontal: false, vertical: true)
                Text(CNL10n.string(detail))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 0.65)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CNL10n.format("%@：%@。%@", title, value, detail))
    }

    private var commonTasks: some View {
        VStack(alignment: .leading, spacing: 13) {
            ContentSectionHeader(
                "常用任务",
                detail: "直接进入功能，不执行自动删除",
                symbol: "square.grid.2x2",
                tint: CNTheme.accent
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { taskTiles }
                VStack(spacing: 10) { taskTiles }
            }
        }
    }

    @ViewBuilder
    private var taskTiles: some View {
        actionTile(
            title: "清理文件",
            detail: "扫描缓存、安装包、归档、媒体与重复文件",
            symbol: "sparkles",
            tint: CNTheme.mint
        ) {
            if store.cleanupHasScanned {
                store.selection = .cleanup
            } else {
                perform(.scanCleanup)
            }
        }
        actionTile(
            title: "卸载 App",
            detail: "预览 App 本体与精确匹配的相关文件",
            symbol: "app.dashed",
            tint: CNTheme.violet
        ) {
            store.selection = .applications
            Task { if !store.applicationsHaveScanned { await store.scanApplications() } }
        }
        actionTile(
            title: "浏览磁盘",
            detail: "按文件夹大小定位空间占用",
            symbol: "chart.pie",
            tint: CNTheme.cyan
        ) {
            store.selection = .analyze
            Task { if !store.diskHasScanned { await store.analyze() } }
        }
    }

    private func actionTile(
        title: String,
        detail: String,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        OverviewActionTile(title: title, detail: detail, symbol: symbol, tint: tint, action: action)
    }

    private var recentResults: some View {
        let statistics = ActivityStatistics(entries: store.activities)
        return SurfaceCard(title: "最近结果", symbol: "clock.arrow.circlepath", prominence: .quiet, tint: CNTheme.mint) {
            if store.activities.isEmpty {
                HStack(alignment: .top, spacing: 11) {
                    CNIconTile(symbol: "clock", tint: Color(nsColor: .secondaryLabelColor), size: 31)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("还没有操作记录").font(.subheadline.weight(.medium))
                        Text("完成一次清理或维护后，这里会显示结果和恢复方式。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        resultStatistics(statistics)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 76)
                        recentActivity
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        resultStatistics(statistics)
                        Divider()
                        recentActivity
                    }
                }

                Label("记录统计；移到废纸篓不等于磁盘已释放。", systemImage: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button {
                    store.selection = .activity
                } label: {
                    Label("查看全部记录", systemImage: "arrow.right")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func resultStatistics(_ statistics: ActivityStatistics) -> some View {
        HStack(spacing: 20) {
            resultStatistic(
                label: "累计处理空间",
                value: CleanNestFormatting.bytes(statistics.processedBytes),
                detail: "来自清理与卸载记录"
            )
            resultStatistic(
                label: "清理项目",
                value: statistics.cleanedItems.formatted(),
                detail: "已移到废纸篓"
            )
            resultStatistic(
                label: "卸载 App",
                value: statistics.uninstalledApplications.formatted(),
                detail: "App 本体已移到废纸篓"
            )
        }
    }

    private func resultStatistic(label: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(CNL10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedMetric()
            Text(CNL10n.string(detail))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CNL10n.format("%@：%@。%@", label, value, detail))
    }

    @ViewBuilder
    private var recentActivity: some View {
        if let recent = store.activities.first {
            HStack(alignment: .top, spacing: 11) {
                CNIconTile(symbol: recent.outcome.symbol, tint: Color.outcome(recent.outcome), size: 31)
                VStack(alignment: .leading, spacing: 4) {
                    Text(CNL10n.string(recent.title)).font(.subheadline.weight(.medium))
                    Text(recent.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    Text(recent.date, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
    }

    private var memoryPressureLabel: String {
        switch store.nativeMonitorSample?.memoryPressureLevel {
        case .normal: return CNL10n.string("正常")
        case .warning: return CNL10n.string("警告")
        case .critical: return CNL10n.string("严重")
        case .unknown: return CNL10n.string("未知")
        case nil: return CNL10n.string("等待采样")
        }
    }

    private var memoryUsageDetail: String {
        guard let value = store.nativeMonitorSample?.memoryUsedPercent else {
            return CNL10n.string("原生实时采样")
        }
        return CNL10n.format("内存已用 %@", CleanNestFormatting.percent(value))
    }

    private var memoryPressureTint: Color {
        switch store.nativeMonitorSample?.memoryPressureLevel {
        case .normal: return CNTheme.success
        case .warning: return CNTheme.warning
        case .critical: return CNTheme.danger
        case .unknown, nil: return CNTheme.violet
        }
    }

    private func perform(_ action: FocusAction) {
        switch action {
        case .scanCleanup:
            Task {
                await store.scanCleanup()
                store.selection = .cleanup
            }
        case .openCleanup:
            store.selection = .cleanup
        case .openSystemStatus:
            store.selection = .status
        }
    }
}

private struct OverviewActionTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    CNIconTile(symbol: symbol, tint: tint, size: 38)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isHovered ? tint : Color(nsColor: .tertiaryLabelColor))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(CNL10n.string(title))
                        .font(.system(size: 14.5, weight: .semibold))
                    Text(CNL10n.string(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
            .padding(16)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(isHovered ? 0.16 : 0.10), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isHovered ? tint.opacity(0.30) : Color.white.opacity(0.08), lineWidth: 0.7)
        )
        .shadow(color: tint.opacity(isHovered ? 0.16 : 0.06), radius: isHovered ? 16 : 8, y: isHovered ? 8 : 4)
        .offset(y: reduceMotion ? 0 : (isHovered ? -2 : 0))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct StorageRing: View {
    let used: Int64
    let total: Int64

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .shadow(color: CNTheme.accent.opacity(0.16), radius: 22)
            Circle()
                .stroke(Color.primary.opacity(0.075), lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(
                        colors: [CNTheme.accentStrong, CNTheme.accent, CNTheme.cyan],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                    .monospacedMetric()
                Text("磁盘已使用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 148, height: 148)
        .padding(7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CNL10n.format("磁盘已使用 %d 百分比", Int((fraction * 100).rounded())))
    }
}
