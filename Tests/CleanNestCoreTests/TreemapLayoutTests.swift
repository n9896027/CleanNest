import CoreGraphics
import XCTest
import CleanNestCore

final class TreemapLayoutTests: XCTestCase {
    func testLayoutIsDeterministicBoundedAndNonOverlapping() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let items = [
            TreemapItem(id: "a", weight: 50),
            TreemapItem(id: "b", weight: 30),
            TreemapItem(id: "c", weight: 20),
            TreemapItem(id: "ignored-zero", weight: 0),
            TreemapItem(id: "ignored-nan", weight: .nan)
        ]
        let first = TreemapLayout.layout(items: items, in: bounds)
        let second = TreemapLayout.layout(items: Array(items.reversed()), in: bounds)

        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first.map(\.id)), ["a", "b", "c"])
        XCTAssertEqual(first.reduce(0) { $0 + $1.rect.width * $1.rect.height }, bounds.width * bounds.height, accuracy: 0.01)
        for placement in first {
            XCTAssertTrue(bounds.contains(placement.rect))
            XCTAssertGreaterThan(placement.rect.width, 0)
            XCTAssertGreaterThan(placement.rect.height, 0)
        }
        for leftIndex in first.indices {
            for rightIndex in first.indices where rightIndex > leftIndex {
                let intersection = first[leftIndex].rect.intersection(first[rightIndex].rect)
                XCTAssertTrue(intersection.isNull || intersection.width == 0 || intersection.height == 0)
            }
        }
    }

    func testInvalidBoundsReturnNoPlacements() {
        let items = [TreemapItem(id: "a", weight: 1)]
        XCTAssertTrue(TreemapLayout.layout(items: items, in: .zero).isEmpty)
        XCTAssertTrue(TreemapLayout.layout(items: items, in: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)).isEmpty)
    }
}
