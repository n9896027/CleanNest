import CryptoKit
import Foundation
import XCTest
@testable import CleanNestCore

final class AppUpdateTests: XCTestCase {
    func testSemanticVersionComparisonHandlesPrefixBuildAndPrerelease() throws {
        let current = try XCTUnwrap(SemanticVersion(parsing: "0.4.0"))
        let next = try XCTUnwrap(SemanticVersion(parsing: "v0.4.1+universal"))
        let releaseCandidate2 = try XCTUnwrap(SemanticVersion(parsing: "1.0.0-rc.2"))
        let releaseCandidate10 = try XCTUnwrap(SemanticVersion(parsing: "1.0.0-rc.10"))
        let final = try XCTUnwrap(SemanticVersion(parsing: "1.0.0"))

        XCTAssertLessThan(current, next)
        XCTAssertLessThan(releaseCandidate2, releaseCandidate10)
        XCTAssertLessThan(releaseCandidate10, final)
        XCTAssertNil(SemanticVersion(parsing: "main"))
        XCTAssertNil(SemanticVersion(parsing: "1.2"))
    }

    func testReleaseParserAcceptsOnlyOfficialPublishedRepositoryURL() throws {
        let release = try GitHubReleaseParser.parse(
            data: releaseData(tag: "v0.4.1"),
            owner: "n9896027",
            repository: "CleanNest"
        )

        XCTAssertEqual(release.version, SemanticVersion(parsing: "0.4.1"))
        XCTAssertEqual(release.pageURL.host, "github.com")
        XCTAssertNil(release.installerPackage)
        XCTAssertEqual(
            try AppUpdatePolicy.decision(localVersion: "0.4.0", release: release),
            .updateAvailable
        )
        XCTAssertEqual(
            try AppUpdatePolicy.decision(localVersion: "0.4.1", release: release),
            .upToDate
        )
        XCTAssertEqual(
            try AppUpdatePolicy.decision(localVersion: "0.5.0", release: release),
            .localVersionAhead
        )
    }

    func testReleaseParserRejectsDraftPrereleaseAndRedirectedDownloadPage() throws {
        XCTAssertThrowsError(
            try GitHubReleaseParser.parse(
                data: releaseData(tag: "v0.4.1", draft: true),
                owner: "n9896027",
                repository: "CleanNest"
            )
        )
        XCTAssertThrowsError(
            try GitHubReleaseParser.parse(
                data: releaseData(tag: "v0.4.1", prerelease: true),
                owner: "n9896027",
                repository: "CleanNest"
            )
        )
        XCTAssertThrowsError(
            try GitHubReleaseParser.parse(
                data: releaseData(
                    tag: "v0.4.1",
                    htmlURL: "https://example.com/n9896027/CleanNest/releases/tag/v0.4.1"
                ),
                owner: "n9896027",
                repository: "CleanNest"
            )
        )
        XCTAssertThrowsError(
            try GitHubReleaseParser.parse(
                data: releaseData(
                    tag: "v0.4.1",
                    htmlURL: "https://github.com/other/CleanNest/releases/tag/v0.4.1"
                ),
                owner: "n9896027",
                repository: "CleanNest"
            )
        )
    }

    func testReleaseParserAcceptsUniqueVersionedInstallerPackage() throws {
        let release = try GitHubReleaseParser.parse(
            data: releaseData(tag: "v0.4.1", assets: [validAsset()]),
            owner: "n9896027",
            repository: "CleanNest"
        )
        let package = try XCTUnwrap(release.installerPackage)

        XCTAssertEqual(package.name, "CleanNest-0.4.1-51.pkg")
        XCTAssertEqual(package.byteCount, 1_024)
        XCTAssertEqual(package.sha256, String(repeating: "a", count: 64))
        XCTAssertTrue(
            GitHubReleaseParser.isTrustedPackageURL(
                package.downloadURL,
                package: package,
                owner: "n9896027",
                repository: "CleanNest",
                tagName: release.tagName
            )
        )
        XCTAssertTrue(
            GitHubReleaseParser.isTrustedPackageResponseURL(
                URL(string: "https://release-assets.githubusercontent.com/github-production-release-asset/asset?signature=redacted")!,
                package: package,
                owner: "n9896027",
                repository: "CleanNest",
                tagName: release.tagName
            )
        )
        XCTAssertFalse(
            GitHubReleaseParser.isTrustedPackageResponseURL(
                URL(string: "https://example.com/CleanNest.pkg")!,
                package: package,
                owner: "n9896027",
                repository: "CleanNest",
                tagName: release.tagName
            )
        )
    }

