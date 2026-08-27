import Foundation

public enum CleanNestScannerService {
    public static let bundleIdentifier = "com.zone.cleannest.scanner"
    public static let protocolVersion = 4
}

/// The XPC boundary intentionally transports only JSON `Data`. This keeps the
/// exported Objective-C surface small and avoids granting arbitrary secure-
/// coding classes to the connection.
@objc public protocol CleanNestScannerXPCProtocol {
    func protocolVersion(withReply reply: @escaping (Int) -> Void)
    func scanCleanup(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func scanDisk(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func scanAgentWorkspace(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
    func progress(for requestID: String, withReply reply: @escaping (Data?) -> Void)
    func cancel(requestID: String, withReply reply: @escaping () -> Void)
}

public enum ScannerOperationKind: String, Codable, Sendable {
    case cleanup
    case disk
    case agentWorkspace
}

public enum ScannerProgressStage: String, Codable, Sendable {
    case preparing
    case cleanupCaches
    case cleanupPersonalFiles
    case diskContents
    case diskEvidence
    case agentWorkspaceMetadata
    case completed
}

public struct AgentWorkspaceScannerRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let homeDirectory: URL
    public let previousObservation: AgentWorkspaceObservation?
    public let ruleCatalog: AgentRuleCatalog

    public init(
        requestID: String = UUID().uuidString,
        homeDirectory: URL,
        previousObservation: AgentWorkspaceObservation?,
        ruleCatalog: AgentRuleCatalog = .builtIn
    ) {
        self.requestID = requestID
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.previousObservation = previousObservation
        self.ruleCatalog = ruleCatalog
    }
}

public struct AgentWorkspaceScannerResponse: Codable, Equatable, Sendable {
    public let requestID: String
    public let result: AgentWorkspaceScanResult
    public let elapsedSeconds: Double

    public init(requestID: String, result: AgentWorkspaceScanResult, elapsedSeconds: Double) {
        self.requestID = requestID
        self.result = result
        self.elapsedSeconds = elapsedSeconds
    }
}

public struct ScannerServiceProgress: Codable, Equatable, Sendable {
    public let requestID: String
    public let operation: ScannerOperationKind
    public let stage: ScannerProgressStage
    public let completed: Int
    public let total: Int
    public let currentName: String
    public let partialReport: DiskReport?
    public let cacheHitCount: Int
    public let scannedCount: Int

    public init(
        requestID: String,
        operation: ScannerOperationKind,
        stage: ScannerProgressStage,
        completed: Int = 0,
        total: Int = 0,
        currentName: String = "",
        partialReport: DiskReport? = nil,
        cacheHitCount: Int = 0,
        scannedCount: Int = 0
    ) {
        self.requestID = requestID
        self.operation = operation
        self.stage = stage
        self.completed = completed
        self.total = total
        self.currentName = String(currentName.prefix(160))
        self.partialReport = partialReport
        self.cacheHitCount = cacheHitCount
        self.scannedCount = scannedCount
    }
}

public struct CleanupScannerRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let homeDirectory: URL
    public let includeApplicationCaches: Bool
    public let includeMediaAndDuplicates: Bool
    public let developerMode: Bool

    public init(
        requestID: String = UUID().uuidString,
        homeDirectory: URL,
        includeApplicationCaches: Bool,
        includeMediaAndDuplicates: Bool,
        developerMode: Bool
    ) {
        self.requestID = requestID
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.includeApplicationCaches = includeApplicationCaches
        self.includeMediaAndDuplicates = includeMediaAndDuplicates
        self.developerMode = developerMode
    }
}

public struct CleanupScannerResponse: Codable, Equatable, Sendable {
    public let requestID: String
    public let candidates: [CleanupCandidate]
    public let insights: CleanupScanInsights
    public let session: CleanupScanSession
    public let elapsedSeconds: Double

    public init(
        requestID: String,
        candidates: [CleanupCandidate],
        insights: CleanupScanInsights,
        session: CleanupScanSession,
        elapsedSeconds: Double
    ) {
        self.requestID = requestID
        self.candidates = candidates
        self.insights = insights
        self.session = session
        self.elapsedSeconds = elapsedSeconds
    }
}

public struct DiskScannerRequest: Codable, Equatable, Sendable {
    public let requestID: String
    public let root: URL
    public let homeDirectory: URL
    public let cache: DiskScanCacheStore
    public let mode: DiskScanMode
    public let previousEvidence: DiskEvidenceReport?

    public init(
        requestID: String = UUID().uuidString,
        root: URL,
        homeDirectory: URL,
        cache: DiskScanCacheStore,
        mode: DiskScanMode,
        previousEvidence: DiskEvidenceReport?
    ) {
        self.requestID = requestID
        self.root = root.standardizedFileURL
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.cache = cache
        self.mode = mode
        self.previousEvidence = previousEvidence
    }
}

public struct DiskScannerResponse: Codable, Equatable, Sendable {
    public let requestID: String
    public let outcome: DiskScanOutcome
    public let evidence: DiskEvidenceReport

    public init(requestID: String, outcome: DiskScanOutcome, evidence: DiskEvidenceReport) {
        self.requestID = requestID
        self.outcome = outcome
        self.evidence = evidence
    }
}

public enum ScannerServiceCodec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        // Keep Foundation's full-precision reference-date representation.
        // Cleanup evidence compares file identities exactly before mutation;
        // millisecond rounding would make an unchanged file look replaced.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return try decoder.decode(type, from: data)
    }
}
