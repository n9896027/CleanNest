import Foundation

public struct FileTreeMetrics: Sendable {
    public let allocatedBytes: Int64
    public let latestModificationDate: Date?

    public init(allocatedBytes: Int64, latestModificationDate: Date?) {
        self.allocatedBytes = allocatedBytes
        self.latestModificationDate = latestModificationDate
    }
}

public enum FileTree {
    public static func allocatedSize(of root: URL, skipPackages: Bool = false) -> Int64 {
        metrics(of: root, skipPackages: skipPackages).allocatedBytes
    }

    public static func metrics(
        of root: URL,
        skipPackages: Bool = false,
        includeLatestModificationDate: Bool = false
    ) -> FileTreeMetrics {
        var keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        if includeLatestModificationDate { keys.insert(.contentModificationDateKey) }

        if let values = try? root.resourceValues(forKeys: keys), values.isRegularFile == true {
            return FileTreeMetrics(
                allocatedBytes: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                latestModificationDate: includeLatestModificationDate ? values.contentModificationDate : nil
            )
        }

        var options: FileManager.DirectoryEnumerationOptions = [.skipsSubdirectoryDescendants]
        options = []
        if skipPackages { options.insert(.skipsPackageDescendants) }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: options,
            errorHandler: { _, _ in true }
        ) else {
            return FileTreeMetrics(allocatedBytes: 0, latestModificationDate: nil)
        }

        var total: Int64 = 0
        var latestModificationDate: Date?
        var visited = 0
        let maximumEntries = 500_000

        for case let url as URL in enumerator {
            visited += 1
            if visited > maximumEntries { break }

            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isRegularFile == true {
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                if includeLatestModificationDate,
                   let modified = values.contentModificationDate {
                    if let latest = latestModificationDate {
                        latestModificationDate = max(latest, modified)
                    } else {
                        latestModificationDate = modified
                    }
                }
            }
        }
        return FileTreeMetrics(
            allocatedBytes: total,
            latestModificationDate: latestModificationDate
        )
    }

    public static func directChildren(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}
