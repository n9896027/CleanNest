import Foundation
import CleanNestCore

enum AppUpdateState: Equatable {
    case idle
    case checking(currentVersion: String)
    case noPublishedRelease(currentVersion: String)
    case updateAvailable(currentVersion: String, release: GitHubReleaseInfo)
    case upToDate(currentVersion: String, release: GitHubReleaseInfo)
    case localVersionAhead(currentVersion: String, release: GitHubReleaseInfo)
    case failed(currentVersion: String, message: String)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    var release: GitHubReleaseInfo? {
        switch self {
        case .updateAvailable(_, let release),
             .upToDate(_, let release),
             .localVersionAhead(_, let release):
            return release
        default:
            return nil
        }
    }
}

enum AppUpdateClientError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case untrustedResponseOrigin
    case rateLimited
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return CNL10n.string("CleanNest 的 GitHub 更新地址无效。")
        case .invalidResponse:
            return CNL10n.string("GitHub 没有返回有效的更新响应。")
        case .untrustedResponseOrigin:
            return CNL10n.string("更新响应没有来自 GitHub 官方 API。")
        case .rateLimited:
            return CNL10n.string("GitHub 暂时限制了检查频率，请稍后再试。")
        case .serverError(let statusCode):
            return CNL10n.format("GitHub 更新服务暂时不可用（HTTP %d）。", statusCode)
        }
    }
}

func localizedAppUpdateError(_ error: Error) -> String {
    if let parsingError = error as? GitHubReleaseParsingError {
        switch parsingError {
        case .responseTooLarge:
            return CNL10n.string("GitHub 返回的数据超出允许范围。")
        case .invalidResponse:
            return CNL10n.string("GitHub 返回了无法识别的发布信息。")
        case .unpublishedRelease:
            return CNL10n.string("GitHub 返回的不是正式公开版本。")
        case .invalidVersionTag(let tag):
            return CNL10n.format("GitHub 版本标签格式无法识别：%@", tag)
        case .untrustedReleaseURL:
            return CNL10n.string("GitHub 返回的下载页面不属于 CleanNest 官方仓库。")
        }
    }
    if error is URLError {
        return CNL10n.string("无法连接 GitHub，请检查网络后重试。")
    }
    return error.localizedDescription
}

struct GitHubAppUpdateClient: Sendable {
    static let owner = "n9896027"
    static let repository = "CleanNest"
    static let releasesPageURL = URL(string: "https://github.com/n9896027/CleanNest/releases")!

    func latestRelease() async throws -> GitHubReleaseInfo? {
        guard let endpoint = URL(
            string: "https://api.github.com/repos/\(Self.owner)/\(Self.repository)/releases/latest"
        ) else {
            throw AppUpdateClientError.invalidEndpoint
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 1
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("CleanNest/\(AppMetadata.shortVersion ?? "development")", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdateClientError.invalidResponse
        }
        guard httpResponse.url?.scheme?.lowercased() == "https",
              httpResponse.url?.host?.lowercased() == "api.github.com",
              httpResponse.url?.port == nil,
              httpResponse.url?.user == nil,
              httpResponse.url?.password == nil else {
            throw AppUpdateClientError.untrustedResponseOrigin
        }

        switch httpResponse.statusCode {
        case 200:
            return try GitHubReleaseParser.parse(
                data: data,
                owner: Self.owner,
                repository: Self.repository
            )
        case 404:
            return nil
        case 403, 429:
            throw AppUpdateClientError.rateLimited
        default:
            throw AppUpdateClientError.serverError(httpResponse.statusCode)
        }
    }
}
