import Foundation

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

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        detail: String,
        outcome: Outcome,
        affectedItems: Int = 0,
        bytes: Int64 = 0,
        category: Category? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.outcome = outcome
        self.affectedItems = affectedItems
        self.bytes = bytes
        self.category = category
    }

    var effectiveCategory: Category {
        if let category { return category }

        // Records written before categories existed remain useful after upgrade.
        if title == "清理空间" { return .cleanup }
        if title.hasPrefix("卸载 ") { return .applicationUninstall }
        return .other
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
