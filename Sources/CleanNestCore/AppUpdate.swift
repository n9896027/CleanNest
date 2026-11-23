import CryptoKit
import Foundation

public struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prereleaseIdentifiers: [String]

    public init?(parsing rawValue: String) {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }

        let withoutBuild = value.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let versionParts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let coreParts = versionParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard coreParts.count == 3,
              coreParts.allSatisfy({ part in
                  !part.isEmpty && part.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
              }),
              let major = Int(coreParts[0]), major >= 0,
              let minor = Int(coreParts[1]), minor >= 0,
              let patch = Int(coreParts[2]), patch >= 0 else {
            return nil
        }

        let prerelease: [String]
        if versionParts.count == 2 {
            prerelease = versionParts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
            guard !prerelease.isEmpty,
                  prerelease.allSatisfy({ identifier in
                      !identifier.isEmpty
                          && identifier.unicodeScalars.allSatisfy { allowed.contains($0) }
                  }) else {
                return nil
            }
        } else {
            prerelease = []
        }

        self.major = major
        self.minor = minor
        self.patch = patch
        self.prereleaseIdentifiers = prerelease
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prereleaseIdentifiers.isEmpty else { return core }
        return core + "-" + prereleaseIdentifiers.joined(separator: ".")
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore {
            return lhsCore.lexicographicallyPrecedes(rhsCore)
        }

        if lhs.prereleaseIdentifiers.isEmpty {
            return false
        }
        if rhs.prereleaseIdentifiers.isEmpty {
            return true
        }

        for (lhsIdentifier, rhsIdentifier) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if lhsIdentifier == rhsIdentifier { continue }

            let lhsNumber = Int(lhsIdentifier)
            let rhsNumber = Int(rhsIdentifier)
            switch (lhsNumber, rhsNumber) {
            case let (.some(lhsNumber), .some(rhsNumber)):
                return lhsNumber < rhsNumber
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhsIdentifier.compare(
                    rhsIdentifier,
                    options: [.literal],
                    range: nil,
                    locale: Locale(identifier: "en_US_POSIX")
                ) == .orderedAscending
            }
        }

        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }
}

public struct AppUpdatePackage: Equatable, Sendable {
    public static let maximumByteCount: Int64 = 512 * 1_024 * 1_024

    public let name: String
    public let downloadURL: URL
    public let byteCount: Int64
    public let sha256: String

    public init(name: String, downloadURL: URL, byteCount: Int64, sha256: String) {
        self.name = name
        self.downloadURL = downloadURL
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

public struct GitHubReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let tagName: String
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let publishedAt: Date?
    public let installerPackage: AppUpdatePackage?

    public init(
        version: SemanticVersion,
        tagName: String,
        title: String,
        notes: String,
        pageURL: URL,
        publishedAt: Date?,
        installerPackage: AppUpdatePackage? = nil
    ) {
        self.version = version
        self.tagName = tagName
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.publishedAt = publishedAt
        self.installerPackage = installerPackage
    }
}

public enum GitHubReleaseParsingError: LocalizedError, Equatable, Sendable {
    case responseTooLarge
    case invalidResponse
    case unpublishedRelease
    case invalidVersionTag(String)
    case untrustedReleaseURL
    case invalidInstallerPackage
    case untrustedPackageURL

    public var errorDescription: String? {
        switch self {
        case .responseTooLarge:
            return "GitHub 返回的数据超出允许范围。"
        case .invalidResponse:
            return "GitHub 返回了无法识别的发布信息。"
        case .unpublishedRelease:
            return "GitHub 返回的不是正式公开版本。"
        case .invalidVersionTag(let tag):
            return "GitHub 版本标签格式无法识别：\(tag)"
        case .untrustedReleaseURL:
            return "GitHub 返回的下载页面不属于 CleanNest 官方仓库。"
        case .invalidInstallerPackage:
            return "GitHub Release 中没有唯一、完整且符合版本命名的 CleanNest 安装包。"
        case .untrustedPackageURL:
            return "安装包下载地址不属于 CleanNest 官方 Release。"
        }
    }
}

public enum GitHubReleaseParser {
    public static let maximumResponseBytes = 1_048_576

