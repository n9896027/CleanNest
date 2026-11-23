import XCTest
@testable import CleanNestCore

final class NativeSystemSnapshotBuilderTests: XCTestCase {
    func testNativeSampleMapsWithoutExternalEngineOrInventedHealth() {
        let snapshot = NativeSystemSnapshotBuilder.makeSnapshot(
            monitor: sample(),
            memoryProbe: SystemMemoryProbeSnapshot(compressedBytes: 2_000, pressureLevel: .normal),
            batteryProbe: nil,
            processCount: 321,
            host: "Test-Mac",
            logicalCPUCount: 8,
            uptimeSeconds: 90_000
        )

        XCTAssertEqual(snapshot.host, "Test-Mac")
        XCTAssertNil(snapshot.healthScore)
        XCTAssertEqual(snapshot.cpuUsage, 42)
        XCTAssertEqual(snapshot.logicalCPUCount, 8)
        XCTAssertEqual(snapshot.memoryAvailableBytes, 6_000)
        XCTAssertEqual(snapshot.memoryCompressedBytes, 2_000)
        XCTAssertEqual(snapshot.memoryPressureLevel, .normal)
        XCTAssertEqual(snapshot.processCount, 321)
        XCTAssertEqual(snapshot.temperatureCelsius, 68)
        XCTAssertEqual(snapshot.temperatureSource, "CPU 温度")
        XCTAssertEqual(snapshot.uptime, "1 天 1 小时")
    }

    func testPowerProbeIsOnlyFallbackForMissingNativeBattery() {
        let battery = BatteryProbeResult(
            availability: .present,
            level: 73,
            status: "正在充电",
            detail: "test"
        )
        let fallback = NativeSystemSnapshotBuilder.makeSnapshot(
            monitor: sample(nativeBatteryLevel: nil, nativeBatteryStatus: nil),
            memoryProbe: nil,
            batteryProbe: battery,
            processCount: nil,
            host: "Test-Mac",
            logicalCPUCount: 8,
            uptimeSeconds: nil
        )
        XCTAssertEqual(fallback.batteryLevel, 73)
        XCTAssertEqual(fallback.batteryStatus, "正在充电")

        let native = NativeSystemSnapshotBuilder.makeSnapshot(
            monitor: sample(),
            memoryProbe: nil,
            batteryProbe: battery,
            processCount: nil,
            host: "Test-Mac",
            logicalCPUCount: 8,
            uptimeSeconds: nil
        )
        XCTAssertEqual(native.batteryLevel, 80)
        XCTAssertEqual(native.batteryStatus, "已连接电源")
    }

    func testUnavailableMeasurementsStayEmptyAndAvailableMemoryIsClamped() {
        let snapshot = NativeSystemSnapshotBuilder.makeSnapshot(
            monitor: sample(
                usedBytes: 12_000,
                totalBytes: 10_000,
                nativeBatteryLevel: nil,
                nativeBatteryStatus: nil
            ),
            memoryProbe: nil,
            batteryProbe: BatteryProbeResult(
                availability: .noInternalBattery,
                level: nil,
                status: "没有内置电池",
                detail: "test"
            ),
            processCount: -1,
            host: "Test-Mac",
            logicalCPUCount: 0,
            uptimeSeconds: nil
        )

        XCTAssertEqual(snapshot.memoryAvailableBytes, 0)
        XCTAssertNil(snapshot.memoryCachedBytes)
        XCTAssertNil(snapshot.memorySwapUsedBytes)
        XCTAssertNil(snapshot.memorySwapTotalBytes)
        XCTAssertNil(snapshot.batteryLevel)
        XCTAssertNil(snapshot.batteryStatus)
        XCTAssertNil(snapshot.logicalCPUCount)
        XCTAssertNil(snapshot.processCount)
    }

    func testUptimeFormattingRejectsInvalidValues() {
        XCTAssertEqual(NativeSystemSnapshotBuilder.formatUptime(0), "0 分钟")
        XCTAssertEqual(NativeSystemSnapshotBuilder.formatUptime(3_660), "1 小时 1 分钟")
        XCTAssertEqual(NativeSystemSnapshotBuilder.formatUptime(86_400), "1 天")
        XCTAssertNil(NativeSystemSnapshotBuilder.formatUptime(-1))
        XCTAssertNil(NativeSystemSnapshotBuilder.formatUptime(.nan))
        XCTAssertNil(NativeSystemSnapshotBuilder.formatUptime(.infinity))
    }

    private func sample(
        usedBytes: Int64 = 4_000,
        totalBytes: Int64 = 10_000,
        nativeBatteryLevel: Double? = 80,
        nativeBatteryStatus: String? = "已连接电源"
    ) -> NativeMonitorSample {
        NativeMonitorSample(
            sampledAt: Date(timeIntervalSince1970: 1_700_000_000),
            cpuUsage: 42,
            memoryUsedPercent: 40,
            memoryUsedBytes: usedBytes,
            memoryTotalBytes: totalBytes,
            memoryPressureLevel: .unknown,
            diskUsedPercent: 60,
            diskFreeBytes: 4_000,
            networkDownloadBytesPerSecond: nil,
            networkUploadBytesPerSecond: nil,
            networkInterfaceName: nil,
            gpuUsage: nil,
            gpuRendererUsage: nil,
            gpuTilerUsage: nil,
            temperatureCelsius: 68,
            temperatureSource: "CPU 温度",
            batteryTemperatureCelsius: 31,
            batteryTemperatureSource: "电池温度",
            fanRPM: nil,
            fanCount: nil,
            batteryLevel: nativeBatteryLevel,
            batteryStatus: nativeBatteryStatus
        )
    }
}
