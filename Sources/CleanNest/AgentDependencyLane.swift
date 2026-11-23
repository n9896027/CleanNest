import SwiftUI
import CleanNestCore

struct AgentDependencyLane: View {
    let provider: AgentWorkspaceProvider
    let graph: AgentDependencyGraphSnapshot
    let rule: AgentProviderRule?
    @State private var isExpanded = false

    private var nodes: [AgentDependencyNode] {
        graph.nodes(for: provider).filter { $0.kind != .agent }
    }

    private var agent: AgentDependencyNode? {
        graph.nodes(for: provider).first { $0.kind == .agent }
    }

    private var connectedModels: [AgentDependencyNode] {
        let providerIDs = Set(nodes.map(\.id))
        let destinationIDs = Set(graph.edges.filter {
            $0.relation == .connectsToModel && providerIDs.contains($0.sourceID)
        }.map(\.destinationID))
        return graph.nodes.filter { destinationIDs.contains($0.id) }
    }

    private var evidenceSummary: String {
        if nodes.isEmpty {
            return rule?.verification == .detectionOnly ? "尚待验证" : "未发现运行证据"
        }
        if !connectedModels.isEmpty { return "已连接本地模型" }
        if nodes.contains(where: { $0.kind == .process && $0.state == .running }) {
            return "运行中 · 未观察到模型连接"
        }
        return CNL10n.format("%@ 项本机证据", String(describing: nodes.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                providerBlock
                Spacer(minLength: 8)
                Text(evidenceSummary)
                    .font(.caption)
                    .foregroundStyle(stateTint)
                    .multilineTextAlignment(.trailing)
            }

            if nodes.isEmpty {
                evidenceStrip
                    .padding(.top, 2)
            } else {
                Button(isExpanded ? "收起证据" : "查看证据") {
                    withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
                }
                .font(.caption.weight(.medium))
                .buttonStyle(.plain)
                .foregroundStyle(CNTheme.accent)
                .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            }

            if !nodes.isEmpty, isExpanded {
                evidenceStrip
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(agent?.state == .notDetected ? 0.62 : 1)
        .accessibilityElement(children: .combine)
    }

    private var providerBlock: some View {
        HStack(spacing: 9) {
            AgentProviderIcon(
                provider: provider,
                rule: rule,
                size: 27,
                fallbackTint: stateTint
            )
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: stateSymbol)
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 12, height: 12)
                    .background(stateTint, in: Circle())
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(provider.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(agent?.state.displayName ?? "未检查")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 142, alignment: .leading)
    }

    @ViewBuilder
    private var evidenceStrip: some View {
        if nodes.isEmpty {
            HStack(spacing: 7) {
                Image(systemName: rule?.verification == .detectionOnly ? "questionmark.diamond" : "minus.circle")
                Text(rule?.verification == .detectionOnly
                    ? "适配器待验证：没有可靠路径，不会猜测扫描"
                    : "没有发现应用、数据、进程或守护证据")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(nodes.prefix(8)) { node in
                        dependencyChip(node)
                    }
                    ForEach(connectedModels) { model in
                        HStack(spacing: 5) {
                            Image(systemName: "bolt.horizontal.circle.fill")
                            Text(model.title)
                                .lineLimit(1)
                            Text("TCP 实测")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(CNTheme.mint)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(CNTheme.mint.opacity(0.10), in: Capsule())
                    }
                }
            }
        }
    }

    private func dependencyChip(_ node: AgentDependencyNode) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol(for: node.kind))
            Text(node.title)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(node.state == .running ? CNTheme.mint : .secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            (node.state == .running ? CNTheme.mint : Color.secondary).opacity(0.08),
            in: Capsule()
        )
        .help("\(node.kind.displayName)：\(node.detail)")
    }

    private var stateSymbol: String {
        switch agent?.state {
        case .running: return "wave.3.right.circle.fill"
        case .detected: return "checkmark.circle.fill"
        case .unverified: return "questionmark.diamond.fill"
        case .notDetected, .none: return "circle.dashed"
        }
    }

    private var stateTint: Color {
        switch agent?.state {
        case .running: return CNTheme.mint
        case .detected: return CNTheme.accent
        case .unverified: return CNTheme.warning
        case .notDetected, .none: return .secondary
        }
    }

    private func symbol(for kind: AgentDependencyNodeKind) -> String {
        switch kind {
        case .agent: return "sparkles"
        case .application: return "app"
        case .data: return "externaldrive"
        case .process: return "cpu"
        case .supervisor: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .endpoint: return "network"
        case .localModel: return "shippingbox"
        }
    }
}
