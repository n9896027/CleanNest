import Darwin
import Foundation

public enum LocalModelControlLevel: String, Codable, Equatable, Sendable {
    case cleanNestOwned
    case currentUserProcess
    case currentUserLaunchAgent
    case protectedReadOnly

    public var title: String {
        switch self {
        case .cleanNestOwned: return "CleanNest 自启"
        case .currentUserProcess: return "当前用户进程"
        case .currentUserLaunchAgent: return "用户守护"
        case .protectedReadOnly: return "受保护 · 只读"
        }
    }

    public var capability: String {
        switch self {
        case .cleanNestOwned:
            return "可直接正常停止；模型文件和设置保持不变。"
        case .currentUserProcess:
            return "风险确认并重新核对身份后，可向精确 PID 发送正常退出。"
        case .currentUserLaunchAgent:
            return "确认后可停用并 bootout 精确用户 LaunchAgent，也可重新启用。"
        case .protectedReadOnly:
            return "系统、其他用户或身份不足的服务只展示证据，不提供控制。"
        }
    }
}

public struct LocalModelClientConnection: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let processID: Int32
    public let commandName: String
    public let endpoint: LocalModelListener

    public init(processID: Int32, commandName: String, endpoint: LocalModelListener) {
        self.processID = processID
        self.commandName = String(commandName.prefix(128))
        self.endpoint = endpoint
    }

    public var id: String { "\(processID):\(endpoint.displayAddress)" }
}

public enum LocalModelRuntimeIssueKind: String, Codable, Equatable, Hashable, Sendable {
    case configuredPortConflict
    case modelSelectionMismatch
    case automaticRestart
    case activeClients
    case localNetworkExposure
    case apiUnverified
    case noLoadedModel
}

public struct LocalModelRuntimeIssue: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let kind: LocalModelRuntimeIssueKind
    public let title: String
    public let detail: String
    public let isWarning: Bool

    public init(
        kind: LocalModelRuntimeIssueKind,
        title: String,
        detail: String,
        isWarning: Bool
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.isWarning = isWarning
    }

    public var id: LocalModelRuntimeIssueKind { kind }
}

public struct LocalModelTCPConnectionRecord: Equatable, Sendable {
    public let processID: Int32
    public let commandName: String
    public let localEndpoint: LocalModelListener
    public let remoteEndpoint: LocalModelListener

    public init(
        processID: Int32,
        commandName: String,
        localEndpoint: LocalModelListener,
        remoteEndpoint: LocalModelListener
    ) {
        self.processID = processID
        self.commandName = commandName
        self.localEndpoint = localEndpoint
        self.remoteEndpoint = remoteEndpoint
    }
}

public extension LocalModelRuntimeInstance {
    var controlLevel: LocalModelControlLevel {
        if isOwnedByCleanNest { return .cleanNestOwned }
        if let supervisor,
           supervisor.kind == .userLaunchAgent,
           supervisor.isOwnedByCurrentUser {
            return .currentUserLaunchAgent
        }
        if process?.ownerUserID == UInt32(getuid()), canRequestExternalStop {
            return .currentUserProcess
        }
        return .protectedReadOnly
    }
}

public struct LocalModelServiceTopology: Identifiable, Equatable, Sendable {
    public let runtimeID: String
    public let platform: LocalModelPlatform
    public let phase: LocalModelRuntimePhase
    public let address: String?
    public let modelIDs: [String]
    public let clients: [LocalModelClientConnection]
    public let supervisorLabel: String?
    public let controlLevel: LocalModelControlLevel
    public let issues: [LocalModelRuntimeIssue]

    public var id: String { runtimeID }
}

public struct LocalModelPlatformTopology: Identifiable, Equatable, Sendable {
    public let platform: LocalModelPlatform
    public let services: [LocalModelServiceTopology]
    public var id: LocalModelPlatform { platform }
}

