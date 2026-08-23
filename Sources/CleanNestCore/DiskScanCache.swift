import Foundation

public struct DiskScanCacheEntry: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let metadataSignature: String
    public let allocatedBytes: Int64
    public let isDirectory: Bool
    public let sampledAt: Date

    public init(
        id: String,
        name: String,
        metadataSignature: String,
        allocatedBytes: Int64,
        isDirectory: Bool,
        sampledAt: Date
    ) {
        self.id = id
        self.name = name
        self.metadataSignature = metadataSignature
        self.allocatedBytes = allocatedBytes
        self.isDirectory = isDirectory
        self.sampledAt = sampledAt
    }
}

public struct DiskScanCacheRoot: Codable, Equatable, Sendable {
    public let id: String
    public let generatedAt: Date
    public let entries: [DiskScanCacheEntry]

    public init(id: String, generatedAt: Date, entries: [DiskScanCacheEntry]) {
        self.id = id
        self.generatedAt = generatedAt
        self.entries = entries
    }
}

/// A bounded, local-only index used to avoid recomputing unchanged top-level
/// subtrees. It stores no file contents and no absolute paths.
public struct DiskScanCacheStore: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let maximumRoots = 12

    public var schemaVersion: Int
    public private(set) var roots: [String: DiskScanCacheRoot]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        roots: [String: DiskScanCacheRoot] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.roots = roots
    }

    public func root(for url: URL) -> DiskScanCacheRoot? {
        roots[DiskEvidenceIndexer.fingerprint(for: url)]
    }

    public mutating func replaceRoot(_ root: DiskScanCacheRoot) {
        roots[root.id] = root
        guard roots.count > Self.maximumRoots else { return }
        let retained = roots.values
            .sorted {
                if $0.generatedAt == $1.generatedAt { return $0.id < $1.id }
                return $0.generatedAt > $1.generatedAt
            }
            .prefix(Self.maximumRoots)
        roots = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
    }

    public mutating func clear() {
        roots.removeAll(keepingCapacity: false)
    }
}

public enum DiskScanCachePersistence {
    public static func load(from url: URL) throws -> DiskScanCacheStore {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return DiskScanCacheStore()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let cache = try decoder.decode(DiskScanCacheStore.self, from: Data(contentsOf: url))
        guard cache.schemaVersion == DiskScanCacheStore.schemaVersion else {
            return DiskScanCacheStore()
        }
        return cache
    }

    public static func save(_ cache: DiskScanCacheStore, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(cache).write(to: url, options: .atomic)
    }
}