    func testReleaseParserAllowsReleaseWithoutInstallerAssets() throws {
        let release = try GitHubReleaseParser.parse(
            data: releaseData(
                tag: "v0.4.1",
                assets: [[
                    "name": "SHA256SUMS",
                    "state": "uploaded",
                    "size": 100,
                    "digest": "sha256:\(String(repeating: "a", count: 64))",
                    "browser_download_url": "https://github.com/n9896027/CleanNest/releases/download/v0.4.1/SHA256SUMS"
                ]]
            ),
            owner: "n9896027",
            repository: "CleanNest"
        )

        XCTAssertNil(release.installerPackage)
    }

    func testReleaseParserRejectsUntrustedInstallerURL() {
        var asset = validAsset()
        asset["browser_download_url"] = "https://example.com/n9896027/CleanNest/releases/download/v0.4.1/CleanNest-0.4.1-51.pkg"

        XCTAssertThrowsError(
            try GitHubReleaseParser.parse(
                data: releaseData(tag: "v0.4.1", assets: [asset]),
                owner: "n9896027",
                repository: "CleanNest"
            )
        ) { error in
            XCTAssertEqual(error as? GitHubReleaseParsingError, .untrustedPackageURL)
        }
    }

    func testReleaseParserRejectsBadDigestDuplicateAndWrongNamedPackages() {
        var badDigest = validAsset()
        badDigest["digest"] = "sha256:not-a-sha256"
        assertInvalidPackage(assets: [badDigest])

        var missingDigest = validAsset()
        missingDigest.removeValue(forKey: "digest")
        assertInvalidPackage(assets: [missingDigest])

        var duplicate = validAsset()
        duplicate["browser_download_url"] = "https://github.com/n9896027/CleanNest/releases/download/v0.4.1/CleanNest-0.4.1-52.pkg"
        duplicate["name"] = "CleanNest-0.4.1-52.pkg"
        assertInvalidPackage(assets: [validAsset(), duplicate])

        var wrongName = validAsset()
        wrongName["name"] = "Other-0.4.1-51.pkg"
        wrongName["browser_download_url"] = "https://github.com/n9896027/CleanNest/releases/download/v0.4.1/Other-0.4.1-51.pkg"
        assertInvalidPackage(assets: [wrongName])
    }

    func testReleaseParserRejectsInvalidInstallerSizeAndUploadState() {
        var empty = validAsset()
        empty["size"] = 0
        assertInvalidPackage(assets: [empty])

        var oversized = validAsset()
        oversized["size"] = AppUpdatePackage.maximumByteCount + 1
        assertInvalidPackage(assets: [oversized])

        var pending = validAsset()
        pending["state"] = "open"
        assertInvalidPackage(assets: [pending])
    }

    func testAutomaticCheckPolicyUsesTwentyFourHourInterval() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let recent = now.addingTimeInterval(-23 * 60 * 60)
        let old = now.addingTimeInterval(-24 * 60 * 60)

