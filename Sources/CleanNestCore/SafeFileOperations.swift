import Foundation

public enum SafePathError: LocalizedError, Equatable {
    case missing
    case symbolicLink
    case protectedPath
    case outsideAllowedRoots
    case invalidApplication

    public var errorDescription: String? {
        switch self {
        case .missing: return "目标已经不存在。"
        case .symbolicLink: return "为避免越过安全边界，符号链接不会被处理。"
        case .protectedPath: return "该路径受到保护，不能清理。"
        case .outsideAllowedRoots: return "该路径不在 CleanNest 允许的清理范围内。"
        case .invalidApplication: return "只能卸载 Applications 目录中的 .app。"
        }
    }
}

public struct SafePathPolicy: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public var cleanupRoots: [URL] {
        [
            homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/HTTPStorages", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Preferences", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/Saved Application State", isDirectory: true),
            homeDirectory.appendingPathComponent("Library/WebKit", isDirectory: true),
            homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
            homeDirectory.appendingPathComponent(".npm/_cacache", isDirectory: true),
            homeDirectory.appendingPathComponent(".cache/pip", isDirectory: true)
        ].map(\.standardizedFileURL)
    }

    public func validateCleanupTarget(_ target: URL) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { throw SafePathError.missing }
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SafePathError.symbolicLink
        }

        let resolved = target.resolvingSymlinksInPath().standardizedFileURL
        let protected = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System"),
            URL(fileURLWithPath: "/Library"),
            homeDirectory,
            homeDirectory.appendingPathComponent("Library")
        ].map { $0.standardizedFileURL.path }
        guard !protected.contains(resolved.path) else { throw SafePathError.protectedPath }

        let isStrictDescendant = cleanupRoots.contains { root in
            let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL.path
            return resolved.path.hasPrefix(resolvedRoot + "/")
        }
        guard isStrictDescendant else { throw SafePathError.outsideAllowedRoots }
    }

    public func validateApplicationTarget(_ target: URL) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { throw SafePathError.missing }
        if (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            throw SafePathError.symbolicLink
        }

        let resolved = target.resolvingSymlinksInPath().standardizedFileURL
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL }

        guard resolved.pathExtension.lowercased() == "app",
              applicationRoots.contains(where: { resolved.deletingLastPathComponent().path == $0.path }) else {
            throw SafePathError.invalidApplication
        }
    }
}

public struct TrashService: Sendable {
    private let policy: SafePathPolicy

    public init(policy: SafePathPolicy = SafePathPolicy()) {
        self.policy = policy
    }

    public func trashCleanupTargets(_ targets: [URL]) async -> [TrashOutcome] {
        await trash(targets) { target in
            try policy.validateCleanupTarget(target)
        }
    }

    public func trashApplication(_ target: URL) async -> TrashOutcome {
        await trash([target]) { candidate in
            try policy.validateApplicationTarget(candidate)
        }.first
            ?? TrashOutcome(source: target, trashedURL: nil, errorDescription: "没有可处理的目标。")
    }

    private func trash(
        _ targets: [URL],
        validator: @escaping @Sendable (URL) throws -> Void
    ) async -> [TrashOutcome] {
        await Task.detached(priority: .userInitiated) {
            targets.map { source in
                do {
                    try validator(source)
                    var resultingURL: NSURL?
                    try FileManager.default.trashItem(at: source, resultingItemURL: &resultingURL)
                    return TrashOutcome(
                        source: source,
                        trashedURL: resultingURL as URL?,
                        errorDescription: nil
                    )
                } catch {
                    return TrashOutcome(
                        source: source,
                        trashedURL: nil,
                        errorDescription: error.localizedDescription
                    )
                }
            }
        }.value
    }
}
