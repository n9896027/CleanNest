import Darwin
import Foundation

public enum LocalModelPlatform: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case omlx
    case mlxLM
    case ollama
    case lmStudio
    case llamaCPP
    case openAICompatible

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .omlx: return "oMLX"
        case .mlxLM: return "MLX-LM Server"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .llamaCPP: return "llama.cpp"
        case .openAICompatible: return "OpenAI 兼容服务"
        }
    }

    public var shortName: String {
        switch self {
        case .omlx: return "oMLX"
        case .mlxLM: return "MLX-LM"
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .llamaCPP: return "llama.cpp"
        case .openAICompatible: return "兼容服务"
        }
    }
}

public enum LocalModelRuntimePhase: String, Codable, Sendable {
    case unknown
    case discovering
    case stopped
    case runningUnverified
    case runningHealthy
    case failed
}

public enum LocalModelExposure: String, Codable, Sendable {
    case localOnly
    case localNetwork
    case unknown

    public var displayName: String {
        switch self {
        case .localOnly: return "仅本机"
        case .localNetwork: return "局域网可访问"
        case .unknown: return "地址未确认"
        }
    }
}

public enum LocalModelEvidenceKind: String, Codable, CaseIterable, Hashable, Sendable {
    case process
    case supervisor
    case listener
    case platformAPI
    case userConfiguration

    public var displayName: String {
        switch self {
        case .process: return "进程"
        case .supervisor: return "守护服务"
        case .listener: return "监听端口"
        case .platformAPI: return "平台 API"
        case .userConfiguration: return "用户配置"
        }
    }
}

public struct LocalModelListener: Equatable, Hashable, Codable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public var displayAddress: String {
        let visibleHost = host == "*" ? "0.0.0.0" : host
        if visibleHost.contains(":"), !visibleHost.hasPrefix("[") {
            return "[\(visibleHost)]:\(port)"
        }
        return "\(visibleHost):\(port)"
    }

    public var isLoopback: Bool {
        host == "127.0.0.1" || host == "::1" || host == "localhost"
    }

    public var isWildcard: Bool {
        host == "*" || host == "0.0.0.0" || host == "::" || host == "[::]"
    }
}

public struct LocalModelProcessSnapshot: Equatable, Codable, Sendable {
    public let pid: Int32
    public let commandName: String
    public let executablePath: String?
    public let residentMemoryBytes: Int64?
    public let startedAt: Date?

    public init(
        pid: Int32,
        commandName: String,
        executablePath: String?,
        residentMemoryBytes: Int64?,
        startedAt: Date?
    ) {
        self.pid = pid
        self.commandName = commandName
        self.executablePath = executablePath
        self.residentMemoryBytes = residentMemoryBytes
        self.startedAt = startedAt
    }
}

