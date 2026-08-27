import Darwin
import Foundation

public struct FileTreeTraversalEvidence: Codable, Equatable, Hashable, Sendable {
    public let rootWasReadable: Bool
    public let visitedEntryCount: Int
    public let regularFileCount: Int
    public let unreadableEntryCount: Int
    public let crossVolumeEntryCount: Int
    public let symbolicLinkCount: Int
    public let reachedEntryLimit: Bool
    public let entryLimit: Int?

    public init(
        rootWasReadable: Bool,
        visitedEntryCount: Int,
        regularFileCount: Int,
        unreadableEntryCount: Int,
        crossVolumeEntryCount: Int,
        symbolicLinkCount: Int,
        reachedEntryLimit: Bool,
        entryLimit: Int?
    ) {
        self.rootWasReadable = rootWasReadable
        self.visitedEntryCount = max(0, visitedEntryCount)
        self.regularFileCount = max(0, regularFileCount)
        self.unreadableEntryCount = max(0, unreadableEntryCount)
        self.crossVolumeEntryCount = max(0, crossVolumeEntryCount)
        self.symbolicLinkCount = max(0, symbolicLinkCount)
        self.reachedEntryLimit = reachedEntryLimit
        self.entryLimit = entryLimit.map { max(1, $0) }
    }

    public var isCompleteWithinFileSystem: Bool {
        rootWasReadable && !reachedEntryLimit && unreadableEntryCount == 0
    }

    public static func unreadable(entryLimit: Int?) -> Self {
        Self(
            rootWasReadable: false,
            visitedEntryCount: 0,
            regularFileCount: 0,
            unreadableEntryCount: 1,
            crossVolumeEntryCount: 0,
            symbolicLinkCount: 0,
            reachedEntryLimit: false,
            entryLimit: entryLimit
        )
    }
}

public struct FileTreeMetrics: Sendable {
    public let allocatedBytes: Int64
    public let latestModificationDate: Date?
    public let traversal: FileTreeTraversalEvidence

    public init(
        allocatedBytes: Int64,
        latestModificationDate: Date?,
        traversal: FileTreeTraversalEvidence = FileTreeTraversalEvidence(
            rootWasReadable: true,
            visitedEntryCount: 0,
            regularFileCount: 0,
            unreadableEntryCount: 0,
            crossVolumeEntryCount: 0,
            symbolicLinkCount: 0,
            reachedEntryLimit: false,
            entryLimit: nil
        )
    ) {
        self.allocatedBytes = allocatedBytes
        self.latestModificationDate = latestModificationDate
        self.traversal = traversal
    }
}

public struct FileTreeChildrenResult: Sendable {
    public let children: [URL]
    public let readErrorCount: Int

    public init(children: [URL], readErrorCount: Int) {
        self.children = children
        self.readErrorCount = max(0, readErrorCount)
    }
}

public enum FileTree {
    public static func allocatedSize(of root: URL, skipPackages: Bool = false) -> Int64 {
        metrics(of: root, skipPackages: skipPackages).allocatedBytes
    }

    public static func metrics(
        of root: URL,
        skipPackages: Bool = false,
        includeLatestModificationDate: Bool = false,
        maximumEntries: Int? = 500_000,
        stayOnFileSystem: Bool = false
    ) -> FileTreeMetrics {
        let normalizedMaximumEntries = maximumEntries.map { max(1, $0) }
        let rootPath = root.standardizedFileURL.path
        var rootStat = stat()
        let rootStatus = rootPath.withCString { lstat($0, &rootStat) }
        guard rootStatus == 0 else {
            return FileTreeMetrics(
                allocatedBytes: 0,
                latestModificationDate: nil,
                traversal: .unreadable(entryLimit: normalizedMaximumEntries)
            )
        }
        if (rootStat.st_mode & S_IFMT) == S_IFREG {
            return FileTreeMetrics(
                allocatedBytes: max(0, Int64(rootStat.st_blocks) * 512),
                latestModificationDate: includeLatestModificationDate
                    ? modificationDate(from: rootStat)
                    : nil,
                traversal: FileTreeTraversalEvidence(
                    rootWasReadable: true,
                    visitedEntryCount: 1,
                    regularFileCount: 1,
                    unreadableEntryCount: 0,
                    crossVolumeEntryCount: 0,
                    symbolicLinkCount: 0,
                    reachedEntryLimit: false,
                    entryLimit: normalizedMaximumEntries
                )
            )
        }
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            return FileTreeMetrics(
                allocatedBytes: 0,
                latestModificationDate: nil,
                traversal: FileTreeTraversalEvidence(
                    rootWasReadable: true,
                    visitedEntryCount: 1,
                    regularFileCount: 0,
                    unreadableEntryCount: 0,
                    crossVolumeEntryCount: 0,
                    symbolicLinkCount: (rootStat.st_mode & S_IFMT) == S_IFLNK ? 1 : 0,
                    reachedEntryLimit: false,
                    entryLimit: normalizedMaximumEntries
                )
            )
        }

