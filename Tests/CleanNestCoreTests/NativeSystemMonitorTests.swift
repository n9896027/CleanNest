import XCTest
@testable import CleanNestCore

final class NativeSystemMonitorTests: XCTestCase {
    func testCPUUsageUsesOnlyTickDelta() {
        let previous = NativeCPUTicks(user: 100, system: 40, idle: 360, nice: 0)
        let current = NativeCPUTicks(user: 140, system: 60, idle: 400, nice: 0)

        XCTAssertEqual(
            NativeMonitorMath.cpuUsage(previous: previous, current: current) ?? -1,
            60,
            accuracy: 0.001
        )
    }

    func testCPUBreakdownSeparatesUserSystemAndIdle() throws {
        let previous = NativeCPUTicks(user: 100, system: 40, idle: 360, nice: 10)
        let current = NativeCPUTicks(user: 130, system: 60, idle: 400, nice: 20)
        let breakdown = try XCTUnwrap(
            NativeMonitorMath.cpuBreakdown(previous: previous, current: current)
        )

        XCTAssertEqual(breakdown.total, 60, accuracy: 0.001)
        XCTAssertEqual(breakdown.user, 40, accuracy: 0.001)
        XCTAssertEqual(breakdown.system, 20, accuracy: 0.001)
        XCTAssertEqual(breakdown.idle, 40, accuracy: 0.001)
    }

    func testCPUUsageRejectsCounterRollbackAndEmptyInterval() {
        let previous = NativeCPUTicks(user: 100, system: 40, idle: 360, nice: 0)
        XCTAssertNil(NativeMonitorMath.cpuUsage(previous: previous, current: previous))
        XCTAssertNil(NativeMonitorMath.cpuUsage(
            previous: previous,
            current: NativeCPUTicks(user: 99, system: 50, idle: 370, nice: 0)
        ))
    }

    func testNetworkRateRejectsRollbackAndUsesElapsedTime() {
        XCTAssertEqual(
            NativeMonitorMath.bytesPerSecond(
                previousBytes: 1_000,
                currentBytes: 5_000,
                elapsed: 2
            ) ?? -1,
            2_000,
            accuracy: 0.001
        )
        XCTAssertNil(NativeMonitorMath.bytesPerSecond(
            previousBytes: 5_000,
            currentBytes: 100,
            elapsed: 2
        ))
        XCTAssertNil(NativeMonitorMath.bytesPerSecond(
            previousBytes: 1_000,
            currentBytes: 5_000,
            elapsed: 0
        ))
    }

    func testBatteryTemperatureNormalizesIOKitCentiDegrees() {
        XCTAssertEqual(
            NativeSystemMonitor.normalizedBatteryTemperature(3_038) ?? -1,
            30.38,
            accuracy: 0.001
        )
        XCTAssertEqual(
            NativeSystemMonitor.normalizedBatteryTemperature(30.5) ?? -1,
            30.5,
            accuracy: 0.001
        )
        XCTAssertNil(NativeSystemMonitor.normalizedBatteryTemperature(20_000))
        XCTAssertNil(NativeSystemMonitor.normalizedBatteryTemperature(.infinity))
    }

    func testDefaultConfigurationIsVisibleButGPUIsOptIn() {
        let configuration = MenuBarMonitorConfiguration.defaults
        XCTAssertTrue(configuration.isEnabled)
        XCTAssertTrue(configuration.preference(for: .cpu).isEnabled)
        XCTAssertTrue(configuration.preference(for: .memory).isEnabled)
        XCTAssertTrue(configuration.preference(for: .temperature).isEnabled)
        XCTAssertTrue(configuration.preference(for: .network).isEnabled)
        XCTAssertTrue(configuration.preference(for: .disk).isEnabled)
        XCTAssertFalse(configuration.preference(for: .gpu).isEnabled)
        XCTAssertTrue(configuration.preference(for: .fan).isEnabled)
        XCTAssertFalse(configuration.preference(for: .battery).isEnabled)
        XCTAssertEqual(configuration.presentationMode, .compact)
        XCTAssertEqual(configuration.networkMode, .physicalAggregate)
        XCTAssertEqual(configuration.refreshInterval, .twoSeconds)
        XCTAssertTrue(configuration.metrics.allSatisfy { $0.style == .text })
    }

    func testNormalizedConfigurationAddsNewMetricsWithoutOverwritingChoice() {
        let oldConfiguration = MenuBarMonitorConfiguration(
            isEnabled: false,
            metrics: [
                MenuBarMetricPreference(metric: .cpu, isEnabled: false, style: .graph)
            ]
        ).normalized

        XCTAssertFalse(oldConfiguration.isEnabled)
        XCTAssertFalse(oldConfiguration.preference(for: .cpu).isEnabled)
        XCTAssertEqual(oldConfiguration.preference(for: .cpu).style, .graph)
        XCTAssertEqual(oldConfiguration.metrics.count, MenuBarMetric.allCases.count)
        XCTAssertTrue(oldConfiguration.preference(for: .memory).isEnabled)
    }

    func testLegacyConfigurationDecodesWithNewSafeDefaults() throws {
        let data = try XCTUnwrap(
            #"{"isEnabled":true,"metrics":[{"metric":"memory","isEnabled":true,"style":"graph"},{"metric":"cpu","isEnabled":true,"style":"text"}]}"#
                .data(using: .utf8)
        )
        var configuration = try JSONDecoder().decode(
            MenuBarMonitorConfiguration.self,
            from: data
        ).normalized

        XCTAssertEqual(configuration.metrics.prefix(2).map(\.metric), [.memory, .cpu])
        XCTAssertEqual(configuration.presentationMode, .compact)
        XCTAssertEqual(configuration.networkMode, .physicalAggregate)
        XCTAssertTrue(configuration.globalHotKeyEnabled)

        configuration.move(.cpu, by: -1)
        XCTAssertEqual(configuration.metrics.prefix(2).map(\.metric), [.cpu, .memory])
    }
}
