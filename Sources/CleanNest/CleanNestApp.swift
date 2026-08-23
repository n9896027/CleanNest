import AppKit
import SwiftUI

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
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    appDelegate.onWillTerminate = { store.shutdownForTermination() }
                    appDelegate.onDidResignActive = { store.applicationDidResignActive() }
                    appDelegate.onDidBecomeActive = {
                        Task { await store.applicationDidBecomeActive() }
                    }
                    SnapshotCapture.captureIfRequested(store: store)
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
                        default: await store.refreshEngine()
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.windows.first?.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        onWillTerminate?()
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
