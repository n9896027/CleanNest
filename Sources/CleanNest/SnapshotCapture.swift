import AppKit
import Foundation

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
        store.selection = snapshotPage(environment["CLEANNEST_SNAPSHOT_PAGE"])

        let size = snapshotSize(environment: environment)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let window = NSApp.windows.first(where: \.isVisible) else {
                fputs("CleanNest snapshot failed: no visible app window\n", stderr)
                NSApp.terminate(nil)
                return
            }

            NSApp.activate(ignoringOtherApps: true)
            window.appearance = NSAppearance(named: .darkAqua)
            window.setContentSize(size)
            window.makeKeyAndOrderFront(nil)
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                do {
                    try FileManager.default.createDirectory(
                        at: outputURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    let capture = Process()
                    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    capture.arguments = ["-l", String(window.windowNumber), "-o", outputURL.path]
                    capture.standardOutput = FileHandle.nullDevice
                    capture.standardError = FileHandle.nullDevice
                    try capture.run()
                    capture.waitUntilExit()
                    guard capture.terminationStatus == 0,
                          FileManager.default.fileExists(atPath: outputURL.path) else {
                        throw CocoaError(.fileWriteNoPermission)
                    }
                    print("CleanNest snapshot: \(outputURL.path)")
                } catch {
                    fputs("CleanNest snapshot failed: \(error.localizedDescription)\n", stderr)
                }
                NSApp.terminate(nil)
            }
        }
    }

    private static func snapshotPage(_ rawValue: String?) -> SidebarItem {
        switch rawValue?.lowercased() {
        case "cleanup": return .cleanup
        case "applications": return .applications
        case "disk", "analyze": return .analyze
        case "status": return .status
        case "maintenance": return .maintenance
        case "agents", "agent", "workspace": return .agentWorkspace
        case "evolution", "learning": return .evolution
        case "activity": return .activity
        case "settings": return .settings
        default: return .overview
        }
    }

    private static func snapshotSize(environment: [String: String]) -> NSSize {
        let width = environment["CLEANNEST_SNAPSHOT_WIDTH"]
            .flatMap(Double.init)
            .map { min(2_000, max(820, $0)) } ?? 1_280
        let height = environment["CLEANNEST_SNAPSHOT_HEIGHT"]
            .flatMap(Double.init)
            .map { min(1_400, max(600, $0)) } ?? 800
        return NSSize(width: width, height: height)
    }
}
