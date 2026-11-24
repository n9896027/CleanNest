import Foundation

public enum AgentRuleBaseDirectory: String, Codable, CaseIterable, Sendable {
    case home
    case applicationSupport
    case caches
    case logs
    case httpStorages
    case preferences
    case savedApplicationState
    case webKit
}

public enum AgentAdapterVerification: String, Codable, Sendable {
    case verifiedReadOnly
    case detectionOnly

    public var displayName: String {
        switch self {
        case .verifiedReadOnly: return "已验证只读适配"
        case .detectionOnly: return "仅检测·规则待验证"
        }
    }
}

public struct AgentRulePath: Codable, Equatable, Hashable, Sendable {
    public let base: AgentRuleBaseDirectory
    public let relativePath: String
    public let defaultKind: AgentArtifactKind

    public init(
        base: AgentRuleBaseDirectory,
        relativePath: String,
        defaultKind: AgentArtifactKind = .unknown
    ) {
        self.base = base
        self.relativePath = relativePath
        self.defaultKind = defaultKind
    }

    public func resolve(homeDirectory: URL) -> URL {
        let home = homeDirectory.standardizedFileURL
        let baseURL: URL
        switch base {
        case .home:
            baseURL = home
        case .applicationSupport:
            baseURL = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        case .caches:
            baseURL = home.appendingPathComponent("Library/Caches", isDirectory: true)
        case .logs:
            baseURL = home.appendingPathComponent("Library/Logs", isDirectory: true)
        case .httpStorages:
            baseURL = home.appendingPathComponent("Library/HTTPStorages", isDirectory: true)
        case .preferences:
            baseURL = home.appendingPathComponent("Library/Preferences", isDirectory: true)
        case .savedApplicationState:
            baseURL = home.appendingPathComponent("Library/Saved Application State", isDirectory: true)
        case .webKit:
            baseURL = home.appendingPathComponent("Library/WebKit", isDirectory: true)
        }
        return baseURL.appendingPathComponent(relativePath, isDirectory: true).standardizedFileURL
    }
}

public struct AgentArtifactNameRule: Codable, Equatable, Hashable, Sendable {
    public let kind: AgentArtifactKind
    public let exact: [String]
    public let contains: [String]
    public let prefixes: [String]
    public let suffixes: [String]

    public init(
        kind: AgentArtifactKind,
        exact: [String] = [],
        contains: [String] = [],
        prefixes: [String] = [],
        suffixes: [String] = []
    ) {
        self.kind = kind
        self.exact = exact
        self.contains = contains
        self.prefixes = prefixes
        self.suffixes = suffixes
    }

    fileprivate func matches(_ rawName: String) -> Bool {
        let name = rawName.lowercased()
        return exact.contains(name)
            || contains.contains(where: name.contains)
            || prefixes.contains(where: name.hasPrefix)
            || suffixes.contains(where: name.hasSuffix)
    }
}

public struct AgentProviderRule: Codable, Equatable, Sendable {
    public let provider: AgentWorkspaceProvider
    public let verification: AgentAdapterVerification
    public let roots: [AgentRulePath]
    public let bundleIdentifiers: [String]
    public let applicationNames: [String]
    public let processMarkers: [String]
    public let supervisorMarkers: [String]
    public let artifactRules: [AgentArtifactNameRule]

    public init(
        provider: AgentWorkspaceProvider,
        verification: AgentAdapterVerification,
        roots: [AgentRulePath],
        bundleIdentifiers: [String] = [],
        applicationNames: [String] = [],
        processMarkers: [String] = [],
        supervisorMarkers: [String] = [],
        artifactRules: [AgentArtifactNameRule]
    ) {
        self.provider = provider
        self.verification = verification
        self.roots = roots
        self.bundleIdentifiers = bundleIdentifiers
        self.applicationNames = applicationNames
        self.processMarkers = processMarkers
        self.supervisorMarkers = supervisorMarkers
        self.artifactRules = artifactRules
    }

    public func resolvedRoots(homeDirectory: URL) -> [(url: URL, defaultKind: AgentArtifactKind)] {
        roots.map { ($0.resolve(homeDirectory: homeDirectory), $0.defaultKind) }
    }

    public func classify(name: String, defaultKind: AgentArtifactKind = .unknown) -> AgentArtifactKind {
        artifactRules.first(where: { $0.matches(name) })?.kind ?? defaultKind
    }
}

