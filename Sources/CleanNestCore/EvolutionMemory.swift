import Foundation

public enum CleanupLearningDecision: String, Codable, CaseIterable, Sendable {
    case preferCleanup
    case preferKeep
    case cleaned
}

public enum LearnedCleanupPreference: String, Codable, Hashable, Sendable {
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
        explicitPreference
    }
}

public enum EvolutionRuleState: String, Codable, CaseIterable, Sendable {
    case pending
    case enabled
    case paused
}

public enum CleanupRuleLocationLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case personalFolder
    case developerStorage
    case applicationData
    case library
    case other

    public var displayName: String {
        switch self {
        case .personalFolder: return "个人文件夹"
        case .developerStorage: return "开发工具目录"
        case .applicationData: return "应用数据目录"
        case .library: return "用户资源库"
        case .other: return "其他有界位置"
        }
    }
}

public enum CleanupRuleRiskLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case low
    case medium
    case high

    public var displayName: String {
        switch self {
        case .low: return "低风险"
        case .medium: return "中风险"
        case .high: return "高风险"
        }
    }
}

public enum CleanupRuleAgeBand: String, Codable, CaseIterable, Hashable, Sendable {
    case recent
    case settled
    case old
    case unknown

    public var displayName: String {
        switch self {
        case .recent: return "7 天内"
        case .settled: return "7–30 天"
        case .old: return "30 天以上"
        case .unknown: return "时间未知"
        }
    }
}

public struct CleanupRuleProposal: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var displayName: String
    public var kind: CleanupKind
    public var suggestedPreference: LearnedCleanupPreference
    public var state: EvolutionRuleState
    public var evidenceCount: Int
    public var reason: String
    public let createdAt: Date
    public var lastUpdatedAt: Date
    public var locationLevel: CleanupRuleLocationLevel?
    public var riskLevel: CleanupRuleRiskLevel?
    public var ageBand: CleanupRuleAgeBand?
    public var trialExpiresAt: Date?

    public init(
        id: String,
        displayName: String,
        kind: CleanupKind,
        suggestedPreference: LearnedCleanupPreference,
        state: EvolutionRuleState = .pending,
        evidenceCount: Int = 1,
        reason: String,
        createdAt: Date = Date(),
        lastUpdatedAt: Date = Date(),
        locationLevel: CleanupRuleLocationLevel? = nil,
        riskLevel: CleanupRuleRiskLevel? = nil,
        ageBand: CleanupRuleAgeBand? = nil,
        trialExpiresAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.suggestedPreference = suggestedPreference
        self.state = state
        self.evidenceCount = max(1, evidenceCount)
        self.reason = reason
        self.createdAt = createdAt
        self.lastUpdatedAt = lastUpdatedAt
        self.locationLevel = locationLevel
        self.riskLevel = riskLevel
        self.ageBand = ageBand
        self.trialExpiresAt = trialExpiresAt
    }


    public var isTrial: Bool { trialExpiresAt != nil && state == .enabled }

    public func isExpired(at now: Date = Date()) -> Bool {
        guard let trialExpiresAt else { return false }
        return trialExpiresAt <= now
    }
}

public struct CleanupRuleCluster: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: CleanupKind
    public let locationLevel: CleanupRuleLocationLevel
    public let riskLevel: CleanupRuleRiskLevel
    public let ageBand: CleanupRuleAgeBand
    public let suggestedPreference: LearnedCleanupPreference
    public let proposalIDs: [String]
    public let exampleNames: [String]
    public let evidenceCount: Int
    public let pendingCount: Int
    public let enabledCount: Int
    public let pausedCount: Int
    public let trialCount: Int
    public let expiredCount: Int
    public let lastUpdatedAt: Date

    public var proposalCount: Int { proposalIDs.count }
}

public struct CleanupRuleSortingImpact: Equatable, Sendable {
    public let matchedCount: Int
    public let movedCount: Int
    public let preferCleanupCount: Int
    public let preferKeepCount: Int

