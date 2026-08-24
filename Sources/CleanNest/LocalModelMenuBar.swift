import AppKit
import Combine
import SwiftUI
import CleanNestCore

@MainActor
final class LocalModelMenuBarController: NSObject, NSPopoverDelegate {
    private weak var store: AppStore?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private let popover = NSPopover()

    func connect(store: AppStore) {
        guard self.store !== store else { return }
        self.store = store
        cancellables.removeAll()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 380, height: 430)

        Publishers.CombineLatest3(
            store.$localModelRuntimeSnapshot,
            store.$localModelDiscoveryPhase,
            store.$localModelMenuBarEnabled
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] snapshot, phase, enabled in
            self?.update(snapshot: snapshot, phase: phase, enabled: enabled)
        }
        .store(in: &cancellables)
    }

    private func update(
        snapshot: LocalModelRuntimeSnapshot,
        phase: LocalModelRuntimePhase,
        enabled: Bool
    ) {
        guard enabled else {
            removeStatusItem()
            return
        }
        let item = statusItem ?? makeStatusItem()
        guard let button = item.button else { return }
        let topValue: String
        switch phase {
        case .runningHealthy:
            topValue = String(max(1, snapshot.healthyInstances.count))
        case .runningUnverified: topValue = "!"
        case .failed: topValue = "×"
        case .discovering: topValue = "…"
        case .unknown, .stopped: topValue = "—"
        }
        let image = statusImage(topValue: topValue, phase: phase)
        item.length = image.size.width + 4
        button.title = ""
        button.imagePosition = .imageOnly
        button.image = image
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseUp])
        button.toolTip = "本地模型 · " + statusDescription(snapshot: snapshot, phase: phase)
        button.setAccessibilityLabel("本地模型，" + statusDescription(snapshot: snapshot, phase: phase))
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: 44)
        item.autosaveName = "CleanNest.LocalModelRuntime"
        statusItem = item
        return item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        popover.performClose(nil)
    }

    @objc private func statusItemPressed(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let store else { return }
        popover.contentViewController = NSHostingController(
            rootView: LocalModelMenuBarPopover()
                .environmentObject(store)
        )
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func statusImage(topValue: String, phase: LocalModelRuntimePhase) -> NSImage {
        let size = NSSize(width: 39, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let stateColor = phase.nsColor
            let labelColor = NSColor.labelColor
            let dot = NSBezierPath(ovalIn: NSRect(x: 4, y: 14, width: 5, height: 5))
            stateColor.setFill()
            dot.fill()
            (topValue as NSString).draw(
                in: NSRect(x: 8, y: 9, width: rect.width - 10, height: 12),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold),
                    .foregroundColor: labelColor,
                    .paragraphStyle: paragraph
                ]
            )
            ("MODEL" as NSString).draw(
                in: NSRect(x: 0, y: 0, width: rect.width, height: 9),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 6.5, weight: .medium),
                    .foregroundColor: labelColor,
                    .paragraphStyle: paragraph,
                    .kern: 0.18
                ]
            )
            return true
        }
        image.isTemplate = false
        return image
    }

    private func statusDescription(
        snapshot: LocalModelRuntimeSnapshot,
        phase: LocalModelRuntimePhase
    ) -> String {
        switch phase {
        case .runningHealthy:
            let runtime = snapshot.primaryInstance
            return "\(runtime?.platform.displayName ?? "模型服务") 正在运行，\(runtime?.primaryModelID ?? "短 ID 已确认")"
        case .runningUnverified: return "发现进程或端口，模型身份尚未确认"
        case .failed: return "发现失败，可打开详情重试"
        case .discovering: return "正在检查进程、端口与模型 API"
        case .unknown: return "尚未检查"
        case .stopped: return "当前没有模型在运行"
        }
    }
}

private struct LocalModelMenuBarPopover: View {
    @EnvironmentObject private var store: AppStore

    private var runtime: LocalModelRuntimeInstance? {
        store.localModelRuntimeSnapshot.primaryInstance
    }

    private var tint: Color {
        switch store.localModelDiscoveryPhase {
        case .runningHealthy: return CNTheme.success
        case .runningUnverified: return CNTheme.warning
        case .failed: return CNTheme.danger
        case .discovering: return CNTheme.cyan
        case .unknown, .stopped: return .secondary
        }
    }

