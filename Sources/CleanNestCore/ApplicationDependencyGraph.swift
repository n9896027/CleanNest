import CoreServices
import Foundation
import Security

public enum ApplicationDependencyKind: String, CaseIterable, Codable, Sendable {
    case applicationBundle
    case relatedFile
    case loginItem
    case userLaunchAgent
    case userDaemon
    case systemLaunchAgent
    case systemLaunchDaemon
    case appExtension
    case systemExtension
    case sharedContainer
    case managedContainer
    case unverifiedItem

    public var displayName: String {
        switch self {
        case .applicationBundle: return "App 本体"
        case .relatedFile: return "精确相关文件"
        case .loginItem: return "登录项"
        case .userLaunchAgent: return "用户启动项"
        case .userDaemon: return "用户守护"
        case .systemLaunchAgent: return "系统启动项"
        case .systemLaunchDaemon: return "系统守护"
        case .appExtension: return "App 扩展"
        case .systemExtension: return "系统扩展"
        case .sharedContainer: return "共享容器"
        case .managedContainer: return "macOS 管理容器"
        case .unverifiedItem: return "无法证明归属"
        }
    }
}

public enum ApplicationDependencyOwnership: String, CaseIterable, Codable, Sendable {
    case applicationOwned
    case sharedGroup
    case systemManaged
    case unverified

    public var displayName: String {
        switch self {
        case .applicationOwned: return "App 私有"
        case .sharedGroup: return "共享组"
        case .systemManaged: return "系统管理"
        case .unverified: return "无法证明"
        }
    }
}

public enum ApplicationDependencyAction: String, Codable, Sendable {
    case applicationBundle
    case removeAfterApplication
    case includedInApplication
    case readOnly

    public var isSeparateRemoval: Bool { self == .removeAfterApplication }
}

public enum ApplicationDependencyItemType: String, Codable, Sendable {
    case regularFile
    case directory
}

/// Stable filesystem identity captured during dependency discovery. It lets the
/// uninstall path reject a related item that was replaced after the preview.
public struct ApplicationDependencyIdentity: Hashable, Codable, Sendable {
    public let deviceID: UInt64
    public let fileID: UInt64
    public let ownerUserID: UInt32
    public let itemType: ApplicationDependencyItemType
    public let modifiedAt: Date?

    public init(
        deviceID: UInt64,
        fileID: UInt64,
        ownerUserID: UInt32,
        itemType: ApplicationDependencyItemType,
        modifiedAt: Date?
    ) {
        self.deviceID = deviceID
        self.fileID = fileID
        self.ownerUserID = ownerUserID
        self.itemType = itemType
        self.modifiedAt = modifiedAt
    }

    public static func capture(
        at target: URL,
        fileManager: FileManager = .default
    ) throws -> ApplicationDependencyIdentity {
        let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { throw SafePathError.symbolicLink }
        let attributes = try fileManager.attributesOfItem(atPath: target.path)
        let itemType: ApplicationDependencyItemType
        switch attributes[.type] as? FileAttributeType {
        case .typeDirectory: itemType = .directory
        case .typeRegular: itemType = .regularFile
        default: throw SafePathError.protectedPath
        }
        guard let deviceID = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let fileID = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let ownerUserID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value else {
            throw SafePathError.protectedPath
        }
        return ApplicationDependencyIdentity(
            deviceID: deviceID,
            fileID: fileID,
            ownerUserID: ownerUserID,
            itemType: itemType,
            modifiedAt: attributes[.modificationDate] as? Date
        )
    }
}

public struct ApplicationCodeSignatureEvidence: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case valid
        case invalid
        case unsigned
        case unavailable

        public var displayName: String {
            switch self {
            case .valid: return "签名有效"
            case .invalid: return "签名校验失败"
            case .unsigned: return "未签名"
            case .unavailable: return "签名信息不可用"
            }
        }
    }

    public let status: Status
    public let signingIdentifier: String?
    public let teamIdentifier: String?
    public let applicationGroups: [String]
    public let diagnostic: String

    public init(
        status: Status,
        signingIdentifier: String?,
        teamIdentifier: String?,
        applicationGroups: [String],
        diagnostic: String
    ) {
        self.status = status
        self.signingIdentifier = signingIdentifier
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
        self.diagnostic = diagnostic
    }
}

