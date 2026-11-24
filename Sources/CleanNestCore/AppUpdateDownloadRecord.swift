import Darwin
import Foundation

/// File identity captured after a successful system package assessment. A path
/// alone never restores installation authority: size, digest and stable file
/// identity are all checked again before the installer is opened.
public struct AppUpdateCachedFileIdentity: Codable, Equatable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let byteCount: Int64
    public let modificationSeconds: Int64
    public let modificationNanoseconds: Int64

    public static func capture(at url: URL) throws -> Self {
        var value = stat()
        guard url.path.withCString({ lstat($0, &value) }) == 0 else {
            throw AppUpdateCachedPackageError.missingOrChanged
        }
        guard value.st_mode & S_IFMT == S_IFREG else {
            throw AppUpdateCachedPackageError.missingOrChanged
        }
        return Self(
            deviceID: UInt64(value.st_dev),
            fileID: UInt64(value.st_ino),
            byteCount: max(0, Int64(value.st_size)),
            modificationSeconds: Int64(value.st_mtimespec.tv_sec),
            modificationNanoseconds: Int64(value.st_mtimespec.tv_nsec)
        )
    }
}

public enum AppUpdateCachedPackageError: LocalizedError, Equatable, Sendable {
    case missingOrChanged
    case assetChanged

    public var errorDescription: String? {
        switch self {
        case .missingOrChanged:
            return "已下载安装包缺失或内容已经变化，已停止打开。请重新下载并校验。"
        case .assetChanged:
            return "Release 中的安装包已经变化，旧缓存不能继续使用。"
        }
    }
}

public struct AppUpdateInstallerTrustEvidence: Codable, Equatable, Sendable {
    public let teamIdentifier: String
    public let developerIDInstallerVerified: Bool
    public let gatekeeperAccepted: Bool
    public let assessedAt: Date

    /// Gatekeeper acceptance is deliberately not described as a stapled-ticket
    /// check. Release engineering verifies stapling separately on a Mac that
    /// has the notarytool/stapler toolchain.
    public init(teamIdentifier: String, assessedAt: Date = Date()) {
        self.teamIdentifier = teamIdentifier
        developerIDInstallerVerified = true
        gatekeeperAccepted = true
        self.assessedAt = assessedAt
    }
}

public struct VerifiedAppUpdatePackage: Codable, Equatable, Sendable {
    public let releaseVersion: String
    public let releaseBuild: String
    public let packageName: String
    public let downloadURL: URL
    public let byteCount: Int64
    public let sha256: String
    public let fileURL: URL
    public let fileIdentity: AppUpdateCachedFileIdentity
    public let trust: AppUpdateInstallerTrustEvidence

    public init(
        releaseVersion: String,
        releaseBuild: String,
        package: AppUpdatePackage,
        fileURL: URL,
        trust: AppUpdateInstallerTrustEvidence
    ) throws {
        guard !releaseVersion.isEmpty, !releaseBuild.isEmpty else {
            throw AppUpdateCachedPackageError.missingOrChanged
        }
        self.releaseVersion = releaseVersion
        self.releaseBuild = releaseBuild
        packageName = package.name
        downloadURL = package.downloadURL
        byteCount = package.byteCount
        sha256 = package.sha256.lowercased()
        self.fileURL = fileURL.standardizedFileURL
        fileIdentity = try AppUpdateCachedFileIdentity.capture(at: fileURL)
        self.trust = trust
        try revalidate()
    }

    public var package: AppUpdatePackage {
        AppUpdatePackage(
            name: packageName,
            downloadURL: downloadURL,
            byteCount: byteCount,
            sha256: sha256,
            version: releaseVersion,
            build: releaseBuild
        )
    }

    public func matches(release: GitHubReleaseInfo) -> Bool {
        guard let candidate = release.installerPackage else { return false }
        return releaseVersion == release.version.description
            && releaseBuild == candidate.build
            && package.isSameAsset(as: candidate)
    }

    public func revalidate() throws {
        let current = try AppUpdateCachedFileIdentity.capture(at: fileURL)
        guard current == fileIdentity, trust.developerIDInstallerVerified,
              trust.gatekeeperAccepted, trust.teamIdentifier == "NC33STD88A" else {
            throw AppUpdateCachedPackageError.missingOrChanged
        }
        try AppUpdatePackageVerifier.verify(fileAt: fileURL, package: package)
    }
}
