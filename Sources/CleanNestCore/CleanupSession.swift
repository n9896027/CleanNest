import Darwin
import Foundation

public enum CleanupScanRootStatus: String, Codable, Equatable, Sendable {
    case checked
    case missing
    case unreadable
    case unsafe
}

public struct CleanupScanRootEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let pathHint: String
    public let status: CleanupScanRootStatus

    public init(name: String, url: URL, homeDirectory: URL) {
        let root = url.standardizedFileURL
        let pathHint = Self.redactedPath(root, homeDirectory: homeDirectory)
        self.name = name
        self.pathHint = pathHint
        self.id = "\(name)|\(pathHint)"
        self.status = CleanupScanRootInspector.status(of: root, relativeTo: homeDirectory)
    }

    public init(name: String, pathHint: String, status: CleanupScanRootStatus) {
        self.id = pathHint
        self.name = name
        self.pathHint = pathHint
        self.status = status
    }

    private static func redactedPath(_ url: URL, homeDirectory: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}

public enum CleanupScanRootInspector {
    public static func status(of url: URL) -> CleanupScanRootStatus {
        var information = stat()
        let result = url.path.withCString { lstat($0, &information) }
        guard result == 0 else {
            return errno == ENOENT || errno == ENOTDIR ? .missing : .unreadable
        }
        let type = information.st_mode & S_IFMT
        if type == S_IFLNK || type != S_IFDIR { return .unsafe }
        guard let directory = opendir(url.path) else { return .unreadable }
        closedir(directory)
        return .checked
    }

    public static func isSafeDirectory(_ url: URL) -> Bool {
        status(of: url) == .checked
    }

    public static func status(of url: URL, relativeTo homeDirectory: URL) -> CleanupScanRootStatus {
        let baseStatus = status(of: url)
        guard baseStatus == .checked else { return baseStatus }

        let lexicalRoot = url.standardizedFileURL
        let lexicalHome = homeDirectory.standardizedFileURL
        guard lexicalRoot.path == lexicalHome.path
                || lexicalRoot.path.hasPrefix(lexicalHome.path + "/") else {
            return baseStatus
        }

        let suffix = String(lexicalRoot.path.dropFirst(lexicalHome.path.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let resolvedHome = lexicalHome.resolvingSymlinksInPath().standardizedFileURL
        let expectedRoot = suffix.isEmpty
            ? resolvedHome
            : resolvedHome.appendingPathComponent(suffix, isDirectory: true).standardizedFileURL
        let resolvedRoot = lexicalRoot.resolvingSymlinksInPath().standardizedFileURL
        return resolvedRoot.path == expectedRoot.path ? .checked : .unsafe
    }
}

public enum CleanupScanSkipReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case cloudPlaceholder
    case symbolicLink
    case packageBoundary
    case unreadable
    case depthLimit
    case unsafeRoot
    case fileLimit
    case hashLimit

    public var id: String { rawValue }
}

public struct CleanupScanSkipEvidence: Codable, Equatable, Identifiable, Sendable {
    public let reason: CleanupScanSkipReason
    public let count: Int

    public var id: CleanupScanSkipReason { reason }

    public init(reason: CleanupScanSkipReason, count: Int) {
        self.reason = reason
        self.count = max(0, count)
    }
}

public struct CleanupScanCategoryEvidence: Codable, Equatable, Identifiable, Sendable {
    public let kind: CleanupKind
    public let count: Int
    public let allocatedBytes: Int64

    public var id: CleanupKind { kind }

    public init(kind: CleanupKind, candidates: [CleanupCandidate]) {
        self.kind = kind
        self.count = candidates.count
        self.allocatedBytes = candidates.reduce(0) { partial, candidate in
            Self.saturatingAdd(partial, max(0, candidate.allocatedBytes))
        }
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}

public struct CleanupScanIssue: Codable, Equatable, Identifiable, Sendable {
    public static let maximumPerScanner = 200

    public let id: String
    public let name: String
    public let url: URL
    public let reason: CleanupScanSkipReason

    public init(url: URL, reason: CleanupScanSkipReason) {
        let standardized = url.standardizedFileURL
        self.url = standardized
        self.name = standardized.lastPathComponent.isEmpty ? standardized.path : standardized.lastPathComponent
        self.reason = reason
        self.id = reason.rawValue + "|" + standardized.path
    }