public struct LocalModelRuntimeInstance: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let platform: LocalModelPlatform
    public let phase: LocalModelRuntimePhase
    public let modelIDs: [String]
    public let defaultModelID: String?
    public let process: LocalModelProcessSnapshot?
    public let supervisor: LocalModelSupervisorSnapshot?
    public let listeners: [LocalModelListener]
    public let exposure: LocalModelExposure
    public let localNetworkAddresses: [String]
    public let evidence: [LocalModelEvidenceKind]
    public let isOwnedByCleanNest: Bool
    public let diagnostic: String
    public let engineMemoryBytes: Int64?

    public init(
        id: String,
        platform: LocalModelPlatform,
        phase: LocalModelRuntimePhase,
        modelIDs: [String],
        defaultModelID: String?,
        process: LocalModelProcessSnapshot?,
        supervisor: LocalModelSupervisorSnapshot? = nil,
        listeners: [LocalModelListener],
        exposure: LocalModelExposure,
        localNetworkAddresses: [String],
        evidence: [LocalModelEvidenceKind],
        isOwnedByCleanNest: Bool = false,
        diagnostic: String,
        engineMemoryBytes: Int64? = nil
    ) {
        self.id = id
        self.platform = platform
        self.phase = phase
        self.modelIDs = Self.normalizedModelIDs(modelIDs)
        self.defaultModelID = defaultModelID.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        self.process = process
        self.supervisor = supervisor
        self.listeners = Array(Set(listeners)).sorted {
            ($0.port, $0.host) < ($1.port, $1.host)
        }
        self.exposure = exposure
        self.localNetworkAddresses = Array(Set(localNetworkAddresses)).sorted()
        self.evidence = LocalModelEvidenceKind.allCases.filter { evidence.contains($0) }
        self.isOwnedByCleanNest = isOwnedByCleanNest
        self.diagnostic = diagnostic
        self.engineMemoryBytes = engineMemoryBytes
    }

    public var primaryModelID: String? {
        if let defaultModelID,
           let listed = modelIDs.first(where: {
               $0.caseInsensitiveCompare(defaultModelID) == .orderedSame
           }) {
            return listed
        }
        return modelIDs.first
    }

    public var primaryAddress: String? { listeners.first?.displayAddress }

    public var canStopDirectly: Bool {
        isOwnedByCleanNest && process != nil
    }

    public func markingOwned(processID: Int32?) -> Self {
        guard let processID, process?.pid == processID else { return self }
        return Self(
            id: id,
            platform: platform,
            phase: phase,
            modelIDs: modelIDs,
            defaultModelID: defaultModelID,
            process: process,
            supervisor: supervisor,
            listeners: listeners,
            exposure: exposure,
            localNetworkAddresses: localNetworkAddresses,
            evidence: evidence,
            isOwnedByCleanNest: true,
            diagnostic: diagnostic,
            engineMemoryBytes: engineMemoryBytes
        )
    }

    private static func normalizedModelIDs(_ rawValues: [String]) -> [String] {
        var seen = Set<String>()
        return rawValues.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  value.count <= 512,
                  !(value as NSString).isAbsolutePath,
                  !value.lowercased().hasPrefix("file://"),
                  value.unicodeScalars.allSatisfy({
                      !CharacterSet.controlCharacters.contains($0)
                  }) else { return nil }
            guard seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }
    }
}

public struct LocalModelRuntimeSnapshot: Equatable, Codable, Sendable {
    public let capturedAt: Date
    public let instances: [LocalModelRuntimeInstance]
    public let diagnostic: String

    public init(
        capturedAt: Date = Date(),
        instances: [LocalModelRuntimeInstance],
        diagnostic: String
    ) {
        self.capturedAt = capturedAt
        self.instances = instances
        self.diagnostic = diagnostic
    }

    public static let empty = LocalModelRuntimeSnapshot(
        capturedAt: .distantPast,
        instances: [],
        diagnostic: "尚未检查本地模型运行时"
    )

    public var phase: LocalModelRuntimePhase {
        if instances.contains(where: { $0.phase == .runningHealthy }) {
            return .runningHealthy
        }
        if instances.contains(where: { $0.phase == .runningUnverified }) {
            return .runningUnverified
        }
        if instances.contains(where: { $0.phase == .failed }) {
            return .failed
        }
        return .stopped
    }

    public var healthyInstances: [LocalModelRuntimeInstance] {
        instances.filter { $0.phase == .runningHealthy }
    }

    public var primaryInstance: LocalModelRuntimeInstance? {
        healthyInstances.first ?? instances.first
    }

    public func markingOwned(processID: Int32?) -> Self {
        Self(
            capturedAt: capturedAt,
            instances: instances.map { $0.markingOwned(processID: processID) },
            diagnostic: diagnostic
        )
    }
}

public struct LocalModelListenerRecord: Equatable, Sendable {
    public let pid: Int32
    public let commandName: String
    public let listener: LocalModelListener

    public init(pid: Int32, commandName: String, listener: LocalModelListener) {
        self.pid = pid
        self.commandName = commandName
        self.listener = listener
    }
}