    var body: some View {
        ZStack {
            CNVisualEffectBackground(material: .popover)
            LinearGradient(
                colors: [tint.opacity(0.13), Color.clear, CNTheme.cyan.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    CNIconTile(symbol: "rectangle.stack.badge.play", tint: tint, size: 35)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("本地模型运行中心")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(store.localModelRuntimeStatusTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle().fill(tint).frame(width: 8, height: 8)
                        .accessibilityLabel(store.localModelRuntimeStatusTitle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                VStack(alignment: .leading, spacing: 15) {
                    Text(runtime?.primaryModelID ?? "没有确认到正在运行的模型")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .textSelection(.enabled)

                    HStack(spacing: 8) {
                        compactFact(
                            title: "平台",
                            value: runtime?.platform.shortName ?? "—",
                            symbol: "server.rack"
                        )
                        compactFact(
                            title: "地址",
                            value: runtime?.primaryAddress ?? "—",
                            symbol: "network"
                        )
                    }

                    HStack(spacing: 8) {
                        compactFact(
                            title: "进程",
                            value: runtime?.process.map { "PID \($0.pid)" } ?? "未关联",
                            symbol: "gearshape.2"
                        )
                        compactFact(
                            title: runtime?.supervisor == nil ? "暴露" : "守护",
                            value: runtime?.supervisor.map {
                                $0.isDisabled ? "已停用" : ($0.keepAlive ? "KeepAlive" : "launchd")
                            } ?? runtime?.exposure.displayName ?? "—",
                            symbol: runtime?.supervisor == nil
                                ? (runtime?.exposure == .localNetwork ? "exclamationmark.shield" : "lock.shield")
                                : "arrow.triangle.2.circlepath"
                        )
                    }

                    Text(runtime?.diagnostic ?? store.localModelRuntimeDiagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if runtime?.exposure == .localNetwork {
                        Label("该服务可能被局域网访问", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(CNTheme.warning)
                    }
                }
                .padding(16)
                .frame(maxHeight: .infinity, alignment: .top)

                Divider()

                HStack(spacing: 8) {
                    Button {
                        store.showMainWindow(selection: .models)
                    } label: {
                        Label("打开运行中心", systemImage: "rectangle.stack.badge.play")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    if runtime?.canStopDirectly == true {
                        Button(role: .destructive) {
                            Task { await store.stopOwnedLocalModelRuntime() }
                        } label: {
                            Label("停止", systemImage: "stop.fill")
                        }
                        .disabled(store.localAIServiceState.isBusy)
                    } else if runtime?.supervisor?.canDisableAndStop == true {
                        Button {
                            store.showMainWindow(selection: .models)
                        } label: {
                            Label("停用守护…", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .help("打开运行中心，查看自动重启风险并停用精确守护服务")
                    } else if runtime?.supervisor?.canEnable == true {
                        Button {
                            store.showMainWindow(selection: .models)
                        } label: {
                            Label("重新启用…", systemImage: "play.circle")
                        }
                    } else if runtime?.canRequestExternalStop == true {
                        Button {
                            store.showMainWindow(selection: .models)
                        } label: {
                            Label("管理/关闭…", systemImage: "exclamationmark.shield")
                        }
                        .help("打开运行中心，查看风险并确认关闭外部服务")
                    } else if store.localModelRuntimeSnapshot.healthyInstances.isEmpty,
                              store.configuredLocalModelCanStart {
                        Button {
                            Task { await store.startConfiguredLocalModelRuntime() }
                        } label: {
                            Label("启动", systemImage: "play.fill")
                        }
                        .disabled(store.localAIServiceState.isBusy)
                    } else {
                        Button {
                            Task { await store.refreshLocalModelRuntimes() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("重新发现本地模型")
                        .disabled(store.localModelDiscoveryIsRunning)
                    }
                }
                .controlSize(.small)
                .padding(14)
            }
        }
        .frame(width: 380, height: 430)
    }

    private func compactFact(title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CNTheme.cyan)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .accessibilityElement(children: .combine)
    }
}

private extension LocalModelRuntimePhase {
    var nsColor: NSColor {
        switch self {
        case .runningHealthy: return .systemGreen
        case .runningUnverified: return .systemOrange
        case .failed: return .systemRed
        case .discovering: return .systemCyan
        case .unknown, .stopped: return .secondaryLabelColor
        }
    }
}
