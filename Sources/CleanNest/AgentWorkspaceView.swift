import SwiftUI
import CleanNestCore

struct AgentWorkspaceView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Agent 工作区",
                    subtitle: "看清 Codex 与 Claude 留下的会话、缓存、运行时与异常增长；只读元数据，不读会话正文。",
                    eyebrow: "占用账本 · 只在本机"
                ) {
                    headerActions
                }

                if case .failed(let message) = store.agentWorkspacePhase {
                    InlineBanner(
                        title: "Agent 工作区扫描没有完成",
                        detail: message,
                        kind: .warning,
                        actionTitle: "重试"
                    ) {
                        Task { await store.refreshAgentWorkspace() }
                    }
                }

                if let snapshot = store.agentWorkspaceSnapshot {
                    if snapshot.detectedAgents.isEmpty {
                        EmptyPanel(
                            symbol: "folder.badge.questionmark",
                            title: "没有发现 Codex 或 Claude 工作痕迹",
                            detail: "CleanNest 只检查它们的默认本机目录；本次没有扫描其他 Agent，也没有遍历你的项目文件。"
                        )
                    } else {
                        storageLedger(snapshot)
                        if !snapshot.alerts.isEmpty { anomalyPanel(snapshot.alerts) }
                        agentInventory(snapshot.detectedAgents)
                        recoveryPreview(snapshot)
                    }

                    InlineBanner(
                        title: snapshot.openFileProbeSucceeded ? "活跃会话已锁定" : "活跃文件确认不完整",
                        detail: snapshot.diagnostic,
                        kind: snapshot.openFileProbeSucceeded ? .success : .warning,
                        actionTitle: "诊断详情"
                    ) {
                        store.lastTechnicalDetail = snapshot.diagnostic
                        store.showTechnicalDetail()
                    }
                } else if store.agentWorkspacePhase.isScanning {
                    loadingPanel
                } else {
                    EmptyPanel(
                        symbol: "sparkle.magnifyingglass",
                        title: "尚未建立 Agent 占用账本",
                        detail: "首次扫描只读取文件大小、数量、时间与打开状态。"
                    )
                }
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
        .task {
            if store.agentWorkspaceSnapshot == nil {
                await store.refreshAgentWorkspace()
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 9) {
            StatusPill(
                text: store.agentWorkspacePhase.isScanning ? "正在采样" : "只读监测",
                symbol: store.agentWorkspacePhase.isScanning ? "arrow.triangle.2.circlepath" : "lock.shield",
                style: store.agentWorkspacePhase.isScanning ? .neutral : .success
            )
            Button {
                Task { await store.refreshAgentWorkspace() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.agentWorkspacePhase.isScanning)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityHint("重新读取 Agent 文件元数据，不会修改文件")
        }
    }

    private var loadingPanel: some View {
        SurfaceCard(prominence: .prominent, tint: CNTheme.cyan) {
            HStack(spacing: 15) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 5) {
                    Text("正在建立占用账本")
                        .font(.headline)
                    Text(store.agentWorkspaceDiagnostic)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func storageLedger(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        SurfaceCard(prominence: .prominent, tint: ledgerTint(snapshot)) {
            ContentSectionHeader(
                "当前占用账本",
                detail: scanTiming(snapshot),
                symbol: "externaldrive.fill.badge.timemachine",
                tint: ledgerTint(snapshot)
            ) {
                StatusPill(
                    text: snapshot.isComplete ? "元数据完整" : "部分路径不完整",
                    symbol: snapshot.isComplete ? "checkmark.seal" : "exclamationmark.triangle",
                    style: snapshot.isComplete ? .success : .warning
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 32) {
                    ledgerPrimaryMetric(snapshot)
                    ledgerSecondaryMetrics(snapshot)
                }
                VStack(alignment: .leading, spacing: 17) {
                    ledgerPrimaryMetric(snapshot)
                    ledgerSecondaryMetrics(snapshot)
                }
            }

            AgentAllocationBar(agents: snapshot.detectedAgents)

            VStack(spacing: 8) {
                ForEach(snapshot.detectedAgents) { agent in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(providerTint(agent.provider))
                            .frame(width: 8, height: 8)
                        Text(agent.provider.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text(CleanNestFormatting.bytes(agent.allocatedBytes))
                            .font(.subheadline)
                            .monospacedDigit()
                        Text("· \(agent.fileCount.formatted()) 个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if agent.activeFileCount > 0 {
                            Label("\(agent.activeFileCount) 个活跃文件已保护", systemImage: "lock.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(CNTheme.success)
                        }
                        Spacer(minLength: 8)
                    }
                }
            }
        }
    }

    private func ledgerPrimaryMetric(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CleanNestFormatting.bytes(snapshot.allocatedBytes))
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .tracking(-0.8)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("目录分配块占用，不等于最终 APFS 可释放量")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func ledgerSecondaryMetrics(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        HStack(spacing: 24) {
            ledgerSmallMetric(
                value: snapshot.activeFileCount.formatted(),
                label: "活跃文件",
                detail: "已锁定"
            )
            ledgerSmallMetric(
                value: CleanNestFormatting.bytes(snapshot.previewBytes),
                label: "回收预览",
                detail: "未执行"
            )
            ledgerSmallMetric(
                value: snapshot.alerts.filter { $0.level >= .warning }.count.formatted(),
                label: "异常线索",
                detail: "需复核"
            )
        }
    }

    private func ledgerSmallMetric(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.caption.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func anomalyPanel(_ alerts: [AgentWorkspaceAlert]) -> some View {
        let highest = alerts.map(\.level).max() ?? .info
        return SurfaceCard(
            title: "异常增长与风险线索",
            symbol: highest == .critical ? "exclamationmark.octagon.fill" : "waveform.path.ecg",
            tint: alertTint(highest)
        ) {
            VStack(spacing: 0) {
                ForEach(Array(alerts.prefix(5).enumerated()), id: \.element.id) { index, alert in
                    AgentWorkspaceAlertRow(alert: alert)
                    if index < min(alerts.count, 5) - 1 { Divider().padding(.leading, 41) }
                }
            }
            if alerts.count > 5 {
                Text("另有 \(alerts.count - 5) 条较低优先级线索，可在各 Agent 分组中查看。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func agentInventory(_ agents: [AgentWorkspaceAgentSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            ContentSectionHeader(
                "会话、缓存与运行时",
                detail: "按真实用途分组，不把整个 Agent 目录当作垃圾",
                symbol: "list.bullet.rectangle.portrait",
                tint: CNTheme.cyan
            )
            ForEach(agents) { agent in
                AgentLedgerPanel(agent: agent)
            }
        }
    }

    private func recoveryPreview(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        let regenerable = snapshot.detectedAgents.flatMap(\.artifacts)
            .filter { $0.disposition == .regenerable }
            .reduce(Int64(0)) { $0 + $1.previewBytes }
        let archive = snapshot.detectedAgents.flatMap(\.artifacts)
            .filter { $0.disposition == .review || $0.disposition == .protected }
            .reduce(Int64(0)) { $0 + $1.previewBytes }
        return SurfaceCard(
            title: "0.6.3 回收计划预览",
            symbol: "checklist.checked",
            tint: CNTheme.mint
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    previewLane(
                        title: "可再生数据",
                        value: CleanNestFormatting.bytes(regenerable),
                        detail: "缓存、临时文件与日志中，已静置且未被打开的部分。",
                        symbol: "arrow.triangle.2.circlepath",
                        tint: CNTheme.cyan
                    )
                    previewLane(
                        title: "归档复核",
                        value: CleanNestFormatting.bytes(archive),
                        detail: "超过 30 天的关闭会话、备份与生成资源；活跃文件已排除。",
                        symbol: "archivebox",
                        tint: CNTheme.violet
                    )
                }
                VStack(spacing: 12) {
                    previewLane(
                        title: "可再生数据",
                        value: CleanNestFormatting.bytes(regenerable),
                        detail: "缓存、临时文件与日志中，已静置且未被打开的部分。",
                        symbol: "arrow.triangle.2.circlepath",
                        tint: CNTheme.cyan
                    )
                    previewLane(
                        title: "归档复核",
                        value: CleanNestFormatting.bytes(archive),
                        detail: "超过 30 天的关闭会话、备份与生成资源；活跃文件已排除。",
                        symbol: "archivebox",
                        tint: CNTheme.violet
                    )
                }
            }

            Label(
                "0.6.2 只生成计划，不会归档、移到废纸篓或结束进程。预览数字不是 APFS 实际释放承诺。",
                systemImage: "lock.shield"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func previewLane(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CNIconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(value).font(.headline).monospacedDigit()
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.14), lineWidth: 0.7))
    }

    private func ledgerTint(_ snapshot: AgentWorkspaceSnapshot) -> Color {
        alertTint(snapshot.alerts.map(\.level).max() ?? .info)
    }

    private func scanTiming(_ snapshot: AgentWorkspaceSnapshot) -> String {
        let current = snapshot.capturedAt.formatted(date: .omitted, time: .standard)
        guard let previous = snapshot.previousCapturedAt else {
            return "\(current) 建立首个基线；之后才能比较增长"
        }
        return "\(current) 采样 · 上次基线 \(previous.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct AgentAllocationBar: View {
    let agents: [AgentWorkspaceAgentSnapshot]

    private var total: Double {
        max(1, Double(agents.reduce(Int64(0)) { $0 + $1.allocatedBytes }))
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(agents) { agent in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(providerTint(agent.provider))
                        .frame(width: max(8, proxy.size.width * Double(agent.allocatedBytes) / total))
                        .accessibilityLabel("\(agent.provider.displayName) \(CleanNestFormatting.bytes(agent.allocatedBytes))")
                }
            }
        }
        .frame(height: 11)
        .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct AgentWorkspaceAlertRow: View {
    let alert: AgentWorkspaceAlert

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: alertSymbol(alert.level))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(alertTint(alert.level))
                .frame(width: 30, height: 30)
                .background(alertTint(alert.level).opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(alert.title).font(.subheadline.weight(.semibold))
                    if let provider = alert.provider {
                        Text(provider.displayName.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(alert.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 10)
    }
}

private struct AgentLedgerPanel: View {
    let agent: AgentWorkspaceAgentSnapshot
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    CNIconTile(
                        symbol: agent.provider == .codex ? "chevron.left.forwardslash.chevron.right" : "command",
                        tint: providerTint(agent.provider),
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(agent.provider.displayName)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                            if agent.activeFileCount > 0 {
                                StatusPill(
                                    text: "\(agent.activeFileCount) 个活跃文件",
                                    symbol: "lock.fill",
                                    style: .success
                                )
                            }
                        }
                        Text("\(agent.artifacts.count) 类工作痕迹 · \(agent.fileCount.formatted()) 个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(CleanNestFormatting.bytes(agent.allocatedBytes))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(agent.previewBytes > 0 ? "\(CleanNestFormatting.bytes(agent.previewBytes)) 进入预览" : "没有可执行动作")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(agent.provider.displayName) 工作痕迹")
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")

            if isExpanded {
                Divider().padding(.vertical, 14)
                VStack(spacing: 0) {
                    ForEach(Array(agent.artifacts.enumerated()), id: \.element.id) { index, artifact in
                        AgentArtifactRow(artifact: artifact)
                        if index < agent.artifacts.count - 1 { Divider().padding(.leading, 43) }
                    }
                }
                if !agent.diagnostics.isEmpty {
                    Label(agent.diagnostics.joined(separator: " "), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(CNTheme.warning)
                        .padding(.top, 12)
                }
            }
        }
        .cnCard(tint: providerTint(agent.provider))
    }
}

private struct AgentArtifactRow: View {
    let artifact: AgentWorkspaceArtifact

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                artifactIcon
                artifactDescription
                Spacer(minLength: 12)
                artifactMetrics
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    artifactIcon
                    artifactDescription
                }
                artifactMetrics
            }
        }
        .padding(.vertical, 12)
    }

    private var artifactIcon: some View {
        Image(systemName: artifactSymbol(artifact.kind))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(dispositionTint(artifact.disposition))
            .frame(width: 31, height: 31)
            .background(dispositionTint(artifact.disposition).opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
    }

    private var artifactDescription: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(artifact.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                StatusPill(
                    text: artifact.disposition.displayName,
                    symbol: dispositionSymbol(artifact.disposition),
                    style: dispositionPillStyle(artifact.disposition)
                )
            }
            Text(pathSummary(artifact.sourcePaths))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let reason = artifact.protectionReasons.first {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(artifact.disposition == .protected ? CNTheme.success : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if artifact.largestFileBytes >= 256 * 1_024 * 1_024 {
                Text("最大单文件 \(CleanNestFormatting.bytes(artifact.largestFileBytes))")
                    .font(.caption2)
                    .foregroundStyle(CNTheme.warning)
            }
        }
    }

    private var artifactMetrics: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(CleanNestFormatting.bytes(artifact.allocatedBytes))
                .font(.headline)
                .monospacedDigit()
            Text("\(artifact.fileCount.formatted()) 文件 · \(CleanNestFormatting.age(from: artifact.latestModificationDate))写入")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if artifact.previewBytes > 0 {
                Text("其中 \(CleanNestFormatting.bytes(artifact.previewBytes)) 仅供后续复核")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CNTheme.violet)
            }
        }
        .frame(minWidth: 170, alignment: .trailing)
    }
}

