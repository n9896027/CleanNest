import Foundation

public struct CleanupRuleScanResult: Sendable {
    public let candidates: [CleanupCandidate]
    public let insights: CleanupScanInsights
    public let roots: [CleanupScanRootEvidence]
    public let issues: [CleanupScanIssue]

    public init(
        candidates: [CleanupCandidate],
        insights: CleanupScanInsights,
        roots: [CleanupScanRootEvidence],
        issues: [CleanupScanIssue] = []
    ) {
        self.candidates = candidates
        self.insights = insights
        self.roots = roots
        self.issues = issues
    }
}

public struct CleanupScanner: Sendable {
    public static let npmCacheDisplayName = "npm 下载缓存"
    public static let npmCacheDetail = "用途：npm 在安装、更新依赖或 CLI 工具时下载并留存的包压缩包和注册表元数据；不是项目源码，也不是已安装包或程序本体。清理不会卸载现有内容，以后需要相同包时会重新下载。"

    private struct Rule: Sendable {
        let name: String
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
        await scanWithEvidence(includeApplicationCaches: includeApplicationCaches).candidates
    }

    public func scanWithEvidence(
        includeApplicationCaches: Bool = false
    ) async -> CleanupRuleScanResult {
        let homeDirectory = self.homeDirectory
        let worker = Task.detached(priority: .userInitiated) {
            let now = Date()
            let day: TimeInterval = 86_400
            var rules = [
                Rule(
                    name: "Xcode DerivedData",
                    root: homeDirectory.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true),
                    kind: .developer,
                    minimumAgeDays: 7,
                    allowedExtensions: nil,
                    recommended: true,
                    detail: "Xcode 会在需要时重新生成",
                    maximumChildren: 250
                ),
                Rule(
                    name: "Homebrew 缓存",
                    root: homeDirectory.appendingPathComponent("Library/Caches/Homebrew", isDirectory: true),
                    kind: .packageManager,
                    minimumAgeDays: 7,
                    allowedExtensions: nil,
                    recommended: true,
                    detail: "Homebrew 下载缓存，可重新获取",
                    maximumChildren: 250
                ),
                Rule(
                    name: "npm 缓存",
                    root: homeDirectory.appendingPathComponent(".npm/_cacache", isDirectory: true),
                    kind: .packageManager,
                    minimumAgeDays: 14,
                    allowedExtensions: nil,
                    recommended: false,
                    detail: Self.npmCacheDetail,
                    maximumChildren: 100
                ),
                Rule(
                    name: "pip 缓存",
                    root: homeDirectory.appendingPathComponent(".cache/pip", isDirectory: true),
                    kind: .packageManager,
                    minimumAgeDays: 14,
                    allowedExtensions: nil,
                    recommended: false,
                    detail: "pip 下载缓存，清理后可能重新下载",
                    maximumChildren: 100
                ),
                Rule(
                    name: "应用日志",
                    root: homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true),
                    kind: .logs,
                    minimumAgeDays: 30,
                    allowedExtensions: nil,
                    recommended: false,
                    detail: "旧日志，仅在不再排查问题时选择",
                    maximumChildren: 250
                )
            ]

            if includeApplicationCaches {
                rules.append(
                    Rule(
                        name: "应用缓存",
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
            let roots = rules.map {
                CleanupScanRootEvidence(
                    name: $0.name,
                    url: $0.root,
                    homeDirectory: homeDirectory
                )
            }
            var examinedItemCount = 0
            var skippedSymbolicLinks = 0
            var skippedPackages = 0
            var skippedUnreadableItems = 0
            var skippedUnsafeRoots = 0
            var reachedFileLimit = false
            var issues: [CleanupScanIssue] = []
            func recordIssue(_ url: URL, _ reason: CleanupScanSkipReason) {
                guard issues.count < CleanupScanIssue.maximumPerScanner else { return }
                issues.append(CleanupScanIssue(url: url, reason: reason))
            }

            ruleLoop: for (rule, evidence) in zip(rules, roots) {
                guard !Task.isCancelled else { break ruleLoop }
                switch evidence.status {
                case .checked:
                    break
                case .unsafe:
                    skippedUnsafeRoots += 1
                    recordIssue(rule.root, .unsafeRoot)
                    continue
                case .unreadable:
                    skippedUnreadableItems += 1
                    recordIssue(rule.root, .unreadable)
                    continue
                case .missing:
                    continue
                }
                let children = FileTree.directChildren(of: rule.root)
                if children.count > rule.maximumChildren {
                    reachedFileLimit = true
                    recordIssue(rule.root, .fileLimit)
                }
                for child in children.prefix(rule.maximumChildren) {
                    guard !Task.isCancelled else { break ruleLoop }
                    examinedItemCount += 1
                    guard let values = try? child.resourceValues(forKeys: [
                        .isSymbolicLinkKey,
                        .isPackageKey,
                        .contentModificationDateKey,
                        .isDirectoryKey
                    ]) else {
                        skippedUnreadableItems += 1
                        recordIssue(child, .unreadable)
                        continue
                    }
                    if values.isSymbolicLink == true {
                        skippedSymbolicLinks += 1
                        recordIssue(child, .symbolicLink)
                        continue
                    }
                    if values.isPackage == true {
                        skippedPackages += 1
                        recordIssue(child, .packageBoundary)
                        continue
                    }
                    if let extensions = rule.allowedExtensions,
                       !extensions.contains(child.pathExtension.lowercased()) {
                        continue
                    }
                    let modified = values.contentModificationDate
                    // 修改时间缺失时失败关闭：无法确认年龄的文件不进入候选。
                    guard let modified else { continue }
                    let isNpmContentCache = child.path.hasSuffix("/.npm/_cacache/content-v2")
                    let metrics = FileTree.metrics(
                        of: child,
                        includeLatestModificationDate: isNpmContentCache
                    )
                    guard metrics.allocatedBytes > 0 else { continue }
                    // Age gate and displayed date must use the same clock:
                    // npm's content-v2 directory mtime can be months old while
                    // its files were written yesterday. Use the newest child.
                    let effectiveModified = isNpmContentCache
                        ? (metrics.latestModificationDate ?? modified)
                        : modified
                    guard now.timeIntervalSince(effectiveModified) >= Double(rule.minimumAgeDays) * day else {
                        continue
                    }
                    let name = isNpmContentCache
                        ? Self.npmCacheDisplayName
                        : child.deletingPathExtension().lastPathComponent
                    candidates.append(
                        CleanupCandidate(
                            name: name,
                            url: child,
                            kind: rule.kind,
                            allocatedBytes: metrics.allocatedBytes,
                            modifiedAt: effectiveModified,
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

            let sortedCandidates = uniqueCandidates.sorted {
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                return $0.allocatedBytes > $1.allocatedBytes
            }
            return CleanupRuleScanResult(
                candidates: sortedCandidates,
                insights: CleanupScanInsights(
                    examinedFileCount: examinedItemCount,
                    skippedSymbolicLinkCount: skippedSymbolicLinks,
                    skippedPackageCount: skippedPackages,
                    skippedUnreadableItemCount: skippedUnreadableItems,
                    skippedUnsafeRootCount: skippedUnsafeRoots,
                    reachedFileLimit: reachedFileLimit
                ),
                roots: roots,
                issues: issues
            )
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
