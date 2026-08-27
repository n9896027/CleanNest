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

    func testNormalWorkloadDoesNotBecomeAHealthAlert() {
        let sample = makeHealthSample(
            cpuUsage: 100,
            networkBytesPerSecond: 2_000_000_000,
            gpuUsage: 100,
            temperatureCelsius: 47,
            fanRPM: 3_128,
            fanLoadPercent: 52
        )

        XCTAssertEqual(sample.healthLevel(for: .cpu), .normal)
        XCTAssertEqual(sample.healthLevel(for: .network), .normal)
        XCTAssertEqual(sample.healthLevel(for: .gpu), .normal)
        XCTAssertEqual(sample.healthLevel(for: .temperature), .normal)
        XCTAssertEqual(sample.healthLevel(for: .fan), .normal)
    }

    func testTemperatureUsesSystemThermalStateAndSensorFallbacks() {
        XCTAssertEqual(
            makeHealthSample(temperatureCelsius: 85).healthLevel(for: .temperature),
            .warning
        )
        XCTAssertEqual(
            makeHealthSample(temperatureCelsius: 95).healthLevel(for: .temperature),
            .critical
        )
        XCTAssertEqual(
            makeHealthSample(
                temperatureCelsius: 47,
                batteryTemperatureCelsius: 40
            ).healthLevel(for: .temperature),
            .warning
        )
        XCTAssertEqual(
            makeHealthSample(
                temperatureCelsius: 47,
                batteryTemperatureCelsius: 45
            ).healthLevel(for: .temperature),
            .critical
        )
        XCTAssertEqual(
            makeHealthSample(temperatureCelsius: 47, thermalState: .fair)
                .healthLevel(for: .temperature),
            .warning
        )
        XCTAssertEqual(
            makeHealthSample(temperatureCelsius: 47, thermalState: .serious)
                .healthLevel(for: .temperature),
            .critical
        )
    }

    func testFanAlertUsesRelativeSpeedAndThermalContext() {
        XCTAssertEqual(
            makeHealthSample(fanRPM: 4_000, fanLoadPercent: 84).healthLevel(for: .fan),
            .normal
        )
        XCTAssertEqual(
            makeHealthSample(fanRPM: 4_100, fanLoadPercent: 85).healthLevel(for: .fan),
            .warning
        )
        XCTAssertEqual(
            makeHealthSample(fanRPM: 4_100, fanLoadPercent: 84.5).healthLevel(for: .fan),
            .warning,
            "The alert band must match the rounded whole-percent value displayed to the user"
        )
        XCTAssertEqual(
            makeHealthSample(
                temperatureCelsius: 96,
                fanRPM: 4_100,
                fanLoadPercent: 70
            ).healthLevel(for: .fan),
            .critical
        )
        XCTAssertEqual(
            makeHealthSample(fanRPM: 5_500, fanLoadPercent: nil).healthLevel(for: .fan),
            .warning
        )
    }

    func testPressureCapacityAndLowBatteryUseRiskSignals() {
        XCTAssertEqual(
            makeHealthSample(memoryPressureLevel: .warning).healthLevel(for: .memory),
            .warning
        )
        XCTAssertEqual(
            makeHealthSample(memoryPressureLevel: .critical).healthLevel(for: .memory),
            .critical
        )
        XCTAssertEqual(makeHealthSample(diskUsedPercent: 90).healthLevel(for: .disk), .warning)
        XCTAssertEqual(makeHealthSample(diskUsedPercent: 97).healthLevel(for: .disk), .critical)
        XCTAssertEqual(makeHealthSample(batteryLevel: 20).healthLevel(for: .battery), .warning)
        XCTAssertEqual(makeHealthSample(batteryLevel: 10).healthLevel(for: .battery), .critical)
        XCTAssertEqual(
            makeHealthSample(
                batteryLevel: 5,
                batteryStatus: "正在充电",
                batteryIsCharging: true
            ).healthLevel(for: .battery),
            .normal
        )
    }
}

private func makeHealthSample(
    cpuUsage: Double? = 30,
    memoryPressureLevel: MemoryPressureLevel = .normal,
    diskUsedPercent: Double? = 60,
    networkBytesPerSecond: Double? = 1_000,
    gpuUsage: Double? = 20,
    temperatureCelsius: Double? = 47,
    batteryTemperatureCelsius: Double? = 30,
    fanRPM: Double? = 3_000,
    fanLoadPercent: Double? = 50,
    batteryLevel: Double? = 80,
    batteryStatus: String? = "使用电池",
    batteryIsCharging: Bool? = false,
    thermalState: NativeThermalState = .nominal
) -> NativeMonitorSample {
    NativeMonitorSample(
        sampledAt: Date(),
        cpuUsage: cpuUsage,
        memoryUsedPercent: 50,
        memoryUsedBytes: 18_000_000_000,
        memoryTotalBytes: 36_000_000_000,
        memoryPressureLevel: memoryPressureLevel,
        diskUsedPercent: diskUsedPercent,
        diskFreeBytes: 150_000_000_000,
        networkDownloadBytesPerSecond: networkBytesPerSecond,
        networkUploadBytesPerSecond: networkBytesPerSecond,
        networkInterfaceName: "en0",
        gpuUsage: gpuUsage,
        gpuRendererUsage: gpuUsage,
        gpuTilerUsage: gpuUsage,
        temperatureCelsius: temperatureCelsius,
        temperatureSource: "测试 CPU 温度",
        batteryTemperatureCelsius: batteryTemperatureCelsius,
        batteryTemperatureSource: "测试电池温度",
        fanRPM: fanRPM,
        fanCount: 2,
        fanLoadPercent: fanLoadPercent,
        batteryLevel: batteryLevel,
        batteryStatus: batteryStatus,
        batteryIsCharging: batteryIsCharging,
        thermalState: thermalState
    )
}
