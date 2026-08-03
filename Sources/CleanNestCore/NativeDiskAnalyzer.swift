import Foundation

public struct NativeDiskAnalyzer: Sendable {
    public init() {}

    public func analyze(root: URL) async -> DiskReport {
        await Task.detached(priority: .userInitiated) {
            let children = FileTree.directChildren(of: root)
            let entries = children.map { child -> DiskEntry in
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey])
                return DiskEntry(
                    name: child.lastPathComponent,
                    url: child,
                    bytes: FileTree.allocatedSize(of: child, skipPackages: false),
                    isDirectory: values?.isDirectory ?? false
                )
            }
            .sorted { $0.bytes > $1.bytes }

            return DiskReport(
                root: root,
                entries: entries,
                largeFiles: entries.filter { !$0.isDirectory }.prefix(20).map { $0 },
                totalBytes: entries.reduce(0) { $0 + $1.bytes },
                totalFiles: entries.filter { !$0.isDirectory }.count
            )
        }.value
    }
}
