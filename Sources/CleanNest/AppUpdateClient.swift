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

enum AppUpdateDownloadState: Equatable {
    case idle
    case downloading(package: AppUpdatePackage)
    case verifying(packageURL: URL, package: AppUpdatePackage)
    case readyToInstall(packageURL: URL, package: AppUpdatePackage)
    case installerOpened(packageURL: URL, package: AppUpdatePackage)
    case failed(message: String, package: AppUpdatePackage)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    var package: AppUpdatePackage? {
        switch self {
        case .idle:
            return nil
        case .downloading(let package),
             .verifying(_, let package),
             .readyToInstall(_, let package),
             .installerOpened(_, let package),
             .failed(_, let package):
            return package
        }
    }

    var packageURL: URL? {
        switch self {
        case .verifying(let url, _), .readyToInstall(let url, _), .installerOpened(let url, _):
            return url
        default:
            return nil
        }
    }
}

enum AppUpdateClientError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case untrustedResponseOrigin
    case untrustedDownloadOrigin
    case downloadCacheUnavailable
    case rateLimited
    case serverError(Int)
    case signatureValidationFailed
    case notarizationValidationFailed
    case gatekeeperValidationFailed
    case installerOpenFailed

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return CNL10n.string("CleanNest 的 GitHub 更新地址无效。")
        case .invalidResponse:
            return CNL10n.string("GitHub 没有返回有效的更新响应。")
        case .untrustedResponseOrigin:
            return CNL10n.string("更新响应没有来自 GitHub 官方 API。")
        case .untrustedDownloadOrigin:
            return CNL10n.string("安装包下载被重定向到不受信任的地址，已停止下载。")
        case .downloadCacheUnavailable:
            return CNL10n.string("无法创建 CleanNest 更新缓存目录。")
        case .rateLimited:
            return CNL10n.string("GitHub 暂时限制了检查频率，请稍后再试。")
        case .serverError(let statusCode):
            return CNL10n.format("GitHub 更新服务暂时不可用（HTTP %d）。", statusCode)
        case .signatureValidationFailed:
            return CNL10n.string("安装包未通过 CleanNest 团队的 Developer ID Installer 签名校验，已停止安装。")
        case .notarizationValidationFailed:
            return CNL10n.string("安装包未通过 Apple 公证票据校验，已停止安装。")
        case .gatekeeperValidationFailed:
            return CNL10n.string("安装包未通过 macOS Gatekeeper 评估，已停止安装。")
        case .installerOpenFailed:
            return CNL10n.string("无法打开 macOS 安装器。安装包仍保留在更新缓存中，你可以重试。")
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
        case .invalidInstallerPackage:
            return CNL10n.string("GitHub Release 的安装包命名、大小或 SHA-256 摘要不符合要求，不能自动下载。")
        case .untrustedPackageURL:
            return CNL10n.string("安装包下载地址不属于 CleanNest 官方 Release。")
        }
    }
    if let verificationError = error as? AppUpdatePackageVerificationError {
        switch verificationError {
        case .invalidFile:
            return CNL10n.string("下载结果不是可读取的普通安装包文件。")
        case .sizeMismatch:
            return CNL10n.string("安装包实际大小与 GitHub Release 记录不一致，已删除下载文件。")
        case .digestMismatch:
            return CNL10n.string("安装包 SHA-256 与 GitHub Release 摘要不一致，已删除下载文件。")
        }
    }
    if let clientError = error as? AppUpdateClientError {
        return clientError.localizedDescription
    }
    if error is CancellationError {
        return CNL10n.string("更新操作已取消。")
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

        let session = Self.makeSession(resourceTimeout: 20)
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

    func downloadInstallerPackage(
        for release: GitHubReleaseInfo
    ) async throws -> (packageURL: URL, package: AppUpdatePackage) {
        guard let package = release.installerPackage,
              GitHubReleaseParser.isTrustedPackageURL(
                package.downloadURL,
                package: package,
                owner: Self.owner,
                repository: Self.repository,
                tagName: release.tagName
              ) else {
            throw AppUpdateClientError.untrustedDownloadOrigin
        }
        guard let cacheRoot = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw AppUpdateClientError.downloadCacheUnavailable
        }

        let updatesDirectory = cacheRoot
            .appendingPathComponent("CleanNest", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)
        let uniqueName = UUID().uuidString
        let partialURL = updatesDirectory.appendingPathComponent("\(uniqueName).download")
        let packageURL = updatesDirectory.appendingPathComponent("\(uniqueName)-\(package.name)")

        let downloadDelegate = AppUpdateDownloadSessionDelegate(
            package: package,
            owner: Self.owner,
            repository: Self.repository,
            tagName: release.tagName
        )
        let configuration = Self.downloadConfiguration()
        let session = URLSession(
            configuration: configuration,
            delegate: downloadDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: package.downloadURL)
        request.httpMethod = "GET"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("CleanNest/\(AppMetadata.shortVersion ?? "development")", forHTTPHeaderField: "User-Agent")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        do {
            let (temporaryURL, response) = try await session.download(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AppUpdateClientError.invalidResponse
            }
            guard httpResponse.statusCode == 200 else {
                throw AppUpdateClientError.serverError(httpResponse.statusCode)
            }
            guard let finalURL = httpResponse.url,
                  GitHubReleaseParser.isTrustedPackageResponseURL(
                    finalURL,
                    package: package,
                    owner: Self.owner,
                    repository: Self.repository,
                    tagName: release.tagName
                  ) else {
                throw AppUpdateClientError.untrustedDownloadOrigin
            }
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporaryURL, to: partialURL)
            try await Task.detached(priority: .utility) {
                try AppUpdatePackageVerifier.verify(fileAt: partialURL, package: package)
            }.value
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: partialURL, to: packageURL)
            return (packageURL, package)
        } catch {
            try? FileManager.default.removeItem(at: partialURL)
            try? FileManager.default.removeItem(at: packageURL)
            throw error
        }
    }

    private static func makeSession(resourceTimeout: TimeInterval) -> URLSession {
        URLSession(configuration: downloadConfiguration(resourceTimeout: resourceTimeout))
    }

    private static func downloadConfiguration(
        resourceTimeout: TimeInterval = 15 * 60
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpMaximumConnectionsPerHost = 1
        return configuration
    }
}

