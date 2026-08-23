import Foundation
import XCTest
import CleanNestCore

final class NativeDiskAnalyzerTests: XCTestCase {
    func testCancellationPropagatesIntoDetachedScanner() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestCancellationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<80 {
            let directory = root.appendingPathComponent("directory-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for fileIndex in 0..<20 {
                try Data(repeating: UInt8(fileIndex), count: 32)
                    .write(to: directory.appendingPathComponent("file-\(fileIndex)"))
            }
        }

        let task = Task {
            try await NativeDiskAnalyzer().analyze(root: root, progress: nil)
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled disk analysis must not return a completed report")
        } catch is CancellationError {
            // Expected.
        }
    }
}
