import AppKit
import SwiftUI
import CleanNestCore

/// Keep progress out of the large AppStore publisher. Only this sheet observes
/// it, and only compact aggregate results survive closing the sheet.
@MainActor final class SystemDataPresentationState: ObservableObject {
    @Published private(set) var report: SystemDataReport?
    @Published private(set) var previousReport: SystemDataReport?
    @Published private(set) var progress: ScannerServiceProgress?
    @Published private(set) var isScanning = false
    @Published private(set) var message: String?
    private let client = ScannerServiceClient()
    private var task: Task<Void, Never>?

    func scan(protectedAccess: Bool, demoMode: Bool) {
        guard task == nil else { return }
        if demoMode {
            previousReport = report
            report = Self.demoReport()
            message = "演示数据，不读取本机目录。"
            return
        }
        isScanning = true
        message = nil
        progress = nil
        let request = SystemDataScannerRequest(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            protectedAccessConfirmed: protectedAccess
        )
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.isScanning = false; self.progress = nil; self.task = nil }
            do {
                let response = try await self.client.scanSystemData(request) { [weak self] value in
                    await self?.receive(value, requestID: request.requestID)
                }
                try Task.checkCancellation()
                guard response.requestID == request.requestID else { throw ScannerServiceClientError.invalidResponse }
                self.previousReport = self.report
                self.report = response.report
            } catch is CancellationError {
                self.message = "已取消；上一次完成的清单仍保留，没有处理任何文件。"
            } catch {
                self.message = CNL10n.format("本次扫描未完成；旧结果已保留。%@", String(describing: error.localizedDescription))
            }
        }
    }

    private func receive(_ value: ScannerServiceProgress, requestID: String) {
        guard value.requestID == requestID, value.operation == .systemData else { return }
        progress = value
    }

    func cancel() { task?.cancel() }

    private static func demoReport() -> SystemDataReport {
        let examples: [(String, Int64)] = [("docker", 31_600_000_000), ("huggingface", 28_000_000_000),
            ("simulators", 16_200_000_000), ("xcode-build", 8_100_000_000), ("npm", 5_330_000_000),
            ("ios-backups", 4_200_000_000)]
        let home = URL(fileURLWithPath: "/Users/Demo")
        let items = examples.compactMap { id, bytes -> SystemDataItem? in
            guard let location = SystemDataCatalog.locations.first(where: { $0.id == id }) else { return nil }
            return SystemDataItem(location: location, url: location.url(in: home), status: .measured,
                                  allocatedBytes: bytes, latestModificationDate: Date().addingTimeInterval(-86_400 * 20))
        } + SystemDataCatalog.locations.filter { $0.id == "app-caches" }.map {
            SystemDataItem(location: $0, url: $0.url(in: home), status: .protectedLocation)
        }
        return SystemDataReport(items: items, volume: DiskVolumeSnapshot(
            selectedRoot: home, volumeRoot: URL(fileURLWithPath: "/"), volumeName: "Macintosh HD",
            totalBytes: 1_000_000_000_000, availableBytes: 126_000_000_000,
            availableForImportantUsageBytes: 138_000_000_000, selectedRootIsVolumeRoot: false))
    }
}

