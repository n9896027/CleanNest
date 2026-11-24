import SwiftUI
import CleanNestCore

struct UpdateCheckView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsDownloadConfirmation = false

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

            if let notice = store.appUpdateNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(CNTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
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
                    .frame(maxHeight: 110)
                }
                .cnInsetPanel()
                .padding(.top, 18)
            }

            if case .updateAvailable(_, let release) = store.appUpdateState,
               release.installerPackage != nil {
                downloadStatusPanel
                    .padding(.top, 16)
            }

            Spacer(minLength: 18)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "network")
                Text("自动检查可在设置中关闭。检查只读取公开 Release；只有你确认后才会下载 PKG，不会发送文件清单或扫描结果。GitHub 可看到当前 App 版本、IP 等常规网络信息。")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 16)

            Divider()
                .padding(.horizontal, -24)

            HStack(spacing: 10) {
                if !store.appUpdateState.isChecking {
                    Button("重新检查") {
                        Task { await store.checkForUpdates() }
                    }
                    .disabled(store.appUpdateDownloadState.isBusy)
                }

                Spacer()

                if showsGitHubButton {
                    Button(gitHubButtonTitle) {
                        store.openLatestCleanNestRelease()
                    }
                }

                primaryAction
            }
            .padding(.top, 16)
        }
        .padding(24)
        .frame(width: 560)
        .frame(minHeight: 360)
        .confirmationDialog(
            "下载并安装 CleanNest？",
            isPresented: $showsDownloadConfirmation,
            titleVisibility: .visible
        ) {
            Button("下载并校验") {
                store.downloadAndPrepareUpdate()
            }
            Button("取消", role: .cancel) { }
        } message: {
            if let package = store.appUpdateState.release?.installerPackage {
                Text(CNL10n.format(
                    "将从 CleanNest 官方 GitHub Release 下载 %@ 安装包，核对 SHA-256 与 Developer ID Installer 签名，并进行 macOS Gatekeeper 系统评估。校验通过后仍需你点击“打开安装器”，并在 macOS 安装器中最终确认。",
                    CleanNestFormatting.bytes(package.byteCount)
                ))
            }
        }
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

    @ViewBuilder
    private var downloadStatusPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.appUpdateDownloadState {
            case .idle:
                Label("官方 PKG 安装包已就绪，等待你确认下载。", systemImage: "shippingbox")
                    .foregroundStyle(.secondary)
            case .downloading(let package):
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(CNL10n.format(
                        "正在下载官方安装包（%@）…",
                        CleanNestFormatting.bytes(package.byteCount)
                    ))
                }
            case .verifying:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在校验 SHA-256、Developer ID Installer 签名与 Gatekeeper 系统评估…")
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .readyToInstall:
                Label("摘要、Developer ID Installer 签名及 Gatekeeper 系统评估已通过。点击“打开安装器”后，由 macOS 安装器继续。", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(CNTheme.success)
                    .fixedSize(horizontal: false, vertical: true)
            case .installerOpened:
                Label("macOS 安装器已打开。请在安装器中核对版本并完成系统确认。", systemImage: "arrow.up.forward.app.fill")
                    .foregroundStyle(CNTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message, _, _):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(CNTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cnInsetPanel()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if case .updateAvailable(_, let release) = store.appUpdateState,
           release.installerPackage != nil {
            switch store.appUpdateDownloadState {
            case .idle:
                Button("下载并安装…") {
                    showsDownloadConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .failed(_, _, let packageURL):
                if packageURL != nil {
                    Button("重试打开安装器") {
                        store.openDownloadedUpdateInstaller()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button("重新下载并校验…") {
                        showsDownloadConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            case .downloading:
                Button("正在下载…") { }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            case .verifying:
                Button("正在校验…") { }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
            case .readyToInstall:
                Button("打开安装器") {
                    store.openDownloadedUpdateInstaller()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            case .installerOpened:
                Button("重新打开安装器") {
                    store.openDownloadedUpdateInstaller()
                }
                .buttonStyle(.borderedProminent)
            }
        } else if !showsGitHubButton {
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
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
            if release.installerPackage != nil {
                return CNL10n.format(
                    "当前版本 %@，最新正式版本 %@。自动检查不会下载；只有你确认后才会获取并校验安装包。",
                    currentVersion,
                    release.version.description
                )
            }
            return CNL10n.format(
                "当前版本 %@，最新正式版本 %@。这个 Release 没有符合要求的 PKG，请前往 GitHub 核对说明并手动下载。",
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
        if case .updateAvailable(_, let release) = store.appUpdateState,
           release.installerPackage != nil {
            return CNL10n.string("发布页")
        }
        if case .updateAvailable = store.appUpdateState {
            return CNL10n.string("打开 GitHub 下载")
        }
        return CNL10n.string("查看 GitHub 发布页")
    }
}
