import Foundation
import XCTest
import CleanNestCore

final class MetricsStoreTests: XCTestCase {
    func testRoundTripRangePruneAndClear() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("metrics.sqlite3")
        let store = MetricsStore(databaseURL: url)
        try await store.prepare()

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = sample(at: now.addingTimeInterval(-40 * 86_400), cpu: 10)
        let recent = sample(at: now.addingTimeInterval(-30), cpu: 44)
        try await store.append(old)
        try await store.append(recent)

        let initialCount = try await store.count()
        let latest = try await store.latest()
        let recentSamples = try await store.samples(since: now.addingTimeInterval(-60))
        let pruned = try await store.prune(retainingDays: 30, now: now)
        let retainedCount = try await store.count()
        XCTAssertEqual(initialCount, 2)
        XCTAssertEqual(latest, recent)
        XCTAssertEqual(recentSamples, [recent])
        XCTAssertEqual(pruned, 1)
        XCTAssertEqual(retainedCount, 1)

        try await store.clear()
        let clearedCount = try await store.count()
        XCTAssertEqual(clearedCount, 0)
    }

    func testReadOnlyStoreCannotCreateOrWrite() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("missing.sqlite3")
        let store = MetricsStore(databaseURL: url, access: .readOnly)

        do {
            _ = try await store.latest()
            XCTFail("Read-only access must not create a missing database")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }

        do {
            try await store.append(sample(at: Date(), cpu: 1))
            XCTFail("Read-only access must reject writes")
        } catch MetricsStoreError.readOnly {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    /// Regression: a `DESC LIMIT n` query used to keep only the newest `n`
    /// samples, so "24 小时 / 7 天 / 30 天" charts silently showed only the
    /// last few hours. With 200 samples in one hour (budget 180), the oldest
    /// point must still be present near the start of the window.
    func testHistoryRangeCoversEntireWindowInsteadOfTruncating() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("metrics.sqlite3")
        let store = MetricsStore(databaseURL: url)
        try await store.prepare()

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for index in 0..<200 {
            let age = TimeInterval(199 - index) * 18
            try await store.append(sample(at: now.addingTimeInterval(-age), cpu: Double(index)))
        }

        let points = try await store.samples(range: .hour, now: now)
        XCTAssertLessThanOrEqual(points.count, MetricHistoryRange.hour.maximumSamples)
        XCTAssertGreaterThan(points.count, 100)
        XCTAssertLessThan(
            points.first?.sampledAt.timeIntervalSince1970 ?? .infinity,
            now.addingTimeInterval(-3_500).timeIntervalSince1970,
            "最旧的数据点不应被 LIMIT 截断"
        )
        XCTAssertEqual(
            points.last?.sampledAt.timeIntervalSince1970 ?? 0,
            now.timeIntervalSince1970,
            accuracy: 0.001
        )
        // Bucket picking must keep original samples, not averaged values.
        XCTAssertTrue(points.allSatisfy { point in
            guard let cpu = point.cpuUsage else { return false }
            return cpu == cpu.rounded()
        })
    }

    func testHistoryRangeKeepsSparseSamplesUnchanged() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("metrics.sqlite3")
        let store = MetricsStore(databaseURL: url)
        try await store.prepare()

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let expected = [
            sample(at: now.addingTimeInterval(-3_500), cpu: 1),
            sample(at: now.addingTimeInterval(-1_800), cpu: 2),
            sample(at: now, cpu: 3)
        ]
        for point in expected { try await store.append(point) }

        let points = try await store.samples(range: .hour, now: now)
        XCTAssertEqual(points, expected)
    }

    private func sample(at date: Date, cpu: Double) -> MetricSample {
        MetricSample(
            sampledAt: date,
            healthScore: 90,
            cpuUsage: cpu,
            memoryUsedPercent: 50,
            memoryPressureLevel: .normal,
            memoryUsedBytes: 10,
            memoryAvailableBytes: 10,
            memoryCompressedBytes: 1,
            memorySwapUsedBytes: 0,
            diskUsedPercent: 60,
            diskFreeBytes: 100,
            batteryLevel: 80,
            temperatureCelsius: 42,
            processCount: 100
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestMetricsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
