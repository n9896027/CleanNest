import AppKit
import SwiftUI
import CleanNestCore

struct DiskAnalyzeView: View {
    @EnvironmentObject private var store: AppStore

    private var largestBytes: Int64 {
        store.diskReport?.entries.map(\.bytes).max() ?? 1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "磁盘浏览",
                    subtitle: "从文件夹大小出发，找到空间真正去了哪里。"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            chooseFolder()
                        } label: {
                            Label("选择文件夹", systemImage: "folder.badge.plus")
                        }
                        Button {
                            Task { await store.analyze() }
                        } label: {
                            Label(CNL10n.string(store.diskHasScanned ? "刷新变化" : "开始分析"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isWorking)
                        Menu {
                            Button {
                                Task { await store.analyze(deepRefresh: true) }
                            } label: {
                                Label("深度刷新（忽略缓存与条目上限）", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .disabled(store.isWorking)
                            Button {
                                store.clearDiskScanCache()
                            } label: {
                                Label("清空增量索引", systemImage: "trash")
                            }
                            .disabled(store.isWorking)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        if store.diskScanProgress != nil || store.diskEvidenceProgress != nil {
                            Button("取消", role: .cancel) {
                                store.cancelDiskAnalysis()
                            }
                        }
                    }
                }

                InlineBanner(
                    title: "原生增量索引",
                    detail: "普通扫描每个顶层项目最多遍历 50 万项，并会明确标出触顶目录；15 分钟内只复用签名未变化且完整度已知的项目。深度刷新会忽略缓存和条目上限，可随时取消。",
                    kind: .info
                )

                pathBar

                if store.diskScanProgress != nil || store.diskEvidenceProgress != nil {
                    diskProgressCard
                }

                if let detail = store.diskPrivacyNoticeDetail {
                    InlineBanner(
                        title: store.diskPrivacyNoticeWasBlocked
                            ? "已阻止连续授权弹窗"
                            : (store.fullDiskAccessProbeIsRunning
                                ? "正在检测受保护目录访问"
                                : "受保护目录暂不扫描"),
                        detail: detail,
                        kind: .warning,
                        actionTitle: "前往设置页"
                    ) {
                        store.openSettings(.scanAndPrivacy)
                    }
                }

                if !store.diskHasScanned && store.diskPartialReport == nil {
                    EmptyPanel(
                        symbol: "chart.pie",
                        title: "选择一个位置开始",
                        detail: "默认分析启动卷 \(store.startupDiskDisplayName)。如果只想快速查看个人文件，可切换到主目录；也可选择项目文件夹或外接磁盘。",
                        actionTitle: "分析 \(store.startupDiskDisplayName)"
                    ) {
                        Task { await store.analyze(AppStore.startupDiskRoot) }
                    }
                } else if let report = store.diskPartialReport ?? store.diskReport {
                    capacityMetricCards(report)

                    if store.diskPartialReport == nil {
                        DiskCapacityTruthCard(report: report)
                        DiskGrowthComparisonCard(report: report)
                        DiskDecisionCenter(report: report)
                    }
                    DiskTreemapView(report: report)
                    if store.diskPartialReport == nil {
                        DiskAIInsightCard()
                    }

                    SurfaceCard(title: "空间分布", symbol: "chart.bar.xaxis") {
                        if report.entries.isEmpty {
                            Text("这个位置没有可显示的内容，或当前权限不足。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 18)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(report.entries.enumerated()), id: \.element.id) { index, entry in
                                    DiskEntryRow(entry: entry, maximumBytes: largestBytes)
                                    if index < report.entries.count - 1 { Divider().padding(.leading, 42) }
                                }
                            }
                        }
                    }

                    if store.diskPartialReport == nil {
                        InlineBanner(
                            title: "浏览页保持只读",
                            detail: "这里负责解释和决策，不会从任意文件夹直接删除内容。请先在 Finder 中确认，或使用“清理空间”里的安全范围。",
                            kind: .success
                        )
                    }
                }
            }
            .padding(CNTheme.pagePadding)
        }
    }

    private var scanModeValue: String {
        if store.diskPartialReport != nil { return "实时更新" }
        if let coverage = store.diskScanCoverage { return coverage.statusLabel }
        if store.diskScanCacheHitCount > 0 {
            return "复用 \(store.diskScanCacheHitCount) 项"
        }
        return store.diskScanScannedCount > 0 ? "实扫 \(store.diskScanScannedCount) 项" : "完整度待核验"
    }

    private var scanModeDetail: String {
        if let coverage = store.diskScanCoverage {
            var parts = ["遍历 \(coverage.visitedEntryCount) 项"]
            if coverage.limitedSubtreeCount > 0 {
                parts.append("\(coverage.limitedSubtreeCount) 个目录触顶")
            }
            if coverage.unreadableEntryCount + coverage.rootEnumerationErrorCount > 0 {
                parts.append("\(coverage.unreadableEntryCount + coverage.rootEnumerationErrorCount) 项不可读")
            }
            return parts.joined(separator: " · ")
        }
        if let elapsed = store.diskScanElapsedSeconds {
            let mode = store.diskScanCacheHitCount > 0
                ? "另实扫 \(store.diskScanScannedCount) 项"
                : "未使用缓存"
            return "\(String(format: "%.2f", elapsed)) 秒 · \(mode)"
        }
        return "缓存命中会明确标注"
    }

    @ViewBuilder
    private func capacityMetricCards(_ report: DiskReport) -> some View {
        let classified = MetricCard(
            label: store.diskPartialReport == nil ? "已归类文件" : "已发现文件",
            value: CleanNestFormatting.bytes(report.totalBytes),
            detail: store.diskPartialReport == nil ? "来自文件遍历，不是 APFS 已用" : "扫描进行中，数值仍会变化",
            symbol: "folder",
            tint: CNTheme.accent
        )
        let layer = MetricCard(
            label: "当前层级",
            value: CNL10n.format("%d 项", report.entries.count),
            detail: store.diskPartialReport == nil ? "按占用从大到小排列" : "实时部分结果",
            symbol: "list.bullet.rectangle",
            tint: CNTheme.success
        )
        let status = MetricCard(
            label: "扫描完整度",
            value: scanModeValue,
            detail: scanModeDetail,
            symbol: "checklist.checked",
            tint: store.diskScanCoverage?.hasKnownLimitOrReadGap == true ? CNTheme.warning : CNTheme.cyan
        )

        if let volume = store.diskVolumeSnapshot {
            let used = MetricCard(
                label: "APFS 实际已用",
                value: CleanNestFormatting.bytes(volume.usedBytes),
                detail: "卷总容量 \(CleanNestFormatting.bytes(volume.totalBytes))",
                symbol: "internaldrive.fill",
                tint: CNTheme.violet
            )
            let available = MetricCard(
                label: "APFS 实际可用",
                value: CleanNestFormatting.bytes(volume.availableBytes),
                detail: "由 macOS 卷总账直接读取",
                symbol: "internaldrive",
                tint: CNTheme.success
            )
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { used; available; classified; status }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    used; available; classified; status
                }
            }
        } else {
            HStack(spacing: 12) { classified; layer; status }
        }
    }

    private var pathBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "internaldrive").foregroundStyle(CNTheme.accent)
                ForEach(Array(breadcrumbs.enumerated()), id: \.element.path) { index, item in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Button(breadcrumbLabel(item, index: index)) {
                        Task { await store.analyze(item) }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(index == breadcrumbs.count - 1 ? .semibold : .regular))
                    .foregroundStyle(index == breadcrumbs.count - 1 ? .primary : CNTheme.accent)
                    .disabled(index == breadcrumbs.count - 1 || store.isWorking)
                }
                Spacer()
                Button {
                    store.revealInFinder(store.diskRoot)
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(.borderless)
                .help(CNL10n.string("在 Finder 中显示"))
                if store.diskRoot != AppStore.startupDiskRoot {
                    Button(store.startupDiskDisplayName) {
                        Task { await store.analyze(AppStore.startupDiskRoot) }
                    }
                    .controlSize(.small)
                    .help("切换到整个启动卷")
                }
                if store.diskRoot != FileManager.default.homeDirectoryForCurrentUser {
                    Button("主目录") {
                        Task { await store.analyze(FileManager.default.homeDirectoryForCurrentUser) }
                    }
                    .controlSize(.small)
                }
            }
            Text(store.diskRoot.path)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(12)
        .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CNTheme.divider, lineWidth: 0.7))
    }

    private var diskProgressCard: some View {
        SurfaceCard {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    if let progress = store.diskEvidenceProgress {
                        Text("正在建立用途与可清理性证据")
                            .font(.subheadline.weight(.semibold))
                        ProgressView(value: progress.fraction)
                        Text(progress.currentName.isEmpty
                            ? "正在汇总文件类型、时间与来源…"
                            : "正在检查 \(progress.currentName) · \(progress.completed)/\(progress.total)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let progress = store.diskScanProgress {
                        Text("正在计算当前层级 · 已出现的结果可先查看")
                            .font(.subheadline.weight(.semibold))
                        if progress.total > 0 { ProgressView(value: progress.fraction) }
                        Text(progress.currentName.isEmpty
                            ? "正在等待分析引擎返回…"
                            : "正在分析 \(progress.currentName)" + (progress.total > 0 ? " · \(progress.completed)/\(progress.total) · 复用 \(progress.cacheHitCount) · 实扫 \(progress.scannedCount)" : ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("取消") { store.cancelDiskAnalysis() }
            }
        }
    }

    private var breadcrumbs: [URL] {
        let target = store.diskRoot.standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let targetPath = target.path
        let base: URL
        if targetPath == home.path || targetPath.hasPrefix(home.path + "/") {
            base = home
        } else {
            base = URL(fileURLWithPath: "/", isDirectory: true)
        }
        if target.path == base.path { return [base] }
        let relative = String(target.path.dropFirst(base.path == "/" ? 1 : base.path.count + 1))
        var result = [base]
        var current = base
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component), isDirectory: true)
            result.append(current)
        }
        return result
    }

    private func breadcrumbLabel(_ url: URL, index: Int) -> String {
        if index == 0, url.standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL {
            return CNL10n.string("主目录")
        }
        if url.path == "/" { return store.startupDiskDisplayName }
        return url.lastPathComponent
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = CNL10n.string("选择要分析的文件夹")
        panel.prompt = CNL10n.string("分析此文件夹")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.diskRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.analyze(url) }
    }
}