private func providerTint(_ provider: AgentWorkspaceProvider) -> Color {
    switch provider {
    case .codex: return CNTheme.cyan
    case .claude: return Color(red: 0.86, green: 0.52, blue: 0.32)
    }
}

private func alertTint(_ level: AgentWorkspaceAlertLevel) -> Color {
    switch level {
    case .info: return CNTheme.accent
    case .warning: return CNTheme.warning
    case .critical: return CNTheme.danger
    }
}

private func alertSymbol(_ level: AgentWorkspaceAlertLevel) -> String {
    switch level {
    case .info: return "info.circle.fill"
    case .warning: return "exclamationmark.triangle.fill"
    case .critical: return "exclamationmark.octagon.fill"
    }
}

private func artifactSymbol(_ kind: AgentArtifactKind) -> String {
    switch kind {
    case .activeSessions: return "text.bubble"
    case .archivedSessions: return "archivebox"
    case .backups: return "clock.arrow.circlepath"
    case .generatedMedia: return "photo.on.rectangle"
    case .caches: return "arrow.triangle.2.circlepath"
    case .temporaryFiles: return "timer"
    case .logs: return "doc.text.magnifyingglass"
    case .runtime: return "shippingbox"
    case .virtualMachines: return "cube.transparent"
    case .memoryAndPlans: return "brain.head.profile"
    case .stateAndIndexes: return "cylinder.split.1x2"
    case .credentials: return "key.fill"
    case .unknown: return "questionmark.folder"
    }
}

