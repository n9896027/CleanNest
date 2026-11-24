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

public enum AgentDesktopProductDetector {
    /// Exact metadata, valid code signature and an allow-listed signer are all
    /// mandatory. Names, websites, caches and process names never establish an
    /// installed desktop product by themselves.
    public static func installations(
        catalog: AgentRuleCatalog,
        applications: [InstalledApplication],
        signature: (URL) -> AgentDesktopSignatureEvidence = inspectSignature
    ) -> [AgentDesktopInstallation] {
        var results: [AgentDesktopInstallation] = []
        var seenPaths = Set<String>()
        for rule in catalog.desktopProducts where rule.verification == .verifiedOfficialSample {
            let candidates = applications.filter {
                guard let identifier = $0.bundleIdentifier else { return false }
                return rule.bundleIdentifiers.contains(identifier)
            }
            for application in candidates
            where seenPaths.insert(application.url.resolvingSymlinksInPath().standardizedFileURL.path).inserted {
                let evidence = signature(application.url)
                guard evidence.isValid,
                      evidence.signingIdentifier == application.bundleIdentifier,
                      let team = evidence.teamIdentifier,
                      rule.allowedTeamIdentifiers.contains(team) else { continue }
                results.append(AgentDesktopInstallation(
                    rule: rule,
                    application: application,
                    teamIdentifier: team,
                    ruleRevision: catalog.revision
                ))
            }
        }
        return results.sorted { $0.copyID < $1.copyID }
    }

    public static func inspectSignature(at url: URL) -> AgentDesktopSignatureEvidence {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return AgentDesktopSignatureEvidence(isValid: false, signingIdentifier: nil, teamIdentifier: nil)
        }
        let validation = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            nil
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

    public func scan(catalog: AgentRuleCatalog) async -> [AgentDesktopInstallation] {
        await Task.detached(priority: .userInitiated) {
            var applications = await ApplicationScanner(homeDirectory: homeDirectory).scan()
            var knownPaths = Set(applications.map { $0.url.resolvingSymlinksInPath().standardizedFileURL.path })
            let identifiers = Set(catalog.desktopProducts.flatMap(\.bundleIdentifiers))
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
            return AgentDesktopProductDetector.installations(catalog: catalog, applications: applications)
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
