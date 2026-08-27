import Foundation

/// Canonical locations for CleanNest-owned local state.
///
/// Keeping these paths in CleanNestCore lets the GUI and the read-only MCP
/// process agree on the same files without environment variables or a network
/// service. Callers may still inject temporary paths in tests.
public enum CleanNestDataPaths {
    public static func applicationSupportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("CleanNest", isDirectory: true)
    }

    public static func metricsDatabase(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("metrics.sqlite3", isDirectory: false)
    }

    public static func systemAlertTimeline(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("system-alert-timeline.json", isDirectory: false)
    }

    public static func diskEvidenceSnapshot(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("disk-evidence.json", isDirectory: false)
    }

    public static func diskEvidenceHistory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("disk-evidence-history.json", isDirectory: false)
    }

    public static func diskScanCache(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("disk-scan-cache.json", isDirectory: false)
    }

    public static func diskManualDecisions(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("disk-manual-decisions.json", isDirectory: false)
    }

    public static func cleanupPreviewSnapshot(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("cleanup-preview.json", isDirectory: false)
    }

    public static func activityLog(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("activity.json", isDirectory: false)
    }

    public static func activityLifetimeTotals(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("activity-lifetime-totals.json", isDirectory: false)
    }

    public static func evolutionMemory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("evolution-memory.json", isDirectory: false)
    }

    public static func agentWorkspaceObservation(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("agent-workspace-observation.json", isDirectory: false)
    }

    public static func agentWorkspaceSummary(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("agent-workspace-summary.json", isDirectory: false)
    }

    public static func agentWorkspaceRecoveryDirectory(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("AgentRecovery", isDirectory: true)
    }
}
