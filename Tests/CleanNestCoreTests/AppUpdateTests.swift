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
