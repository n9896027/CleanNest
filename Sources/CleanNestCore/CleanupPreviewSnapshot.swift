import Foundation

public struct CleanupPreviewItem: Codable, Equatable, Sendable {
    public let token: String
    public let name: String
    public let kind: CleanupKind
    public let allocatedBytes: Int64
    public let modifiedAt: Date?
    public let isRecommended: Bool
    public let detail: String
    public let pathHint: String

    public init(
        token: String,
        name: String,
        kind: CleanupKind,
        allocatedBytes: Int64,
        modifiedAt: Date?,
        isRecommended: Bool,
        detail: String,
        pathHint: String
    ) {
        self.token = token
        self.name = name
        self.kind = kind
        self.allocatedBytes = allocatedBytes
        self.modifiedAt = modifiedAt
        self.isRecommended = isRecommended
        self.detail = detail
        self.pathHint = pathHint
    }
}

public struct CleanupPreviewSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let items: [CleanupPreviewItem]

    public init(
        schemaVersion: Int = Self.schemaVersion,
        generatedAt: Date = Date(),
        items: [CleanupPreviewItem]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.items = items
    }

    public static func make(
        candidates: [CleanupCandidate],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        limit: Int = 64
    ) -> CleanupPreviewSnapshot {
        let safeLimit = min(max(limit, 1), 256)
        let selected = candidates
            .sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.name < $1.name }
                return $0.allocatedBytes > $1.allocatedBytes
            }
            .prefix(safeLimit)
        let items = selected.enumerated().map { index, candidate in
            CleanupPreviewItem(
                token: String(format: "c%04d", index + 1),
                name: sanitize(candidate.name, maximumLength: 160),
                kind: candidate.kind,
                allocatedBytes: max(0, candidate.allocatedBytes),
                modifiedAt: candidate.modifiedAt,
                isRecommended: candidate.isRecommended,
                detail: sanitize(candidate.detail, maximumLength: 500),
                pathHint: redactedPath(candidate.url, homeDirectory: homeDirectory)
            )
        }
        return CleanupPreviewSnapshot(items: items)
    }

    private static func redactedPath(_ url: URL, homeDirectory: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = homeDirectory.standardizedFileURL.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return sanitize("~" + String(path.dropFirst(home.count)), maximumLength: 240)
        }
        return sanitize(url.lastPathComponent, maximumLength: 240)
    }

    private static func sanitize(_ value: String, maximumLength: Int) -> String {
        let clean = value.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        return String(clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).prefix(maximumLength))
    }
}

public enum CleanupPreviewPersistence {
    public static func load(from url: URL) throws -> CleanupPreviewSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        let snapshot = try JSONDecoder().decode(CleanupPreviewSnapshot.self, from: data)
        guard snapshot.schemaVersion == CleanupPreviewSnapshot.schemaVersion else { return nil }
        return snapshot
    }

    public static func save(_ snapshot: CleanupPreviewSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }
}
