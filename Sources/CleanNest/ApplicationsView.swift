import AppKit
import SwiftUI
import CleanNestCore

struct ApplicationsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var includeLeftovers = true
    @State private var confirmingUninstall = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                title: "应用卸载",
                subtitle: "先看懂 App、私有数据、登录项、守护和扩展的关系，再决定处理什么。"
            ) {
                Button {
                    Task { await store.scanApplications() }
                } label: {
                    Label(store.applicationsHaveScanned ? "重新扫描" : "扫描 App", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isWorking)
            }
            .padding(CNTheme.pagePadding)
            .padding(.bottom, 14)

            if let session = store.applicationUninstallSession,
               store.selectedApplication?.id != session.applicationID {
                ApplicationUninstallResultCard(
                    session: session,
                    canRetry: store.canRetryApplicationUninstallRelatedFiles,
                    reveal: {
                        if let url = session.applicationTrashURL { store.revealInFinder(url) }
                    },
                    retry: {
                        Task { await store.retryApplicationUninstallRelatedFiles() }
                    }
                )
                .padding(.horizontal, CNTheme.pagePadding)
                .padding(.bottom, 14)
            }

            if !store.applicationsHaveScanned {
                EmptyPanel(
                    symbol: "square.grid.3x3.square",
                    title: "读取已安装的 App",
                    detail: "扫描只读取应用名称、版本、Bundle ID 和磁盘大小，不会卸载任何内容。",
                    actionTitle: "扫描已安装 App"
                ) {
                    Task { await store.scanApplications() }
                }
                .padding(.horizontal, CNTheme.pagePadding)
                .padding(.bottom, CNTheme.pagePadding)
            } else if store.applications.isEmpty {
                EmptyPanel(
                    symbol: "app.badge.checkmark",
                    title: "没有找到可管理的 App",
                    detail: "CleanNest 当前检查 /Applications 和当前账户的 Applications 文件夹。"
                )
                .padding(.horizontal, CNTheme.pagePadding)
                .padding(.bottom, CNTheme.pagePadding)
            } else {
                HSplitView {
                    applicationList
                        .frame(minWidth: 280, idealWidth: 330, maxWidth: 420)
                    applicationDetail
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .alert(CNL10n.format("卸载 %@？", store.selectedApplication?.name ?? CNL10n.string("这个 App")), isPresented: $confirmingUninstall) {
            Button("返回检查", role: .cancel) { }
            Button(CNL10n.string(requiresAdministratorAuthentication ? "认证并移到废纸篓" : "移到废纸篓"), role: .destructive) {
                Task { await store.uninstallSelectedApplication(includeLeftovers: includeLeftovers) }
            }
        } message: {
            let count = includeLeftovers ? selectedRelatedCount : 0
            if requiresAdministratorAuthentication {
                Text(CNL10n.format("这个 App 由系统或其他管理员账户安装。下一步 macOS 会显示原生管理员认证；CleanNest 不会读取或保存密码。认证成功并确认 App 已进入废纸篓后，才会处理 %d 个相关项目。", count))
            } else {
                Text(CNL10n.format("App 本体和 %d 个相关项目将移到废纸篓。只有确认 App 本体成功后，CleanNest 才会处理相关项目。", count))
            }
        }
    }

    private var selectedRemovalRequirement: ApplicationRemovalRequirement? {
        guard let application = store.selectedApplication else { return nil }
        return store.applicationRemovalRequirement(for: application)
    }

    private var requiresAdministratorAuthentication: Bool {
        selectedRemovalRequirement == .administratorAuthentication
    }

    private var applicationList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索 App 或 Bundle ID", text: $store.applicationSearch)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(CNTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CNTheme.divider, lineWidth: 0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List(store.filteredApplications, selection: Binding(
                get: { store.selectedApplication?.id },
                set: { id in
                    guard let id, let application = store.applications.first(where: { $0.id == id }) else { return }
                    Task { await store.chooseApplication(application) }
                }
            )) { application in
                ApplicationListRow(application: application)
                    .tag(application.id)
            }
            .listStyle(.inset)
        }
        .background(CNTheme.surfaceSubtle.opacity(0.35))
    }

    @ViewBuilder
    private var applicationDetail: some View {
        if let application = store.selectedApplication {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 16) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 68, height: 68)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Text(application.name)
                                    .font(.system(size: 25, weight: .semibold, design: .rounded))
                                if store.applicationIsRunning(application) {
                                    StatusPill(text: "正在运行", symbol: "play.fill", style: .warning)
                                }
                            }
                            Text(application.bundleIdentifier ?? "未提供 Bundle ID")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text("版本 \(application.version ?? "未知") · \(CleanNestFormatting.bytes(application.allocatedBytes))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            store.revealInFinder(application.url)
                        } label: {
                            Label("Finder", systemImage: "folder")
                        }
                    }

                    if store.applicationIsRunning(application) {
                        InlineBanner(
                            title: "请先退出 \(application.name)",
                            detail: "CleanNest 不会静默强制结束正在运行的 App。",
                            kind: .warning,
                            actionTitle: "请求退出"
                        ) {
                            store.askApplicationToQuit(application)
                        }
                    }

                    if requiresAdministratorAuthentication {
                        InlineBanner(
                            title: "需要管理员认证",
                            detail: "此 App 不是当前账户所有。确认卸载后，macOS 会用原生窗口完成认证；CleanNest 不会看到、读取或保存你的密码。",
                            kind: .info
                        )
                    } else if selectedRemovalRequirement == nil {
                        InlineBanner(
                            title: "App 状态已经变化",
                            detail: "当前路径无法通过安全校验。请重新扫描；CleanNest 不会对未知目标尝试卸载。",
                            kind: .warning,
                            actionTitle: "重新扫描"
                        ) {
                            Task { await store.scanApplications() }
                        }
                    }

                    if !store.fullDiskAccessProbePassed {
                        InlineBanner(
                            title: "受保护的相关文件尚未检查",
                            detail: "为避免连续授权弹窗，CleanNest 已跳过 Application Support、Containers 和 Group Containers；当前列表只包含能够安全读取的位置。",
                            kind: .warning,
                            actionTitle: "前往设置页"
                        ) {
                            store.selection = .settings
                        }
                    }

                    if store.applicationDependencyGraphIsLoading {
                        SurfaceCard(title: "正在建立依赖地图", symbol: "point.3.connected.trianglepath.dotted") {
                            HStack(spacing: 12) {
                                ProgressView().controlSize(.small)
                                Text("正在核对代码签名、Launch Services、相关目录与 launchd 配置；不会改动文件。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 10)
                        }
                    } else if let graph = store.selectedApplicationDependencyGraph,
                              graph.applicationID == application.id {
                        ApplicationIdentityEvidenceCard(graph: graph)

                        ApplicationUninstallFlowCard(
                            session: store.applicationUninstallSession?.applicationID == application.id
                                ? store.applicationUninstallSession
                                : nil,
                            applicationIsRunning: store.applicationIsRunning(application),
                            requiresAuthentication: requiresAdministratorAuthentication
                        )

                        ApplicationDependencyMapCard(
                            graph: graph,
                            includeRemovableItems: $includeLeftovers,
                            selectedIDs: store.selectedApplicationDependencyIDs,
                            setSelected: store.setApplicationDependencySelected,
                            reveal: store.revealInFinder
                        )
                    }

                    InlineBanner(
                        title: "恢复方式：废纸篓",
                        detail: "当前版本不执行永久删除。共享组、系统管理项和无法证明归属的项目始终只读；完成后会显示 App 与相关文件各自的恢复位置。",
                        kind: .info
                    )
                }
                .padding(.horizontal, CNTheme.pagePadding)
                .padding(.bottom, 88)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("预计处理 \(1 + (includeLeftovers ? selectedRelatedCount : 0)) 项")
                            .font(.subheadline.weight(.semibold))
                        Text(CNL10n.string(requiresAdministratorAuthentication ? "先由 macOS 完成管理员认证，再移到废纸篓" : "全部移到废纸篓"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(
                        CNL10n.format(
                            requiresAdministratorAuthentication ? "认证并卸载 %@" : "卸载 %@",
                            application.name
                        ),
                        role: .destructive
                    ) {
                        confirmingUninstall = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(CNTheme.danger)
                    .disabled(
                        store.applicationIsRunning(application)
                            || store.isWorking
                            || selectedRemovalRequirement == nil
                            || store.selectedApplicationDependencyGraph?.applicationID != application.id
                    )
                }
                .padding(.horizontal, CNTheme.pagePadding)
                .padding(.vertical, 12)
                .background(.bar)
                .overlay(alignment: .top) { Divider() }
            }
        } else {
            EmptyPanel(
                symbol: "cursorarrow.click",
                title: "选择一个 App",
                detail: "右侧会显示应用本体、相关文件、预计大小和恢复方式。"
            )
            .padding(CNTheme.pagePadding)
        }
    }

    private var selectedRelatedCount: Int {
        guard includeLeftovers, let graph = store.selectedApplicationDependencyGraph else { return 0 }
        return graph.separatelyRemovableNodes.reduce(0) {
            $0 + (store.selectedApplicationDependencyIDs.contains($1.id) ? 1 : 0)
        }
    }
}

