import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 206, ideal: 232, max: 270)
        } detail: {
            ZStack {
                AppCanvas()
                VStack(spacing: 0) {
                    Group {
                        switch store.selection ?? .overview {
                        case .overview: OverviewView()
                        case .cleanup: CleanupView()
                        case .applications: ApplicationsView()
                        case .analyze: DiskAnalyzeView()
                        case .status: SystemStatusView()
                        case .maintenance: MaintenanceView()
                        case .evolution: EvolutionView()
                        case .activity: ActivityView()
                        case .settings: SettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    OperationBanner()
                }
            }
        }
        .tint(CNTheme.accent)
        .navigationSplitViewStyle(.balanced)
        .background(CNWindowChromeConfigurator())
        .sheet(isPresented: $store.showingTechnicalDetail) {
            TechnicalDetailSheet(detail: store.lastTechnicalDetail)
        }
        .sheet(isPresented: $store.showingUpdateChecker) {
            UpdateCheckView()
                .environmentObject(store)
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var store: AppStore
    @State private var hoveredItem: SidebarItem?

    var body: some View {
        VStack(spacing: 0) {
            brand

            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    sidebarRow(.overview)
                    sidebarSection("空间", items: SidebarItem.spaceItems)
                    sidebarSection("系统", items: SidebarItem.systemItems)
                    sidebarSection("智能", items: SidebarItem.intelligenceItems)

                    VStack(spacing: 5) {
                        sidebarRow(.activity)
                        sidebarRow(.settings)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 10)
            }

            appFooter
        }
        .background {
            ZStack {
                CNVisualEffectBackground(material: .sidebar, blendingMode: .behindWindow)
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.055),
                        CNTheme.accent.opacity(0.025),
                        Color.black.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 0.5)
        }
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CNTheme.cyan, CNTheme.accent, CNTheme.accentStrong],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "leaf.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            .shadow(color: CNTheme.accent.opacity(0.26), radius: 12, y: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text("CleanNest")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("本地 Mac 管家")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 15)
        .padding(.top, 16)
        .padding(.bottom, 13)
    }

    private func sidebarSection(_ title: String, items: [SidebarItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CNL10n.string(title).uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.leading, 11)
            VStack(spacing: 5) {
                ForEach(items) { sidebarRow($0) }
            }
        }
    }

    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = (store.selection ?? .overview) == item
        return Button {
            store.selection = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? CNTheme.accent : .secondary)
                    .frame(width: 27, height: 27)
                    .background(
                        isSelected ? CNTheme.accent.opacity(0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                Text(item.displayName)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 39)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(isSelected ? 1 : (hoveredItem == item ? 0.52 : 0))
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [CNTheme.accent.opacity(0.18), CNTheme.cyan.opacity(0.055)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.white.opacity(0.085), lineWidth: 0.65)
            }
        }
        .overlay(alignment: .leading) {
            if isSelected {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [CNTheme.cyan, CNTheme.accent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: 20)
                    .shadow(color: CNTheme.accent.opacity(0.5), radius: 4)
                    .offset(x: -2)
            }
        }
        .onHover { hovering in
            hoveredItem = hovering ? item : (hoveredItem == item ? nil : hoveredItem)
        }
        .accessibilityLabel(item.displayName)
        .accessibilityValue(isSelected ? CNL10n.string("已选中") : "")
    }

    private var appFooter: some View {
        Button {
            store.selection = .settings
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                Text(AppMetadata.compactDisplayVersion)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(1)

                HStack(spacing: 8) {
                    Circle()
                        .fill(store.engine == nil ? CNTheme.warning : CNTheme.success)
                        .frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.engine == nil ? "引擎未连接" : "本地引擎就绪")
                            .font(.caption.weight(.medium))
                        Text(store.engine?.version ?? "点击设置")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [Color.white.opacity(0.045), CNTheme.accent.opacity(0.025)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [Color.clear, Color.white.opacity(0.11), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 0.7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppMetadata.displayVersion)，\(store.engine == nil ? "引擎未连接" : "本地引擎就绪")，\(store.engine?.version ?? "点击设置")")
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
