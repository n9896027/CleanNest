import CryptoKit
import Foundation

public enum DiskScanMode: String, Codable, Equatable, Sendable {
    case reuseFreshCache
    case bypassCache
}

public struct DiskScanProgress: Codable, Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentName: String
    public let partialReport: DiskReport?
    public let cacheHitCount: Int
    public let scannedCount: Int

    public init(
        completed: Int,
        total: Int,
        currentName: String,
        partialReport: DiskReport? = nil,
        cacheHitCount: Int = 0,
        scannedCount: Int = 0
    ) {
        self.completed = completed
        self.total = total
        self.currentName = currentName
        self.partialReport = partialReport
        self.cacheHitCount = cacheHitCount
        self.scannedCount = scannedCount
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

public struct DiskScanOutcome: Codable, Equatable, Sendable {
    public let report: DiskReport
    public let updatedCache: DiskScanCacheStore
    public let cacheHitCount: Int
    public let scannedCount: Int
    public let elapsedSeconds: Double
    public let volumeSnapshot: DiskVolumeSnapshot?
    public let coverage: DiskScanCoverage

    public init(
        report: DiskReport,
        updatedCache: DiskScanCacheStore,
        cacheHitCount: Int,
        scannedCount: Int,
        elapsedSeconds: Double,
        volumeSnapshot: DiskVolumeSnapshot?,
        coverage: DiskScanCoverage
    ) {
        self.report = report
        self.updatedCache = updatedCache
        self.cacheHitCount = cacheHitCount
        self.scannedCount = scannedCount
        self.elapsedSeconds = elapsedSeconds
        self.volumeSnapshot = volumeSnapshot
        self.coverage = coverage
    }

    public var usedCache: Bool { cacheHitCount > 0 }
}

public struct NativeDiskAnalyzer: Sendable {
    public let cacheMaximumAge: TimeInterval
    public let maximumSignatureChildren: Int
    public let maximumTraversalEntriesPerItem: Int

    public init(
        cacheMaximumAge: TimeInterval = 15 * 60,
        maximumSignatureChildren: Int = 4_096,
        maximumTraversalEntriesPerItem: Int = 500_000
    ) {
        self.cacheMaximumAge = max(0, cacheMaximumAge)
        self.maximumSignatureChildren = min(max(maximumSignatureChildren, 32), 20_000)
        self.maximumTraversalEntriesPerItem = max(1, maximumTraversalEntriesPerItem)
    }

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
        try await analyze(
            root: root,
            cache: DiskScanCacheStore(),
            mode: .bypassCache,
            progress: progress
        ).report
    }

    public func analyze(
        root: URL,
        cache: DiskScanCacheStore,
        mode: DiskScanMode = .reuseFreshCache,
        now: Date = Date(),
        progress: (@Sendable (DiskScanProgress) -> Void)? = nil
    ) async throws -> DiskScanOutcome {
        // A detached worker does not inherit an already-cancelled parent task.
        // Reject that state before allocating or enumerating anything.
        try Task.checkCancellation()
        let cacheMaximumAge = self.cacheMaximumAge
        let maximumSignatureChildren = self.maximumSignatureChildren
        let maximumTraversalEntriesPerItem = self.maximumTraversalEntriesPerItem
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let worker = Task.detached(priority: .userInitiated) {
            let normalizedRoot = root.standardizedFileURL
            let childResult = FileTree.directChildrenResult(
                of: normalizedRoot,
                includingHidden: true
            )
            let children = childResult.children
            let hiddenTopLevelEntryCount = children.filter {
                $0.lastPathComponent.hasPrefix(".")
            }.count
            let volumeSnapshot = DiskVolumeSnapshot.capture(for: normalizedRoot)
            let traversalLimit: Int? = mode == .bypassCache
                ? nil
                : maximumTraversalEntriesPerItem
            // 磁盘缓存可能被截断或损坏；重复条目保留第一份，不崩溃。
            let previousByID = Dictionary(
                (cache.root(for: normalizedRoot)?.entries ?? []).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            var entries: [DiskEntry] = []
            var nextCacheEntries: [DiskScanCacheEntry] = []
            var cacheHitCount = 0
            var scannedCount = 0
            entries.reserveCapacity(children.count)
            nextCacheEntries.reserveCapacity(children.count)

            progress?(
                DiskScanProgress(
                    completed: 0,
                    total: children.count,
                    currentName: normalizedRoot.lastPathComponent
                )
            )

            for (index, child) in children.enumerated() {
                try Task.checkCancellation()
                let values = try? child.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey
                ])
                let isDirectory = values?.isDirectory ?? false
                let isSymbolicLink = values?.isSymbolicLink ?? false
                let entryID = DiskEvidenceIndexer.fingerprint(for: child)
                let signature = Self.metadataSignature(
                    for: child,
                    isDirectory: isDirectory,
                    isSymbolicLink: isSymbolicLink,
                    maximumChildren: maximumSignatureChildren
                )
                let cached = previousByID[entryID]
                let cacheIsFresh = cached.map {
                    now.timeIntervalSince($0.sampledAt) >= 0
                        && now.timeIntervalSince($0.sampledAt) <= cacheMaximumAge
                } ?? false
                let mayReuse = mode == .reuseFreshCache
                    && cacheIsFresh
                    && cached?.metadataSignature == signature
                    && cached?.isDirectory == isDirectory

                let bytes: Int64
                let sampledAt: Date
                let traversal: FileTreeTraversalEvidence?
                if mayReuse, let cached {
                    bytes = max(0, cached.allocatedBytes)
                    sampledAt = cached.sampledAt
                    traversal = cached.traversal
                    cacheHitCount += 1
                } else {
                    let metrics = FileTree.metrics(
                        of: child,
                        skipPackages: false,
                        maximumEntries: traversalLimit,
                        stayOnFileSystem: true
                    )
                    bytes = max(0, metrics.allocatedBytes)
                    sampledAt = now
                    traversal = metrics.traversal
                    scannedCount += 1
                }
                try Task.checkCancellation()

                entries.append(
                    DiskEntry(
                        name: child.lastPathComponent,
                        url: child,
                        bytes: bytes,
                        isDirectory: isDirectory,
                        traversal: traversal
                    )
                )
                nextCacheEntries.append(
                    DiskScanCacheEntry(
                        id: entryID,
                        name: String(child.lastPathComponent.prefix(240)),
                        metadataSignature: signature,
                        allocatedBytes: bytes,
                        isDirectory: isDirectory,
                        sampledAt: sampledAt,
                        traversal: traversal
                    )
                )

                let partial = Self.makeReport(root: normalizedRoot, entries: entries)
                progress?(
                    DiskScanProgress(
                        completed: index + 1,
                        total: children.count,
                        currentName: String(child.lastPathComponent.prefix(120)),
                        partialReport: partial,
                        cacheHitCount: cacheHitCount,
                        scannedCount: scannedCount
                    )
                )
            }

            let report = Self.makeReport(root: normalizedRoot, entries: entries)
            let coverage = DiskScanCoverage.summarize(
                entries: report.entries,
                rootEnumerationErrorCount: childResult.readErrorCount,
                hiddenTopLevelEntryCount: hiddenTopLevelEntryCount,
                unboundedTraversal: traversalLimit == nil
            )
            var updatedCache = cache
            updatedCache.replaceRoot(
                DiskScanCacheRoot(
                    id: DiskEvidenceIndexer.fingerprint(for: normalizedRoot),
                    generatedAt: now,
                    entries: nextCacheEntries
                )
            )
            let endedAt = DispatchTime.now().uptimeNanoseconds
            let elapsed = Double(endedAt - startedAt) / 1_000_000_000
            return DiskScanOutcome(
                report: report,
                updatedCache: updatedCache,
                cacheHitCount: cacheHitCount,
                scannedCount: scannedCount,
                elapsedSeconds: elapsed,
                volumeSnapshot: volumeSnapshot,
                coverage: coverage
            )
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func makeReport(root: URL, entries: [DiskEntry]) -> DiskReport {
        let sorted = entries.sorted {
            if $0.bytes == $1.bytes { return $0.name < $1.name }
            return $0.bytes > $1.bytes
        }
        return DiskReport(
            root: root,
            entries: sorted,
            largeFiles: sorted.filter { !$0.isDirectory }.prefix(20).map { $0 },
            totalBytes: sorted.reduce(0) { $0 + $1.bytes },
            totalFiles: sorted.reduce(0) { partial, entry in
                partial + (entry.traversal?.regularFileCount ?? (entry.isDirectory ? 0 : 1))
            }
        )
    }

    /// A cheap change detector. For directories it includes their own metadata
    /// and a bounded summary of direct children. Deeper changes can remain
    /// cached only until the short freshness window expires; a deep refresh
    /// always bypasses this decision.
    private static func metadataSignature(
        for url: URL,
        isDirectory: Bool,
        isSymbolicLink: Bool,
        maximumChildren: Int
    ) -> String {
        var parts = [metadataLine(for: url, name: url.lastPathComponent)]
        parts.append(isDirectory ? "directory" : "file")
        parts.append(isSymbolicLink ? "symlink" : "regular")

        if isDirectory, !isSymbolicLink {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .totalFileAllocatedSizeKey,
                    .contentModificationDateKey
                ],
                options: []
            )) ?? []
            parts.append("children:\(children.count)")
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).prefix(maximumChildren) {
                parts.append(metadataLine(for: child, name: child.lastPathComponent))
            }
            if children.count > maximumChildren {
                parts.append("limited:\(maximumChildren)")
            }
        }

        let digest = SHA256.hash(data: Data(parts.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func metadataLine(for url: URL, name: String) -> String {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ])
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? -1
        let size = values?.totalFileAllocatedSize ?? values?.fileSize ?? -1
        return [
            String(name.prefix(240)),
            values?.isDirectory == true ? "d" : "f",
            values?.isSymbolicLink == true ? "l" : "n",
            String(size),
            String(format: "%.6f", modified)
        ].joined(separator: "|")
    }
}
