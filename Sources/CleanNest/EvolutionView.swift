import SwiftUI
import CleanNestCore

struct EvolutionView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmingReset = false

    private var hasMemory: Bool {
        !store.evolutionMemory.events.isEmpty
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
        }
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
                Text("只保存项目类型、你的选择和模型评价；不保存文件内容或完整路径。")
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
            Text("先完成一次空间扫描，再对某个项目选择“以后优先清理”或“以后优先保留”。CleanNest 会把这条理由带到下一次扫描，而不是只给你三个没有意义的 0。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 500, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    store.selection = .cleanup
                    Task { if !store.cleanupHasScanned { await store.scanCleanup() } }
                } label: {
                    Label("扫描并建立第一条偏好", systemImage: "sparkle.magnifyingglass")
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
                        Text("CleanNest 正在形成你的本机偏好")
                            .font(.system(size: 25, weight: .semibold, design: .rounded))
                        Text("熟悉的项目会按你的清理或保留习惯排序，并明确标注依据。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 18)
                    LearningOrbitGraphic(compact: true)
                }
                VStack(alignment: .leading, spacing: 18) {
                    Text("CleanNest 正在形成你的本机偏好")
                        .font(.system(size: 25, weight: .semibold, design: .rounded))
                    Text("熟悉的项目会按你的清理或保留习惯排序，并明确标注依据。")
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
                stat("已学会", CNL10n.format("%d 项", store.evolutionMemory.learnedCleanupCount), "清理或保留偏好")
                statDivider
                stat("安全清理", CNL10n.format("%d 次", store.evolutionMemory.successfulCleanupCount), "成功移到废纸篓")
                statDivider
                stat("模型评价", CNL10n.format("%d 条", store.evolutionMemory.modelFeedbackCount), "用于比较本机模型")
            }
            VStack(spacing: 12) {
                stat("已学会", CNL10n.format("%d 项", store.evolutionMemory.learnedCleanupCount), "清理或保留偏好")
                Divider()
                stat("安全清理", CNL10n.format("%d 次", store.evolutionMemory.successfulCleanupCount), "成功移到废纸篓")
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
                flowStep("1", "你确认", "明确选择清理或保留")
                flowArrow
                flowStep("2", "本机记住", "只记录偏好与理由")
                flowArrow
                flowStep("3", "下次解释", "排序时标出学习依据")
            }
            VStack(alignment: .leading, spacing: 14) {
                flowStep("1", "你确认", "明确选择清理或保留")
                flowStep("2", "本机记住", "只记录偏好与理由")
                flowStep("3", "下次解释", "排序时标出学习依据")
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

    private var cleanupMemory: some View {
        SurfaceCard(title: "清理偏好", symbol: "arrow.up.arrow.down") {
            if store.evolutionMemory.sortedCleanupSignals.isEmpty {
                compactEmpty(symbol: "cursorarrow.click.2", title: "还没有清理偏好", detail: "扫描后明确选择优先清理或保留。")
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
        SurfaceCard(title: "模型表现", symbol: "brain.head.profile") {
            if store.evolutionMemory.sortedModelSignals.isEmpty {
                compactEmpty(symbol: "hand.thumbsup", title: "还没有模型评价", detail: "完成一次 AI 分析后，评价建议是否有帮助。")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.evolutionMemory.sortedModelSignals.enumerated()), id: \.element.id) { index, signal in
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
                        if index < store.evolutionMemory.sortedModelSignals.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
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
        }
    }

    private func eventTint(_ kind: EvolutionEvent.Kind) -> Color {
        switch kind {
        case .cleanupPreference: return CNTheme.accent
        case .successfulCleanup: return CNTheme.success
        case .modelFeedback: return CNTheme.warning
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
