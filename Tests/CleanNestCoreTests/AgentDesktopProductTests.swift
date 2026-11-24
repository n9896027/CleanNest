import XCTest
@testable import CleanNestCore

final class AgentDesktopProductTests: XCTestCase {
    func testBuiltInGrokRuleIsBoundToVerifiedOfficialIdentity() throws {
        let grok = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first { $0.id == "grok-bot" })
        XCTAssertEqual(grok.bundleIdentifiers, ["com.anysphere.sand"])
        XCTAssertEqual(grok.allowedTeamIdentifiers, ["DCNK4UB866"])
        XCTAssertFalse(AgentRuleCatalog.builtIn.desktopProducts.contains { $0.id.localizedCaseInsensitiveContains("muse") })
    }

    func testLegacyCatalogDecodesAndMergedBaselineAddsOnlyMissingProducts() throws {
        struct Legacy: Encodable {
            let schemaVersion: Int
            let revision: String
            let issuedAt: Date
            let providers: [AgentProviderRule]
        }
        let legacy = Legacy(schemaVersion: 1, revision: "signed-old", issuedAt: Date(), providers: AgentRuleCatalog.builtIn.providers)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AgentRuleCatalog.self, from: encoder.encode(legacy))
        XCTAssertTrue(decoded.desktopProducts.isEmpty)
        let merged = try decoded.mergingBuiltInBaseline()
        XCTAssertEqual(merged.desktopProducts.map(\.id), ["grok-bot"])
        XCTAssertEqual(Set(merged.providers.map(\.provider)), Set(AgentWorkspaceProvider.allCases))
    }

    func testExactBundleValidSignatureAndSignerAreRequiredForEveryCopy() {
        let first = application(path: "/Applications/Grok Bot.app")
        let second = application(path: "/tmp/Grok Bot Copy.app")
        let renamedImpostor = InstalledApplication(
            name: "Grok Bot", bundleIdentifier: "local.muse.lookalike", version: "1",
            url: URL(fileURLWithPath: "/Applications/Muse.app"), allocatedBytes: 0, modifiedAt: nil
        )
        let detected = AgentDesktopProductDetector.installations(
            catalog: .builtIn,
            applications: [first, second, renamedImpostor]
        ) { url in
            if url == second.url {
                return AgentDesktopSignatureEvidence(isValid: true, signingIdentifier: "com.anysphere.sand", teamIdentifier: "WRONGTEAM1")
            }
            return AgentDesktopSignatureEvidence(isValid: true, signingIdentifier: "com.anysphere.sand", teamIdentifier: "DCNK4UB866")
        }
        XCTAssertEqual(detected.map(\.application.url), [first.url])
        XCTAssertEqual(detected.first?.productID, "grok-bot")
        XCTAssertNotEqual(detected.first?.copyID, detected.first?.productID)
    }

    func testInvalidSignatureCannotBecomeAnInstallation() {
        let detected = AgentDesktopProductDetector.installations(catalog: .builtIn, applications: [application(path: "/Applications/Grok Bot.app")]) { _ in
            AgentDesktopSignatureEvidence(isValid: false, signingIdentifier: "com.anysphere.sand", teamIdentifier: "DCNK4UB866")
        }
        XCTAssertTrue(detected.isEmpty)
    }

    func testProductGraphKeepsApplicationDataReadOnlyAndTracksProductID() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let product = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first)
        let privateData = try XCTUnwrap(product.privateData.first { $0.disposition == .retained })
        let url = privateData.path.resolve(homeDirectory: home)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let appURL = home.appendingPathComponent("Grok Bot.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        let app = application(path: appURL.path)
        let graph = ApplicationDependencyGraph(
            applicationID: app.id, capturedAt: Date(),
            codeSignature: ApplicationCodeSignatureEvidence(status: .valid, signingIdentifier: app.bundleIdentifier, teamIdentifier: "DCNK4UB866", applicationGroups: [], diagnostic: "fixture"),
            registration: ApplicationRegistrationEvidence(bundleIdentifier: app.bundleIdentifier, registeredURLs: [], scannedPathIsRegistered: false, diagnostic: "fixture"),
            nodes: [], diagnostic: "fixture"
        ).includingDesktopProduct(product, homeDirectory: home)
        XCTAssertEqual(graph.productID, "grok-bot")
        XCTAssertEqual(graph.separatelyRemovableNodes, [])
        XCTAssertTrue(graph.nodes.contains { $0.url == url && $0.isReadOnly && $0.productID == "grok-bot" })
    }

    func testOfficialGrokSampleUsesProductionSignatureValidation() throws {
        guard let path = ProcessInfo.processInfo.environment["CLEANNEST_GROK_SAMPLE_APP"], !path.isEmpty else {
            throw XCTSkip("Set CLEANNEST_GROK_SAMPLE_APP to run the read-only official sample release check.")
        }
        let installations = AgentDesktopProductDetector.installations(
            catalog: .builtIn,
            applications: [application(path: path)]
        )
        let installation = try XCTUnwrap(installations.first)
        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installation.bundleIdentifier, "com.anysphere.sand")
        XCTAssertEqual(installation.teamIdentifier, "DCNK4UB866")
        XCTAssertEqual(installation.application.version, "1.2.3")
    }

    func testSignedCatalogCanAddThirdBrandWithoutProviderOrUIChanges() throws {
        let thirdBrand = AgentDesktopProductRule(
            id: "synthetic-third-agent",
            displayName: "Synthetic Third Agent",
            bundleIdentifiers: ["com.example.synthetic-third-agent"],
            allowedTeamIdentifiers: ["TESTTEAM12"],
            applicationNames: ["Synthetic Third Agent"],
            verification: .verifiedOfficialSample
        )
        let catalog = try AgentRuleCatalog(
            revision: "signed-third-brand-fixture",
            issuedAt: Date(timeIntervalSince1970: 1_795_478_401),
            providers: AgentRuleCatalog.builtIn.providers,
            desktopProducts: AgentRuleCatalog.builtIn.desktopProducts + [thirdBrand]
        )
        let app = InstalledApplication(
            name: "Renamed Third Agent Copy",
            bundleIdentifier: "com.example.synthetic-third-agent",
            version: "4.5",
            buildVersion: "67",
            url: URL(fileURLWithPath: "/tmp/Third Agent Custom Location.app"),
            allocatedBytes: 0,
            modifiedAt: nil
        )
        let installations = AgentDesktopProductDetector.installations(catalog: catalog, applications: [app]) { _ in
            AgentDesktopSignatureEvidence(
                isValid: true,
                signingIdentifier: "com.example.synthetic-third-agent",
                teamIdentifier: "TESTTEAM12"
            )
        }
        let installation = try XCTUnwrap(installations.first)
        XCTAssertEqual(installations.count, 1)
        XCTAssertEqual(installation.productID, "synthetic-third-agent")
        XCTAssertEqual(installation.displayName, "Synthetic Third Agent")
        XCTAssertEqual(installation.application.url, app.url)
        XCTAssertNil(thirdBrand.legacyProvider)
        XCTAssertEqual(AgentWorkspaceProvider.allCases.count, catalog.providers.count)
    }

    func testProductRuleCannotIntroduceNewDeletionPath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let grok = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first)
        let importedProduct = AgentDesktopProductRule(
            id: grok.id,
            displayName: grok.displayName,
            bundleIdentifiers: grok.bundleIdentifiers,
            allowedTeamIdentifiers: grok.allowedTeamIdentifiers,
            applicationNames: grok.applicationNames,
            verification: grok.verification,
            privateData: [AgentDesktopDataRule(
                path: AgentRulePath(base: .caches, relativePath: "OtherSoftware/ImportantData"),
                disposition: .regenerable
            )]
        )
        let url = importedProduct.privateData[0].path.resolve(homeDirectory: home)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let app = application(path: home.appendingPathComponent("Grok Bot.app").path)
        let graph = ApplicationDependencyGraph(
            applicationID: app.id, capturedAt: Date(),
            codeSignature: ApplicationCodeSignatureEvidence(status: .valid, signingIdentifier: app.bundleIdentifier, teamIdentifier: "DCNK4UB866", applicationGroups: [], diagnostic: "fixture"),
            registration: ApplicationRegistrationEvidence(bundleIdentifier: app.bundleIdentifier, registeredURLs: [], scannedPathIsRegistered: false, diagnostic: "fixture"),
            nodes: [], diagnostic: "fixture"
        ).includingDesktopProduct(importedProduct, homeDirectory: home)
        XCTAssertTrue(graph.separatelyRemovableNodes.isEmpty)
        XCTAssertTrue(graph.nodes.contains { $0.url == url && $0.isReadOnly })
    }

    private func application(path: String) -> InstalledApplication {
        InstalledApplication(name: "Grok Bot", bundleIdentifier: "com.anysphere.sand", version: "1.2.3", buildVersion: "1.2.3", url: URL(fileURLWithPath: path), allocatedBytes: 0, modifiedAt: nil)
    }
}
