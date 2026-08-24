import AppKit
import Foundation

let mainBundleURL = Bundle.main.bundleURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let bundleIdentifier = "com.zone.cleannest"
if NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--menubar-only"]
    configuration.activates = false
    NSWorkspace.shared.openApplication(
        at: mainBundleURL,
        configuration: configuration
    ) { _, _ in
        CFRunLoopStop(CFRunLoopGetMain())
    }
    CFRunLoopRunInMode(.defaultMode, 8, false)
}
