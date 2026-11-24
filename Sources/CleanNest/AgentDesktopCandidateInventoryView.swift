import SwiftUI
import CleanNestCore

struct AgentDesktopCandidateInventorySection: View {
    let candidates: [AgentDesktopCandidate]

    var body: some View {
        SurfaceCard(prominence: .standard, tint: CNTheme.warning) {
            ContentSectionHeader(
                "待核验的独立客户端",
                detail: "仅限独立 AI / Agent 产品；身份或卸载验收未通过",
                symbol: "questionmark.app.dashed",
                tint: CNTheme.warning
            ) {
                StatusPill(
                    text: CNL10n.format("%@ 个只读", String(candidates.count)),
                    symbol: "eye",
                    style: .warning
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                ForEach(candidates) { candidate in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            AgentDesktopCandidateIcon(candidate: candidate, size: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.displayName)
                                    .font(.headline)
                                Text(CNL10n.format("声明的产品：%@", candidate.expectedProductName))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        Text(candidate.application.bundleIdentifier ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Label(candidate.application.url.path, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(issueDetail(candidate.issue))
                            .font(.caption)
                            .foregroundStyle(CNTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "Signing ID: " + (candidate.signingIdentifier ?? "—"))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(verbatim: "Team ID: " + (candidate.teamIdentifier ?? "—"))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        HStack {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([candidate.application.url])
                            } label: {
                                Label("在 Finder 中显示", systemImage: "arrow.right.circle")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(CNTheme.accent)
                            Spacer()
                            Label("只读，不提供卸载", systemImage: "lock.shield")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                    .padding(16)
                    .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CNTheme.divider, lineWidth: 0.7))
                }
            }
            Text("这些条目没有卸载权限。请从官方渠道重新安装或等待样本验收；不会仅凭 App 名称放行。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func issueDetail(_ issue: AgentDesktopCandidateIssue) -> String {
        switch issue {
        case .invalidSignature:
            return CNL10n.string("签名完整性或 Apple 信任链未通过，不能作为已验证客户端管理。")
        case .unexpectedSigner:
            return CNL10n.string("签名者或 Team ID 与已核验身份不符。")
        case .pendingOfficialSample:
            return CNL10n.string("尚未完成官方完整样本与卸载验收。")
        }
    }
}