private struct ApplicationListRow: View {
    let application: InstalledApplication

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(application.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(application.version.map { "版本 \($0)" } ?? "版本未知")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text(CleanNestFormatting.bytes(application.allocatedBytes))
                .font(.caption.weight(.medium))
                .monospacedMetric()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct ApplicationIdentityEvidenceCard: View {
    let graph: ApplicationDependencyGraph

    var body: some View {
        SurfaceCard(title: "身份与注册证据", symbol: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 8) {
                    StatusPill(
                        text: graph.codeSignature.status.displayName,
                        symbol: signatureSymbol,
                        style: signatureStyle
                    )
                    StatusPill(
                        text: graph.registration.scannedPathIsRegistered ? "路径已登记" : "登记路径待复核",
                        symbol: graph.registration.scannedPathIsRegistered ? "checkmark.circle" : "exclamationmark.circle",
                        style: graph.registration.scannedPathIsRegistered ? .success : .warning
                    )
                    Spacer()
                }

                EvidenceLine(
                    title: "签名身份",
                    value: [
                        graph.codeSignature.signingIdentifier,
                        graph.codeSignature.teamIdentifier.map { "Team \($0)" }
                    ].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "未取得可展示的签名身份"
                )
                EvidenceLine(title: "代码签名", value: graph.codeSignature.diagnostic)
                EvidenceLine(title: "系统登记", value: graph.registration.diagnostic)
                if !graph.registration.registeredURLs.isEmpty {
                    EvidenceLine(
                        title: "登记位置",
                        value: graph.registration.registeredURLs
                            .prefix(2)
                            .map { displayPath($0.path) }
                            .joined(separator: " · ")
                    )
                }
            }
        }
    }

