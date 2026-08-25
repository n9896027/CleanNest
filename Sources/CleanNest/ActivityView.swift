import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CleanNestCore

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmingClear = false
    @State private var exportMessage: String?
    @State private var exportFailed = false

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

                if store.activities.isEmpty {
                    EmptyPanel(
                        symbol: "clock.arrow.circlepath",
                        title: "还没有操作记录",
                        detail: "完成一次清理、卸载或维护后，这里会显示结果。"
                    )
                } else {
                    ActivitySummaryPanel(
                        statistics: ActivityStatistics(entries: store.activities)
                    )

                    SurfaceCard {
                        VStack(spacing: 0) {
                            ForEach(Array(store.activities.enumerated()), id: \.element.id) { index, entry in
                                ActivityRow(entry: entry)
                                if index < store.activities.count - 1 { Divider().padding(.leading, 45) }
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
            "清空所有 CleanNest 活动记录？",
            isPresented: $confirmingClear,
            titleVisibility: .visible
        ) {
            Button("清空记录", role: .destructive) {
                store.clearActivities()
                exportMessage = "活动列表与累计成果统计已清空；废纸篓、扫描结果与 Mole 日志未改变。"
                exportFailed = false
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("这项操作不能从 CleanNest 内撤销，累计成果统计也会归零；但不会删除文件或清空废纸篓。")
        }
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
    let statistics: ActivityStatistics

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
                value: CleanNestFormatting.bytes(statistics.processedBytes),
                detail: "来自清理与卸载记录",
                symbol: "internaldrive",
                tint: CNTheme.cyan
            ),
            Definition(
                label: "清理项目",
                value: statistics.cleanedItems.formatted(),
                detail: "已成功移入废纸篓",
                symbol: "sparkles",
                tint: CNTheme.mint
            ),
            Definition(
                label: "卸载 App",
                value: statistics.uninstalledApplications.formatted(),
                detail: "App 本体已移入废纸篓",
                symbol: "app.badge.checkmark",
                tint: CNTheme.violet
            ),
            Definition(
                label: "有成果操作",
                value: statistics.productiveOperations.formatted(),
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

            Label(
                CNL10n.format(
                    "根据仍保留的 %d 条活动记录统计；移入废纸篓不等于已释放 APFS 空间，清空记录后统计归零。",
                    statistics.recordCount
                ),
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityLabel(CNL10n.format("%@：%@。%@", label, value, detail))
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