    public static func parse(
        data: Data,
        owner: String,
        repository: String
    ) throws -> GitHubReleaseInfo {
        guard data.count <= maximumResponseBytes else {
            throw GitHubReleaseParsingError.responseTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response: ReleaseResponse
        do {
            response = try decoder.decode(ReleaseResponse.self, from: data)
        } catch {
            throw GitHubReleaseParsingError.invalidResponse
        }

        guard !response.draft, !response.prerelease else {
            throw GitHubReleaseParsingError.unpublishedRelease
        }
        guard let version = SemanticVersion(parsing: response.tagName) else {
            throw GitHubReleaseParsingError.invalidVersionTag(response.tagName)
        }
        guard let pageURL = URL(string: response.htmlURL),
              pageURL.scheme?.lowercased() == "https",
              pageURL.host?.lowercased() == "github.com",
              pageURL.port == nil,
              pageURL.user == nil,
              pageURL.password == nil else {
            throw GitHubReleaseParsingError.untrustedReleaseURL
        }

        let expectedPrefix = "/\(owner)/\(repository)/releases/tag/".lowercased()
        guard pageURL.path.lowercased().hasPrefix(expectedPrefix) else {
            throw GitHubReleaseParsingError.untrustedReleaseURL
        }

        let trimmedTitle = (response.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = (response.body ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let package = try parseInstallerPackage(
            assets: response.assets,
            version: version,
            tagName: response.tagName,
            owner: owner,
            repository: repository
        )

        return GitHubReleaseInfo(
            version: version,
            tagName: response.tagName,
            title: trimmedTitle.isEmpty ? response.tagName : trimmedTitle,
            notes: String(trimmedNotes.prefix(12_000)),
            pageURL: pageURL,
            publishedAt: response.publishedAt,
            installerPackage: package
        )
    }

    public static func isTrustedPackageURL(
        _ url: URL,
        package: AppUpdatePackage,
        owner: String,
        repository: String,
        tagName: String
    ) -> Bool {
        guard hasSecureURLShape(url), url.query == nil, url.fragment == nil else { return false }
        let expectedPath = "/\(owner)/\(repository)/releases/download/\(tagName)/\(package.name)"
        return url.host?.lowercased() == "github.com" && url.path == expectedPath
    }

    public static func isTrustedPackageResponseURL(
        _ url: URL,
        package: AppUpdatePackage,
        owner: String,
        repository: String,
        tagName: String
    ) -> Bool {
        guard hasSecureURLShape(url) else { return false }
        let host = url.host?.lowercased()
        if host == "github.com" {
            return isTrustedPackageURL(
                url,
                package: package,
                owner: owner,
                repository: repository,
                tagName: tagName
            )
        }
        return host == "release-assets.githubusercontent.com"
            || host == "objects.githubusercontent.com"
    }

    private static func hasSecureURLShape(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host != nil
            && url.port == nil
            && url.user == nil
            && url.password == nil
    }

    private static func parseInstallerPackage(
        assets: [ReleaseAsset]?,
        version: SemanticVersion,
        tagName: String,
        owner: String,
        repository: String
    ) throws -> AppUpdatePackage? {
        guard let assets else { return nil }
        let packageAssets = assets.filter { $0.name.lowercased().hasSuffix(".pkg") }
        guard !packageAssets.isEmpty else { return nil }

        let expectedPrefix = "CleanNest-\(version.description)-"
        let matchingAssets = packageAssets.filter { asset in
            guard asset.name.hasPrefix(expectedPrefix), asset.name.hasSuffix(".pkg") else { return false }
            let build = asset.name.dropFirst(expectedPrefix.count).dropLast(4)
            return !build.isEmpty && build.allSatisfy(\.isNumber)
        }
        guard packageAssets.count == 1, matchingAssets.count == 1,
              let asset = matchingAssets.first,
              asset.state == "uploaded",
              asset.size > 0, asset.size <= AppUpdatePackage.maximumByteCount,
              let digest = asset.digest,
              digest.hasPrefix("sha256:") else {
            throw GitHubReleaseParsingError.invalidInstallerPackage
        }

        let sha256 = String(digest.dropFirst("sha256:".count)).lowercased()
        guard sha256.count == 64,
              sha256.allSatisfy({ $0.isHexDigit }),
              let downloadURL = URL(string: asset.browserDownloadURL) else {
            throw GitHubReleaseParsingError.invalidInstallerPackage
        }
        let package = AppUpdatePackage(
            name: asset.name,
            downloadURL: downloadURL,
            byteCount: asset.size,
            sha256: sha256
        )
        guard isTrustedPackageURL(
            downloadURL,
            package: package,
            owner: owner,
            repository: repository,
            tagName: tagName
        ) else {
            throw GitHubReleaseParsingError.untrustedPackageURL
        }
        return package
    }

    private struct ReleaseResponse: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let publishedAt: Date?
        let assets: [ReleaseAsset]?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case draft
            case prerelease
            case publishedAt = "published_at"
            case assets
        }
    }

    private struct ReleaseAsset: Decodable {
        let name: String
        let state: String
        let size: Int64
        let digest: String?
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case state
            case size
            case digest
            case browserDownloadURL = "browser_download_url"
        }
    }
}

public enum AppUpdateDecision: Equatable, Sendable {
    case updateAvailable
    case upToDate
    case localVersionAhead
}

public enum AppUpdatePolicy {
    public static func decision(
        localVersion rawLocalVersion: String,
        release: GitHubReleaseInfo
    ) throws -> AppUpdateDecision {
        guard let localVersion = SemanticVersion(parsing: rawLocalVersion) else {
            throw GitHubReleaseParsingError.invalidVersionTag(rawLocalVersion)
        }
        if localVersion < release.version { return .updateAvailable }
        if release.version < localVersion { return .localVersionAhead }
        return .upToDate
    }
}

public enum AppUpdateAutomaticCheckPolicy {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func shouldCheck(
        isEnabled: Bool,
        lastAttemptAt: Date?,
        now: Date = Date()
    ) -> Bool {
        guard isEnabled else { return false }
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= interval
            || now.timeIntervalSince(lastAttemptAt) < 0
    }
}

public enum AppUpdatePackageVerificationError: LocalizedError, Equatable, Sendable {
    case invalidFile
    case sizeMismatch(expected: Int64, actual: Int64)
    case digestMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidFile:
            return "下载结果不是可读取的普通安装包文件。"
        case .sizeMismatch(let expected, let actual):
            return "安装包大小不匹配：预期 \(expected) 字节，实际 \(actual) 字节。"
        case .digestMismatch:
            return "安装包 SHA-256 与 GitHub Release 摘要不一致。"
        }
    }
}

public enum AppUpdatePackageVerifier {
    public static func verify(fileAt url: URL, package: AppUpdatePackage) throws {
        guard package.byteCount > 0 else {
            throw AppUpdatePackageVerificationError.invalidFile
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw AppUpdatePackageVerificationError.invalidFile
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        guard fileSize == UInt64(package.byteCount) else {
            throw AppUpdatePackageVerificationError.sizeMismatch(
                expected: package.byteCount,
                actual: fileSize > UInt64(Int64.max) ? Int64.max : Int64(fileSize)
            )
        }
        try handle.seek(toOffset: 0)
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        let actualDigest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard actualDigest == package.sha256 else {
            throw AppUpdatePackageVerificationError.digestMismatch
        }
    }
}
