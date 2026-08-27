import AppKit
import SwiftUI
import CleanNestCore
import CleanNestMutation

struct AgentWorkspaceView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingRecoveryConfirmation = false
    @State private var nativeCleanupRequest: NativeDeveloperStorageEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Agent 工作区",
                    subtitle: "看清 Codex 与 Claude 的本机占用；扫描只读元数据，安全处置仅限已静置的可再生文件。",
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
                        recoveryCenter(snapshot)
                        nativeToolCenter
                        agentInventory(snapshot.detectedAgents)
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
            if store.nativeDeveloperStorageSnapshot == nil {
                await store.refreshNativeDeveloperStorage()
            }
        }
        .sheet(isPresented: $showingRecoveryConfirmation) {
            AgentWorkspaceRecoveryConfirmation(
                candidates: store.selectedAgentWorkspaceCandidates,
                isBusy: store.agentWorkspaceRecoveryPhase.isBusy
            ) {
                Task { await store.createAgentWorkspaceRecovery() }
            }
        }
        .sheet(item: $nativeCleanupRequest) { entry in
            NativeDeveloperStorageConfirmation(entry: entry) {
                Task { await store.runNativeDeveloperStorageCleanup(entry.tool) }
            }
        }
    }

    private var headerActions: some View {
        HStack(spacing: 9) {
            StatusPill(
                text: store.agentWorkspacePhase.isScanning ? "正在采样" : "备份优先",
                symbol: store.agentWorkspacePhase.isScanning ? "arrow.triangle.2.circlepath" : "checkmark.shield",
                style: store.agentWorkspacePhase.isScanning ? .neutral : .success
            )
            Button {
                Task { await store.refreshAgentWorkspace() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.agentWorkspacePhase.isScanning)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .accessibilityHint("重新读取 Agent 文件元数据；刷新本身不会修改文件")
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

    private func recoveryCenter(_ snapshot: AgentWorkspaceSnapshot) -> some View {
        let candidates = snapshot.actionCandidates
        let candidateGroups = AgentWorkspaceCandidateGroup.make(from: candidates)
        let allSelected = !candidates.isEmpty
            && candidates.allSatisfy { store.selectedAgentWorkspaceCandidateIDs.contains($0.id) }
        let archive = snapshot.detectedAgents.flatMap(\.artifacts)
            .filter { $0.disposition == .review || $0.disposition == .protected }
            .reduce(Int64(0)) { $0 + $1.previewBytes }
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
                        detail: "会话、备份与生成资源仍只读；未验证索引协议前不执行。",
                        symbol: "lock.doc",
                        tint: CNTheme.violet
                    )
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
                        detail: "会话、备份与生成资源仍只读；未验证索引协议前不执行。",
                        symbol: "lock.doc",
                        tint: CNTheme.violet
                    )
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
                    "当前没有同时满足普通文件、静置超过 15 分钟、未被打开和扫描完整四项条件的可执行候选。",
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

    @ViewBuilder
    private var recoveryRecords: some View {
        if !store.agentWorkspaceRecoveryRecords.isEmpty {
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
                ForEach(Array(store.agentWorkspaceRecoveryRecords.prefix(5).enumerated()), id: \.element.id) { index, record in
                    AgentWorkspaceRecoveryRecordRow(record: record)
                        .environmentObject(store)
                    if index < min(5, store.agentWorkspaceRecoveryRecords.count) - 1 {
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
    let isBusy: Bool
    let onConfirm: () -> Void
    @State private var acknowledged = false

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

            VStack(alignment: .leading, spacing: 11) {
                confirmationStep(1, "再次读取打开文件表并核对设备号、文件号、大小与修改时间。")
                confirmationStep(2, "在本机恢复区创建 ZIP，并用 CRC 完整性检查确认备份可读。")
                confirmationStep(3, "只有备份通过后才处理缓存、临时文件和日志；会话、索引、记忆与凭据不动。")
                confirmationStep(4, "完成后对比 APFS 可用空间；结果可能小于候选体积，甚至因压缩率低而不增加。")
            }
            .padding(14)
            .background(CNTheme.mint.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))

            InlineBanner(
                title: "恢复包包含所选文件的真实内容",
                detail: "它只保存在这台 Mac 的 CleanNest Application Support，不上传；恢复清单还会保存原路径。恢复时若原位置已有新文件，会拒绝覆盖。",
                kind: .warning
            )

            Toggle("我已确认范围和恢复方式", isOn: $acknowledged)
                .toggleStyle(.checkbox)

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Label("创建备份并处理", systemImage: "archivebox")
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
