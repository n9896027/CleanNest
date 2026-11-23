import SwiftUI
import CleanNestCore

struct APFSDiagnosticsCard: View {
    @EnvironmentObject private var store: AppStore
    let diskReport: DiskReport

    private var sparseFiles: [SparseFileSizeEvidence] {
        diskReport.largeFiles.prefix(40).compactMap { entry in
            guard !entry.isDirectory,
                  let evidence = try? SparseFileSizeEvidence.capture(at: entry.url),
                  evidence.isSparse else { return nil }
            return evidence
        }
    }

    var body: some View {
        SurfaceCard(title: "APFS 与稀疏文件只读诊断", symbol: "internaldrive") {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("把逻辑大小、实际分配块与卷总账分开")
                            .font(.subheadline.weight(.semibold))
                        Text("这里只读取证据，不清空废纸篓、不删除快照，也不执行 purge。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        Task { await store.refreshAPFSDiagnostics() }
                    } label: {
                        Label("重新读取", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.diskAPFSDiagnosticsAreRefreshing)
                }

                if store.diskAPFSDiagnosticsAreRefreshing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在读取有界只读诊断…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let report = store.diskAPFSDiagnosticReport {
                    volumeFacts(report)
                    trashFacts(report.trash)
                    sparseFileFacts
                    apfsVolumeFacts(report)
                    snapshotFacts(report)
                    if !report.diagnostics.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(report.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                                Label(diagnostic, systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundStyle(CNTheme.warning)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                } else if !store.diskAPFSDiagnosticsAreRefreshing {
                    Text("只读诊断尚不可用；可以点击“重新读取”。未知不会被换算成可清理空间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: store.diskRoot.path) {
            await store.refreshAPFSDiagnostics()
        }
    }

    private func volumeFacts(_ report: APFSDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("卷容量")
                .font(.caption.weight(.semibold))
            if let volume = report.volume {
                factRow(title: "卷", value: volume.volumeName)
                factRow(title: "已用／可用", value: "\(CleanNestFormatting.bytes(volume.usedBytes)) ／ \(CleanNestFormatting.bytes(volume.availableBytes))")
                factRow(
                    title: "重要用途可用",
                    value: volume.availableForImportantUsageBytes.map(CleanNestFormatting.bytes) ?? "未知"
                )
            } else {
                factRow(title: "卷总账", value: "未知")
            }
        }
        .padding(12)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private func trashFacts(_ trash: APFSTrashSizeEvidence) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("当前用户废纸篓")
                .font(.caption.weight(.semibold))
            factRow(title: "逻辑大小", value: trash.logicalBytes.map(CleanNestFormatting.bytes) ?? "未知")
            factRow(title: "分配块", value: trash.allocatedBytes.map(CleanNestFormatting.bytes) ?? "未知")
            Text(CNL10n.format("只读遍历 %@ 项；不可读 %@ 项。清空前不会把占用记为已释放。", trash.visitedEntryCount.formatted(), trash.unreadableEntryCount.formatted()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private var sparseFileFacts: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("当前大文件清单中的稀疏文件")
                .font(.caption.weight(.semibold))
            if sparseFiles.isEmpty {
                Text("当前清单未发现稀疏文件；这不是对整个卷的结论。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sparseFiles.prefix(4)) { file in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.url.lastPathComponent)
                            .font(.caption.weight(.medium))
                        Text(CNL10n.format("逻辑 %@ · 实际分配 %@ · 稀疏差额 %@", CleanNestFormatting.bytes(file.logicalBytes), CleanNestFormatting.bytes(file.allocatedBytes), CleanNestFormatting.bytes(file.unallocatedLogicalBytes)))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(file.url.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    }
                }
                Text("稀疏差额不是可直接释放的物理空间；实际分配块才用于磁盘占用解释。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private func apfsVolumeFacts(_ report: APFSDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("APFS 卷摘要")
                .font(.caption.weight(.semibold))
            if report.apfsVolumes.isEmpty {
                Text("卷明细未知")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.apfsVolumes.prefix(6)) { volume in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(volume.name) · \(volume.role ?? volume.id)")
                            .font(.caption.weight(.medium))
                        Text(CNL10n.format("已用 %@ · 容量 %@", volume.usedBytes.map(CleanNestFormatting.bytes) ?? "未知", volume.capacityBytes.map(CleanNestFormatting.bytes) ?? "未知"))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("同容器卷可能共享容量，不能把各卷容量相加。未显示的 Preboot、Recovery、VM 等卷也不能自动视为垃圾。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private func snapshotFacts(_ report: APFSDiagnosticReport) -> some View {
        let snapshotCommandSucceeded = report.commands.contains {
            $0.id == "tmutil listlocalsnapshots /" && $0.succeeded
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("本地快照")
                .font(.caption.weight(.semibold))
            if snapshotCommandSucceeded {
                Text(CNL10n.format("系统返回 %@ 个本地快照；仅显示名称，不执行删除。", report.localSnapshots.count.formatted()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(Array(report.localSnapshots.prefix(3).enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                }
            } else {
                Text("本地快照未知；不会根据卷差额猜测快照数量或大小。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private func factRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
