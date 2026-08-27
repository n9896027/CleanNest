import Darwin
import Foundation

public enum AgentDependencyNodeKind: String, Codable, Sendable {
    case agent
    case application
    case data
    case process
    case supervisor
    case endpoint
    case localModel

    public var displayName: String {
        switch self {
        case .agent: return "Agent"
        case .application: return "应用"
        case .data: return "本机数据"
        case .process: return "进程"
        case .supervisor: return "守护服务"
        case .endpoint: return "端口"
        case .localModel: return "本地模型"
        }
    }
}

public enum AgentDependencyNodeState: String, Codable, Sendable {
    case notDetected
    case detected
    case running
    case unverified

    public var displayName: String {
        switch self {
        case .notDetected: return "未发现"
        case .detected: return "已发现"
        case .running: return "运行中"
        case .unverified: return "待验证"
        }
    }
}

public struct AgentDependencyNode: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let provider: AgentWorkspaceProvider?
    public let kind: AgentDependencyNodeKind
    public let title: String
    public let detail: String
    public let state: AgentDependencyNodeState

    public init(
        id: String,
        provider: AgentWorkspaceProvider?,
        kind: AgentDependencyNodeKind,
        title: String,
        detail: String,
        state: AgentDependencyNodeState
    ) {
        self.id = id
        self.provider = provider
        self.kind = kind
        self.title = String(title.prefix(160))
        self.detail = String(detail.prefix(320))
        self.state = state
    }
}

public enum AgentDependencyRelation: String, Codable, Sendable {
    case installedAs
    case storesDataIn
    case runsAs
    case keptAliveBy
    case exposes
    case servesModel
    case connectsToModel

    public var displayName: String {
        switch self {
        case .installedAs: return "安装为"
        case .storesDataIn: return "数据位于"
        case .runsAs: return "运行进程"
        case .keptAliveBy: return "受守护"
        case .exposes: return "监听"
        case .servesModel: return "提供"
        case .connectsToModel: return "实测连接"
        }
    }
}

public enum AgentDependencyEvidence: String, Codable, Sendable {
    case exactBundleIdentifier
    case verifiedDataRoot
    case exactProcess
    case launchdLabel
    case listeningSocket
    case establishedTCPConnection

    public var displayName: String {
        switch self {
        case .exactBundleIdentifier: return "Bundle ID"
        case .verifiedDataRoot: return "默认目录"
        case .exactProcess: return "进程命令"
        case .launchdLabel: return "launchd 标签"
        case .listeningSocket: return "监听套接字"
        case .establishedTCPConnection: return "已建立 TCP 连接"
        }
    }
}

public struct AgentDependencyEdge: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceID: String
    public let destinationID: String
    public let relation: AgentDependencyRelation
    public let evidence: AgentDependencyEvidence

    public init(
        sourceID: String,
        destinationID: String,
        relation: AgentDependencyRelation,
        evidence: AgentDependencyEvidence
    ) {
        self.id = "\(sourceID)>\(destinationID)>\(relation.rawValue)"
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.relation = relation
        self.evidence = evidence
    }
}

public struct AgentDependencyGraphSnapshot: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let nodes: [AgentDependencyNode]
    public let edges: [AgentDependencyEdge]
    public let diagnostic: String

    public init(
        capturedAt: Date = Date(),
        nodes: [AgentDependencyNode],
        edges: [AgentDependencyEdge],
        diagnostic: String
    ) {
        self.capturedAt = capturedAt
        self.nodes = nodes
        self.edges = edges
        self.diagnostic = diagnostic
    }

    public static let empty = Self(
        capturedAt: .distantPast,
        nodes: [],
        edges: [],
        diagnostic: "尚未建立 Agent 运行关系图。"
    )

    public var runningProviderCount: Int {
        Set(nodes.filter { $0.kind == .process && $0.provider != nil }.compactMap(\.provider)).count
    }

    public var confirmedModelConnectionCount: Int {
        edges.filter { $0.relation == .connectsToModel }.count
    }

    public func nodes(for provider: AgentWorkspaceProvider) -> [AgentDependencyNode] {
        nodes.filter { $0.provider == provider }
    }

    public func connections(for provider: AgentWorkspaceProvider) -> [AgentDependencyEdge] {
        let ids = Set(nodes(for: provider).map(\.id))
        return edges.filter { ids.contains($0.sourceID) || ids.contains($0.destinationID) }
    }
}