public struct ApplicationRegistrationEvidence: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let registeredURLs: [URL]
    public let scannedPathIsRegistered: Bool
    public let diagnostic: String

    public init(
        bundleIdentifier: String?,
        registeredURLs: [URL],
        scannedPathIsRegistered: Bool,
        diagnostic: String
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.registeredURLs = registeredURLs
        self.scannedPathIsRegistered = scannedPathIsRegistered
        self.diagnostic = diagnostic
    }
}

public struct ApplicationDependencyNode: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    public let kind: ApplicationDependencyKind
    public let ownership: ApplicationDependencyOwnership
    public let action: ApplicationDependencyAction
    public let allocatedBytes: Int64
    public let evidence: [String]
    public let identity: ApplicationDependencyIdentity?

    public init(
        id: String? = nil,
        name: String,
        url: URL,
        kind: ApplicationDependencyKind,
        ownership: ApplicationDependencyOwnership,
        action: ApplicationDependencyAction,
        allocatedBytes: Int64,
        evidence: [String],
        identity: ApplicationDependencyIdentity?
    ) {
        self.id = id ?? "\(kind.rawValue):\(url.standardizedFileURL.path)"
        self.name = name
        self.url = url.standardizedFileURL
        self.kind = kind
        self.ownership = ownership
        self.action = action
        self.allocatedBytes = max(0, allocatedBytes)
        self.evidence = evidence
        self.identity = identity
    }

    public var isReadOnly: Bool { action == .readOnly }
}

public struct ApplicationDependencyGraph: Sendable {
    public let applicationID: String
    public let capturedAt: Date
    public let codeSignature: ApplicationCodeSignatureEvidence
    public let registration: ApplicationRegistrationEvidence
    public let nodes: [ApplicationDependencyNode]
    public let diagnostic: String

    public init(
        applicationID: String,
        capturedAt: Date,
        codeSignature: ApplicationCodeSignatureEvidence,
        registration: ApplicationRegistrationEvidence,
        nodes: [ApplicationDependencyNode],
        diagnostic: String
    ) {
        self.applicationID = applicationID
        self.capturedAt = capturedAt
        self.codeSignature = codeSignature
        self.registration = registration
        self.nodes = nodes
        self.diagnostic = diagnostic
    }

    public var separatelyRemovableNodes: [ApplicationDependencyNode] {
        nodes.filter {
            $0.ownership == .applicationOwned
                && $0.action == .removeAfterApplication
                && $0.identity != nil
        }
    }

    public var readOnlyNodes: [ApplicationDependencyNode] {
        nodes.filter(\.isReadOnly)
    }

    public var includedNodes: [ApplicationDependencyNode] {
        nodes.filter { $0.action == .includedInApplication }
    }
}

public enum ApplicationUninstallStage: String, CaseIterable, Sendable {
    case quitApplication
    case revalidateIdentity
    case authenticate
    case confirmApplicationTrash
    case removeRelatedFiles
    case finalReview

    public var displayName: String {
        switch self {
        case .quitApplication: return "请求 App 退出"
        case .revalidateIdentity: return "重验 App 身份"
        case .authenticate: return "系统认证"
        case .confirmApplicationTrash: return "确认 App 进入废纸篓"
        case .removeRelatedFiles: return "处理精确相关文件"
        case .finalReview: return "最终复核"
        }
    }
}

public enum ApplicationUninstallStageState: Equatable, Sendable {
    case pending
    case running
    case succeeded(String)
    case skipped(String)
    case failed(String)
}

public struct ApplicationUninstallStep: Identifiable, Equatable, Sendable {
    public var id: ApplicationUninstallStage { stage }
    public let stage: ApplicationUninstallStage
    public var state: ApplicationUninstallStageState

    public init(stage: ApplicationUninstallStage, state: ApplicationUninstallStageState = .pending) {
        self.stage = stage
        self.state = state
    }
}

public struct ApplicationUninstallSession: Equatable, Sendable {
    public let applicationID: String
    public let applicationName: String
    public let startedAt: Date
    public var completedAt: Date?
    public var steps: [ApplicationUninstallStep]
    public var applicationTrashURL: URL?
    public var relatedTrashURLs: [URL]
    public var failedRelatedPaths: [String]

    public init(applicationID: String, applicationName: String, startedAt: Date = Date()) {
        self.applicationID = applicationID
        self.applicationName = applicationName
        self.startedAt = startedAt
        self.completedAt = nil
        self.steps = ApplicationUninstallStage.allCases.map { ApplicationUninstallStep(stage: $0) }
        self.applicationTrashURL = nil
        self.relatedTrashURLs = []
        self.failedRelatedPaths = []
    }

