import SwiftUI
import CleanNestCore

struct AgentDesktopInventorySection: View {
    let installations: [AgentDesktopInstallation]
    let isRefreshing: Bool
    let uninstall: (AgentDesktopInstallation) -> Void

    var body: some View {
        SurfaceCard(prominence: .prominent, tint: CNTheme.accent) {
            ContentSectionHeader(
                "本机 AI / Agent 客户端",
                detail: "只列独立客户端；Bundle ID、有效签名和开发者团队均已核实",
                symbol: "desktopcomputer",
                tint: CNTheme.accent
            ) {
                StatusPill(
                    text: isRefreshing ? "正在刷新" : "独立于工作区扫描",
                    symbol: isRefreshing ? "arrow.triangle.2.circlepath" : "checkmark.shield",
                    style: isRefreshing ? .neutral : .success
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                ForEach(installations) { installation in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            AgentDesktopProductIcon(installation: installation, size: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(installation.displayName)
                                    .font(.headline)
                                Text(CNL10n.format("版本 %@ · Build %@", installation.application.version ?? CNL10n.string("未知"), installation.application.buildVersion ?? CNL10n.string("未知")))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(installation.bundleIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Label(installation.application.url.path, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(CNL10n.format("签名团队 %@ · 此副本单独管理", installation.teamIdentifier))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([installation.application.url])
                            } label: {
                                Label("在 Finder 中显示", systemImage: "arrow.right.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(CNTheme.accent)
                            Spacer()
                            Button("卸载 Agent…") {
                                uninstall(installation)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .font(.caption)
                    }
                    .padding(16)
                    .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CNTheme.divider, lineWidth: 0.7))
                }
            }
            Text("只卸载你选择的安装副本。云端账户、机器人、浏览器记录、共享容器及无法证明归属的内容不在操作范围内。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
