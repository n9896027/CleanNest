import XCTest
@testable import CleanNestCore

final class ScannerClientTrustTests: XCTestCase {
    func testDeveloperIDRequirementIsAcceptedBySecurity() {
        let text = ScannerClientTrust.developerIDRequirement(team: "NC33STD88A")

        XCTAssertNotNil(ScannerClientTrust.validatedRequirement(text))
        XCTAssertTrue(text.contains("identifier \"com.zone.cleannest\""))
        XCTAssertTrue(text.contains("anchor apple generic"))
        XCTAssertTrue(text.contains("certificate 1[field.1.2.840.113635.100.6.2.6]"))
        XCTAssertTrue(text.contains("certificate leaf[field.1.2.840.113635.100.6.1.13]"))
        XCTAssertTrue(text.contains("certificate leaf[subject.OU] = \"NC33STD88A\""))
    }

    func testUnsupportedTeamIdentifierTokenIsRejectedBeforeNSXPC() {
        let invalid = "identifier \"com.zone.cleannest\" and anchor apple generic " +
            "and teamidentifier \"NC33STD88A\""

        XCTAssertNil(ScannerClientTrust.validatedRequirement(invalid))
    }

    func testMalformedRequirementIsRejectedBeforeNSXPC() {
        XCTAssertNil(ScannerClientTrust.validatedRequirement("identifier \"unterminated"))
    }

    func testBundleIdentifierOnlyRequirementRemainsValidForLocalFallback() {
        let text = "identifier \"com.zone.cleannest\""

        XCTAssertEqual(ScannerClientTrust.validatedRequirement(text), text)
    }
}
