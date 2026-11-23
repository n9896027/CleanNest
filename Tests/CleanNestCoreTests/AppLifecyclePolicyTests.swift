import XCTest
@testable import CleanNestCore

final class AppLifecyclePolicyTests: XCTestCase {
    func testColdStartNeverIncludesPageScopedHeavyScanners() {
        let workloads = AppLifecyclePolicy.bootstrapWorkloads(
            menuBarMonitoringEnabled: true,
            localModelMenuBarEnabled: true
        )

        XCTAssertTrue(workloads.contains(.nativeMenuBarMonitor))
        XCTAssertTrue(workloads.contains(.metricsStorage))
        XCTAssertTrue(workloads.contains(.localModelRuntimeDiscovery))
        XCTAssertFalse(workloads.contains(.agentWorkspaceScan))
        XCTAssertFalse(workloads.contains(.agentDependencyGraph))
        XCTAssertFalse(workloads.contains(.nativeDeveloperStorage))
        XCTAssertFalse(workloads.contains(.localModelCatalog))
        XCTAssertFalse(workloads.contains(.fullDiskAccessProbe))
        XCTAssertFalse(workloads.contains(.processInspection))
    }

    func testAgentAndSystemWorkloadsAreBoundToTheirOwnPages() {
        XCTAssertEqual(
            AppLifecyclePolicy.foregroundWorkloads(for: .agentWorkspace),
            [.agentWorkspaceScan, .agentDependencyGraph, .nativeDeveloperStorage]
        )
        XCTAssertEqual(
            AppLifecyclePolicy.foregroundWorkloads(for: .systemStatus),
            [.metricHistory, .processInspection]
        )
        XCTAssertTrue(
            AppLifecyclePolicy.foregroundWorkloads(for: .overview).isEmpty
        )
        XCTAssertTrue(
            AppLifecyclePolicy.foregroundWorkloads(for: .settings).isEmpty
        )
        XCTAssertEqual(
            AppLifecyclePolicy.foregroundWorkloads(forSettingsSection: .scanAndPrivacy),
            [.fullDiskAccessProbe]
        )
        XCTAssertEqual(
            AppLifecyclePolicy.foregroundWorkloads(forSettingsSection: .localAI),
            [.localModelCatalog, .localModelRuntimeDiscovery, .localAIProbe]
        )
        XCTAssertTrue(
            AppLifecyclePolicy.foregroundWorkloads(forSettingsSection: .general).isEmpty
        )
    }

    func testOnlyHeavyPresentationPagesRequestRelease() {
        XCTAssertTrue(AppLifecyclePolicy.releasesHeavyPresentationData(whenLeaving: .agentWorkspace))
        XCTAssertTrue(AppLifecyclePolicy.releasesHeavyPresentationData(whenLeaving: .systemStatus))
        XCTAssertFalse(AppLifecyclePolicy.releasesHeavyPresentationData(whenLeaving: .activity))
        XCTAssertFalse(AppLifecyclePolicy.releasesHeavyPresentationData(whenLeaving: .overview))
        XCTAssertFalse(AppLifecyclePolicy.releasesHeavyPresentationData(whenLeaving: .cleanup))
    }
}
