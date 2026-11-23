import AppKit
import SwiftUI

enum CleanNestLaunchContext {
    static let menuBarOnly = ProcessInfo.processInfo.arguments.contains("--menubar-only")
}

@main
struct CleanNestApp: App {
    @NSApplicationDelegateAdaptor(CleanNestAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("CleanNest") {
            RootView()
                .environmentObject(store)
                .frame(
                    minWidth: 900,
                    idealWidth: 1120,
                    maxWidth: .infinity,
                    minHeight: 640,
                    idealHeight: 760,
                    maxHeight: .infinity
                )
                .tint(CNTheme.accent)
                .onAppear {
                    appDelegate.connect(store: store)
                    appDelegate.onWillTerminate = { store.shutdownForTermination() }
                    appDelegate.onDidResignActive = { store.applicationDidResignActive() }
                    appDelegate.onDidBecomeActive = {
                        Task { await store.applicationDidBecomeActive() }
                    }
                    appDelegate.onSystemWillSleep = { store.systemWillSleep() }
                    appDelegate.onSystemDidWake = {
                        Task { await store.systemDidWake() }
                    }
                    SnapshotCapture.captureIfRequested(store: store)
                    MemoryBudgetCapture.runIfRequested(store: store)
                    if CleanNestLaunchContext.menuBarOnly {
                        NSApp.setActivationPolicy(.accessory)
                        DispatchQueue.main.async {
                            NSApp.windows.filter { !($0 is NSPanel) }.forEach { $0.orderOut(nil) }
                        }
                    } else {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .appInfo) {
                Button("检查更新…") {
                    store.presentUpdateChecker()
                }
                .disabled(store.appUpdateState.isChecking)
                Divider()
            }
            CommandMenu("操作") {
                Button("重新扫描") {
                    Task {
                        switch store.selection {
                        case .cleanup: await store.scanCleanup()
                        case .applications: await store.scanApplications()
                        case .analyze: await store.analyze()
                        case .status: await store.refreshSystemStatus()
                        case .agentWorkspace: await store.refreshAgentWorkspace()
                        default: break
                        }
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store.isWorking)
            }
        }
    }
}

@MainActor
final class CleanNestAppDelegate: NSObject, NSApplicationDelegate {
    var onWillTerminate: (() -> Void)?
    var onDidResignActive: (() -> Void)?
    var onDidBecomeActive: (() -> Void)?
    var onSystemWillSleep: (() -> Void)?
    var onSystemDidWake: (() -> Void)?
    private var menuBarMonitorController: MenuBarMonitorController?
    private var localModelMenuBarController: LocalModelMenuBarController?
    private var workspaceNotificationsConnected = false

    func connect(store: AppStore) {
        if menuBarMonitorController == nil {
            menuBarMonitorController = MenuBarMonitorController()
        }
        if localModelMenuBarController == nil {
            localModelMenuBarController = LocalModelMenuBarController()
        }
        menuBarMonitorController?.connect(store: store)
        localModelMenuBarController?.connect(store: store)
        if !workspaceNotificationsConnected {
            let notifications = NSWorkspace.shared.notificationCenter
            notifications.addObserver(
                self,
                selector: #selector(workspaceWillSleep(_:)),
                name: NSWorkspace.willSleepNotification,
                object: nil
            )
            notifications.addObserver(
                self,
                selector: #selector(workspaceDidWake(_:)),
                name: NSWorkspace.didWakeNotification,
                object: nil
            )
            workspaceNotificationsConnected = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !CleanNestLaunchContext.menuBarOnly else {
            NSApp.setActivationPolicy(.accessory)
            DispatchQueue.main.async {
                NSApp.windows.filter { !($0 is NSPanel) }.forEach { $0.orderOut(nil) }
            }
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.setActivationPolicy(.regular)
        sender.windows.first?.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.removeObserver(self)
        workspaceNotificationsConnected = false
        onWillTerminate?()
    }

    @objc private func workspaceWillSleep(_ notification: Notification) {
        onSystemWillSleep?()
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        onSystemDidWake?()
    }

    func applicationDidResignActive(_ notification: Notification) {
        onDidResignActive?()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        onDidBecomeActive?()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
