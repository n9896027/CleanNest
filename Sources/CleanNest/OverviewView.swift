import SwiftUI
import CleanNestCore

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(
                    title: "总览",
                    subtitle: "先看清空间去了哪里，再决定要不要处理。所有分析都在本机完成。"
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
                        detail: "状态与磁盘分析需要 Mole CLI。你可以在 App 内免费安装，不必打开终端。",
                        kind: .warning,
                        actionTitle: "去设置"
                    ) {
                        store.selection = .settings
                    }
                }

                storageWorkspace
                nextActions
                activityAndLearning
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
    }

    private var usedBytes: Int64 {
        max(0, store.diskTotalBytes - store.diskFreeBytes)
    }

    private var storageWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            ContentSectionHeader(
                "启动磁盘",
                detail: "只读容量快照",
                symbol: "internaldrive.fill",
                tint: CNTheme.cyan
            ) {
                StatusPill(text: "只读概览", symbol: "eye", style: .neutral)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 38) {
                    storageNarrative
                    Spacer(minLength: 14)
                    StorageRing(used: usedBytes, total: store.diskTotalBytes)
                }
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 20) {
                        StorageRing(used: usedBytes, total: store.diskTotalBytes)
                        storageNarrative
                    }
                }
            }

            factStrip
        }
        .cnHeroPanel()
    }

    private var storageNarrative: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(CNL10n.format("还有 %@ 可用", CleanNestFormatting.bytes(store.diskFreeBytes)))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.72)
                .monospacedMetric()
            Text(CNL10n.format(
                "在 %@ 的磁盘中，已使用 %@。先扫描可清理内容，再逐项确认。",
                CleanNestFormatting.bytes(store.diskTotalBytes),
                CleanNestFormatting.bytes(usedBytes)
            ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 590, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    Task {
                        await store.scanCleanup()
                        store.selection = .cleanup
                    }
                } label: {
                    Label(
                        CNL10n.string(store.cleanupHasScanned ? "重新扫描" : "扫描可清理内容"),
                        systemImage: "sparkle.magnifyingglass"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isWorking)
                .shadow(color: CNTheme.accent.opacity(0.22), radius: 10, y: 4)

                Text("不会自动删除")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var factStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                fact(
                    title: "建议查看",
                    value: store.cleanupHasScanned ? CleanNestFormatting.bytes(store.cleanupPotentialBytes) : "尚未扫描",
                    detail: store.cleanupHasScanned ? "执行前可逐项取消" : "先建立可清理证据",
                    tint: CNTheme.warning
                )
                fact(
                    title: "系统状态",
                    value: store.systemSnapshot?.healthScore.map { CNL10n.format("%d 分", $0) } ?? "等待检查",
                    detail: "只读探测，不制造焦虑",
                    tint: CNTheme.success
                )
                fact(
                    title: "本机学习",
                    value: CNL10n.format("%d 项偏好", store.evolutionMemory.learnedCleanupCount),
                    detail: "只来自你的明确判断",
                    tint: CNTheme.violet
                )
            }
            VStack(spacing: 13) {
                fact(title: "建议查看", value: store.cleanupHasScanned ? CleanNestFormatting.bytes(store.cleanupPotentialBytes) : "尚未扫描", detail: "执行前可逐项取消", tint: CNTheme.warning)
                fact(title: "系统状态", value: store.systemSnapshot?.healthScore.map { CNL10n.format("%d 分", $0) } ?? "等待检查", detail: "只读探测，不制造焦虑", tint: CNTheme.success)
                fact(title: "本机学习", value: CNL10n.format("%d 项偏好", store.evolutionMemory.learnedCleanupCount), detail: "只来自你的明确判断", tint: CNTheme.violet)
            }
        }
    }

    private func fact(title: String, value: String, detail: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Capsule()
                .fill(tint)
                .frame(width: 3, height: 34)
                .shadow(color: tint.opacity(0.35), radius: 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(CNL10n.string(title))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CNL10n.string(value))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedMetric()
                Text(CNL10n.string(detail))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.075), lineWidth: 0.65)
        )
    }

    private var nextActions: some View {
        VStack(alignment: .leading, spacing: 13) {
            ContentSectionHeader(
                "下一步",
                detail: "选择一个明确任务，CleanNest 不会替你自动删除",
                symbol: "arrow.right.circle",
                tint: CNTheme.accent
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    actionTile(
                        title: "看清最大文件夹",
                        detail: "从主目录开始定位空间占用",
                        symbol: "chart.pie",
                        tint: CNTheme.cyan
                    ) {
                        store.selection = .analyze
                        Task { if !store.diskHasScanned { await store.analyze() } }
                    }
                    actionTile(
                        title: "管理已安装 App",
                        detail: "预览本体与精确匹配的相关文件",
                        symbol: "app.dashed",
                        tint: CNTheme.violet
                    ) {
                        store.selection = .applications
                        Task { if !store.applicationsHaveScanned { await store.scanApplications() } }
                    }
                    actionTile(
                        title: "运行系统维护",
                        detail: "按任务执行，不做含糊的一键加速",
                        symbol: "wrench.and.screwdriver",
                        tint: CNTheme.mint
                    ) {
                        store.selection = .maintenance
                    }
                }
                VStack(spacing: 10) {
                    actionTile(
                    title: "看清最大文件夹",
                    detail: "从主目录开始定位空间占用",
                    symbol: "chart.pie",
                    tint: CNTheme.cyan
                ) {
                    store.selection = .analyze
                    Task { if !store.diskHasScanned { await store.analyze() } }
                }
                    actionTile(
                    title: "管理已安装 App",
                    detail: "预览 App 本体与精确匹配的相关文件",
                    symbol: "app.dashed",
                    tint: CNTheme.violet
                ) {
                    store.selection = .applications
                    Task { if !store.applicationsHaveScanned { await store.scanApplications() } }
                }
                    actionTile(
                    title: "运行系统维护",
                    detail: "按任务执行，不做含糊的一键加速",
                    symbol: "wrench.and.screwdriver",
                    tint: CNTheme.mint
                ) {
                    store.selection = .maintenance
                }
                }
            }
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

    private var activityAndLearning: some View {
        SurfaceCard(title: "本机动态", symbol: "waveform.path", prominence: .quiet, tint: CNTheme.mint) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    recentActivity
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Divider().frame(height: 50)
                    learningAction
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 14) {
                    recentActivity
                    Divider()
                    learningAction
                }
            }
        }
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
        } else {
            HStack(alignment: .top, spacing: 11) {
                CNIconTile(symbol: "clock", tint: Color(nsColor: .secondaryLabelColor), size: 31)
                VStack(alignment: .leading, spacing: 4) {
                    Text("还没有操作记录").font(.subheadline.weight(.medium))
                    Text("完成一次清理或维护后，这里会显示结果和恢复方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var learningAction: some View {
        Button {
            store.selection = .evolution
        } label: {
            HStack(spacing: 11) {
                CNIconTile(symbol: "sparkles.rectangle.stack", tint: CNTheme.violet, size: 31)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.evolutionMemory.learnedCleanupCount > 0 ? "查看已经学会的偏好" : "建立第一条本机偏好")
                        .font(.subheadline.weight(.medium))
                    Text("可检查、撤销或随时清空，不上传文件内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
                        .lineLimit(2)
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
                Text("已使用")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 148, height: 148)
        .padding(7)
        .accessibilityLabel("磁盘已使用 \(Int((fraction * 100).rounded())) 百分比")
    }
}
