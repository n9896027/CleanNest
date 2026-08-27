import SwiftUI
import CleanNestCore

struct EvolutionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmingReset = false
    @State private var visibleRuleLimit = 100
    @State private var visibleModelLimit = 50

    private var hasMemory: Bool {
        !store.evolutionMemory.events.isEmpty
            || !store.evolutionMemory.ruleProposals.isEmpty
            || store.evolutionMemory.learnedCleanupCount > 0
            || store.evolutionMemory.successfulCleanupCount > 0
            || store.evolutionMemory.modelFeedbackCount > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "本机学习",
                    subtitle: "把你的明确判断变成下次更清楚的排序；不会擅自替你删除文件。"
                ) {
                    StatusPill(text: "仅存本机", symbol: "lock.shield", style: .success)
                }

                if hasMemory {
                    learnedWorkspace
                    memoryDetails
                    resetControl
                } else {
                    firstLearningWorkspace
                }
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
            .accessibilityElement(children: .contain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("本机学习")
        .alert("清空所有本机学习记录？", isPresented: $confirmingReset) {
            Button("取消", role: .cancel) { }
            Button("清空记录", role: .destructive) {
                store.resetEvolutionMemory()
            }
        } message: {
            Text("清理偏好和模型评价会被清空；文件、扫描结果与本机模型不会受到影响。")
        }
    }

    private var firstLearningWorkspace: some View {
        VStack(alignment: .leading, spacing: 24) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    firstLearningNarrative
                    Spacer(minLength: 18)
                    LearningOrbitGraphic()
                }
                VStack(alignment: .leading, spacing: 22) {
                    LearningOrbitGraphic()
                        .frame(maxWidth: .infinity)
                    firstLearningNarrative
                }
            }

            Divider().opacity(0.7)
            learningFlow

            HStack(spacing: 7) {
                Image(systemName: "lock.shield")
                Text("只保存项目类型、哈希身份、你的选择和模型评价；不保存文件内容或完整路径。")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .cnHeroPanel()
    }

    private var firstLearningNarrative: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("它还不了解你的取舍")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .tracking(-0.35)
            Text("先完成一次空间扫描，再对某个项目提出“以后优先清理”或“以后优先保留”。CleanNest 只会生成待审核提案；你在这里启用后，它才会影响下一次排序。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 500, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    store.selection = .cleanup
                    Task { if !store.cleanupHasScanned { await store.scanCleanup() } }
                } label: {
                    Label("扫描并建立第一条提案", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isWorking)

                Button("设置本机模型") {
                    store.selection = .settings
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private var learnedWorkspace: some View {
        VStack(alignment: .leading, spacing: 22) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("规则只有在你审核后才生效")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text("CleanNest 可以形成提案，但启用、暂停和撤销始终由你决定；规则只影响排序与标记。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 18)
                    LearningOrbitGraphic(compact: true)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("规则只有在你审核后才生效")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("CleanNest 可以形成提案，但启用、暂停和撤销始终由你决定；规则只影响排序与标记。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            statStrip
        }
        .cnHeroPanel()
    }

    private var statStrip: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                stat("待审核", CNL10n.format("%d 条", store.evolutionMemory.pendingRuleCount), "尚未影响任何排序")
                statDivider
                stat("已启用", CNL10n.format("%d 条", store.evolutionMemory.enabledRuleCount), "可随时暂停或撤销")
                statDivider
                stat("试用中", CNL10n.format("%d 条", store.evolutionMemory.trialRuleCount), "到期自动暂停")
                statDivider
                stat("模型评价", CNL10n.format("%d 条", store.evolutionMemory.modelFeedbackCount), "用于比较本机模型")
            }
            VStack(spacing: 12) {
                stat("待审核", CNL10n.format("%d 条", store.evolutionMemory.pendingRuleCount), "尚未影响任何排序")
                Divider()
                stat("已启用", CNL10n.format("%d 条", store.evolutionMemory.enabledRuleCount), "可随时暂停或撤销")
                Divider()
                stat("试用中", CNL10n.format("%d 条", store.evolutionMemory.trialRuleCount), "到期自动暂停")
                Divider()
                stat("模型评价", CNL10n.format("%d 条", store.evolutionMemory.modelFeedbackCount), "用于比较本机模型")
            }
        }
        .cnInsetPanel()
    }

    private var statDivider: some View {
        Divider().frame(height: 42).padding(.horizontal, 18)
    }

    private func stat(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CNL10n.string(title)).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedMetric()
            Text(CNL10n.string(detail)).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var learningFlow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                flowStep("1", "你选择", "提出清理或保留倾向")
                flowArrow
                flowStep("2", "形成提案", "记录理由和证据次数")
                flowArrow
                flowStep("3", "你审核", "启用、暂停或撤销")
                flowArrow
                flowStep("4", "下次解释", "仅调整排序与标记")
            }
            VStack(alignment: .leading, spacing: 14) {
                flowStep("1", "你选择", "提出清理或保留倾向")
                flowStep("2", "形成提案", "记录理由和证据次数")
                flowStep("3", "你审核", "启用、暂停或撤销")
                flowStep("4", "下次解释", "仅调整排序与标记")
            }
        }
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
    }

    private func flowStep(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(CNTheme.accent)
                .frame(width: 28, height: 28)
                .background(CNTheme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(CNL10n.string(title)).font(.subheadline.weight(.semibold))
                Text(CNL10n.string(detail)).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memoryDetails: some View {
        VStack(spacing: 16) {
            ruleReview
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    cleanupMemory.frame(maxWidth: .infinity)
                    modelMemory.frame(maxWidth: .infinity)
                }
                VStack(spacing: 16) {
                    cleanupMemory
                    modelMemory
                }
            }
            recentLearning
        }
    }

    private var ruleReview: some View {
        let clusters = store.evolutionMemory.ruleClusters()
        let visibleClusters = Array(clusters.prefix(visibleRuleLimit))
        let impact = store.cleanupLearningSortingImpact
        return SurfaceCard(
            title: "类别规则审核台",
            symbol: "checklist",
            prominence: .prominent,
            tint: CNTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 12) {
                InlineBanner(
                    title: "一组规则代表同类证据，不代表批量删除",
                    detail: "规则按类型、位置级别、风险和时间聚合。启用后只改变下次列表顺序；不会勾选项目、扩大路径、删除文件或结束进程。",
                    kind: .success
                )

                sortingImpactPanel(impact)

                if store.evolutionMemory.expiredRuleCount() > 0 {
                    InlineBanner(
                        title: "有 \(store.evolutionMemory.expiredRuleCount()) 条试用规则已经到期",
                        detail: "它们已自动暂停，不再影响排序；可以一次清理这些过期记录。",
                        kind: .warning,
                        actionTitle: "清理过期规则"
                    ) {
                        store.removeExpiredCleanupRules()
                    }
                }

                if clusters.isEmpty {
                    compactEmpty(
                        symbol: "doc.badge.plus",
                        title: "还没有规则提案",
                        detail: "在清理列表中选择“提议：以后优先清理/保留”，或完成一次安全清理。"
                    )
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleClusters.enumerated()), id: \.element.id) { index, cluster in
                            ruleClusterRow(cluster)
                            if index < visibleClusters.count - 1 {
                                Divider().padding(.leading, 43)
                            }
                        }
                    }
                    if visibleClusters.count < clusters.count {
                        Button("再显示 \(min(100, clusters.count - visibleClusters.count)) 组") {
                            visibleRuleLimit += 100
                        }
                        .buttonStyle(.borderless)
                        .frame(maxWidth: .infinity)
                        .accessibilityHint("只加载更多类别规则，不会启用或修改规则")
                    }
                }
            }
        }
    }

    private func sortingImpactPanel(_ impact: CleanupRuleSortingImpact) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CNIconTile(symbol: "arrow.up.arrow.down", tint: CNTheme.cyan, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("对当前清理列表的真实影响")
                    .font(.subheadline.weight(.semibold))
                if store.cleanupCandidates.isEmpty {
                    Text("当前没有保留扫描结果；下次扫描后会显示具体有多少项目被前移或后移。")
                } else if impact.matchedCount == 0 {
                    Text("当前扫描结果没有命中已启用规则，排序保持原样。")
                } else {
                    Text("命中 \(impact.matchedCount) 项，其中 \(impact.movedCount) 项位置发生变化：\(impact.preferCleanupCount) 项前移复核，\(impact.preferKeepCount) 项后移保留。")
                }
                Text("已选数量与安全校验：0 项被规则自动改变。")
                    .foregroundStyle(CNTheme.mint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
        .padding(12)
        .background(CNTheme.cyan.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("规则排序影响，命中 \(impact.matchedCount) 项，移动 \(impact.movedCount) 项，没有自动改变选择")
    }

    private func ruleClusterRow(_ cluster: CleanupRuleCluster) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                ruleClusterDescription(cluster)
                Spacer(minLength: 12)
                ruleClusterActions(cluster)
            }
            VStack(alignment: .leading, spacing: 11) {
                ruleClusterDescription(cluster)
                ruleClusterActions(cluster)
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(cluster.kind.rawValue)，\(cluster.locationLevel.displayName)，\(cluster.riskLevel.displayName)，\(cluster.ageBand.displayName)，共 \(cluster.proposalCount) 条规则")
    }

    private func ruleClusterDescription(_ cluster: CleanupRuleCluster) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CNIconTile(
                symbol: cluster.suggestedPreference == .preferKeep ? "hand.raised.fill" : cluster.kind.symbolName,
                tint: cluster.suggestedPreference == .preferKeep ? CNTheme.warning : CNTheme.success,
                size: 34
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("\(cluster.kind.rawValue) · \(cluster.locationLevel.displayName)")
                        .font(.subheadline.weight(.semibold))
                    StatusPill(
                        text: cluster.riskLevel.displayName,
                        symbol: cluster.riskLevel == .high ? "exclamationmark.triangle" : nil,
                        style: cluster.riskLevel == .high ? .warning : .neutral
                    )
                    StatusPill(
                        text: cluster.suggestedPreference == .preferKeep ? "优先保留" : "优先复核",
                        symbol: nil,
                        style: cluster.suggestedPreference == .preferKeep ? .warning : .success
                    )
                }
                Text("\(cluster.ageBand.displayName) · \(cluster.proposalCount) 条文件证据 · 共 \(cluster.evidenceCount) 次判断")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ruleClusterStateText(cluster))
                    .font(.caption2)
                    .foregroundStyle(cluster.expiredCount > 0 ? CNTheme.warning : Color.secondary.opacity(0.72))
                if !cluster.exampleNames.isEmpty {
                    Text("示例：\(cluster.exampleNames.joined(separator: "、"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func ruleClusterActions(_ cluster: CleanupRuleCluster) -> some View {
        HStack(spacing: 8) {
            if cluster.pendingCount > 0 || cluster.pausedCount > 0 {
                Button("审核并启用") { store.enableCleanupRuleCluster(cluster) }
                .buttonStyle(.borderedProminent)
                Button("试用 7 天") { store.trialCleanupRuleCluster(cluster) }
            }
            if cluster.enabledCount > 0 {
                Button("暂停") { store.pauseCleanupRuleCluster(cluster) }
            }
            Button("撤销", role: .destructive) { store.removeCleanupRuleCluster(cluster) }
        }
        .controlSize(.small)
    }

    private func ruleClusterStateText(_ cluster: CleanupRuleCluster) -> String {
        var parts: [String] = []
        if cluster.pendingCount > 0 { parts.append("待审核 \(cluster.pendingCount)") }
        if cluster.enabledCount > 0 { parts.append("已启用 \(cluster.enabledCount)") }
        if cluster.trialCount > 0 { parts.append("试用中 \(cluster.trialCount)") }
        if cluster.pausedCount > 0 { parts.append("已暂停 \(cluster.pausedCount)") }
        if cluster.expiredCount > 0 { parts.append("已到期 \(cluster.expiredCount)") }
        return parts.joined(separator: " · ")
    }

    private var cleanupMemory: some View {
        SurfaceCard(title: "已生效偏好", symbol: "arrow.up.arrow.down") {
            if store.evolutionMemory.sortedCleanupSignals.isEmpty {
                compactEmpty(symbol: "cursorarrow.click.2", title: "还没有已启用规则", detail: "先在上方审核并启用提案。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.evolutionMemory.sortedCleanupSignals.prefix(8).enumerated()), id: \.element.id) { index, signal in
                        HStack(spacing: 10) {
                            Image(systemName: signal.effectivePreference == .preferKeep ? "hand.raised" : "sparkles")
                                .foregroundStyle(signal.effectivePreference == .preferKeep ? CNTheme.warning : CNTheme.success)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(signal.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text(signal.kind.rawValue).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            StatusPill(
                                text: signal.effectivePreference == .preferKeep ? "优先保留" : "优先清理",
                                symbol: nil,
                                style: signal.effectivePreference == .preferKeep ? .warning : .success
                            )
                        }
                        .padding(.vertical, 9)
                        if index < min(8, store.evolutionMemory.sortedCleanupSignals.count) - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            }
        }
    }

    private var modelMemory: some View {
        let signals = store.evolutionMemory.sortedModelSignals
        let visibleSignals = Array(signals.prefix(visibleModelLimit))
        return SurfaceCard(title: "模型表现", symbol: "brain.head.profile") {
            if store.evolutionMemory.sortedModelSignals.isEmpty {
                compactEmpty(symbol: "hand.thumbsup", title: "还没有模型评价", detail: "完成一次 AI 分析后，评价建议是否有帮助。")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(visibleSignals.enumerated()), id: \.element.id) { index, signal in
                        HStack(spacing: 10) {
                            Image(systemName: "cpu").foregroundStyle(CNTheme.accent).frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(signal.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                                Text("有帮助 \(signal.helpfulCount) · 不准确 \(signal.unhelpfulCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let ratio = signal.helpfulRatio {
                                Text("\(Int((ratio * 100).rounded()))%")
                                    .font(.title3.weight(.semibold))
                                    .monospacedMetric()
                                    .foregroundStyle(ratio >= 0.6 ? CNTheme.success : CNTheme.warning)
                            }
                        }
                        .padding(.vertical, 9)
                        if index < visibleSignals.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
                if visibleSignals.count < signals.count {
                    Button("再显示 \(min(50, signals.count - visibleSignals.count)) 个模型") {
                        visibleModelLimit += 50
                    }
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var recentLearning: some View {
        SurfaceCard(title: "最近学到什么", symbol: "clock.arrow.circlepath") {
            VStack(spacing: 0) {
                ForEach(Array(store.evolutionMemory.events.prefix(10).enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: eventSymbol(event.kind))
                            .foregroundStyle(eventTint(event.kind))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.subheadline.weight(.medium))
                            Text(event.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(event.date, style: .relative).font(.caption2).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                    if index < min(10, store.evolutionMemory.events.count) - 1 {
                        Divider().padding(.leading, 37)
                    }
                }
            }
        }
    }

    private var resetControl: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("你始终拥有最终控制权").font(.subheadline.weight(.semibold))
                Text("清空学习记录不会删除扫描结果、文件或本机模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("清空本机学习记录", role: .destructive) {
                confirmingReset = true
            }
        }
    }

    private func compactEmpty(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).foregroundStyle(CNTheme.accent).frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(CNL10n.string(title)).font(.subheadline.weight(.medium))
                Text(CNL10n.string(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 7)
    }

    private func eventSymbol(_ kind: EvolutionEvent.Kind) -> String {
        switch kind {
        case .cleanupPreference: return "cursorarrow.click.2"
        case .successfulCleanup: return "checkmark.circle"
        case .modelFeedback: return "brain.head.profile"
        case .ruleProposal: return "doc.badge.plus"
        case .ruleState: return "checklist"
        }
    }

    private func eventTint(_ kind: EvolutionEvent.Kind) -> Color {
        switch kind {
        case .cleanupPreference: return CNTheme.accent
        case .successfulCleanup: return CNTheme.success
        case .modelFeedback: return CNTheme.warning
        case .ruleProposal: return CNTheme.violet
        case .ruleState: return CNTheme.cyan
        }
    }
}

private struct LearningOrbitGraphic: View {
    var compact = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(CNTheme.accent.opacity(0.18), lineWidth: 0.8))
                .frame(width: compact ? 112 : 158, height: compact ? 112 : 158)

            Circle()
                .stroke(CNTheme.accent.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
                .frame(width: compact ? 82 : 122, height: compact ? 82 : 122)

            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.system(size: compact ? 27 : 37, weight: .medium))
                .foregroundStyle(CNTheme.accent)
                .shadow(color: CNTheme.accent.opacity(0.18), radius: 10)

            orbitNode("hand.raised.fill", tint: CNTheme.warning)
                .offset(x: compact ? -43 : -61, y: compact ? -32 : -45)
            orbitNode("checkmark", tint: CNTheme.success)
                .offset(x: compact ? 46 : 64, y: compact ? -12 : -17)
            orbitNode("brain.head.profile", tint: CNTheme.accent)
                .offset(x: compact ? -4 : -6, y: compact ? 52 : 73)
        }
        .frame(width: compact ? 142 : 205, height: compact ? 136 : 196)
        .accessibilityHidden(true)
    }

    private func orbitNode(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: compact ? 9 : 11, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: compact ? 25 : 30, height: compact ? 25 : 30)
            .background(.regularMaterial, in: Circle())
            .overlay(Circle().stroke(tint.opacity(0.22), lineWidth: 0.7))
    }
}
