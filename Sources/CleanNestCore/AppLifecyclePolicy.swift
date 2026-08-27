import Foundation

public enum CleanNestSurface: String, CaseIterable, Codable, Sendable {
    case overview
    case cleanup
    case applications
    case disk
    case systemStatus
    case maintenance
    case agentWorkspace
    case localModels
    case learning
    case activity
    case settings
}

public enum CleanNestWorkload: String, CaseIterable, Codable, Hashable, Sendable {
    case nativeMenuBarMonitor
    case engineProbe
    case metricsStorage
    case metricHistory
    case processInspection
    case fullDiskAccessProbe
    case localModelCatalog
    case localModelRuntimeDiscovery
    case localAIProbe
    case agentWorkspaceScan
    case agentDependencyGraph
    case nativeDeveloperStorage
}

/// Centralizes which work is allowed at launch and which work is page-scoped.
/// The GUI executes this policy; tests can therefore prevent a heavy scanner
/// from quietly returning to the cold-start path.
public enum AppLifecyclePolicy {
    public static func bootstrapWorkloads(
        menuBarMonitoringEnabled: Bool,
        localModelMenuBarEnabled: Bool
    ) -> Set<CleanNestWorkload> {
        var workloads: Set<CleanNestWorkload> = [.engineProbe, .metricsStorage]
        if menuBarMonitoringEnabled { workloads.insert(.nativeMenuBarMonitor) }
        if localModelMenuBarEnabled { workloads.insert(.localModelRuntimeDiscovery) }
        return workloads
    }

    public static func foregroundWorkloads(for surface: CleanNestSurface) -> Set<CleanNestWorkload> {
        switch surface {
        case .overview, .maintenance, .learning, .activity:
            return []
        case .cleanup, .applications, .disk:
            return [.fullDiskAccessProbe]
        case .systemStatus:
            return [.metricHistory, .processInspection]
        case .agentWorkspace:
            return [.agentWorkspaceScan, .agentDependencyGraph, .nativeDeveloperStorage]
        case .localModels:
            return [.localModelCatalog, .localModelRuntimeDiscovery, .localAIProbe]
        case .settings:
            return [.fullDiskAccessProbe, .localModelCatalog]
        }
    }

    public static func releasesHeavyPresentationData(whenLeaving surface: CleanNestSurface) -> Bool {
        surface == .agentWorkspace || surface == .systemStatus
    }
}