    public var guidance: String {
        switch reason {
        case .unreadable: return "检查 macOS 文件访问权限后重新扫描；不会直接生成清理候选。"
        case .unsafeRoot: return "路径身份未通过安全检查，重新扫描不会绕过这条边界。"
        case .symbolicLink: return "为避免触及链接目标，重新扫描也不会跟随或清理链接目标。"
        case .packageBoundary: return "App 或资料库包保持完整；请使用所属 App 管理，不展开清理。"
        case .cloudPlaceholder: return "先在云端服务中完成下载或释放本地副本，再重新扫描。"
        case .depthLimit, .fileLimit, .hashLimit: return "本轮有界扫描未覆盖此处；相同设置下重扫不会扩大范围或执行权限。"
        }
    }
}

public struct CleanupScanSession: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let requestID: String
    public let startedAt: Date
    public let completedAt: Date
    public let elapsedSeconds: Double
    public let roots: [CleanupScanRootEvidence]
    public let examinedFileCount: Int
    public let categories: [CleanupScanCategoryEvidence]
    public let skips: [CleanupScanSkipEvidence]
    public let issues: [CleanupScanIssue]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        requestID: String,
        startedAt: Date,
        completedAt: Date,
        elapsedSeconds: Double,
        roots: [CleanupScanRootEvidence],
        insights: CleanupScanInsights,
        candidates: [CleanupCandidate],
        issues: [CleanupScanIssue] = []
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.startedAt = startedAt
        self.completedAt = max(startedAt, completedAt)
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.roots = roots
        self.examinedFileCount = max(0, insights.examinedFileCount)
        self.categories = CleanupKind.allCases.compactMap { kind in
            let matches = candidates.filter { $0.kind == kind }
            return matches.isEmpty ? nil : CleanupScanCategoryEvidence(kind: kind, candidates: matches)
        }
        self.skips = Self.makeSkips(insights)
        self.issues = issues
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case requestID
        case startedAt
        case completedAt
        case elapsedSeconds
        case roots
        case examinedFileCount
        case categories
        case skips
        case issues
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        requestID = try container.decode(String.self, forKey: .requestID)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        elapsedSeconds = try container.decode(Double.self, forKey: .elapsedSeconds)
        roots = try container.decode([CleanupScanRootEvidence].self, forKey: .roots)
        examinedFileCount = try container.decode(Int.self, forKey: .examinedFileCount)
        categories = try container.decode([CleanupScanCategoryEvidence].self, forKey: .categories)
        skips = try container.decode([CleanupScanSkipEvidence].self, forKey: .skips)
        issues = try container.decodeIfPresent([CleanupScanIssue].self, forKey: .issues) ?? []
    }

    public var checkedRootCount: Int { roots.filter { $0.status == .checked }.count }
    public var candidateCount: Int { categories.reduce(0) { $0 + $1.count } }

    private static func makeSkips(_ insights: CleanupScanInsights) -> [CleanupScanSkipEvidence] {
        let values: [(CleanupScanSkipReason, Int)] = [
            (.cloudPlaceholder, insights.skippedCloudItemCount),
            (.symbolicLink, insights.skippedSymbolicLinkCount),
            (.packageBoundary, insights.skippedPackageCount),
            (.unreadable, insights.skippedUnreadableItemCount),
            (.depthLimit, insights.skippedDepthLimitCount),
            (.unsafeRoot, insights.skippedUnsafeRootCount),
            (.fileLimit, insights.reachedFileLimit ? 1 : 0),
            (.hashLimit, insights.reachedHashLimit ? 1 : 0)
        ]
        return values.compactMap { reason, count in
            count > 0 ? CleanupScanSkipEvidence(reason: reason, count: count) : nil
        }
    }
}

public enum CleanupBatchSelectionAction: Sendable {
    case selectAll
    case clear
    case invert
}

public enum CleanupSelectionPolicy {
    public static func applying(
        _ action: CleanupBatchSelectionAction,
        candidateIDs: Set<String>,
        to currentSelection: Set<String>
    ) -> Set<String> {
        switch action {
        case .selectAll:
            return currentSelection.union(candidateIDs)
        case .clear:
            return currentSelection.subtracting(candidateIDs)
        case .invert:
            let selectedInScope = currentSelection.intersection(candidateIDs)
            return currentSelection.subtracting(candidateIDs).union(candidateIDs.subtracting(selectedInScope))
        }
    }
}

