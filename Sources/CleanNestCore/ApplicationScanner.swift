import Foundation

public struct ApplicationScanner: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func scan() async -> [InstalledApplication] {
        await Task.detached(priority: .userInitiated) {
            let roots = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appendingPathComponent("Applications", isDirectory: true)
            ]
            var applications: [InstalledApplication] = []

            for root in roots {
                for url in FileTree.directChildren(of: root)
                where url.pathExtension.lowercased() == "app" {
                    let bundle = Bundle(url: url)
                    let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

                    applications.append(
                        InstalledApplication(
                            name: displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent,
                            bundleIdentifier: bundle?.bundleIdentifier,
                            version: version,
                            url: url,
                            allocatedBytes: FileTree.allocatedSize(of: url),
                            modifiedAt: modified
                        )
                    )
                }
            }

            return applications.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }.value
    }

    public func leftovers(
        for application: InstalledApplication,
        includeProtectedAppData: Bool = false
    ) async -> [CleanupCandidate] {
        guard let identifier = application.bundleIdentifier, !identifier.isEmpty else { return [] }

        return await Task.detached(priority: .userInitiated) {
            let roots: [(relativePath: String, kind: CleanupKind, requiresAppDataAccess: Bool)] = [
                ("Library/Application Support", .leftover, true),
                ("Library/Caches", .leftover, false),
                ("Library/Containers", .leftover, true),
                ("Library/Group Containers", .leftover, true),
                ("Library/HTTPStorages", .leftover, false),
                ("Library/Logs", .leftover, false),
                ("Library/Preferences", .leftover, false),
                ("Library/Saved Application State", .leftover, false),
                ("Library/WebKit", .leftover, false)
            ]
            var matches: [CleanupCandidate] = []

            for rootSpec in roots where includeProtectedAppData || !rootSpec.requiresAppDataAccess {
                let root = homeDirectory.appendingPathComponent(rootSpec.relativePath, isDirectory: true)
                for child in FileTree.directChildren(of: root) {
                    let name = child.lastPathComponent
                    let isExactBundleMatch = name == identifier
                        || name == identifier + ".plist"
                        || name == identifier + ".savedState"
                        || name.hasPrefix(identifier + ".")
                    guard isExactBundleMatch else { continue }
                    let values = try? child.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
                    guard values?.isSymbolicLink != true else { continue }
                    matches.append(
                        CleanupCandidate(
                            name: name,
                            url: child,
                            kind: rootSpec.kind,
                            allocatedBytes: FileTree.allocatedSize(of: child),
                            modifiedAt: values?.contentModificationDate,
                            isRecommended: true,
                            detail: "按 Bundle ID 精确匹配：\(identifier)"
                        )
                    )
                }
            }
            return matches.sorted { $0.allocatedBytes > $1.allocatedBytes }
        }.value
    }
}
