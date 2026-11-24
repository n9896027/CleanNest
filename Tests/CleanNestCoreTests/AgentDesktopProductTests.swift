import XCTest
@testable import CleanNestCore

final class AgentDesktopProductTests: XCTestCase {
    private let expectedVerifiedIdentities: [String: [String]] = [
        "chatgpt": ["com.openai.codex", "2DC432GLL2"],
        "claude": ["com.anthropic.claudefordesktop", "Q6L2SF6YDW"],
        "doubao": ["com.bot.neotix.doubao", "96L78H6LMH"],
        "gemini": ["com.google.GeminiMacOS", "EQHXZ8M8AV"],
        "grok-bot": ["com.anysphere.sand", "DCNK4UB866"],
        "kimi": ["com.moonshot.kimichat", "2J9472RW75"],
        "minimax-design": ["com.minimax.hub.global", "5Y7L83QLXD"],
        "muse": ["com.meta.endo", "V9WTTPBFK9"],
        "newmax": ["cc.newmax.desktop", "22HUP6KLKD"],
        "tabbit": ["com.tabbit-ai.Tabbit", "2DE8QTFYGR"],
        "zcode": ["dev.zcode.app", "8A5X4JJ39T"],
        "xiaoyunque": ["com.bytedance.pippit.xiaoyunque", "JH23ZR9LF5"]
    ]

    private let expectedPendingProducts = Set(["hermes-studio", "pi-agent", "workbuddy"])

    private let expectedRelatedSoftware: [String: (String, AgentRelatedSoftwareRole)] = [
        "cc-switch": ("com.ccswitch.desktop", .configurationTool),
        "claude-code-url-handler": ("com.anthropic.claude-code-url-handler", .urlHandler),
        "hermes-helper-shell": ("com.tianshu.hermes.shell", .helperShell),
        "kimi-cu": ("ai.kimi.cu", .bundledComponent),
        "minimax-hub-2-launcher": ("local.zone.minimax-hub2", .localLauncher),
        "ollama": ("com.electron.ollama", .localModelRunner),
        "workdaddy": ("com.workdaddy.launcher", .automationLauncher),
        "yuanhub": ("io.github.creatorhub.desktop", .automationWorkbench)
    ]

    func testBuiltInProductsMatchIndependentlyRecordedSampleIdentities() throws {
        let products = AgentRuleCatalog.builtIn.desktopProducts
        let verified = products.filter { $0.verification == .verifiedOfficialSample }
        XCTAssertEqual(products.count, 15)
        XCTAssertEqual(Set(verified.map(\.id)), Set(expectedVerifiedIdentities.keys))
        XCTAssertEqual(
            Set(products.filter { $0.verification == .pendingOfficialSample }.map(\.id)),
            expectedPendingProducts
        )
        for (productID, identity) in expectedVerifiedIdentities {
            let product = try XCTUnwrap(products.first { $0.id == productID })
            XCTAssertEqual(product.bundleIdentifiers, [identity[0]], productID)
            XCTAssertEqual(product.allowedTeamIdentifiers, [identity[1]], productID)
        }
        let muse = try XCTUnwrap(products.first { $0.id == "muse" })
        XCTAssertEqual(muse.bundleIdentifiers, ["com.meta.endo"])
        XCTAssertEqual(muse.allowedTeamIdentifiers, ["V9WTTPBFK9"])
    }

    func testFunctionalRolesCoverAllEightRelatedAppsWithoutCountingThemAsAgents() {
        let related = AgentRuleCatalog.builtIn.relatedSoftware
        XCTAssertEqual(related.count, 8)
        XCTAssertEqual(Set(related.map(\.id)), Set(expectedRelatedSoftware.keys))
        for item in related {
            XCTAssertEqual(item.bundleIdentifier, expectedRelatedSoftware[item.id]?.0, item.id)
            XCTAssertEqual(item.role, expectedRelatedSoftware[item.id]?.1, item.id)
        }
        XCTAssertTrue(AgentRuleCatalog.builtIn.desktopProducts.allSatisfy { product in
            !expectedRelatedSoftware.keys.contains(product.id)
        })
    }

