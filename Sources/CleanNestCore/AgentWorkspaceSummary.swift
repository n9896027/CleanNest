import Foundation

/// A deliberately small, non-actionable cache for cold start and page return.
///
/// Unlike `AgentWorkspaceSnapshot`, this type cannot carry paths, open-file
/// details, file identities, or mutation candidates. A cached summary is only
/// historical context; every action still requires a fresh complete scan.
public struct AgentWorkspaceSummary: Codable, Equatable, Sendable {
    public struct ProviderSummary: Identifiable, Codable, Equatable, Sendable {
        public let provider: AgentWorkspaceProvider
        public let allocatedBytes: Int64
        public let fileCount: Int
        public let activeFileCount: Int
        public let previewBytes: Int64
        public let isComplete: Bool

        public var id: AgentWorkspaceProvider { provider }

        public init(
            provider: AgentWorkspaceProvider,
            allocatedBytes: Int64,
            fileCount: Int,
            activeFileCount: Int,
            previewBytes: Int64,
            isComplete: Bool
        ) {
            self.provider = provider
            self.allocatedBytes = max(0, allocatedBytes)
            self.fileCount = max(0, fileCount)
            self.activeFileCount = max(0, activeFileCount)
            self.previewBytes = max(0, previewBytes)
            self.isComplete = isComplete
        }
    }

    public let capturedAt: Date
    public let providers: [ProviderSummary]
    public let alertCount: Int
    public let isComplete: Bool

    public var allocatedBytes: Int64 {
        providers.reduce(0) { partial, provider in
            let bytes = max(0, provider.allocatedBytes)
            return partial > Int64.max - bytes ? Int64.max : partial + bytes
        }
    }

    public var fileCount: Int {
        providers.reduce(0) { partial, provider in
            let count = max(0, provider.fileCount)
            return partial > Int.max - count ? Int.max : partial + count
        }
    }

    public var activeFileCount: Int {
        providers.reduce(0) { partial, provider in
            let count = max(0, provider.activeFileCount)
            return partial > Int.max - count ? Int.max : partial + count
        }
    }

    public init(
        capturedAt: Date,
        providers: [ProviderSummary],
        alertCount: Int,
        isComplete: Bool
    ) {
        self.capturedAt = capturedAt
        self.providers = providers
        self.alertCount = max(0, alertCount)
        self.isComplete = isComplete
    }

    public init(snapshot: AgentWorkspaceSnapshot) {
        self.init(
            capturedAt: snapshot.capturedAt,
            providers: snapshot.detectedAgents.map { agent in
                ProviderSummary(
                    provider: agent.provider,
                    allocatedBytes: agent.allocatedBytes,
                    fileCount: agent.fileCount,
                    activeFileCount: agent.activeFileCount,
                    previewBytes: agent.previewBytes,
                    isComplete: agent.isComplete
                )
            },
            alertCount: snapshot.alerts.count,
            isComplete: snapshot.isComplete
        )
    }
}

public enum AgentWorkspaceSummaryPersistence {
    public static func load(from url: URL) throws -> AgentWorkspaceSummary? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            AgentWorkspaceSummary.self,
            from: Data(contentsOf: url, options: [.mappedIfSafe])
        )
    }

    public static func save(_ summary: AgentWorkspaceSummary, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(to: url, options: .atomic)
    }
}