    private var signatureSymbol: String {
        graph.codeSignature.status == .valid ? "checkmark.seal.fill" : "exclamationmark.triangle"
    }

    private var signatureStyle: StatusPill.Style {
        switch graph.codeSignature.status {
        case .valid: return .success
        case .unsigned, .unavailable: return .warning
        case .invalid: return .danger
        }
    }
}

private struct EvidenceLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

private struct ApplicationUninstallFlowCard: View {
    let session: ApplicationUninstallSession?
    let applicationIsRunning: Bool
    let requiresAuthentication: Bool

    var body: some View {
        SurfaceCard(title: "卸载状态机", symbol: "list.number") {
            VStack(spacing: 0) {
                ForEach(ApplicationUninstallStage.allCases, id: \.self) { stage in
                    let step = session?.steps.first { $0.stage == stage }
                    ApplicationUninstallFlowRow(
                        stage: stage,
                        state: step?.state,
                        previewDetail: previewDetail(for: stage)
                    )
                    if stage != ApplicationUninstallStage.allCases.last { Divider().padding(.leading, 34) }
                }
            }
        }
    }

    private func previewDetail(for stage: ApplicationUninstallStage) -> String {
        switch stage {
        case .quitApplication:
            return applicationIsRunning ? "等待你先保存工作并请求退出" : "执行时再次确认 App 没有运行"
        case .revalidateIdentity:
            return "核对路径、设备号、文件号、所有者与 Bundle ID"
        case .authenticate:
            return requiresAuthentication ? "需要 macOS 原生管理员认证" : "当前账户预计无需管理员认证"
        case .confirmApplicationTrash:
            return "未确认 App 本体进入废纸篓前，相关文件保持零变更"
        case .removeRelatedFiles:
            return "只处理你勾选且能证明为 App 私有的项目"
        case .finalReview:
            return "列出恢复位置、未完成项和可重试项"
        }
    }
}

