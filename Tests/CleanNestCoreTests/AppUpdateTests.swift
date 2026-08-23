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

    private func releaseData(
        tag: String,
        draft: Bool = false,
        prerelease: Bool = false,
        htmlURL: String = "https://github.com/n9896027/CleanNest/releases/tag/v0.4.1"
    ) -> Data {
        Data(
            """
            {
              "tag_name": "\(tag)",
              "name": "CleanNest \(tag)",
              "body": "A safe update.",
              "html_url": "\(htmlURL)",
              "draft": \(draft),
              "prerelease": \(prerelease),
              "published_at": "2026-08-23T12:00:00Z"
            }
            """.utf8
        )
    }
}
