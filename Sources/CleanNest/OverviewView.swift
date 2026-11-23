import SwiftUI
import CleanNestCore

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var nativeMonitorSample: NativeMonitorSample? = nil

    private enum FocusAction {
        case scanCleanup
        case openCleanup
        case openSystemStatus
        case openSettings(CleanNestSettingsSection)
        case openActivity(UUID)
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
    }

    private struct PriorityTask: Identifiable {
        let id: String
        let title: String
        let detail: String
        let actionTitle: String
        let action: FocusAction
        let symbol: String
        let tint: Color
        let pillText: String
        let pillStyle: StatusPill.Style
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "总览",
                    subtitle: "你的 Mac，今天怎么样？"
                ) {
                    StatusPill(
                        text: store.demoMode ? "演示数据" : "本地运行",
                        symbol: store.demoMode ? "sparkles" : "lock.shield",
                        style: store.demoMode ? .warning : .success
                    )
                }

                priorityTaskQueue
                readOnlySnapshot
                commonTasks
                CNDetailSection(title: "最近操作与累计成果", summary: "查看处理结果、统计与恢复入口", symbol: "clock.arrow.circlepath") {
                    recentResults
                }
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
        .onReceive(store.nativeMonitorSamplePublisher) { nativeMonitorSample = $0 }
    }

    private var usedBytes: Int64 {
        max(0, store.diskTotalBytes - store.diskFreeBytes)
    }

    private var diskUsedFraction: Double? {
        guard store.diskTotalBytes > 0 else { return nil }
        return min(1, max(0, Double(usedBytes) / Double(store.diskTotalBytes)))
    }

    private var focusState: FocusState {
        if nativeMonitorSample?.memoryPressureLevel == .critical {
            return FocusState(
                title: "内存压力较高",
                detail: "macOS 已报告严重内存压力。先查看占用进程，再决定是否退出。",
                actionTitle: "查看内存进程",
                action: .openSystemStatus,
                symbol: "memorychip.fill",
                tint: CNTheme.danger,
                pillText: "需要处理",
                pillStyle: .danger
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
                pillStyle: .warning
            )
        }

        if nativeMonitorSample?.memoryPressureLevel == .warning {
            return FocusState(
                title: "内存压力正在升高",
                detail: "macOS 已报告内存压力警告。查看连续采样和占用进程，再决定是否退出。",
                actionTitle: "查看内存进程",
                action: .openSystemStatus,
                symbol: "memorychip",
                tint: CNTheme.warning,
                pillText: "建议查看",
                pillStyle: .warning
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
                pillStyle: .neutral
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
                pillStyle: .neutral
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
            pillStyle: .success
        )
    }

    private var priorityTasks: [PriorityTask] {
        let focus = focusState
        var tasks = [PriorityTask(
            id: "primary",
            title: focus.title,
            detail: focus.detail,
            actionTitle: focus.actionTitle,
            action: focus.action,
            symbol: focus.symbol,
            tint: focus.tint,
            pillText: focus.pillText,
            pillStyle: focus.pillStyle
        )]

        if let failed = store.activities.first(where: { $0.outcome == .failed }) {
            tasks.append(PriorityTask(
                id: "activity:\(failed.id.uuidString)",
                title: "查看最近未完成的操作",
                detail: failed.title + "：" + failed.detail,
                actionTitle: "查看记录详情",
                action: .openActivity(failed.id),
                symbol: "exclamationmark.bubble",
                tint: CNTheme.warning,
                pillText: "待复核",
                pillStyle: .warning
            ))
        }

        if store.fullDiskAccessProbeResult != .accessible {
            tasks.append(PriorityTask(
                id: "privacy",
                title: store.fullDiskAccessProbeResult == .permissionDenied
                    ? "受保护目录访问未通过"
                    : "确认受保护目录访问",
                detail: store.fullDiskAccessProbeResult == .permissionDenied
                    ? "需要受保护目录的任务会在扫描前停止；普通目录仍可使用。"
                    : "CleanNest 本次还没有实测受保护目录；进入隐私设置后只检测一次。",
                actionTitle: "打开扫描与隐私",
                action: .openSettings(.scanAndPrivacy),
                symbol: "lock.shield",
                tint: CNTheme.warning,
                pillText: store.fullDiskAccessProbeResult == .permissionDenied ? "未通过" : "待确认",
                pillStyle: .warning
            ))
        }

        var seen = Set<String>()
        return tasks.filter { seen.insert($0.id).inserted }.prefix(3).map { $0 }
    }

    private var priorityTaskQueue: some View {
        VStack(alignment: .leading, spacing: 13) {
            ContentSectionHeader(
                "接下来",
                symbol: "list.bullet.rectangle.portrait",
                tint: CNTheme.accent
            ) {
                EmptyView()
            }

            if let hero = priorityTasks.first {
                heroTaskCard(hero)
            }

            let rest = Array(priorityTasks.dropFirst())
            if !rest.isEmpty {
                VStack(spacing: 8) {
                    ForEach(rest) { task in
                        compactTaskRow(task)
                    }
                }
            }
        }
    }

    private func heroTaskCard(_ task: PriorityTask) -> some View {
        Button { perform(task.action) } label: {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 15) {
                    heroTaskContent(task)
                    Spacer(minLength: 14)
                    heroTaskAction(task)
                }
                VStack(alignment: .leading, spacing: 12) {
                    heroTaskContent(task)
                    heroTaskAction(task)
                }
            }
            .padding(18)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [task.tint.opacity(0.16), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(task.tint.opacity(0.28), lineWidth: 0.9)
        )
        .accessibilityLabel(CNL10n.format("%@。%@。下一步：%@", task.title, task.detail, task.actionTitle))
        .accessibilityHint("打开对应栏目；不会直接执行清理或修改设置")
    }

    private func heroTaskContent(_ task: PriorityTask) -> some View {
        HStack(alignment: .center, spacing: 13) {
            CNIconTile(symbol: task.symbol, tint: task.tint, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(CNL10n.string(task.title))
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    StatusPill(text: task.pillText, symbol: nil, style: task.pillStyle)
                }
                Text(CNL10n.string(task.detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func heroTaskAction(_ task: PriorityTask) -> some View {
        Label(CNL10n.string(task.actionTitle), systemImage: "arrow.right.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(task.tint, in: Capsule())
    }

    private func compactTaskRow(_ task: PriorityTask) -> some View {
        Button { perform(task.action) } label: {
            HStack(spacing: 11) {
                CNIconTile(symbol: task.symbol, tint: task.tint, size: 30)
                Text(CNL10n.string(task.title))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                StatusPill(text: task.pillText, symbol: nil, style: task.pillStyle)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityLabel(CNL10n.format("%@。下一步：%@", task.title, task.actionTitle))
        .accessibilityHint("打开对应栏目；不会直接执行清理或修改设置")
    }

    private var readOnlySnapshot: some View {
        VStack(alignment: .leading, spacing: 13) {
            ContentSectionHeader(
                "状态",
                symbol: "gauge.with.dots.needle.67percent",
                tint: CNTheme.cyan
            ) {
                EmptyView()
            }
            summaryMetrics
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
            tint: diskUsedFraction.map { $0 >= 0.90 ? CNTheme.warning : CNTheme.cyan } ?? CNTheme.cyan,
            destination: .analyze
        )
        summaryMetric(
            title: "清理扫描",
            value: store.cleanupHasScanned ? CNL10n.format("%d 项待查看", store.cleanupCandidates.count) : "尚未扫描",
            detail: store.cleanupHasScanned ? CNL10n.format("候选内容合计 %@", CleanNestFormatting.bytes(store.cleanupPotentialBytes)) : "扫描不会删除文件",
            symbol: "checklist",
            tint: CNTheme.accent,
            destination: .cleanup
        )
        summaryMetric(
            title: "内存压力",
            value: memoryPressureLabel,
            detail: memoryUsageDetail,
            symbol: "memorychip",
            tint: memoryPressureTint,
            destination: .status
        )
    }

    private func summaryMetric(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color,
        destination: SidebarItem
    ) -> some View {
        Button { store.selection = destination } label: {
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CNL10n.format("%@：%@。%@", title, value, detail))
        .accessibilityHint("打开" + destination.displayName)
    }

    private var commonTasks: some View {
        VStack(alignment: .leading, spacing: 13) {
            ContentSectionHeader(
                "常用任务",
                symbol: "square.grid.2x2",
                tint: CNTheme.accent
            ) {
                EmptyView()
            }

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
        let totals = store.activityLifetimeTotals
        return SurfaceCard(title: "最近结果", symbol: "clock.arrow.circlepath", prominence: .quiet, tint: CNTheme.mint) {
            if store.activities.isEmpty, totals.productiveOperations == 0 {
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
                        resultStatistics(totals)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Divider().frame(height: 76)
                        recentActivity
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        resultStatistics(totals)
                        Divider()
                        recentActivity
                    }
                }

                Label("累计成果独立保存；清空明细不会归零。移到废纸篓也不等于磁盘已释放。", systemImage: "info.circle")
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

    private func resultStatistics(_ totals: ActivityLifetimeTotals) -> some View {
        HStack(spacing: 20) {
            resultStatistic(
                label: "累计处理空间",
                value: CleanNestFormatting.bytes(totals.processedBytes),
                detail: "独立累计"
            )
            resultStatistic(
                label: "清理项目",
                value: totals.cleanedItems.formatted(),
                detail: "已移到废纸篓"
            )
            resultStatistic(
                label: "卸载 App",
                value: totals.uninstalledApplications.formatted(),
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
            Button { store.openActivityDetail(recent.id) } label: {
                HStack(alignment: .top, spacing: 11) {
                    CNIconTile(symbol: recent.outcome.symbol, tint: Color.outcome(recent.outcome), size: 31)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(CNL10n.string(recent.title)).font(.subheadline.weight(.medium))
                        Text(CNL10n.string(recent.detail)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Text(recent.date, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                CNL10n.format(
                    "%@。%@。%@。%@",
                    recent.title,
                    recent.detail,
                    recent.outcome.rawValue,
                    recent.date.formatted(date: .abbreviated, time: .shortened)
                )
            )
            .accessibilityHint("打开这条活动记录的完整详情")
        } else {
            Text("活动明细已清空；累计成果仍保留。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var memoryPressureLabel: String {
        switch nativeMonitorSample?.memoryPressureLevel {
        case .normal: return CNL10n.string("正常")
        case .warning: return CNL10n.string("警告")
        case .critical: return CNL10n.string("严重")
        case .unknown: return CNL10n.string("未知")
        case nil: return CNL10n.string("等待采样")
        }
    }

    private var memoryUsageDetail: String {
        guard let value = nativeMonitorSample?.memoryUsedPercent else {
            return CNL10n.string("原生实时采样")
        }
        return CNL10n.format("内存已用 %@", CleanNestFormatting.percent(value))
    }

    private var memoryPressureTint: Color {
        switch nativeMonitorSample?.memoryPressureLevel {
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
        case .openSettings(let section):
            store.openSettings(section)
        case .openActivity(let id):
            store.openActivityDetail(id)
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
        .accessibilityLabel(CNL10n.format("%@。%@", title, detail))
        .accessibilityHint("打开对应功能；不会直接执行删除")
    }
}
