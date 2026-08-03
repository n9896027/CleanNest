import SwiftUI
import CleanNestCore

struct CleanupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var confirmingTrash = false

    private var filteredCandidates: [CleanupCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return store.cleanupCandidates }
        return store.cleanupCandidates.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.url.path.localizedCaseInsensitiveContains(query)
                || $0.kind.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedCandidates: [(CleanupKind, [CleanupCandidate])] {
        let originalOrder = Dictionary(
            uniqueKeysWithValues: filteredCandidates.enumerated().map { ($0.element.id, $0.offset) }
        )
        return CleanupKind.allCases.compactMap { kind -> (CleanupKind, [CleanupCandidate])? in
            let items = filteredCandidates.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            guard store.cleanupAIAnalysis != nil else { return (kind, items) }

            let sorted = items.sorted { lhs, rhs in
                let leftPriority = store.aiAdvice(for: lhs)?.priority ?? 4
                let rightPriority = store.aiAdvice(for: rhs)?.priority ?? 4
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                return originalOrder[lhs.id, default: .max] < originalOrder[rhs.id, default: .max]
            }
            return (kind, sorted)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        title: "清理空间",
                        subtitle: "所有项目先预览，执行时只会移到废纸篓。"
                    ) {
                        HStack(spacing: 8) {
                            Button("推荐项") {
                                store.selectedCleanupIDs = Set(store.cleanupCandidates.filter(\.isRecommended).map(\.id))
                            }
                            .disabled(store.cleanupCandidates.isEmpty)
                            Button {
                                Task { await store.scanCleanup() }
                            } label: {
                                Label(store.cleanupHasScanned ? "重新扫描" : "开始扫描", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(store.isWorking)
                        }
                    }

                    InlineBanner(
                        title: "安全模式已开启",
                        detail: "CleanNest 会拒绝系统目录、允许范围根目录和符号链接；废纸篓失败时不会改为永久删除。",
                        kind: .success
                    )

                    if !store.cleanupCandidates.isEmpty {
                        LocalAIAdviceCard()
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("搜索名称或路径", text: $searchText)
                                .textFieldStyle(.plain)
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CNTheme.divider, lineWidth: 0.7))

                        Toggle("包含应用缓存", isOn: $store.includeApplicationCaches)
                            .toggleStyle(.switch)
                            .help("应用缓存默认不扫描；开启后也不会自动勾选。")
                    }

                    if !store.cleanupHasScanned {
                        EmptyPanel(
                            symbol: "sparkle.magnifyingglass",
                            title: "先扫描，再做决定",
                            detail: "CleanNest 会检查开发缓存、下载的安装包和旧日志。扫描过程不会改动文件。",
                            actionTitle: "扫描可清理内容"
                        ) {
                            Task { await store.scanCleanup() }
                        }
                    } else if store.cleanupCandidates.isEmpty {
                        EmptyPanel(
                            symbol: "checkmark.seal",
                            title: "这里很干净",
                            detail: "本次没有发现建议清理的内容。你可以稍后重新扫描。",
                            actionTitle: "重新扫描"
                        ) {
                            Task { await store.scanCleanup() }
                        }
                    } else if groupedCandidates.isEmpty {
                        EmptyPanel(
                            symbol: "line.3.horizontal.decrease.circle",
                            title: "没有符合筛选条件的项目",
                            detail: "清除搜索词即可查看完整结果。",
                            actionTitle: "清除搜索"
                        ) {
                            searchText = ""
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(groupedCandidates, id: \.0) { kind, items in
                                CleanupGroup(kind: kind, candidates: items)
                            }
                        }
                    }
                }
                .padding(CNTheme.pagePadding)
                .padding(.bottom, store.cleanupCandidates.isEmpty ? 0 : 68)
            }

            if !store.cleanupCandidates.isEmpty {
                ReviewBar(
                    count: store.selectedCleanupCount,
                    bytes: store.selectedCleanupBytes,
                    actionTitle: "移到废纸篓",
                    disabled: store.selectedCleanupCount == 0 || store.isWorking
                ) {
                    confirmingTrash = true
                }
            }
        }
        .alert("将 \(store.selectedCleanupCount) 项移到废纸篓？", isPresented: $confirmingTrash) {
            Button("返回检查", role: .cancel) { }
            Button("移到废纸篓") {
                Task { await store.trashSelectedCleanup() }
            }
        } message: {
            Text("预计释放 \(CleanNestFormatting.bytes(store.selectedCleanupBytes))。这些内容可在清空废纸篓前恢复。")
        }
    }
}

private struct CleanupGroup: View {
    @EnvironmentObject private var store: AppStore
    let kind: CleanupKind
    let candidates: [CleanupCandidate]

    private var total: Int64 { candidates.reduce(0) { $0 + $1.allocatedBytes } }

    var body: some View {
        SurfaceCard {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: kind.symbolName)
                        .foregroundStyle(CNTheme.accent)
                    Text(kind.rawValue).font(.headline)
                    StatusPill(text: "\(candidates.count) 项", symbol: nil)
                    Spacer()
                    Text(CleanNestFormatting.bytes(total))
                        .font(.subheadline.weight(.semibold))
                        .monospacedMetric()
                }
                .padding(.bottom, 10)

                Divider()

                ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                    CleanupRow(candidate: candidate)
                    if index < candidates.count - 1 { Divider().padding(.leading, 38) }
                }
            }
        }
    }
}