public struct CleanupCandidatePageWindow: Equatable, Sendable {
    public static let defaultPageSize = 40

    public let itemCount: Int
    public let pageSize: Int
    public let pageIndex: Int

    public init(
        itemCount: Int,
        pageSize: Int = Self.defaultPageSize,
        requestedPageIndex: Int = 0
    ) {
        self.itemCount = max(0, itemCount)
        self.pageSize = max(1, pageSize)
        let availablePages = self.itemCount == 0
            ? 0
            : ((self.itemCount - 1) / self.pageSize) + 1
        self.pageIndex = availablePages == 0
            ? 0
            : min(max(0, requestedPageIndex), availablePages - 1)
    }

    public var pageCount: Int {
        itemCount == 0 ? 0 : ((itemCount - 1) / pageSize) + 1
    }

    public var range: Range<Int> {
        guard itemCount > 0 else { return 0..<0 }
        let lowerBound = pageIndex * pageSize
        return lowerBound..<(lowerBound + min(pageSize, itemCount - lowerBound))
    }

    public var displayedStartNumber: Int { range.isEmpty ? 0 : range.lowerBound + 1 }
    public var displayedEndNumber: Int { range.upperBound }
    public var hasPreviousPage: Bool { pageIndex > 0 }
    public var hasNextPage: Bool { pageIndex + 1 < pageCount }
}

public struct CleanupBasketSummary: Equatable, Sendable {
    public let selectedCount: Int
    public let selectedBytes: Int64
    public let projectedFreeBytesAfterEmptyingTrash: Int64
    public let personalFileCount: Int
    public let duplicateCount: Int
    public let identityRevalidationCount: Int
    public let pathRevalidationCount: Int

    public init(
        candidates: [CleanupCandidate],
        selectedIDs: Set<String>,
        currentFreeBytes: Int64
    ) {
        let selected = candidates.filter { selectedIDs.contains($0.id) }
        selectedCount = selected.count
        selectedBytes = selected.reduce(0) { partial, candidate in
            Self.saturatingAdd(partial, max(0, candidate.allocatedBytes))
        }
        projectedFreeBytesAfterEmptyingTrash = Self.saturatingAdd(
            max(0, currentFreeBytes),
            selectedBytes
        )
        personalFileCount = selected.filter { $0.kind.isPersonalFile }.count
        duplicateCount = selected.filter { $0.duplicateEvidence != nil }.count
        identityRevalidationCount = selected.filter { $0.fileIdentity != nil }.count
        pathRevalidationCount = selected.count - identityRevalidationCount
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}

public enum CleanupMediaTimeBucket: String, CaseIterable, Identifiable, Sendable {
    case recent
    case aging
    case old
    case unknown

    public var id: String { rawValue }
}

public enum CleanupMediaSizeBucket: String, CaseIterable, Identifiable, Sendable {
    case under100MB
    case from100MBTo1GB
    case over1GB

    public var id: String { rawValue }
}

public struct CleanupMediaClusterSummary: Equatable, Sendable {
    public let timeCounts: [CleanupMediaTimeBucket: Int]
    public let sizeCounts: [CleanupMediaSizeBucket: Int]

    public init(candidates: [CleanupCandidate], now: Date = Date()) {
        var timeCounts: [CleanupMediaTimeBucket: Int] = [:]
        var sizeCounts: [CleanupMediaSizeBucket: Int] = [:]
        for candidate in candidates {
            let timeBucket: CleanupMediaTimeBucket
            if let modifiedAt = candidate.modifiedAt {
                let age = max(0, now.timeIntervalSince(modifiedAt))
                if age < 30 * 86_400 {
                    timeBucket = .recent
                } else if age < 90 * 86_400 {
                    timeBucket = .aging
                } else {
                    timeBucket = .old
                }
            } else {
                timeBucket = .unknown
            }
            timeCounts[timeBucket, default: 0] += 1

            let bytes = max(0, candidate.allocatedBytes)
            let sizeBucket: CleanupMediaSizeBucket
            if bytes < 100 * 1_048_576 {
                sizeBucket = .under100MB
            } else if bytes < 1_024 * 1_048_576 {
                sizeBucket = .from100MBTo1GB
            } else {
                sizeBucket = .over1GB
            }
            sizeCounts[sizeBucket, default: 0] += 1
        }
        self.timeCounts = timeCounts
        self.sizeCounts = sizeCounts
    }
}
