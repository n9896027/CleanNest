import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CleanNestCore

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmingClear = false
    @State private var confirmingTotalsReset = false
    @State private var exportMessage: String?
    @State private var exportFailed = false
    @State private var searchText = ""
    @State private var categoryScope = ActivityCategoryScope.all
    @State private var outcomeScope = ActivityOutcomeScope.all
    @State private var timeWindow = ActivityTimeWindow.all
    @State private var selectedEntry: ActivityEntry?

    private enum ActivityCategoryScope: String, CaseIterable, Identifiable {
        case all
        case cleanup
        case applicationUninstall
        case other

        var id: String { rawValue }
        var category: ActivityEntry.Category? {
            switch self {
            case .all: return nil
            case .cleanup: return .cleanup
            case .applicationUninstall: return .applicationUninstall
            case .other: return .other
            }
        }
        var label: String {
            switch self {
            case .all: return "全部类型"
            case .cleanup: return "清理"
            case .applicationUninstall: return "App 卸载"
            case .other: return "维护与其他"
            }
        }
    }

    private enum ActivityOutcomeScope: String, CaseIterable, Identifiable {
        case all
        case success
        case partial
        case failed

        var id: String { rawValue }
        var outcome: ActivityEntry.Outcome? {
            switch self {
            case .all: return nil
            case .success: return .success
            case .partial: return .partial
            case .failed: return .failed
            }
        }
        var label: String {
            switch self {
            case .all: return "全部结果"
            case .success: return "完成"
            case .partial: return "部分完成"
            case .failed: return "未完成"
            }
        }
    }

    private var filteredActivities: [ActivityEntry] {
        ActivityFilter(
            query: searchText,
            category: categoryScope.category,
            outcome: outcomeScope.outcome,
            timeWindow: timeWindow
        ).apply(to: store.activities)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "活动记录",
                    subtitle: "记录完成、跳过与失败；只有明确可恢复的操作才会显示恢复入口。"
                ) {
                    HStack(spacing: 8) {
                        Button {
                            exportActivities()
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                        }
                        .disabled(store.activities.isEmpty)
                        Button("清空…", role: .destructive) {
                            confirmingClear = true
                        }
                        .disabled(store.activities.isEmpty)
                        Button {
                            store.openTrash()
                        } label: {
                            Label("打开废纸篓", systemImage: "trash")
                        }
                    }
                }

                if let exportMessage {
                    InlineBanner(
                        title: exportFailed ? "活动记录未能导出" : "活动记录已导出",
                        detail: exportMessage,
                        kind: exportFailed ? .warning : .success
                    )
                }

                if store.activityLifetimeTotals.productiveOperations > 0 || !store.activities.isEmpty {
                    ActivitySummaryPanel(
                        totals: store.activityLifetimeTotals,
                        detailCount: store.activities.count,
                        onReset: { confirmingTotalsReset = true }
                    )
                }

                if store.activities.isEmpty {
                    EmptyPanel(
                        symbol: "clock.arrow.circlepath",
                        title: store.activityLifetimeTotals.productiveOperations > 0
                            ? "活动明细已清空"
                            : "还没有操作记录",
                        detail: store.activityLifetimeTotals.productiveOperations > 0
                            ? "累计成果仍保留；新的清理、卸载或维护结果会继续出现在这里。"
                            : "完成一次清理、卸载或维护后，这里会显示结果。"
                    )
                } else {
                    filterBar

                    SurfaceCard {
                        if filteredActivities.isEmpty {
                            EmptyPanel(
                                symbol: "line.3.horizontal.decrease.circle",
                                title: "没有符合条件的记录",
                                detail: "调整搜索、类型、结果或时间范围；不会修改原始记录。"
                            )
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(filteredActivities.enumerated()), id: \.element.id) { index, entry in
                                    Button { selectedEntry = entry } label: {
                                        ActivityRow(entry: entry)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        CNL10n.format(
                                            "%@。%@。%@。%@",
                                            entry.title,
                                            entry.detail,
                                            entry.outcome.rawValue,
                                            entry.date.formatted(date: .abbreviated, time: .shortened)
                                        )
                                    )
                                    .accessibilityHint("打开这条记录的完整详情")
                                    if index < filteredActivities.count - 1 { Divider().padding(.leading, 45) }
                                }
                            }
                        }
                    }
                }

                InlineBanner(
                    title: "操作记录保存在本机",
                    detail: "CleanNest 的记录位于 Application Support；Mole 自身的文件操作日志仍保留在 ~/Library/Logs/mole。",
                    kind: .info,
                    actionTitle: store.lastTechnicalDetail.isEmpty ? nil : "诊断详情"
                ) {
                    store.showTechnicalDetail()
                }
            }
            .padding(CNTheme.pagePadding)
        }
        .confirmationDialog(
            "清空所有 CleanNest 活动明细？",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("清空记录", role: .destructive) {
                store.clearActivities()
                exportMessage = "活动明细已清空；累计成果仍保留，废纸篓、扫描结果与 Mole 日志未改变。"
                exportFailed = false
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("这项操作不能从 CleanNest 内撤销，但累计成果不会归零；也不会删除文件或清空废纸篓。")
        }
        .confirmationDialog(
            "把累计成果归零？",
            isPresented: $confirmingTotalsReset,
            titleVisibility: .visible
        ) {
            Button("累计成果归零", role: .destructive) {
                store.resetActivityLifetimeTotals()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只会重置累计空间、清理项目、卸载 App 和有成果操作计数；活动明细、文件与废纸篓保持不变。")
        }
        .sheet(item: $selectedEntry) { entry in
            ActivityDetailView(entry: entry)
        }
        .onAppear { presentRequestedDetailIfNeeded() }
        .onChange(of: store.requestedActivityDetailID) {
            presentRequestedDetailIfNeeded()
        }
    }

    private var filterBar: some View {
        SurfaceCard(prominence: .quiet, tint: CNTheme.cyan) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { filterControls }
                VStack(alignment: .leading, spacing: 10) { filterControls }
            }
            Text("显示 \(filteredActivities.count) / \(store.activities.count) 条；筛选只改变当前显示。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var filterControls: some View {
        TextField("搜索标题或说明", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 220)
        Picker("类型", selection: $categoryScope) {
            ForEach(ActivityCategoryScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .frame(width: 150)
        Picker("结果", selection: $outcomeScope) {
            ForEach(ActivityOutcomeScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .frame(width: 140)
        Picker("时间", selection: $timeWindow) {
            Text("全部时间").tag(ActivityTimeWindow.all)
            Text("最近 24 小时").tag(ActivityTimeWindow.day)
            Text("最近 7 天").tag(ActivityTimeWindow.week)
            Text("最近 30 天").tag(ActivityTimeWindow.month)
        }
        .frame(width: 150)
    }

    private func presentRequestedDetailIfNeeded() {
        guard let id = store.requestedActivityDetailID,
              let entry = store.activities.first(where: { $0.id == id }) else { return }
        selectedEntry = entry
        store.requestedActivityDetailID = nil
    }

    private func exportActivities() {
        let panel = NSSavePanel()
        panel.title = CNL10n.string("导出活动记录")
        panel.prompt = CNL10n.string("导出")
        panel.nameFieldStringValue = "CleanNest-Activity-\(Date.now.formatted(.iso8601.year().month().day()))"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportActivities(to: url)
            exportMessage = "已写入你选择的位置；JSON 可能包含操作项目名称，请在公开分享前检查。"
            exportFailed = false
        } catch {
            exportMessage = error.localizedDescription
            exportFailed = true
        }
    }
}

private struct ActivitySummaryPanel: View {
    let totals: ActivityLifetimeTotals
    let detailCount: Int
    let onReset: () -> Void

    private struct Definition: Identifiable {
        let label: String
        let value: String
        let detail: String
        let symbol: String
        let tint: Color

        var id: String { label }
    }

    private var definitions: [Definition] {
        [
            Definition(
                label: "累计处理空间",
                value: CleanNestFormatting.bytes(totals.processedBytes),
                detail: "独立累计，不随明细清空",
                symbol: "internaldrive",
                tint: CNTheme.cyan
            ),
            Definition(
                label: "清理项目",
                value: totals.cleanedItems.formatted(),
                detail: "已成功移入废纸篓",
                symbol: "sparkles",
                tint: CNTheme.mint
            ),
            Definition(
                label: "卸载 App",
                value: totals.uninstalledApplications.formatted(),
                detail: "App 本体已移入废纸篓",
                symbol: "app.badge.checkmark",
                tint: CNTheme.violet
            ),
            Definition(
                label: "有成果操作",
                value: totals.productiveOperations.formatted(),
                detail: "完成或部分完成",
                symbol: "checkmark.seal",
                tint: CNTheme.success
            )
        ]
    }

    var body: some View {
        SurfaceCard(
            title: "累计成果",
            symbol: "chart.bar.xaxis",
            prominence: .prominent,
            tint: CNTheme.mint
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    statisticTiles
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 10
                ) {
                    statisticTiles
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Label(
                    "累计成果与 \(detailCount) 条活动明细分开保存；移入废纸篓不等于已释放 APFS 空间。",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("累计归零…", role: .destructive, action: onReset)
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private var statisticTiles: some View {
        ForEach(definitions) { definition in
            ActivityStatisticTile(
                label: definition.label,
                value: definition.value,
                detail: definition.detail,
                symbol: definition.symbol,
                tint: definition.tint
            )
        }
    }
}

private struct ActivityStatisticTile: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                Text(CNL10n.string(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .tracking(-0.2)
                .monospacedMetric()
            Text(CNL10n.string(detail))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 170, maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
        .padding(12)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 0.7)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CNL10n.format("只读统计，%@：%@。%@", label, value, detail))
    }
}

private struct ActivityDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: ActivityEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 13) {
                CNIconTile(symbol: entry.outcome.symbol, tint: Color.outcome(entry.outcome), size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(CNL10n.string(entry.title))
                        .font(.title2.weight(.semibold))
                    Text(entry.date.formatted(date: .long, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    text: entry.outcome.rawValue,
                    symbol: nil,
                    style: entry.outcome == .success ? .success : (entry.outcome == .partial ? .warning : .danger)
                )
            }

            Text(entry.detail)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { detailFacts }
                VStack(spacing: 10) { detailFacts }
            }

            InlineBanner(
                title: "这是一条本机结果记录",
                detail: "它能说明当时发生了什么，但不会重新执行操作。需要恢复文件时，请先在废纸篓或对应功能页核对当前状态。",
                kind: .info
            )

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 640, maxWidth: 720)
    }

    @ViewBuilder
    private var detailFacts: some View {
        detailFact("类型", categoryLabel, symbol: "tray.full")
        detailFact("项目", entry.affectedItems.formatted(), symbol: "number")
        detailFact("记录体积", CleanNestFormatting.bytes(entry.bytes), symbol: "internaldrive")
        detailFact("记录 ID", String(entry.id.uuidString.prefix(8)), symbol: "number.square")
    }

    private func detailFact(_ label: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            CNIconTile(symbol: symbol, tint: CNTheme.cyan, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.tertiary)
                Text(value).font(.caption.weight(.semibold)).textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var categoryLabel: String {
        switch entry.effectiveCategory {
        case .cleanup: return "清理"
        case .applicationUninstall: return "App 卸载"
        case .other: return "维护与其他"
        }
    }
}

private struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: entry.outcome.symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.outcome(entry.outcome))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(CNL10n.string(entry.title))
                        .font(.subheadline.weight(.semibold))
                    StatusPill(
                        text: entry.outcome.rawValue,
                        symbol: nil,
                        style: entry.outcome == .success ? .success : (entry.outcome == .partial ? .warning : .danger)
                    )
                }
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    if entry.affectedItems > 0 { Text("\(entry.affectedItems) 项") }
                    if entry.bytes > 0 { Text(CleanNestFormatting.bytes(entry.bytes)) }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }
}
