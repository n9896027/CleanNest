import Foundation
import XCTest
import CleanNestCore
import CleanNestMutation

final class MigrationCompatibilityTests: XCTestCase {
    func test065MenuBarSettingsUpgradeAndRemainReadableByLegacyShape() throws {
        let legacyData = Data(#"{"isEnabled":true,"metrics":[{"metric":"cpu","isEnabled":true,"style":"text"}]}"#.utf8)

        let upgraded = try JSONDecoder().decode(MenuBarMonitorConfiguration.self, from: legacyData).normalized

        XCTAssertTrue(upgraded.isEnabled)
        XCTAssertTrue(upgraded.preference(for: .cpu).isEnabled)
        XCTAssertEqual(upgraded.presentationMode, .compact)
        XCTAssertEqual(upgraded.refreshInterval, .twoSeconds)
        XCTAssertEqual(upgraded.networkMode, .physicalAggregate)
        XCTAssertEqual(Set(upgraded.metrics.map(\.metric)), Set(MenuBarMetric.allCases))

        let currentData = try JSONEncoder().encode(upgraded)
        let legacyReader = try JSONDecoder().decode(LegacyMenuBarConfiguration.self, from: currentData)
        XCTAssertTrue(legacyReader.isEnabled)
        XCTAssertTrue(legacyReader.metrics.contains { $0.metric == .cpu && $0.isEnabled })
    }

    func test065ActivitiesUpgradeWithoutInventingCleanupResultsAndRollbackIgnoresNewField() throws {
        let legacy = LegacyActivityEntry(
            id: UUID(),
            date: Date(timeIntervalSinceReferenceDate: 123_456),
            title: "清理空间",
            detail: "旧版记录",
            outcome: .success,
            affectedItems: 3,
            bytes: 8_192,
            category: .cleanup
        )
        let legacyData = try JSONEncoder().encode(legacy)

        let upgraded = try JSONDecoder().decode(ActivityEntry.self, from: legacyData)

        XCTAssertEqual(upgraded.effectiveCategory, .cleanup)
        XCTAssertNil(upgraded.cleanupResult)
        XCTAssertEqual(ActivityStatistics(entries: [upgraded]).processedBytes, 8_192)

        let current = ActivityEntry(
            id: legacy.id,
            date: legacy.date,
            title: legacy.title,
            detail: legacy.detail,
            outcome: legacy.outcome,
            affectedItems: legacy.affectedItems,
            bytes: legacy.bytes,
            category: legacy.category,
            cleanupResult: CleanupActivityResult(
                candidateBytes: 12_288,
                trashedBytes: 8_192,
                apfsFreeBytesDelta: 4_096
            )
        )
        let rollbackDecoded = try JSONDecoder().decode(
            LegacyActivityEntry.self,
            from: JSONEncoder().encode(current)
        )
        XCTAssertEqual(rollbackDecoded, legacy)
    }

    func test065DiskIndexMigratesInPlaceAndFutureSchemaFailsClosed() throws {
        let directory = try temporaryDirectory(named: "DiskCacheMigration")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cacheURL = directory.appendingPathComponent("disk-scan-cache.json")
        let sampledMilliseconds = 1_700_000_000_000.0
        let legacyObject: [String: Any] = [
            "schemaVersion": 1,
            "roots": [
                "root-fingerprint": [
                    "id": "root-fingerprint",
                    "generatedAt": sampledMilliseconds,
                    "entries": [[
                        "id": "entry-fingerprint",
                        "name": "Caches",
                        "metadataSignature": "legacy",
                        "allocatedBytes": 4_096,
                        "isDirectory": true,
                        "sampledAt": sampledMilliseconds
                    ]]
                ]
            ]
        ]
        try JSONSerialization.data(withJSONObject: legacyObject, options: [.sortedKeys])
            .write(to: cacheURL, options: .atomic)

        let migrated = try DiskScanCachePersistence.load(from: cacheURL)

        XCTAssertEqual(migrated.schemaVersion, DiskScanCacheStore.schemaVersion)
        XCTAssertEqual(migrated.roots["root-fingerprint"]?.entries.first?.allocatedBytes, 4_096)
        XCTAssertNil(migrated.roots["root-fingerprint"]?.entries.first?.traversal)

        var future = legacyObject
        future["schemaVersion"] = DiskScanCacheStore.schemaVersion + 1
        try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
            .write(to: cacheURL, options: .atomic)
        XCTAssertTrue(try DiskScanCachePersistence.load(from: cacheURL).roots.isEmpty)
    }

    func test065LearningRulesUpgradeWithBackupAndDowngradeFailsClosed() throws {
        let directory = try temporaryDirectory(named: "EvolutionMigration")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("evolution-memory.json")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let rule = LegacyCleanupRuleProposal(
            id: "package|legacy",
            displayName: "content-v2",
            kind: .packageManager,
            suggestedPreference: .preferCleanup,
            state: .enabled,
            evidenceCount: 2,
            reason: "旧版明确选择",
            createdAt: date,
            lastUpdatedAt: date
        )
        let legacy = LegacyEvolutionMemory(
            schemaVersion: 2,
            cleanupSignals: [
                rule.id: CleanupLearningSignal(
                    id: rule.id,
                    displayName: rule.displayName,
                    kind: rule.kind,
                    explicitPreference: .preferCleanup,
                    explicitRevisionCount: 1,
                    successfulCleanupCount: 1,
                    lastUpdatedAt: date
                )
            ],
            ruleProposals: [rule.id: rule],
            modelSignals: [:],
            events: [],
            updatedAt: date
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let legacyData = try encoder.encode(legacy)
        try legacyData.write(to: url, options: .atomic)

        let upgraded = try EvolutionMemoryPersistence.load(from: url)

        XCTAssertEqual(upgraded.schemaVersion, EvolutionMemory.schemaVersion)
        XCTAssertEqual(upgraded.ruleProposals[rule.id]?.state, .enabled)
        XCTAssertNil(upgraded.ruleProposals[rule.id]?.trialExpiresAt)

        try EvolutionMemoryPersistence.save(upgraded, to: url)
        let backupURL = EvolutionMemoryPersistence.rollbackBackupURL(for: url)
        XCTAssertEqual(try Data(contentsOf: backupURL), legacyData)
        XCTAssertEqual(
            try decodeLegacyEvolution(at: backupURL).ruleProposals[rule.id],
            rule
        )

        let current = try decodeLegacyEvolution(at: url)
        XCTAssertEqual(current.schemaVersion, 3)
        XCTAssertFalse((1...2).contains(current.schemaVersion))
    }

    func test065AgentObservationAndRecoveryManifestRoundTripBothDirections() throws {
        let observation = AgentWorkspaceObservation(
            capturedAt: Date(timeIntervalSinceReferenceDate: 456_789),
            allocatedBytesByAgent: ["codex": 8_192],
            allocatedBytesByArtifact: ["codex:caches": 8_192]
        )
        let observationData = try JSONEncoder().encode(observation)
        XCTAssertEqual(
            try JSONDecoder().decode(AgentWorkspaceObservation.self, from: observationData),
            observation
        )

        let identity = AgentWorkspaceFileIdentity(
            deviceID: 1,
            fileID: 2,
            ownerUserID: 501,
            logicalBytes: 4_096,
            allocatedBytes: 4_096,
            modificationSeconds: 1_700_000_000,
            modificationNanoseconds: 0
        )
        let candidate = AgentWorkspaceActionCandidate(
            id: "legacy-candidate",
            provider: .codex,
            kind: .caches,
            path: "/Users/example/.codex/cache/old.bin",
            identity: identity,
            scannedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let item = AgentWorkspaceRecoveryItem(
            candidate: candidate,
            archiveRelativePath: "files/000001.bin",
            pendingFileName: "000001.bin"
        )
        let record = LegacyRecoveryRecord(
            id: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            completedAt: Date(timeIntervalSince1970: 1_700_000_300),
            restoredAt: nil,
            status: .available,
            items: [item],
            originalAllocatedBytes: 4_096,
            originalLogicalBytes: 4_096,
            archiveAllocatedBytes: 2_048,
            archiveSHA256: String(repeating: "a", count: 64),
            removedOriginalBytes: 4_096,
            pendingOriginalBytes: 0,
            apfsFreeBefore: 1_000_000,
            apfsFreeAfter: 1_004_096,
            apfsFreeAfterRestore: nil,
            diagnostic: "legacy"
        )
        let isoEncoder = JSONEncoder()
        isoEncoder.dateEncodingStrategy = .iso8601
        let isoDecoder = JSONDecoder()
        isoDecoder.dateDecodingStrategy = .iso8601
        let upgradedRecord = try isoDecoder.decode(
            AgentWorkspaceRecoveryRecord.self,
            from: isoEncoder.encode(record)
        )
        XCTAssertEqual(upgradedRecord.id, record.id)
        XCTAssertEqual(upgradedRecord.items, record.items)

        let rollback = try isoDecoder.decode(
            LegacyRecoveryRecord.self,
            from: isoEncoder.encode(upgradedRecord)
        )
        XCTAssertEqual(rollback, record)
    }

    func testMetricsSchemaRemainsCompatibleAndLowDiskBackupFailsBeforeMutation() async throws {
        XCTAssertEqual(MetricsStore.schemaVersion, 1)
        let directory = try temporaryDirectory(named: "MetricsMigration")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MetricsStore(databaseURL: directory.appendingPathComponent("metrics.sqlite3"))
        try await store.prepare()
        let metricCount = try await store.count()
        XCTAssertEqual(metricCount, 0)

        let logicalBytes: Int64 = 256 * 1_024 * 1_024
        let required = AgentWorkspaceBackupCapacityPolicy.requiredFreeBytes(
            forLogicalBytes: logicalBytes
        )
        XCTAssertFalse(AgentWorkspaceBackupCapacityPolicy.hasCapacity(
            logicalBytes: logicalBytes,
            availableBytes: required - 1
        ))
        XCTAssertTrue(AgentWorkspaceBackupCapacityPolicy.hasCapacity(
            logicalBytes: logicalBytes,
            availableBytes: required
        ))
        XCTAssertEqual(
            AgentWorkspaceBackupCapacityPolicy.requiredFreeBytes(forLogicalBytes: Int64.max),
            Int64.max
        )
    }

    private func temporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNest-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func decodeLegacyEvolution(at url: URL) throws -> LegacyEvolutionMemory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LegacyEvolutionMemory.self, from: Data(contentsOf: url))
    }
}

private struct LegacyMenuBarConfiguration: Codable {
    let isEnabled: Bool
    let metrics: [MenuBarMetricPreference]
}

private struct LegacyActivityEntry: Codable, Equatable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let outcome: ActivityEntry.Outcome
    let affectedItems: Int
    let bytes: Int64
    let category: ActivityEntry.Category?
}

