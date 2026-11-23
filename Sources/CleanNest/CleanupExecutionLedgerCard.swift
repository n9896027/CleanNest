import SwiftUI
import CleanNestCore

struct CleanupExecutionLedgerCard: View {
    let snapshot: CleanupExecutionLedgerSnapshot
    let diagnostic: String?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CNIconTile(symbol: "list.bullet.clipboard", tint: CNTheme.accent, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("清理执行账本与恢复").font(.headline)
                        Text("候选体积、实际移入量、即时 APFS 变化和清空后的最终观测分别记录。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        text: CNL10n.format("%d 次执行", snapshot.records.count),
                        symbol: "number",
                        style: .neutral
                    )
                }
                if let diagnostic {
                    InlineBanner(title: "账本需要复核", detail: diagnostic, kind: .warning)
                }
                ForEach(Array(snapshot.records.prefix(5))) { record in
                    CleanupExecutionRecordView(record: record)
                }
            }
        }
    }
}

private struct CleanupExecutionRecordView: View {
    @EnvironmentObject private var store: AppStore
    let record: CleanupExecutionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(CNL10n.format("执行 %@", record.id))
                    .font(.caption.monospaced())
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(record.isComplete ? "已记录完成" : "中断或未完成")
                    .font(.caption)
                    .foregroundColor(record.isComplete ? .secondary : .orange)
            }
            CleanupReconciliationFacts(record: record)
            Text("最终数值只在记录中的废纸篓项目已消失后生成；它包含同期系统变化，不作独占归因。")
                .font(.caption2).foregroundStyle(.tertiary)
            Button("复核最终空间") { store.reconcileCleanupExecution(recordID: record.id) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(!record.isComplete)
            Divider()
            ForEach(Array(record.items.prefix(20))) { item in
                CleanupExecutionItemRow(recordID: record.id, item: item)
            }
            if record.items.count > 20 {
                Text(CNL10n.format("本次还有 %d 项保留在持久化账本中。", record.items.count - 20))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(11)
        .background(CNTheme.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CleanupReconciliationFacts: View {
    let record: CleanupExecutionRecord

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { facts }
            VStack(alignment: .leading, spacing: 5) { facts }
        }
    }

    @ViewBuilder
    private var facts: some View {
        fact("候选体积", CleanNestFormatting.bytes(record.candidateBytes))
        fact("已确认移入", CleanNestFormatting.bytes(record.movedBytes))
        fact("即时 APFS 变化", byteDelta(record.immediateAPFSFreeBytesDelta))
        fact("清空后最终观测", byteDelta(record.finalAPFSFreeBytesDelta))
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.tertiary)
            Text(value).font(.caption.weight(.semibold)).monospacedMetric()
        }
    }

    private func byteDelta(_ value: Int64?) -> String {
        guard let value else { return CNL10n.string("未知／待复核") }
        return (value > 0 ? "+" : "") + CleanNestFormatting.bytes(value)
    }
}

private struct CleanupExecutionItemRow: View {
    @EnvironmentObject private var store: AppStore
    let recordID: String
    let item: CleanupExecutionItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(item.name).font(.subheadline.weight(.medium)).lineLimit(1)
                Text(statusTitle).font(.caption).foregroundStyle(statusColor)
                Spacer()
                if item.status == .movedToTrash || item.status == .restoreFailed {
                    restoreButton
                }
            }
            Text(displayPath(item.sourceURL))
                .font(.caption2.monospaced()).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            if let trashURL = item.trashURL {
                Text(CNL10n.format("实际废纸篓目标：%@", displayPath(trashURL)))
                    .font(.caption2.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            if let error = item.errorDescription {
                Text(error).font(.caption2).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .background(CNTheme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }

    private var restoreButton: some View {
        Button {
            Task { await store.restoreCleanupExecutionItem(recordID: recordID, itemID: item.id) }
        } label: {
            if store.cleanupRestoringItemID == item.id {
                ProgressView().controlSize(.small)
            } else {
                Label("恢复原位置", systemImage: "arrow.uturn.backward")
            }
        }
        .buttonStyle(.bordered).controlSize(.small)
        .disabled(store.isWorking || store.cleanupRestoringItemID != nil)
    }

    private var statusTitle: String {
        switch item.status {
        case .pending: return CNL10n.string("中断待核对")
        case .movedToTrash: return CNL10n.string("已确认在废纸篓")
        case .failed: return CNL10n.string("未移动")
        case .indeterminate: return CNL10n.string("结果不确定")
        case .restored: return CNL10n.string("已恢复")
        case .restoreFailed: return CNL10n.string("恢复未成功")
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .movedToTrash, .restored: return .green
        case .failed, .indeterminate, .restoreFailed, .pending: return .orange
        }
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }
}
