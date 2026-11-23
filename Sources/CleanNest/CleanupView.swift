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

    private var scanCoverageWarning: (title: String, detail: String)? {
        guard let session = store.cleanupScanSession else { return nil }
        let blockedRoots = session.roots.filter { $0.status == .unreadable || $0.status == .unsafe }
        let limitingSkips = session.skips.filter {
            switch $0.reason {
            case .unreadable, .unsafeRoot, .depthLimit, .fileLimit, .hashLimit:
                return true
            case .cloudPlaceholder, .symbolicLink, .packageBoundary:
                return false
            }
        }
        guard !blockedRoots.isEmpty || !limitingSkips.isEmpty else { return nil }

        var parts: [String] = []
        if !blockedRoots.isEmpty {
            parts.append(CNL10n.format("%@ 个位置未能安全读取", String(describing: blockedRoots.count)))
        }
        if !limitingSkips.isEmpty {
            let skippedCount = limitingSkips.reduce(0) { $0 + $1.count }
            parts.append(CNL10n.format("%@ 项因读取或本轮上限未纳入", String(describing: skippedCount)))
        }
        return (
            CNL10n.string("本次扫描不完整"),
            CNL10n.format("%@。展开“本次扫描详情”可查看范围；未扫描内容不会被处理。", parts.joined(separator: "；"))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(
                        title: "清理空间",
                        subtitle: "先选择要处理的项目；所有操作都会先移到废纸篓。"
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
                        title: "安全处理已开启",
                        detail: "个人文件默认不选；重复项会在处理前再次核验。",
                        kind: .success
                    )

                    if let warning = scanCoverageWarning {
                        InlineBanner(title: warning.title, detail: warning.detail, kind: .warning)
                    }

                    if case .failed(let message) = store.cleanupAIPhase {
                        InlineBanner(
                            title: "本机 AI 分析未完成",
                            detail: message + " 普通扫描与手动选择仍可正常使用。",
                            kind: .warning
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

                    if !store.cleanupReviewItems.isEmpty {
                        CleanupReviewCard(items: store.cleanupReviewItems)
                    }

                    if let session = store.cleanupScanSession, !session.issues.isEmpty {
                        CleanupScanIssuesCard(issues: session.issues)
                    }

                    if !store.cleanupExecutionLedger.records.isEmpty || store.cleanupExecutionLedgerDiagnostic != nil {
                        CleanupExecutionLedgerCard(
                            snapshot: store.cleanupExecutionLedger,
                            diagnostic: store.cleanupExecutionLedgerDiagnostic
                        )
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            cleanupSearchField
                            scanOptions
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            cleanupSearchField
                            scanOptions
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

                    if !store.cleanupCandidates.isEmpty {
                        LocalAIAdviceCard()
                    }

                    if let session = store.cleanupScanSession {
                        CNDetailSection(
                            title: "本次扫描详情",
                            summary: CNL10n.format("%@ 项候选 · %@/%@ 个位置可读", String(describing: session.candidateCount), String(describing: session.checkedRootCount), String(describing: session.roots.count)),
                            symbol: "doc.text.magnifyingglass"
                        ) {
                            CleanupScanSessionCard(
                                session: session,
                                mediaScanEnabled: store.cleanupScanIncludedMediaAndDuplicates
                            )
                        }
                    }
                }
                .padding(CNTheme.pagePadding)
                .padding(.bottom, store.cleanupCandidates.isEmpty ? 0 : 112)
            }

            if !store.cleanupCandidates.isEmpty {
                CleanupProcessingBasketBar(
                    summary: store.cleanupBasketSummary,
                    disabled: store.selectedCleanupCount == 0 || store.isWorking,
                    onClear: { store.clearCleanupSelection() },
                    onReview: { confirmingTrash = true }
                )
            }
        }
        .alert(CNL10n.format("将 %@ 项移到废纸篓？", String(describing: store.selectedCleanupCount)), isPresented: $confirmingTrash) {
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

    private var scanOptions: some View {
        CNDetailSection(
            title: "扫描选项",
            summary: scanOptionsSummary,
            symbol: "slider.horizontal.3"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("检查媒体与重复文件", isOn: $store.includeMediaAndDuplicates)
                    .toggleStyle(.switch)
                    .help("只读取本机媒体元数据；只对同尺寸文件计算 SHA-256，不上传文件或哈希。")
                Toggle("检查应用缓存", isOn: $store.includeApplicationCaches)
                    .toggleStyle(.switch)
                    .help("应用缓存不会自动勾选。")
            }
            .disabled(store.cleanupScanIsActive)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var scanOptionsSummary: String {
        let enabled = [
            store.includeMediaAndDuplicates ? CNL10n.string("媒体与重复文件") : nil,
            store.includeApplicationCaches ? CNL10n.string("应用缓存") : nil
        ].compactMap { $0 }
        return enabled.isEmpty
            ? CNL10n.string("仅检查安装包与归档")
            : CNL10n.format("已选：%@", enabled.joined(separator: "、"))
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

private struct CleanupReviewCard: View {
    @EnvironmentObject private var store: AppStore
    let items: [CleanupReviewItem]

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    CNIconTile(symbol: "checklist", tint: CNTheme.warning, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("需要逐项复核")
                            .font(.headline)
                        Text("只重试仍可使用原证据的项目；身份或路径变化必须重新扫描。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        text: CNL10n.format("%d 项未移动", items.count),
                        symbol: "hand.raised",
                        style: .warning
                    )
                }

                Divider()

                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 8) {
                            Text(item.candidate.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            StatusPill(text: item.title, symbol: "exclamationmark.shield", style: .warning)
                            Spacer()
                            Button("诊断") {
                                store.lastTechnicalDetail = item.technicalDescription ?? item.detail
                                store.showTechnicalDetail()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                        Text(item.candidate.url.path.replacingOccurrences(
                            of: FileManager.default.homeDirectoryForCurrentUser.path,
                            with: "~"
                        ))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        Text(item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.guidance)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            if item.failureKind == .permissionDenied {
                                Button("打开权限设置") { store.openFullDiskAccessSettings() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                            switch item.action {
                            case .retry:
                                Button {
                                    Task { await store.retryCleanupReview(item) }
                                } label: {
                                    if store.cleanupReviewRetryingID == item.id {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("重试此项", systemImage: "arrow.clockwise")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(store.isWorking || store.cleanupReviewRetryingID != nil)
                                .help("重新执行全部执行前安全检查，不会跳过活跃或身份复核")
                            case .rescan:
                                Button {
                                    Task { await store.scanCleanup() }
                                } label: {
                                    Label("重新扫描", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(store.isWorking)
                            }
                        }
                    }
                    .padding(10)
                    .background(CNTheme.warning.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                }
            }
        }
    }
}

private struct CleanupProcessingBasketBar: View {
    let summary: CleanupBasketSummary
    let disabled: Bool
    let onClear: () -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { basketContent }
                VStack(alignment: .leading, spacing: 10) { basketContent }
            }
            Text("本次只移入废纸篓；清空废纸篓后空间才会真正释放。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CNTheme.pagePadding)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    @ViewBuilder
    private var basketContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(CNL10n.format("已选 %d 项", summary.selectedCount))
                .font(.subheadline.weight(.semibold))
            Text(CleanNestFormatting.bytes(summary.selectedBytes))
                .font(.title3.weight(.semibold))
                .monospacedMetric()
        }
        basketFact(
            "清空后的预估可用空间",
            CleanNestFormatting.bytes(summary.projectedFreeBytesAfterEmptyingTrash),
            symbol: "internaldrive"
        )
        basketFact("恢复方式", "清空前可从废纸篓放回", symbol: "arrow.uturn.backward.circle")
        basketFact(
            "安全核验",
            CNL10n.format("%@ 项会在执行前重验", String(describing: summary.identityRevalidationCount + summary.pathRevalidationCount)),
            symbol: "checkmark.shield"
        )
        Spacer(minLength: 8)
        Button("清空选择", action: onClear)
            .disabled(summary.selectedCount == 0)
        Button("复核并移到废纸篓…", action: onReview)
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
            .help("只打开最终复核；不会在这一步移动文件")
    }

    private func basketFact(_ label: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(CNTheme.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(CNL10n.string(label)).font(.caption2).foregroundStyle(.tertiary)
                Text(CNL10n.string(value)).font(.caption.weight(.semibold)).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupScanSessionCard: View {
    let session: CleanupScanSession
    let mediaScanEnabled: Bool

    private let metricColumns = [GridItem(.adaptive(minimum: 155), spacing: 10)]
    private let evidenceColumns = [GridItem(.adaptive(minimum: 190), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundStyle(CNTheme.cyan)
                        .frame(width: 32, height: 32)
                        .background(CNTheme.cyan.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本次扫描会话")
                            .font(.headline)
                        Text("记下扫了哪里、看了多少文件、跳过了什么；结果本身不会删除文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusPill(
                        text: CNL10n.format("%@/%@ 个位置可读", String(describing: session.checkedRootCount), String(describing: session.roots.count)),
                        symbol: "checklist",
                        style: session.roots.contains(where: { $0.status == .unsafe || $0.status == .unreadable }) ? .warning : .success
                    )
                }

                Divider()

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                    EvidenceMetric(
                        label: "已检查文件",
                        value: session.examinedFileCount.formatted(),
                        detail: "有界扫描，不会为凑数读取包内容",
                        symbol: "doc.text.magnifyingglass",
                        tint: CNTheme.cyan
                    )
                    EvidenceMetric(
                        label: "原始候选",
                        value: CNL10n.format("%d 项", session.candidateCount),
                        detail: "候选体积不等于已释放空间",
                        symbol: "shippingbox.and.arrow.backward",
                        tint: CNTheme.accent
                    )
                    EvidenceMetric(
                        label: "扫描耗时",
                        value: String(format: "%.2f 秒", session.elapsedSeconds),
                        detail: "高成本遍历在独立扫描进程中完成",
                        symbol: "timer",
                        tint: CNTheme.mint
                    )
                    EvidenceMetric(
                        label: "证据时间",
                        value: session.completedAt.formatted(date: .omitted, time: .shortened),
                        detail: session.completedAt.formatted(date: .abbreviated, time: .omitted),
                        symbol: "clock.badge.checkmark",
                        tint: CNTheme.violet
                    )
                }

                evidenceSectionTitle("检查位置")
                LazyVGrid(columns: evidenceColumns, alignment: .leading, spacing: 8) {
                    ForEach(session.roots) { root in
                        rootEvidence(root)
                    }
                }

                if !session.categories.isEmpty {
                    evidenceSectionTitle("本次扫描原始类别")
                    LazyVGrid(columns: evidenceColumns, alignment: .leading, spacing: 8) {
                        ForEach(session.categories) { category in
                            Label(
                                CNL10n.format("%@ %@ 项 · %@", String(describing: CNL10n.string(category.kind.rawValue)), String(describing: category.count), String(describing: CleanNestFormatting.bytes(category.allocatedBytes))),
                                systemImage: category.kind.symbolName
                            )
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(9)
                            .background(CNTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }

                if !session.skips.isEmpty {
                    evidenceSectionTitle("安全跳过")
                    LazyVGrid(columns: evidenceColumns, alignment: .leading, spacing: 8) {
                        ForEach(session.skips) { skip in
                            Label(skipDescription(skip), systemImage: skipSymbol(skip.reason))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(9)
                                .background(CNTheme.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }

                Text(mediaScanEnabled
                    ? "截图按常见中英文文件名识别；其他媒体按修改时间和体积进入候选。同一文件可同时具有重复证据，不要将分类数量直接相加。"
                    : "本次未启用媒体与重复文件分析；只检查桌面和下载中的安装包与归档。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func evidenceSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func rootEvidence(_ root: CleanupScanRootEvidence) -> some View {
        HStack(spacing: 9) {
            Image(systemName: rootStatusSymbol(root.status))
                .foregroundStyle(rootStatusTint(root.status))
            VStack(alignment: .leading, spacing: 2) {
                Text(root.name).font(.caption.weight(.semibold))
                Text(CNL10n.format("%@ · %@", root.pathHint, rootStatusLabel(root.status)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(CNTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
        .accessibilityElement(children: .combine)
    }

    private func rootStatusLabel(_ status: CleanupScanRootStatus) -> String {
        switch status {
        case .checked: return "已检查"
        case .missing: return "位置不存在"
        case .unreadable: return "当前不可读"
        case .unsafe: return "安全校验未通过"
        }
    }

    private func rootStatusSymbol(_ status: CleanupScanRootStatus) -> String {
        switch status {
        case .checked: return "checkmark.circle.fill"
        case .missing: return "minus.circle"
        case .unreadable: return "lock.circle"
        case .unsafe: return "exclamationmark.shield"
        }
    }

    private func rootStatusTint(_ status: CleanupScanRootStatus) -> Color {
        switch status {
        case .checked: return CNTheme.success
        case .missing: return .secondary
        case .unreadable: return CNTheme.warning
        case .unsafe: return CNTheme.danger
        }
    }

    private func skipDescription(_ skip: CleanupScanSkipEvidence) -> String {
        let label: String
        switch skip.reason {
        case .cloudPlaceholder: label = "云端文件尚未完整下载"
        case .symbolicLink: label = "符号链接不跟随"
        case .packageBoundary: label = "App/资料库包内容不展开"
        case .unreadable: label = "文件或目录当前不可读"
        case .depthLimit: label = "超出本轮有界深度"
        case .unsafeRoot: label = "根目录未通过安全检查"
        case .fileLimit: label = "达到本轮文件上限"
        case .hashLimit: label = "达到本轮哈希上限"
        }
        return "\(label) · \(skip.count)"
    }

    private func skipSymbol(_ reason: CleanupScanSkipReason) -> String {
        switch reason {
        case .cloudPlaceholder: return "icloud.and.arrow.down"
        case .symbolicLink: return "link.badge.plus"
        case .packageBoundary: return "shippingbox"
        case .unreadable: return "lock"
        case .depthLimit: return "arrow.down.to.line.compact"
        case .unsafeRoot: return "exclamationmark.shield"
        case .fileLimit, .hashLimit: return "gauge.with.dots.needle.67percent"
        }
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
    private static let autoExpandLimit = 24

    @EnvironmentObject private var store: AppStore
    let kind: CleanupKind
    let candidates: [CleanupCandidate]
    @State private var isExpanded: Bool
    @State private var pageIndex: Int

    private var total: Int64 { candidates.reduce(0) { $0 + $1.allocatedBytes } }
    private var selectedCount: Int {
        candidates.reduce(0) { $0 + (store.selectedCleanupIDs.contains($1.id) ? 1 : 0) }
    }
    private var allSelected: Bool { !candidates.isEmpty && selectedCount == candidates.count }
    private var pageWindow: CleanupCandidatePageWindow {
        CleanupCandidatePageWindow(
            itemCount: candidates.count,
            requestedPageIndex: pageIndex
        )
    }
    private var visibleCandidates: [CleanupCandidate] {
        Array(candidates[pageWindow.range])
    }
    private var showsMediaClusters: Bool {
        kind == .screenshot || kind == .image || kind == .video || kind == .audio
    }
    private var mediaClusterLabels: [String] {
        guard showsMediaClusters else { return [] }
        let summary = CleanupMediaClusterSummary(candidates: candidates)
        let timeLabels: [(CleanupMediaTimeBucket, String)] = [
            (.recent, "近 30 天"),
            (.aging, "30–90 天"),
            (.old, "90 天以上"),
            (.unknown, "时间未知")
        ]
        let sizeLabels: [(CleanupMediaSizeBucket, String)] = [
            (.under100MB, "< 100 MB"),
            (.from100MBTo1GB, "100 MB–1 GB"),
            (.over1GB, "> 1 GB")
        ]
        return timeLabels.compactMap { bucket, label in
            guard let count = summary.timeCounts[bucket], count > 0 else { return nil }
            return "\(label) \(count)"
        } + sizeLabels.compactMap { bucket, label in
            guard let count = summary.sizeCounts[bucket], count > 0 else { return nil }
            return "\(label) \(count)"
        }
    }

    init(kind: CleanupKind, candidates: [CleanupCandidate]) {
        self.kind = kind
        self.candidates = candidates
        _isExpanded = State(initialValue: candidates.count <= Self.autoExpandLimit)
        _pageIndex = State(initialValue: 0)
    }

    var body: some View {
        SurfaceCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button {
                        pageIndex = 0
                        isExpanded.toggle()
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

                    if kind == .screenshot {
                        HStack(spacing: 6) {
                            Button {
                                store.setCleanupSelection(candidates, selected: !allSelected)
                            } label: {
                                Label(
                                    allSelected ? "取消全选" : "全选截图",
                                    systemImage: allSelected ? "checkmark.square.fill" : "checkmark.square"
                                )
                            }
                            Button {
                                store.invertCleanupSelection(candidates)
                            } label: {
                                Label("反选截图", systemImage: "arrow.triangle.2.circlepath")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button {
                            store.setCleanupSelection(candidates, selected: !allSelected)
                        } label: {
                            Label(
                                allSelected ? "取消全选" : "全选本组",
                                systemImage: allSelected ? "checkmark.square.fill" : "checkmark.square"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if showsMediaClusters, !mediaClusterLabels.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 112), spacing: 7)],
                        alignment: .leading,
                        spacing: 7
                    ) {
                        ForEach(mediaClusterLabels, id: \.self) { label in
                            Text(label)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(CNTheme.violet.opacity(0.08), in: Capsule())
                        }
                    }
                    .padding(.top, 9)
                    .accessibilityLabel(CNL10n.format("媒体时间与体积分组：%@", mediaClusterLabels.joined(separator: "，")))
                }

                if isExpanded {
                    Divider()
                        .padding(.top, 10)

                    VStack(spacing: 0) {
                        ForEach(visibleCandidates) { candidate in
                            CleanupRow(candidate: candidate)
                            if candidate.id != visibleCandidates.last?.id {
                                Divider().padding(.leading, 38)
                            }
                        }
                    }

                    if pageWindow.pageCount > 1 {
                        Divider()
                        cleanupPagination
                    }
                }
            }
        }
        .onChange(of: candidates.count) { _, _ in
            pageIndex = pageWindow.pageIndex
        }
    }

    private var cleanupPagination: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                paginationExplanation
                Spacer(minLength: 12)
                paginationControls
            }
            VStack(alignment: .leading, spacing: 9) {
                paginationExplanation
                paginationControls
            }
        }
        .padding(.top, 10)
    }

    private var paginationExplanation: some View {
        Text(
            CNL10n.format(
                "当前显示 %d–%d / %d 项。为避免大型列表卡住，每页最多加载 %d 项。",
                pageWindow.displayedStartNumber,
                pageWindow.displayedEndNumber,
                candidates.count,
                pageWindow.pageSize
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var paginationControls: some View {
        HStack(spacing: 8) {
            Button {
                pageIndex = max(0, pageWindow.pageIndex - 1)
            } label: {
                Label(CNL10n.string("上一页"), systemImage: "chevron.left")
            }
            .disabled(!pageWindow.hasPreviousPage)

            Text(CNL10n.format("第 %d / %d 页", pageWindow.pageIndex + 1, pageWindow.pageCount))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                pageIndex = min(pageWindow.pageCount - 1, pageWindow.pageIndex + 1)
            } label: {
                Label(CNL10n.string("下一页"), systemImage: "chevron.right")
            }
            .disabled(!pageWindow.hasNextPage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
                .accessibilityLabel(CNL10n.format("选择 %@", candidate.name))

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
                Text(CNL10n.format(
                    "%@ · %@",
                    CNL10n.string(candidate.detail),
                    CNL10n.age(CleanNestFormatting.age(from: candidate.modifiedAt))
                ))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let duplicate = candidate.duplicateEvidence {
                    Label(
                        CNL10n.format("保留副本：%@ · 本组 %@ 份", String(describing: redactedPath(duplicate.retainedURL)), String(describing: duplicate.groupFileCount)),
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CNTheme.success)
                    .lineLimit(2)
                    .help("移动前会重新计算候选与这份保留副本的完整 SHA-256")
                } else if candidate.kind == .duplicate {
                    Label("未找到可验证的保留副本；本项不会通过执行前重验", systemImage: "exclamationmark.shield")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(CNTheme.warning)
                }
                if let advice = aiAdvice {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        StatusPill(
                            text: aiAdviceLabel(advice),
                            symbol: aiAdviceSymbol(advice),
                            style: aiAdviceStyle(advice)
                        )
                        Text(CNL10n.string(advice.reason))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(.top, 2)
                }
                if let learnedPreference {
                    HStack(spacing: 7) {
                        StatusPill(
                            text: learnedPreference == .preferKeep ? "已记住：优先保留" : "已记住：优先清理",
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
                        Text("不会自动改变排序；到“清理习惯”页启用后才生效")
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
            .help("查看或管理清理习惯")
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
        if signal.explicitPreference != nil { return CNL10n.string("来自你的明确判断") }
        if signal.successfulCleanupCount > 0 {
            return CNL10n.format("你曾安全清理 %@ 次", String(describing: signal.successfulCleanupCount))
        }
        return CNL10n.string("本机记录")
    }

    private func redactedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + String(path.dropFirst(home.count))
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
        case .reclaimable: verdict = CNL10n.string("适合清理")
        case .review: verdict = CNL10n.string("建议检查")
        case .keep: verdict = CNL10n.string("建议保留")
        }
        return CNL10n.format("AI 优先 %@：%@", String(describing: advice.priority), verdict)
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
        CNDetailSection(
            title: "本机 AI 分析",
            summary: aiSummary,
            symbol: "brain.head.profile"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("只读分析，不会改动你的选择")
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
                        Text(CNL10n.format("%@ 正在判断体积最大的 %d 项…", store.localAIModelDisplayName, min(store.cleanupCandidates.count, CleanupAIRequestBuilder.maximumCandidates)))
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

    private var aiSummary: String {
        if let analysis = store.cleanupAIAnalysis {
            return CNL10n.format("已分析 %@ 项", String(describing: analysis.requestedCount))
        }
        if store.localAIIsReady { return CNL10n.format("可用：%@", String(describing: store.localAIModelDisplayName)) }
        return "未连接时仍可正常清理"
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
            Button("在设置中连接") { store.openSettings(.localAI) }
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
                    text: CNL10n.format("已分析 %@ 项", String(describing: analysis.requestedCount)),
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
