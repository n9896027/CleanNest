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
                            Label(store.diskHasScanned ? "重新分析" : "开始分析", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isWorking)
                    }
                }

                if store.engine == nil {
                    InlineBanner(
                        title: "正在使用原生扫描",
                        detail: "安装 Mole CLI 后可获得更快的分析与大文件索引；当前结果仍只在本机生成。",
                        kind: .info,
                        actionTitle: "设置引擎"
                    ) {
                        store.selection = .settings
                    }
                }

                pathBar

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
                        store.selection = .settings
                    }
                }

                if !store.diskHasScanned {
                    EmptyPanel(
                        symbol: "chart.pie",
                        title: "选择一个位置开始",
                        detail: "默认从你的主目录分析。你也可以选择项目文件夹或外接磁盘。",
                        actionTitle: "分析主目录"
                    ) {
                        Task { await store.analyze() }
                    }
                } else if let report = store.diskReport {
                    HStack(spacing: 12) {
                        MetricCard(label: "已分析", value: CleanNestFormatting.bytes(report.totalBytes), detail: report.root.path, symbol: "folder", tint: CNTheme.accent)
                        MetricCard(label: "当前层级", value: "\(report.entries.count) 项", detail: "按占用从大到小排列", symbol: "list.bullet.rectangle", tint: CNTheme.success)
                        MetricCard(label: "文件计数", value: report.totalFiles > 0 ? "\(report.totalFiles)" : "—", detail: "由分析引擎报告", symbol: "doc.on.doc", tint: CNTheme.warning)
                    }

                    DiskAIInsightCard()

                    SurfaceCard(title: "空间分布", symbol: "chart.bar.xaxis") {
                        if report.entries.isEmpty {
                            Text("这个位置没有可显示的内容，或当前权限不足。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 18)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(report.entries.enumerated()), id: \.element.id) { index, entry in
                                    DiskEntryRow(entry: entry, maximumBytes: largestBytes)
                                    if index < report.entries.count - 1 { Divider().padding(.leading, 42) }
                                }
                            }
                        }
                    }

                    InlineBanner(
                        title: "浏览页保持只读",
                        detail: "首版不会从任意文件夹直接删除内容。请先在 Finder 中确认，或使用“清理空间”里的安全范围。",
                        kind: .success
                    )
                }
            }
            .padding(CNTheme.pagePadding)
        }
    }

    private var pathBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "internaldrive").foregroundStyle(CNTheme.accent)
            Text(store.diskRoot.path)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                store.revealInFinder(store.diskRoot)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
            if store.diskRoot != FileManager.default.homeDirectoryForCurrentUser {
                Button("主目录") {
                    Task { await store.analyze(FileManager.default.homeDirectoryForCurrentUser) }
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(CNTheme.divider, lineWidth: 0.7))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择要分析的文件夹"
        panel.prompt = "分析此文件夹"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = store.diskRoot
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.analyze(url) }
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
                        Text("Mole 可用时先读取最大的 4 个目录的直接子项，再由 Gemma 判断用途、风险和查看优先级。")
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
            Label("Gemma 正在根据实际子项和体积判断用途与风险…", systemImage: "sparkles")
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
                if let childContext, !childContext.entries.isEmpty {
                    Text(childSummary(childContext))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
