import SwiftUI
import CleanNestCore

struct AgentRelatedSoftwareInventorySection: View {
    let software: [AgentRelatedSoftwareInstallation]
    let catalog: AgentRuleCatalog

    var body: some View {
        SurfaceCard(prominence: .standard, tint: CNTheme.cyan) {
            ContentSectionHeader(
                "附带组件与相关工具",
                detail: "按实际功能分类，不计入 Agent 客户端数量；本组只读",
                symbol: "puzzlepiece.extension",
                tint: CNTheme.cyan
            ) {
                StatusPill(
                    text: CNL10n.format("%@ 个相关软件", String(software.count)),
                    symbol: "eye",
                    style: .neutral
                )
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 290), spacing: 14)], spacing: 14) {
                ForEach(software) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            AgentRelatedSoftwareIcon(software: item, size: 46)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayName).font(.headline)
                                Text(CNL10n.string(item.role.displayName))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        if let owner = ownerName(for: item) {
                            Text(CNL10n.format("所属产品：%@", owner))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.application.bundleIdentifier ?? "—")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        Label(item.application.url.path, systemImage: "folder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text(signatureSummary(item.signature))
                            .font(.caption2)
                            .foregroundStyle(item.signature.isValid ? CNTheme.success : CNTheme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.application.url])
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
            Text("签名验证回答“是不是这个开发者签的”，产品分类回答“它是什么”，两者不能互相替代。这些软件仍保留在盘点中，但不会在 Agent 工作区获得卸载权限。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func ownerName(for item: AgentRelatedSoftwareInstallation) -> String? {
        guard let id = item.owningProductID else { return nil }
        return catalog.desktopProducts.first { $0.id == id }?.displayName
    }

    private func signatureSummary(_ evidence: AgentDesktopSignatureEvidence) -> String {
        if evidence.isValid, let team = evidence.teamIdentifier {
            return CNL10n.format("Apple 信任链有效 · Team ID %@", team)
        }
        return CNL10n.string("签名完整性或 Apple 信任链未通过；不影响本组的功能分类")
    }
}