public enum AgentRuleCatalogError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case emptyRevision
    case duplicateProvider(String)
    case missingProvider(String)
    case invalidPath(String)
    case overlyBroadPath(String)
    case oversizedCatalog
    case emptyDetectionRule(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version): return "规则包 schema \(version) 不受支持。"
        case .emptyRevision: return "规则包没有修订号。"
        case .duplicateProvider(let provider): return "规则包重复定义了 \(provider)。"
        case .missingProvider(let provider): return "规则包缺少 \(provider) 的安全边界。"
        case .invalidPath(let path): return "规则路径无效：\(path)"
        case .overlyBroadPath(let path): return "规则路径范围过宽：\(path)"
        case .oversizedCatalog: return "规则包超出有界大小。"
        case .emptyDetectionRule(let provider): return "\(provider) 没有任何可验证的检测证据。"
        }
    }
}

/// Data-only adapter catalog. It may expand read-only detection, but it never
/// grants mutation authority. The latter remains hard-coded to Codex/Claude.
public struct AgentRuleCatalog: Codable, Equatable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let revision: String
    public let issuedAt: Date
    public let providers: [AgentProviderRule]
    public let desktopProducts: [AgentDesktopProductRule]
    public let relatedSoftware: [AgentRelatedSoftwareRule]

    public init(
        schemaVersion: Int = supportedSchemaVersion,
        revision: String,
        issuedAt: Date,
        providers: [AgentProviderRule],
        desktopProducts: [AgentDesktopProductRule] = [],
        relatedSoftware: [AgentRelatedSoftwareRule] = []
    ) throws {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.issuedAt = issuedAt
        self.providers = providers
        self.desktopProducts = desktopProducts
        self.relatedSoftware = relatedSoftware
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, issuedAt, providers, desktopProducts, relatedSoftware
    }

    /// Schema 1 bundles predate dynamic desktop products and related software.
    /// Their signed legacy workspace rules remain valid, while new built-in
    /// entries are supplied locally. No missing field can grant file authority.
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(String.self, forKey: .revision)
        issuedAt = try values.decode(Date.self, forKey: .issuedAt)
        providers = try values.decode([AgentProviderRule].self, forKey: .providers)
        desktopProducts = try values.decodeIfPresent([AgentDesktopProductRule].self, forKey: .desktopProducts) ?? []
        relatedSoftware = try values.decodeIfPresent([AgentRelatedSoftwareRule].self, forKey: .relatedSoftware) ?? []
        try validate()
    }

    public func rule(for provider: AgentWorkspaceProvider) -> AgentProviderRule? {
        providers.first { $0.provider == provider }
    }

    public func mergingBuiltInBaseline() throws -> AgentRuleCatalog {
        let importedProviders = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider, $0) })
        let importedProductIDs = Set(desktopProducts.map(\.id))
        let importedRelatedIDs = Set(relatedSoftware.map(\.id))
        return try AgentRuleCatalog(
            schemaVersion: schemaVersion,
            revision: revision,
            issuedAt: issuedAt,
            providers: AgentWorkspaceProvider.allCases.map { provider in
                importedProviders[provider] ?? Self.builtIn.providers.first { $0.provider == provider }!
            },
            desktopProducts: desktopProducts + Self.builtIn.desktopProducts.filter { !importedProductIDs.contains($0.id) },
            relatedSoftware: relatedSoftware + Self.builtIn.relatedSoftware.filter { !importedRelatedIDs.contains($0.id) }
        )
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw AgentRuleCatalogError.unsupportedSchema(schemaVersion)
        }
        let normalizedRevision = revision.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRevision.isEmpty, normalizedRevision.count <= 80 else {
            throw AgentRuleCatalogError.emptyRevision
        }
        guard providers.count <= 32,
              providers.reduce(0, { $0 + $1.roots.count }) <= 128,
              providers.reduce(0, { $0 + $1.artifactRules.count }) <= 512 else {
            throw AgentRuleCatalogError.oversizedCatalog
        }
        var seen = Set<AgentWorkspaceProvider>()
        for rule in providers {
            guard seen.insert(rule.provider).inserted else {
                throw AgentRuleCatalogError.duplicateProvider(rule.provider.rawValue)
            }
            let markerCount = rule.bundleIdentifiers.count + rule.applicationNames.count
                + rule.processMarkers.count + rule.supervisorMarkers.count
            guard !rule.roots.isEmpty || markerCount > 0 else {
                throw AgentRuleCatalogError.emptyDetectionRule(rule.provider.displayName)
            }
            for root in rule.roots {
                try Self.validate(relativePath: root.relativePath)
            }
            let strings = rule.bundleIdentifiers + rule.applicationNames
                + rule.processMarkers + rule.supervisorMarkers
                + rule.artifactRules.flatMap { $0.exact + $0.contains + $0.prefixes + $0.suffixes }
            guard strings.count <= 512,
                  strings.allSatisfy({ !$0.isEmpty && $0.count <= 160 && !$0.contains("\0") }) else {
                throw AgentRuleCatalogError.oversizedCatalog
            }
        }
        for provider in AgentWorkspaceProvider.allCases where !seen.contains(provider) {
            throw AgentRuleCatalogError.missingProvider(provider.displayName)
        }
        guard desktopProducts.count <= 32, relatedSoftware.count <= 32 else {
            throw AgentRuleCatalogError.oversizedCatalog
        }
        var productIDs = Set<String>()
        var productBundleIdentifiers = Set<String>()
        for product in desktopProducts {
            guard productIDs.insert(product.id).inserted else {
                throw AgentRuleCatalogError.duplicateProvider(product.id)
            }
            for identifier in product.bundleIdentifiers {
                guard productBundleIdentifiers.insert(identifier).inserted else {
                    throw AgentRuleCatalogError.duplicateProvider(identifier)
                }
            }
            try product.validate()
        }
        var relatedIDs = Set<String>()
        var relatedBundleIdentifiers = Set<String>()
        for software in relatedSoftware {
            guard relatedIDs.insert(software.id).inserted,
                  !productIDs.contains(software.id),
                  relatedBundleIdentifiers.insert(software.bundleIdentifier).inserted,
                  !productBundleIdentifiers.contains(software.bundleIdentifier) else {
                throw AgentRuleCatalogError.duplicateProvider(software.id)
            }
            if let owner = software.owningProductID {
                guard productIDs.contains(owner) else {
                    throw AgentRuleCatalogError.missingProvider(owner)
                }
            }
            try software.validate()
        }
    }

    public static func validate(dataPath: String) throws {
        try validate(relativePath: dataPath)
    }

    private static func validate(relativePath rawPath: String) throws {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty,
              path.count <= 240,
              !(path as NSString).isAbsolutePath,
              !path.lowercased().hasPrefix("file://"),
              !path.contains("\0") else {
            throw AgentRuleCatalogError.invalidPath(rawPath)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AgentRuleCatalogError.invalidPath(rawPath)
        }
        let broad = Set(["library", "application support", "caches", "logs", "documents", "desktop", "downloads"])
        guard !(components.count == 1 && broad.contains(String(components[0]).lowercased())) else {
            throw AgentRuleCatalogError.overlyBroadPath(rawPath)
        }
    }

    public static let builtIn: AgentRuleCatalog = {
        let shared: [AgentArtifactNameRule] = [
            .init(kind: .credentials, exact: ["web data"], contains: ["credential", "token", "cookie", "keychain", "auth"]),
            .init(kind: .logs, exact: ["logs", "log"], suffixes: [".log"]),
            .init(kind: .temporaryFiles, exact: ["tmp", ".tmp", "temp"], contains: ["temporary"]),
            .init(kind: .caches, exact: ["blob_storage", "gpucache", "service worker"], contains: ["cache"]),
            .init(kind: .backups, contains: ["backup"]),
            .init(kind: .archivedSessions, contains: ["archive"]),
            .init(kind: .stateAndIndexes, contains: ["state", "index", "database", "sqlite", "storage", "queue"]),
            .init(kind: .memoryAndPlans, exact: ["memory", "memories", "plans", "todos"]),
            .init(kind: .runtime, contains: ["runtime", "plugin", "extension"])
        ]
        let catalog = try! AgentRuleCatalog(
            revision: "builtin-2026.11.24.3",
            issuedAt: Date(timeIntervalSince1970: 1_795_478_400),
            providers: [
                .init(
                    provider: .codex,
                    verification: .verifiedReadOnly,
                    roots: [.init(base: .home, relativePath: ".codex")],
                    bundleIdentifiers: ["com.openai.codex"],
                    applicationNames: ["Codex"],
                    processMarkers: ["codex"],
                    artifactRules: [
                        .init(kind: .activeSessions, exact: ["sessions"]),
                        .init(kind: .archivedSessions, exact: ["archived_sessions"]),
                        .init(kind: .generatedMedia, exact: ["generated_images", "computer-use"]),
                        .init(kind: .memoryAndPlans, exact: ["memories", "plans"]),
                        .init(kind: .stateAndIndexes, exact: ["thread-writer-locks"])
                    ] + shared
                ),
                .init(
                    provider: .claude,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .home, relativePath: ".claude"),
                        .init(base: .applicationSupport, relativePath: "Claude")
                    ],
                    bundleIdentifiers: ["com.anthropic.claudefordesktop"],
                    applicationNames: ["Claude"],
                    processMarkers: ["claude"],
                    artifactRules: [
                        .init(kind: .activeSessions, exact: ["projects", "local-agent-mode-sessions", "session-env", "shell-snapshots", "todos", "history.jsonl"], suffixes: [".jsonl"]),
                        .init(kind: .memoryAndPlans, exact: ["file-history", "plans", "memory"]),
                        .init(kind: .virtualMachines, exact: ["vm_bundles", "claude-code-vm"]),
                        .init(kind: .runtime, exact: ["claude-code"])
                    ] + shared
                ),
                .init(
                    provider: .piAgent,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .home, relativePath: ".pi/agent"),
                        .init(base: .applicationSupport, relativePath: "com.abcwyc.pi-agent"),
                        .init(base: .caches, relativePath: "com.abcwyc.pi-agent", defaultKind: .caches),
                        .init(base: .logs, relativePath: "com.abcwyc.pi-agent", defaultKind: .logs)
                    ],
                    bundleIdentifiers: ["com.abcwyc.pi-agent"],
                    applicationNames: ["Pi Agent"],
                    processMarkers: ["pi-agent-desktop"],
                    artifactRules: [
                        .init(kind: .activeSessions, exact: ["sessions"]),
                        .init(kind: .credentials, exact: ["auth.json"]),
                        .init(kind: .runtime, exact: ["bin", "extensions", "skills"]),
                        .init(kind: .memoryAndPlans, exact: ["agents.md"]),
                        .init(kind: .stateAndIndexes, exact: ["models.json", "models-store.json", "settings.json", "pi-web-update-check.json", "ui-prefs.json"])
                    ] + shared
                ),
                .init(
                    provider: .kimi,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .home, relativePath: ".kimi"),
                        .init(base: .home, relativePath: ".kimi-cu"),
                        .init(base: .applicationSupport, relativePath: "kimi-desktop"),
                        .init(base: .applicationSupport, relativePath: "KimiCU"),
                        .init(base: .caches, relativePath: "kimi-code", defaultKind: .caches),
                        .init(base: .caches, relativePath: "kimi-desktop-updater", defaultKind: .caches),
                        .init(base: .caches, relativePath: "ai.kimi.cu", defaultKind: .caches),
                        .init(base: .logs, relativePath: "kimi-desktop", defaultKind: .logs),
                        .init(base: .httpStorages, relativePath: "ai.kimi.cu", defaultKind: .stateAndIndexes)
                    ],
                    bundleIdentifiers: ["com.moonshot.kimichat", "ai.kimi.cu"],
                    applicationNames: ["Kimi", "KimiCU"],
                    processMarkers: ["kimi", "kimi-cli", "kimi-cu"],
                    artifactRules: [.init(kind: .activeSessions, contains: ["session", "conversation", "chat"])] + shared
                ),
                .init(
                    provider: .workBuddy,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .home, relativePath: ".workbuddy"),
                        .init(base: .applicationSupport, relativePath: "WorkBuddy"),
                        .init(base: .applicationSupport, relativePath: "@genie/workbuddy-desktop"),
                        .init(base: .applicationSupport, relativePath: "com.workbuddy.workbuddy"),
                        .init(base: .logs, relativePath: "WorkBuddy", defaultKind: .logs)
                    ],
                    bundleIdentifiers: ["com.workbuddy.workbuddy"],
                    applicationNames: ["WorkBuddy"],
                    processMarkers: ["workbuddy"],
                    supervisorMarkers: ["workbuddy"],
                    artifactRules: [.init(kind: .activeSessions, contains: ["session", "conversation", "chat"])] + shared
                ),
                .init(
                    provider: .hermes,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .home, relativePath: ".hermes"),
                        .init(base: .applicationSupport, relativePath: "hermes-studio")
                    ],
                    bundleIdentifiers: ["com.hermeswebui.studio"],
                    applicationNames: ["Hermes Studio", "Hermes"],
                    processMarkers: ["hermes", "hermes-shell"],
                    artifactRules: [.init(kind: .activeSessions, contains: ["session", "conversation", "chat"])] + shared
                ),
                .init(
                    provider: .openClaw,
                    verification: .verifiedReadOnly,
                    roots: [.init(base: .home, relativePath: ".openclaw")],
                    applicationNames: ["OpenClaw"],
                    processMarkers: ["openclaw"],
                    supervisorMarkers: ["openclaw"],
                    artifactRules: [
                        .init(kind: .activeSessions, exact: ["sessions", "tasks", "agents"]),
                        .init(kind: .generatedMedia, exact: ["media"]),
                        .init(kind: .memoryAndPlans, exact: ["memory"])
                    ] + shared
                ),
                .init(
                    provider: .trae,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .applicationSupport, relativePath: "Trae CN"),
                        .init(base: .applicationSupport, relativePath: "TRAE SOLO CN")
                    ],
                    bundleIdentifiers: ["cn.trae.app"],
                    applicationNames: ["Trae CN", "TRAE SOLO CN"],
                    processMarkers: ["trae"],
                    artifactRules: [
                        .init(kind: .activeSessions, exact: ["backups"], contains: ["workspace", "session"]),
                        .init(kind: .runtime, exact: ["user"])
                    ] + shared
                ),
                .init(
                    provider: .miniMaxHub,
                    verification: .verifiedReadOnly,
                    roots: [
                        .init(base: .logs, relativePath: "MiniMax Hub", defaultKind: .logs),
                        .init(base: .logs, relativePath: "MiniMax Hub Twin", defaultKind: .logs),
                        .init(base: .logs, relativePath: "MiniMax Design", defaultKind: .logs)
                    ],
                    bundleIdentifiers: ["local.zone.minimax-hub2", "com.minimax.hub", "com.minimax.hub.global"],
                    applicationNames: ["MiniMax Hub 2", "MiniMax Design"],
                    processMarkers: ["minimax hub", "minimax design"],
                    artifactRules: shared
                ),
                .init(
                    provider: .xiaoyunque,
                    verification: .detectionOnly,
                    roots: [],
                    bundleIdentifiers: ["com.bytedance.pippit.xiaoyunque"],
                    applicationNames: ["小云雀"],
                    processMarkers: ["xiaoyunque", "小云雀"],
                    artifactRules: shared
                )
            ],
            desktopProducts: [
                AgentDesktopProductRule(
                    id: "chatgpt", displayName: "ChatGPT",
                    bundleIdentifiers: ["com.openai.codex"],
                    allowedTeamIdentifiers: ["2DC432GLL2"],
                    applicationNames: ["ChatGPT"], verification: .verifiedOfficialSample,
                    legacyProvider: .codex,
                    privateData: agentDesktopData(
                        "com.openai.codex", applicationSupport: ["Codex", "OpenAI"], home: [".codex"],
                        logs: ["com.openai.codex"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "claude", displayName: "Claude",
                    bundleIdentifiers: ["com.anthropic.claudefordesktop"],
                    allowedTeamIdentifiers: ["Q6L2SF6YDW"],
                    applicationNames: ["Claude"], verification: .verifiedOfficialSample,
                    legacyProvider: .claude,
                    privateData: agentDesktopData(
                        "com.anthropic.claudefordesktop", applicationSupport: ["Claude"], home: [".claude"],
                        logs: ["Claude"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "doubao", displayName: "Doubao",
                    bundleIdentifiers: ["com.bot.neotix.doubao"],
                    allowedTeamIdentifiers: ["96L78H6LMH"],
                    applicationNames: ["Doubao"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData("com.bot.neotix.doubao", applicationSupport: ["Doubao"])
                ),
                AgentDesktopProductRule(
                    id: "gemini", displayName: "Gemini",
                    bundleIdentifiers: ["com.google.GeminiMacOS"],
                    allowedTeamIdentifiers: ["EQHXZ8M8AV"],
                    applicationNames: ["Gemini"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData("com.google.GeminiMacOS", home: [".gemini"])
                ),
                AgentDesktopProductRule(
                    id: "grok-bot", displayName: "Grok Bot",
                    bundleIdentifiers: ["com.anysphere.sand"],
                    allowedTeamIdentifiers: ["DCNK4UB866"],
                    applicationNames: ["Grok Bot"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData(
                        "com.anysphere.sand", applicationSupport: ["Grok Bot"], home: [".grok", ".grokbot"],
                        logs: ["com.anysphere.sand"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "hermes-studio", displayName: "Hermes Studio",
                    bundleIdentifiers: ["com.hermeswebui.studio"],
                    allowedTeamIdentifiers: ["74J93F4W83"],
                    applicationNames: ["Hermes Studio"], verification: .pendingOfficialSample,
                    legacyProvider: .hermes
                ),
                AgentDesktopProductRule(
                    id: "kimi", displayName: "Kimi",
                    bundleIdentifiers: ["com.moonshot.kimichat"],
                    allowedTeamIdentifiers: ["2J9472RW75"],
                    applicationNames: ["Kimi"], verification: .verifiedOfficialSample,
                    legacyProvider: .kimi,
                    privateData: agentDesktopData(
                        "com.moonshot.kimichat", applicationSupport: ["Kimi", "kimi-desktop"], home: [".kimi"],
                        logs: ["kimi-desktop"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "minimax-design", displayName: "MiniMax Design",
                    bundleIdentifiers: ["com.minimax.hub.global"],
                    allowedTeamIdentifiers: ["5Y7L83QLXD"],
                    applicationNames: ["MiniMax Design"], verification: .verifiedOfficialSample,
                    legacyProvider: .miniMaxHub,
                    privateData: agentDesktopData(
                        "com.minimax.hub.global", applicationSupport: ["MiniMax Design"], logs: ["MiniMax Design"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "muse", displayName: "Muse",
                    bundleIdentifiers: ["com.meta.endo"],
                    allowedTeamIdentifiers: ["V9WTTPBFK9"],
                    applicationNames: ["Muse"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData("com.meta.endo")
                ),
                AgentDesktopProductRule(
                    id: "newmax", displayName: "NewMax",
                    bundleIdentifiers: ["cc.newmax.desktop"],
                    allowedTeamIdentifiers: ["22HUP6KLKD"],
                    applicationNames: ["NewMax"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData(
                        "cc.newmax.desktop", applicationSupport: ["NewmaxAI"], home: [".newmax"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "pi-agent", displayName: "Pi Agent",
                    bundleIdentifiers: ["com.abcwyc.pi-agent"],
                    allowedTeamIdentifiers: [],
                    applicationNames: ["Pi Agent"], verification: .pendingOfficialSample,
                    legacyProvider: .piAgent
                ),
                AgentDesktopProductRule(
                    id: "tabbit", displayName: "Tabbit",
                    bundleIdentifiers: ["com.tabbit-ai.Tabbit"],
                    allowedTeamIdentifiers: ["2DE8QTFYGR"],
                    applicationNames: ["Tabbit"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData(
                        "com.tabbit-ai.Tabbit", applicationSupport: ["Tabbit"], caches: ["Tabbit"]
                    )
                ),
                AgentDesktopProductRule(
                    id: "workbuddy", displayName: "WorkBuddy",
                    bundleIdentifiers: ["com.workbuddy.workbuddy"],
                    allowedTeamIdentifiers: ["FN2V63AD2J"],
                    applicationNames: ["WorkBuddy"], verification: .pendingOfficialSample,
                    legacyProvider: .workBuddy
                ),
                AgentDesktopProductRule(
                    id: "zcode", displayName: "ZCode",
                    bundleIdentifiers: ["dev.zcode.app"],
                    allowedTeamIdentifiers: ["8A5X4JJ39T"],
                    applicationNames: ["ZCode"], verification: .verifiedOfficialSample,
                    privateData: agentDesktopData("dev.zcode.app", applicationSupport: ["ZCode"], home: [".zcode"])
                ),
                AgentDesktopProductRule(
                    id: "xiaoyunque", displayName: "小云雀",
                    bundleIdentifiers: ["com.bytedance.pippit.xiaoyunque"],
                    allowedTeamIdentifiers: ["JH23ZR9LF5"],
                    applicationNames: ["小云雀"], verification: .verifiedOfficialSample,
                    legacyProvider: .xiaoyunque,
                    privateData: agentDesktopData("com.bytedance.pippit.xiaoyunque", applicationSupport: ["小云雀"])
                )
            ],
            relatedSoftware: [
                AgentRelatedSoftwareRule(
                    id: "cc-switch", displayName: "CC Switch",
                    bundleIdentifier: "com.ccswitch.desktop", role: .configurationTool
                ),
                AgentRelatedSoftwareRule(
                    id: "claude-code-url-handler", displayName: "Claude Code URL Handler",
                    bundleIdentifier: "com.anthropic.claude-code-url-handler", role: .urlHandler,
                    owningProductID: "claude"
                ),
                AgentRelatedSoftwareRule(
                    id: "hermes-helper-shell", displayName: "Hermes",
                    bundleIdentifier: "com.tianshu.hermes.shell", role: .helperShell,
                    owningProductID: "hermes-studio"
                ),
                AgentRelatedSoftwareRule(
                    id: "kimi-cu", displayName: "KimiCU",
                    bundleIdentifier: "ai.kimi.cu", role: .bundledComponent,
                    owningProductID: "kimi"
                ),
                AgentRelatedSoftwareRule(
                    id: "minimax-hub-2-launcher", displayName: "MiniMax Hub 2",
                    bundleIdentifier: "local.zone.minimax-hub2", role: .localLauncher
                ),
                AgentRelatedSoftwareRule(
                    id: "ollama", displayName: "Ollama",
                    bundleIdentifier: "com.electron.ollama", role: .localModelRunner
                ),
                AgentRelatedSoftwareRule(
                    id: "workdaddy", displayName: "WorkDaddy",
                    bundleIdentifier: "com.workdaddy.launcher", role: .automationLauncher,
                    owningProductID: "workbuddy"
                ),
                AgentRelatedSoftwareRule(
                    id: "yuanhub", displayName: "YuanHub",
                    bundleIdentifier: "io.github.creatorhub.desktop", role: .automationWorkbench
                )
            ]
        )
        return catalog
    }()
}

/// Every desktop product retains the standard locations that can contain login
/// state, cookies, preferences or browsing data. Only exact cache/log roots are
/// regenerable; all other evidence remains read-only during product uninstall.
private func agentDesktopData(
    _ bundleIdentifier: String,
    applicationSupport: [String] = [],
    home: [String] = [],
    caches: [String]? = nil,
    logs: [String] = []
) -> [AgentDesktopDataRule] {
    var rules = ([bundleIdentifier] + applicationSupport).map {
        AgentDesktopDataRule(path: AgentRulePath(base: .applicationSupport, relativePath: $0), disposition: .retained)
    }
    rules += home.map {
        AgentDesktopDataRule(path: AgentRulePath(base: .home, relativePath: $0), disposition: .retained)
    }
    rules += [
        AgentDesktopDataRule(
            path: AgentRulePath(base: .httpStorages, relativePath: bundleIdentifier), disposition: .retained
        ),
        AgentDesktopDataRule(
            path: AgentRulePath(base: .preferences, relativePath: bundleIdentifier + ".plist"), disposition: .retained
        ),
        AgentDesktopDataRule(
            path: AgentRulePath(base: .savedApplicationState, relativePath: bundleIdentifier + ".savedState"),
            disposition: .retained
        ),
        AgentDesktopDataRule(
            path: AgentRulePath(base: .webKit, relativePath: bundleIdentifier), disposition: .retained
        )
    ]
    rules += (caches ?? [bundleIdentifier]).map {
        AgentDesktopDataRule(
            path: AgentRulePath(base: .caches, relativePath: $0, defaultKind: .caches), disposition: .regenerable
        )
    }
    rules += logs.map {
        AgentDesktopDataRule(
            path: AgentRulePath(base: .logs, relativePath: $0, defaultKind: .logs), disposition: .regenerable
        )
    }
    return rules
}
