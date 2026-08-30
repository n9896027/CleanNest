import AppKit
import SwiftUI
import CleanNestCore
import CleanNestMutation

struct AgentWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var presentation: AgentWorkspacePresentationState
    @State private var showingRecoveryConfirmation = false
    @State private var showingArchiveSuggestions = false
    @State private var nativeCleanupRequest: NativeDeveloperStorageEntry?
    @State private var showingNativeTools = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: pageTitle,
                    subtitle: pageSubtitle,
                    eyebrow: showingNativeTools ? "原生 dry-run · 只在本机" : "占用账本 · 变化 · 活跃保护"
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
                    if showingNativeTools {
                        nativeToolCenter
                    } else if let provider = store.selectedAgentWorkspaceProvider,
                              let agent = snapshot.agents.first(where: { $0.provider == provider }) {
                        agentDetail(agent, snapshot: snapshot)
                    } else if snapshot.detectedAgents.isEmpty {
                        EmptyPanel(
                            symbol: "folder.badge.questionmark",
                            title: "没有发现已验证的 Agent 数据根",
                            detail: "CleanNest 没有猜测目录，也没有遍历你的项目文件。可以刷新聚合账本，或进入工具账本查看官方 dry-run。"
                        )
                    } else {
                        agentOverview(snapshot)
                        if !snapshot.alerts.isEmpty { anomalyPanel(snapshot.alerts) }
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
                } else {
                    if let summary = store.agentWorkspaceSummary {
                        cachedSummaryPanel(summary)
                    }
                    if store.agentWorkspacePhase.isScanning {
                        loadingPanel
                    } else if store.agentWorkspaceSummary == nil {
                        EmptyPanel(
                            symbol: "sparkle.magnifyingglass",
                            title: "尚未建立 Agent 占用账本",
                            detail: "首次扫描只读取文件大小、数量、时间与打开状态。"
                        )
                    }
                }
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
        .sheet(isPresented: $showingRecoveryConfirmation) {
            AgentWorkspaceRecoveryConfirmation(
                candidates: store.selectedAgentWorkspaceCandidates,
                runningProviders: Set(store.agentDependencyGraph.nodes.compactMap { node in
                    guard node.kind == .process, node.state == .running else { return nil }
                    return node.provider
                }),
                isBusy: store.agentWorkspaceRecoveryPhase.isBusy
            ) {
                Task { await store.createAgentWorkspaceRecovery() }
            }
        }
        .sheet(isPresented: $showingArchiveSuggestions) {
            if let snapshot = store.agentWorkspaceSnapshot {
                AgentArchiveSuggestionsSheet(
                    artifacts: archiveSuggestionArtifacts(snapshot),
                    ruleCatalog: store.agentRuleCatalog
                )
            }
        }
        .sheet(item: $nativeCleanupRequest) { entry in
            NativeDeveloperStorageConfirmation(entry: entry) {
                Task { await store.runNativeDeveloperStorageCleanup(entry.tool) }
            }
        }
    }

    private var pageTitle: String {
        if showingNativeTools { return "Agent 工具账本" }
        if let provider = store.selectedAgentWorkspaceProvider {
            return "\(provider.displayName) 工作区"
        }
        return "Agent 工作区"
    }

    private var pageSubtitle: String {
        if showingNativeTools {
            return "让 Git、Hugging Face 等工具先用自己的接口解释可回收对象；没有可靠预演就保持只读。"
        }
        if store.selectedAgentWorkspaceProvider != nil {
            return "按类别查看占用，再按需生成逐文件证据；会话、凭据与私有索引不会被 CleanNest 猜测处置。"
        }
        return "先看谁在增长、谁正活跃、哪里出现异常；点进单个 Agent 后才生成文件级明细。"
    }

    private var headerActions: some View {
        HStack(spacing: 9) {
            if showingNativeTools || store.selectedAgentWorkspaceProvider != nil {
                Button {
                    showingNativeTools = false
                    store.closeAgentWorkspaceDetail()
                } label: {
                    Label("返回概览", systemImage: "chevron.left")
                }
                .keyboardShortcut(.cancelAction)
            } else {
                Button {
                    showingNativeTools = true
                } label: {
                    Label("工具账本", systemImage: "wrench.and.screwdriver")
                }
            }
            StatusPill(
                text: store.agentWorkspacePhase.isScanning
                    ? "正在采样"
                    : (store.selectedAgentWorkspaceProvider == nil ? "概览不建文件明细" : "详情已绑定身份"),
                symbol: store.agentWorkspacePhase.isScanning ? "arrow.triangle.2.circlepath" : "checkmark.shield",
                style: store.agentWorkspacePhase.isScanning ? .neutral : .success
            )
            Button {
                Task {
                    if let provider = store.selectedAgentWorkspaceProvider {
                        await store.refreshAgentWorkspace(provider: provider)
                    } else if showingNativeTools {
                        await store.refreshNativeDeveloperStorage()
                    } else {
                        await store.refreshAgentWorkspace()
                    }
                }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.agentWorkspacePhase.isScanning)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityHint("重新读取 Agent 文件元数据；刷新本身不会修改文件")
        }
    }

    private func agentOverview(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            SurfaceCard(prominence: .prominent, tint: ledgerTint(snapshot)) {
                ContentSectionHeader(
                    "Agent 占用概览",
                    detail: scanTiming(snapshot),
                    symbol: "square.grid.2x2",
                    tint: ledgerTint(snapshot)
                ) {
                    StatusPill(
                        text: snapshot.isComplete ? "聚合账本已验证" : "部分路径不完整",
                        symbol: snapshot.isComplete ? "checkmark.seal" : "exclamationmark.triangle",
                        style: snapshot.isComplete ? .success : .warning
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        overviewMetric("总占用", CleanNestFormatting.bytes(snapshot.allocatedBytes), "目录分配块")
                        overviewDivider
                        overviewMetric("相比上次", aggregateChangeText(snapshot), "同一元数据口径")
                        overviewDivider
                        overviewMetric("活跃保护", "\(snapshot.activeFileCount) 个", "不会进入处置")
                        overviewDivider
                        overviewMetric("异常", "\(snapshot.alerts.filter { $0.level >= .warning }.count) 条", "先看高优先级")
                    }
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            overviewMetric("总占用", CleanNestFormatting.bytes(snapshot.allocatedBytes), "目录分配块")
                            overviewMetric("相比上次", aggregateChangeText(snapshot), "同一元数据口径")
                        }
                        HStack(spacing: 12) {
                            overviewMetric("活跃保护", "\(snapshot.activeFileCount) 个", "不会进入处置")
                            overviewMetric("异常", "\(snapshot.alerts.filter { $0.level >= .warning }.count) 条", "先看高优先级")
                        }
                    }
                }

                AgentAllocationBar(agents: snapshot.detectedAgents)
            }

            ContentSectionHeader(
                "选择一个 Agent 深入查看",
                detail: "进入后才构建该 Agent 的文件级证据",
                symbol: "rectangle.grid.2x2",
                tint: CNTheme.cyan
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                ForEach(snapshot.detectedAgents) { agent in
                    AgentOverviewButton(
                        agent: agent,
                        alertCount: snapshot.alerts.filter { $0.provider == agent.provider }.count,
                        rule: store.agentRuleCatalog.rule(for: agent.provider)
                    ) {
                        Task { await store.openAgentWorkspaceDetail(agent.provider) }
                    }
                }
            }
        }
    }

    private var overviewDivider: some View {
        Divider().frame(height: 45).padding(.horizontal, 18)
    }

    private func overviewMetric(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aggregateChangeText(_ snapshot: AgentWorkspaceSnapshot) -> String {
        let changes = snapshot.detectedAgents.compactMap(\.allocatedBytesChange)
        guard changes.count == snapshot.detectedAgents.count, !changes.isEmpty else { return "待建立基线" }
        let delta = changes.reduce(Int64(0), +)
        if delta == 0 { return "无变化" }
        return (delta > 0 ? "+" : "−") + CleanNestFormatting.bytes(abs(delta))
    }

    @ViewBuilder
    private func agentDetail(
        _ agent: AgentWorkspaceAgentSnapshot,
        snapshot: AgentWorkspaceSnapshot
    ) -> some View {
        let detailSnapshot = AgentWorkspaceSnapshot(
            capturedAt: snapshot.capturedAt,
            previousCapturedAt: snapshot.previousCapturedAt,
            agents: [agent],
            alerts: snapshot.alerts.filter { $0.provider == agent.provider },
            openFileProbeSucceeded: snapshot.openFileProbeSucceeded,
            diagnostic: snapshot.diagnostic
        )

        SurfaceCard(prominence: .prominent, tint: providerTint(agent.provider)) {
            HStack(alignment: .center, spacing: 16) {
                AgentProviderIcon(
                    provider: agent.provider,
                    rule: store.agentRuleCatalog.rule(for: agent.provider),
                    size: 52,
                    fallbackTint: providerTint(agent.provider)
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text(CleanNestFormatting.bytes(agent.allocatedBytes))
                        .font(.system(size: 31, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(agent.artifacts.count) 类 · \(agent.fileCount.formatted()) 个文件 · \(agentChangeText(agent))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(
                    text: agent.activeFileCount > 0 ? "\(agent.activeFileCount) 个活跃文件已锁定" : "未发现活跃写入",
                    symbol: agent.activeFileCount > 0 ? "lock.fill" : "checkmark.shield",
                    style: .success
                )
            }
        }

        SurfaceCard(title: "类别账本", symbol: "list.bullet.rectangle", tint: providerTint(agent.provider)) {
            AgentLedgerPanel(
                agent: agent,
                rule: store.agentRuleCatalog.rule(for: agent.provider),
                initiallyExpanded: true
            )
        }

        recoveryCenter(detailSnapshot)

        SurfaceCard(title: "运行关系", symbol: "point.3.connected.trianglepath.dotted", tint: CNTheme.violet) {
            AgentDependencyLane(
                provider: agent.provider,
                graph: store.agentDependencyGraph,
                rule: store.agentRuleCatalog.rule(for: agent.provider)
            )
            Label(
                "只有进程、端口或 TCP 连接等系统证据存在时，才显示运行或模型实连。",
                systemImage: "checkmark.seal"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func agentChangeText(_ agent: AgentWorkspaceAgentSnapshot) -> String {
        guard let delta = agent.allocatedBytesChange else { return "尚无变化基线" }
        if delta == 0 { return "相比上次无变化" }
        return "相比上次\(delta > 0 ? "增加" : "减少") \(CleanNestFormatting.bytes(abs(delta)))"
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

    private func cachedSummaryPanel(_ summary: AgentWorkspaceSummary) -> some View {
        SurfaceCard(prominence: .prominent, tint: CNTheme.violet) {
            ContentSectionHeader(
                "上次完成的聚合结果",
                detail: summary.capturedAt.formatted(date: .abbreviated, time: .shortened),
                symbol: "clock.arrow.circlepath",
                tint: CNTheme.violet
            ) {
                StatusPill(
                    text: summary.isComplete ? "历史结果" : "历史结果不完整",
                    symbol: "clock",
                    style: summary.isComplete ? .neutral : .warning
                )
            }

            HStack(spacing: 12) {
                MetricCard(
                    label: "Agent",
                    value: "\(summary.providers.count) 个",
                    detail: "仅聚合计数",
                    symbol: "terminal",
                    tint: CNTheme.violet
                )
                MetricCard(
                    label: "上次占用",
                    value: CleanNestFormatting.bytes(summary.allocatedBytes),
                    detail: "不含文件路径",
                    symbol: "internaldrive",
                    tint: CNTheme.cyan
                )
                MetricCard(
                    label: "文件",
                    value: summary.fileCount.formatted(),
                    detail: "活跃 \(summary.activeFileCount) 个",
                    symbol: "doc.on.doc",
                    tint: CNTheme.warning
                )
            }

            InlineBanner(
                title: "正在重新验证，不会沿用旧处置权限",
                detail: "这个摘要不含路径、打开文件或处置令牌；刷新完成前只能看，不能据此清理。",
                kind: .info
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("上次完成的 Agent 聚合结果")
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
                        AgentProviderIcon(
                            provider: agent.provider,
                            rule: store.agentRuleCatalog.rule(for: agent.provider),
                            size: 19,
                            fallbackTint: providerTint(agent.provider)
                        )
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

    private var dependencyGraphPanel: some View {
        let graph = store.agentDependencyGraph
        return SurfaceCard(prominence: .prominent, tint: CNTheme.violet) {
            ContentSectionHeader(
                "本机运行关系",
                detail: "像电路追踪板一样，只点亮有系统证据的节点和连接",
                symbol: "point.3.connected.trianglepath.dotted",
                tint: CNTheme.violet
            ) {
                StatusPill(
                    text: store.agentDependencyGraphIsRefreshing
                        ? "正在核对"
                        : "\(graph.runningProviderCount) 个运行中",
                    symbol: store.agentDependencyGraphIsRefreshing ? "arrow.triangle.2.circlepath" : "dot.radiowaves.left.and.right",
                    style: graph.runningProviderCount > 0 ? .success : .neutral
                )
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    graphMetric(
                        value: graph.confirmedModelConnectionCount.formatted(),
                        label: "模型实连",
                        detail: "已建立 TCP"
                    )
                    graphMetric(
                        value: store.agentRuleCatalog.providers.count.formatted(),
                        label: "有界适配器",
                        detail: "未验证不猜测"
                    )
                    Spacer(minLength: 12)
                    ruleCatalogActions
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 18) {
                        graphMetric(
                            value: graph.confirmedModelConnectionCount.formatted(),
                            label: "模型实连",
                            detail: "已建立 TCP"
                        )
                        graphMetric(
                            value: store.agentRuleCatalog.providers.count.formatted(),
                            label: "有界适配器",
                            detail: "未验证不猜测"
                        )
                    }
                    ruleCatalogActions
                }
            }

            VStack(spacing: 0) {
                ForEach(AgentWorkspaceProvider.allCases) { provider in
                    AgentDependencyLane(
                        provider: provider,
                        graph: graph,
                        rule: store.agentRuleCatalog.rule(for: provider)
                    )
                    if provider != AgentWorkspaceProvider.allCases.last {
                        Divider().padding(.leading, 38)
                    }
                }
            }
            .background(Color.primary.opacity(0.018), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(CNTheme.mint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(graph.diagnostic)
                    Text("规则 \(store.agentRuleCatalog.revision) · \(store.agentRuleCatalogSource.displayName)。\(store.agentRuleCatalogDiagnostic)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func graphMetric(value: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label).font(.caption.weight(.semibold))
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 88, alignment: .leading)
    }

    private var ruleCatalogActions: some View {
        HStack(spacing: 8) {
            Button {
                chooseAgentRuleBundle()
            } label: {
                Label("导入签名规则…", systemImage: "checkmark.shield")
            }
            .help("只接受与当前 CleanNest 同一签名者签署、且通过严格路径校验的规则包")
            if store.agentRuleCatalogSource.isExternal {
                Button("恢复内置") {
                    Task { await store.resetAgentRuleCatalog() }
                }
            }
            Button {
                Task { await store.refreshAgentDependencyGraph() }
            } label: {
                Label("复核关系", systemImage: "arrow.clockwise")
            }
            .disabled(store.agentDependencyGraphIsRefreshing)
        }
        .controlSize(.small)
    }

    private func chooseAgentRuleBundle() {
        let panel = NSOpenPanel()
        panel.title = "选择由 CleanNest 维护者签名的 Agent 规则包"
        panel.prompt = "验证并导入"
        // Finder presents signed .bundle packages as files even though their
        // contents are directories. The verifier below still requires a real,
        // non-symlink directory bundle and rejects ordinary files.
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.importAgentRuleCatalog(from: url) }
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
                AgentLedgerPanel(
                    agent: agent,
                    rule: store.agentRuleCatalog.rule(for: agent.provider)
                )
            }
        }
    }

    private func recoveryCenter(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        let candidates = snapshot.actionCandidates
        let candidateGroups = AgentWorkspaceCandidateGroup.make(from: candidates)
        let allSelected = !candidates.isEmpty
            && candidates.allSatisfy { store.selectedAgentWorkspaceCandidateIDs.contains($0.id) }
        let archiveSuggestions = archiveSuggestionArtifacts(snapshot)
        let archive = archiveSuggestions.reduce(Int64(0)) { partial, artifact in
            let bytes = max(0, artifact.previewBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
        return SurfaceCard(
            title: "安全处置与恢复",
            symbol: "archivebox.circle",
            tint: CNTheme.mint
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    previewLane(
                        title: "可执行候选",
                        value: CleanNestFormatting.bytes(snapshot.actionableBytes),
                        detail: "\(candidates.count.formatted()) 个静置普通文件；逐文件身份已绑定。",
                        symbol: "checkmark.shield",
                        tint: CNTheme.cyan
                    )
                    previewLane(
                        title: "会话归档建议",
                        value: CleanNestFormatting.bytes(archive),
                        detail: "这不是已选垃圾。点开查看由哪些旧会话、备份和生成资源组成。",
                        symbol: "lock.doc",
                        tint: CNTheme.violet,
                        actionLabel: "查看详情"
                    ) {
                        showingArchiveSuggestions = true
                    }
                }
                VStack(spacing: 12) {
                    previewLane(
                        title: "可执行候选",
                        value: CleanNestFormatting.bytes(snapshot.actionableBytes),
                        detail: "\(candidates.count.formatted()) 个静置普通文件；逐文件身份已绑定。",
                        symbol: "checkmark.shield",
                        tint: CNTheme.cyan
                    )
                    previewLane(
                        title: "会话归档建议",
                        value: CleanNestFormatting.bytes(archive),
                        detail: "这不是已选垃圾。点开查看由哪些旧会话、备份和生成资源组成。",
                        symbol: "lock.doc",
                        tint: CNTheme.violet,
                        actionLabel: "查看详情"
                    ) {
                        showingArchiveSuggestions = true
                    }
                }
            }

            if !candidates.isEmpty {
                Divider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("手动决定处理范围")
                            .font(.subheadline.weight(.semibold))
                        Text("默认不选择；可以按分类批量选择，再展开取消任意单文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(allSelected ? "清空选择" : "选择全部可执行项") {
                        store.setAgentWorkspaceCandidates(candidates, selected: !allSelected)
                    }
                    .controlSize(.small)
                }

                VStack(spacing: 0) {
                    ForEach(candidateGroups) { group in
                        AgentWorkspaceCandidateGroupRow(group: group)
                            .environmentObject(store)
                        if group.id != candidateGroups.last?.id {
                            Divider().padding(.leading, 41)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("已选 \(store.selectedAgentWorkspaceCandidates.count.formatted()) 项 · \(CleanNestFormatting.bytes(store.selectedAgentWorkspaceBytes))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text("先压缩并校验，再处理原文件；完成后显示处理前后 APFS 可用空间实测。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        showingRecoveryConfirmation = true
                    } label: {
                        Label("检查计划…", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        store.selectedAgentWorkspaceCandidates.isEmpty
                            || store.agentWorkspaceRecoveryPhase.isBusy
                            || !snapshot.isComplete
                    )
                }
            } else {
                Label(
                    "当前没有满足类别静置门槛（缓存与安装残留 15 分钟，备份、已归档会话与虚拟机 30 天，活跃会话 60 天）、未被打开且扫描完整的可执行候选。",
                    systemImage: "checkmark.shield"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let message = store.agentWorkspaceRecoveryMessage {
                InlineBanner(
                    title: store.agentWorkspaceRecoveryMessageIsWarning ? "安全处置需要注意" : "安全处置已更新",
                    detail: message,
                    kind: store.agentWorkspaceRecoveryMessageIsWarning ? .warning : .success
                )
            }

            recoveryRecords

            Label(
                "压缩包和含原路径的恢复清单只保存在本机 Application Support；CleanNest 不会结束 Agent、清空废纸篓或直接改写会话索引。",
                systemImage: "lock.shield"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func archiveSuggestionArtifacts(_ snapshot: AgentWorkspaceSnapshot) -> [AgentWorkspaceArtifact] {
        snapshot.detectedAgents
            .flatMap(\.artifacts)
            .filter { artifact in
                artifact.previewBytes > 0
                    && [.activeSessions, .archivedSessions, .backups, .generatedMedia].contains(artifact.kind)
                    && (artifact.disposition == .review || artifact.disposition == .protected)
            }
            .sorted {
                if $0.previewBytes == $1.previewBytes {
                    if $0.provider == $1.provider { return $0.kind.rawValue < $1.kind.rawValue }
                    let lhs = AgentWorkspaceProvider.allCases.firstIndex(of: $0.provider) ?? Int.max
                    let rhs = AgentWorkspaceProvider.allCases.firstIndex(of: $1.provider) ?? Int.max
                    return lhs < rhs
                }
                return $0.previewBytes > $1.previewBytes
            }
    }

    @ViewBuilder
    private var recoveryRecords: some View {
        let records = store.agentWorkspaceRecoveryRecords.filter { record in
            guard let provider = store.selectedAgentWorkspaceProvider else { return true }
            return record.items.contains { $0.candidate.provider == provider }
        }
        if !records.isEmpty {
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("本机恢复记录")
                        .font(.subheadline.weight(.semibold))
                    Text("恢复会先检查原位置，绝不覆盖 Agent 后来新建的同名文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("打开恢复区") { store.openAgentWorkspaceRecoveryFolder() }
                    .controlSize(.small)
            }
            VStack(spacing: 0) {
                ForEach(Array(records.prefix(5).enumerated()), id: \.element.id) { index, record in
                    AgentWorkspaceRecoveryRecordRow(record: record)
                        .environmentObject(store)
                    if index < min(5, records.count) - 1 {
                        Divider().padding(.leading, 41)
                    }
                }
            }
        }
    }

    private var nativeToolCenter: some View {
        SurfaceCard(
            title: "开发工具原生接口",
            symbol: "terminal.fill",
            tint: CNTheme.cyan
        ) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("让工具自己解释可回收对象")
                        .font(.subheadline.weight(.semibold))
                    Text("优先使用官方 dry-run/账本；没有预演能力的广域删除保持禁用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    selectGitRepository()
                } label: {
                    Label("选择 Git 仓库", systemImage: "folder.badge.gearshape")
                }
                .controlSize(.small)
                Button {
                    Task { await store.refreshNativeDeveloperStorage() }
                } label: {
                    if store.nativeDeveloperStorageIsRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .controlSize(.small)
                .disabled(store.nativeDeveloperStorageIsRefreshing)
            }

            if let snapshot = store.nativeDeveloperStorageSnapshot {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.entries.enumerated()), id: \.element.id) { index, entry in
                        NativeDeveloperStorageRow(entry: entry) {
                            if entry.tool == .gitWorktree, entry.state == .needsSelection {
                                selectGitRepository()
                            } else if entry.supportsNativeCleanup, entry.state == .ready {
                                nativeCleanupRequest = entry
                            }
                        }
                        if index < snapshot.entries.count - 1 { Divider().padding(.leading, 43) }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在读取 Git、Docker、Hugging Face、npm 与 pip 的原生账本…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            if let message = store.nativeDeveloperStorageMessage {
                InlineBanner(
                    title: store.nativeDeveloperStorageMessageIsWarning ? "原生工具操作未完成" : "原生工具账本已更新",
                    detail: message,
                    kind: store.nativeDeveloperStorageMessageIsWarning ? .warning : .success
                )
            }

            Label(
                "Git worktree prune 与 hf cache prune 只有在官方 dry-run 重新通过后才开放；Docker system prune、npm clean 与 pip purge 当前不会执行。",
                systemImage: "shield.lefthalf.filled"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func selectGitRepository() {
        let panel = NSOpenPanel()
        panel.title = "选择要检查 worktree 的 Git 仓库"
        panel.prompt = "选择仓库"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.setNativeGitRepository(url) }
    }

    @ViewBuilder
    private func previewLane(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action {
            Button(action: action) {
                previewLaneContent(
                    title: title,
                    value: value,
                    detail: detail,
                    symbol: symbol,
                    tint: tint,
                    actionLabel: actionLabel
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(actionLabel ?? "查看详情")\(title)"))
            .accessibilityValue(Text(value))
            .accessibilityHint(Text("打开只读明细，不会移动或删除文件"))
        } else {
            previewLaneContent(
                title: title,
                value: value,
                detail: detail,
                symbol: symbol,
                tint: tint,
                actionLabel: nil
            )
        }
    }

    private func previewLaneContent(
        title: String,
        value: String,
        detail: String,
        symbol: String,
        tint: Color,
        actionLabel: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CNIconTile(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(value).font(.headline).monospacedDigit()
                        if let actionLabel {
                            HStack(spacing: 4) {
                                Text(actionLabel)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                        }
                    }
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

private struct AgentArchiveSuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let artifacts: [AgentWorkspaceArtifact]
    let ruleCatalog: AgentRuleCatalog

    private var totalPreviewBytes: Int64 {
        artifacts.reduce(Int64(0)) { partial, artifact in
            let bytes = max(0, artifact.previewBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
    }

    private var totalOldFileCount: Int {
        artifacts.reduce(0) { partial, artifact in
            let count = max(0, artifact.oldFileCount)
            return partial > Int.max - count ? Int.max : partial + count
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                CNIconTile(symbol: "lock.doc.fill", tint: CNTheme.violet, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("会话归档建议")
                        .font(.title2.weight(.semibold))
                    Text("\(artifacts.count.formatted()) 类数据 · \(totalOldFileCount.formatted()) 个旧文件 · \(CleanNestFormatting.bytes(totalPreviewBytes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                StatusPill(text: "只读建议", symbol: "eye", style: .neutral)
            }

            InlineBanner(
                title: "这些不是“已选垃圾”",
                detail: "CleanNest 只是根据时间找到旧会话、备份和生成资源。它们可能仍然是你的工作记录，所以当前不会自动移动或删除。",
                kind: .warning
            )

            VStack(alignment: .leading, spacing: 6) {
                Label("0.8.0 起，这些建议如何变成动作？", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
                Text("超过 30 天的备份、已归档会话和超时未用的虚拟机，以及超过 60 天的会话文件，可以在详情页进入备份优先的安全处置，随时从恢复区还原。生成图片、记忆、索引、凭据和运行时继续保持只读。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("注意：移除会话文件后，Agent 自己的会话列表可能短暂保留失效条目；这是已知现象，恢复备份即可还原。")
                    .font(.caption)
                    .foregroundStyle(CNTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            if artifacts.isEmpty {
                EmptyPanel(
                    symbol: "archivebox",
                    title: "暂时没有归档建议",
                    detail: "重新扫描后，只有时间较旧且允许只读复核的会话类数据会显示在这里。"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(artifacts.enumerated()), id: \.element.id) { index, artifact in
                            archiveSuggestionRow(artifact)
                            if index < artifacts.count - 1 {
                                Divider().padding(.leading, 51)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color.secondary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                }
                .frame(maxHeight: 300)
            }

            HStack(spacing: 12) {
                Label("“显示位置”只会打开 Finder，不会改动文件。", systemImage: "checkmark.shield")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(CNTheme.mint)
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 660)
        .frame(minHeight: 520)
    }

    private func archiveSuggestionRow(_ artifact: AgentWorkspaceArtifact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AgentProviderIcon(
                provider: artifact.provider,
                rule: ruleCatalog.rule(for: artifact.provider),
                size: 36,
                fallbackTint: providerTint(artifact.provider)
            )
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("\(artifact.provider.displayName) · \(artifact.kind.displayName)")
                        .font(.subheadline.weight(.semibold))
                    StatusPill(
                        text: artifact.disposition == .protected ? "当前锁定" : "人工复核",
                        symbol: artifact.disposition == .protected ? "lock.fill" : "eye",
                        style: artifact.disposition == .protected ? .warning : .neutral
                    )
                }
                Text(pathSummary(artifact.sourcePaths))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text("\(artifact.oldFileCount.formatted()) 个旧文件只进入建议；该分组共 \(artifact.fileCount.formatted()) 个文件。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 7) {
                Text(CleanNestFormatting.bytes(artifact.previewBytes))
                    .font(.headline)
                    .monospacedDigit()
                Button("显示位置") {
                    revealInFinder(artifact)
                }
                .controlSize(.small)
                .disabled(firstExistingPath(for: artifact) == nil)
                .accessibilityHint("在 Finder 中显示该分组的第一个已验证位置")
            }
        }
        .padding(.vertical, 12)
    }

    private func firstExistingPath(for artifact: AgentWorkspaceArtifact) -> String? {
        artifact.sourcePaths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func revealInFinder(_ artifact: AgentWorkspaceArtifact) {
        guard let path = firstExistingPath(for: artifact) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

private struct AgentWorkspaceCandidateGroup: Identifiable {
    let provider: AgentWorkspaceProvider
    let kind: AgentArtifactKind
    let candidates: [AgentWorkspaceActionCandidate]

    var id: String { "\(provider.rawValue):\(kind.rawValue)" }
    var allocatedBytes: Int64 {
        candidates.reduce(0) { partial, candidate in
            let bytes = max(0, candidate.identity.allocatedBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
    }

    static func make(from candidates: [AgentWorkspaceActionCandidate]) -> [Self] {
        let grouped = Dictionary(grouping: candidates) {
            "\($0.provider.rawValue):\($0.kind.rawValue)"
        }
        return grouped.values.compactMap { values in
            guard let first = values.first else { return nil }
            return Self(
                provider: first.provider,
                kind: first.kind,
                candidates: values.sorted {
                    if $0.identity.allocatedBytes == $1.identity.allocatedBytes { return $0.path < $1.path }
                    return $0.identity.allocatedBytes > $1.identity.allocatedBytes
                }
            )
        }.sorted {
            if $0.provider != $1.provider { return $0.provider.rawValue < $1.provider.rawValue }
            return $0.kind.rawValue < $1.kind.rawValue
        }
    }
}

private struct AgentWorkspaceCandidateGroupRow: View {
    @EnvironmentObject private var store: AppStore
    let group: AgentWorkspaceCandidateGroup
    @State private var isExpanded = false

    private var selectedCount: Int {
        group.candidates.reduce(0) {
            $0 + (store.selectedAgentWorkspaceCandidateIDs.contains($1.id) ? 1 : 0)
        }
    }

    private var allSelected: Bool {
        selectedCount == group.candidates.count && !group.candidates.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "收起文件" : "展开文件")

                CNIconTile(symbol: artifactSymbol(group.kind), tint: providerTint(group.provider), size: 31)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(group.provider.displayName) · \(group.kind.displayName)")
                        .font(.subheadline.weight(.semibold))
                    Text("\(group.candidates.count.formatted()) 项 · \(CleanNestFormatting.bytes(group.allocatedBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedCount > 0 {
                    Text("已选 \(selectedCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CNTheme.mint)
                        .monospacedDigit()
                }
                Button(allSelected ? "清除" : "选择") {
                    store.setAgentWorkspaceCandidates(group.candidates, selected: !allSelected)
                }
                .controlSize(.small)
            }
            .padding(.vertical, 10)

            if group.kind == .activeSessions || group.kind == .archivedSessions {
                Text("移除会话文件后，Agent 自己的会话列表可能短暂保留失效条目；备份保留在恢复区，可随时还原。")
                    .font(.caption2)
                    .foregroundStyle(CNTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 31)
                    .padding(.bottom, 4)
            }

            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.candidates.prefix(30).enumerated()), id: \.element.id) { index, candidate in
                        AgentWorkspaceCandidateSelectionRow(candidate: candidate)
                            .environmentObject(store)
                        if index < min(30, group.candidates.count) - 1 {
                            Divider().padding(.leading, 31)
                        }
                    }
                    if group.candidates.count > 30 {
                        Text("另有 \(group.candidates.count - 30) 个较小文件；按分类选择会包含它们，仍会在执行前逐一复核身份。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 9)
                            .padding(.leading, 31)
                    }
                }
                .padding(.leading, 31)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct AgentWorkspaceCandidateSelectionRow: View {
    @EnvironmentObject private var store: AppStore
    let candidate: AgentWorkspaceActionCandidate

    var body: some View {
        Toggle(isOn: Binding(
            get: { store.selectedAgentWorkspaceCandidateIDs.contains(candidate.id) },
            set: { store.setAgentWorkspaceCandidate(candidate.id, selected: $0) }
        )) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name.isEmpty ? "未命名文件" : candidate.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(abbreviatedHomePath(candidate.path))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 10)
                Text(CleanNestFormatting.bytes(candidate.identity.allocatedBytes))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 8)
    }
}

private struct AgentWorkspaceRecoveryRecordRow: View {
    @EnvironmentObject private var store: AppStore
    let record: AgentWorkspaceRecoveryRecord

    private var isRestoring: Bool {
        store.agentWorkspaceRecoveryPhase == .restoring(record.id)
    }

    private var deltaText: String {
        guard let delta = record.apfsDeltaBytes else { return "APFS 尚未完成对比" }
        if delta > 0 { return "APFS +\(CleanNestFormatting.bytes(delta))" }
        if delta < 0 { return "APFS −\(CleanNestFormatting.bytes(-delta))" }
        return "APFS 无可确认变化"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: record.status == .restored ? "arrow.uturn.backward.circle.fill" : "archivebox.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(record.status == .restored ? CNTheme.success : CNTheme.violet)
                .frame(width: 31, height: 31)
                .background(
                    (record.status == .restored ? CNTheme.success : CNTheme.violet).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("\(record.items.count) 个 Agent 文件")
                        .font(.subheadline.weight(.semibold))
                    StatusPill(
                        text: record.status.displayName,
                        symbol: record.status == .restored ? "checkmark" : "arrow.uturn.backward",
                        style: record.status == .interrupted ? .warning : .neutral
                    )
                }
                Text("原目录 \(CleanNestFormatting.bytes(record.originalAllocatedBytes)) · 备份 \(CleanNestFormatting.bytes(record.archiveAllocatedBytes)) · \(deltaText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 10)
            if record.status != .restored {
                Button {
                    Task { await store.restoreAgentWorkspaceRecovery(record) }
                } label: {
                    if isRestoring {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("恢复", systemImage: "arrow.uturn.backward")
                    }
                }
                .controlSize(.small)
                .disabled(store.agentWorkspaceRecoveryPhase.isBusy)
            }
        }
        .padding(.vertical, 10)
    }
}

private struct AgentWorkspaceRecoveryConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let candidates: [AgentWorkspaceActionCandidate]
    let runningProviders: Set<AgentWorkspaceProvider>
    let isBusy: Bool
    let onConfirm: () -> Void
    @State private var acknowledged = false
    @State private var showsTechnicalDetails = false

    private var allocatedBytes: Int64 {
        candidates.reduce(0) { partial, candidate in
            let bytes = max(0, candidate.identity.allocatedBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
    }

    private var logicalBytes: Int64 {
        candidates.reduce(0) { partial, candidate in
            let bytes = max(0, candidate.identity.logicalBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
    }

    private var providerBreakdown: [(provider: AgentWorkspaceProvider, bytes: Int64)] {
        Dictionary(grouping: candidates, by: \.provider)
            .map { provider, items in
                let bytes = items.reduce(Int64(0)) { partial, candidate in
                    let value = max(0, candidate.identity.allocatedBytes)
                    return partial > Int64.max - value ? Int64.max : partial + value
                }
                return (provider, bytes)
            }
            .sorted {
                let lhs = AgentWorkspaceProvider.allCases.firstIndex(of: $0.provider) ?? Int.max
                let rhs = AgentWorkspaceProvider.allCases.firstIndex(of: $1.provider) ?? Int.max
                return lhs < rhs
            }
    }

    private var selectedProviderNames: String {
        providerBreakdown.map(\.provider.displayName).joined(separator: "、")
    }

    private var runningSelectedProviders: [AgentWorkspaceProvider] {
        providerBreakdown.map(\.provider).filter(runningProviders.contains)
    }

    private var runningProviderNames: String {
        runningSelectedProviders.map(\.displayName).joined(separator: "、")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                CNIconTile(symbol: "checkmark.shield.fill", tint: CNTheme.mint, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("确认 Agent 安全处置")
                        .font(.title2.weight(.semibold))
                    Text("\(candidates.count.formatted()) 个文件 · 分配块 \(CleanNestFormatting.bytes(allocatedBytes)) · 逻辑体积 \(CleanNestFormatting.bytes(logicalBytes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            impactSummary

            InlineBanner(
                title: "恢复包包含所选文件的真实内容",
                detail: "它只保存在这台 Mac 的 CleanNest Application Support，不上传；恢复清单还会保存原路径。恢复时若原位置已有新文件，会拒绝覆盖。",
                kind: .warning
            )

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsTechnicalDetails.toggle()
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .rotationEffect(.degrees(showsTechnicalDetails ? 90 : 0))
                        Label("查看技术保护步骤", systemImage: "lock.doc")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(showsTechnicalDetails ? "收起" : "展开")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsTechnicalDetails ? "已展开" : "已折叠")

                if showsTechnicalDetails {
                    VStack(alignment: .leading, spacing: 11) {
                        confirmationStep(1, "再次读取打开文件表并核对设备号、文件号、大小与修改时间。")
                        confirmationStep(2, "在本机恢复区创建 ZIP，并用 CRC 完整性检查确认备份可读。")
                        confirmationStep(3, "只有备份通过后才处理所选文件；生成内容、索引、记忆与凭据不动。")
                        confirmationStep(4, "完成后对比 APFS 可用空间；结果可能小于候选体积，甚至因压缩率低而不增加。")
                    }
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            Toggle("我知道这不会让模型变快，并确认范围和恢复方式", isOn: $acknowledged)
                .toggleStyle(.checkbox)

            HStack {
                Button(runningSelectedProviders.isEmpty ? "取消" : "等任务结束再处理", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Label(
                        runningSelectedProviders.isEmpty ? "创建备份并处理" : "仍要创建备份并处理",
                        systemImage: "archivebox"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!acknowledged || candidates.isEmpty || isBusy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 590)
        .interactiveDismissDisabled(isBusy)
    }

    private var impactSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("不会让 \(selectedProviderNames) 的模型回复更快", systemImage: "speedometer")
                .font(.headline)
                .foregroundStyle(CNTheme.warning)

            Text("这次只是把所选旧文件移出原位置。它不会降低当前进程内存、减少 Token，或改善模型能力；下次用到相关缓存时可能会重新生成，第一次打开反而可能稍慢。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) { providerImpactChips }
                VStack(alignment: .leading, spacing: 8) { providerImpactChips }
            }

            Label(
                "候选分配块是 \(CleanNestFormatting.bytes(allocatedBytes))，但恢复 ZIP 也占空间，所以实际腾出的空间会更少，并以完成后的 APFS 实测为准。",
                systemImage: "internaldrive"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if !runningSelectedProviders.isEmpty {
                Label(
                    "\(runningProviderNames) 现在仍在运行。最稳妥的做法是先完成当前任务并退出；若继续，CleanNest 仍会复核打开文件和身份，发生变化就停止。",
                    systemImage: "pause.circle.fill"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(CNTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
            }

            Label("会话历史、登录状态、记忆、配置和生成媒体不会被处理。", systemImage: "checkmark.shield")
                .font(.caption.weight(.medium))
                .foregroundStyle(CNTheme.mint)
        }
        .padding(15)
        .background(CNTheme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var providerImpactChips: some View {
        ForEach(providerBreakdown, id: \.provider) { item in
            HStack(spacing: 7) {
                AgentProviderIcon(
                    provider: item.provider,
                    rule: AgentRuleCatalog.builtIn.rule(for: item.provider),
                    size: 23,
                    fallbackTint: providerTint(item.provider)
                )
                Text(item.provider.displayName)
                    .font(.caption.weight(.semibold))
                Text(CleanNestFormatting.bytes(item.bytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.045), in: Capsule())
        }
    }

    private func confirmationStep(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number.formatted())
                .font(.caption.weight(.bold))
                .foregroundStyle(CNTheme.mint)
                .frame(width: 23, height: 23)
                .background(CNTheme.mint.opacity(0.12), in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct NativeDeveloperStorageRow: View {
    let entry: NativeDeveloperStorageEntry
    let action: () -> Void

    private var tint: Color {
        switch entry.state {
        case .ready: return entry.supportsNativeCleanup ? CNTheme.mint : CNTheme.cyan
        case .needsSelection: return CNTheme.warning
        case .unavailable: return CNTheme.warning
        case .notInstalled: return Color.secondary
        }
    }

    private var symbol: String {
        switch entry.tool {
        case .gitWorktree: return "arrow.triangle.branch"
        case .docker: return "shippingbox"
        case .huggingFace: return "face.smiling"
        case .npm: return "cube"
        case .pip: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CNIconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(entry.tool.displayName)
                        .font(.subheadline.weight(.semibold))
                    StatusPill(
                        text: entry.state.displayName,
                        symbol: entry.state == .ready ? "checkmark" : nil,
                        style: entry.state == .unavailable ? .warning : .neutral
                    )
                }
                Text(entry.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let preview = entry.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 10)
            if entry.tool == .gitWorktree, entry.state == .needsSelection {
                Button("选择…", action: action)
                    .controlSize(.small)
            } else if entry.supportsNativeCleanup, entry.state == .ready {
                Button("检查并执行…", action: action)
                    .controlSize(.small)
            } else {
                Text("只读")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.vertical, 10)
    }
}

private struct NativeDeveloperStorageConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    let entry: NativeDeveloperStorageEntry
    let onConfirm: () -> Void
    @State private var acknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                CNIconTile(symbol: "terminal.fill", tint: CNTheme.cyan, size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text("执行 \(entry.tool.displayName) 原生清理")
                        .font(.title2.weight(.semibold))
                    Text(entry.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            InlineBanner(
                title: "执行前会重新 dry-run",
                detail: "CleanNest 不会直接复用这张旧预览；范围或工具状态变化时会停止。完成后记录 APFS 前后可用空间。",
                kind: .success
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("风险与恢复边界")
                    .font(.subheadline.weight(.semibold))
                Text(entry.cleanupRisk)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.tool == .huggingFace {
                    Text("Hugging Face 未引用修订不会进入 CleanNest 压缩恢复区；需要时由 hf 重新下载。")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(CNTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .background(CNTheme.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

            Toggle("我已确认原生工具的处理范围", isOn: $acknowledged)
                .toggleStyle(.checkbox)

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Label("重新预演并执行", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!acknowledged)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
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

private struct AgentOverviewButton: View {
    let agent: AgentWorkspaceAgentSnapshot
    let alertCount: Int
    let rule: AgentProviderRule?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 11) {
                    AgentProviderIcon(
                        provider: agent.provider,
                        rule: rule,
                        size: 38,
                        fallbackTint: providerTint(agent.provider)
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.provider.displayName)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                        Text("\(agent.fileCount.formatted()) 个文件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                HStack(alignment: .lastTextBaseline) {
                    Text(CleanNestFormatting.bytes(agent.allocatedBytes))
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(changeText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(changeTint)
                }

                HStack(spacing: 8) {
                    StatusPill(
                        text: agent.activeFileCount > 0 ? "\(agent.activeFileCount) 活跃已保护" : "无活跃写入",
                        symbol: agent.activeFileCount > 0 ? "lock.fill" : "checkmark",
                        style: .success
                    )
                    if alertCount > 0 {
                        StatusPill(text: "\(alertCount) 条线索", symbol: "waveform.path.ecg", style: .warning)
                    } else {
                        StatusPill(text: "无异常", symbol: "checkmark.circle", style: .neutral)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(
                providerTint(agent.provider).opacity(0.055),
                in: RoundedRectangle(cornerRadius: CNTheme.cardRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CNTheme.cardRadius, style: .continuous)
                    .stroke(providerTint(agent.provider).opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.provider.displayName)，占用 \(CleanNestFormatting.bytes(agent.allocatedBytes))，\(changeText)，\(agent.activeFileCount) 个活跃文件，\(alertCount) 条异常线索")
        .accessibilityHint("打开该 Agent 的类别、文件、运行关系和恢复记录")
    }

    private var changeText: String {
        guard let delta = agent.allocatedBytesChange else { return "待建立变化基线" }
        if delta == 0 { return "无变化" }
        return (delta > 0 ? "+" : "−") + CleanNestFormatting.bytes(abs(delta))
    }

    private var changeTint: Color {
        guard let delta = agent.allocatedBytesChange, delta != 0 else { return .secondary }
        return delta > 0 ? CNTheme.warning : CNTheme.mint
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
    let rule: AgentProviderRule?
    @State private var isExpanded: Bool

    init(
        agent: AgentWorkspaceAgentSnapshot,
        rule: AgentProviderRule?,
        initiallyExpanded: Bool? = nil
    ) {
        self.agent = agent
        self.rule = rule
        _isExpanded = State(initialValue: initiallyExpanded ?? agent.provider.supportsBackupFirstRecovery)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    AgentProviderIcon(
                        provider: agent.provider,
                        rule: rule,
                        size: 36,
                        fallbackTint: providerTint(agent.provider)
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
            if artifact.actionableBytes > 0 {
                Text("其中 \(CleanNestFormatting.bytes(artifact.actionableBytes)) 可进入安全处置")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CNTheme.mint)
            } else if artifact.previewBytes > 0 {
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
    case .piAgent: return Color(red: 0.38, green: 0.72, blue: 0.98)
    case .kimi: return Color(red: 0.30, green: 0.55, blue: 0.98)
    case .workBuddy: return CNTheme.mint
    case .hermes: return CNTheme.violet
    case .openClaw: return Color(red: 0.95, green: 0.38, blue: 0.42)
    case .trae: return Color(red: 0.42, green: 0.73, blue: 0.98)
    case .miniMaxHub: return Color(red: 0.94, green: 0.60, blue: 0.24)
    case .xiaoyunque: return Color.secondary
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
    case .installerLeftovers: return "doc.zipper"
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