    func testValidSignatureNeverPromotesRelatedSoftwareToAgent() {
        let applications = AgentRuleCatalog.builtIn.relatedSoftware.map { rule in
            application(
                path: "/Applications/\(rule.displayName).app",
                name: rule.displayName,
                bundleIdentifier: rule.bundleIdentifier
            )
        }
        let inventory = AgentDesktopProductDetector.inventory(catalog: .builtIn, applications: applications) { url in
            let identifier = applications.first { $0.url == url }?.bundleIdentifier
            return AgentDesktopSignatureEvidence(
                isValid: true, signingIdentifier: identifier, teamIdentifier: "VALIDTEAM1"
            )
        }
        XCTAssertTrue(inventory.installations.isEmpty)
        XCTAssertTrue(inventory.candidates.isEmpty)
        XCTAssertEqual(Set(inventory.relatedSoftware.map(\.softwareID)), Set(expectedRelatedSoftware.keys))
        XCTAssertTrue(inventory.relatedSoftware.allSatisfy { $0.signature.isValid })
    }

    func testRelatedAndAgentBundleIdentifiersCannotOverlap() throws {
        let kimi = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first { $0.id == "kimi" })
        let duplicate = AgentRelatedSoftwareRule(
            id: "not-an-independent-agent", displayName: "Kimi helper",
            bundleIdentifier: "com.moonshot.kimichat", role: .bundledComponent,
            owningProductID: "kimi"
        )
        XCTAssertThrowsError(try AgentRuleCatalog(
            revision: "cross-category-duplicate", issuedAt: Date(),
            providers: AgentRuleCatalog.builtIn.providers,
            desktopProducts: [kimi], relatedSoftware: [duplicate]
        ))
    }

    func testKimiCUIsObservedAsKimiComponentWithOnlyIndexedPaths() throws {
        let rule = try XCTUnwrap(AgentRuleCatalog.builtIn.rule(for: .kimi))
        let paths = Set(rule.roots.map(\.relativePath))
        XCTAssertTrue(rule.bundleIdentifiers.contains("ai.kimi.cu"))
        for path in [".kimi-cu", "KimiCU", "ai.kimi.cu"] {
            XCTAssertTrue(paths.contains(path), path)
        }
        XCTAssertFalse(AgentRuleCatalog.builtIn.desktopProducts.contains { $0.id == "kimi-cu" })
        XCTAssertEqual(
            AgentRuleCatalog.builtIn.relatedSoftware.first { $0.id == "kimi-cu" }?.owningProductID,
            "kimi"
        )
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
        XCTAssertTrue(decoded.relatedSoftware.isEmpty)
        let merged = try decoded.mergingBuiltInBaseline()
        XCTAssertEqual(merged.desktopProducts.map(\.id), AgentRuleCatalog.builtIn.desktopProducts.map(\.id))
        XCTAssertEqual(merged.relatedSoftware.map(\.id), AgentRuleCatalog.builtIn.relatedSoftware.map(\.id))
        XCTAssertEqual(Set(merged.providers.map(\.provider)), Set(AgentWorkspaceProvider.allCases))
    }

    func testExactBundleValidSignatureAndSignerAreRequiredForEveryCopy() {
        let first = application(path: "/Applications/Grok Bot.app")
        let second = application(path: "/tmp/Grok Bot Copy.app")
        let renamedImpostor = InstalledApplication(
            name: "Grok Bot", bundleIdentifier: "local.muse.lookalike", version: "1",
            url: URL(fileURLWithPath: "/Applications/Muse.app"), allocatedBytes: 0, modifiedAt: nil
        )
        let inventory = AgentDesktopProductDetector.inventory(
            catalog: .builtIn,
            applications: [first, second, renamedImpostor]
        ) { url in
            if url == second.url {
                return AgentDesktopSignatureEvidence(isValid: true, signingIdentifier: "com.anysphere.sand", teamIdentifier: "WRONGTEAM1")
            }
            return AgentDesktopSignatureEvidence(isValid: true, signingIdentifier: "com.anysphere.sand", teamIdentifier: "DCNK4UB866")
        }
        XCTAssertEqual(inventory.installations.map(\.application.url), [first.url])
        XCTAssertEqual(inventory.installations.first?.productID, "grok-bot")
        XCTAssertNotEqual(inventory.installations.first?.copyID, inventory.installations.first?.productID)
        XCTAssertEqual(inventory.candidates.map(\.productID), ["grok-bot"])
        XCTAssertEqual(inventory.candidates.first?.issue, .unexpectedSigner)
        XCTAssertEqual(inventory.candidates.first?.displayName, "Grok Bot")
    }

    func testInvalidSignatureCannotBecomeAnInstallation() {
        let inventory = AgentDesktopProductDetector.inventory(
            catalog: .builtIn,
            applications: [application(path: "/Applications/Grok Bot.app")]
        ) { _ in
            AgentDesktopSignatureEvidence(isValid: false, signingIdentifier: "com.anysphere.sand", teamIdentifier: "DCNK4UB866")
        }
        XCTAssertTrue(inventory.installations.isEmpty)
        XCTAssertEqual(inventory.candidates.count, 1)
        XCTAssertEqual(inventory.candidates.first?.issue, .invalidSignature)
    }

    func testValidSignatureCannotPromotePendingProduct() throws {
        let rule = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first { $0.id == "workbuddy" })
        let app = application(
            path: "/Applications/WorkBuddy.app", name: "WorkBuddy",
            bundleIdentifier: "com.workbuddy.workbuddy"
        )
        let inventory = AgentDesktopProductDetector.inventory(catalog: .builtIn, applications: [app]) { _ in
            AgentDesktopSignatureEvidence(
                isValid: true, signingIdentifier: "com.workbuddy.workbuddy", teamIdentifier: "FN2V63AD2J"
            )
        }
        XCTAssertEqual(rule.verification, .pendingOfficialSample)
        XCTAssertTrue(inventory.installations.isEmpty)
        XCTAssertEqual(inventory.candidates.first?.issue, .pendingOfficialSample)
    }

    func testEveryVerifiedProductRetainsSensitiveStandardLocations() throws {
        for product in AgentRuleCatalog.builtIn.desktopProducts where product.verification == .verifiedOfficialSample {
            let identifier = try XCTUnwrap(product.bundleIdentifiers.first)
            let retained = Set(product.privateData.filter { $0.disposition == .retained }.map(\.path))
            XCTAssertTrue(retained.contains(AgentRulePath(base: .applicationSupport, relativePath: identifier)), product.id)
            XCTAssertTrue(retained.contains(AgentRulePath(base: .httpStorages, relativePath: identifier)), product.id)
            XCTAssertTrue(retained.contains(AgentRulePath(base: .preferences, relativePath: identifier + ".plist")), product.id)
            XCTAssertTrue(retained.contains(AgentRulePath(base: .savedApplicationState, relativePath: identifier + ".savedState")), product.id)
            XCTAssertTrue(retained.contains(AgentRulePath(base: .webKit, relativePath: identifier)), product.id)
            for item in product.privateData where item.disposition == .regenerable {
                XCTAssertTrue(item.path.base == .caches || item.path.base == .logs, product.id)
            }
        }
    }

    func testProductGraphAllowsOnlyRegisteredCacheAndLogPathsForEveryProduct() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        for product in AgentRuleCatalog.builtIn.desktopProducts where product.verification == .verifiedOfficialSample {
            let identifier = try XCTUnwrap(product.bundleIdentifiers.first)
            var nodes = try product.privateData.map { item in
                let url = item.path.resolve(homeDirectory: home)
                if item.path.base == .preferences {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try Data("fixture".utf8).write(to: url)
                } else {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }
                return ApplicationDependencyNode(
                    name: url.lastPathComponent, url: url, kind: .relatedFile,
                    ownership: .applicationOwned, action: .removeAfterApplication,
                    allocatedBytes: 0, evidence: ["simulated overly broad removal"],
                    identity: try ApplicationDependencyIdentity.capture(at: url)
                )
            }
            let unregisteredURL = home
                .appendingPathComponent("Library/Application Support/Generic Unregistered", isDirectory: true)
                .appendingPathComponent(product.id, isDirectory: true)
            try FileManager.default.createDirectory(at: unregisteredURL, withIntermediateDirectories: true)
            nodes.append(ApplicationDependencyNode(
                name: unregisteredURL.lastPathComponent, url: unregisteredURL, kind: .relatedFile,
                ownership: .applicationOwned, action: .removeAfterApplication,
                allocatedBytes: 0, evidence: ["simulated generic name-match removal"],
                identity: try ApplicationDependencyIdentity.capture(at: unregisteredURL)
            ))
            let app = application(
                path: home.appendingPathComponent(product.applicationNames[0]).appendingPathExtension("app").path,
                name: product.displayName, bundleIdentifier: identifier
            )
            let graph = ApplicationDependencyGraph(
                applicationID: app.id, capturedAt: Date(),
                codeSignature: ApplicationCodeSignatureEvidence(
                    status: .valid, signingIdentifier: identifier,
                    teamIdentifier: product.allowedTeamIdentifiers[0], applicationGroups: [], diagnostic: "fixture"
                ),
                registration: ApplicationRegistrationEvidence(
                    bundleIdentifier: identifier, registeredURLs: [], scannedPathIsRegistered: false, diagnostic: "fixture"
                ),
                nodes: nodes, diagnostic: "fixture"
            ).includingDesktopProduct(product, homeDirectory: home)
            let expectedRemovable = Set(product.privateData.filter { $0.disposition == .regenerable }.map {
                $0.path.resolve(homeDirectory: home).standardizedFileURL
            })
            let expectedRetained = Set(product.privateData.filter { $0.disposition == .retained }.map {
                $0.path.resolve(homeDirectory: home).standardizedFileURL
            }).union([unregisteredURL.standardizedFileURL])
            XCTAssertEqual(Set(graph.separatelyRemovableNodes.map(\.url)), expectedRemovable, product.id)
            XCTAssertEqual(Set(graph.readOnlyNodes.map(\.url)), expectedRetained, product.id)
            let unregistered = try XCTUnwrap(graph.nodes.first { $0.url == unregisteredURL }, product.id)
            XCTAssertTrue(unregistered.isReadOnly, product.id)
            XCTAssertEqual(unregistered.kind, .unverifiedItem, product.id)
            XCTAssertEqual(unregistered.ownership, .unverified, product.id)
            XCTAssertEqual(graph.productID, product.id)
        }
    }

    func testOfficialDesktopSamplesUseProductionSignatureValidation() throws {
        let environment = ProcessInfo.processInfo.environment
        let grokPath = environment["CLEANNEST_GROK_SAMPLE_APP"]
        let sampleRoot = environment["CLEANNEST_AGENT_SAMPLE_ROOT"]
        guard grokPath?.isEmpty == false || sampleRoot?.isEmpty == false else {
            throw XCTSkip("Set CLEANNEST_AGENT_SAMPLE_ROOT or CLEANNEST_GROK_SAMPLE_APP for official sample checks.")
        }
        if let grokPath, !grokPath.isEmpty {
            let installations = AgentDesktopProductDetector.installations(
                catalog: .builtIn,
                applications: [application(path: grokPath)]
            )
            let installation = try XCTUnwrap(installations.first)
            XCTAssertEqual(installations.count, 1)
            XCTAssertEqual(installation.bundleIdentifier, "com.anysphere.sand")
            XCTAssertEqual(installation.teamIdentifier, "DCNK4UB866")
            XCTAssertEqual(installation.application.version, "1.2.3")
        }
        if let sampleRoot, !sampleRoot.isEmpty {
            let root = URL(fileURLWithPath: sampleRoot, isDirectory: true)
            let products = AgentRuleCatalog.builtIn.desktopProducts
            let related = AgentRuleCatalog.builtIn.relatedSoftware
            let productApplications = try products.map { try sampleApplication(for: $0, root: root) }
            let relatedApplications = try related.map { try sampleApplication(for: $0, root: root) }
            let inventory = AgentDesktopProductDetector.inventory(
                catalog: .builtIn, applications: productApplications + relatedApplications
            )
            XCTAssertEqual(Set(inventory.installations.map(\.productID)), Set(expectedVerifiedIdentities.keys))
            XCTAssertEqual(inventory.installations.count, expectedVerifiedIdentities.count)
            XCTAssertEqual(Set(inventory.candidates.map(\.productID)), expectedPendingProducts)
            XCTAssertEqual(inventory.candidates.count, expectedPendingProducts.count)
            XCTAssertEqual(Set(inventory.relatedSoftware.map(\.softwareID)), Set(expectedRelatedSoftware.keys))
            XCTAssertEqual(inventory.relatedSoftware.count, expectedRelatedSoftware.count)
            XCTAssertEqual(
                Set(productApplications.map(\.bundleIdentifier)).union(relatedApplications.map(\.bundleIdentifier)).count,
                23
            )
            for candidate in inventory.candidates {
                XCTAssertEqual(candidate.issue, .invalidSignature, candidate.productID)
                XCTAssertEqual(candidate.displayName, candidate.application.name)
            }
        }
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
            version: "4.5", buildVersion: "67",
            url: URL(fileURLWithPath: "/tmp/Third Agent Custom Location.app"),
            allocatedBytes: 0, modifiedAt: nil
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

    func testDesktopProductBundleIdentifiersCannotOverlap() throws {
        let grok = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first { $0.id == "grok-bot" })
        let duplicate = AgentDesktopProductRule(
            id: "duplicate-grok", displayName: "Duplicate Grok",
            bundleIdentifiers: grok.bundleIdentifiers,
            allowedTeamIdentifiers: grok.allowedTeamIdentifiers,
            applicationNames: ["Duplicate"], verification: .verifiedOfficialSample
        )
        XCTAssertThrowsError(try AgentRuleCatalog(
            revision: "duplicate-product-fixture", issuedAt: Date(),
            providers: AgentRuleCatalog.builtIn.providers,
            desktopProducts: [grok, duplicate]
        ))
    }

    func testProductRuleCannotIntroduceNewDeletionPath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let grok = try XCTUnwrap(AgentRuleCatalog.builtIn.desktopProducts.first { $0.id == "grok-bot" })
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

    private func sampleApplication(for rule: AgentDesktopProductRule, root: URL) throws -> InstalledApplication {
        let url = root.appendingPathComponent(rule.applicationNames[0]).appendingPathExtension("app")
        return try sampleApplication(named: rule.displayName, at: url, id: rule.id)
    }

    private func sampleApplication(for rule: AgentRelatedSoftwareRule, root: URL) throws -> InstalledApplication {
        let url = root.appendingPathComponent(rule.displayName).appendingPathExtension("app")
        return try sampleApplication(named: rule.displayName, at: url, id: rule.id)
    }

    private func sampleApplication(named displayName: String, at url: URL, id: String) throws -> InstalledApplication {
        let bundle = try XCTUnwrap(Bundle(url: url), id)
        return InstalledApplication(
            name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? displayName,
            bundleIdentifier: bundle.bundleIdentifier,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildVersion: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            url: url, allocatedBytes: 0, modifiedAt: nil
        )
    }

    private func application(
        path: String,
        name: String = "Grok Bot",
        bundleIdentifier: String = "com.anysphere.sand",
        version: String = "1.2.3",
        buildVersion: String = "1.2.3"
    ) -> InstalledApplication {
        InstalledApplication(
            name: name, bundleIdentifier: bundleIdentifier, version: version, buildVersion: buildVersion,
            url: URL(fileURLWithPath: path), allocatedBytes: 0, modifiedAt: nil
        )
    }
}