private final class AppUpdateDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let package: AppUpdatePackage
    private let owner: String
    private let repository: String
    private let tagName: String

    init(package: AppUpdatePackage, owner: String, repository: String, tagName: String) {
        self.package = package
        self.owner = owner
        self.repository = repository
        self.tagName = tagName
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              GitHubReleaseParser.isTrustedPackageResponseURL(
                url,
                package: package,
                owner: owner,
                repository: repository,
                tagName: tagName
              ) else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if totalBytesWritten > package.byteCount
            || totalBytesWritten > AppUpdatePackage.maximumByteCount {
            downloadTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The async URLSession download API owns the temporary-file handoff.
    }
}

struct AppUpdateInstallerValidator: Sendable {
    static let expectedTeamIdentifier = "NC33STD88A"

    let commandRunner: CommandRunner

    init(commandRunner: CommandRunner = CommandRunner()) {
        self.commandRunner = commandRunner
    }

    func validate(packageAt url: URL) async throws {
        do {
            let result = try await commandRunner.runChecked(
                executable: URL(fileURLWithPath: "/usr/sbin/pkgutil"),
                arguments: ["--check-signature", url.path],
                timeout: 60
            )
            let output = result.standardOutput + "\n" + result.standardError
            let hasExpectedSigner = output
                .split(whereSeparator: \.isNewline)
                .contains { line in
                    line.contains("Developer ID Installer")
                        && line.contains("(\(Self.expectedTeamIdentifier))")
                }
            guard hasExpectedSigner else {
                throw AppUpdateClientError.signatureValidationFailed
            }
        } catch let error as AppUpdateClientError {
            throw error
        } catch {
            throw AppUpdateClientError.signatureValidationFailed
        }

        do {
            _ = try await commandRunner.runChecked(
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["stapler", "validate", url.path],
                timeout: 60
            )
        } catch {
            throw AppUpdateClientError.notarizationValidationFailed
        }

        do {
            _ = try await commandRunner.runChecked(
                executable: URL(fileURLWithPath: "/usr/sbin/spctl"),
                arguments: ["--assess", "--type", "install", url.path],
                timeout: 60
            )
        } catch {
            throw AppUpdateClientError.gatekeeperValidationFailed
        }
    }
}