        XCTAssertFalse(AppUpdateAutomaticCheckPolicy.shouldCheck(isEnabled: false, lastAttemptAt: nil, now: now))
        XCTAssertTrue(AppUpdateAutomaticCheckPolicy.shouldCheck(isEnabled: true, lastAttemptAt: nil, now: now))
        XCTAssertFalse(AppUpdateAutomaticCheckPolicy.shouldCheck(isEnabled: true, lastAttemptAt: recent, now: now))
        XCTAssertTrue(AppUpdateAutomaticCheckPolicy.shouldCheck(isEnabled: true, lastAttemptAt: old, now: now))
        XCTAssertTrue(AppUpdateAutomaticCheckPolicy.shouldCheck(isEnabled: true, lastAttemptAt: now.addingTimeInterval(60), now: now))
    }

    func testPackageVerifierChecksSizeAndSHA256() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent("CleanNest.pkg")
        let bytes = Data("CleanNest signed package fixture".utf8)
        try bytes.write(to: fileURL)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let package = AppUpdatePackage(
            name: "CleanNest-0.4.1-51.pkg",
            downloadURL: URL(string: "https://github.com/n9896027/CleanNest/releases/download/v0.4.1/CleanNest-0.4.1-51.pkg")!,
            byteCount: Int64(bytes.count),
            sha256: digest
        )

        XCTAssertNoThrow(try AppUpdatePackageVerifier.verify(fileAt: fileURL, package: package))

        try Data("tampered".utf8).write(to: fileURL)
        XCTAssertThrowsError(try AppUpdatePackageVerifier.verify(fileAt: fileURL, package: package)) { error in
            guard case AppUpdatePackageVerificationError.sizeMismatch = error else {
                return XCTFail("Expected size mismatch, got \(error)")
            }
        }

        try Data(repeating: 0, count: bytes.count).write(to: fileURL)
        XCTAssertThrowsError(try AppUpdatePackageVerifier.verify(fileAt: fileURL, package: package)) { error in
            XCTAssertEqual(error as? AppUpdatePackageVerificationError, .digestMismatch)
        }

        let invalidPackage = AppUpdatePackage(
            name: package.name,
            downloadURL: package.downloadURL,
            byteCount: -1,
            sha256: package.sha256
        )
        XCTAssertThrowsError(try AppUpdatePackageVerifier.verify(fileAt: fileURL, package: invalidPackage)) { error in
            XCTAssertEqual(error as? AppUpdatePackageVerificationError, .invalidFile)
        }
    }

    func testRateLimitPolicyDistinguishesOrdinary403AndHonorsRetrySignals() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        XCTAssertNil(AppUpdateRateLimitPolicy.retryAt(
            statusCode: 403,
            headers: ["X-RateLimit-Remaining": "17"],
            now: now
        ))
        XCTAssertEqual(
            AppUpdateRateLimitPolicy.retryAt(
                statusCode: 403,
                headers: ["retry-after": "120"],
                now: now
            ),
            now.addingTimeInterval(120)
        )
        XCTAssertEqual(
            AppUpdateRateLimitPolicy.retryAt(
                statusCode: 429,
                headers: [:],
                now: now
            ),
            now.addingTimeInterval(AppUpdateRateLimitPolicy.fallbackDelay)
        )
        XCTAssertEqual(
            AppUpdateRateLimitPolicy.retryAt(
                statusCode: 403,
                headers: [
                    "X-RateLimit-Remaining": "0",
                    "X-RateLimit-Reset": "2000000300"
                ],
                now: now
            ),
            Date(timeIntervalSince1970: 2_000_000_300)
        )
    }

    func testAutomaticPolicyUsesSuccessAndRetryDeadlineRatherThanBlockingOnFailure() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let failedAttempt = now.addingTimeInterval(-60)
        XCTAssertTrue(AppUpdateAutomaticCheckPolicy.shouldCheck(
            isEnabled: true,
            lastAttemptAt: failedAttempt,
            lastSuccessfulAt: now.addingTimeInterval(-25 * 3_600),
            now: now
        ))
        XCTAssertFalse(AppUpdateAutomaticCheckPolicy.shouldCheck(
            isEnabled: true,
            lastAttemptAt: failedAttempt,
            lastSuccessfulAt: now.addingTimeInterval(-3_600),
            now: now
        ))
        XCTAssertFalse(AppUpdateAutomaticCheckPolicy.shouldCheck(
            isEnabled: true,
            lastAttemptAt: failedAttempt,
            nextAllowedAttemptAt: now.addingTimeInterval(60),
            now: now
        ))
        XCTAssertTrue(AppUpdateAutomaticCheckPolicy.shouldCheck(
            isEnabled: true,
            lastAttemptAt: failedAttempt,
            nextAllowedAttemptAt: now.addingTimeInterval(-1),
            now: now
        ))
    }

    func testVerifiedPackagePersistsTrustAndRejectsMissingChangedOrDifferentAsset() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestVerifiedPackageTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("CleanNest-0.12.3-53.pkg")
        let bytes = Data("signed package fixture".utf8)
        try bytes.write(to: url)
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let package = AppUpdatePackage(
            name: url.lastPathComponent,
            downloadURL: URL(string: "https://github.com/n9896027/CleanNest/releases/download/v0.12.3/CleanNest-0.12.3-53.pkg")!,
            byteCount: Int64(bytes.count),
            sha256: digest,
            version: "0.12.3",
            build: "53"
        )
        let release = GitHubReleaseInfo(
            version: SemanticVersion(parsing: "0.12.3")!,
            tagName: "v0.12.3",
            title: "CleanNest 0.12.3",
            notes: "fixture",
            pageURL: URL(string: "https://github.com/n9896027/CleanNest/releases/tag/v0.12.3")!,
            publishedAt: nil,
            installerPackage: package
        )
        let verified = try VerifiedAppUpdatePackage(
            releaseVersion: "0.12.3",
            releaseBuild: "53",
            package: package,
            fileURL: url,
            trust: AppUpdateInstallerTrustEvidence(teamIdentifier: "NC33STD88A")
        )
        XCTAssertTrue(verified.matches(release: release))
        XCTAssertNoThrow(try verified.revalidate())
        let decoded = try JSONDecoder().decode(
            VerifiedAppUpdatePackage.self,
            from: JSONEncoder().encode(verified)
        )
        XCTAssertNoThrow(try decoded.revalidate())
        XCTAssertFalse(decoded.trust.developerIDInstallerVerified == false)

        let changedPackage = AppUpdatePackage(
            name: "CleanNest-0.12.3-54.pkg",
            downloadURL: URL(string: "https://github.com/n9896027/CleanNest/releases/download/v0.12.3/CleanNest-0.12.3-54.pkg")!,
            byteCount: package.byteCount,
            sha256: package.sha256,
            version: "0.12.3",
            build: "54"
        )
        let changedRelease = GitHubReleaseInfo(
            version: release.version,
            tagName: release.tagName,
            title: release.title,
            notes: release.notes,
            pageURL: release.pageURL,
            publishedAt: nil,
            installerPackage: changedPackage
        )
        XCTAssertFalse(verified.matches(release: changedRelease))

        try Data(repeating: 0, count: bytes.count).write(to: url)
        XCTAssertThrowsError(try verified.revalidate())
        try FileManager.default.removeItem(at: url)
        XCTAssertThrowsError(try verified.revalidate()) { error in
            XCTAssertEqual(error as? AppUpdateCachedPackageError, .missingOrChanged)
        }
    }

    private func assertInvalidPackage(
        assets: [[String: Any]],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try GitHubReleaseParser.parse(
                data: releaseData(tag: "v0.4.1", assets: assets),
                owner: "n9896027",
                repository: "CleanNest"
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(error as? GitHubReleaseParsingError, .invalidInstallerPackage, file: file, line: line)
        }
    }

    private func validAsset() -> [String: Any] {
        [
            "name": "CleanNest-0.4.1-51.pkg",
            "state": "uploaded",
            "size": 1_024,
            "digest": "sha256:\(String(repeating: "a", count: 64))",
            "browser_download_url": "https://github.com/n9896027/CleanNest/releases/download/v0.4.1/CleanNest-0.4.1-51.pkg"
        ]
    }

    private func releaseData(
        tag: String,
        draft: Bool = false,
        prerelease: Bool = false,
        htmlURL: String = "https://github.com/n9896027/CleanNest/releases/tag/v0.4.1",
        assets: [[String: Any]]? = nil
    ) -> Data {
        var response: [String: Any] = [
            "tag_name": tag,
            "name": "CleanNest \(tag)",
            "body": "A safe update.",
            "html_url": htmlURL,
            "draft": draft,
            "prerelease": prerelease,
            "published_at": "2026-08-23T12:00:00Z"
        ]
        if let assets { response["assets"] = assets }
        // Fixtures are constructed entirely from valid JSON values above.
        return try! JSONSerialization.data(withJSONObject: response)
    }
}
