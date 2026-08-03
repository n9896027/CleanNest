import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 188, ideal: 216, max: 252)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    switch store.selection ?? .overview {
                    case .overview: OverviewView()
                    case .cleanup: CleanupView()
                    case .applications: ApplicationsView()
                    case .analyze: DiskAnalyzeView()
                    case .status: SystemStatusView()
                    case .maintenance: MaintenanceView()
                    case .activity: ActivityView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                OperationBanner()
            }
            .background(CNTheme.canvas)
        }
        .sheet(isPresented: $store.showingTechnicalDetail) {
            TechnicalDetailSheet(detail: store.lastTechnicalDetail)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List(selection: $store.selection) {
            sidebarRow(.overview)

            Section("空间") {
                ForEach(SidebarItem.spaceItems) { sidebarRow($0) }
            }

            Section("系统") {
                ForEach(SidebarItem.systemItems) { sidebarRow($0) }
            }

            Section {
                sidebarRow(.activity)
                sidebarRow(.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CNTheme.accent)
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CleanNest")
                        .font(.headline)
                    Text("本地 Mac 管家")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            engineFooter
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        Label(item.rawValue, systemImage: item.symbol)
            .tag(item)
    }

    private var engineFooter: some View {
        Button {
            store.selection = .settings
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(store.engine == nil ? CNTheme.warning : CNTheme.success)
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.engine == nil ? "引擎未连接" : "本地引擎就绪")
                        .font(.caption.weight(.medium))
                    Text(store.engine?.version ?? "点击设置")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct TechnicalDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("诊断详情").font(.title2.weight(.semibold))
                    Text("这些信息只来自本机，可复制后用于排查问题。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                Text(detail.isEmpty ? "没有额外诊断信息。" : detail)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(CNTheme.surfaceSubtle, in: RoundedRectangle(cornerRadius: 9))

            HStack {
                Spacer()
                Button("复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(detail, forType: .string)
                }
            }
        }
        .padding(22)
        .frame(width: 620, height: 420)
    }
}
