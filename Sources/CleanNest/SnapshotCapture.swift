import AppKit
import Foundation
import SwiftUI
import CleanNestCore

enum SnapshotCapture {
    @MainActor
    static func captureIfRequested(store: AppStore) {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CLEANNEST_DEMO"] == "1",
              let requestedPath = environment["CLEANNEST_SNAPSHOT"],
              requestedPath.hasSuffix(".png") else {
            return
        }

        let outputURL = URL(fileURLWithPath: requestedPath).standardizedFileURL
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let content = SnapshotShell()
                .environmentObject(store)
                .frame(width: 1120, height: 760)
                .background(CNTheme.canvas)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: 1120, height: 760)
            renderer.scale = 2

            do {
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.createDirectory(
                    at: outputURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try png.write(to: outputURL, options: .atomic)
                print("CleanNest snapshot: \(outputURL.path)")
            } catch {
                fputs("CleanNest snapshot failed: \(error.localizedDescription)\n", stderr)
            }
            NSApp.terminate(nil)
        }
    }
}

private struct SnapshotShell: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(CNTheme.accent)
                        Image(systemName: "leaf.fill").foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("CleanNest").font(.headline)
                        Text("本地 Mac 管家").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(14)

                VStack(alignment: .leading, spacing: 5) {
                    snapshotRow(.overview)
                    Text("空间").font(.caption).foregroundStyle(.secondary).padding(.top, 12).padding(.leading, 9)
                    ForEach(SidebarItem.spaceItems) { snapshotRow($0) }
                    Text("系统").font(.caption).foregroundStyle(.secondary).padding(.top, 12).padding(.leading, 9)
                    ForEach(SidebarItem.systemItems) { snapshotRow($0) }
                    snapshotRow(.activity).padding(.top, 12)
                    snapshotRow(.settings)
                }
                .padding(.horizontal, 10)
                Spacer()
                HStack(spacing: 8) {
                    Circle().fill(CNTheme.success).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("本地引擎就绪").font(.caption.weight(.medium))
                        Text(store.engine?.version ?? "Mole CLI").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .frame(width: 216)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()
            SnapshotOverview()
                .frame(width: 903, height: 760)
                .background(CNTheme.canvas)
        }
    }

    private func snapshotRow(_ item: SidebarItem) -> some View {
        Label(item.rawValue, systemImage: item.symbol)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                item == .overview ? CNTheme.accent.opacity(0.13) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .foregroundStyle(item == .overview ? CNTheme.accent : Color.primary)
    }
}

private struct SnapshotOverview: View {
    @EnvironmentObject private var store: AppStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "让这台 Mac 保持从容",
                subtitle: "先查看，再决定。扫描和清理都在本机完成。"
            ) {
                StatusPill(text: "演示数据", symbol: "sparkles", style: .warning)
            }

            SurfaceCard {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("启动磁盘").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(CleanNestFormatting.bytes(store.diskTotalBytes - store.diskFreeBytes))
                                .font(.system(size: 30, weight: .semibold, design: .rounded))
                                .monospacedMetric()
                            Text("已使用").font(.subheadline).foregroundStyle(.secondary)
                        }
                        CapacityBar(used: store.diskTotalBytes - store.diskFreeBytes, total: store.diskTotalBytes)
                        Text("共 \(CleanNestFormatting.bytes(store.diskTotalBytes)) · 仍有 \(CleanNestFormatting.bytes(store.diskFreeBytes)) 可用")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button { } label: {
                            Label("重新扫描", systemImage: "sparkle.magnifyingglass")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Text("只扫描，不会自动更改文件").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            LazyVGrid(columns: columns, spacing: 12) {
                MetricCard(label: "可用空间", value: CleanNestFormatting.bytes(store.diskFreeBytes), detail: "启动磁盘当前可用", symbol: "internaldrive", tint: CNTheme.accent)
                MetricCard(label: "建议查看", value: CleanNestFormatting.bytes(store.cleanupPotentialBytes), detail: "执行前可逐项取消", symbol: "sparkles", tint: CNTheme.warning)
                MetricCard(label: "系统状态", value: store.systemSnapshot?.healthScore.map(String.init) ?? "—", detail: "只读检查，不制造焦虑", symbol: "waveform.path.ecg", tint: CNTheme.success)
            }

            HStack(alignment: .top, spacing: 14) {
                SurfaceCard(title: "快捷入口", symbol: "bolt") {
                    snapshotAction("查看最大文件夹", "从主目录浏览空间占用", "chart.pie")
                    Divider()
                    snapshotAction("管理已安装 App", "预览本体与精确匹配的文件", "app.dashed")
                    Divider()
                    snapshotAction("运行系统维护", "按任务执行，不做一键加速", "wrench.and.screwdriver")
                }
                SurfaceCard(title: "最近活动", symbol: "clock.arrow.circlepath") {
                    if let recent = store.activities.first {
                        HStack {
                            Image(systemName: recent.outcome.symbol).foregroundStyle(Color.outcome(recent.outcome))
                            Text(recent.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("2 小时前").font(.caption).foregroundStyle(.secondary)
                        }
                        Text(recent.detail).font(.caption).foregroundStyle(.secondary)
                        Text(CleanNestFormatting.bytes(recent.bytes))
                            .font(.title3.weight(.semibold)).monospacedMetric()
                        Text("查看全部记录 →")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(CNTheme.accent)
                    }
                    Spacer(minLength: 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(CNTheme.pagePadding)
    }

    private func snapshotAction(_ title: String, _ detail: String, _ symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(CNTheme.accent)
                .frame(width: 28, height: 28)
                .background(CNTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 7)
    }
}