public struct AgentDependencyGraphBuilder: Sendable {
    private struct ProcessRecord: Sendable {
        let pid: Int32
        let parentPID: Int32
        let userID: UInt32
        let rssBytes: Int64
        let command: String
    }

    private struct ConnectionRecord: Sendable {
        let pid: Int32
        let peerPort: Int
    }

    private struct ApplicationRecord: Sendable {
        let name: String
        let bundleIdentifier: String?
        let path: String
    }

    public init() {}

    public func build(
        workspace: AgentWorkspaceSnapshot?,
        catalog: AgentRuleCatalog,
        localModels: LocalModelRuntimeSnapshot,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        suppliedProcessOutput: String? = nil,
        suppliedLaunchctlOutput: String? = nil,
        suppliedConnectionOutput: String? = nil,
        suppliedApplications: [(name: String, bundleIdentifier: String?, path: String)]? = nil,
        now: Date = Date()
    ) async -> AgentDependencyGraphSnapshot {
        let evidence = await Task.detached(priority: .utility) {
            let processOutput = suppliedProcessOutput ?? Self.run(
                executable: "/bin/ps",
                arguments: ["-axo", "pid=,ppid=,uid=,rss=,command="],
                maximumBytes: 4 * 1_024 * 1_024
            )
            let launchctlOutput = suppliedLaunchctlOutput ?? Self.run(
                executable: "/bin/launchctl",
                arguments: ["list"],
                maximumBytes: 2 * 1_024 * 1_024
            )
            let connectionOutput = suppliedConnectionOutput ?? Self.run(
                executable: "/usr/sbin/lsof",
                arguments: ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-Fpcn"],
                maximumBytes: 4 * 1_024 * 1_024
            )
            let apps: [ApplicationRecord]
            if let suppliedApplications {
                apps = suppliedApplications.map { .init(name: $0.name, bundleIdentifier: $0.bundleIdentifier, path: $0.path) }
            } else {
                apps = Self.installedApplications(homeDirectory: homeDirectory)
            }
            return (
                Self.parseProcessOutput(processOutput),
                Self.parseLaunchctlLabels(launchctlOutput),
                Self.parseConnectionOutput(connectionOutput),
                apps
            )
        }.value

        let currentUserID = getuid()
        let processes = evidence.0.filter { $0.userID == currentUserID }
        let labels = evidence.1
        let connections = evidence.2
        let applications = evidence.3
        var nodes: [AgentDependencyNode] = []
        var edges: [AgentDependencyEdge] = []
        var processProviders: [Int32: AgentWorkspaceProvider] = [:]

        for rule in catalog.providers {
            let provider = rule.provider
            let agentID = "agent:\(provider.rawValue)"
            let workspaceAgent = workspace?.agents.first { $0.provider == provider }
            let matchedApps = applications.filter { Self.matches(application: $0, rule: rule) }
            let matchedProcesses = processes.filter { Self.matches(process: $0, rule: rule) }
                .prefix(8)
            let matchedLabels = labels.filter { Self.matches(label: $0, rule: rule) }.prefix(6)
            let hasEvidence = workspaceAgent?.detected == true
                || !matchedApps.isEmpty || !matchedProcesses.isEmpty || !matchedLabels.isEmpty
            let agentState: AgentDependencyNodeState
            if rule.verification == .detectionOnly {
                agentState = .unverified
            } else if !matchedProcesses.isEmpty {
                agentState = .running
            } else if hasEvidence {
                agentState = .detected
            } else {
                agentState = .notDetected
            }
            nodes.append(.init(
                id: agentID,
                provider: provider,
                kind: .agent,
                title: provider.displayName,
                detail: rule.verification.displayName,
                state: agentState
            ))

            for app in matchedApps.prefix(4) {
                let nodeID = "app:\(provider.rawValue):\(Self.stableKey(app.path))"
                nodes.append(.init(
                    id: nodeID,
                    provider: provider,
                    kind: .application,
                    title: app.name,
                    detail: app.bundleIdentifier ?? "Bundle ID 未提供",
                    state: .detected
                ))
                edges.append(.init(
                    sourceID: agentID,
                    destinationID: nodeID,
                    relation: .installedAs,
                    evidence: .exactBundleIdentifier
                ))
            }

            if let workspaceAgent, workspaceAgent.detected {
                let nodeID = "data:\(provider.rawValue)"
                nodes.append(.init(
                    id: nodeID,
                    provider: provider,
                    kind: .data,
                    title: "\(workspaceAgent.artifacts.count) 类本机数据",
                    detail: "\(CleanNestFormatting.bytes(workspaceAgent.allocatedBytes)) · \(workspaceAgent.fileCount.formatted()) 个文件",
                    state: workspaceAgent.isComplete ? .detected : .unverified
                ))
                edges.append(.init(
                    sourceID: agentID,
                    destinationID: nodeID,
                    relation: .storesDataIn,
                    evidence: .verifiedDataRoot
                ))
            }

            for process in matchedProcesses {
                processProviders[process.pid] = provider
                let nodeID = "process:\(process.pid)"
                let commandName = Self.commandName(process.command)
                nodes.append(.init(
                    id: nodeID,
                    provider: provider,
                    kind: .process,
                    title: "\(commandName) · PID \(process.pid)",
                    detail: "内存 \(CleanNestFormatting.bytes(process.rssBytes)) · 父进程 \(process.parentPID)",
                    state: .running
                ))
                edges.append(.init(
                    sourceID: agentID,
                    destinationID: nodeID,
                    relation: .runsAs,
                    evidence: .exactProcess
                ))
            }

            for label in matchedLabels {
                let nodeID = "supervisor:\(provider.rawValue):\(Self.stableKey(label))"
                nodes.append(.init(
                    id: nodeID,
                    provider: provider,
                    kind: .supervisor,
                    title: label,
                    detail: "用户 launchd 服务",
                    state: .running
                ))
                edges.append(.init(
                    sourceID: agentID,
                    destinationID: nodeID,
                    relation: .keptAliveBy,
                    evidence: .launchdLabel
                ))
            }
        }

        var modelNodeByPort: [Int: String] = [:]
        for model in localModels.instances {
            let modelNodeID = "model:\(Self.stableKey(model.id))"
            let modelTitle = model.primaryModelID ?? model.platform.displayName
            nodes.append(.init(
                id: modelNodeID,
                provider: nil,
                kind: .localModel,
                title: modelTitle,
                detail: model.platform.displayName,
                state: model.phase == .runningHealthy || model.phase == .runningUnverified ? .running : .detected
            ))
            for listener in model.listeners {
                let endpointID = "endpoint:\(listener.host):\(listener.port)"
                if !nodes.contains(where: { $0.id == endpointID }) {
                    nodes.append(.init(
                        id: endpointID,
                        provider: nil,
                        kind: .endpoint,
                        title: listener.displayAddress,
                        detail: model.exposure.displayName,
                        state: .running
                    ))
                }
                modelNodeByPort[listener.port] = modelNodeID
                edges.append(.init(
                    sourceID: endpointID,
                    destinationID: modelNodeID,
                    relation: .servesModel,
                    evidence: .listeningSocket
                ))
                if let process = model.process {
                    let modelProcessID = "model-process:\(process.pid)"
                    if !nodes.contains(where: { $0.id == modelProcessID }) {
                        nodes.append(.init(
                            id: modelProcessID,
                            provider: nil,
                            kind: .process,
                            title: "\(process.commandName) · PID \(process.pid)",
                            detail: "模型服务进程",
                            state: .running
                        ))
                    }
                    edges.append(.init(
                        sourceID: modelProcessID,
                        destinationID: endpointID,
                        relation: .exposes,
                        evidence: .listeningSocket
                    ))
                }
            }
        }

        for connection in connections {
            guard processProviders[connection.pid] != nil,
                  let modelID = modelNodeByPort[connection.peerPort] else { continue }
            edges.append(.init(
                sourceID: "process:\(connection.pid)",
                destinationID: modelID,
                relation: .connectsToModel,
                evidence: .establishedTCPConnection
            ))
        }

        nodes = Self.uniqued(nodes).sorted { lhs, rhs in
            (lhs.provider?.rawValue ?? "zz-model", lhs.kind.rawValue, lhs.title)
                < (rhs.provider?.rawValue ?? "zz-model", rhs.kind.rawValue, rhs.title)
        }
        edges = Array(Set(edges.map(\.id))).compactMap { id in edges.first { $0.id == id } }
            .sorted { $0.id < $1.id }
        let detected = nodes.filter { $0.kind == .agent && $0.state != .notDetected && $0.state != .unverified }.count
        let linked = edges.filter { $0.relation == .connectsToModel }.count
        let diagnostic = linked > 0
            ? "已发现 \(detected) 个有本机证据的 Agent；\(linked) 条 Agent 到本地模型的关系由已建立 TCP 连接确认。"
            : "已发现 \(detected) 个有本机证据的 Agent；当前没有已建立 TCP 连接可证明某个 Agent 正在调用本地模型。"
        return .init(capturedAt: now, nodes: nodes, edges: edges, diagnostic: diagnostic)
    }