public struct LocalModelRuntimeDiscovery: Sendable {
    private struct ProcessRecord: Sendable {
        let snapshot: LocalModelProcessSnapshot
        let argumentsForClassification: String
        let platform: LocalModelPlatform?
    }

    private struct Candidate: Hashable, Sendable {
        let port: Int
        let processID: Int32?
        let platformHint: LocalModelPlatform?
        let isConfigured: Bool
    }

    private struct APIProbe: Sendable {
        let platform: LocalModelPlatform
        let phase: LocalModelRuntimePhase
        let modelIDs: [String]
        let defaultModelID: String?
        let diagnostic: String
        let engineMemoryBytes: Int64?
    }

    public init() {}

    public func discover(configuredEndpoint: String? = nil) async -> LocalModelRuntimeSnapshot {
        let lsofResult = Self.runSystemCommand(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcn"]
        )
        let processResult = Self.runSystemCommand(
            executable: "/bin/ps",
            arguments: ["-axo", "pid=,rss=,lstart=,comm=,args="]
        )
        let listenerRecords = Self.parseLsofFieldOutput(lsofResult.output)
        let processRecords = Self.parseProcessList(processResult.output)
        let supervisorInventory = LocalModelSupervisorDiscovery.capture()
        let supervisorsByProcessID = supervisorInventory.byProcessID
        let localAddresses = Self.localIPv4Addresses()

        let configuredPort = configuredEndpoint.flatMap { rawValue in
            (try? LocalAIEndpoint(rawValue: rawValue))?.port
        }
        var candidatesByPort: [Int: Candidate] = [:]
        func registerCandidate(
            port: Int,
            processID: Int32?,
            platformHint: LocalModelPlatform?,
            isConfigured: Bool
        ) {
            let existing = candidatesByPort[port]
            candidatesByPort[port] = Candidate(
                port: port,
                processID: existing?.processID ?? processID,
                platformHint: existing?.platformHint ?? platformHint,
                isConfigured: existing?.isConfigured == true || isConfigured
            )
        }
        for record in listenerRecords {
            let process = processRecords[record.pid]
            let platform = process?.platform
                ?? Self.classifyPlatform(text: record.commandName)
            guard platform != nil || [8080, 11434, 1234].contains(record.listener.port)
                    || record.listener.port == configuredPort else { continue }
            registerCandidate(
                port: record.listener.port,
                processID: record.pid,
                platformHint: platform,
                isConfigured: record.listener.port == configuredPort
            )
        }

        for port in [8080, 11434, 1234] {
            registerCandidate(
                port: port,
                processID: listenerRecords.first(where: { $0.listener.port == port })?.pid,
                platformHint: port == 11434 ? .ollama : (port == 1234 ? .lmStudio : nil),
                isConfigured: port == configuredPort
            )
        }
        if let configuredPort {
            registerCandidate(
                port: configuredPort,
                processID: listenerRecords.first(where: { $0.listener.port == configuredPort })?.pid,
                platformHint: nil,
                isConfigured: true
            )
        }

        let probePairs = await withTaskGroup(
            of: (Candidate, APIProbe?).self,
            returning: [(Candidate, APIProbe?)].self
        ) { group in
            for candidate in candidatesByPort.values {
                group.addTask {
                    (candidate, await Self.probe(candidate: candidate))
                }
            }
            var values: [(Candidate, APIProbe?)] = []
            for await value in group { values.append(value) }
            return values
        }

        var instances: [LocalModelRuntimeInstance] = []
        var representedProcessIDs = Set<Int32>()
        for (candidate, apiProbe) in probePairs {
            let listenerMatches = listenerRecords.filter {
                $0.listener.port == candidate.port
                    && (candidate.processID == nil || $0.pid == candidate.processID)
            }
            let listeners = listenerMatches.map(\.listener)
            let process = candidate.processID.flatMap { processRecords[$0] }
            let supervisor = process.flatMap { supervisorsByProcessID[$0.snapshot.pid] }
            guard apiProbe != nil || process?.platform != nil || !listeners.isEmpty && candidate.isConfigured else {
                continue
            }
            if let pid = process?.snapshot.pid { representedProcessIDs.insert(pid) }
            let platform = apiProbe?.platform
                ?? process?.platform
                ?? candidate.platformHint
                ?? .openAICompatible
            let exposure = Self.exposure(for: listeners)
            var evidence: [LocalModelEvidenceKind] = []
            if process != nil { evidence.append(.process) }
            if supervisor != nil { evidence.append(.supervisor) }
            if !listeners.isEmpty { evidence.append(.listener) }
            if apiProbe != nil { evidence.append(.platformAPI) }
            if candidate.isConfigured { evidence.append(.userConfiguration) }
            let phase = apiProbe?.phase ?? .runningUnverified
            let diagnostic = apiProbe?.diagnostic
                ?? "发现进程或监听端口，但平台 API 尚未确认模型身份。"
            let stableID = "\(platform.rawValue):\(candidate.processID.map(String.init) ?? "api"):\(candidate.port)"
            instances.append(
                LocalModelRuntimeInstance(
                    id: stableID,
                    platform: platform,
                    phase: phase,
                    modelIDs: apiProbe?.modelIDs ?? [],
                    defaultModelID: apiProbe?.defaultModelID,
                    process: process?.snapshot,
                    supervisor: supervisor,
                    listeners: listeners.isEmpty
                        ? [LocalModelListener(host: "127.0.0.1", port: candidate.port)]
                        : listeners,
                    exposure: listeners.isEmpty ? .unknown : exposure,
                    localNetworkAddresses: exposure == .localNetwork
                        ? localAddresses.map { "\($0):\(candidate.port)" }
                        : [],
                    evidence: evidence,
                    diagnostic: diagnostic,
                    engineMemoryBytes: apiProbe?.engineMemoryBytes
                )
            )
        }

        for process in processRecords.values where process.platform != nil {
            guard !representedProcessIDs.contains(process.snapshot.pid) else { continue }
            let platform = process.platform ?? .openAICompatible
            instances.append(
                LocalModelRuntimeInstance(
                    id: "\(platform.rawValue):\(process.snapshot.pid):process",
                    platform: platform,
                    phase: .runningUnverified,
                    modelIDs: [],
                    defaultModelID: nil,
                    process: process.snapshot,
                    supervisor: supervisorsByProcessID[process.snapshot.pid],
                    listeners: [],
                    exposure: .unknown,
                    localNetworkAddresses: [],
                    evidence: [.process],
                    diagnostic: "发现模型相关进程，但没有确认到监听地址或可用模型。"
                )
            )
        }

        let representedSupervisorIDs = Set(instances.compactMap { $0.supervisor?.id })
        for supervisor in supervisorInventory.supervisors
            where !representedSupervisorIDs.contains(supervisor.id) && supervisor.processID == nil {
            instances.append(
                LocalModelRuntimeInstance(
                    id: "supervisor:\(supervisor.id)",
                    platform: supervisor.platform,
                    phase: .stopped,
                    modelIDs: [],
                    defaultModelID: nil,
                    process: nil,
                    supervisor: supervisor,
                    listeners: [],
                    exposure: .unknown,
                    localNetworkAddresses: [],
                    evidence: [.supervisor],
                    diagnostic: supervisor.isDisabled
                        ? "已发现停用的 \(supervisor.kind.displayName)，当前不会自动拉起模型服务。"
                        : "已发现模型守护配置，但当前没有对应进程。"
                )
            )
        }

        instances.sort { lhs, rhs in
            let lhsRank = Self.phaseRank(lhs.phase)
            let rhsRank = Self.phaseRank(rhs.phase)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.platform != rhs.platform {
                return lhs.platform.displayName < rhs.platform.displayName
            }
            return (lhs.process?.pid ?? 0) < (rhs.process?.pid ?? 0)
        }

        let commandFailures = [lsofResult, processResult].filter { $0.exitCode != 0 }
        let diagnostic: String
        if let healthy = instances.first(where: { $0.phase == .runningHealthy }) {
            diagnostic = "已确认 \(healthy.platform.displayName) 的进程、地址与模型 API。"
        } else if !instances.isEmpty {
            diagnostic = "发现模型相关运行迹象，但 API 或模型身份尚未完整确认。"
        } else if !commandFailures.isEmpty || supervisorInventory.commandFailed {
            diagnostic = "没有发现可用模型服务；部分系统进程证据无法读取。"
        } else {
            diagnostic = "当前没有发现正在运行的本地模型服务。"
        }

        return LocalModelRuntimeSnapshot(instances: instances, diagnostic: diagnostic)
    }

