import Foundation

public struct DiskVolumeSnapshot: Codable, Equatable, Sendable {
    public let selectedRoot: URL
    public let volumeRoot: URL
    public let volumeName: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let availableForImportantUsageBytes: Int64?
    public let selectedRootIsVolumeRoot: Bool

    public init(
        selectedRoot: URL,
        volumeRoot: URL,
        volumeName: String,
        totalBytes: Int64,
        availableBytes: Int64,
        availableForImportantUsageBytes: Int64?,
        selectedRootIsVolumeRoot: Bool
    ) {
        self.selectedRoot = selectedRoot.standardizedFileURL
        self.volumeRoot = volumeRoot.standardizedFileURL
        self.volumeName = volumeName
        self.totalBytes = max(0, totalBytes)
        self.availableBytes = max(0, min(availableBytes, totalBytes))
        self.availableForImportantUsageBytes = availableForImportantUsageBytes.map {
            max(0, min($0, totalBytes))
        }
        self.selectedRootIsVolumeRoot = selectedRootIsVolumeRoot
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    public var reclaimableCapacityBytes: Int64? {
        guard let availableForImportantUsageBytes else { return nil }
        return max(0, availableForImportantUsageBytes - availableBytes)
    }

    public static func capture(for selectedRoot: URL) -> DiskVolumeSnapshot? {
        let normalized = selectedRoot.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .volumeURLKey,
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? normalized.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacity,
              total > 0 else {
            return nil
        }
        let volumeRoot = (values.volume ?? normalized).standardizedFileURL
        return DiskVolumeSnapshot(
            selectedRoot: normalized,
            volumeRoot: volumeRoot,
            volumeName: values.volumeName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? FileManager.default.displayName(atPath: volumeRoot.path),
            totalBytes: Int64(total),
            availableBytes: Int64(available),
            availableForImportantUsageBytes: values.volumeAvailableCapacityForImportantUsage,
            selectedRootIsVolumeRoot: normalized.path == volumeRoot.path
        )
    }
}

public struct DiskScanCoverage: Codable, Equatable, Sendable {
    public let rootEnumerationErrorCount: Int
    public let topLevelEntryCount: Int
    public let hiddenTopLevelEntryCount: Int
    public let visitedEntryCount: Int
    public let regularFileCount: Int
    public let unreadableEntryCount: Int
    public let crossVolumeEntryCount: Int
    public let symbolicLinkCount: Int
    public let limitedSubtreeCount: Int
    public let unknownCachedSubtreeCount: Int
    public let unboundedTraversal: Bool

    public init(
        rootEnumerationErrorCount: Int,
        topLevelEntryCount: Int,
        hiddenTopLevelEntryCount: Int,
        visitedEntryCount: Int,
        regularFileCount: Int,
        unreadableEntryCount: Int,
        crossVolumeEntryCount: Int,
        symbolicLinkCount: Int,
        limitedSubtreeCount: Int,
        unknownCachedSubtreeCount: Int,
        unboundedTraversal: Bool
    ) {
        self.rootEnumerationErrorCount = max(0, rootEnumerationErrorCount)
        self.topLevelEntryCount = max(0, topLevelEntryCount)
        self.hiddenTopLevelEntryCount = max(0, hiddenTopLevelEntryCount)
        self.visitedEntryCount = max(0, visitedEntryCount)
        self.regularFileCount = max(0, regularFileCount)
        self.unreadableEntryCount = max(0, unreadableEntryCount)
        self.crossVolumeEntryCount = max(0, crossVolumeEntryCount)
        self.symbolicLinkCount = max(0, symbolicLinkCount)
        self.limitedSubtreeCount = max(0, limitedSubtreeCount)
        self.unknownCachedSubtreeCount = max(0, unknownCachedSubtreeCount)
        self.unboundedTraversal = unboundedTraversal
    }

    public var hasKnownLimitOrReadGap: Bool {
        rootEnumerationErrorCount > 0
            || unreadableEntryCount > 0
            || limitedSubtreeCount > 0
            || unknownCachedSubtreeCount > 0
    }

    public var statusLabel: String {
        if limitedSubtreeCount > 0 { return "达到条目上限" }
        if rootEnumerationErrorCount + unreadableEntryCount > 0 { return "存在不可读项目" }
        if unknownCachedSubtreeCount > 0 { return "旧索引完整度未知" }
        return unboundedTraversal ? "深度遍历完成" : "有界遍历完成"
    }

    public static func summarize(
        entries: [DiskEntry],
        rootEnumerationErrorCount: Int,
        hiddenTopLevelEntryCount: Int,
        unboundedTraversal: Bool
    ) -> DiskScanCoverage {
        let known = entries.compactMap(\.traversal)
        return DiskScanCoverage(
            rootEnumerationErrorCount: rootEnumerationErrorCount,
            topLevelEntryCount: entries.count,
            hiddenTopLevelEntryCount: hiddenTopLevelEntryCount,
            visitedEntryCount: known.reduce(0) { $0 + $1.visitedEntryCount },
            regularFileCount: known.reduce(0) { $0 + $1.regularFileCount },
            unreadableEntryCount: known.reduce(0) { $0 + $1.unreadableEntryCount },
            crossVolumeEntryCount: known.reduce(0) { $0 + $1.crossVolumeEntryCount },
            symbolicLinkCount: known.reduce(0) { $0 + $1.symbolicLinkCount },
            limitedSubtreeCount: known.filter(\.reachedEntryLimit).count,
            unknownCachedSubtreeCount: entries.count - known.count,
            unboundedTraversal: unboundedTraversal
        )
    }
}

public struct DiskCapacityReconciliation: Equatable, Sendable {
    public let volume: DiskVolumeSnapshot
    public let classifiedBytes: Int64

    public init(volume: DiskVolumeSnapshot, classifiedBytes: Int64) {
        self.volume = volume
        self.classifiedBytes = max(0, classifiedBytes)
    }

    public var isComparable: Bool { volume.selectedRootIsVolumeRoot }

    /// Positive means the APFS allocation ledger contains more used bytes than
    /// the visible file walk classified. Negative values are possible when
    /// clones, hard links or firmlinks make per-file allocated blocks overlap.
    public var accountingDifferenceBytes: Int64? {
        guard isComparable else { return nil }
        return volume.usedBytes - classifiedBytes
    }

    public var classifiedShareOfUsed: Double? {
        guard isComparable, volume.usedBytes > 0 else { return nil }
        return Double(classifiedBytes) / Double(volume.usedBytes)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
