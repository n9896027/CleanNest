import SwiftUI
import CleanNestCore

struct CleanupScanIssuesCard: View {
    @EnvironmentObject private var store: AppStore
    let issues: [CleanupScanIssue]

    private let displayLimit = 100

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CNIconTile(symbol: "magnifyingglass", tint: CNTheme.warning, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("扫描保护项逐路径复核")
                            .font(.headline)
                        Text("这些路径没有生成清理候选；请补充权限或重新扫描，不能直接重试移动。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        text: CNL10n.format("%d 条路径证据", issues.count),
                        symbol: "location",
                        style: .warning
                    )
                }

                Divider()

                ForEach(Array(issues.prefix(displayLimit))) { issue in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(issue.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            StatusPill(text: title(for: issue.reason), symbol: "shield", style: .warning)
                            Spacer()
                            Button("在 Finder 中显示") { store.revealInFinder(issue.url) }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                        Text(displayPath(issue.url))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(issue.guidance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            if issue.reason == .unreadable {
                                Button("打开权限设置") { store.openFullDiskAccessSettings() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                            Button {
                                Task { await store.scanCleanup() }
                            } label: {
                                Label("重新扫描", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(store.isWorking)
                        }
                    }
                    .padding(10)
                    .background(CNTheme.warning.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                }

                if issues.count > displayLimit {
                    Text(CNL10n.format("仅显示前 %d 条；完整数量保留在本次扫描证据中。", displayLimit))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func displayPath(_ url: URL) -> String {
        url.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path,
            with: "~"
        )
    }

    private func title(for reason: CleanupScanSkipReason) -> String {
        switch reason {
        case .cloudPlaceholder: return CNL10n.string("云端占位文件")
        case .symbolicLink: return CNL10n.string("符号链接边界")
        case .packageBoundary: return CNL10n.string("App 或包边界")
        case .unreadable: return CNL10n.string("路径不可读取")
        case .depthLimit: return CNL10n.string("达到目录深度上限")
        case .unsafeRoot: return CNL10n.string("根目录不安全")
        case .fileLimit: return CNL10n.string("达到文件数量上限")
        case .hashLimit: return CNL10n.string("达到哈希检查上限")
        }
    }
}
