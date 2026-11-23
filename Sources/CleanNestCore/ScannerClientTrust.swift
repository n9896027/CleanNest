import Foundation
import Security

/// The embedded XPC service accepts only the CleanNest app signed by the same
/// identity. Distribution builds pin the Developer ID issuer, certificate type,
/// team and bundle identifier; local self-signed builds pin the signing root.
public enum ScannerClientTrust {
    static let clientIdentifier = "com.zone.cleannest"
    private static let baseline = "identifier \"\(clientIdentifier)\""

    /// NSXPCConnection raises an Objective-C exception, rather than a Swift
    /// error, for an invalid requirement. Parse with Security first so a bad
    /// rule rejects the connection instead of terminating the scanner process.
    static func validatedRequirement(_ text: String) -> String? {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            text as CFString,
            SecCSFlags(rawValue: 0),
            &requirement
        ) == errSecSuccess, requirement != nil else { return nil }
        return text
    }

    public static func requirement() -> String? {
        validatedRequirement(unvalidatedRequirement())
    }

    private static func unvalidatedRequirement() -> String {
        let flags = SecCSFlags(rawValue: 0)
        var code: SecCode?
        guard SecCodeCopySelf(flags, &code) == errSecSuccess, let code else { return baseline }
        return requirement(for: code, flags: flags)
    }

    private static func requirement(for code: SecCode, flags: SecCSFlags) -> String {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, flags, &staticCode) == errSecSuccess,
              let staticCode else { return baseline }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess, let dict = info as? [String: Any] else { return baseline }

        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return developerIDRequirement(team: team)
        }

        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, flags, &requirement) == errSecSuccess,
              let requirement else { return baseline }
        var text: CFString?
        guard SecRequirementCopyString(requirement, flags, &text) == errSecSuccess,
              let designated = text as String?,
              let marker = designated.range(of: "certificate root = H\"") else { return baseline }
        let fingerprint = designated[marker.upperBound...].prefix { $0 != "\"" }
        guard !fingerprint.isEmpty else { return baseline }
        return "identifier \"\(clientIdentifier)\" and certificate root = H\"\(fingerprint)\""
    }

    static func developerIDRequirement(team: String) -> String {
        // Apple TN3127's Developer ID Application designated requirement.
        // `teamidentifier` is not a supported requirement-language token.
        "identifier \"\(clientIdentifier)\" and anchor apple generic " +
            "and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ " +
            "and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ " +
            "and certificate leaf[subject.OU] = \"\(team)\""
    }
}
