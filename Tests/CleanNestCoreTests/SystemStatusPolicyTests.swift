import XCTest
@testable import CleanNestCore

final class SystemStatusPolicyTests: XCTestCase {
    func testWidthBudgetAlwaysKeepsAbnormalAndPreferredMetrics() {
        let candidates = [
            MenuBarWidthCandidate(metric: .cpu, width: 50, healthLevel: .normal),
            MenuBarWidthCandidate(metric: .memory, width: 50, healthLevel: .critical),
            MenuBarWidthCandidate(metric: .temperature, width: 50, healthLevel: .warning),
            MenuBarWidthCandidate(metric: .network, width: 80, healthLevel: .normal),
            MenuBarWidthCandidate(metric: .disk, width: 50, healthLevel: .normal)
        ]

        let result = MenuBarWidthPolicy.select(
            candidates: candidates,
            budget: 120,
            preferredMetric: .cpu
        )

        XCTAssertEqual(result.visible, [.cpu, .memory, .temperature])
        XCTAssertEqual(result.collapsed, [.network, .disk])
        XCTAssertEqual(result.usedWidth, 150)
    }

    func testWidthBudgetKeepsAtLeastOneMetric() {
        let result = MenuBarWidthPolicy.select(
            candidates: [
                MenuBarWidthCandidate(metric: .network, width: 80, healthLevel: .normal),
                MenuBarWidthCandidate(metric: .disk, width: 50, healthLevel: .normal)
            ],
            budget: 0,
            preferredMetric: nil
        )
        XCTAssertEqual(result.visible, [.network])
        XCTAssertEqual(result.collapsed, [.disk])
    }

    func testAlertTimelineOpensPeaksRecoversAndBreaksAcrossSleepGap() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var timeline = SystemAlertTimeline(maximumEventCount: 20, maximumContinuousSampleGap: 60)

        XCTAssertTrue(timeline.record(
            sample: sample(at: start, temperature: 86),
            thresholds: .defaults
        ))
        XCTAssertTrue(timeline.record(
            sample: sample(at: start.addingTimeInterval(10), temperature: 87),
            thresholds: .defaults
        ))
        XCTAssertEqual(timeline.events.filter { $0.metric == .temperature }.count, 1)
        XCTAssertEqual(
            timeline.events.first { $0.metric == .temperature }?.peakValue,
            87
        )

        XCTAssertTrue(timeline.record(
            sample: sample(at: start.addingTimeInterval(20), temperature: 96),
            thresholds: .defaults
        ))
        XCTAssertEqual(
            timeline.events.first { $0.metric == .temperature }?.level,
            .critical
        )
        XCTAssertEqual(
            timeline.events.first { $0.metric == .temperature }?.peakValue,
            96
        )

        XCTAssertTrue(timeline.record(
            sample: sample(at: start.addingTimeInterval(30), temperature: 70),
            thresholds: .defaults
        ))
        XCTAssertNotNil(
            timeline.events.first { $0.metric == .temperature }?.endedAt
        )

        XCTAssertTrue(timeline.record(
            sample: sample(at: start.addingTimeInterval(40), temperature: 86),
            thresholds: .defaults
        ))
        XCTAssertTrue(timeline.record(
            sample: sample(at: start.addingTimeInterval(200), temperature: 87),
            thresholds: .defaults
        ))
        XCTAssertEqual(timeline.events.filter { $0.metric == .temperature }.count, 3)
        XCTAssertEqual(
            timeline.events.filter { $0.metric == .temperature && $0.isActive }.count,
            1
        )
    }

    func testAlertPersistenceClosesOpenEventAtLastObservation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("alerts.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        var timeline = SystemAlertTimeline()
        let date = Date(timeIntervalSince1970: 2_000)
        timeline.record(sample: sample(at: date, diskUsed: 98), thresholds: .defaults)
        try SystemAlertTimelinePersistence.save(timeline, to: url)
        var loaded = try SystemAlertTimelinePersistence.load(from: url)
        XCTAssertTrue(loaded.closeUnfinishedEventsFromPreviousRun())
        XCTAssertEqual(loaded.events.first?.endedAt, date)
    }

    func testMemoryProcessesAreGroupedByOwningApplication() {
        let processes = [
            process(pid: 10, name: "Browser", app: "Browser", footprint: 400),
            process(pid: 11, name: "Browser Helper", app: "Browser", footprint: 200),
            process(pid: 12, name: "worker", app: nil, footprint: 300)
        ]
        let groups = MemoryApplicationGrouper.groups(processes)
        XCTAssertEqual(groups.map(\.displayName), ["Browser", "worker"])
        XCTAssertEqual(groups[0].processes.count, 2)
        XCTAssertEqual(groups[0].physicalFootprintBytes, 600)
    }

    func testAcceleratedFortyEightHourAlertSoakRemainsBounded() {
        let start = Date(timeIntervalSince1970: 10_000)
        var timeline = SystemAlertTimeline(maximumEventCount: 200)
        let sampleCount = 48 * 60 * 30 // one sample every two seconds

        for offset in 0..<sampleCount {
            let cycle = offset % (6 * 60 * 30)
            let temperature = cycle < 5 * 30 ? 86.0 : 70.0
            timeline.record(
                sample: sample(
                    at: start.addingTimeInterval(Double(offset * 2)),
                    temperature: temperature
                ),
                thresholds: .defaults
            )
        }

        XCTAssertLessThanOrEqual(timeline.events.count, 200)
        XCTAssertTrue(timeline.events.allSatisfy { $0.duration(at: start.addingTimeInterval(48 * 3_600)) >= 0 })
        XCTAssertLessThanOrEqual(timeline.events.filter(\.isActive).count, 2)
    }
}

private func sample(
    at date: Date,
    temperature: Double = 70,
    diskUsed: Double = 60
) -> NativeMonitorSample {
    NativeMonitorSample(
        sampledAt: date,
        cpuUsage: 10,
        memoryUsedPercent: 40,
        memoryUsedBytes: 4_000,
        memoryTotalBytes: 10_000,
        memoryPressureLevel: .normal,
        diskUsedPercent: diskUsed,
        diskFreeBytes: 4_000,
        networkDownloadBytesPerSecond: 10,
        networkUploadBytesPerSecond: 5,
        networkInterfaceName: "en0",
        gpuUsage: 10,
        gpuRendererUsage: 10,
        gpuTilerUsage: 10,
        temperatureCelsius: temperature,
        temperatureSource: "test",
        batteryTemperatureCelsius: 30,
        batteryTemperatureSource: "test",
        fanRPM: 2_000,
        fanCount: 1,
        fanLoadPercent: 30,
        batteryLevel: 80,
        batteryStatus: "使用电池",
        batteryIsCharging: false,
        thermalState: .nominal
    )
}

private func process(
    pid: Int32,
    name: String,
    app: String?,
    footprint: Int64
) -> MemoryProcessSnapshot {
    MemoryProcessSnapshot(
        pid: pid,
        parentPID: 1,
        name: name,
        applicationName: app,
        executablePath: nil,
        physicalFootprintBytes: footprint,
        residentBytes: footprint,
        ownerUserID: 501,
        startSeconds: 1,
        startMicroseconds: 0,
        purpose: "test",
        terminationImpact: "test",
        protectionReason: nil
    )
}