    public init(
        matchedCount: Int,
        movedCount: Int,
        preferCleanupCount: Int,
        preferKeepCount: Int
    ) {
        self.matchedCount = max(0, matchedCount)
        self.movedCount = max(0, movedCount)
        self.preferCleanupCount = max(0, preferCleanupCount)
        self.preferKeepCount = max(0, preferKeepCount)
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
        case ruleProposal
        case ruleState
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
    public static let schemaVersion = 3

    public var schemaVersion: Int
    public var cleanupSignals: [String: CleanupLearningSignal]
    public var ruleProposals: [String: CleanupRuleProposal]
    public var modelSignals: [String: ModelLearningSignal]
    public var events: [EvolutionEvent]
    public var updatedAt: Date?

    public init(
        schemaVersion: Int = EvolutionMemory.schemaVersion,
        cleanupSignals: [String: CleanupLearningSignal] = [:],
        ruleProposals: [String: CleanupRuleProposal] = [:],
        modelSignals: [String: ModelLearningSignal] = [:],
        events: [EvolutionEvent] = [],
        updatedAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.cleanupSignals = cleanupSignals
        self.ruleProposals = ruleProposals
        self.modelSignals = modelSignals
        self.events = events
        self.updatedAt = updatedAt
    }

    public var learnedCleanupCount: Int {
        cleanupSignals.values.filter { signal in
            signal.effectivePreference != nil
                && ruleProposals[signal.id]?.isExpired() != true
        }.count
    }

    public var successfulCleanupCount: Int {
        cleanupSignals.values.reduce(0) { $0 + $1.successfulCleanupCount }
    }

    public var modelFeedbackCount: Int {
        modelSignals.values.reduce(0) { $0 + $1.feedbackCount }
    }

    public var pendingRuleCount: Int {
        ruleProposals.values.filter { $0.state == .pending }.count
    }

    public var enabledRuleCount: Int {
        ruleProposals.values.filter { $0.state == .enabled && !$0.isExpired() }.count
    }

    public var trialRuleCount: Int {
        ruleProposals.values.filter { $0.isTrial && !$0.isExpired() }.count
    }

    public func expiredRuleCount(at now: Date = Date()) -> Int {
        ruleProposals.values.filter { $0.isExpired(at: now) }.count
    }

    public func ruleClusters(now: Date = Date()) -> [CleanupRuleCluster] {
        struct Key: Hashable {
            let kind: CleanupKind
            let location: CleanupRuleLocationLevel
            let risk: CleanupRuleRiskLevel
            let age: CleanupRuleAgeBand
            let preference: LearnedCleanupPreference
        }
        var grouped: [Key: [CleanupRuleProposal]] = [:]
        for proposal in ruleProposals.values {
            let key = Key(
                kind: proposal.kind,
                location: proposal.locationLevel ?? Self.defaultLocationLevel(for: proposal.kind),
                risk: proposal.riskLevel ?? Self.defaultRiskLevel(for: proposal.kind),
                age: proposal.ageBand ?? .unknown,
                preference: proposal.suggestedPreference
            )
            grouped[key, default: []].append(proposal)
        }
        return grouped.map { key, proposals in
            let sorted = proposals.sorted {
                if $0.lastUpdatedAt == $1.lastUpdatedAt { return $0.id < $1.id }
                return $0.lastUpdatedAt > $1.lastUpdatedAt
            }
            return CleanupRuleCluster(
                id: [
                    key.kind.rawValue,
                    key.location.rawValue,
                    key.risk.rawValue,
                    key.age.rawValue,
                    key.preference.rawValue
                ].joined(separator: "|"),
                kind: key.kind,
                locationLevel: key.location,
                riskLevel: key.risk,
                ageBand: key.age,
                suggestedPreference: key.preference,
                proposalIDs: sorted.map(\.id),
                exampleNames: Array(sorted.prefix(3).map(\.displayName)),
                evidenceCount: sorted.reduce(0) { $0 + $1.evidenceCount },
                pendingCount: sorted.filter { $0.state == .pending }.count,
                enabledCount: sorted.filter { $0.state == .enabled && !$0.isExpired(at: now) }.count,
                pausedCount: sorted.filter { $0.state == .paused }.count,
                trialCount: sorted.filter { $0.isTrial && !$0.isExpired(at: now) }.count,
                expiredCount: sorted.filter { $0.isExpired(at: now) }.count,
                lastUpdatedAt: sorted.first?.lastUpdatedAt ?? .distantPast
            )
        }.sorted {
            if $0.pendingCount != $1.pendingCount { return $0.pendingCount > $1.pendingCount }
            if $0.riskLevel != $1.riskLevel {
                let order: [CleanupRuleRiskLevel: Int] = [.high: 0, .medium: 1, .low: 2]
                return order[$0.riskLevel, default: 3] < order[$1.riskLevel, default: 3]
            }
            if $0.lastUpdatedAt != $1.lastUpdatedAt { return $0.lastUpdatedAt > $1.lastUpdatedAt }
            return $0.id < $1.id
        }
    }

    public func sortingImpact(on candidates: [CleanupCandidate]) -> CleanupRuleSortingImpact {
        let preferences = Dictionary(uniqueKeysWithValues: candidates.compactMap { candidate in
            cleanupPreference(for: candidate).map { (candidate.id, $0) }
        })
        var moved = 0
        for kind in CleanupKind.allCases {
            let original = candidates.filter { $0.kind == kind }
            let oldPositions = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($1.id, $0) })
            let sorted = original.sorted { lhs, rhs in
                let left = Self.preferenceRank(preferences[lhs.id])
                let right = Self.preferenceRank(preferences[rhs.id])
                if left != right { return left < right }
                return oldPositions[lhs.id, default: .max] < oldPositions[rhs.id, default: .max]
            }
            moved += sorted.enumerated().reduce(0) { partial, pair in
                partial + (oldPositions[pair.element.id] == pair.offset ? 0 : 1)
            }
        }
        return CleanupRuleSortingImpact(
            matchedCount: preferences.count,
            movedCount: moved,
            preferCleanupCount: preferences.values.filter { $0 == .preferCleanup }.count,
            preferKeepCount: preferences.values.filter { $0 == .preferKeep }.count
        )
    }

    public var sortedRuleProposals: [CleanupRuleProposal] {
        ruleProposals.values.sorted {
            if $0.state != $1.state {
                let order: [EvolutionRuleState: Int] = [.pending: 0, .enabled: 1, .paused: 2]
                return (order[$0.state] ?? 3) < (order[$1.state] ?? 3)
            }
            if $0.lastUpdatedAt == $1.lastUpdatedAt { return $0.displayName < $1.displayName }
            return $0.lastUpdatedAt > $1.lastUpdatedAt
        }
    }

    public var sortedCleanupSignals: [CleanupLearningSignal] {
        cleanupSignals.values
            .filter { signal in
                signal.effectivePreference != nil
                    && ruleProposals[signal.id]?.isExpired() != true
            }
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

    public func cleanupPreference(
        for candidate: CleanupCandidate,
        now: Date = Date()
    ) -> LearnedCleanupPreference? {
        let key = Self.cleanupKey(for: candidate)
        if ruleProposals[key]?.isExpired(at: now) == true { return nil }
        return cleanupSignals[key]?.effectivePreference
    }

    public func ruleProposal(for candidate: CleanupCandidate) -> CleanupRuleProposal? {
        ruleProposals[Self.cleanupKey(for: candidate)]
    }

    public mutating func proposeCleanupPreference(
        for candidate: CleanupCandidate,
        preference: LearnedCleanupPreference,
        reason: String,
        now: Date = Date()
    ) {
        let key = Self.cleanupKey(for: candidate)
        var proposal = ruleProposals[key] ?? CleanupRuleProposal(
            id: key,
            displayName: candidate.name,
            kind: candidate.kind,
            suggestedPreference: preference,
            reason: reason,
            createdAt: now,
            lastUpdatedAt: now
        )
        if ruleProposals[key] != nil { proposal.evidenceCount += 1 }
        proposal.displayName = candidate.name
        proposal.kind = candidate.kind
        proposal.suggestedPreference = preference
        proposal.state = .pending
        proposal.reason = reason
        proposal.lastUpdatedAt = now
        proposal.locationLevel = Self.locationLevel(for: candidate)
        proposal.riskLevel = Self.defaultRiskLevel(for: candidate.kind)
        proposal.ageBand = Self.ageBand(for: candidate, now: now)
        proposal.trialExpiresAt = nil
        ruleProposals[key] = proposal
        updatedAt = now
        appendEvent(EvolutionEvent(
            date: now,
            kind: .ruleProposal,
            title: "生成待审核规则",
            detail: "\(candidate.kind.rawValue) · \(candidate.name)"
        ))
    }

    public mutating func enableRuleProposal(id: String, now: Date = Date()) {
        guard var proposal = ruleProposals[id] else { return }
        proposal.state = .enabled
        proposal.lastUpdatedAt = now
        proposal.trialExpiresAt = nil
        ruleProposals[id] = proposal

        var signal = cleanupSignals[id] ?? CleanupLearningSignal(
            id: id,
            displayName: proposal.displayName,
            kind: proposal.kind,
            lastUpdatedAt: now
        )
        signal.displayName = proposal.displayName
        signal.kind = proposal.kind
        signal.explicitPreference = proposal.suggestedPreference
        signal.explicitRevisionCount += 1
        signal.lastUpdatedAt = now
        cleanupSignals[id] = signal
        updatedAt = now
        appendEvent(EvolutionEvent(
            date: now,
            kind: .ruleState,
            title: "已启用学习规则",
            detail: "\(proposal.kind.rawValue) · \(proposal.displayName)"
        ))
    }

    public mutating func pauseRuleProposal(id: String, now: Date = Date()) {
        guard var proposal = ruleProposals[id] else { return }
        proposal.state = .paused
        proposal.lastUpdatedAt = now
        ruleProposals[id] = proposal
        clearPreference(signalID: id, now: now)
        appendEvent(EvolutionEvent(
            date: now,
            kind: .ruleState,
            title: "已暂停学习规则",
            detail: "\(proposal.kind.rawValue) · \(proposal.displayName)"
        ))
    }

    public mutating func removeRuleProposal(id: String, now: Date = Date()) {
        guard let proposal = ruleProposals.removeValue(forKey: id) else { return }
        clearPreference(signalID: id, now: now)
        appendEvent(EvolutionEvent(
            date: now,
            kind: .ruleState,
            title: "已撤销学习规则",
            detail: "\(proposal.kind.rawValue) · \(proposal.displayName)"
        ))
    }

    public mutating func enableRuleProposals(ids: [String], now: Date = Date()) {
        for id in Set(ids) { enableRuleProposal(id: id, now: now) }
    }

    public mutating func startTrialRuleProposals(
        ids: [String],
        duration: TimeInterval = 7 * 86_400,
        now: Date = Date()
    ) {
        let expiresAt = now.addingTimeInterval(max(60, duration))
        for id in Set(ids) {
            enableRuleProposal(id: id, now: now)
            guard var proposal = ruleProposals[id] else { continue }
            proposal.trialExpiresAt = expiresAt
            proposal.lastUpdatedAt = now
            ruleProposals[id] = proposal
        }
        appendEvent(EvolutionEvent(
            date: now,
            kind: .ruleState,
            title: "开始限时试用规则",
            detail: "\(Set(ids).count) 条规则将在到期后自动暂停"
        ))
    }

    public mutating func pauseRuleProposals(ids: [String], now: Date = Date()) {
        for id in Set(ids) { pauseRuleProposal(id: id, now: now) }
    }

    public mutating func removeRuleProposals(ids: [String], now: Date = Date()) {
        for id in Set(ids) { removeRuleProposal(id: id, now: now) }
    }

    @discardableResult
    public mutating func expireTrials(now: Date = Date()) -> Int {
        let expiredIDs = ruleProposals.values.filter {
            $0.state == .enabled && $0.isExpired(at: now)
        }.map(\.id)
        for id in expiredIDs { pauseRuleProposal(id: id, now: now) }
        if !expiredIDs.isEmpty {
            appendEvent(EvolutionEvent(
                date: now,
                kind: .ruleState,
                title: "试用规则已到期并暂停",
                detail: "\(expiredIDs.count) 条规则不再影响排序"
            ))
        }
        return expiredIDs.count
    }

    @discardableResult
    public mutating func removeExpiredRuleProposals(now: Date = Date()) -> Int {
        let expiredIDs = ruleProposals.values.filter { $0.isExpired(at: now) }.map(\.id)
        removeRuleProposals(ids: expiredIDs, now: now)
        return expiredIDs.count
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
        if decision == .cleaned {
            recordSuccessfulCleanupEvidence(for: candidate, now: now)
        }
    }

    public mutating func clearExplicitPreference(
        for candidate: CleanupCandidate,
        now: Date = Date()
    ) {
        let key = Self.cleanupKey(for: candidate)
        guard var signal = cleanupSignals[key], signal.explicitPreference != nil else { return }
        signal.explicitPreference = nil
        cleanupSignals[key] = signal
        clearPreference(signalID: key, now: now)
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

    private mutating func recordSuccessfulCleanupEvidence(
        for candidate: CleanupCandidate,
        now: Date
    ) {
        let key = Self.cleanupKey(for: candidate)
        var proposal = ruleProposals[key] ?? CleanupRuleProposal(
            id: key,
            displayName: candidate.name,
            kind: candidate.kind,
            suggestedPreference: .preferCleanup,
            reason: "你曾确认并成功把这个项目移到废纸篓。",
            createdAt: now,
            lastUpdatedAt: now
        )
        if ruleProposals[key] != nil { proposal.evidenceCount += 1 }
        proposal.displayName = candidate.name
        proposal.kind = candidate.kind
        proposal.suggestedPreference = .preferCleanup
        proposal.reason = "你曾确认并成功把这个项目移到废纸篓。"
        proposal.lastUpdatedAt = now
        proposal.locationLevel = Self.locationLevel(for: candidate)
        proposal.riskLevel = Self.defaultRiskLevel(for: candidate.kind)
        proposal.ageBand = Self.ageBand(for: candidate, now: now)
        ruleProposals[key] = proposal
    }

    private mutating func clearPreference(signalID: String, now: Date) {
        guard var signal = cleanupSignals[signalID] else { return }
        signal.explicitPreference = nil
        signal.lastUpdatedAt = now
        updatedAt = now
        if signal.successfulCleanupCount == 0 {
            cleanupSignals.removeValue(forKey: signalID)
        } else {
            cleanupSignals[signalID] = signal
        }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case cleanupSignals
        case ruleProposals
        case modelSignals
        case events
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        cleanupSignals = try container.decodeIfPresent(
            [String: CleanupLearningSignal].self,
            forKey: .cleanupSignals
        ) ?? [:]
        ruleProposals = try container.decodeIfPresent(
            [String: CleanupRuleProposal].self,
            forKey: .ruleProposals
        ) ?? [:]
        modelSignals = try container.decodeIfPresent(
            [String: ModelLearningSignal].self,
            forKey: .modelSignals
        ) ?? [:]
        events = try container.decodeIfPresent([EvolutionEvent].self, forKey: .events) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(cleanupSignals, forKey: .cleanupSignals)
        try container.encode(ruleProposals, forKey: .ruleProposals)
        try container.encode(modelSignals, forKey: .modelSignals)
        try container.encode(events, forKey: .events)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
    }

    public mutating func migrateToCurrentSchema() {
        guard schemaVersion < Self.schemaVersion else { return }
        let now = updatedAt ?? Date()
        for (key, signal) in cleanupSignals where ruleProposals[key] == nil {
            let preference = signal.explicitPreference ?? .preferCleanup
            let state: EvolutionRuleState = signal.explicitPreference == nil ? .pending : .enabled
            let reason = signal.explicitPreference == nil
                ? "旧版本记录了成功清理；请审核后再启用。"
                : "由旧版本中你明确设置的清理偏好迁移。"
            ruleProposals[key] = CleanupRuleProposal(
                id: key,
                displayName: signal.displayName,
                kind: signal.kind,
                suggestedPreference: preference,
                state: state,
                evidenceCount: max(1, signal.explicitRevisionCount + signal.successfulCleanupCount),
                reason: reason,
                createdAt: signal.lastUpdatedAt,
                lastUpdatedAt: signal.lastUpdatedAt
            )
        }
        schemaVersion = Self.schemaVersion
        updatedAt = now
    }

    public static func cleanupKey(for candidate: CleanupCandidate) -> String {
        "\(candidate.kind.rawValue)|\(normalized(candidate.name))|\(stableFingerprint(candidate.url.standardizedFileURL.path))"
    }

    private static func locationLevel(for candidate: CleanupCandidate) -> CleanupRuleLocationLevel {
        switch candidate.kind {
        case .developer, .packageManager:
            return .developerStorage
        case .appCache, .leftover:
            return .applicationData
        case .installer, .archive, .screenshot, .image, .video, .audio, .duplicate:
            return .personalFolder
        case .logs:
            return .library
        }
    }

    private static func defaultLocationLevel(for kind: CleanupKind) -> CleanupRuleLocationLevel {
        switch kind {
        case .developer, .packageManager: return .developerStorage
        case .appCache, .leftover: return .applicationData
        case .installer, .archive, .screenshot, .image, .video, .audio, .duplicate:
            return .personalFolder
        case .logs: return .library
        }
    }

    private static func defaultRiskLevel(for kind: CleanupKind) -> CleanupRuleRiskLevel {
        switch kind {
        case .developer, .packageManager, .logs, .appCache:
            return .low
        case .installer, .archive, .screenshot:
            return .medium
        case .image, .video, .audio, .duplicate, .leftover:
            return .high
        }
    }

    private static func ageBand(for candidate: CleanupCandidate, now: Date) -> CleanupRuleAgeBand {
        guard let modifiedAt = candidate.modifiedAt else { return .unknown }
        let age = max(0, now.timeIntervalSince(modifiedAt))
        if age < 7 * 86_400 { return .recent }
        if age < 30 * 86_400 { return .settled }
        return .old
    }

    private static func preferenceRank(_ preference: LearnedCleanupPreference?) -> Int {
        switch preference {
        case .preferCleanup: return 0
        case nil: return 1
        case .preferKeep: return 2
        }
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
    /// A one-time copy of the last pre-v3 learning file. CleanNest 0.6.5 does
    /// not understand trial expiry metadata, so keeping this file is safer
    /// than pretending a v3 rule set can be downgraded losslessly.
    public static func rollbackBackupURL(for url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("pre-v3.json")
    }

    public static func load(from url: URL) throws -> EvolutionMemory {
        guard FileManager.default.fileExists(atPath: url.path) else { return EvolutionMemory() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var memory = try decoder.decode(EvolutionMemory.self, from: Data(contentsOf: url))
        guard (1...EvolutionMemory.schemaVersion).contains(memory.schemaVersion) else {
            return EvolutionMemory()
        }
        memory.migrateToCurrentSchema()
        return memory
    }

    public static func save(_ memory: EvolutionMemory, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try preserveRollbackBackupIfNeeded(at: url)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(memory)
        try data.write(to: url, options: .atomic)
    }

    private static func preserveRollbackBackupIfNeeded(at url: URL) throws {
        let backupURL = rollbackBackupURL(for: url)
        guard !FileManager.default.fileExists(atPath: backupURL.path),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schemaVersion = root["schemaVersion"] as? Int,
              (1..<EvolutionMemory.schemaVersion).contains(schemaVersion) else { return }
        try data.write(to: backupURL, options: .atomic)
    }
}