        guard let rootCString = strdup(rootPath) else {
            return FileTreeMetrics(
                allocatedBytes: 0,
                latestModificationDate: nil,
                traversal: .unreadable(entryLimit: normalizedMaximumEntries)
            )
        }
        defer { free(rootCString) }

        let paths = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: 2)
        paths.initialize(repeating: nil, count: 2)
        paths[0] = rootCString
        defer { paths.deinitialize(count: 2); paths.deallocate() }

        var options = FTS_PHYSICAL | FTS_NOCHDIR
        if stayOnFileSystem { options |= FTS_XDEV }
        guard let stream = fts_open(
            UnsafePointer(paths),
            options,
            nil
        ) else {
            return FileTreeMetrics(
                allocatedBytes: 0,
                latestModificationDate: nil,
                traversal: .unreadable(entryLimit: normalizedMaximumEntries)
            )
        }
        defer { fts_close(stream) }

        var total: Int64 = 0
        var latestModificationDate: Date?
        var visited = 0
        var regularFiles = 0
        var unreadableEntries = 0
        var crossVolumeEntries = 0
        var symbolicLinks = 0
        var reachedEntryLimit = false

        // fts performs a physical POSIX walk and never constructs one NSURL +
        // resource-value cache per entry. That keeps a large cache tree from
        // inflating the main process allocator by several gigabytes.
        while !Task.isCancelled, let entry = fts_read(stream) {
            let info = Int32(entry.pointee.fts_info)
            if entry.pointee.fts_level == FTS_ROOTLEVEL { continue }
            if let normalizedMaximumEntries, visited >= normalizedMaximumEntries {
                reachedEntryLimit = true
                break
            }
            visited += 1

            if info == FTS_DNR || info == FTS_ERR || info == FTS_NS {
                unreadableEntries += 1
                continue
            }
            if info == FTS_SL || info == FTS_SLNONE {
                symbolicLinks += 1
                continue
            }
            if stayOnFileSystem,
               let statPointer = entry.pointee.fts_statp,
               statPointer.pointee.st_dev != rootStat.st_dev {
                crossVolumeEntries += 1
                if info == FTS_D { _ = fts_set(stream, entry, FTS_SKIP) }
                continue
            }

            if skipPackages,
               info == FTS_D,
               isPackagePath(entry.pointee.fts_path) {
                _ = fts_set(stream, entry, FTS_SKIP)
                continue
            }
            guard info == FTS_F,
                  let statPointer = entry.pointee.fts_statp else { continue }
            let fileStat = statPointer.pointee
            regularFiles += 1
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
            latestModificationDate: latestModificationDate,
            traversal: FileTreeTraversalEvidence(
                rootWasReadable: true,
                visitedEntryCount: visited,
                regularFileCount: regularFiles,
                unreadableEntryCount: unreadableEntries,
                crossVolumeEntryCount: crossVolumeEntries,
                symbolicLinkCount: symbolicLinks,
                reachedEntryLimit: reachedEntryLimit,
                entryLimit: normalizedMaximumEntries
            )
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

    public static func directChildren(
        of root: URL,
        includingHidden: Bool = false
    ) -> [URL] {
        directChildrenResult(of: root, includingHidden: includingHidden).children
    }

    public static func directChildrenResult(
        of root: URL,
        includingHidden: Bool = false
    ) -> FileTreeChildrenResult {
        var readErrorCount = 0
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
            options: includingHidden
                ? [.skipsSubdirectoryDescendants]
                : [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: { _, _ in
                readErrorCount += 1
                return true
            }
        ) else {
            return FileTreeChildrenResult(children: [], readErrorCount: 1)
        }

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
        return FileTreeChildrenResult(children: children, readErrorCount: readErrorCount)
    }
}
