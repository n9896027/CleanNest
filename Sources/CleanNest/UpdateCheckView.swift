import SwiftUI
import CleanNestCore

struct UpdateCheckView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("检查更新")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.bottom, 22)

            HStack(alignment: .top, spacing: 18) {
                statusIcon
                VStack(alignment: .leading, spacing: 8) {
                    Text(statusTitle)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let release = store.appUpdateState.release,
               !release.notes.isEmpty,
               shouldShowReleaseNotes {
                VStack(alignment: .leading, spacing: 8) {
                    Text("版本说明")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(release.notes)
                            .font(.caption)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 130)
                }
                .cnInsetPanel()
                .padding(.top, 20)
            }

            Spacer(minLength: 22)

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "network")
                Text("仅在你点击检查时访问 GitHub；会发送当前 App 版本，GitHub 可看到 IP 等常规网络信息，但不会收到文件清单或扫描结果。")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 18)

            Divider()
                .padding(.horizontal, -24)

            HStack(spacing: 10) {
                if !store.appUpdateState.isChecking {
                    Button("重新检查") {
                        Task { await store.checkForUpdates() }
                    }
                }

                Spacer()

                if showsGitHubButton {
                    Button(gitHubButtonTitle) {
                        store.openLatestCleanNestRelease()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("完成") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 330)
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusTint.opacity(0.12))
            if store.appUpdateState.isChecking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: statusSymbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(statusTint)
            }
        }
        .frame(width: 52, height: 52)
    }

    private var statusTitle: String {
        switch store.appUpdateState {
        case .idle, .checking:
            return CNL10n.string("正在检查 GitHub 最新版本…")
        case .noPublishedRelease:
            return CNL10n.string("GitHub 尚未发布正式版本")
        case .updateAvailable(_, let release):
            return CNL10n.format("发现新版本 %@", release.tagName)
        case .upToDate:
            return CNL10n.string("已经是最新正式版本")
        case .localVersionAhead:
            return CNL10n.string("当前版本比最新 Release 更新")
        case .failed:
            return CNL10n.string("暂时无法检查更新")
        }
    }

    private var statusDetail: String {
        switch store.appUpdateState {
        case .idle:
            return AppMetadata.displayVersion
        case .checking(let currentVersion):
            return CNL10n.format("当前版本 %@，正在读取公开的 GitHub Release。", currentVersion)
        case .noPublishedRelease(let currentVersion):
            return CNL10n.format(
                "当前版本为 %@。仓库目前没有正式 Release；维护者发布后，这里会自动参与版本比较。",
                currentVersion
            )
        case .updateAvailable(let currentVersion, let release):
            return CNL10n.format(
                "当前版本 %@，最新正式版本 %@。CleanNest 不会自动替换 App，请前往 GitHub 核对说明后下载。",
                currentVersion,
                release.version.description
            )
        case .upToDate(let currentVersion, _):
            return CNL10n.format("当前版本 %@ 已与 GitHub 最新正式版本一致。", currentVersion)
        case .localVersionAhead(let currentVersion, let release):
            return CNL10n.format(
                "当前版本 %@，GitHub 最新正式版本 %@。你可能正在使用开发构建。",
                currentVersion,
                release.version.description
            )
        case .failed(_, let message):
            return message
        }
    }

    private var statusSymbol: String {
        switch store.appUpdateState {
        case .updateAvailable: return "arrow.down.circle.fill"
        case .upToDate: return "checkmark.seal.fill"
        case .localVersionAhead: return "hammer.circle.fill"
        case .noPublishedRelease: return "shippingbox"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle, .checking: return "arrow.triangle.2.circlepath"
        }
    }

    private var statusTint: Color {
        switch store.appUpdateState {
        case .updateAvailable: return CNTheme.accent
        case .upToDate: return CNTheme.success
        case .localVersionAhead, .noPublishedRelease: return CNTheme.warning
        case .failed: return CNTheme.danger
        case .idle, .checking: return CNTheme.accent
        }
    }

    private var shouldShowReleaseNotes: Bool {
        if case .updateAvailable = store.appUpdateState { return true }
        return false
    }

    private var showsGitHubButton: Bool {
        switch store.appUpdateState {
        case .updateAvailable, .noPublishedRelease, .localVersionAhead:
            return true
        default:
            return false
        }
    }

    private var gitHubButtonTitle: String {
        if case .updateAvailable = store.appUpdateState {
            return CNL10n.string("打开 GitHub 下载")
        }
        return CNL10n.string("查看 GitHub 发布页")
    }
}