private struct LegacyCleanupRuleProposal: Codable, Equatable {
    let id: String
    var displayName: String
    var kind: CleanupKind
    var suggestedPreference: LearnedCleanupPreference
    var state: EvolutionRuleState
    var evidenceCount: Int
    var reason: String
    let createdAt: Date
    var lastUpdatedAt: Date
}

private struct LegacyEvolutionMemory: Codable {
    var schemaVersion: Int
    var cleanupSignals: [String: CleanupLearningSignal]
    var ruleProposals: [String: LegacyCleanupRuleProposal]
    var modelSignals: [String: ModelLearningSignal]
    var events: [EvolutionEvent]
    var updatedAt: Date?
}

private struct LegacyRecoveryRecord: Codable, Equatable {
    let id: UUID
    let createdAt: Date
    var completedAt: Date?
    var restoredAt: Date?
    var status: AgentWorkspaceRecoveryStatus
    let items: [AgentWorkspaceRecoveryItem]
    let originalAllocatedBytes: Int64
    let originalLogicalBytes: Int64
    var archiveAllocatedBytes: Int64
    var archiveSHA256: String?
    var removedOriginalBytes: Int64
    var pendingOriginalBytes: Int64
    let apfsFreeBefore: Int64
    var apfsFreeAfter: Int64?
    var apfsFreeAfterRestore: Int64?
    var diagnostic: String
}
