import AppKit
import Darwin
import Foundation

enum MemoryBudgetCapture {
    private struct Sample: Codable {
        let phase: String
        let capturedAt: Date
        let physicalFootprintBytes: UInt64?
    }

    private struct Report: Codable {
        let schemaVersion: Int
        let mode: String
        let appVersion: String
        let demoMode: Bool
        let samples: [Sample]
        let coldBudgetBytes: UInt64
        let settledBudgetBytes: UInt64
        let interactionBudgetBytes: UInt64
        let passed: Bool
        let limitations: [String]
    }

    private static let coldBudget: UInt64 = 220 * 1_024 * 1_024
    private static let settledBudget: UInt64 = 350 * 1_024 * 1_024
    private static let interactionBudget: UInt64 = 650 * 1_024 * 1_024

    @MainActor
    static func runIfRequested(store: AppStore) {
        let environment = ProcessInfo.processInfo.environment
        guard let rawPath = environment["CLEANNEST_MEMORY_REPORT"],
              rawPath.hasSuffix(".json") else { return }
        let outputURL = URL(fileURLWithPath: rawPath).standardizedFileURL
        let mode = environment["CLEANNEST_MEMORY_MODE"]?.lowercased() ?? "cold"
        let settleSeconds = environment["CLEANNEST_MEMORY_SETTLE_SECONDS"]
            .flatMap(Double.init)
            .map { min(300, max(1, $0)) } ?? 60

        Task {
            await run(
                mode: mode,
                settleSeconds: settleSeconds,
                outputURL: outputURL,
                store: store
            )
        }
    }

    @MainActor
    private static func run(
        mode: String,
        settleSeconds: Double,
        outputURL: URL,
        store: AppStore
    ) async {
        var samples: [Sample] = []
        var limitations: [String] = []

        switch mode {
        case "cold":
            await pause(seconds: 15)
            samples.append(sample("cold-15s"))

        case "tour":
            let pages: [SidebarItem] = [
                .overview, .cleanup, .applications, .analyze, .status,
                .maintenance, .agentWorkspace, .models, .evolution,
                .activity, .settings
            ]
            for page in pages {
                store.selection = page
                await store.activatePage(page)
                await pause(seconds: store.demoMode ? 0.35 : 1.0)
                samples.append(sample("page-\(page.lifecycleSurface.rawValue)"))
            }
            store.selection = .overview
            await store.activatePage(.overview)
            await pause(seconds: settleSeconds)
            samples.append(sample("tour-settled"))
            if store.demoMode {
                limitations.append("页面巡游使用合成数据；它验证渲染生命周期，不证明真实扫描峰值。")
            }

        case "agent":
            store.selection = .agentWorkspace
            await store.activatePage(.agentWorkspace)
            samples.append(sample("agent-first-scan"))
            await store.refreshAgentWorkspace()
            samples.append(sample("agent-repeat-scan"))
            store.selection = .overview
            await store.activatePage(.overview)
            await pause(seconds: settleSeconds)
            samples.append(sample("agent-settled"))

        default:
            limitations.append(CNL10n.format("未知模式 %@；没有执行内存场景。", String(describing: mode)))
        }

        let passed: Bool
        switch mode {
        case "cold":
            passed = samples.last?.physicalFootprintBytes.map { $0 <= coldBudget } ?? false
        case "tour":
            let peak = samples.compactMap(\.physicalFootprintBytes).max()
            let settled = samples.last?.physicalFootprintBytes
            passed = peak.map { $0 <= interactionBudget } == true
                && settled.map { $0 <= settledBudget } == true
        case "agent":
            let settled = samples.last?.physicalFootprintBytes
            passed = settled.map { $0 <= settledBudget } == true
        default:
            passed = false
        }

        let report = Report(
            schemaVersion: 1,
            mode: mode,
            appVersion: AppMetadata.compactDisplayVersion,
            demoMode: store.demoMode,
            samples: samples,
            coldBudgetBytes: coldBudget,
            settledBudgetBytes: settledBudget,
            interactionBudgetBytes: interactionBudget,
            passed: passed,
            limitations: limitations
        )

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: outputURL, options: .atomic)
            print("CleanNest memory report: \(outputURL.path)")
        } catch {
            fputs("CleanNest memory report failed: \(error.localizedDescription)\n", stderr)
        }
        store.shutdownForTermination()
        NSApp.terminate(nil)
    }

    private static func sample(_ phase: String) -> Sample {
        Sample(
            phase: phase,
            capturedAt: Date(),
            physicalFootprintBytes: currentPhysicalFootprint()
        )
    }

    private static func currentPhysicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }

    private static func pause(seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