private struct CleanupRow: View {
    @EnvironmentObject private var store: AppStore
    let candidate: CleanupCandidate

    private var isSelected: Binding<Bool> {
        Binding(
            get: { store.selectedCleanupIDs.contains(candidate.id) },
            set: { selected in
                if selected { store.selectedCleanupIDs.insert(candidate.id) }
                else { store.selectedCleanupIDs.remove(candidate.id) }
            }
        )
    }

    private var aiAdvice: CleanupAIAdvice? { store.aiAdvice(for: candidate) }

    var body: some View {
        HStack(spacing: 11) {
            Toggle("", isOn: isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("选择 \(candidate.name)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(candidate.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    StatusPill(
                        text: candidate.isRecommended ? "通常可重新生成" : "需要查看",
                        symbol: candidate.isRecommended ? "checkmark.shield" : "eye",
                        style: candidate.isRecommended ? .success : .warning
                    )
                }
                Text(candidate.url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(candidate.detail) · \(CleanNestFormatting.age(from: candidate.modifiedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let advice = aiAdvice {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        StatusPill(
                            text: aiAdviceLabel(advice),
                            symbol: aiAdviceSymbol(advice),
                            style: aiAdviceStyle(advice)
                        )
                        Text(advice.reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text(CleanNestFormatting.bytes(candidate.allocatedBytes))
                    .font(.subheadline.weight(.semibold))
                    .monospacedMetric()
                Text("移到废纸篓")
                    .font(.caption2)
                    .foregroundStyle(CNTheme.success)
            }

            Button {
                store.revealInFinder(candidate.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中显示")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture { store.toggleCleanup(candidate) }
        .contextMenu {
            Button("在 Finder 中显示") { store.revealInFinder(candidate.url) }
            Divider()
            Button(store.selectedCleanupIDs.contains(candidate.id) ? "取消选择" : "选择") {
                store.toggleCleanup(candidate)
            }
        }
    }

    private func aiAdviceLabel(_ advice: CleanupAIAdvice) -> String {
        let verdict: String
        switch advice.verdict {
        case .reclaimable: verdict = "适合清理"
        case .review: verdict = "建议检查"
        case .keep: verdict = "建议保留"
        }
        return "AI 优先 \(advice.priority)：\(verdict)"
    }

    private func aiAdviceSymbol(_ advice: CleanupAIAdvice) -> String {
        switch advice.verdict {
        case .reclaimable: return "sparkles"
        case .review: return "eye"
        case .keep: return "hand.raised"
        }
    }

    private func aiAdviceStyle(_ advice: CleanupAIAdvice) -> StatusPill.Style {
        switch advice.risk {
        case .low: return .success
        case .medium: return .warning
        case .high: return .danger
        }
    }
}

private struct LocalAIAdviceCard: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "brain.head.profile")
                        .foregroundStyle(CNTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(CNTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本机 AI 深度分析")
                            .font(.headline)
                        Text("只读扫描元数据，不读取文件内容，也不会改变你的勾选。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    if store.localAIIsReady {
                        StatusPill(text: store.localAIModelDisplayName, symbol: "cpu", style: .success)
                            .lineLimit(1)
                            .frame(maxWidth: 180)
                    }
                    actionButton
                }

                switch store.cleanupAIPhase {
                case .analyzing:
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text("\(store.localAIModelDisplayName) 正在判断体积最大的 \(min(store.cleanupCandidates.count, CleanupAIRequestBuilder.maximumCandidates)) 项…")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                case .failed(let message):
                    InlineBanner(
                        title: "AI 建议暂时不可用",
                        detail: message + " 普通扫描结果仍然有效。",
                        kind: .warning
                    )
                case .completed, .idle:
                    analysisContent
                }
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if store.localAIIsReady {
            Button(store.cleanupAIAnalysis == nil ? "用本机 AI 分析" : "重新分析") {
                Task { await store.analyzeCleanupWithLocalAI() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.cleanupAIPhase.isBusy)
        } else if store.localAIServiceState.isBusy {
            ProgressView().controlSize(.small)
        } else {
            Button("在设置中连接") { store.selection = .settings }
        }
    }

    @ViewBuilder
    private var analysisContent: some View {
        if let analysis = store.cleanupAIAnalysis {
            Divider()
            Text(analysis.summary)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                StatusPill(
                    text: "已分析 \(analysis.requestedCount) 项",
                    symbol: "checkmark.circle",
                    style: .success
                )
                if store.cleanupCandidates.count > analysis.requestedCount {
                    Text("优先覆盖体积最大的项目")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(Array(analysis.cautions.enumerated()), id: \.offset) { _, caution in
                Label(caution, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(localAIEmptyDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var localAIEmptyDetail: String {
        switch store.localAIServiceState {
        case .disabled:
            return "本机 AI 已关闭；普通规则扫描仍可独立使用。"
        case .ready:
            return "让本机 Gemma 根据类型、体积和修改时间补充清理顺序与风险说明。"
        case .checking:
            return "正在检测本机模型服务。"
        case .starting:
            return "模型正在载入，完成后即可分析。"
        case .stopping:
            return "模型正在停止；普通规则扫描不受影响。"
        case .unchecked:
            return "尚未检测本机模型，可前往设置连接。"
        case .unavailable(let detail):
            return detail
        }
    }
}
