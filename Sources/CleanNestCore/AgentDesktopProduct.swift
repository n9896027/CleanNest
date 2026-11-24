import CoreServices
import Foundation
import Security

/// A stable product identity is separate from the historical workspace-provider
/// enum. A signed rule bundle can therefore add a desktop product without a new
/// SwiftUI branch or changing the meaning of saved workspace observations.
public enum AgentDesktopProductVerification: String, Codable, Sendable {
    case verifiedOfficialSample
    case pendingOfficialSample
}

public enum AgentDesktopDataDisposition: String, Codable, Sendable {
    case regenerable
    case retained
}

public struct AgentDesktopDataRule: Codable, Equatable, Sendable {
    public let path: AgentRulePath
    public let disposition: AgentDesktopDataDisposition

    public init(path: AgentRulePath, disposition: AgentDesktopDataDisposition) {
        self.path = path
        self.disposition = disposition
    }
}

public struct AgentDesktopProductRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifiers: [String]
    public let allowedTeamIdentifiers: [String]
    public let applicationNames: [String]
    public let verification: AgentDesktopProductVerification
    public let legacyProvider: AgentWorkspaceProvider?
    public let privateData: [AgentDesktopDataRule]

    public init(
        id: String,
        displayName: String,
        bundleIdentifiers: [String],
        allowedTeamIdentifiers: [String],
        applicationNames: [String],
        verification: AgentDesktopProductVerification,
        legacyProvider: AgentWorkspaceProvider? = nil,
        privateData: [AgentDesktopDataRule] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifiers = bundleIdentifiers
        self.allowedTeamIdentifiers = allowedTeamIdentifiers
        self.applicationNames = applicationNames
        self.verification = verification
        self.legacyProvider = legacyProvider
        self.privateData = privateData
    }

    func validate() throws {
        let identifiers = [id] + bundleIdentifiers
        guard id.count <= 80, displayName.count <= 120,
              !id.isEmpty, !displayName.isEmpty,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              identifiers.allSatisfy({ !$0.isEmpty && $0.count <= 160 && !$0.contains("/") && !$0.contains("\0") }),
              !bundleIdentifiers.isEmpty,
              allowedTeamIdentifiers.allSatisfy({ $0.count == 10 }),
              allowedTeamIdentifiers.allSatisfy({ $0.count == 10 && $0.allSatisfy({ $0.isUppercase || $0.isNumber }) }),
              verification == .verifiedOfficialSample ? !allowedTeamIdentifiers.isEmpty : true,
              privateData.count <= 32 else {
            throw AgentRuleCatalogError.emptyDetectionRule(displayName)
        }
        for item in privateData {
            try AgentRuleCatalog.validate(dataPath: item.path.relativePath)
        }
    }
}

public struct AgentDesktopInstallation: Identifiable, Equatable, Sendable {
    public let productID: String
    public let copyID: String
    public let displayName: String
    public let application: InstalledApplication
    public let teamIdentifier: String
    public let ruleRevision: String

    public init(
        rule: AgentDesktopProductRule,
        application: InstalledApplication,
        teamIdentifier: String,
        ruleRevision: String
    ) {
        productID = rule.id
        copyID = rule.id + ":" + application.id
        displayName = rule.displayName
        self.application = application
        self.teamIdentifier = teamIdentifier
        self.ruleRevision = ruleRevision
    }

    public var id: String { copyID }
    public var bundleIdentifier: String { application.bundleIdentifier ?? "" }
    public var cacheKey: String {
        [productID, bundleIdentifier, application.buildVersion ?? application.version ?? "unknown", application.url.standardizedFileURL.path, ruleRevision]
            .joined(separator: "|")
    }
}

public struct AgentDesktopSignatureEvidence: Equatable, Sendable {
    public let isValid: Bool
    public let signingIdentifier: String?
    public let teamIdentifier: String?