struct SystemDataView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var state: SystemDataPresentationState
    @State private var query = ""
    @State private var filter = SystemDataFilter.all
    @State private var selectedID: String?

    private var items: [SystemDataItem] {
        state.report?.visibleItems(query: query, filter: filter, previous: state.previousReport) ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("系统数据").font(.title2.bold())
                    Text("找到大项，看懂用途，再决定怎么处理。").foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { state.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }

            if let report = state.report {
                summary(report)
            } else {
                Text(CNL10n.format("检查本机 %d 个常见位置：开发缓存、模拟器、设备备份、模型和虚拟机。只读元数据，不扫描你的整块硬盘。", SystemDataCatalog.locations.count))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                TextField("搜索软件、用途或路径", text: $query).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("搜索系统数据")
                Picker("筛选", selection: $filter) {
                    Text("全部").tag(SystemDataFilter.all)
                    Text("可重建").tag(SystemDataFilter.rebuildable)
                    Text("需保留 / 工具管理").tag(SystemDataFilter.managed)
                    Text("扫描缺口").tag(SystemDataFilter.gaps)
                }
                .frame(width: 185)
                Button(state.report == nil ? "开始扫描" : "重新扫描") {
                    selectedID = nil
                    state.scan(protectedAccess: store.fullDiskAccessProbePassed, demoMode: store.demoMode)
                }.buttonStyle(.borderedProminent).disabled(state.isScanning || store.isWorking)
                    .keyboardShortcut("r", modifiers: .command)
            }

            if state.isScanning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(CNL10n.format("%d / %d · %@", state.progress?.completed ?? 0, state.progress?.total ?? SystemDataCatalog.locations.count, CNL10n.string(state.progress?.currentName ?? "正在连接扫描服务")))
                        .font(.callout).lineLimit(2)
                    Spacer()
                    Button("取消扫描") { state.cancel() }
                }
                if state.report != nil { Text("下方仍是上次完成的结果，本次扫描尚未替换它。").font(.caption).foregroundStyle(.secondary) }
            }
            if let message = state.message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(items) { item in
                        inventoryRow(item)
                        Divider()
                    }
                    if items.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "internaldrive").font(.largeTitle).foregroundStyle(.secondary)
                            Text(state.report == nil ? "点“开始扫描”生成占用清单" : "没有符合条件的项目")
                            if state.report != nil { Text("可以清空搜索或切回“全部”；默认路径未找到不代表该软件没有安装。").font(.caption).foregroundStyle(.secondary) }
                        }.frame(maxWidth: .infinity).padding(40)
                    }
                }
            }

            CNDetailSection(title: "统计范围与口径", summary: "占用不是可释放空间；模型与备份不能直接删。") {
                Text("只统计清单内已读到的文件分配块；硬链接 / APFS 克隆可能共享空间，合计不等于可释放空间或 macOS“系统数据”。不含系统快照、系统级运行时、交换文件和自定义目录。每处最多遍历 10 万项；不跨卷、不跟随符号链接。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(minWidth: 700, idealWidth: 880, maxWidth: 1100, minHeight: 560, idealHeight: 740)
        .onDisappear { state.cancel() }
        .task {
            if store.demoMode && state.report == nil { state.scan(protectedAccess: false, demoMode: true) }
        }
    }

    private func previous(_ item: SystemDataItem) -> SystemDataItem? {
        state.previousReport?.items.first { $0.id == item.id }
    }

    @ViewBuilder private func summary(_ report: SystemDataReport) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("已解释的占用").font(.caption).foregroundStyle(.secondary)
                Text(CleanNestFormatting.bytes(report.measuredBytes)).font(.title.bold()).monospacedDigit()
                Text(CNL10n.format("%d 个位置 · %d 处未完整扫描", report.items.filter { $0.allocatedBytes != nil }.count, report.incompleteCount))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let volume = report.volume {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("磁盘实际可用").font(.caption).foregroundStyle(.secondary)
                    Text(CleanNestFormatting.bytes(volume.availableBytes)).font(.title2.bold()).monospacedDigit()
                    if let estimate = volume.reclaimableCapacityBytes {
                        Text(CNL10n.format("系统另估可回收 %@，不保证立即释放", CleanNestFormatting.bytes(estimate)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(CNTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        Text(CNL10n.format("采样 %@ · 变化只比较本次打开 App 后的两次完整测量", report.capturedAt.formatted(date: .abbreviated, time: .shortened)))
            .font(.caption).foregroundStyle(.secondary)
    }

    private func inventoryRow(_ item: SystemDataItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { selectedID = selectedID == item.id ? nil : item.id } label: {
                HStack(spacing: 12) {
                    Image(systemName: selectedID == item.id ? "chevron.down" : "chevron.right")
                        .frame(width: 14).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.location.name).font(.headline)
                        Text(item.location.owner + " · " + item.location.disposition.label)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(item.allocatedBytes.map(CleanNestFormatting.bytes) ?? "未测量")
                            .font(.headline).monospacedDigit().fixedSize()
                        if let delta = item.change(from: previous(item)), delta != 0 {
                            Text(CNL10n.format("较上次 %@%@", delta > 0 ? "+" : "−", CleanNestFormatting.bytes(abs(delta))))
                                .font(.caption).foregroundStyle(delta > 0 ? CNTheme.warning : CNTheme.success)
                        } else {
                            Text(item.status.label).font(.caption)
                                .foregroundStyle(item.status == .measured ? .secondary : CNTheme.warning)
                        }
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(CNL10n.format("%@，%@，查看用途和处理影响", CNL10n.string(item.location.name), CNL10n.string(item.status.label)))
            .accessibilityValue(item.allocatedBytes.map(CleanNestFormatting.bytes) ?? "未测量")

            if selectedID == item.id {
                if item.status == .protectedLocation {
                    Text("此位置尚未检查，也尚未确认是否存在；请先完成现有访问检测。").font(.caption).foregroundStyle(CNTheme.warning)
                }
                Text(item.location.purpose).font(.callout).fixedSize(horizontal: false, vertical: true)
                Label(item.location.impact, systemImage: "info.circle")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("~/" + item.location.relativePath).font(.caption.monospaced()).textSelection(.enabled)
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let evidence = item.traversal {
                    Text(CNL10n.format("已读 %d 个文件 · 不可读 %d · 链接跳过 %d%@", evidence.regularFileCount, evidence.unreadableEntryCount, evidence.symbolicLinkCount, evidence.reachedEntryLimit ? CNL10n.string(" · 已达条目上限，大小仅为下限") : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let date = item.latestModificationDate {
                    Text(CNL10n.format("最近文件写入：%@（不是最后使用时间）", date.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                rowActions(item)
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 6)
    }

    @ViewBuilder private func rowActions(_ item: SystemDataItem) -> some View {
        HStack {
            if item.status == .protectedLocation {
                Button("查看访问权限") { state.cancel(); dismiss(); store.openSettings(.scanAndPrivacy) }
            } else if item.status == .measured || item.status == .partial {
                Button("在 Finder 查看") {
                    if !store.demoMode { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                }.disabled(store.demoMode)
                Button("查看里面的大项") {
                    state.cancel(); dismiss()
                    Task { await store.analyze(item.url) }
                }.disabled(state.isScanning || store.demoMode)
            }
            if item.location.disposition == .rebuildable {
                Button("去清理空间复核") { state.cancel(); dismiss(); store.selection = .cleanup }
                    .disabled(state.isScanning)
            } else if ["ollama", "huggingface", "lmstudio", "claude-vm"].contains(item.id) {
                Button(item.id == "claude-vm" ? "去 Agent 工作区" : "去本地模型管理") {
                    state.cancel(); dismiss()
                    store.selection = item.id == "claude-vm" ? .agentWorkspace : .models
                }.disabled(state.isScanning)
            }
        }.controlSize(.small)
    }
}
