import XCTest
@testable import CleanNestCore

final class ActivityStatisticsTests: XCTestCase {
    func testStatisticsCountOnlyProductiveCleanupAndUninstallResults() {
        let entries = [
            ActivityEntry(
                title: "清理空间",
                detail: "done",
                outcome: .success,
                affectedItems: 2,
                bytes: 1_000,
                category: .cleanup
            ),
            ActivityEntry(
                title: "卸载 Example",
                detail: "partial",
                outcome: .partial,
                affectedItems: 3,
                bytes: 900,
                category: .applicationUninstall
            ),
            ActivityEntry(
                title: "清理空间",
                detail: "failed",
                outcome: .failed,
                affectedItems: 5,
                bytes: 5_000,
                category: .cleanup
            ),
            ActivityEntry(
                title: "结束进程",
                detail: "done",
                outcome: .success,
                affectedItems: 1,
                bytes: 2_000,
                category: .other
            )
        ]

        let statistics = ActivityStatistics(entries: entries)

        XCTAssertEqual(statistics.processedBytes, 1_900)
        XCTAssertEqual(statistics.cleanedItems, 2)
        XCTAssertEqual(statistics.uninstalledApplications, 1)
        XCTAssertEqual(statistics.productiveOperations, 3)
        XCTAssertEqual(statistics.recordCount, 4)
    }

    func testLegacyRecordsWithoutCategoryStillContributeToStatistics() throws {
        let legacyJSON = #"""
        {
          "id": "0B37C652-A7A4-4B50-9BA5-82ED990148E5",
          "date": 0,
          "title": "清理空间",
          "detail": "legacy",
          "outcome": "完成",
          "affectedItems": 4,
          "bytes": 2048
        }
        """#.data(using: .utf8)!

        let entry = try JSONDecoder().decode(ActivityEntry.self, from: legacyJSON)
        let statistics = ActivityStatistics(entries: [entry])

        XCTAssertNil(entry.category)
        XCTAssertNil(entry.cleanupResult)
        XCTAssertEqual(statistics.processedBytes, 2_048)
        XCTAssertEqual(statistics.cleanedItems, 4)
    }

    func testCleanupResultKeepsCandidateTrashAndAPFSFactsSeparateAcrossRoundTrip() throws {
        let entry = ActivityEntry(
            title: "清理空间",
            detail: "partial",
            outcome: .partial,
            affectedItems: 2,
            bytes: 700,
            category: .cleanup,
            cleanupResult: CleanupActivityResult(
                candidateBytes: 1_000,
                trashedBytes: 700,
                apfsFreeBytesDelta: -128
            )
        )

        let decoded = try JSONDecoder().decode(
            ActivityEntry.self,
            from: JSONEncoder().encode(entry)
        )

        XCTAssertEqual(decoded, entry)
        XCTAssertEqual(decoded.cleanupResult?.candidateBytes, 1_000)
        XCTAssertEqual(decoded.cleanupResult?.trashedBytes, 700)
        XCTAssertEqual(decoded.cleanupResult?.apfsFreeBytesDelta, -128)
        XCTAssertEqual(ActivityStatistics(entries: [decoded]).processedBytes, 700)
    }

    func testCleanupResultClampsInvalidPersistedVolumes() throws {
        let data = #"{"candidateBytes":-1,"trashedBytes":-2,"apfsFreeBytesDelta":-9223372036854775808}"#
            .data(using: .utf8)!
        let result = try JSONDecoder().decode(CleanupActivityResult.self, from: data)

        XCTAssertEqual(result.candidateBytes, 0)
        XCTAssertEqual(result.trashedBytes, 0)
        XCTAssertEqual(result.apfsFreeBytesDelta, -Int64.max)
    }

    func testLifetimeTotalsSurviveDetailListResetAndRoundTrip() throws {
        let entries = [
            ActivityEntry(
                date: Date(timeIntervalSince1970: 100),
                title: "清理空间",
                detail: "done",
                outcome: .success,
                affectedItems: 8,
                bytes: 4_096,
                category: .cleanup
            ),
            ActivityEntry(
                date: Date(timeIntervalSince1970: 200),
                title: "卸载 Example",
                detail: "done",
                outcome: .partial,
                affectedItems: 2,
                bytes: 2_048,
                category: .applicationUninstall
            )
        ]
        let totals = ActivityLifetimeTotals(entries: entries)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("totals.json")

        try ActivityLifetimeTotalsPersistence.save(totals, to: url)
        let loaded = try XCTUnwrap(ActivityLifetimeTotalsPersistence.load(from: url))

        XCTAssertEqual(loaded.processedBytes, 6_144)
        XCTAssertEqual(loaded.cleanedItems, 8)
        XCTAssertEqual(loaded.uninstalledApplications, 1)
        XCTAssertEqual(loaded.productiveOperations, 2)

        var detailList = entries
        detailList.removeAll()
        XCTAssertTrue(detailList.isEmpty)
        XCTAssertEqual(loaded.processedBytes, 6_144)
    }

    func testActivityFilterCombinesSearchCategoryOutcomeAndTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let entries = [
            ActivityEntry(
                date: now.addingTimeInterval(-60),
                title: "清理 Codex 缓存",
                detail: "已移到废纸篓",
                outcome: .success,
                category: .cleanup
            ),
            ActivityEntry(
                date: now.addingTimeInterval(-120),
                title: "卸载 Codex",
                detail: "未完成",
                outcome: .failed,
                category: .applicationUninstall
            ),
            ActivityEntry(
                date: now.addingTimeInterval(-8 * 24 * 60 * 60),
                title: "清理 Codex 缓存",
                detail: "旧记录",
                outcome: .success,
                category: .cleanup
            )
        ]
        let filter = ActivityFilter(
            query: "codex",
            category: .cleanup,
            outcome: .success,
            timeWindow: .week
        )

        XCTAssertEqual(filter.apply(to: entries, relativeTo: now).map(\.detail), ["已移到废纸篓"])
    }
}
