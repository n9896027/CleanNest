import SwiftUI
import CleanNestCore

struct CleanupView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var confirmingTrash = false
    @State private var confirmingMountedInstallerEject = false
    @State private var mountedInstallerPendingEject: MountedInstallerVolume?

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

            let sorted = items.sorted { lhs, rhs in
                let leftLearningRank = store.cleanupLearningRank(for: lhs)
                let rightLearningRank = store.cleanupLearningRank(for: rhs)
                if leftLearningRank != rightLearningRank {
                    return leftLearningRank < rightLearningRank
                }
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
                        subtitle: "把可重建缓存、桌面/下载安装包、个人媒体与重复副本分开判断。"
                    ) {
                        HStack(spacing: 8) {
                            Button("推荐项") {
                                store.selectedCleanupIDs = Set(store.cleanupCandidates.filter(\.isRecommended).map(\.id))
                            }
                            .disabled(store.cleanupCandidates.isEmpty)
                            if store.cleanupScanIsActive {
                                Button("取消", role: .cancel) {
                                    store.cancelCleanupScan()
                                }
                                .buttonStyle(.borderedProminent)
                            } else {
                                Button {
                                    Task { await store.scanCleanup() }
                                } label: {
                                    Label(store.cleanupHasScanned ? "重新扫描" : "开始扫描", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.isWorking)
                            }
                        }
                    }

                    InlineBanner(
                        title: "安全模式已开启",
                        detail: "个人下载和媒体默认不勾选；重复文件执行前会重新核验保留副本与 SHA-256，失败时不会改为永久删除。",
                        kind: .success
                    )

                    if store.cleanupHasScanned {
                        CleanupEvidenceOverview(
                            insights: store.cleanupScanInsights,
                            screenshotCount: store.cleanupScreenshotCount,
                            mediaScanEnabled: store.cleanupScanIncludedMediaAndDuplicates
                        )
                    }

                    if store.cleanupHasScanned, !store.mountedInstallerVolumes.isEmpty {
                        MountedInstallerVolumesCard(
                            volumes: store.mountedInstallerVolumes,
                            ejectingID: store.ejectingMountedInstallerID
                        ) { volume in
                            mountedInstallerPendingEject = volume
                            confirmingMountedInstallerEject = true
                        }
                    }

                    if let mountedInstallerMessage = store.mountedInstallerMessage {
                        InlineBanner(
                            title: store.mountedInstallerMessageIsWarning
                                ? "安装介质需要处理"
                                : "安装介质已更新",
                            detail: mountedInstallerMessage,
                            kind: store.mountedInstallerMessageIsWarning ? .warning : .success
                        )
                    }

                    if !store.cleanupCandidates.isEmpty {
                        LocalAIAdviceCard()
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            cleanupSearchField
                            cleanupScanToggles
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            cleanupSearchField
                            cleanupScanToggles
                        }
                    }

                    if !store.cleanupHasScanned {
                        EmptyPanel(
                            symbol: "sparkle.magnifyingglass",
                            title: "先扫描，再做决定",
                            detail: "CleanNest 会检查缓存、桌面/下载安装包、已挂载安装介质和大型媒体；启用媒体分析时还会用本机 SHA-256 查找字节完全相同的副本。扫描不会改动文件。",
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
            Text(confirmationDetail)
        }
        .confirmationDialog(
            mountedInstallerPendingEject.map {
                CNL10n.format("推出“%@”？", $0.displayName)
            } ?? CNL10n.string("推出安装介质？"),
            isPresented: $confirmingMountedInstallerEject,
            titleVisibility: .visible,
            presenting: mountedInstallerPendingEject
        ) { volume in
            Button("安全推出") {
                Task { await store.ejectMountedInstaller(volume) }
            }
            Button("取消", role: .cancel) { }
        } message: { volume in
            if volume.sourceExists {
                Text("只会卸载当前磁盘映像，不会删除或移动原始安装包。请先关闭从该卷打开的安装程序。")
            } else {
                Text("原始安装包路径已不存在。推出后桌面图标会消失；若要再次打开，需要重新下载安装包。")
            }
        }
    }

    private var cleanupSearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索名称或路径", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(.horizontal, 11)
        .frame(minWidth: 220, maxWidth: .infinity, minHeight: 34, maxHeight: 34)
        .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(CNTheme.divider, lineWidth: 0.7))
    }

    private var cleanupScanToggles: some View {
        HStack(spacing: 14) {
            Toggle("下次扫描：媒体与重复文件", isOn: $store.includeMediaAndDuplicates)
                .toggleStyle(.switch)
                .help("只在本机读取媒体元数据；仅对同尺寸文件计算 SHA-256，不上传文件或哈希。")
            Toggle("下次扫描：应用缓存", isOn: $store.includeApplicationCaches)
                .toggleStyle(.switch)
                .help("应用缓存默认不扫描；开启后也不会自动勾选。")
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(store.cleanupScanIsActive)
    }

    private var confirmationDetail: String {
        var parts = [CNL10n.format(
            "候选体积 %@，实际 APFS 释放量以清空废纸篓后为准。",
            CleanNestFormatting.bytes(store.selectedCleanupBytes)
        )]
        if store.selectedPersonalCleanupCount > 0 {
            parts.append(CNL10n.format(
                "其中 %d 项属于下载或个人媒体，请确认不再需要。",
                store.selectedPersonalCleanupCount
            ))
        }
        if store.selectedDuplicateCleanupCount > 0 {
            parts.append(CNL10n.format(
                "%d 个重复副本会在移动前再次核验内容，并确保扫描时选定的保留副本仍存在。",
                store.selectedDuplicateCleanupCount
            ))
        }
        parts.append(CNL10n.string("这些内容可在清空废纸篓前恢复。"))
        return parts.joined(separator: " ")
    }
}