private struct ApplicationUninstallFlowRow: View {
    let stage: ApplicationUninstallStage
    let state: ApplicationUninstallStageState?
    let previewDetail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Group {
                if case .running? = state {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(stage.displayName)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            if let statusText {
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let state else { return previewDetail }
        switch state {
        case .pending, .running: return previewDetail
        case .succeeded(let value), .skipped(let value), .failed(let value): return value
        }
    }

    private var statusText: String? {
        guard let state else { return "待执行" }
        switch state {
        case .pending: return "待执行"
        case .running: return "进行中"
        case .succeeded: return "完成"
        case .skipped: return "跳过"
        case .failed: return "未完成"
        }
    }

    private var symbol: String {
        guard let state else { return "circle" }
        switch state {
        case .pending: return "circle"
        case .running: return "arrow.clockwise"
        case .succeeded: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var tint: Color {
        guard let state else { return .secondary }
        switch state {
        case .pending: return .secondary
        case .running: return CNTheme.accent
        case .succeeded: return CNTheme.success
        case .skipped: return .secondary
        case .failed: return CNTheme.danger
        }
    }
}

private struct ApplicationDependencyMapCard: View {
    let graph: ApplicationDependencyGraph
    @Binding var includeRemovableItems: Bool
    let selectedIDs: Set<String>
    let setSelected: (String, Bool) -> Void
    let reveal: (URL) -> Void

    var body: some View {
        SurfaceCard(title: "依赖地图", symbol: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    DependencyMetric(
                        value: "\(graph.separatelyRemovableNodes.count)",
                        label: "可单独处理",
                        tint: CNTheme.success
                    )
                    DependencyMetric(
                        value: "\(graph.includedNodes.count)",
                        label: "随 App 本体",
                        tint: CNTheme.accent
                    )
                    DependencyMetric(
                        value: "\(graph.readOnlyNodes.count)",
                        label: "只读证据",
                        tint: CNTheme.warning
                    )
                    Spacer()
                }

                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("处理 App 私有相关文件")
                            .font(.subheadline.weight(.semibold))
                        Text("总开关关闭时全部保留；打开后仍可逐项取消。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $includeRemovableItems)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(12)
                .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))

                ForEach(ApplicationDependencyOwnership.allCases, id: \.self) { ownership in
                    let nodes = graph.nodes.filter { $0.ownership == ownership }
                    if !nodes.isEmpty {
                        DependencyOwnershipSection(
                            ownership: ownership,
                            nodes: nodes,
                            includeRemovableItems: includeRemovableItems,
                            selectedIDs: selectedIDs,
                            setSelected: setSelected,
                            reveal: reveal
                        )
                    }
                }

                Text(graph.diagnostic)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DependencyMetric: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedMetric()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 86, alignment: .leading)
    }
}

private struct DependencyOwnershipSection: View {
    let ownership: ApplicationDependencyOwnership
    let nodes: [ApplicationDependencyNode]
    let includeRemovableItems: Bool
    let selectedIDs: Set<String>
    let setSelected: (String, Bool) -> Void
    let reveal: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: ownershipSymbol)
                    .foregroundStyle(ownershipTint)
                Text(ownership.displayName)
                    .font(.subheadline.weight(.semibold))
                Text("\(nodes.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if ownership != .applicationOwned {
                    StatusPill(text: "只读", symbol: "lock.fill", style: ownership == .unverified ? .warning : .neutral)
                }
            }
            .padding(.bottom, 7)

