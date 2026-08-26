import Darwin
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
        let rootPath = root.standardizedFileURL.path
        var rootStat = stat()
        let rootStatus = rootPath.withCString { lstat($0, &rootStat) }
        guard rootStatus == 0 else {
            return FileTreeMetrics(allocatedBytes: 0, latestModificationDate: nil)
        }
        if (rootStat.st_mode & S_IFMT) == S_IFREG {
            return FileTreeMetrics(
                allocatedBytes: max(0, Int64(rootStat.st_blocks) * 512),
                latestModificationDate: includeLatestModificationDate
                    ? modificationDate(from: rootStat)
                    : nil
            )
        }
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            return FileTreeMetrics(allocatedBytes: 0, latestModificationDate: nil)
        }

        guard let rootCString = strdup(rootPath) else {
            return FileTreeMetrics(allocatedBytes: 0, latestModificationDate: nil)
        }
        defer { free(rootCString) }

        let paths = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        paths.initialize(repeating: nil, count: 2)
        paths[0] = rootCString
        defer { paths.deinitialize(count: 2); paths.deallocate() }

        guard let stream = fts_open(
            UnsafePointer(paths),
            FTS_PHYSICAL | FTS_NOCHDIR,
            nil
        ) else {
            return FileTreeMetrics(allocatedBytes: 0, latestModificationDate: nil)
        }
        defer { fts_close(stream) }

        var total: Int64 = 0
        var latestModificationDate: Date?
        var visited = 0
        let maximumEntries = 500_000

        // fts performs a physical POSIX walk and never constructs one NSURL +
        // resource-value cache per entry. That keeps a large cache tree from
        // inflating the main process allocator by several gigabytes.
        while visited < maximumEntries,
              !Task.isCancelled,
              let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            if entry.pointee.fts_level == FTS_ROOTLEVEL { continue }
            visited += 1

            if skipPackages,
               info == FTS_D,
               isPackagePath(entry.pointee.fts_path) {
                _ = fts_set(stream, entry, FTS_SKIP)
                continue
            }
            guard info == FTS_F,
                  let statPointer = entry.pointee.fts_statp else { continue }
            let fileStat = statPointer.pointee
            total += max(0, Int64(fileStat.st_blocks) * 512)
            if includeLatestModificationDate {
                let modified = modificationDate(from: fileStat)
                latestModificationDate = latestModificationDate.map {
                    max($0, modified)
                } ?? modified
            }
        }
        return FileTreeMetrics(
            allocatedBytes: total,
            latestModificationDate: latestModificationDate
        )
    }

    private static func modificationDate(from fileStat: stat) -> Date {
        Date(
            timeIntervalSince1970: TimeInterval(fileStat.st_mtimespec.tv_sec)
                + TimeInterval(fileStat.st_mtimespec.tv_nsec) / 1_000_000_000
        )
    }

    private static func isPackagePath(_ path: UnsafeMutablePointer<CChar>?) -> Bool {
        guard let path else { return false }
        let value = String(cString: path).lowercased()
        let packageExtensions = [
            ".app", ".bundle", ".framework", ".plugin", ".kext", ".pkg",
            ".xcodeproj", ".xcworkspace", ".playground", ".photoslibrary",
            ".imovielibrary", ".musiclibrary", ".logicx", ".garageband",
            ".prefpane", ".mdimporter", ".qlgenerator", ".saver", ".workflow"
        ]
        return packageExtensions.contains { value.hasSuffix($0) }
    }

    public static func directChildren(of root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var children: [URL] = []
        var exhausted = false
        while !exhausted, !Task.isCancelled {
            autoreleasepool {
                for _ in 0..<256 {
                    guard !Task.isCancelled,
                          let url = enumerator.nextObject() as? URL else {
                        exhausted = true
                        break
                    }
                    // Recreate the URL from its path so prefetched resource
                    // values from DirectoryEnumerator cannot escape this pool.
                    children.append(
                        URL(fileURLWithPath: (url.path as NSString).standardizingPath)
                    )
                }
            }
        }
        return children
    }
}