    public static func parseLsofFieldOutput(_ output: String) -> [LocalModelListenerRecord] {
        var records: [LocalModelListenerRecord] = []
        var currentPID: Int32?
        var currentCommand = ""
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
                currentCommand = ""
            case "c":
                currentCommand = Self.sanitizedProcessLabel(value)
            case "n":
                guard let pid = currentPID,
                      let listener = parseListener(value) else { continue }
                records.append(
                    LocalModelListenerRecord(
                        pid: pid,
                        commandName: currentCommand,
                        listener: listener
                    )
                )
            default:
                continue
            }
        }
        return records
    }

    public static func parseListener(_ rawValue: String) -> LocalModelListener? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let suffix = value.range(of: " (LISTEN)") { value.removeSubrange(suffix.lowerBound...) }
        let host: String
        let portText: String
        if value.hasPrefix("[") {
            guard let close = value.lastIndex(of: "]"),
                  value.index(after: close) < value.endIndex,
                  value[value.index(after: close)] == ":" else { return nil }
            host = String(value[value.index(after: value.startIndex)..<close])
            portText = String(value[value.index(close, offsetBy: 2)...])
        } else {
            guard let colon = value.lastIndex(of: ":") else { return nil }
            host = String(value[..<colon])
            portText = String(value[value.index(after: colon)...])
        }
        guard let port = Int(portText), (1...65_535).contains(port), !host.isEmpty else { return nil }
        return LocalModelListener(host: host, port: port)
    }

    public static func classifyPlatform(text rawText: String) -> LocalModelPlatform? {
        let text = rawText.lowercased()
        if text.contains("omlx") || text.contains("omlx-server") { return .omlx }
        if text.contains("mlx_lm.server") || text.contains("mlx-lm-server") { return .mlxLM }
        if text.contains("ollama") { return .ollama }
        if text.contains("lm studio") || text.contains("lm-studio") || text.contains("lmstudio") {
            return .lmStudio
        }
        if text.contains("llama-server") || text.contains("llama_server") || text.contains("llama.cpp") {
            return .llamaCPP
        }
        return nil
    }

    private static func parseProcessList(_ output: String) -> [Int32: ProcessRecord] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        var records: [Int32: ProcessRecord] = [:]
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let components = rawLine.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard components.count >= 8,
                  let pid = Int32(components[0]),
                  let rssKiB = Int64(components[1]) else { continue }
            let dateText = components[2...6].map(String.init).joined(separator: " ")
            let command = sanitizedProcessLabel(String(components[7]))
            let arguments = components.count > 8
                ? components[8...].map(String.init).joined(separator: " ")
                : ""
            let classificationText = command + " " + arguments
            let platform = classifyPlatform(text: classificationText)
            guard platform != nil else { continue }
            let executable = String(components[7])
            records[pid] = ProcessRecord(
                snapshot: LocalModelProcessSnapshot(
                    pid: pid,
                    commandName: command,
                    executablePath: executable.hasPrefix("/") ? executable : nil,
                    residentMemoryBytes: max(0, rssKiB) * 1_024,
                    startedAt: formatter.date(from: dateText)
                ),
                argumentsForClassification: classificationText,
                platform: platform
            )
        }
        return records
    }

    private static func probe(candidate: Candidate) async -> APIProbe? {
        if candidate.platformHint == .ollama || candidate.port == 11434 {
            if let result = await probeOllama(port: candidate.port) { return result }
        }
        return await probeOpenAICompatible(port: candidate.port, hint: candidate.platformHint)
    }

    private static func probeOpenAICompatible(
        port: Int,
        hint: LocalModelPlatform?
    ) async -> APIProbe? {
        guard let modelsURL = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return nil }
        let modelsResponse = await request(modelsURL, timeout: 1.8, maximumBytes: 256 * 1_024)
        guard let modelsResponse else { return nil }
        guard (200...299).contains(modelsResponse.statusCode) else {
            let diagnostic = modelsResponse.statusCode == 401 || modelsResponse.statusCode == 403
                ? "服务正在监听，但模型 API 需要认证；CleanNest 不读取或保存密钥。"
                : "服务正在监听，但 /v1/models 返回 HTTP \(modelsResponse.statusCode)。"
            return APIProbe(
                platform: hint ?? .openAICompatible,
                phase: .runningUnverified,
                modelIDs: [],
                defaultModelID: nil,
                diagnostic: diagnostic,
                engineMemoryBytes: nil
            )
        }

        guard let envelope = try? JSONDecoder().decode(OpenAIModelsEnvelope.self, from: modelsResponse.data) else {
            return APIProbe(
                platform: hint ?? .openAICompatible,
                phase: .runningUnverified,
                modelIDs: [],
                defaultModelID: nil,
                diagnostic: "服务响应了 /v1/models，但返回结构无法确认。",
                engineMemoryBytes: nil
            )
        }
        let ownerNames = envelope.data.compactMap(\.ownedBy).map { $0.lowercased() }
        let platform: LocalModelPlatform
        if ownerNames.contains(where: { $0.contains("omlx") }) {
            platform = .omlx
        } else {
            platform = hint ?? .openAICompatible
        }

        var defaultModelID: String?
        var engineMemoryBytes: Int64?
        if let healthURL = URL(string: "http://127.0.0.1:\(port)/health"),
           let health = await request(healthURL, timeout: 1.2, maximumBytes: 32 * 1_024),
           (200...299).contains(health.statusCode),
           let decoded = try? JSONDecoder().decode(OpenAIHealthEnvelope.self, from: health.data) {
            defaultModelID = decoded.defaultModel
            engineMemoryBytes = decoded.enginePool?.currentModelMemory
        }

        let modelIDs = envelope.data.map(\.id)
        return APIProbe(
            platform: platform,
            phase: modelIDs.isEmpty ? .runningUnverified : .runningHealthy,
            modelIDs: modelIDs,
            defaultModelID: defaultModelID,
            diagnostic: modelIDs.isEmpty
                ? "模型 API 可读，但当前没有列出可用模型。"
                : "模型 API 已确认，共列出 \(modelIDs.count) 个短 ID。",
            engineMemoryBytes: engineMemoryBytes
        )
    }

    private static func probeOllama(port: Int) async -> APIProbe? {
        guard let tagsURL = URL(string: "http://127.0.0.1:\(port)/api/tags"),
              let tags = await request(tagsURL, timeout: 1.5, maximumBytes: 512 * 1_024),
              (200...299).contains(tags.statusCode),
              (try? JSONDecoder().decode(OllamaTagsEnvelope.self, from: tags.data)) != nil else {
            return nil
        }
        var runningModels: [String] = []
        if let processURL = URL(string: "http://127.0.0.1:\(port)/api/ps"),
           let processResponse = await request(processURL, timeout: 1.5, maximumBytes: 512 * 1_024),
           (200...299).contains(processResponse.statusCode),
           let processEnvelope = try? JSONDecoder().decode(OllamaProcessEnvelope.self, from: processResponse.data) {
            runningModels = processEnvelope.models.map { $0.name ?? $0.model ?? "" }
        }
        return APIProbe(
            platform: .ollama,
            phase: runningModels.isEmpty ? .runningUnverified : .runningHealthy,
            modelIDs: runningModels,
            defaultModelID: runningModels.first,
            diagnostic: runningModels.isEmpty
                ? "Ollama 服务正在运行，但 /api/ps 没有正在加载的模型。"
                : "Ollama 已确认 \(runningModels.count) 个正在运行的模型。",
            engineMemoryBytes: nil
        )
    }

    private static func request(
        _ url: URL,
        timeout: TimeInterval,
        maximumBytes: Int
    ) async -> HTTPResult? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        let redirectDelegate = LocalModelRuntimeNoRedirectDelegate()
        let session = URLSession(
            configuration: configuration,
            delegate: redirectDelegate,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  data.count <= maximumBytes else { return nil }
            return HTTPResult(statusCode: response.statusCode, data: data)
        } catch {
            return nil
        }
    }

    private static func exposure(for listeners: [LocalModelListener]) -> LocalModelExposure {
        guard !listeners.isEmpty else { return .unknown }
        if listeners.contains(where: { $0.isWildcard || !$0.isLoopback }) {
            return .localNetwork
        }
        return listeners.allSatisfy(\.isLoopback) ? .localOnly : .unknown
    }

    private static func phaseRank(_ phase: LocalModelRuntimePhase) -> Int {
        switch phase {
        case .runningHealthy: return 0
        case .runningUnverified: return 1
        case .failed: return 2
        case .discovering: return 3
        case .unknown: return 4
        case .stopped: return 5
        }
    }

    private static func sanitizedProcessLabel(_ rawValue: String) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(value.prefix(128)).unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
    }

    private static func localIPv4Addresses() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var addresses = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            let item = current.pointee
            defer { cursor = item.ifa_next }
            guard let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET),
                  (item.ifa_flags & UInt32(IFF_UP)) != 0,
                  (item.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            let name = String(cString: item.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            guard getnameinfo(
                address,
                length,
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }
            addresses.insert(String(cString: hostname))
        }
        return addresses.sorted()
    }

    private static func runSystemCommand(executable: String, arguments: [String]) -> SystemCommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard data.count <= 4 * 1_024 * 1_024 else {
                return SystemCommandResult(exitCode: -1, output: "")
            }
            return SystemCommandResult(
                exitCode: process.terminationStatus,
                output: String(decoding: data, as: UTF8.self)
            )
        } catch {
            return SystemCommandResult(exitCode: -1, output: "")
        }
    }
}

