import Combine
import Foundation
import CleanNestCore
import CleanNestMutation

/// Page-scoped observable state for the heaviest CleanNest surface.
///
/// Keeping these publications off `AppStore.objectWillChange` prevents an
/// Agent scan from invalidating unrelated pages and menu-bar controllers.
@MainActor
final class AgentWorkspacePresentationState: ObservableObject {
    @Published var cachedSummary: AgentWorkspaceSummary?
    @Published var snapshot: AgentWorkspaceSnapshot?
    @Published var phase: AgentWorkspaceScanPhase = .idle
    @Published var diagnostic = "尚未扫描 Agent 占用"
    @Published var selectedCandidateIDs = Set<String>()
    @Published var selectedProvider: AgentWorkspaceProvider?
    @Published var detailScanningProvider: AgentWorkspaceProvider?
    @Published var recoveryRecords: [AgentWorkspaceRecoveryRecord] = []
    @Published var recoveryPhase: AgentWorkspaceRecoveryPhase = .idle
    @Published var recoveryMessage: String?
    @Published var recoveryMessageIsWarning = false
    @Published var ruleCatalog = AgentRuleCatalog.builtIn
    @Published var ruleCatalogSource: AgentRuleCatalogSource = .builtIn
    @Published var ruleCatalogDiagnostic = "正在使用内置规则。"
    @Published var ruleCatalogUpdateIsRunning = false
    @Published var desktopInstallations: [AgentDesktopInstallation] = []
    @Published var desktopCandidates: [AgentDesktopCandidate] = []
    @Published var relatedSoftware: [AgentRelatedSoftwareInstallation] = []
    @Published var desktopInventoryIsRefreshing = false
    @Published var dependencyGraph = AgentDependencyGraphSnapshot.empty
    @Published var dependencyGraphIsRefreshing = false
    @Published var nativeDeveloperStorageSnapshot: NativeDeveloperStorageSnapshot?
    @Published var nativeDeveloperStorageIsRefreshing = false
    @Published var nativeDeveloperStorageActionTool: NativeDeveloperStorageTool?
    @Published var nativeDeveloperStorageMessage: String?
    @Published var nativeDeveloperStorageMessageIsWarning = false
    @Published var nativeGitRepository: URL?

    func releaseHeavyDetails() {
        snapshot = nil
        selectedCandidateIDs.removeAll(keepingCapacity: false)
        selectedProvider = nil
        detailScanningProvider = nil
        dependencyGraph = .empty
        nativeDeveloperStorageSnapshot = nil
        phase = .idle
        diagnostic = cachedSummary == nil
            ? "尚未扫描 Agent 占用"
            : "已释放文件级明细；再次进入时会重新验证。"
    }
}