            VStack(spacing: 0) {
                ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                    ApplicationDependencyRow(
                        node: node,
                        includeRemovableItems: includeRemovableItems,
                        selected: selectedIDs.contains(node.id),
                        setSelected: setSelected,
                        reveal: reveal
                    )
                    if index < nodes.count - 1 { Divider().padding(.leading, 39) }
                }
            }
            .padding(.horizontal, 12)
            .background(CNTheme.surfaceSubtle.opacity(0.72), in: RoundedRectangle(cornerRadius: 11))
        }
    }

    private var ownershipSymbol: String {
        switch ownership {
        case .applicationOwned: return "app.badge.checkmark"
        case .sharedGroup: return "person.2.fill"
        case .systemManaged: return "gearshape.2.fill"
        case .unverified: return "questionmark.diamond.fill"
        }
    }

    private var ownershipTint: Color {
        switch ownership {
        case .applicationOwned: return CNTheme.success
        case .sharedGroup: return CNTheme.accent
        case .systemManaged: return .secondary
        case .unverified: return CNTheme.warning
        }
    }
}

private struct ApplicationDependencyRow: View {
    let node: ApplicationDependencyNode
    let includeRemovableItems: Bool
    let selected: Bool
    let setSelected: (String, Bool) -> Void
    let reveal: (URL) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if node.action == .removeAfterApplication {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { includeRemovableItems && selected },
                        set: { setSelected(node.id, $0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(!includeRemovableItems)
            } else {
                Image(systemName: actionSymbol)
                    .foregroundStyle(actionTint)
                    .frame(width: 16)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(node.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(node.kind.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(node.evidence.first ?? "没有可展示的归属证据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(displayPath(node.url.path))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(CleanNestFormatting.bytes(node.allocatedBytes))
                    .font(.caption.weight(.semibold))
                    .monospacedMetric()
                Text(actionText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(actionTint)
            }
            Button {
                reveal(node.url)
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在 Finder 中查看")
            .accessibilityLabel("在 Finder 中查看 \(node.name)")
        }
        .padding(.vertical, 10)
    }

    private var actionText: String {
        switch node.action {
        case .applicationBundle: return "先处理本体"
        case .removeAfterApplication: return includeRemovableItems && selected ? "已勾选" : "保留"
        case .includedInApplication: return "随本体"
        case .readOnly: return "只读"
        }
    }

    private var actionSymbol: String {
        switch node.action {
        case .applicationBundle: return "lock.fill"
        case .removeAfterApplication: return selected ? "checkmark.square.fill" : "square"
        case .includedInApplication: return "arrow.turn.down.right"
        case .readOnly: return "eye.fill"
        }
    }

    private var actionTint: Color {
        switch node.action {
        case .applicationBundle, .includedInApplication: return CNTheme.accent
        case .removeAfterApplication: return selected ? CNTheme.success : .secondary
        case .readOnly: return node.ownership == .unverified ? CNTheme.warning : .secondary
        }
    }
}

private struct ApplicationUninstallResultCard: View {
    let session: ApplicationUninstallSession
    let canRetry: Bool
    let reveal: () -> Void
    let retry: () -> Void

    var body: some View {
        SurfaceCard(
            title: session.failedRelatedPaths.isEmpty ? "\(session.applicationName) 已进入废纸篓" : "\(session.applicationName) 已卸载，仍有未完成项",
            symbol: session.failedRelatedPaths.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        ) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(resultSummary)
                        .font(.subheadline)
                    if let appTrashURL = session.applicationTrashURL {
                        Text("App 恢复位置：\(displayPath(appTrashURL.path))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let first = session.failedRelatedPaths.first {
                        Text("保持原位：\(displayPath(first))\(session.failedRelatedPaths.count > 1 ? " 等 \(session.failedRelatedPaths.count) 项" : "")")
                            .font(.caption)
                            .foregroundStyle(CNTheme.warning)
                    }
                }
                Spacer()
                Button("在 Finder 中查看", action: reveal)
                    .disabled(session.applicationTrashURL == nil)
                if canRetry {
                    Button("重试未完成项", action: retry)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private var resultSummary: String {
        if session.failedRelatedPaths.isEmpty {
            return "App 本体与 \(session.relatedTrashURLs.count) 个所选私有项目都有可恢复位置；共享、系统管理和未证实项目没有改动。"
        }
        return "\(session.relatedTrashURLs.count) 个私有项目已进入废纸篓，\(session.failedRelatedPaths.count) 个项目仍在原位，可安全重试。"
    }
}

private func displayPath(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