    private static func matches(application: ApplicationRecord, rule: AgentProviderRule) -> Bool {
        if let identifier = application.bundleIdentifier,
           rule.bundleIdentifiers.contains(where: { $0.caseInsensitiveCompare(identifier) == .orderedSame }) {
            return true
        }
        return rule.applicationNames.contains { $0.caseInsensitiveCompare(application.name) == .orderedSame }
    }

    private static func matches(process: ProcessRecord, rule: AgentProviderRule) -> Bool {
        let command = process.command.lowercased()
        if rule.applicationNames.contains(where: {
            command.contains("/\($0.lowercased()).app/")
        }) { return true }
        let executable = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        let basename = URL(fileURLWithPath: executable).lastPathComponent
        return rule.processMarkers.contains { marker in
            let value = marker.lowercased()
            return basename == value || basename.hasPrefix(value + "-") || basename.hasSuffix("-" + value)
        }
    }

    private static func matches(label: String, rule: AgentProviderRule) -> Bool {
        let normalized = label.lowercased()
        return rule.supervisorMarkers.contains { normalized.contains($0.lowercased()) }
    }

    private static func parseProcessOutput(_ output: String) -> [ProcessRecord] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard parts.count == 5,
                  let pid = Int32(parts[0]),
                  let parent = Int32(parts[1]),
                  let uid = UInt32(parts[2]),
                  let rssKiB = Int64(parts[3]) else { return nil }
            return .init(
                pid: pid,
                parentPID: parent,
                userID: uid,
                rssBytes: max(0, rssKiB) * 1_024,
                command: String(parts[4])
            )
        }
    }

    private static func parseLaunchctlLabels(_ output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).compactMap { line in
            let columns = line.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard columns.count >= 3 else { return nil }
            let label = String(columns.last ?? "")
            return label == "Label" ? nil : label
        }
    }

    private static func parseConnectionOutput(_ output: String) -> [ConnectionRecord] {
        var currentPID: Int32?
        var records: [ConnectionRecord] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let prefix = line.first else { continue }
            let value = String(line.dropFirst())
            if prefix == "p" {
                currentPID = Int32(value)
            } else if prefix == "n", let pid = currentPID,
                      let arrow = value.range(of: "->") {
                let peer = String(value[arrow.upperBound...]).split(separator: " ").first.map(String.init) ?? ""
                let portText = peer.split(separator: ":").last.map(String.init) ?? ""
                if let port = Int(portText), (1...65_535).contains(port) {
                    records.append(.init(pid: pid, peerPort: port))
                }
            }
        }
        return records
    }

    private static func installedApplications(homeDirectory: URL) -> [ApplicationRecord] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        return roots.flatMap { root -> [ApplicationRecord] in
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { return [] }
            return children.prefix(1_000).compactMap { url in
                guard url.pathExtension.lowercased() == "app" else { return nil }
                let plist = url.appendingPathComponent("Contents/Info.plist")
                let values = NSDictionary(contentsOf: plist)
                return .init(
                    name: url.deletingPathExtension().lastPathComponent,
                    bundleIdentifier: values?["CFBundleIdentifier"] as? String,
                    path: url.standardizedFileURL.path
                )
            }
        }
    }

    private static func run(executable: String, arguments: [String], maximumBytes: Int) -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard data.count <= maximumBytes else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private static func commandName(_ command: String) -> String {
        let executable = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
        return String(URL(fileURLWithPath: executable).lastPathComponent.prefix(80))
    }

    private static func stableKey(_ value: String) -> String {
        value.unicodeScalars.reduce(into: UInt64(14_695_981_039_346_656_037)) { hash, scalar in
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }.description
    }

    private static func uniqued(_ nodes: [AgentDependencyNode]) -> [AgentDependencyNode] {
        var seen = Set<String>()
        return nodes.filter { seen.insert($0.id).inserted }
    }
}
