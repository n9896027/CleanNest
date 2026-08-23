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
        store.selection = .overview

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard let window = NSApp.windows.first(where: \.isVisible) else {
                fputs("CleanNest snapshot failed: no visible app window\n", stderr)
                NSApp.terminate(nil)
                return
            }

            window.appearance = NSAppearance(named: .darkAqua)
            window.setContentSize(NSSize(width: 1_280, height: 800))
            window.layoutIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
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
}