private struct DiskCapacityTruthCard: View {
    @EnvironmentObject private var store: AppStore
    let report: DiskReport

    private var reconciliation: DiskCapacityReconciliation? {
        store.diskCapacityReconciliation
    }

    var body: some View {
        SurfaceCard(
            title: "磁盘总账与文件归类",
            symbol: "equal.circle",
            prominence: .prominent,
            tint: CNTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    CNIconTile(symbol: "internaldrive.fill", tint: CNTheme.violet, size: 42)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(accountingHeadline)
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(accountingExplanation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    StatusPill(
                        text: coveragePillText,
                        symbol: coverageHasGap ? "exclamationmark.triangle" : "checkmark.circle",
                        style: coverageHasGap ? .warning : .success
                    )
                }

                if let reconciliation,
                   let difference = reconciliation.accountingDifferenceBytes {
                    VStack(alignment: .leading, spacing: 8) {
                        accountingBar(reconciliation)
                        HStack {
                            Label(
                                "APFS 已用 \(CleanNestFormatting.bytes(reconciliation.volume.usedBytes))",
                                systemImage: "internaldrive.fill"
                            )
                            Spacer()
                            Label(
                                "文件已归类 \(CleanNestFormatting.bytes(reconciliation.classifiedBytes))",
                                systemImage: "folder.fill"
                            )
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                        if difference > 0 {
                            InlineBanner(
                                title: "还有 \(CleanNestFormatting.bytes(difference)) 未被文件遍历解释",
                                detail: "这不是“可清理空间”。它可能包含 APFS 快照、Preboot/Recovery/VM 等同容器卷、受保护目录、触及条目上限的目录、系统保留，以及克隆或硬链接造成的账本差异。",
                                kind: .warning
                            )
                        } else if difference < 0 {
                            InlineBanner(
                                title: "文件分配块合计比 APFS 物理已用多 \(CleanNestFormatting.bytes(abs(difference)))",
                                detail: "APFS 克隆、硬链接或 firmlink 可能让多个路径引用同一批物理块。文件求和不能替代卷总账。",
                                kind: .info
                            )
                        }
                    }
                } else {
                    InlineBanner(
                        title: "当前只分析所选文件夹",
                        detail: "\(report.root.path) 不是卷根目录，因此只显示这里已归类的文件；不会拿它与整块磁盘已用空间制造虚假的“缺口”。",
                        kind: .info
                    )
                }

                if let coverage = store.diskScanCoverage {
                    coverageFacts(coverage)
                    HStack(spacing: 8) {
                        if coverage.limitedSubtreeCount > 0 || coverage.unknownCachedSubtreeCount > 0 {
                            Button {
                                Task { await store.analyze(deepRefresh: true) }
                            } label: {
                                Label("深度重扫，不设条目上限", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isWorking)
                        }
                        if coverage.unreadableEntryCount + coverage.rootEnumerationErrorCount > 0 {
                            Button("检查文件访问") {
                                store.openSettings(.scanAndPrivacy)
                            }
                        }
                        Spacer()
                        Text("仍保持只读，不会把差额当成垃圾")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("磁盘总账与文件归类。\(accountingHeadline)。\(accountingExplanation)")
    }

    private var coverageHasGap: Bool {
        store.diskScanCoverage?.hasKnownLimitOrReadGap ?? true
    }

    private var coveragePillText: String {
        store.diskScanCoverage?.statusLabel ?? "完整度未知"
    }

    private var accountingHeadline: String {
        guard let reconciliation,
              let difference = reconciliation.accountingDifferenceBytes else {
            return "文件夹归类与整卷空间是两套数字"
        }
        if difference >= 0 {
            return "\(CleanNestFormatting.bytes(report.totalBytes)) 已归类；不是磁盘总占用"
        }
        return "文件路径求和与 APFS 物理账本存在重叠"
    }

    private var accountingExplanation: String {
        guard let volume = store.diskVolumeSnapshot else {
            return "CleanNest 目前只有文件遍历结果，无法读取这个位置所在卷的容量总账。"
        }
        if volume.selectedRootIsVolumeRoot {
            return "macOS 报告 \(volume.volumeName) 实际已用 \(CleanNestFormatting.bytes(volume.usedBytes))、实际可用 \(CleanNestFormatting.bytes(volume.availableBytes))；CleanNest 另行解释能遍历到的文件。"
        }
        return "所在卷实际已用 \(CleanNestFormatting.bytes(volume.usedBytes))、可用 \(CleanNestFormatting.bytes(volume.availableBytes))；当前所选文件夹只占其中一部分。"
    }

    private func accountingBar(_ value: DiskCapacityReconciliation) -> some View {
        GeometryReader { proxy in
            let usedWidth = proxy.size.width
            let classifiedShare = min(1, max(0, value.classifiedShareOfUsed ?? 0))
            ZStack(alignment: .leading) {
                Capsule().fill(CNTheme.violet.opacity(0.18))
                Capsule()
                    .fill(CNTheme.accent.opacity(0.82))
                    .frame(width: usedWidth * classifiedShare)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("APFS 已用空间中，文件遍历已归类约 \(Int(min(1, max(0, value.classifiedShareOfUsed ?? 0)) * 100)) 百分比")
    }

    private func coverageFacts(_ coverage: DiskScanCoverage) -> some View {
        let readErrors = coverage.rootEnumerationErrorCount + coverage.unreadableEntryCount
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                StatusPill(text: "遍历 \(coverage.visitedEntryCount) 项", symbol: "doc.text.magnifyingglass", style: .neutral)
                StatusPill(text: "文件 \(coverage.regularFileCount) 个", symbol: "doc", style: .neutral)
                StatusPill(text: "隐藏顶层 \(coverage.hiddenTopLevelEntryCount) 项", symbol: "eye.slash", style: .neutral)
                if coverage.limitedSubtreeCount > 0 {
                    StatusPill(text: "\(coverage.limitedSubtreeCount) 个目录触顶", symbol: "exclamationmark.triangle", style: .warning)
                }
                if readErrors > 0 {
                    StatusPill(text: "\(readErrors) 项不可读", symbol: "lock", style: .warning)
                }
                if coverage.crossVolumeEntryCount > 0 {
                    StatusPill(text: "跳过 \(coverage.crossVolumeEntryCount) 个其他卷入口", symbol: "externaldrive", style: .neutral)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    StatusPill(text: "遍历 \(coverage.visitedEntryCount) 项", symbol: "doc.text.magnifyingglass", style: .neutral)
                    StatusPill(text: "文件 \(coverage.regularFileCount) 个", symbol: "doc", style: .neutral)
                }
                HStack(spacing: 8) {
                    if coverage.limitedSubtreeCount > 0 {
                        StatusPill(text: "\(coverage.limitedSubtreeCount) 个目录触顶", symbol: "exclamationmark.triangle", style: .warning)
                    }
                    if readErrors > 0 {
                        StatusPill(text: "\(readErrors) 项不可读", symbol: "lock", style: .warning)
                    }
                }
            }
        }
    }
}

private struct DiskGrowthComparisonCard: View {
    @EnvironmentObject private var store: AppStore
    let report: DiskReport

    private struct Change: Identifiable {
        enum Kind { case grown, shrunk, added, removed }
        let id: String
        let name: String
        let bytes: Int64
        let kind: Kind
    }

    private var comparisonIsReliable: Bool {
        guard let coverage = store.diskScanCoverage else { return false }
        return !coverage.hasKnownLimitOrReadGap
    }

    private var changes: [Change] {
        guard comparisonIsReliable,
              let current = store.diskEvidenceReport,
              let previous = store.diskPreviousEvidenceReport else { return [] }
        let previousByID = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.id, $0) })
        let currentIDs = Set(current.entries.map(\.id))
        var values = current.entries.compactMap { entry -> Change? in
            guard let old = previousByID[entry.id] else {
                return Change(id: entry.id, name: entry.name, bytes: entry.allocatedBytes, kind: .added)
            }
            let delta = entry.allocatedBytes - old.allocatedBytes
            guard delta != 0 else { return nil }
            return Change(
                id: entry.id,
                name: entry.name,
                bytes: abs(delta),
                kind: delta > 0 ? .grown : .shrunk
            )
        }
        values += previous.entries.compactMap { entry in
            guard !currentIDs.contains(entry.id) else { return nil }
            return Change(id: entry.id, name: entry.name, bytes: entry.allocatedBytes, kind: .removed)
        }
        return values.sorted {
            if $0.bytes == $1.bytes { return $0.name < $1.name }
            return $0.bytes > $1.bytes
        }
    }

    var body: some View {
        SurfaceCard(title: "与上次完整扫描相比", symbol: "clock.arrow.2.circlepath") {
            if store.diskScanCoverage?.hasKnownLimitOrReadGap == true {
                InlineBanner(
                    title: "本次不生成增长结论",
                    detail: "本次扫描触及条目上限、存在不可读项目或复用了完整度未知的旧索引。CleanNest 保留上次可靠基线，不用不完整数字制造“突然增长”。",
                    kind: .warning
                )
            } else if let previous = store.diskPreviousEvidenceReport,
                      let previousBytes = store.diskPreviousClassifiedBytes {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(netChangeText(previousBytes: previousBytes))
                                .font(.title3.weight(.semibold))
                            Text("基线：\(previous.generatedAt.formatted(date: .abbreviated, time: .shortened)) · 只比较同一根目录的两次可靠结果")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(text: "不完整扫描不入账", symbol: "checkmark.shield", style: .success)
                    }

                    if changes.isEmpty {
                        Text("前 16 个证据目录没有可见变化。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(changes.prefix(8)) { change in
                                changeTile(change)
                            }
                        }
                    }
                }
            } else {
                InlineBanner(
                    title: "这次先建立可靠基线",
                    detail: "完成下一次同一根目录的可靠扫描后，这里会显示新出现、增长、缩小和消失的目录。只保留最近两次本机聚合快照，不保存文件内容。",
                    kind: .info
                )
            }
        }
    }

    private func netChangeText(previousBytes: Int64) -> String {
        let delta = report.totalBytes - previousBytes
        if delta > 0 { return "已归类文件净增加 \(CleanNestFormatting.bytes(delta))" }
        if delta < 0 { return "已归类文件净减少 \(CleanNestFormatting.bytes(abs(delta)))" }
        return "已归类文件总量没有变化"
    }

    private func changeTile(_ change: Change) -> some View {
        let presentation = changePresentation(change.kind)
        return HStack(spacing: 10) {
            CNIconTile(symbol: presentation.symbol, tint: presentation.tint, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(change.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(presentation.label) \(CleanNestFormatting.bytes(change.bytes))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(presentation.tint)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(presentation.tint.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private func changePresentation(_ kind: Change.Kind) -> (label: String, symbol: String, tint: Color) {
        switch kind {
        case .grown: return ("增长", "arrow.up.right", CNTheme.warning)
        case .shrunk: return ("缩小", "arrow.down.right", CNTheme.success)
        case .added: return ("新出现", "plus.circle", CNTheme.accent)
        case .removed: return ("已消失", "minus.circle", CNTheme.violet)
        }
    }
}

private enum DiskDecisionFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case review = "待复核"
    case ownerApp = "App 内管理"
    case keep = "保留"
    case manual = "我的决定"

    var id: String { rawValue }
}

private enum DiskDecisionChoice: String, CaseIterable, Identifiable {
    case followSystem
    case reviewForCleanup
    case keep
    case decideLater

    var id: String { rawValue }

    init(_ decision: DiskManualDecision?) {
        switch decision {
        case .reviewForCleanup: self = .reviewForCleanup
        case .keep: self = .keep
        case .decideLater: self = .decideLater
        case nil: self = .followSystem
        }
    }

    var manualDecision: DiskManualDecision? {
        switch self {
        case .followSystem: return nil
        case .reviewForCleanup: return .reviewForCleanup
        case .keep: return .keep
        case .decideLater: return .decideLater
        }
    }

    var label: String {
        switch self {
        case .followSystem: return "跟随建议"
        case .reviewForCleanup: return "待清理复核"
        case .keep: return "保留"
        case .decideLater: return "稍后处理"
        }
    }
}

private struct DiskDecisionItem: Identifiable {
    let entry: DiskEntry
    let evidence: DiskEvidenceEntry
    var id: String { entry.id }
}

private struct DiskDecisionCenter: View {
    @EnvironmentObject private var store: AppStore
    let report: DiskReport
    @State private var filter: DiskDecisionFilter = .all
    @State private var selectedID: String?

    private var items: [DiskDecisionItem] {
        report.entries.compactMap { entry in
            guard let evidence = store.diskEvidence(for: entry) else { return nil }
            return DiskDecisionItem(entry: entry, evidence: evidence)
        }
    }

    private var filteredItems: [DiskDecisionItem] {
        items.filter { item in
            let manual = store.manualDiskDecision(for: item.evidence)
            switch filter {
            case .all:
                return true
            case .review:
                if manual == .reviewForCleanup { return true }
                guard manual == nil else { return false }
                return [.reviewCandidate, .inspectFurther].contains(item.evidence.cleanupDecision.disposition)
            case .ownerApp:
                guard manual == nil else { return false }
                return item.evidence.cleanupDecision.disposition == .manageInOwnerApp
            case .keep:
                return manual == .keep
                    || (manual == nil && item.evidence.cleanupDecision.disposition == .keep)
            case .manual:
                return manual != nil
            }
        }
    }

    private var selectedItem: DiskDecisionItem? {
        if let selectedID, let item = items.first(where: { $0.id == selectedID }) {
            return item
        }
        return filteredItems.first ?? items.first
    }

    var body: some View {
        SurfaceCard(
            title: "清理决策中心",
            symbol: "scope",
            prominence: .prominent,
            tint: CNTheme.cyan
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 12) {
                        decisionIntroduction
                        Spacer()
                        decisionFilter
                            .frame(width: 520)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        decisionIntroduction
                        decisionFilter
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        decisionList
                            .frame(width: 300)
                        if let selectedItem {
                            decisionDetail(selectedItem)
                                .frame(width: 540, alignment: .topLeading)
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        decisionList
                        if let selectedItem { decisionDetail(selectedItem) }
                    }
                }
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = filteredItems.first?.id ?? items.first?.id }
        }
        .onChange(of: filter) {
            if let selectedID, filteredItems.contains(where: { $0.id == selectedID }) { return }
            selectedID = filteredItems.first?.id
        }
    }

    private var decisionIntroduction: some View {
        Text("系统先给出确定性证据；你可以手动改为待复核、保留或稍后处理。模型和手动选择都不能突破安全边界。")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var decisionFilter: some View {
        Picker("决策筛选", selection: $filter) {
            ForEach(DiskDecisionFilter.allCases) { value in
                Text(CNL10n.string(value.rawValue)).tag(value)
            }
        }
        .pickerStyle(.segmented)
    }

    private var decisionList: some View {
        LazyVStack(spacing: 0) {
            if filteredItems.isEmpty {
                Text("这个筛选下没有项目。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                    decisionRow(item)
                    if index < filteredItems.count - 1 { Divider().padding(.leading, 40) }
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 0.7)
        )
    }

    private func decisionRow(_ item: DiskDecisionItem) -> some View {
        let decision = item.evidence.cleanupDecision
        let manual = store.manualDiskDecision(for: item.evidence)
        let selected = selectedItem?.id == item.id
        return Button {
            selectedID = item.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: rowSymbol(manual: manual, system: decision.disposition))
                    .foregroundStyle(rowTint(manual: manual, system: decision.disposition))
                    .frame(width: 28, height: 28)
                    .background(
                        rowTint(manual: manual, system: decision.disposition).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.entry.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(CNL10n.string(rowHeadline(manual: manual, system: decision)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(CleanNestFormatting.bytes(item.entry.bytes))
                    .font(.caption.weight(.semibold))
                    .monospacedMetric()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(selected ? CNTheme.accent.opacity(0.10) : Color.clear)
        .accessibilityLabel("\(item.entry.name)，\(rowHeadline(manual: manual, system: decision))，\(CleanNestFormatting.bytes(item.entry.bytes))")
    }

    private func decisionDetail(_ item: DiskDecisionItem) -> some View {
        let decision = item.evidence.cleanupDecision
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                CNIconTile(
                    symbol: dispositionSymbol(decision.disposition),
                    tint: dispositionTint(decision.disposition),
                    size: 42
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.entry.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(decision.headline)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(dispositionTint(decision.disposition))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    StatusPill(
                        text: CNL10n.format(
                            "系统建议 · %@",
                            CNL10n.string(confidenceLabel(decision.confidence))
                        ),
                        symbol: "checkmark.seal",
                        style: decision.confidence == .high ? .success : (decision.confidence == .medium ? .warning : .neutral)
                    )
                    if store.manualDiskDecision(for: item.evidence) != nil {
                        StatusPill(text: "已手动调整", symbol: "hand.tap", style: .neutral)
                    }
                }
            }

            manualDecisionControl(item)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    decisionFact("用途", item.evidence.purpose, symbol: "questionmark.folder")
                    decisionFact("为何变大", decision.whyLarge, symbol: "arrow.up.right")
                }
                VStack(alignment: .leading, spacing: 10) {
                    decisionFact("用途", item.evidence.purpose, symbol: "questionmark.folder")
                    decisionFact("为何变大", decision.whyLarge, symbol: "arrow.up.right")
                }
            }
            decisionFact("处理影响", decision.impact, symbol: "exclamationmark.shield")
            decisionFact("可恢复性", decision.recovery, symbol: "arrow.uturn.backward.circle")
            decisionFact("下一步", decision.nextStep, symbol: "arrow.right.circle")

            DisclosureGroup("查看本机证据（\(decision.evidence.count)）") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(decision.evidence, id: \.self) { signal in
                        Label(signal, systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 7)
            }
            .font(.caption.weight(.medium))

            HStack(spacing: 8) {
                if item.entry.isDirectory {
                    Button {
                        Task { await store.analyze(item.entry.url) }
                    } label: {
                        Label("进入下一层", systemImage: "arrow.right")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isWorking)
                }
                Button {
                    store.revealInFinder(item.entry.url)
                } label: {
                    Label("在 Finder 中确认", systemImage: "folder")
                }
                if store.diskOwnerApplicationURL(for: item.evidence) != nil {
                    Button {
                        store.openDiskOwnerApplication(for: item.evidence)
                    } label: {
                        Label("在所属 App 管理", systemImage: "app.badge")
                    }
                }
                if store.manualDiskDecision(for: item.evidence) == .reviewForCleanup {
                    Button {
                        store.selection = .cleanup
                    } label: {
                        Label("前往安全清理页", systemImage: "trash.slash")
                    }
                }
                Spacer()
                StatusPill(text: "不自动删除", symbol: "lock.shield", style: .success)
            }
        }
        .padding(17)
        .background(
            LinearGradient(
                colors: [dispositionTint(decision.disposition).opacity(0.11), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(dispositionTint(decision.disposition).opacity(0.16), lineWidth: 0.7)
        )
    }

    private func manualDecisionControl(_ item: DiskDecisionItem) -> some View {
        let canReview = store.canMarkForCleanupReview(item.evidence)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("你的决定", systemImage: "hand.tap")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("保存在本机")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Picker("你的决定", selection: manualDecisionBinding(for: item)) {
                ForEach(DiskDecisionChoice.allCases) { choice in
                    Text(CNL10n.string(choice.label))
                        .tag(choice)
                        .disabled(choice == .reviewForCleanup && !canReview)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Text(CNL10n.string(canReview
                ? "“待清理复核”会把它保留在待复核列表，但不会自动勾选或删除；实际处理仍需进入安全清理页再次确认。"
                : "此项目受保护、风险较高或应由所属 App 管理，因此不能标为待清理；你仍可选择保留、稍后处理或跟随系统。"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(CNTheme.accent.opacity(0.075), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(CNTheme.accent.opacity(0.14), lineWidth: 0.7)
        )
    }

    private func manualDecisionBinding(for item: DiskDecisionItem) -> Binding<DiskDecisionChoice> {
        Binding(
            get: { DiskDecisionChoice(store.manualDiskDecision(for: item.evidence)) },
            set: { choice in
                store.setManualDiskDecision(choice.manualDecision, for: item.evidence)
            }
        )
    }

    private func rowHeadline(
        manual: DiskManualDecision?,
        system: DiskCleanupDecision
    ) -> String {
        switch manual {
        case .reviewForCleanup: return "你的决定：待清理复核"
        case .keep: return "你的决定：保留"
        case .decideLater: return "你的决定：稍后处理"
        case nil: return system.headline
        }
    }

    private func rowSymbol(
        manual: DiskManualDecision?,
        system: DiskCleanupDisposition
    ) -> String {
        switch manual {
        case .reviewForCleanup: return "checkmark.shield"
        case .keep: return "hand.raised.fill"
        case .decideLater: return "clock"
        case nil: return dispositionSymbol(system)
        }
    }

    private func rowTint(
        manual: DiskManualDecision?,
        system: DiskCleanupDisposition
    ) -> Color {
        switch manual {
        case .reviewForCleanup: return CNTheme.success
        case .keep: return CNTheme.accent
        case .decideLater: return CNTheme.warning
        case nil: return dispositionTint(system)
        }
    }

    private func decisionFact(_ title: String, _ detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(CNTheme.accent)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dispositionSymbol(_ disposition: DiskCleanupDisposition) -> String {
        switch disposition {
        case .reviewCandidate: return "checkmark.shield"
        case .inspectFurther: return "arrow.down.right.and.arrow.up.left"
        case .manageInOwnerApp: return "app.badge"
        case .keep: return "lock.shield"
        }
    }

    private func dispositionTint(_ disposition: DiskCleanupDisposition) -> Color {
        switch disposition {
        case .reviewCandidate: return CNTheme.success
        case .inspectFurther: return CNTheme.warning
        case .manageInOwnerApp: return CNTheme.violet
        case .keep: return CNTheme.danger
        }
    }

    private func confidenceLabel(_ confidence: DiskDecisionConfidence) -> String {
        switch confidence {
        case .high: return "高证据"
        case .medium: return "中等证据"
        case .low: return "证据不足"
        }
    }
}

private struct DiskTreemapView: View {
    @EnvironmentObject private var store: AppStore
    let report: DiskReport

    private var entriesByID: [String: DiskEntry] {
        Dictionary(uniqueKeysWithValues: report.entries.map { ($0.id, $0) })
    }

    var body: some View {
        SurfaceCard(title: "空间地图", symbol: "square.grid.3x3.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("面积代表占用大小；点击文件夹继续下钻，点击文件在 Finder 中确认。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    StatusPill(text: "只读浏览", symbol: "lock.shield", style: .success)
                }

                GeometryReader { proxy in
                    let placements = TreemapLayout.layout(
                        items: report.entries.map {
                            TreemapItem(id: $0.id, weight: Double(max(0, $0.bytes)))
                        },
                        in: CGRect(origin: .zero, size: proxy.size)
                    )
                    ZStack(alignment: .topLeading) {
                        ForEach(placements) { placement in
                            if let entry = entriesByID[placement.id] {
                                treemapTile(entry, placement: placement)
                            }
                        }
                    }
                }
                .frame(height: 330)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(CNTheme.divider, lineWidth: 0.7))

                HStack(spacing: 12) {
                    legend("可再生成", color: CNTheme.success)
                    legend("需逐项确认", color: CNTheme.warning)
                    legend("用户内容", color: CNTheme.accent)
                    legend("受保护/未知", color: CNTheme.danger)
                }
            }
        }
    }

    private func treemapTile(_ entry: DiskEntry, placement: TreemapPlacement) -> some View {
        let rect = placement.rect.insetBy(dx: 1.5, dy: 1.5)
        let evidence = store.diskEvidence(for: entry)
        return Button {
            if entry.isDirectory {
                Task { await store.analyze(entry.url) }
            } else {
                store.revealInFinder(entry.url)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: min(8, max(3, rect.width / 10)))
                    .fill(color(for: evidence).opacity(0.78))
                if rect.width > 64, rect.height > 38 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(rect.height > 70 ? 2 : 1)
                        Text(CleanNestFormatting.bytes(entry.bytes))
                            .font(.caption2.monospacedDigit())
                            .opacity(0.82)
                    }
                    .foregroundStyle(.white)
                    .padding(7)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .position(x: rect.midX, y: rect.midY)
        .help("\(entry.name) · \(CleanNestFormatting.bytes(entry.bytes))")
        .accessibilityLabel("\(entry.name)，\(CleanNestFormatting.bytes(entry.bytes))")
        .disabled(store.isWorking)
        .contextMenu {
            Button("在 Finder 中显示") { store.revealInFinder(entry.url) }
            if entry.isDirectory {
                Button("进入此文件夹") { Task { await store.analyze(entry.url) } }
            }
        }
    }

    private func color(for evidence: DiskEvidenceEntry?) -> Color {
        guard let evidence else { return CNTheme.danger }
        switch evidence.category {
        case .cache, .developerArtifacts, .packageManagerData:
            return CNTheme.success
        case .logs, .installerOrArchive:
            return CNTheme.warning
        case .userContent, .cloudDocuments:
            return CNTheme.accent
        case .appSandboxData, .appSupportData, .systemData, .unknown:
            return CNTheme.danger
        }
    }

    private func legend(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(CNL10n.string(title)).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct DiskAIInsightCard: View {
    @EnvironmentObject private var store: AppStore
    @State private var cautionsExpanded = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CNTheme.accent)
                        .frame(width: 38, height: 38)
                        .background(CNTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("本机 AI 深度解读")
                            .font(.headline)
                        Text("Mole 可用时先读取最大的 4 个目录的直接子项，再由你选择的本机模型判断用途、风险和查看优先级。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    if store.localAIIsReady {
                        StatusPill(text: store.localAIModelDisplayName, symbol: "cpu", style: .success)
                    }
                    actionView
                }

                InlineBanner(
                    title: "只读元数据分析",
                    detail: "不读取文件内容，不会勾选或删除项目。高风险目录只能解释用途，并引导你进入下一层或在所属 App 内管理。",
                    kind: .success
                )

                content
            }
        }
    }

    @ViewBuilder
    private var actionView: some View {
        if store.diskAIPhase.isBusy || store.isWorking {
            ProgressView().controlSize(.small)
        } else if store.currentDiskTraversalIsBlocked {
            Button("前往设置页") { store.selection = .settings }
        } else if store.localAIIsReady {
            Button(store.diskAIAnalysis == nil ? "AI 深度分析" : "重新深度分析") {
                Task { await store.analyzeDiskWithLocalAI() }
            }
            .buttonStyle(.borderedProminent)
        } else if store.localAIServiceState.isBusy {
            ProgressView().controlSize(.small)
        } else {
            Button("在设置中连接") { store.selection = .settings }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.diskAIPhase {
        case .collecting:
            Label("正在读取大目录内部构成，这一步可能需要十几秒…", systemImage: "externaldrive.badge.timemachine")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .analyzing:
            Label("所选本机模型正在根据实际子项和体积判断用途与风险…", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .failed(let detail):
            InlineBanner(
                title: "AI 解读没有完成",
                detail: detail,
                kind: .warning,
                actionTitle: "重试"
            ) {
                Task { await store.analyzeDiskWithLocalAI() }
            }
        case .completed:
            if let analysis = store.diskAIAnalysis {
                Divider()
                Text(analysis.summary)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    StatusPill(text: "解读 \(analysis.requestedCount) 项", symbol: "checkmark.circle", style: .success)
                    StatusPill(text: "深入 \(analysis.deepSampledCount) 个目录", symbol: "folder.badge.gearshape", style: .neutral)
                    Text("覆盖 \(CleanNestFormatting.bytes(analysis.coveredBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !analysis.cautions.isEmpty {
                    DisclosureGroup("注意事项（\(analysis.cautions.count)）", isExpanded: $cautionsExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(analysis.cautions.enumerated()), id: \.offset) { _, caution in
                                Label(caution, systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 7)
                    }
                    .font(.caption.weight(.medium))
                }
                AIFeedbackControl(feedback: store.diskAIFeedback) { helpful in
                    store.recordDiskAIFeedback(helpful: helpful)
                }
            }
        case .idle:
            Text("容量扫描已经完成。点击“AI 深度分析”，即可看到大目录的实际主要构成和安全处理建议。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DiskEntryRow: View {
    @EnvironmentObject private var store: AppStore
    let entry: DiskEntry
    let maximumBytes: Int64

    private var fraction: Double {
        guard maximumBytes > 0 else { return 0 }
        return max(0.015, Double(entry.bytes) / Double(maximumBytes))
    }

    private var aiAdvice: DiskAIAdvice? { store.diskAIAdvice(for: entry) }
    private var childContext: DiskAIChildContext? { store.diskAIChildContext(for: entry) }
    private var evidence: DiskEvidenceEntry? { store.diskEvidence(for: entry) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundStyle(entry.isDirectory ? CNTheme.accent : .secondary)
                .frame(width: 28, height: 28)
                .background((entry.isDirectory ? CNTheme.accent : Color.secondary).opacity(0.08), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(entry.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text(CleanNestFormatting.bytes(entry.bytes))
                        .font(.subheadline.weight(.semibold))
                        .monospacedMetric()
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.11))
                        Capsule().fill(CNTheme.accent.opacity(0.72))
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 5)
                Text(entry.url.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let traversal = entry.traversal,
                   !traversal.isCompleteWithinFileSystem {
                    HStack(spacing: 7) {
                        StatusPill(
                            text: traversal.reachedEntryLimit ? "容量为部分结果" : "存在不可读项目",
                            symbol: "exclamationmark.triangle",
                            style: .warning
                        )
                        Text(traversalDetail(traversal))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if entry.traversal == nil {
                    StatusPill(text: "旧索引完整度未知", symbol: "questionmark.circle", style: .warning)
                }
                if let childContext, !childContext.entries.isEmpty {
                    Text(childSummary(childContext))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let evidence {
                    HStack(spacing: 7) {
                        StatusPill(
                            text: evidenceCategoryLabel(evidence.category),
                            symbol: "checkmark.seal",
                            style: .neutral
                        )
                        StatusPill(
                            text: boundaryLabel(evidence.cleanupBoundary),
                            symbol: evidence.cleanupBoundary == .reviewable ? "eye" : "lock.shield",
                            style: boundaryStyle(evidence.cleanupBoundary)
                        )
                        if let growth = evidence.growthBytes, growth != 0 {
                            Text(growth > 0
                                ? "较上次 +\(CleanNestFormatting.bytes(growth))"
                                : "较上次 −\(CleanNestFormatting.bytes(abs(growth)))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(growth > 0 ? CNTheme.warning : CNTheme.success)
                        }
                    }
                    Text(CNL10n.string(evidence.purpose))
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CNL10n.format("来源：%@", CNL10n.string(evidence.provenance)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CNL10n.format("可恢复性：%@", CNL10n.string(evidence.regeneration)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(evidenceSummary(evidence))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let aiAdvice {
                    HStack(spacing: 7) {
                        StatusPill(text: categoryLabel(aiAdvice.category), symbol: "sparkles", style: .neutral)
                        StatusPill(
                            text: verdictLabel(aiAdvice),
                            symbol: verdictSymbol(aiAdvice),
                            style: verdictStyle(aiAdvice)
                        )
                        Text("AI 优先 \(aiAdvice.priority)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(aiAdvice.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(safeHandlingText(aiAdvice))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(safeHandlingColor(aiAdvice))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if entry.isDirectory {
                Button {
                    Task { await store.analyze(entry.url) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(store.diskAIPhase.isBusy || store.isWorking)
                .help("进入并分析")
            } else {
                Button {
                    store.revealInFinder(entry.url)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .help("在 Finder 中显示")
            }
        }
        .padding(.vertical, 10)
        .contextMenu {
            Button("在 Finder 中显示") { store.revealInFinder(entry.url) }
            if entry.isDirectory {
                Button("分析此文件夹") { Task { await store.analyze(entry.url) } }
                    .disabled(store.diskAIPhase.isBusy || store.isWorking)
            }
        }
    }

    private func traversalDetail(_ traversal: FileTreeTraversalEvidence) -> String {
        var parts: [String] = []
        if traversal.reachedEntryLimit, let limit = traversal.entryLimit {
            parts.append("到达 \(limit) 项上限")
        }
        if traversal.unreadableEntryCount > 0 {
            parts.append("\(traversal.unreadableEntryCount) 项不可读")
        }
        if traversal.crossVolumeEntryCount > 0 {
            parts.append("\(traversal.crossVolumeEntryCount) 个其他卷入口已跳过")
        }
        return parts.isEmpty ? "本次文件遍历没有形成完整证据" : parts.joined(separator: " · ")
    }

    private func evidenceCategoryLabel(_ category: DiskAIContentCategory) -> String {
        switch category {
        case .cache: return "下载/运行缓存"
        case .logs: return "日志"
        case .developerArtifacts: return "开发产物"
        case .packageManagerData: return "包管理器数据"
        case .appSandboxData: return "应用沙盒"
        case .appSupportData: return "应用支持数据"
        case .cloudDocuments: return "云端同步文件"
        case .userContent: return "用户内容"
        case .systemData: return "系统数据"
        case .installerOrArchive: return "安装包/归档"
        case .unknown: return "用途未知"
        }
    }

    private func boundaryLabel(_ boundary: DiskAICleanupBoundary) -> String {
        switch boundary {
        case .reviewable: return "可逐项复核"
        case .inspectOnly: return "只可继续查看"
        case .protected: return "受保护"
        }
    }

    private func boundaryStyle(_ boundary: DiskAICleanupBoundary) -> StatusPill.Style {
        switch boundary {
        case .reviewable: return .warning
        case .inspectOnly: return .neutral
        case .protected: return .danger
        }
    }

    private func evidenceSummary(_ evidence: DiskEvidenceEntry) -> String {
        let types = evidence.typeDistribution.prefix(3).map {
            "\(fileKindLabel($0.kind)) \(CleanNestFormatting.bytes($0.allocatedBytes))"
        }.joined(separator: " · ")
        let observed = evidence.observedFileCount > 0
            ? "已抽样 \(evidence.observedFileCount) 个文件" + (evidence.scanWasLimited ? "（达到安全上限）" : "")
            : "未发现可统计文件"
        return types.isEmpty ? observed : "\(observed) · \(types)"
    }

    private func fileKindLabel(_ kind: DiskEvidenceFileKind) -> String {
        switch kind {
        case .image: return "图片"
        case .video: return "视频"
        case .audio: return "音频"
        case .document: return "文档"
        case .archive: return "归档"
        case .installer: return "安装包"
        case .sourceCode: return "源码"
        case .database: return "数据库"
        case .log: return "日志"
        case .other: return "其他"
        }
    }

    private func childSummary(_ context: DiskAIChildContext) -> String {
        let highlights = context.entries.prefix(3).map {
            "\($0.name) \(CleanNestFormatting.bytes($0.bytes))"
        }.joined(separator: "、")
        let suffix = context.totalEntryCount > context.entries.count
            ? "等 \(context.totalEntryCount) 项"
            : ""
        return "实际主要构成：\(highlights)\(suffix)"
    }

    private func categoryLabel(_ category: DiskAIContentCategory) -> String {
        switch category {
        case .cache: return "缓存"
        case .logs: return "日志"
        case .developerArtifacts: return "开发产物"
        case .packageManagerData: return "包管理器数据"
        case .appSandboxData: return "应用沙盒数据"
        case .appSupportData: return "应用支持数据"
        case .cloudDocuments: return "云端同步文件"
        case .userContent: return "用户内容"
        case .systemData: return "系统与应用数据"
        case .installerOrArchive: return "安装包或归档"
        case .unknown: return "用途待确认"
        }
    }

    private func verdictLabel(_ advice: DiskAIAdvice) -> String {
        switch advice.verdict {
        case .likelyReclaimable: return "低风险候选"
        case .review: return advice.risk == .high ? "高风险·先下钻" : "需要逐项确认"
        case .keep: return "建议保留"
        }
    }

    private func verdictSymbol(_ advice: DiskAIAdvice) -> String {
        switch advice.verdict {
        case .likelyReclaimable: return "checkmark.shield"
        case .review: return "eye"
        case .keep: return "lock.shield"
        }
    }

    private func verdictStyle(_ advice: DiskAIAdvice) -> StatusPill.Style {
        switch advice.verdict {
        case .likelyReclaimable: return .success
        case .review: return advice.risk == .high ? .danger : .warning
        case .keep: return .danger
        }
    }

    private func safeHandlingText(_ advice: DiskAIAdvice) -> String {
        switch advice.suggestion {
        case .inspectFurther:
            return "本机安全规则：当前目录只供继续查看，不能作为整体清理目标。"
        case .reviewForCleanup:
            return "本机安全规则：仅作为低风险候选，仍需逐项复核后由你决定。"
        case .cleanInOwnerApp:
            return "本机安全规则：当前目录保持不动，只能在所属 App 的设置中管理。"
        case .keep:
            return "本机安全规则：建议保留，当前目录不会进入清理流程。"
        }
    }

    private func safeHandlingColor(_ advice: DiskAIAdvice) -> Color {
        switch advice.suggestion {
        case .reviewForCleanup: return CNTheme.success
        case .inspectFurther: return CNTheme.warning
        case .cleanInOwnerApp, .keep: return CNTheme.danger
        }
    }
}
