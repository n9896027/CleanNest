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
                exportMessage = "只清除了 CleanNest 的本机活动列表；废纸篓、扫描结果与 Mole 日志未改变。"
                exportFailed = false
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("这项操作不能从 CleanNest 内撤销，但不会删除文件或清空废纸篓。")
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