private struct CleanupEvidenceOverview: View {
    let insights: CleanupScanInsights
    let screenshotCount: Int
    let mediaScanEnabled: Bool

    private let columns = [GridItem(.adaptive(minimum: 155), spacing: 0)]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(CNTheme.cyan)
                        .frame(width: 32, height: 32)
                        .background(CNTheme.cyan.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本机文件证据")
                            .font(.headline)
                        Text("先判断来源与内容关系，再让你决定；扫描结果本身不会删除文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: "仅在本机", symbol: "lock.shield", style: .success)
                }

                Divider()

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    EvidenceMetric(
                        label: "安装包与归档",
                        value: CNL10n.format("%d 项", insights.installerCount + insights.archiveCount),
                        detail: CNL10n.format("桌面/下载：%d 个安装包 · %d 个归档", insights.installerCount, insights.archiveCount),
                        symbol: "arrow.down.doc",
                        tint: CNTheme.warning
                    )
                    EvidenceMetric(
                        label: "个人媒体",
                        value: mediaScanEnabled ? CNL10n.format("%d 项", insights.mediaCount) : CNL10n.string("未启用"),
                        detail: CNL10n.format("图片 %d（截图 %d）· 视频 %d · 音频 %d", insights.imageCount, screenshotCount, insights.videoCount, insights.audioCount),
                        symbol: "photo.on.rectangle.angled",
                        tint: CNTheme.violet
                    )
                    EvidenceMetric(
                        label: "完全重复",
                        value: mediaScanEnabled ? CNL10n.format("%d 组", insights.duplicateGroupCount) : CNL10n.string("未启用"),
                        detail: CNL10n.format("%d 个副本 · %@", insights.duplicateFileCount, CleanNestFormatting.bytes(insights.duplicateBytes)),
                        symbol: "square.on.square",
                        tint: CNTheme.success
                    )
                    EvidenceMetric(
                        label: "检查范围",
                        value: CNL10n.format("%d 个文件", insights.examinedFileCount),
                        detail: CNL10n.string(insights.wasLimited ? "达到本轮安全上限" : "有界扫描已完成"),
                        symbol: "scope",
                        tint: CNTheme.accent
                    )
                }

