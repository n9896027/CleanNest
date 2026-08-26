import Darwin
import Foundation
import XCTest
@testable import CleanNestCore

final class FileTreeTests: XCTestCase {
    func testBatchedMetricsAndDirectChildrenPreserveResults() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestFileTreeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        var expectedAllocatedBytes: Int64 = 0
        for index in 0..<600 {
            let parent = index.isMultiple(of: 2) ? root : nested
            let file = parent.appendingPathComponent("item-\(index).bin")
            try Data(repeating: UInt8(index % 251), count: 17).write(to: file)
            var fileStat = stat()
            XCTAssertEqual(file.path.withCString { lstat($0, &fileStat) }, 0)
            expectedAllocatedBytes += Int64(fileStat.st_blocks) * 512
        }

        let metrics = FileTree.metrics(
            of: root,
            includeLatestModificationDate: true
        )
        let children = FileTree.directChildren(of: root)

        XCTAssertEqual(metrics.allocatedBytes, expectedAllocatedBytes)
        XCTAssertNotNil(metrics.latestModificationDate)
        XCTAssertEqual(children.count, 301)
        XCTAssertTrue(children.contains { $0.lastPathComponent == "nested" })
        XCTAssertFalse(children.contains { $0.lastPathComponent == "item-1.bin" })
    }
}
