import Foundation
import CleanNestCore

struct AgentRuleCatalogUpdateClient: Sendable {
    enum UpdateError: LocalizedError {
        case invalidResponse
        case notPublished
        case transport(Int)
        case tooLarge
        case invalidArchive
        case untrustedRedirect
        case olderThanCurrent

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "在线识别规则没有返回有效响应。"
            case .notPublished: return "当前正式版本没有单独的在线规则包，内置规则继续有效。"
            case .transport(let code): return CNL10n.format("在线规则服务暂时不可用（HTTP %d）。", code)
            case .tooLarge: return "在线规则包超过 2 MB 安全上限。"
            case .invalidArchive: return "在线规则归档中只有一个 CleanNestAgentRules.bundle 才能安装。"
            case .untrustedRedirect: return "在线规则下载被重定向到不受信任的地址。"
            case .olderThanCurrent: return "在线规则早于当前已验证规则，已停止降级。"
            }
        }
    }

    static let downloadURL = URL(string: "https://github.com/n9896027/CleanNest/releases/latest/download/CleanNestAgentRules.zip")!
    let store: AgentRuleCatalogStore

    func checkForUpdate(current: AgentRuleCatalog) async throws -> AgentRuleCatalog? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: Self.downloadURL)
        request.setValue("CleanNest/\(AppMetadata.shortVersion ?? "development")", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await session.download(for: request)
        guard let response = response as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        if response.statusCode == 404 { throw UpdateError.notPublished }
        guard response.statusCode == 200 else { throw UpdateError.transport(response.statusCode) }
        guard let finalURL = response.url,
              finalURL.scheme?.lowercased() == "https",
              let host = finalURL.host?.lowercased(),
              host == "github.com" || host == "release-assets.githubusercontent.com" || host == "objects.githubusercontent.com" else {
            throw UpdateError.untrustedRedirect
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
        guard let size = (attributes[.size] as? NSNumber)?.int64Value, size <= 2_097_152 else {
            throw UpdateError.tooLarge
        }

        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestAgentRules-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        _ = try await CommandRunner().runChecked(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", temporaryURL.path, workspace.path],
            timeout: 30
        )
        let entries = try FileManager.default.contentsOfDirectory(
            at: workspace,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        guard entries.count == 1,
              let bundle = entries.first,
              bundle.lastPathComponent == "CleanNestAgentRules.bundle" else {
            throw UpdateError.invalidArchive
        }
        let bundleValues = try bundle.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard bundleValues.isDirectory == true, bundleValues.isSymbolicLink != true else {
            throw UpdateError.invalidArchive
        }
        let candidate = try store.inspect(source: bundle)
        guard candidate.issuedAt >= current.issuedAt else { throw UpdateError.olderThanCurrent }
        guard candidate.revision != current.revision || candidate != current else { return nil }
        return try store.install(from: bundle)
    }
}
