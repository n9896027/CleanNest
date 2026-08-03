import SwiftUI
import CleanNestCore

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "让这台 Mac 保持从容",
                    subtitle: "先查看，再决定。扫描和清理都在本机完成。"
                ) {
                    if store.demoMode {
                        StatusPill(text: "演示数据", symbol: "sparkles", style: .warning)
                    } else {
                        StatusPill(
                            text: store.engine == nil ? "部分功能待设置" : "本地运行",
                            symbol: store.engine == nil ? "exclamationmark.triangle" : "lock.shield",
                            style: store.engine == nil ? .warning : .success
                        )
                    }
                }

                if store.engine == nil {
                    InlineBanner(
                        title: "连接开源清理引擎",
                        detail: "状态与磁盘分析需要 Mole CLI。你可以在 App 内免费安装，不必打开终端。",
                        kind: .warning,
                        actionTitle: "去设置"
                    ) {
                        store.selection = .settings
                    }
                }

                storageHero

                LazyVGrid(columns: columns, spacing: 12) {
                    MetricCard(
                        label: "可用空间",
                        value: CleanNestFormatting.bytes(store.diskFreeBytes),
                        detail: "启动磁盘当前可用",
                        symbol: "internaldrive",
                        tint: CNTheme.accent
                    )
                    MetricCard(
                        label: "建议查看",
                        value: store.cleanupHasScanned ? CleanNestFormatting.bytes(store.cleanupPotentialBytes) : "尚未扫描",
                        detail: store.cleanupHasScanned ? "执行前可逐项取消" : "不会自动删除",
                        symbol: "sparkles",
                        tint: CNTheme.warning
                    )
                    MetricCard(
                        label: "系统状态",
                        value: store.systemSnapshot?.healthScore.map { "\($0)" } ?? "—",
                        detail: store.systemSnapshot == nil ? "等待本地状态" : "只读检查，不制造焦虑",
                        symbol: "waveform.path.ecg",
                        tint: CNTheme.success
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    quickActions
                    recentActivity
                }
            }
            .padding(CNTheme.pagePadding)
        }
    }

    private var storageHero: some View {
        SurfaceCard {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("启动磁盘")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(CleanNestFormatting.bytes(max(0, store.diskTotalBytes - store.diskFreeBytes)))
                            .font(.system(size: 32, weight: .semibold, design: .rounded))
                            .monospacedMetric()
                        Text("已使用")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    CapacityBar(
                        used: max(0, store.diskTotalBytes - store.diskFreeBytes),
                        total: store.diskTotalBytes
                    )
                    .frame(maxWidth: 520)
                    Text("共 \(CleanNestFormatting.bytes(store.diskTotalBytes)) · 仍有 \(CleanNestFormatting.bytes(store.diskFreeBytes)) 可用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        Task {
                            await store.scanCleanup()
                            store.selection = .cleanup
                        }
                    } label: {
                        Label(store.cleanupHasScanned ? "重新扫描" : "扫描可清理内容", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(store.isWorking)

                    Text("只扫描，不会自动更改文件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var quickActions: some View {
        SurfaceCard(title: "快捷入口", symbol: "bolt") {
            VStack(spacing: 0) {
                quickActionRow(
                    title: "查看最大文件夹",
                    detail: "从主目录开始浏览空间占用",
                    symbol: "chart.pie"
                ) {
                    store.selection = .analyze
                    Task { if !store.diskHasScanned { await store.analyze() } }
                }
                Divider().padding(.leading, 42)
                quickActionRow(
                    title: "管理已安装 App",
                    detail: "预览本体与精确匹配的相关文件",
                    symbol: "app.dashed"
                ) {
                    store.selection = .applications
                    Task { if !store.applicationsHaveScanned { await store.scanApplications() } }
                }
                Divider().padding(.leading, 42)
                quickActionRow(
                    title: "运行系统维护",
                    detail: "按任务执行，不做含糊的一键加速",
                    symbol: "wrench.and.screwdriver"
                ) {
                    store.selection = .maintenance
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func quickActionRow(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(CNTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(CNTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }

    private var recentActivity: some View {
        SurfaceCard(title: "最近活动", symbol: "clock.arrow.circlepath") {
            if let recent = store.activities.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: recent.outcome.symbol)
                            .foregroundStyle(Color.outcome(recent.outcome))
                        Text(recent.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(recent.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(recent.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if recent.bytes > 0 {
                        Text(CleanNestFormatting.bytes(recent.bytes))
                            .font(.title3.weight(.semibold))
                            .monospacedMetric()
                    }
                    Button("查看全部记录") { store.selection = .activity }
                        .buttonStyle(.link)
                }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("还没有操作记录")
                        .font(.subheadline.weight(.medium))
                    Text("完成一次清理或维护后，这里会显示结果和恢复方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