                Text("截图按 ScreenShot、Screenshot、Screen Shot、ScreenCapture、截屏或截图等文件名直接识别，不受大图和时间门槛限制；其他媒体仍要求至少 14 天未修改，图片 ≥ 5 MB、视频 ≥ 100 MB、音频 ≥ 20 MB。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("同一文件可能同时属于下载/媒体与完全重复，所以上方数量不能直接相加；列表保留原始类型，并用“字节完全相同”标记重叠项目。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if insights.wasLimited || insights.skippedCloudItemCount > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Image(systemName: "info.circle")
                        Text(limitDetail)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var limitDetail: String {
        var messages: [String] = []
        if insights.wasLimited { messages.append(CNL10n.string("为控制耗时，本轮在文件或哈希上限处停止；结果是部分集合。")) }
        if insights.skippedCloudItemCount > 0 {
            messages.append(CNL10n.format("跳过 %d 个尚未完整下载的云端占位文件，避免触发下载。", insights.skippedCloudItemCount))
        }
        return messages.joined(separator: " ")
    }
}

private struct MountedInstallerVolumesCard: View {
    let volumes: [MountedInstallerVolume]
    let ejectingID: String?
    let onEject: (MountedInstallerVolume) -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .foregroundStyle(CNTheme.warning)
                        .frame(width: 32, height: 32)
                        .background(CNTheme.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("已挂载安装介质")
                            .font(.headline)
                        Text("与可删除的安装包分开管理；不会把 /Volumes 内容加入清理清单。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(text: CNL10n.format("%d 个", volumes.count), symbol: "externaldrive")
                }

                Divider()

                VStack(spacing: 0) {
                    ForEach(Array(volumes.enumerated()), id: \.element.id) { index, volume in
                        mountedVolumeRow(volume)
                        if index < volumes.count - 1 {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private func mountedVolumeRow(_ volume: MountedInstallerVolume) -> some View {
        HStack(spacing: 11) {
            CNIconTile(symbol: "externaldrive.fill", tint: CNTheme.warning, size: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(volume.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    StatusPill(
                        text: volume.sourceExists ? "原始包仍在" : "仅剩挂载卷",
                        symbol: volume.sourceExists ? "checkmark.circle" : "exclamationmark.triangle",
                        style: volume.sourceExists ? .success : .warning
                    )
                }
                Text(volume.mountURL.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(sourceDetail(volume))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            Spacer(minLength: 10)

            if let imageBytes = volume.imageBytes {
                Text(CleanNestFormatting.bytes(imageBytes))
                    .font(.caption.weight(.semibold))
                    .monospacedMetric()
                    .foregroundStyle(.secondary)
            }

            Button {
                onEject(volume)
            } label: {
                if ejectingID == volume.id {
                    ProgressView().controlSize(.small)
                } else {
                    Label("推出…", systemImage: "eject")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(ejectingID != nil)
            .help("不删除原始安装包，只安全卸载当前磁盘映像")
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func sourceDetail(_ volume: MountedInstallerVolume) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let source = volume.sourceURL.path.replacingOccurrences(of: home, with: "~")
        if volume.sourceExists {
            return CNL10n.format("原始安装包：%@；推出不会删除它。", source)
        }
        return CNL10n.format("原始路径已不存在：%@；推出后需重新下载才能再打开。", source)
    }
}

private struct EvidenceMetric: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(CNL10n.string(label))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(CNL10n.string(value))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(CNL10n.string(detail))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupGroup: View {
    @EnvironmentObject private var store: AppStore
    let kind: CleanupKind
    let candidates: [CleanupCandidate]
    @State private var isExpanded: Bool

    private var total: Int64 { candidates.reduce(0) { $0 + $1.allocatedBytes } }
    private var selectedCount: Int {
        candidates.reduce(0) { $0 + (store.selectedCleanupIDs.contains($1.id) ? 1 : 0) }
    }
    private var allSelected: Bool { !candidates.isEmpty && selectedCount == candidates.count }
    private var selectionTitle: String {
        if allSelected { return "取消全选" }
        return kind == .screenshot ? "全选截图" : "全选本组"
    }

    init(kind: CleanupKind, candidates: [CleanupCandidate]) {
        self.kind = kind
        self.candidates = candidates
        _isExpanded = State(initialValue: candidates.count <= 24)
    }

    var body: some View {
        SurfaceCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: kind.symbolName)
                                .foregroundStyle(CNTheme.accent)
                            Text(CNL10n.string(kind.rawValue)).font(.headline)
                            StatusPill(text: CNL10n.format("%d 项", candidates.count), symbol: nil)
                            Spacer()
                            Text(CleanNestFormatting.bytes(total))
                                .font(.subheadline.weight(.semibold))
                                .monospacedMetric()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(CNL10n.format("%@，%d 项，%@", CNL10n.string(kind.rawValue), candidates.count, CleanNestFormatting.bytes(total)))
                    .accessibilityHint(CNL10n.string(isExpanded ? "收起分组" : "展开查看全部项目"))

                    Button {
                        store.setCleanupSelection(candidates, selected: !allSelected)
                    } label: {
                        Label(
                            CNL10n.string(selectionTitle),
                            systemImage: allSelected ? "checkmark.square.fill" : "checkmark.square"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint(CNL10n.format("仅修改 %@ 分组的勾选，不会立即移动文件", CNL10n.string(kind.rawValue)))
                }

                if isExpanded {
                    Divider()
                        .padding(.top, 10)

                    LazyVStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            CleanupRow(candidate: candidate)
                            if index < candidates.count - 1 { Divider().padding(.leading, 38) }
                        }
                    }
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
    private var learnedPreference: LearnedCleanupPreference? {
        store.learnedCleanupPreference(for: candidate)
    }
    private var learningSignal: CleanupLearningSignal? {
        store.cleanupLearningSignal(for: candidate)
    }
    private var ruleProposal: CleanupRuleProposal? {
        store.cleanupRuleProposal(for: candidate)
    }

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
                        text: reviewStatus.text,
                        symbol: reviewStatus.symbol,
                        style: reviewStatus.style
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
                if let learnedPreference {
                    HStack(spacing: 7) {
                        StatusPill(
                            text: learnedPreference == .preferKeep ? "已学习：优先保留" : "已学习：优先清理",
                            symbol: learnedPreference == .preferKeep ? "hand.raised" : "sparkles",
                            style: learnedPreference == .preferKeep ? .warning : .success
                        )
                        Text(learningDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 1)
                } else if let ruleProposal {
                    HStack(spacing: 7) {
                        StatusPill(
                            text: ruleProposal.state == .pending ? "待审核规则" : "规则已暂停",
                            symbol: ruleProposal.state == .pending ? "doc.badge.clock" : "pause.circle",
                            style: ruleProposal.state == .pending ? .warning : .neutral
                        )
                        Text("不会改变排序，需到本机学习页确认")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 1)
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

            Menu {
                learningMenuContent
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("创建或管理本机学习规则")
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
            Divider()
            learningMenuContent
        }
    }

    @ViewBuilder
    private var learningMenuContent: some View {
        Button {
            store.rememberCleanupPreference(candidate, preference: .preferCleanup)
        } label: {
            Label("提议：以后优先清理", systemImage: "sparkles")
        }
        Button {
            store.rememberCleanupPreference(candidate, preference: .preferKeep)
        } label: {
            Label("提议：以后优先保留", systemImage: "hand.raised")
        }
        if ruleProposal != nil {
            Divider()
            Button {
                store.selection = .evolution
            } label: {
                Label("打开规则审核", systemImage: "checklist")
            }
            Button {
                store.forgetCleanupPreference(candidate)
            } label: {
                Label("撤销这条提案/规则", systemImage: "arrow.uturn.backward")
            }
        }
    }

    private var learningDetail: String {
        guard let signal = learningSignal else { return "" }
        if signal.explicitPreference != nil { return "来自你的明确判断" }
        if signal.successfulCleanupCount > 0 {
            return "你曾安全清理 \(signal.successfulCleanupCount) 次"
        }
        return "本机记录"
    }

    private var reviewStatus: (text: String, symbol: String, style: StatusPill.Style) {
        if candidate.duplicateEvidence != nil {
            return ("字节完全相同", "checkmark.seal", .success)
        }
        switch candidate.kind {
        case .duplicate:
            return ("字节完全相同", "checkmark.seal", .success)
        case .installer:
            return ("下载安装介质", "externaldrive", .warning)
        case .archive:
            return ("资料归档 · 需复核", "archivebox", .warning)
        case .screenshot:
            return ("截图 · 可批量选择", "camera.viewfinder", .warning)
        case .image, .video, .audio:
            return ("个人媒体 · 手动选择", "hand.raised", .warning)
        default:
            return candidate.isRecommended
                ? ("通常可重新生成", "checkmark.shield", .success)
                : ("需要查看", "eye", .warning)
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
            AIFeedbackControl(feedback: store.cleanupAIFeedback) { helpful in
                store.recordCleanupAIFeedback(helpful: helpful)
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
            return "让你选择的本机模型根据类型、体积和修改时间补充清理顺序与风险说明。"
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