enum LocalModelRuntimeNetworkPolicy {
    static func redirectedRequest(_ proposedRequest: URLRequest) -> URLRequest? {
        // Discovery is deliberately restricted to the original loopback URL.
        // A local service must not be able to redirect this read-only probe to
        // a LAN or public endpoint.
        nil
    }
}

private final class LocalModelRuntimeNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(LocalModelRuntimeNetworkPolicy.redirectedRequest(request))
    }
}

private struct SystemCommandResult {
    let exitCode: Int32
    let output: String
}

private struct HTTPResult {
    let statusCode: Int
    let data: Data
}

private struct OpenAIModelsEnvelope: Decodable {
    struct Model: Decodable {
        let id: String
        let ownedBy: String?

        enum CodingKeys: String, CodingKey {
            case id
            case ownedBy = "owned_by"
        }
    }

    let data: [Model]
}

private struct OpenAIHealthEnvelope: Decodable {
    struct EnginePool: Decodable {
        let currentModelMemory: Int64?

        enum CodingKeys: String, CodingKey {
            case currentModelMemory = "current_model_memory"
        }
    }

    let defaultModel: String?
    let enginePool: EnginePool?

    enum CodingKeys: String, CodingKey {
        case defaultModel = "default_model"
        case enginePool = "engine_pool"
    }
}

private struct OllamaTagsEnvelope: Decodable {
    let models: [OllamaModel]
}

private struct OllamaProcessEnvelope: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String?
    let model: String?
}
