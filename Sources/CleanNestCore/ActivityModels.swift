import Foundation

public struct CleanupActivityResult: Codable, Hashable, Sendable {
    public let candidateBytes: Int64
    public let trashedBytes: Int64
    public let apfsFreeBytesDelta: Int64

    private enum CodingKeys: String, CodingKey {
        case candidateBytes
        case trashedBytes
        case apfsFreeBytesDelta
    }

    public init(candidateBytes: Int64, trashedBytes: Int64, apfsFreeBytesDelta: Int64) {
        self.candidateBytes = max(0, candidateBytes)
        self.trashedBytes = max(0, trashedBytes)
        self.apfsFreeBytesDelta = max(-Int64.max, apfsFreeBytesDelta)
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            candidateBytes: try values.decode(Int64.self, forKey: .candidateBytes),
            trashedBytes: try values.decode(Int64.self, forKey: .trashedBytes),
            apfsFreeBytesDelta: try values.decode(Int64.self, forKey: .apfsFreeBytesDelta)
        )
    }
}

public struct ActivityEntry: Identifiable, Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Hashable, Sendable {
        case success = "完成"
        case partial = "部分完成"
        case failed = "未完成"

        public var symbol: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .partial: return "exclamationmark.circle.fill"
            case .failed: return "xmark.circle.fill"
            }
        }
    }

    public enum Category: String, Codable, Hashable, Sendable {
        case cleanup
        case applicationUninstall
        case other
    }

    public let id: UUID
    public let date: Date
    public let title: String
    public let detail: String
    public let outcome: Outcome
    public let affectedItems: Int
    public let bytes: Int64
    public let category: Category?
    public let cleanupResult: CleanupActivityResult?
    public let executionID: String?

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        detail: String,
        outcome: Outcome,
        affectedItems: Int = 0,
        bytes: Int64 = 0,
        category: Category? = nil,
        cleanupResult: CleanupActivityResult? = nil,
        executionID: String? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.outcome = outcome
        self.affectedItems = affectedItems
        self.bytes = bytes
        self.category = category
        self.cleanupResult = cleanupResult
        self.executionID = executionID
    }

    public var effectiveCategory: Category {
        if let category { return category }

        // Records written before categories existed remain useful after upgrade.
        if title == "清理空间" { return .cleanup }
        if title.hasPrefix("卸载 ") { return .applicationUninstall }
        return .other
    }
}

public struct ActivityLifetimeTotals: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public private(set) var processedBytes: Int64
    public private(set) var cleanedItems: Int
    public private(set) var uninstalledApplications: Int
    public private(set) var productiveOperations: Int
    public private(set) var lastUpdatedAt: Date?

    public init(
        schemaVersion: Int = Self.schemaVersion,
        processedBytes: Int64 = 0,
        cleanedItems: Int = 0,
        uninstalledApplications: Int = 0,
        productiveOperations: Int = 0,
        lastUpdatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.processedBytes = max(0, processedBytes)
        self.cleanedItems = max(0, cleanedItems)
        self.uninstalledApplications = max(0, uninstalledApplications)
        self.productiveOperations = max(0, productiveOperations)
        self.lastUpdatedAt = lastUpdatedAt
    }

    public init(entries: [ActivityEntry]) {
        self.init()
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            record(entry)
        }
    }

    public mutating func record(_ entry: ActivityEntry) {
        guard entry.outcome != .failed else { return }
        productiveOperations = Self.saturatingAdd(productiveOperations, 1)
        switch entry.effectiveCategory {
        case .cleanup:
            cleanedItems = Self.saturatingAdd(cleanedItems, max(0, entry.affectedItems))
            processedBytes = Self.saturatingAdd(processedBytes, max(0, entry.bytes))
        case .applicationUninstall:
            uninstalledApplications = Self.saturatingAdd(uninstalledApplications, 1)
            processedBytes = Self.saturatingAdd(processedBytes, max(0, entry.bytes))
        case .other:
            break
        }
        lastUpdatedAt = max(lastUpdatedAt ?? entry.date, entry.date)
    }

    private static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        guard rhs > 0 else { return lhs }
        return lhs > Int.max - rhs ? Int.max : lhs + rhs
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        guard rhs > 0 else { return lhs }
        return lhs > Int64.max - rhs ? Int64.max : lhs + rhs
    }
}

public enum ActivityLifetimeTotalsPersistence {
    public static func load(from url: URL) throws -> ActivityLifetimeTotals? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let totals = try JSONDecoder().decode(
            ActivityLifetimeTotals.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
        guard totals.schemaVersion == ActivityLifetimeTotals.schemaVersion else { return nil }
        return totals
    }

    public static func save(_ totals: ActivityLifetimeTotals, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(totals).write(to: url, options: .atomic)
    }
}

public enum ActivityTimeWindow: String, CaseIterable, Identifiable, Sendable {
    case all
    case day
    case week
    case month

    public var id: String { rawValue }

    fileprivate func lowerBound(relativeTo referenceDate: Date) -> Date? {
        let seconds: TimeInterval
        switch self {
        case .all: return nil
        case .day: seconds = 24 * 60 * 60
        case .week: seconds = 7 * 24 * 60 * 60
        case .month: seconds = 30 * 24 * 60 * 60
        }
        return referenceDate.addingTimeInterval(-seconds)
    }
}

public struct ActivityFilter: Equatable, Sendable {
    public var query: String
    public var category: ActivityEntry.Category?
    public var outcome: ActivityEntry.Outcome?
    public var timeWindow: ActivityTimeWindow

    public init(
        query: String = "",
        category: ActivityEntry.Category? = nil,
        outcome: ActivityEntry.Outcome? = nil,
        timeWindow: ActivityTimeWindow = .all
    ) {
        self.query = query
        self.category = category
        self.outcome = outcome
        self.timeWindow = timeWindow
    }

    public func apply(
        to entries: [ActivityEntry],
        relativeTo referenceDate: Date = Date()
    ) -> [ActivityEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerBound = timeWindow.lowerBound(relativeTo: referenceDate)
        return entries.filter { entry in
            if let category, entry.effectiveCategory != category { return false }
            if let outcome, entry.outcome != outcome { return false }
            if let lowerBound, entry.date < lowerBound { return false }
            guard !trimmedQuery.isEmpty else { return true }
            return entry.title.localizedCaseInsensitiveContains(trimmedQuery)
                || entry.detail.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
}

public struct ActivityStatistics: Equatable, Sendable {
    public let processedBytes: Int64
    public let cleanedItems: Int
    public let uninstalledApplications: Int
    public let productiveOperations: Int
    public let recordCount: Int

    public init(entries: [ActivityEntry]) {
        let productive = entries.filter { $0.outcome != .failed }
        let cleanup = productive.filter { $0.effectiveCategory == .cleanup }
        let uninstall = productive.filter { $0.effectiveCategory == .applicationUninstall }

        processedBytes = (cleanup + uninstall).reduce(0) { partial, entry in
            partial + max(0, entry.bytes)
        }
        cleanedItems = cleanup.reduce(0) { partial, entry in
            partial + max(0, entry.affectedItems)
        }
        uninstalledApplications = uninstall.count
        productiveOperations = productive.count
        recordCount = entries.count
    }
}