public extension LocalModelRuntimeSnapshot {
    var topology: [LocalModelPlatformTopology] {
        let grouped = Dictionary(grouping: instances, by: \.platform)
        return LocalModelPlatform.allCases.compactMap { platform in
            guard let runtimes = grouped[platform], !runtimes.isEmpty else { return nil }
            let services = runtimes.map { runtime in
                LocalModelServiceTopology(
                    runtimeID: runtime.id,
                    platform: runtime.platform,
                    phase: runtime.phase,
                    address: runtime.primaryAddress,
                    modelIDs: runtime.modelIDs,
                    clients: runtime.clients,
                    supervisorLabel: runtime.supervisor?.label,
                    controlLevel: runtime.controlLevel,
                    issues: runtime.issues
                )
            }
            return LocalModelPlatformTopology(platform: platform, services: services)
        }
    }
}

public enum LocalModelAdapterAPIStyle: String, Equatable, Sendable {
    case openAICompatible
    case ollama
}

public struct LocalModelPlatformAdapterDescriptor: Equatable, Identifiable, Sendable {
    public let platform: LocalModelPlatform
    public let processMarkers: [String]
    public let defaultPorts: [Int]
    public let apiStyle: LocalModelAdapterAPIStyle

    public var id: LocalModelPlatform { platform }

    public func matches(processText rawText: String) -> Bool {
        let text = rawText.lowercased()
        return processMarkers.contains { text.contains($0) }
    }
}

public enum LocalModelPlatformAdapterRegistry {
    public static let adapters: [LocalModelPlatformAdapterDescriptor] = [
        .init(platform: .omlx, processMarkers: ["omlx"], defaultPorts: [8_080], apiStyle: .openAICompatible),
        .init(platform: .mlxLM, processMarkers: ["mlx_lm.server", "mlx-lm-server"], defaultPorts: [8_080], apiStyle: .openAICompatible),
        .init(platform: .mlxServe, processMarkers: ["mlx-serve"], defaultPorts: [11_234], apiStyle: .openAICompatible),
        .init(platform: .ollama, processMarkers: ["ollama"], defaultPorts: [11_434], apiStyle: .ollama),
        .init(platform: .lmStudio, processMarkers: ["lm studio", "lm-studio", "lmstudio"], defaultPorts: [1_234], apiStyle: .openAICompatible),
        .init(platform: .llamaCPP, processMarkers: ["llama-server", "llama_server", "llama.cpp"], defaultPorts: [8_080], apiStyle: .openAICompatible)
    ]

    public static var defaultPorts: [Int] {
        Array(Set(adapters.flatMap(\.defaultPorts))).sorted()
    }

    public static func adapter(for platform: LocalModelPlatform?) -> LocalModelPlatformAdapterDescriptor? {
        guard let platform else { return nil }
        return adapters.first { $0.platform == platform }
    }

    public static func classify(processText: String) -> LocalModelPlatform? {
        adapters.first { $0.matches(processText: processText) }?.platform
    }
}

public enum LocalModelStartReadiness: Equatable, Sendable {
    case ready
    case configurationMissing(String)
    case unsupportedExecutable(String)
    case portOccupied(LocalModelRuntimeInstance)
    case busy

    public var canStart: Bool { self == .ready }

    public var detail: String {
        switch self {
        case .ready:
            return "配置完整，端口当前未被占用。"
        case .configurationMissing(let detail), .unsupportedExecutable(let detail):
            return detail
        case .portOccupied(let runtime):
            return "\(runtime.primaryAddress ?? "配置端口") 已由 \(runtime.process?.commandName ?? runtime.platform.displayName) 使用。"
        case .busy:
            return "另一项模型操作仍在进行。"
        }
    }
}

