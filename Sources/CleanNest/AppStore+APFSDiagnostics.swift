import Foundation
import CleanNestCore

@MainActor
extension AppStore {
    func refreshAPFSDiagnostics() async {
        let requestID = UUID()
        diskAPFSDiagnosticsRequestID = requestID
        guard !demoMode else {
            diskAPFSDiagnosticReport = nil
            diskAPFSDiagnosticsAreRefreshing = false
            return
        }
        diskAPFSDiagnosticReport = nil
        diskAPFSDiagnosticsAreRefreshing = true
        let selectedRoot = diskRoot
        let report = await APFSReadOnlyDiagnostics().capture(selectedRoot: selectedRoot)
        guard diskAPFSDiagnosticsRequestID == requestID else { return }
        diskAPFSDiagnosticReport = report
        diskAPFSDiagnosticsAreRefreshing = false
    }
}
