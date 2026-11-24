import Foundation

public extension ApplicationDependencyGraph {
    /// Adds only signed-catalog, exact-path evidence to the existing application
    /// graph. Shared containers, managed containers and unverified items remain
    /// read-only. Catalog roots never grant deletion authority by themselves.
    func includingDesktopProduct(
        _ product: AgentDesktopProductRule,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ApplicationDependencyGraph {
        var expanded = nodes.map { node in
            ApplicationDependencyNode(
                id: node.id,
                name: node.name,
                url: node.url,
                kind: node.kind,
                ownership: node.ownership,
                action: node.action,
                allocatedBytes: node.allocatedBytes,
                evidence: node.evidence,
                identity: node.identity,
                productID: product.id
            )
        }
        // Downloaded rules may add detection and read-only data evidence, but
        // cannot remotely introduce a new deletion path. Only an unchanged,
        // built-in product rule can classify its cache/log entries as removable.
        let hasBuiltInMutationApproval = AgentRuleCatalog.builtIn.desktopProducts.contains(product)
        for item in product.privateData {
            let url = item.path.resolve(homeDirectory: homeDirectory)
            guard let identity = try? ApplicationDependencyIdentity.capture(at: url) else { continue }
            expanded.removeAll { $0.url.standardizedFileURL == url.standardizedFileURL }
            let removable = hasBuiltInMutationApproval
                && item.disposition == .regenerable
                && (item.path.base == .caches || item.path.base == .logs)
            expanded.append(ApplicationDependencyNode(
                name: url.lastPathComponent,
                url: url,
                kind: removable ? .relatedFile : .unverifiedItem,
                ownership: removable ? .applicationOwned : .unverified,
                action: removable ? .removeAfterApplication : .readOnly,
                allocatedBytes: FileTree.allocatedSize(of: url),
                evidence: [
                    "已签名产品规则 \(product.id) 的精确路径",
                    removable ? "仅限已证实的可再生缓存或日志" : "应用数据可能包含历史、项目或凭据；保持只读"
                ],
                identity: identity,
                productID: product.id
            ))
        }
        expanded = Dictionary(grouping: expanded, by: \.id).compactMap(\.value.first)
        return ApplicationDependencyGraph(
            applicationID: applicationID,
            capturedAt: capturedAt,
            codeSignature: codeSignature,
            registration: registration,
            nodes: expanded,
            diagnostic: diagnostic + " 产品 \(product.displayName) 的私有数据只按精确证据处理。",
            productID: product.id
        )
    }
}
