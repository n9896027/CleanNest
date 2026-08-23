import SwiftUI
import CleanNestCore

struct ActivityView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "活动记录",
                    subtitle: "记录完成、跳过与失败；只有明确可恢复的操作才会显示恢复入口。"
                ) {
                    Button {
                        store.openTrash()
                    } label: {
                        Label("打开废纸篓", systemImage: "trash")
                    }
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