public enum LocalModelStartPolicy {
    public static func evaluate(
        modelIsComplete: Bool,
        executablePath: String,
        configuredPort: Int?,
        runtimes: [LocalModelRuntimeInstance],
        isBusy: Bool
    ) -> LocalModelStartReadiness {
        if isBusy { return .busy }
        guard modelIsComplete else {
            return .configurationMissing("本机模型目录不完整，或尚未选择模型。")
        }
        let name = URL(fileURLWithPath: executablePath).lastPathComponent.lowercased()
        guard !name.isEmpty else {
            return .configurationMissing("尚未选择本机模型服务程序。")
        }
        guard name == "omlx" || name.hasPrefix("omlx-")
                || name.contains("mlx_lm.server") || name.contains("mlx-lm-server") else {
            return .unsupportedExecutable("CleanNest 自启目前只支持 oMLX 与 MLX-LM；其他平台保持发现和确认后控制。")
        }
        guard let configuredPort else {
            return .configurationMissing("回环服务端口无效。")
        }
        if let occupied = runtimes.first(where: { runtime in
            runtime.listeners.contains { $0.port == configuredPort }
        }) {
            return .portOccupied(occupied)
        }
        return .ready
    }
}

public enum LocalModelRuntimeTransitionKind: String, Codable, Equatable, Sendable {
    case appeared
    case disappeared
    case processReplaced
    case modelChanged
    case wakeRecheck
    case startFailed
}

public struct LocalModelRuntimeTransition: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let kind: LocalModelRuntimeTransitionKind
    public let runtimeID: String
    public let title: String
    public let detail: String

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        kind: LocalModelRuntimeTransitionKind,
        runtimeID: String,
        title: String,
        detail: String
    ) {
        self.id = id
        self.date = date
        self.kind = kind
        self.runtimeID = runtimeID
        self.title = title
        self.detail = detail
    }
}

public enum LocalModelRuntimeTransitionDetector {
    public static func compare(
        previous: LocalModelRuntimeSnapshot,
        current: LocalModelRuntimeSnapshot,
        date: Date = Date()
    ) -> [LocalModelRuntimeTransition] {
        guard previous.capturedAt != .distantPast else { return [] }
        var transitions: [LocalModelRuntimeTransition] = []
        var matchedCurrentIDs = Set<String>()

        for old in previous.instances where old.process != nil {
            let replacement = current.instances.first { new in
                new.platform == old.platform
                    && new.process?.pid != old.process?.pid
                    && !Set(new.listeners.map(\.port)).isDisjoint(with: old.listeners.map(\.port))
            }
            if let replacement {
                matchedCurrentIDs.insert(replacement.id)
                transitions.append(.init(
                    date: date,
                    kind: .processReplaced,
                    runtimeID: replacement.id,
                    title: "模型服务出现新进程",
                    detail: "\(old.platform.displayName) 从 PID \(old.process?.pid ?? 0) 变为 PID \(replacement.process?.pid ?? 0)；\(replacement.supervisor == nil ? "可能由平台自身重新启动" : "已关联自动拉起守护")。"
                ))
                continue
            }
            guard !current.instances.contains(where: { $0.id == old.id }) else { continue }
            transitions.append(.init(
                date: date,
                kind: .disappeared,
                runtimeID: old.id,
                title: "模型服务已离开",
                detail: "\(old.platform.displayName) · PID \(old.process?.pid ?? 0) 当前不再监听。"
            ))
        }

        for new in current.instances where new.process != nil && !matchedCurrentIDs.contains(new.id) {
            guard !previous.instances.contains(where: { $0.id == new.id }) else {
                if let old = previous.instances.first(where: { $0.id == new.id }),
                   old.modelIDs != new.modelIDs {
                    transitions.append(.init(
                        date: date,
                        kind: .modelChanged,
                        runtimeID: new.id,
                        title: "服务模型列表已变化",
                        detail: "\(new.platform.displayName) 现在列出 \(new.modelIDs.count) 个模型短 ID。"
                    ))
                }
                continue
            }
            transitions.append(.init(
                date: date,
                kind: .appeared,
                runtimeID: new.id,
                title: "发现模型服务",
                detail: "\(new.platform.displayName) · PID \(new.process?.pid ?? 0) · \(new.primaryAddress ?? "地址未确认")。"
            ))
        }
        return transitions
    }
}

extension Array {
    func cnUniqued<Key: Hashable>(on key: (Element) -> Key) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert(key($0)).inserted }
    }
}