    public init(isValid: Bool, signingIdentifier: String?, teamIdentifier: String?) {
        self.isValid = isValid
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
    }
}

public enum AgentDesktopCandidateIssue: Equatable, Sendable {
    case invalidSignature
    case unexpectedSigner
    case pendingOfficialSample
}

/// A bundle that declares a known product identifier but cannot be managed
/// safely. It remains visible without inheriting the product's trusted name or
/// receiving any mutation authority.
public struct AgentDesktopCandidate: Identifiable, Equatable, Sendable {
    public let productID: String
    public let copyID: String
    public let displayName: String
    public let expectedProductName: String
    public let application: InstalledApplication
    public let issue: AgentDesktopCandidateIssue
    public let signingIdentifier: String?
    public let teamIdentifier: String?

    public init(
        rule: AgentDesktopProductRule,
        application: InstalledApplication,
        issue: AgentDesktopCandidateIssue,
        signature: AgentDesktopSignatureEvidence
    ) {
        productID = rule.id
        copyID = rule.id + ":" + application.id
        displayName = application.name
        expectedProductName = rule.displayName
        self.application = application
        self.issue = issue
        signingIdentifier = signature.signingIdentifier
        teamIdentifier = signature.teamIdentifier
    }

    public var id: String { copyID }
}

public struct AgentDesktopInventorySnapshot: Equatable, Sendable {
    public let installations: [AgentDesktopInstallation]
    public let candidates: [AgentDesktopCandidate]
    public let relatedSoftware: [AgentRelatedSoftwareInstallation]

    public init(
        installations: [AgentDesktopInstallation],
        candidates: [AgentDesktopCandidate],
        relatedSoftware: [AgentRelatedSoftwareInstallation] = []
    ) {
        self.installations = installations
        self.candidates = candidates
        self.relatedSoftware = relatedSoftware
    }
}

public enum AgentDesktopProductDetector {
    /// Exact metadata, an Apple-anchored valid signature and an allow-listed
    /// signer are mandatory for Agent management. Related software is detected
    /// separately by functional role; its signature never promotes it to Agent.
    public static func inventory(
        catalog: AgentRuleCatalog,
        applications: [InstalledApplication],
        signature: (URL) -> AgentDesktopSignatureEvidence = inspectSignature
    ) -> AgentDesktopInventorySnapshot {
        var installations: [AgentDesktopInstallation] = []
        var candidates: [AgentDesktopCandidate] = []
        var relatedSoftware: [AgentRelatedSoftwareInstallation] = []
        var seenPaths = Set<String>()
        for rule in catalog.desktopProducts {
            for application in applications where rule.bundleIdentifiers.contains(application.bundleIdentifier ?? "") {
                let path = application.url.resolvingSymlinksInPath().standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                let evidence = signature(application.url)
                let expectedIdentity = evidence.signingIdentifier == application.bundleIdentifier
                let allowedSigner = evidence.teamIdentifier.map(rule.allowedTeamIdentifiers.contains) == true
                if rule.verification == .verifiedOfficialSample,
                   evidence.isValid, expectedIdentity, allowedSigner, let team = evidence.teamIdentifier {
                    installations.append(AgentDesktopInstallation(
                        rule: rule,
                        application: application,
                        teamIdentifier: team,
                        ruleRevision: catalog.revision
                    ))
                    continue
                }
                let issue: AgentDesktopCandidateIssue
                if !evidence.isValid {
                    issue = .invalidSignature
                } else if !expectedIdentity || !allowedSigner {
                    issue = .unexpectedSigner
                } else {
                    issue = .pendingOfficialSample
                }
                candidates.append(AgentDesktopCandidate(
                    rule: rule,
                    application: application,
                    issue: issue,
                    signature: evidence
                ))
            }
        }
        for rule in catalog.relatedSoftware {
            for application in applications where application.bundleIdentifier == rule.bundleIdentifier {
                let path = application.url.resolvingSymlinksInPath().standardizedFileURL.path
                guard seenPaths.insert(path).inserted else { continue }
                relatedSoftware.append(AgentRelatedSoftwareInstallation(
                    rule: rule,
                    application: application,
                    signature: signature(application.url)
                ))
            }
        }
        return AgentDesktopInventorySnapshot(
            installations: installations.sorted { $0.copyID < $1.copyID },
            candidates: candidates.sorted { $0.copyID < $1.copyID },
            relatedSoftware: relatedSoftware.sorted { $0.copyID < $1.copyID }
        )
    }

