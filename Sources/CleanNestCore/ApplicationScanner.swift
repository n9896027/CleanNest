import Foundation

public struct ApplicationScanner: Sendable {
    public let homeDirectory: URL
    private let dependencyGraphBuilder: ApplicationDependencyGraphBuilder

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.dependencyGraphBuilder = ApplicationDependencyGraphBuilder(homeDirectory: homeDirectory)
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
                    let resourceValues = try? url.resourceValues(forKeys: [
                        .contentModificationDateKey,
                        .isSymbolicLinkKey
                    ])
                    guard resourceValues?.isSymbolicLink != true else { continue }
                    let bundle = Bundle(url: url)
                    let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                    let version = bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                    let buildVersion = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String

                    applications.append(
                        InstalledApplication(
                            name: displayName ?? bundleName ?? url.deletingPathExtension().lastPathComponent,
                            bundleIdentifier: bundle?.bundleIdentifier,
                            version: version,
                            buildVersion: buildVersion,
                            url: url,
                            allocatedBytes: FileTree.allocatedSize(of: url),
                            modifiedAt: resourceValues?.contentModificationDate,
                            fileIdentity: try? ApplicationFileIdentity.capture(at: url)
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
        let graph = await dependencyGraph(
            for: application,
            includeProtectedAppData: includeProtectedAppData
        )
        return graph.separatelyRemovableNodes.map { node in
            CleanupCandidate(
                name: node.name,
                url: node.url,
                kind: .leftover,
                allocatedBytes: node.allocatedBytes,
                modifiedAt: node.identity?.modifiedAt,
                isRecommended: true,
                detail: node.evidence.joined(separator: " · ")
            )
        }
    }

    public func dependencyGraph(
        for application: InstalledApplication,
        includeProtectedAppData: Bool = false,
        applicationIsRunning: Bool? = nil,
        desktopProduct: AgentDesktopProductRule? = nil
    ) async -> ApplicationDependencyGraph {
        let graph = await dependencyGraphBuilder.build(
            for: application,
            includeProtectedAppData: includeProtectedAppData,
            applicationIsRunning: applicationIsRunning
        )
        guard let desktopProduct,
              let identifier = application.bundleIdentifier,
              desktopProduct.bundleIdentifiers.contains(identifier) else { return graph }
        return graph.includingDesktopProduct(desktopProduct, homeDirectory: homeDirectory)
    }
}