private func dispositionTint(_ disposition: AgentArtifactDisposition) -> Color {
    switch disposition {
    case .protected: return CNTheme.success
    case .keep: return CNTheme.accent
    case .review: return CNTheme.violet
    case .regenerable: return CNTheme.cyan
    case .unknown: return CNTheme.warning
    }
}

private func dispositionSymbol(_ disposition: AgentArtifactDisposition) -> String {
    switch disposition {
    case .protected: return "lock.fill"
    case .keep: return "hand.raised.fill"
    case .review: return "archivebox"
    case .regenerable: return "arrow.triangle.2.circlepath"
    case .unknown: return "questionmark"
    }
}

private func dispositionPillStyle(_ disposition: AgentArtifactDisposition) -> StatusPill.Style {
    switch disposition {
    case .protected: return .success
    case .keep: return .neutral
    case .review: return .neutral
    case .regenerable: return .neutral
    case .unknown: return .warning
    }
}

private func pathSummary(_ paths: [String]) -> String {
    guard let first = paths.first else { return "路径未知" }
    let suffix = paths.count > 1 ? "  +\(paths.count - 1) 个路径" : ""
    return abbreviatedHomePath(first) + suffix
}

private func abbreviatedHomePath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    let components = URL(fileURLWithPath: path).pathComponents
    if components.count >= 4, components[1] == "Users" {
        return "~/" + components.dropFirst(3).joined(separator: "/")
    }
    return path
}
