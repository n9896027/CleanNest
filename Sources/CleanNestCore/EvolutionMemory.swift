import Foundation

public enum CleanupLearningDecision: String, Codable, CaseIterable, Sendable {
    case preferCleanup
    case preferKeep
    case cleaned
}

public enum LearnedCleanupPreference: String, Codable, Sendable {
    case preferCleanup
    case preferKeep
}

public struct CleanupLearningSignal: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var displayName: String
    public var kind: CleanupKind
    public var explicitPreference: LearnedCleanupPreference?
    public var explicitRevisionCount: Int
    public var successfulCleanupCount: Int
    public var lastUpdatedAt: Date

    public init(
        id: String,
        displayName: String,
        kind: CleanupKind,
        explicitPreference: LearnedCleanupPreference? = nil,
        explicitRevisionCount: Int = 0,
        successfulCleanupCount: Int = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.explicitPreference = explicitPreference
        self.explicitRevisionCount = explicitRevisionCount
        self.successfulCleanupCount = successfulCleanupCount
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var effectivePreference: LearnedCleanupPreference? {
        if let explicitPreference { return explicitPreference }
        return successfulCleanupCount > 0 ? .preferCleanup : nil
    }
}

public struct ModelLearningSignal: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var displayName: String
    public var helpfulCount: Int
    public var unhelpfulCount: Int
    public var lastUpdatedAt: Date

    public init(
        id: String,
        displayName: String,
        helpfulCount: Int = 0,
        unhelpfulCount: Int = 0,
        lastUpdatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.helpfulCount = helpfulCount
        self.unhelpfulCount = unhelpfulCount
        self.lastUpdatedAt = lastUpdatedAt
    }

    public var feedbackCount: Int { helpfulCount + unhelpfulCount }

    public var helpfulRatio: Double? {
        guard feedbackCount > 0 else { return nil }
        return Double(helpfulCount) / Double(feedbackCount)
    }
}

