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
        XCTAssertEqual(statistics.processedBytes, 2_048)
        XCTAssertEqual(statistics.cleanedItems, 4)
    }
}
