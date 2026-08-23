import Foundation

public struct DiskScanProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentName: String

    public init(completed: Int, total: Int, currentName: String) {
        self.completed = completed
        self.total = total
        self.currentName = currentName
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public struct NativeDiskAnalyzer: Sendable {
    public init() {}

    public func analyze(root: URL) async -> DiskReport {
        do {
            return try await analyze(root: root, progress: nil)
        } catch {
            return DiskReport(root: root, entries: [], largeFiles: [], totalBytes: 0, totalFiles: 0)
        }
    }

    public func analyze(
        root: URL,
        progress: (@Sendable (DiskScanProgress) -> Void)?
    ) async throws -> DiskReport {
        let worker = Task.detached(priority: .userInitiated) {
            let children = FileTree.directChildren(of: root)
            var entries: [DiskEntry] = []
            entries.reserveCapacity(children.count)
            for (index, child) in children.enumerated() {
                try Task.checkCancellation()
                progress?(
                    DiskScanProgress(
                        completed: index,
                        total: children.count,
                        currentName: String(child.lastPathComponent.prefix(120))
                    )
                )
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                let entry = DiskEntry(
                    name: child.lastPathComponent,
                    url: child,
                    bytes: FileTree.allocatedSize(of: child, skipPackages: false),
                    isDirectory: values?.isDirectory ?? false
                )
                try Task.checkCancellation()
                entries.append(entry)
            }
            entries.sort { $0.bytes > $1.bytes }
            progress?(DiskScanProgress(completed: children.count, total: children.count, currentName: ""))

            return DiskReport(
                root: root,
                entries: entries,
                largeFiles: entries.filter { !$0.isDirectory }.prefix(20).map { $0 },
                totalBytes: entries.reduce(0) { $0 + $1.bytes },
                totalFiles: entries.filter { !$0.isDirectory }.count
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
