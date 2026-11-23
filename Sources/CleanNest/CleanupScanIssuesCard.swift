import SwiftUI
import CleanNestCore

struct CleanupScanIssuesCard: View {
    @EnvironmentObject private var store: AppStore
    let issues: [CleanupScanIssue]

    @State private var expandedGroups = Set<CleanupScanSkipReason>()

    private var groups: [CleanupScanIssueGroup] {
        CleanupScanIssuePresentation.groups(for: issues)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                CNIconTile(symbol: "tray.full", tint: CNTheme.warning, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("未纳入本次清理")
                        .font(.headline)
                    Text("这些不是清理候选，也不会被处理。按原因查看路径证据。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    text: CNL10n.format("%d 条路径证据", issues.count),
                    symbol: "location",
                    style: .neutral
                )
            }

            if !groups.isEmpty {
                Divider()

                VStack(spacing: 10) {
                    ForEach(groups) { group in
                        issueGroup(group)
                    }
                }
            }
        }
    }

    private func issueGroup(_ group: CleanupScanIssueGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.reason)
        let isBoundary = group.disposition == .safetyBoundary

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpanded {
                    expandedGroups.remove(group.reason)
                } else {
                    expandedGroups.insert(group.reason)
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: isBoundary ? "shield.lefthalf.filled" : "exclamationmark.circle")
                        .foregroundStyle(isBoundary ? CNTheme.cyan : CNTheme.warning)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 7) {
                            Text(title(for: group.reason))
                                .font(.subheadline.weight(.semibold))
                            StatusPill(
                                text: CNL10n.string(isBoundary ? "安全边界" : "需要处理"),
                                symbol: nil,
                                style: isBoundary ? .neutral : .warning
                            )
                        }
                        Text(CNL10n.string(group.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(CNL10n.format("%d 条", group.issues.count))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CNL10n.format("%@，%d 条", title(for: group.reason), group.issues.count))
            .accessibilityValue(CNL10n.string(isExpanded ? "已展开" : "已折叠"))

            if isExpanded {
                Divider().padding(.vertical, 10)

                if group.allowsAuthorizationAndRescan {
                    HStack(spacing: 8) {
                        Button("打开权限设置") { store.openFullDiskAccessSettings() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button {
                            Task { await store.scanCleanup() }
                        } label: {
                            Label("授权后重新扫描", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(store.isWorking)
                    }
                    .padding(.bottom, 10)
                }

                LazyVStack(spacing: 0) {
                    ForEach(Array(group.issues.enumerated()), id: \.element.id) { index, issue in
                        issueRow(issue)
                        if index < group.issues.count - 1 {
                            Divider().padding(.leading, 24)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            (isBoundary ? CNTheme.cyan : CNTheme.warning).opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private func issueRow(_ issue: CleanupScanIssue) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(issue.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(displayPath(issue.url))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button("在 Finder 中显示") { store.revealInFinder(issue.url) }
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
        .padding(.vertical, 7)
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
