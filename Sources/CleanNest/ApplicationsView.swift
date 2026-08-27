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
                subtitle: "先确认 App 本体和精确匹配的相关文件，再移到废纸篓。"
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
            let count = includeLeftovers ? store.selectedApplicationLeftovers.count : 0
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

                    SurfaceCard(title: "卸载检查", symbol: "checklist") {
                        VStack(spacing: 0) {
                            UninstallItemRow(
                                title: "App 本体",
                                path: application.url.path,
                                bytes: application.allocatedBytes,
                                selected: true,
                                locked: true
                            )
                            Divider()
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("精确匹配的相关文件")
                                        .font(.subheadline.weight(.medium))
                                    Text("仅按 Bundle ID 匹配，不使用模糊名称猜测")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(CleanNestFormatting.bytes(store.selectedApplicationLeftovers.reduce(0) { $0 + $1.allocatedBytes }))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedMetric()
                                Toggle("", isOn: $includeLeftovers)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                            }
                            .padding(.vertical, 12)
                        }
                    }

                    if includeLeftovers {
                        SurfaceCard(title: "相关文件", symbol: "doc.on.doc") {
                            if store.selectedApplicationLeftovers.isEmpty {
                                Text(store.fullDiskAccessProbePassed
                                    ? "没有发现能够确认归属的相关文件。"
                                    : "当前可访问的位置没有发现能够确认归属的相关文件；受保护位置尚未检查。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(store.selectedApplicationLeftovers.enumerated()), id: \.element.id) { index, item in
                                        UninstallItemRow(
                                            title: item.name,
                                            path: item.url.path,
                                            bytes: item.allocatedBytes,
                                            selected: true,
                                            locked: false
                                        )
                                        if index < store.selectedApplicationLeftovers.count - 1 { Divider() }
                                    }
                                }
                            }
                        }
                    }

                    InlineBanner(
                        title: "恢复方式：废纸篓",
                        detail: "当前版本不执行永久删除。清空废纸篓前，你仍可恢复 App 和相关文件。",
                        kind: .info
                    )
                }
                .padding(.horizontal, CNTheme.pagePadding)
                .padding(.bottom, 88)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("预计处理 \(1 + (includeLeftovers ? store.selectedApplicationLeftovers.count : 0)) 项")
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

private struct UninstallItemRow: View {
    let title: String
    let path: String
    let bytes: Int64
    let selected: Bool
    let locked: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? CNTheme.success : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.medium))
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(CleanNestFormatting.bytes(bytes))
                .font(.caption.weight(.semibold))
                .monospacedMetric()
        }
        .padding(.vertical, 10)
    }
}