    public static func installations(
        catalog: AgentRuleCatalog,
        applications: [InstalledApplication],
        signature: (URL) -> AgentDesktopSignatureEvidence = inspectSignature
    ) -> [AgentDesktopInstallation] {
        inventory(catalog: catalog, applications: applications, signature: signature).installations
    }

    /// Read-only discovery deliberately uses a separate result type. A pending
    /// product or failed signature never receives uninstall authority.
    public static func unverifiedCandidates(
        catalog: AgentRuleCatalog,
        applications: [InstalledApplication],
        signature: (URL) -> AgentDesktopSignatureEvidence = inspectSignature
    ) -> [AgentDesktopCandidate] {
        inventory(catalog: catalog, applications: applications, signature: signature).candidates
    }

    public static func inspectSignature(at url: URL) -> AgentDesktopSignatureEvidence {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return AgentDesktopSignatureEvidence(isValid: false, signingIdentifier: nil, teamIdentifier: nil)
        }
        // A Team ID in an arbitrary self-signed certificate is not proof of an
        // official product. Require an Apple-anchored distribution chain first;
        // callers then compare the exact signing identifier and allowed team.
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            "anchor apple generic" as CFString,
            SecCSFlags(rawValue: 0),
            &requirement
        ) == errSecSuccess, let requirement else {
            return AgentDesktopSignatureEvidence(isValid: false, signingIdentifier: nil, teamIdentifier: nil)
        }
        let validation = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            requirement
        )
        var raw: CFDictionary?
        let copied = SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &raw)
        let information = copied == errSecSuccess ? raw as? [CFString: Any] : nil
        return AgentDesktopSignatureEvidence(
            isValid: validation == errSecSuccess,
            signingIdentifier: information?[kSecCodeInfoIdentifier] as? String,
            teamIdentifier: information?[kSecCodeInfoTeamIdentifier] as? String
        )
    }
}

public struct AgentDesktopProductInventory: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func scan(catalog: AgentRuleCatalog) async -> AgentDesktopInventorySnapshot {
        await Task.detached(priority: .userInitiated) {
            var applications = await ApplicationScanner(homeDirectory: homeDirectory).scan()
            var knownPaths = Set(applications.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })
            let identifiers = Set(catalog.desktopProducts.flatMap(\.bundleIdentifiers))
                .union(catalog.relatedSoftware.map(\.bundleIdentifier))
            for identifier in identifiers {
                guard let raw = LSCopyApplicationURLsForBundleIdentifier(identifier as CFString, nil)?.takeRetainedValue(),
                      let urls = raw as? [URL] else { continue }
                for url in urls where url.pathExtension.lowercased() == "app" {
                    let normalized = url.resolvingSymlinksInPath().standardizedFileURL
                    guard knownPaths.insert(normalized.path).inserted,
                          let application = Self.application(at: normalized) else { continue }
                    applications.append(application)
                }
            }
            return AgentDesktopProductDetector.inventory(catalog: catalog, applications: applications)
        }.value
    }

    private static func application(at url: URL) -> InstalledApplication? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { return nil }
        let bundle = Bundle(url: url)
        return InstalledApplication(
            name: bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundle?.bundleIdentifier,
            version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            url: url,
            allocatedBytes: FileTree.allocatedSize(of: url),
            modifiedAt: values?.contentModificationDate,
            fileIdentity: try? ApplicationFileIdentity.capture(at: url)
        )
    }
}