    public mutating func set(_ stage: ApplicationUninstallStage, _ state: ApplicationUninstallStageState) {
        guard let index = steps.firstIndex(where: { $0.stage == stage }) else { return }
        steps[index].state = state
    }

    public mutating func finish() {
        completedAt = Date()
    }
}

public enum ApplicationUninstallSafetyPolicy {
    /// Related items are eligible only after the exact scanned App has been
    /// confirmed at a destination inside the current user's Trash.
    public static func approvedDependencies(
        from nodes: [ApplicationDependencyNode],
        after applicationOutcome: TrashOutcome
    ) -> [ApplicationDependencyNode] {
        guard applicationOutcome.succeeded, applicationOutcome.trashedURL != nil else { return [] }
        return nodes.filter {
            $0.ownership == .applicationOwned
                && $0.action == .removeAfterApplication
                && $0.identity != nil
        }
    }
}

public struct ApplicationDependencyGraphBuilder: Sendable {
    public let homeDirectory: URL
    public let systemLibraryDirectory: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemLibraryDirectory: URL = URL(fileURLWithPath: "/Library", isDirectory: true)
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.systemLibraryDirectory = systemLibraryDirectory.standardizedFileURL
    }

    public func build(
        for application: InstalledApplication,
        includeProtectedAppData: Bool,
        applicationIsRunning: Bool? = nil
    ) async -> ApplicationDependencyGraph {
        await Task.detached(priority: .userInitiated) {
            buildSynchronously(
                for: application,
                includeProtectedAppData: includeProtectedAppData,
                applicationIsRunning: applicationIsRunning
            )
        }.value
    }

    private func buildSynchronously(
        for application: InstalledApplication,
        includeProtectedAppData: Bool,
        applicationIsRunning: Bool?
    ) -> ApplicationDependencyGraph {
        let signature = inspectSignature(at: application.url)
        let registration = inspectRegistration(for: application)
        var nodes = [applicationNode(application)]
        guard let identifier = application.bundleIdentifier, !identifier.isEmpty else {
            return ApplicationDependencyGraph(
                applicationID: application.id,
                capturedAt: Date(),
                codeSignature: signature,
                registration: registration,
                nodes: nodes,
                diagnostic: "App 未提供 Bundle ID；只显示本体，未猜测任何相关文件。"
            )
        }

        nodes += exactRelatedNodes(
            identifier: identifier,
            includeProtectedAppData: includeProtectedAppData
        )
        nodes += sharedContainerNodes(groups: signature.applicationGroups)
        nodes += launchdNodes(identifier: identifier, applicationURL: application.url)
        nodes += embeddedNodes(applicationURL: application.url)
        nodes += unverifiedNameMatches(application: application, excluding: Set(nodes.map { $0.url.path }))

        let containerRoots = Set([
            homeDirectory.appendingPathComponent("Library/Containers", isDirectory: true).standardizedFileURL,
            homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true).standardizedFileURL
        ])
        let containerInspector = ApplicationContainerReadOnlyInspector(homeDirectory: homeDirectory)
        let signatureMatchesApplication = signature.status == .valid && signature.signingIdentifier == identifier
        let containerReports = nodes.compactMap { node -> ApplicationContainerReadOnlyReport? in
            guard node.kind == .managedContainer || node.kind == .sharedContainer,
                  containerRoots.contains(node.url.deletingLastPathComponent().standardizedFileURL) else { return nil }
            return containerInspector.inspect(
                container: node.url,
                expectedBundleIdentifier: identifier,
                declaredApplicationGroups: signature.applicationGroups,
                signatureMatchesApplication: signatureMatchesApplication,
                applicationIsRunning: applicationIsRunning
            )
        }
        if !containerReports.isEmpty {
            let reportsByPath = Dictionary(uniqueKeysWithValues: containerReports.map { ($0.containerURL.path, $0) })
            nodes = nodes.map { node in
                guard let report = reportsByPath[node.url.path] else { return node }
                return ApplicationDependencyNode(
                    id: node.id,
                    name: node.name,
                    url: node.url,
                    kind: node.kind,
                    ownership: report.ownership,
                    action: .readOnly,
                    allocatedBytes: node.allocatedBytes,
                    evidence: node.evidence + report.evidence,
                    identity: node.identity
                )
            }
        }

        let unique = Dictionary(grouping: nodes, by: \.id).compactMap { $0.value.first }
        let sorted = unique.sorted {
            if $0.action == $1.action {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.name < $1.name }
                return $0.allocatedBytes > $1.allocatedBytes
            }
            return actionRank($0.action) < actionRank($1.action)
        }
        let mutableCount = sorted.filter { $0.action == .removeAfterApplication }.count
        let readOnlyCount = sorted.filter(\.isReadOnly).count
        return ApplicationDependencyGraph(
            applicationID: application.id,
            capturedAt: Date(),
            codeSignature: signature,
            registration: registration,
            nodes: sorted,
            diagnostic: "确认 \(mutableCount) 个可在 App 本体进入废纸篓后单独处理的项目；另有 \(readOnlyCount) 个只读证据。"
        )
    }

    private func applicationNode(_ application: InstalledApplication) -> ApplicationDependencyNode {
        ApplicationDependencyNode(
            name: application.name,
            url: application.url,
            kind: .applicationBundle,
            ownership: .applicationOwned,
            action: .applicationBundle,
            allocatedBytes: application.allocatedBytes,
            evidence: [
                application.bundleIdentifier.map { "Bundle ID：\($0)" } ?? "Bundle ID 不可用",
                application.fileIdentity.map { "稳定身份：设备 \($0.deviceID) · 文件 \($0.fileID)" }
                    ?? "稳定身份不可用"
            ],
            identity: try? ApplicationDependencyIdentity.capture(at: application.url)
        )
    }

    private func exactRelatedNodes(
        identifier: String,
        includeProtectedAppData: Bool
    ) -> [ApplicationDependencyNode] {
        struct RootSpec {
            let relativePath: String
            let ownership: ApplicationDependencyOwnership
            let kind: ApplicationDependencyKind
            let action: ApplicationDependencyAction
            let requiresProtectedAccess: Bool
        }
        let roots = [
            RootSpec(relativePath: "Library/Application Support", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: true),
            RootSpec(relativePath: "Library/Caches", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: false),
            RootSpec(relativePath: "Library/HTTPStorages", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: false),
            RootSpec(relativePath: "Library/Logs", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: false),
            RootSpec(relativePath: "Library/Preferences", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: false),
            RootSpec(relativePath: "Library/Saved Application State", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: false),
            RootSpec(relativePath: "Library/WebKit", ownership: .applicationOwned, kind: .relatedFile, action: .removeAfterApplication, requiresProtectedAccess: false),
            RootSpec(relativePath: "Library/Containers", ownership: .systemManaged, kind: .managedContainer, action: .readOnly, requiresProtectedAccess: true),
            RootSpec(relativePath: "Library/Application Scripts", ownership: .systemManaged, kind: .managedContainer, action: .readOnly, requiresProtectedAccess: true),
            RootSpec(relativePath: "Library/Daemon Containers", ownership: .systemManaged, kind: .managedContainer, action: .readOnly, requiresProtectedAccess: true)
        ]
        var result: [ApplicationDependencyNode] = []
        for root in roots where includeProtectedAppData || !root.requiresProtectedAccess {
            let directory = homeDirectory.appendingPathComponent(root.relativePath, isDirectory: true)
            for child in FileTree.directChildren(of: directory) {
                let name = child.lastPathComponent
                let isExact = exactMatch(name, identifier: identifier)
                let isNamespaceMatch = !isExact && name.hasPrefix(identifier + ".")
                guard isExact || isNamespaceMatch else { continue }
                let ownership: ApplicationDependencyOwnership = isNamespaceMatch && root.ownership == .applicationOwned
                    ? .unverified
                    : root.ownership
                let action: ApplicationDependencyAction = isNamespaceMatch ? .readOnly : root.action
                let kind: ApplicationDependencyKind = isNamespaceMatch && root.kind == .relatedFile
                    ? .unverifiedItem
                    : root.kind
                guard let node = makeNode(
                    at: child,
                    kind: kind,
                    ownership: ownership,
                    action: action,
                    evidence: isExact
                        ? ["Bundle ID 精确匹配：\(identifier)", "位置：~/\(root.relativePath)"]
                        : ["只匹配 Bundle ID 命名空间：\(identifier).*", "可能属于辅助 App，无法证明时保持只读"]
                ) else { continue }
                result.append(node)
            }
        }
        return result
    }

    private func sharedContainerNodes(groups: [String]) -> [ApplicationDependencyNode] {
        guard !groups.isEmpty else { return [] }
        let root = homeDirectory.appendingPathComponent("Library/Group Containers", isDirectory: true)
        let groupSet = Set(groups)
        return FileTree.directChildren(of: root).compactMap { child in
            guard groupSet.contains(child.lastPathComponent) else { return nil }
            return makeNode(
                at: child,
                kind: .sharedContainer,
                ownership: .sharedGroup,
                action: .readOnly,
                evidence: ["代码签名声明共享组：\(child.lastPathComponent)", "可能同时被同一开发者的其他 App 使用"]
            )
        }
    }

    private func launchdNodes(identifier: String, applicationURL: URL) -> [ApplicationDependencyNode] {
        let roots: [(URL, ApplicationDependencyKind, ApplicationDependencyOwnership)] = [
            (homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true), .userLaunchAgent, .applicationOwned),
            (systemLibraryDirectory.appendingPathComponent("LaunchAgents", isDirectory: true), .systemLaunchAgent, .systemManaged),
            (systemLibraryDirectory.appendingPathComponent("LaunchDaemons", isDirectory: true), .systemLaunchDaemon, .systemManaged)
        ]
        var result: [ApplicationDependencyNode] = []
        for (root, defaultKind, ownership) in roots {
            for child in FileTree.directChildren(of: root).prefix(2_048) where child.pathExtension.lowercased() == "plist" {
                guard let data = try? Data(contentsOf: child, options: [.mappedIfSafe]),
                      data.count <= 1_048_576,
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                    continue
                }
                let label = plist["Label"] as? String ?? child.deletingPathExtension().lastPathComponent
                let program = plist["Program"] as? String
                let arguments = plist["ProgramArguments"] as? [String] ?? []
                let pathEvidence = ([program].compactMap { $0 } + arguments).contains {
                    $0 == applicationURL.path || $0.hasPrefix(applicationURL.path + "/")
                }
                let labelEvidence = label == identifier || label.hasPrefix(identifier + ".")
                guard pathEvidence || labelEvidence else { continue }
                let keepAlive = (plist["KeepAlive"] as? Bool) == true || plist["KeepAlive"] is [String: Any]
                let kind = defaultKind == .userLaunchAgent && keepAlive ? .userDaemon : defaultKind
                let evidence = [
                    labelEvidence ? "launchd 标签与 Bundle ID 匹配：\(label)" : nil,
                    pathEvidence ? "启动程序位于 App 包内" : nil,
                    keepAlive ? "KeepAlive 会在退出后尝试重启" : nil
                ].compactMap { $0 }
                guard let node = makeNode(
                    at: child,
                    kind: kind,
                    ownership: ownership,
                    action: .readOnly,
                    evidence: evidence + ["服务配置保持只读；卸载后可在最终复核中检查"]
                ) else { continue }
                result.append(node)
            }
        }
        return result
    }

    private func embeddedNodes(applicationURL: URL) -> [ApplicationDependencyNode] {
        let specs: [(String, Set<String>, ApplicationDependencyKind)] = [
            ("Contents/Library/LoginItems", ["app"], .loginItem),
            ("Contents/PlugIns", ["appex"], .appExtension),
            ("Contents/Library/SystemExtensions", ["systemextension"], .systemExtension)
        ]
        var result: [ApplicationDependencyNode] = []
        for (relativePath, extensions, kind) in specs {
            let root = applicationURL.appendingPathComponent(relativePath, isDirectory: true)
            for child in FileTree.directChildren(of: root) where extensions.contains(child.pathExtension.lowercased()) {
                guard let node = makeNode(
                    at: child,
                    kind: kind,
                    ownership: .applicationOwned,
                    action: .includedInApplication,
                    evidence: ["位于 App 包内；随 App 本体一起进入废纸篓", "不是额外删除动作"]
                ) else { continue }
                result.append(node)
            }
        }
        return result
    }

    private func unverifiedNameMatches(
        application: InstalledApplication,
        excluding paths: Set<String>
    ) -> [ApplicationDependencyNode] {
        let needle = application.name
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
        guard needle.count >= 4 else { return [] }
        let roots = [
            "Library/Application Support",
            "Library/Caches",
            "Library/Logs"
        ]
        var result: [ApplicationDependencyNode] = []
        for relativePath in roots {
            let root = homeDirectory.appendingPathComponent(relativePath, isDirectory: true)
            for child in FileTree.directChildren(of: root) {
                guard !paths.contains(child.standardizedFileURL.path) else { continue }
                let normalized = child.lastPathComponent
                    .replacingOccurrences(of: " ", with: "")
                    .lowercased()
                guard normalized.contains(needle) else { continue }
                guard let node = makeNode(
                    at: child,
                    kind: .unverifiedItem,
                    ownership: .unverified,
                    action: .readOnly,
                    evidence: ["名称近似：\(application.name)", "没有 Bundle ID、签名或注册元数据证明归属"]
                ) else { continue }
                result.append(node)
                if result.count >= 12 { return result }
            }
        }
        return result
    }

    private func makeNode(
        at url: URL,
        kind: ApplicationDependencyKind,
        ownership: ApplicationDependencyOwnership,
        action: ApplicationDependencyAction,
        evidence: [String]
    ) -> ApplicationDependencyNode? {
        guard let identity = try? ApplicationDependencyIdentity.capture(at: url) else { return nil }
        return ApplicationDependencyNode(
            name: url.lastPathComponent,
            url: url,
            kind: kind,
            ownership: ownership,
            action: action,
            allocatedBytes: FileTree.allocatedSize(of: url),
            evidence: evidence,
            identity: identity
        )
    }

    private func exactMatch(_ name: String, identifier: String) -> Bool {
        name == identifier
            || name == identifier + ".plist"
            || name == identifier + ".savedState"
    }

    private func inspectSignature(at url: URL) -> ApplicationCodeSignatureEvidence {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard creation == errSecSuccess, let code else {
            return ApplicationCodeSignatureEvidence(
                status: creation == errSecCSUnsigned ? .unsigned : .unavailable,
                signingIdentifier: nil,
                teamIdentifier: nil,
                applicationGroups: [],
                diagnostic: "无法读取代码签名（状态 \(creation)）。"
            )
        }

        let validation = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            nil
        )
        var rawInformation: CFDictionary?
        let copied = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &rawInformation
        )
        let information = copied == errSecSuccess ? rawInformation as? [CFString: Any] : nil
        let entitlements = information?[kSecCodeInfoEntitlementsDict] as? [String: Any]
        let groups = (entitlements?["com.apple.security.application-groups"] as? [String] ?? [])
            .filter { !$0.isEmpty }
            .sorted()
        let status: ApplicationCodeSignatureEvidence.Status
        if validation == errSecSuccess {
            status = .valid
        } else if validation == errSecCSUnsigned {
            status = .unsigned
        } else {
            status = .invalid
        }
        return ApplicationCodeSignatureEvidence(
            status: status,
            signingIdentifier: information?[kSecCodeInfoIdentifier] as? String,
            teamIdentifier: information?[kSecCodeInfoTeamIdentifier] as? String,
            applicationGroups: groups,
            diagnostic: validation == errSecSuccess
                ? "macOS 代码签名校验通过。"
                : "macOS 代码签名校验状态：\(validation)。"
        )
    }

    private func inspectRegistration(for application: InstalledApplication) -> ApplicationRegistrationEvidence {
        guard let identifier = application.bundleIdentifier, !identifier.isEmpty else {
            return ApplicationRegistrationEvidence(
                bundleIdentifier: nil,
                registeredURLs: [],
                scannedPathIsRegistered: false,
                diagnostic: "没有 Bundle ID，无法查询 Launch Services 注册记录。"
            )
        }
        let raw = LSCopyApplicationURLsForBundleIdentifier(identifier as CFString, nil)?.takeRetainedValue()
        let urls = (raw as? [URL] ?? []).map(\.standardizedFileURL)
        let scanned = application.url.resolvingSymlinksInPath().standardizedFileURL
        let isRegistered = urls.contains {
            $0.resolvingSymlinksInPath().standardizedFileURL == scanned
        }
        return ApplicationRegistrationEvidence(
            bundleIdentifier: identifier,
            registeredURLs: urls,
            scannedPathIsRegistered: isRegistered,
            diagnostic: isRegistered
                ? "Launch Services 已登记当前扫描路径。"
                : (urls.isEmpty
                    ? "Launch Services 没有返回该 Bundle ID 的登记路径。"
                    : "Launch Services 登记的是其他路径；卸载前必须以稳定文件身份复核。")
        )
    }

    private func actionRank(_ action: ApplicationDependencyAction) -> Int {
        switch action {
        case .applicationBundle: return 0
        case .removeAfterApplication: return 1
        case .includedInApplication: return 2
        case .readOnly: return 3
        }
    }
}
