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

public struct GitHubReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let tagName: String
    public let title: String
    public let notes: String
    public let pageURL: URL
    public let publishedAt: Date?

    public init(
        version: SemanticVersion,
        tagName: String,
        title: String,
        notes: String,
        pageURL: URL,
        publishedAt: Date?
    ) {
        self.version = version
        self.tagName = tagName
        self.title = title
        self.notes = notes
        self.pageURL = pageURL
        self.publishedAt = publishedAt
    }
}

public enum GitHubReleaseParsingError: LocalizedError, Equatable, Sendable {
    case responseTooLarge
    case invalidResponse
    case unpublishedRelease
    case invalidVersionTag(String)
    case untrustedReleaseURL

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

        return GitHubReleaseInfo(
            version: version,
            tagName: response.tagName,
            title: trimmedTitle.isEmpty ? response.tagName : trimmedTitle,
            notes: String(trimmedNotes.prefix(12_000)),
            pageURL: pageURL,
            publishedAt: response.publishedAt
        )
    }

    private struct ReleaseResponse: Decodable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
            case draft
            case prerelease
            case publishedAt = "published_at"
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