public struct EvolutionEvent: Identifiable, Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case cleanupPreference
        case successfulCleanup
        case modelFeedback
    }

    public let id: UUID
    public let date: Date
    public let kind: Kind
    public let title: String
    public let detail: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: Kind,
        title: String,
        detail: String
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct EvolutionMemory: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var cleanupSignals: [String: CleanupLearningSignal]
    public var modelSignals: [String: ModelLearningSignal]
    public var events: [EvolutionEvent]
    public var updatedAt: Date?

    public init(
        schemaVersion: Int = EvolutionMemory.schemaVersion,
        cleanupSignals: [String: CleanupLearningSignal] = [:],
        modelSignals: [String: ModelLearningSignal] = [:],
        events: [EvolutionEvent] = [],
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.cleanupSignals = cleanupSignals
        self.modelSignals = modelSignals
        self.events = events
        self.updatedAt = updatedAt
    }

    public var learnedCleanupCount: Int {
        cleanupSignals.values.filter { $0.effectivePreference != nil }.count
    }

    public var successfulCleanupCount: Int {
        cleanupSignals.values.reduce(0) { $0 + $1.successfulCleanupCount }
    }

    public var modelFeedbackCount: Int {
        modelSignals.values.reduce(0) { $0 + $1.feedbackCount }
    }

    public var sortedCleanupSignals: [CleanupLearningSignal] {
        cleanupSignals.values
            .filter { $0.effectivePreference != nil }
            .sorted {
                if $0.lastUpdatedAt == $1.lastUpdatedAt { return $0.displayName < $1.displayName }
                return $0.lastUpdatedAt > $1.lastUpdatedAt
            }
    }

    public var sortedModelSignals: [ModelLearningSignal] {
        modelSignals.values.sorted {
            if $0.lastUpdatedAt == $1.lastUpdatedAt { return $0.displayName < $1.displayName }
            return $0.lastUpdatedAt > $1.lastUpdatedAt
        }
    }

    public func cleanupSignal(for candidate: CleanupCandidate) -> CleanupLearningSignal? {
        cleanupSignals[Self.cleanupKey(for: candidate)]
    }

    public func cleanupPreference(for candidate: CleanupCandidate) -> LearnedCleanupPreference? {
        cleanupSignal(for: candidate)?.effectivePreference
    }

    public mutating func recordCleanup(
        _ candidate: CleanupCandidate,
        decision: CleanupLearningDecision,
        now: Date = Date()
    ) {
        let key = Self.cleanupKey(for: candidate)
        var signal = cleanupSignals[key] ?? CleanupLearningSignal(
            id: key,
            displayName: candidate.name,
            kind: candidate.kind,
            lastUpdatedAt: now
        )
        signal.displayName = candidate.name
        signal.kind = candidate.kind
        signal.lastUpdatedAt = now

        let eventTitle: String
        let eventDetail: String
        switch decision {
        case .preferCleanup:
            signal.explicitPreference = .preferCleanup
            signal.explicitRevisionCount += 1
            eventTitle = "记住优先清理"
            eventDetail = "\(candidate.kind.rawValue) · \(candidate.name)"
        case .preferKeep:
            signal.explicitPreference = .preferKeep
            signal.explicitRevisionCount += 1
            eventTitle = "记住优先保留"
            eventDetail = "\(candidate.kind.rawValue) · \(candidate.name)"
        case .cleaned:
            signal.successfulCleanupCount += 1
            eventTitle = "完成一次安全清理"
            eventDetail = "\(candidate.kind.rawValue) · \(candidate.name)"
        }

        cleanupSignals[key] = signal
        updatedAt = now
        appendEvent(EvolutionEvent(
            date: now,
            kind: decision == .cleaned ? .successfulCleanup : .cleanupPreference,
            title: eventTitle,
            detail: eventDetail
        ))
    }

    public mutating func clearExplicitPreference(
        for candidate: CleanupCandidate,
        now: Date = Date()
    ) {
        let key = Self.cleanupKey(for: candidate)
        guard var signal = cleanupSignals[key], signal.explicitPreference != nil else { return }
        signal.explicitPreference = nil
        signal.lastUpdatedAt = now
        updatedAt = now
        if signal.successfulCleanupCount == 0 {
            cleanupSignals.removeValue(forKey: key)
        } else {
            cleanupSignals[key] = signal
        }
        appendEvent(EvolutionEvent(
            date: now,
            kind: .cleanupPreference,
            title: "已撤销清理偏好",
            detail: "\(candidate.kind.rawValue) · \(candidate.name)"
        ))
    }

    public mutating func recordModelFeedback(
        modelID: String,
        displayName: String,
        helpful: Bool,
        scope: String,
        now: Date = Date()
    ) {
        let key = Self.modelKey(modelID)
        var signal = modelSignals[key] ?? ModelLearningSignal(
            id: key,
            displayName: displayName,
            lastUpdatedAt: now
        )
        signal.displayName = displayName
        signal.lastUpdatedAt = now
        if helpful { signal.helpfulCount += 1 }
        else { signal.unhelpfulCount += 1 }
        modelSignals[key] = signal
        updatedAt = now
        appendEvent(EvolutionEvent(
            date: now,
            kind: .modelFeedback,
            title: helpful ? "模型建议有帮助" : "模型建议不准确",
            detail: "\(displayName) · \(scope)"
        ))
    }

    private mutating func appendEvent(_ event: EvolutionEvent) {
        events.insert(event, at: 0)
        events = Array(events.prefix(120))
    }

    public static func cleanupKey(for candidate: CleanupCandidate) -> String {
        "\(candidate.kind.rawValue)|\(normalized(candidate.name))|\(stableFingerprint(candidate.url.standardizedFileURL.path))"
    }

    private static func modelKey(_ modelID: String) -> String {
        let value = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "unknown-model" }
        return "model-\(stableFingerprint(value))"
    }

    private static func stableFingerprint(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func normalized(_ value: String) -> String {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
        }
        return String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
    }
}

public enum EvolutionMemoryPersistence {
    public static func load(from url: URL) throws -> EvolutionMemory {
        guard FileManager.default.fileExists(atPath: url.path) else { return EvolutionMemory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let memory = try decoder.decode(EvolutionMemory.self, from: Data(contentsOf: url))
        guard memory.schemaVersion == EvolutionMemory.schemaVersion else { return EvolutionMemory() }
        return memory
    }

    public static func save(_ memory: EvolutionMemory, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(memory)
        try data.write(to: url, options: .atomic)
    }
}
