import Foundation

/// A user-owned workflow decision layered on top of CleanNest's deterministic
/// disk safety assessment. These values never grant deletion authority.
public enum DiskManualDecision: String, Codable, CaseIterable, Sendable {
    case reviewForCleanup
    case keep
    case decideLater
}

public struct DiskManualDecisionRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let decision: DiskManualDecision
    public let updatedAt: Date

    public init(id: String, decision: DiskManualDecision, updatedAt: Date = Date()) {
        self.id = id
        self.decision = decision
        self.updatedAt = updatedAt
    }
}

public enum DiskManualDecisionError: LocalizedError, Equatable {
    case cleanupReviewNotAllowed

    public var errorDescription: String? {
        switch self {
        case .cleanupReviewNotAllowed:
            return "这个项目受保护、风险较高或应由所属 App 管理，不能标记为待清理复核。"
        }
    }
}

public enum DiskManualDecisionPolicy {
    /// A manual choice may only nominate an item for later review when the
    /// deterministic engine already proved that it is inside a reviewable,
    /// non-high-risk cleanup boundary.
    public static func canReviewForCleanup(_ entry: DiskEvidenceEntry) -> Bool {
        entry.cleanupBoundary == .reviewable
            && entry.minimumRisk != .high
            && entry.cleanupDecision.disposition == .reviewCandidate
    }
}

public struct DiskManualDecisionStore: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumRecordCount = 500

    public var schemaVersion: Int
    public private(set) var records: [String: DiskManualDecisionRecord]

    public init(
        schemaVersion: Int = DiskManualDecisionStore.schemaVersion,
        records: [String: DiskManualDecisionRecord] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    public func decision(for entry: DiskEvidenceEntry) -> DiskManualDecision? {
        guard let decision = records[entry.id]?.decision else { return nil }
        if decision == .reviewForCleanup,
           !DiskManualDecisionPolicy.canReviewForCleanup(entry) {
            // Evidence can become more restrictive after a later scan. Never
            // let an older manual record override the new safety boundary.
            return nil
        }
        return decision
    }

    public mutating func set(
        _ decision: DiskManualDecision?,
        for entry: DiskEvidenceEntry,
        now: Date = Date()
    ) throws {
        guard let decision else {
            records.removeValue(forKey: entry.id)
            return
        }
        if decision == .reviewForCleanup,
           !DiskManualDecisionPolicy.canReviewForCleanup(entry) {
            throw DiskManualDecisionError.cleanupReviewNotAllowed
        }
        records[entry.id] = DiskManualDecisionRecord(
            id: entry.id,
            decision: decision,
            updatedAt: now
        )
        pruneIfNeeded()
    }

    private mutating func pruneIfNeeded() {
        guard records.count > Self.maximumRecordCount else { return }
        let retained = records.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.maximumRecordCount)
        records = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
    }
}

public enum DiskManualDecisionPersistence {
    public static func load(from url: URL) throws -> DiskManualDecisionStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DiskManualDecisionStore()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let store = try decoder.decode(
            DiskManualDecisionStore.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
        guard store.schemaVersion == DiskManualDecisionStore.schemaVersion else {
            return DiskManualDecisionStore()
        }
        return store
    }

    public static func save(_ store: DiskManualDecisionStore, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(store)
        try data.write(to: url, options: .atomic)
    }
}
