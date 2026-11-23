import XCTest
import CleanNestCore

final class FeatureNavigationTests: XCTestCase {
    func testEveryExistingPageRemainsDiscoverable() {
        let pages = Set(FeatureDirectory.destinations.map(\.page))
        XCTAssertEqual(pages, Set(["总览", "清理空间", "应用卸载", "磁盘浏览", "系统状态", "系统维护", "Agent 工作区", "本地模型", "清理习惯", "活动记录", "设置"]))
        XCTAssertEqual(Set(FeatureDirectory.destinations.map(\.id)).count, FeatureDirectory.destinations.count)
    }

    func testSearchAcceptsHumanAndTechnicalKeywords() {
        for (query, expected) in [("重复文件", "cleanup"), ("Codex", "agents"), ("OMLX", "models"), ("温度", "status"), ("权限", "permissions"), ("更新", "about")] {
            XCTAssertTrue(FeatureDirectory.search(query).contains { $0.id == expected }, query)
        }
        XCTAssertEqual(FeatureDirectory.search(" \n"), FeatureDirectory.destinations)
        XCTAssertTrue(FeatureDirectory.search("xyz-no-feature").isEmpty)
        XCTAssertTrue(FeatureDirectory.search("模型 地址").contains { $0.id == "ai" })
    }

    func testSettingsResultsNavigateToKnownSectionsOnly() {
        let settings = FeatureDirectory.destinations.filter { $0.settingsSection != nil }
        XCTAssertTrue(settings.allSatisfy { $0.page == "设置" })
        XCTAssertEqual(Set(settings.compactMap(\.settingsSection)), Set(CleanNestSettingsSection.allCases.filter { $0 != .general }))
    }

    func testDirectFeatureNamesRankAboveIncidentalDescriptionMatches() {
        XCTAssertEqual(FeatureDirectory.search("模型").first?.id, "models")
        XCTAssertEqual(FeatureDirectory.search("清理空间").first?.id, "cleanup")
        XCTAssertEqual(FeatureDirectory.search("设置").first?.id, "settings")
    }

    func testBackForwardAndBranchDoNotDuplicateOrRetainStaleForwardHistory() {
        var history = PageNavigationHistory(initial: "总览")
        XCTAssertNil(history.back())
        history.visit("清理空间")
        history.visit("清理空间")
        history.visit("设置")
        XCTAssertEqual(history.pages.count, 3)
        XCTAssertEqual(history.back(), "清理空间")
        history.visit("清理空间") // Observing the navigation must not duplicate it.
        XCTAssertEqual(history.forward(), "设置")
        _ = history.back()
        history.visit("本地模型")
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.pages, ["总览", "清理空间", "本地模型"])
    }

    func testHistoryHasBoundedRetention() {
        var history = PageNavigationHistory(initial: "initial")
        for index in 0..<500 { history.visit(String(index)) }
        XCTAssertEqual(history.pages.count, 40)
        XCTAssertEqual(history.current, "499")
        for _ in 0..<100 { _ = history.back() }
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.index, 0)
    }
}
