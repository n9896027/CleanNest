import Foundation

public struct CleanupScanner: Sendable {
    public static let npmCacheDisplayName = "npm 下载缓存"
    public static let npmCacheDetail = "用途：npm 在安装、更新依赖或 CLI 工具时下载并留存的包压缩包和注册表元数据；不是项目源码，也不是已安装包或程序本体。清理不会卸载现有内容，以后需要相同包时会重新下载。"

    private struct Rule: Sendable {
        let root: URL
        let kind: CleanupKind
        let minimumAgeDays: Int
        let allowedExtensions: Set<String>?
        let recommended: Bool
        let detail: String
        let maximumChildren: Int
    }

    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func scan(includeApplicationCaches: Bool = false) async -> [CleanupCandidate] {
        await Task.detached(priority: .userInitiated) {
            let now = Date()
            let day: TimeInterval = 86_400
            var rules = [
                Rule(
                    root: homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
                    kind: .developer,
                    minimumAgeDays: 7,
                    allowedExtensions: nil,
                    recommended: true,
                    detail: "Xcode 会在需要时重新生成",
                    maximumChildren: 250
                ),
                Rule(
                    root: homeDirectory.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true),
                    kind: .packageManager,
                    minimumAgeDays: 7,
                    allowedExtensions: nil,
                    recommended: true,
                    detail: "Homebrew 下载缓存，可重新获取",
                    maximumChildren: 250
                ),
                Rule(
                    root: homeDirectory.appendingPathComponent(".npm/_cacache", isDirectory: true),
                    kind: .packageManager,
                    minimumAgeDays: 14,
                    allowedExtensions: nil,
                    recommended: false,
                    detail: Self.npmCacheDetail,
                    maximumChildren: 100
                ),
                Rule(
                    root: homeDirectory.appendingPathComponent(".cache/pip", isDirectory: true),
                    kind: .packageManager,
                    minimumAgeDays: 14,
                    allowedExtensions: nil,
                    recommended: false,
                    detail: "pip 下载缓存，清理后可能重新下载",
                    maximumChildren: 100
                ),
                Rule(
                    root: homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true),
                    kind: .logs,
                    minimumAgeDays: 30,
                    allowedExtensions: nil,
                    recommended: false,
                    detail: "旧日志，仅在不再排查问题时选择",
                    maximumChildren: 250
                ),
                Rule(
                    root: homeDirectory.appendingPathComponent("Downloads", isDirectory: true),
                    kind: .installer,
                    minimumAgeDays: 7,
                    allowedExtensions: ["dmg", "pkg", "xip", "iso"],
                    recommended: true,
                    detail: "已下载的安装镜像，请确认不再需要",
                    maximumChildren: 500
                )
            ]

            if includeApplicationCaches {
                rules.append(
                    Rule(
                        root: homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true),
                        kind: .appCache,
                        minimumAgeDays: 30,
                        allowedExtensions: nil,
                        recommended: false,
                        detail: "应用缓存；运行中的 App 可能立即重建",
                        maximumChildren: 350
                    )
                )
            }

            var candidates: [CleanupCandidate] = []
            for rule in rules where FileManager.default.fileExists(atPath: rule.root.path) {
                for child in FileTree.directChildren(of: rule.root).prefix(rule.maximumChildren) {
                    guard let values = try? child.resourceValues(forKeys: [
                        .isSymbolicLinkKey,
                        .contentModificationDateKey,
                        .isDirectoryKey
                    ]), values.isSymbolicLink != true else {
                        continue
                    }
                    if let extensions = rule.allowedExtensions,
                       !extensions.contains(child.pathExtension.lowercased()) {
                        continue
                    }
                    let modified = values.contentModificationDate
                    if let modified, now.timeIntervalSince(modified) < Double(rule.minimumAgeDays) * day {
                        continue
                    }
                    let isNpmContentCache = child.path.hasSuffix("/.npm/_cacache/content-v2")
                    let metrics = FileTree.metrics(
                        of: child,
                        includeLatestModificationDate: isNpmContentCache
                    )
                    guard metrics.allocatedBytes > 0 else { continue }
                    let name = isNpmContentCache
                        ? Self.npmCacheDisplayName
                        : child.deletingPathExtension().lastPathComponent
                    candidates.append(
                        CleanupCandidate(
                            name: name,
                            url: child,
                            kind: rule.kind,
                            allocatedBytes: metrics.allocatedBytes,
                            modifiedAt: isNpmContentCache
                                ? (metrics.latestModificationDate ?? modified)
                                : modified,
                            isRecommended: rule.recommended,
                            detail: rule.detail
                        )
                    )
                }
            }

            var seenPaths = Set<String>()
            let uniqueCandidates = candidates.filter {
                seenPaths.insert($0.url.standardizedFileURL.path).inserted
            }

            return uniqueCandidates.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.allocatedBytes > $1.allocatedBytes
            }
        }.value
    }
}
