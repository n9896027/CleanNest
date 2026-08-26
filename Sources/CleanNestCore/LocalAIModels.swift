import Foundation

public enum LocalAIError: LocalizedError, Sendable {
    case invalidEndpoint(String)
    case serviceUnavailable(String)
    case modelUnavailable(String)
    case invalidResponse(String)
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let detail): return "本机 AI 地址无效：\(detail)"
        case .serviceUnavailable(let detail): return "本机 AI 服务不可用：\(detail)"
        case .modelUnavailable(let detail): return "本机模型不可用：\(detail)"
        case .invalidResponse(let detail): return "本机模型返回了无效结果：\(detail)"
        case .requestFailed(let detail): return "本机 AI 分析未完成：\(detail)"
        }
    }
}

public struct LocalAIEndpoint: Equatable, Sendable {
    public let baseURL: URL
    public let healthURL: URL
    public let modelsURL: URL
    public let chatCompletionsURL: URL
    public let port: Int

    public init(rawValue: String) throws {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "http",
              components.host == "127.0.0.1",
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil else {
            throw LocalAIError.invalidEndpoint("只允许 http://127.0.0.1 上的回环服务")
        }

        guard let resolvedPort = components.port, (1...65_535).contains(resolvedPort) else {
            throw LocalAIError.invalidEndpoint("必须填写 1 到 65535 之间的端口")
        }

        let path = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard path.isEmpty || path == "v1" else {
            throw LocalAIError.invalidEndpoint("地址路径只能是 /v1")
        }

        components.path = "/v1"
        components.percentEncodedQuery = nil
        guard let baseURL = components.url else {
            throw LocalAIError.invalidEndpoint("无法解析地址")
        }

        var healthComponents = components
        healthComponents.path = "/health"
        var modelsComponents = components
        modelsComponents.path = "/v1/models"
        var chatComponents = components
        chatComponents.path = "/v1/chat/completions"
        guard let healthURL = healthComponents.url,
              let modelsURL = modelsComponents.url,
              let chatURL = chatComponents.url else {
            throw LocalAIError.invalidEndpoint("无法构造服务路径")
        }

        self.baseURL = baseURL
        self.healthURL = healthURL
        self.modelsURL = modelsURL
        self.chatCompletionsURL = chatURL
        self.port = resolvedPort
    }
}

public struct LocalAIProbeResult: Equatable, Sendable {
    public let modelIDs: [String]
    public let defaultModelID: String?

    public init(modelIDs: [String], defaultModelID: String? = nil) {
        var seen = Set<String>()
        self.modelIDs = modelIDs.compactMap { rawValue in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !(value as NSString).isAbsolutePath,
                  !value.lowercased().hasPrefix("file://") else { return nil }
            let key = value.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return value
        }
        let normalizedDefault = defaultModelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedDefault,
           !normalizedDefault.isEmpty,
           !(normalizedDefault as NSString).isAbsolutePath,
           !normalizedDefault.lowercased().hasPrefix("file://") {
            self.defaultModelID = normalizedDefault
        } else {
            self.defaultModelID = nil
        }
    }

    public func listedModelID(matching rawModelID: String) -> String? {
        let modelID = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return nil }
        return modelIDs.first { $0.caseInsensitiveCompare(modelID) == .orderedSame }
    }

    /// Resolves the exact ID that must be sent back to the OpenAI-compatible API.
    /// A user-selected service ID is fail-closed; an invalid explicit selection
    /// never silently falls back to another model.
    public func resolvedModelID(
        preferredModelID: String?,
        selectedLocalModel: LocalModelDescriptor?
    ) -> String? {
        let preferred = preferredModelID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !preferred.isEmpty {
            return listedModelID(matching: preferred)
        }

        if let selectedLocalModel,
           let matched = modelIDs.first(where: selectedLocalModel.matches(serviceModelID:)) {
            return matched
        }

        if let defaultModelID,
           let matched = listedModelID(matching: defaultModelID) {
            return matched
        }

        return modelIDs.count == 1 ? modelIDs[0] : nil
    }
}

public struct LocalAIBenchmarkResult: Equatable, Sendable {
    public let modelID: String
    public let firstTokenMilliseconds: Double
    public let totalMilliseconds: Double
    public let outputTokens: Int?
    public let outputCharacters: Int

    public init(
        modelID: String,
        firstTokenMilliseconds: Double,
        totalMilliseconds: Double,
        outputTokens: Int?,
        outputCharacters: Int
    ) {
        self.modelID = modelID
        self.firstTokenMilliseconds = max(0, firstTokenMilliseconds)
        self.totalMilliseconds = max(0, totalMilliseconds)
        self.outputTokens = outputTokens.map { max(0, $0) }
        self.outputCharacters = max(0, outputCharacters)
    }

    public var tokensPerSecond: Double? {
        guard let outputTokens, outputTokens > 0, totalMilliseconds > 0 else { return nil }
        return Double(outputTokens) / (totalMilliseconds / 1_000)
    }
}

public enum LocalAIHealthStatus {
    public static func isReady(_ rawValue: String) -> Bool {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ok", "healthy": return true
        default: return false
        }
    }
}

public enum CleanupAIVerdict: String, Codable, CaseIterable, Sendable {
    case reclaimable
    case review
    case keep
}

public enum CleanupAIRisk: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public struct CleanupAIAdvice: Identifiable, Equatable, Sendable {
    public var id: String { candidateID }
    public let candidateID: String
    public let verdict: CleanupAIVerdict
    public let risk: CleanupAIRisk
    public let priority: Int
    public let reason: String

    public init(
        candidateID: String,
        verdict: CleanupAIVerdict,
        risk: CleanupAIRisk,
        priority: Int,
        reason: String
    ) {
        self.candidateID = candidateID
        self.verdict = verdict
        self.risk = risk
        self.priority = priority
        self.reason = reason
    }
}

public struct CleanupAIAnalysis: Equatable, Sendable {
    public let modelID: String
    public let summary: String
    public let advice: [CleanupAIAdvice]
    public let cautions: [String]
    public let requestedCount: Int
    public let generatedAt: Date

    public init(
        modelID: String,
        summary: String,
        advice: [CleanupAIAdvice],
        cautions: [String],
        requestedCount: Int,
        generatedAt: Date = Date()
    ) {
        self.modelID = modelID
        self.summary = summary
        self.advice = advice
        self.cautions = cautions
        self.requestedCount = requestedCount
        self.generatedAt = generatedAt
    }
}

public struct CleanupAIRequestSnapshot: Equatable, Sendable {
    public let payloadJSON: String
    public let tokenToCandidateID: [String: String]
    public let requestedCount: Int

    public init(payloadJSON: String, tokenToCandidateID: [String: String], requestedCount: Int) {
        self.payloadJSON = payloadJSON
        self.tokenToCandidateID = tokenToCandidateID
        self.requestedCount = requestedCount
    }
}

public enum CleanupAIRequestBuilder {
    public static let maximumCandidates = 16

    public static func makeSnapshot(
        candidates: [CleanupCandidate],
        diskTotalBytes: Int64,
        diskFreeBytes: Int64,
        homeDirectory: URL,
        now: Date = Date(),
        limit: Int = maximumCandidates
    ) throws -> CleanupAIRequestSnapshot {
        let boundedLimit = min(max(limit, 1), maximumCandidates)
        let selected = candidates
            .sorted {
                if $0.allocatedBytes == $1.allocatedBytes { return $0.name < $1.name }
                return $0.allocatedBytes > $1.allocatedBytes
            }
            .prefix(boundedLimit)

        guard !selected.isEmpty else {
            throw LocalAIError.requestFailed("没有可分析的扫描项目")
        }

        var tokenMap: [String: String] = [:]
        var encodedCandidates: [[String: Any]] = []
        let homePath = homeDirectory.standardizedFileURL.path

        for (index, candidate) in selected.enumerated() {
            let token = String(format: "c%04d", index + 1)
            tokenMap[token] = candidate.id

            let path = candidate.url.standardizedFileURL.path
            let pathHint: String
            if path == homePath {
                pathHint = "~"
            } else if path.hasPrefix(homePath + "/") {
                pathHint = "~" + String(path.dropFirst(homePath.count))
            } else {
                pathHint = candidate.url.lastPathComponent
            }

            let ageDays: Any
            if let modifiedAt = candidate.modifiedAt {
                ageDays = max(0, Int(now.timeIntervalSince(modifiedAt) / 86_400))
            } else {
                ageDays = NSNull()
            }

            encodedCandidates.append([
                "token": token,
                "name": sanitize(candidate.name, maximumLength: 100),
                "path_hint": sanitize(pathHint, maximumLength: 240),
                "kind": stableKind(candidate.kind),
                "allocated_bytes": max(0, candidate.allocatedBytes),
                "age_days": ageDays,
                "scanner_recommended": candidate.isRecommended,
                "scanner_detail": sanitize(candidate.detail, maximumLength: 180)
            ])
        }

        let object: [String: Any] = [
            "schema_version": 1,
            "disk": [
                "total_bytes": max(0, diskTotalBytes),
                "free_bytes": max(0, diskFreeBytes)
            ],
            "candidates": encodedCandidates
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let payload = String(data: data, encoding: .utf8) else {
            throw LocalAIError.requestFailed("无法编码扫描元数据")
        }
        return CleanupAIRequestSnapshot(
            payloadJSON: payload,
            tokenToCandidateID: tokenMap,
            requestedCount: encodedCandidates.count
        )
    }

    private static func sanitize(_ value: String, maximumLength: Int) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maximumLength))
    }

    private static func stableKind(_ kind: CleanupKind) -> String {
        switch kind {
        case .developer: return "developer_cache"
        case .packageManager: return "package_manager_cache"
        case .logs: return "old_logs"
        case .installer: return "installer"
        case .archive: return "download_archive"
        case .screenshot: return "screenshot"
        case .image: return "image_file"
        case .video: return "video_file"
        case .audio: return "audio_file"
        case .duplicate: return "duplicate_file"
        case .appCache: return "application_cache"
        case .leftover: return "application_leftover"
        }
    }
}

public enum CleanupAIResponseValidator {
    private static let rootKeys: Set<String> = ["schema_version", "summary", "items", "cautions"]
    private static let itemKeys: Set<String> = ["token", "verdict", "risk", "priority", "reason"]

    public static func validate(
        content: String,
        snapshot: CleanupAIRequestSnapshot,
        modelID: String,
        now: Date = Date()
    ) throws -> CleanupAIAnalysis {
        guard let data = content.data(using: .utf8), data.count <= 96 * 1_024 else {
            throw LocalAIError.invalidResponse("响应过大或不是 UTF-8")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else {
            throw LocalAIError.invalidResponse("必须只返回一个 JSON 对象")
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LocalAIError.invalidResponse("JSON 无法解析")
        }
        guard let root = raw as? [String: Any], Set(root.keys) == rootKeys else {
            throw LocalAIError.invalidResponse("顶层字段缺失或包含未允许字段")
        }
        guard integer(root["schema_version"]) == 1 else {
            throw LocalAIError.invalidResponse("schema_version 不受支持")
        }
        let summary = try boundedString(root["summary"], name: "summary", range: 1...280)
        guard let rawItems = root["items"] as? [Any], rawItems.count == snapshot.requestedCount else {
            throw LocalAIError.invalidResponse("项目数量与本次请求不一致")
        }
        guard let rawCautions = root["cautions"] as? [Any], rawCautions.count <= 5 else {
            throw LocalAIError.invalidResponse("cautions 格式不正确")
        }

        var seenTokens = Set<String>()
        var advice: [CleanupAIAdvice] = []
        for rawItem in rawItems {
            guard let item = rawItem as? [String: Any], Set(item.keys) == itemKeys else {
                throw LocalAIError.invalidResponse("项目字段缺失或包含未允许字段")
            }
            let token = try boundedString(item["token"], name: "token", range: 1...16)
            guard seenTokens.insert(token).inserted else {
                throw LocalAIError.invalidResponse("出现重复项目 token")
            }
            guard let candidateID = snapshot.tokenToCandidateID[token] else {
                throw LocalAIError.invalidResponse("模型返回了本次扫描之外的项目")
            }
            guard let verdictText = item["verdict"] as? String,
                  let verdict = CleanupAIVerdict(rawValue: verdictText),
                  let riskText = item["risk"] as? String,
                  let risk = CleanupAIRisk(rawValue: riskText),
                  let priority = integer(item["priority"]),
                  (1...3).contains(priority) else {
                throw LocalAIError.invalidResponse("项目枚举或优先级无效")
            }
            let reason = try boundedString(item["reason"], name: "reason", range: 1...280)
            advice.append(
                CleanupAIAdvice(
                    candidateID: candidateID,
                    verdict: verdict,
                    risk: risk,
                    priority: priority,
                    reason: reason
                )
            )
        }

        guard seenTokens == Set(snapshot.tokenToCandidateID.keys) else {
            throw LocalAIError.invalidResponse("模型没有覆盖本次请求的全部项目")
        }

        let cautions = try rawCautions.map {
            try boundedString($0, name: "caution", range: 1...220)
        }
        return CleanupAIAnalysis(
            modelID: modelID,
            summary: summary,
            advice: advice.sorted {
                if $0.priority == $1.priority { return $0.candidateID < $1.candidateID }
                return $0.priority < $1.priority
            },
            cautions: cautions,
            requestedCount: snapshot.requestedCount,
            generatedAt: now
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type != "c", type != "B" else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func boundedString(_ value: Any?, name: String, range: ClosedRange<Int>) throws -> String {
        guard let string = value as? String,
              range.contains(string.count),
              !containsUnsafeControlCharacter(string) else {
            throw LocalAIError.invalidResponse("\(name) 文本无效")
        }
        return string
    }

    private static func containsUnsafeControlCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar)
                && scalar != "\n"
                && scalar != "\r"
                && scalar != "\t"
        }
    }
}

public enum DiskAIContentCategory: String, Codable, CaseIterable, Sendable {
    case cache
    case logs
    case developerArtifacts = "developer_artifacts"
    case packageManagerData = "package_manager_data"
    case appSandboxData = "app_sandbox_data"
    case appSupportData = "app_support_data"
    case cloudDocuments = "cloud_documents"
    case userContent = "user_content"
    case systemData = "system_data"
    case installerOrArchive = "installer_or_archive"
    case unknown
}

public enum DiskAIConfidence: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum DiskAIVerdict: String, Codable, CaseIterable, Sendable {
    case likelyReclaimable = "likely_reclaimable"
    case review
    case keep
}

public enum DiskAIRisk: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high
}

public enum DiskAISuggestion: String, Codable, CaseIterable, Sendable {
    case inspectFurther = "inspect_further"
    case reviewForCleanup = "review_for_cleanup"
    case cleanInOwnerApp = "clean_in_owner_app"
    case keep
}

public enum DiskAICleanupBoundary: String, Codable, Sendable {
    case protected
    case inspectOnly = "inspect_only"
    case reviewable
}

public struct DiskAIInputPolicy: Equatable, Sendable {
    public let category: DiskAIContentCategory
    public let boundary: DiskAICleanupBoundary
    public let minimumRisk: DiskAIRisk

    public init(
        category: DiskAIContentCategory,
        boundary: DiskAICleanupBoundary,
        minimumRisk: DiskAIRisk
    ) {
        self.category = category
        self.boundary = boundary
        self.minimumRisk = minimumRisk
    }
}

public struct DiskAIChildContext: Equatable, Sendable {
    public let entries: [DiskEntry]
    public let totalEntryCount: Int
    public let totalBytes: Int64

    public init(entries: [DiskEntry], totalEntryCount: Int, totalBytes: Int64) {
        self.entries = entries
        self.totalEntryCount = totalEntryCount
        self.totalBytes = totalBytes
    }
}

public struct DiskAIAdvice: Identifiable, Equatable, Sendable {
    public var id: String { entryID }
    public let entryID: String
    public let category: DiskAIContentCategory
    public let confidence: DiskAIConfidence
    public let verdict: DiskAIVerdict
    public let risk: DiskAIRisk
    public let priority: Int
    public let suggestion: DiskAISuggestion
    public let explanation: String

    public init(
        entryID: String,
        category: DiskAIContentCategory,
        confidence: DiskAIConfidence,
        verdict: DiskAIVerdict,
        risk: DiskAIRisk,
        priority: Int,
        suggestion: DiskAISuggestion,
        explanation: String
    ) {
        self.entryID = entryID
        self.category = category
        self.confidence = confidence
        self.verdict = verdict
        self.risk = risk
        self.priority = priority
        self.suggestion = suggestion
        self.explanation = explanation
    }
}

public struct DiskAIAnalysis: Equatable, Sendable {
    public let modelID: String
    public let summary: String
    public let advice: [DiskAIAdvice]
    public let cautions: [String]
    public let requestedCount: Int
    public let coveredBytes: Int64
    public let deepSampledCount: Int
    public let generatedAt: Date

    public init(
        modelID: String,
        summary: String,
        advice: [DiskAIAdvice],
        cautions: [String],
        requestedCount: Int,
        coveredBytes: Int64,
        deepSampledCount: Int,
        generatedAt: Date = Date()
    ) {
        self.modelID = modelID
        self.summary = summary
        self.advice = advice
        self.cautions = cautions
        self.requestedCount = requestedCount
        self.coveredBytes = coveredBytes
        self.deepSampledCount = deepSampledCount
        self.generatedAt = generatedAt
    }
}

public struct DiskAIRequestSnapshot: Equatable, Sendable {
    public let payloadJSON: String
    public let tokenToEntryID: [String: String]
    public let tokenPolicies: [String: DiskAIInputPolicy]
    public let sourceRootID: String
    public let requestedCount: Int
    public let requestedBytes: Int64
    public let deepSampledCount: Int

    public init(
        payloadJSON: String,
        tokenToEntryID: [String: String],
        tokenPolicies: [String: DiskAIInputPolicy],
        sourceRootID: String,
        requestedCount: Int,
        requestedBytes: Int64,
        deepSampledCount: Int
    ) {
        self.payloadJSON = payloadJSON
        self.tokenToEntryID = tokenToEntryID
        self.tokenPolicies = tokenPolicies
        self.sourceRootID = sourceRootID
        self.requestedCount = requestedCount
        self.requestedBytes = requestedBytes
        self.deepSampledCount = deepSampledCount
    }
}

public enum DiskAISafetyPolicy {
    public static func policy(for url: URL, homeDirectory: URL) -> DiskAIInputPolicy {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = homeDirectory.standardizedFileURL.resolvingSymlinksInPath().path
        guard path == homePath || path.hasPrefix(homePath + "/") else {
            return DiskAIInputPolicy(category: .unknown, boundary: .inspectOnly, minimumRisk: .high)
        }

        let relative = path == homePath ? "" : String(path.dropFirst(homePath.count + 1))
        let components = relative.split(separator: "/").map(String.init)

        if hasPrefix(components, ["Library", "Mobile Documents"])
            || hasPrefix(components, ["Library", "CloudStorage"]) {
            return DiskAIInputPolicy(category: .cloudDocuments, boundary: .protected, minimumRisk: .high)
        }
        if hasPrefix(components, ["Library", "Containers"])
            || hasPrefix(components, ["Library", "Group Containers"]) {
            return DiskAIInputPolicy(category: .appSandboxData, boundary: .protected, minimumRisk: .high)
        }
        if hasPrefix(components, ["Library", "Application Support"]) {
            return DiskAIInputPolicy(category: .appSupportData, boundary: .inspectOnly, minimumRisk: .high)
        }
        if hasPrefix(components, ["Library", "Caches"]) {
            let isRoot = components.count == 2
            return DiskAIInputPolicy(
                category: .cache,
                boundary: isRoot ? .inspectOnly : .reviewable,
                minimumRisk: isRoot ? .medium : .low
            )
        }
        if hasPrefix(components, ["Library", "pnpm"]) {
            if components.count >= 3, components[2] == ".tools" || components[2] == "global" {
                return DiskAIInputPolicy(category: .packageManagerData, boundary: .protected, minimumRisk: .high)
            }
            if components.count >= 3, components[2] == "store" {
                return DiskAIInputPolicy(category: .packageManagerData, boundary: .reviewable, minimumRisk: .medium)
            }
            return DiskAIInputPolicy(category: .packageManagerData, boundary: .inspectOnly, minimumRisk: .medium)
        }
        if hasPrefix(components, ["Library", "Logs"]) {
            return DiskAIInputPolicy(
                category: .logs,
                boundary: components.count == 2 ? .inspectOnly : .reviewable,
                minimumRisk: .medium
            )
        }
        if hasPrefix(components, ["Library", "Developer", "Xcode", "DerivedData"])
            || hasPrefix(components, [".npm", "_cacache"])
            || hasPrefix(components, [".cache", "pip"]) {
            return DiskAIInputPolicy(category: .developerArtifacts, boundary: .reviewable, minimumRisk: .low)
        }
        if hasPrefix(components, ["Library", "Fonts"])
            || hasPrefix(components, ["Library", "Rime"]) {
            return DiskAIInputPolicy(category: .userContent, boundary: .protected, minimumRisk: .high)
        }
        if let generated = generatedProjectPolicy(for: url) {
            return generated
        }
        if let first = components.first,
           ["Desktop", "Documents", "Movies", "Music", "Pictures"].contains(first) {
            return DiskAIInputPolicy(category: .userContent, boundary: .protected, minimumRisk: .high)
        }
        if components.first == "Downloads" {
            return DiskAIInputPolicy(category: .userContent, boundary: .inspectOnly, minimumRisk: .medium)
        }
        if components.first == "Library" {
            return DiskAIInputPolicy(category: .systemData, boundary: .inspectOnly, minimumRisk: .high)
        }
        return DiskAIInputPolicy(category: .unknown, boundary: .inspectOnly, minimumRisk: .high)
    }

    private static func hasPrefix(_ values: [String], _ prefix: [String]) -> Bool {
        values.count >= prefix.count && zip(values, prefix).allSatisfy(==)
    }

    /// Recognizes generated directories only when adjacent project manifests
    /// provide deterministic provenance. A directory name alone is not enough.
    private static func generatedProjectPolicy(for url: URL) -> DiskAIInputPolicy? {
        let name = url.lastPathComponent.lowercased()
        if name == ".git" {
            return DiskAIInputPolicy(category: .userContent, boundary: .protected, minimumRisk: .high)
        }
        let parent = url.deletingLastPathComponent()
        let fileManager = FileManager.default
        func hasMarker(_ names: [String]) -> Bool {
            names.contains { fileManager.fileExists(atPath: parent.appendingPathComponent($0).path) }
        }

        if name == ".build", hasMarker(["Package.swift"]) {
            return DiskAIInputPolicy(category: .developerArtifacts, boundary: .reviewable, minimumRisk: .low)
        }
        if name == "node_modules", hasMarker(["package.json"]) {
            return DiskAIInputPolicy(category: .packageManagerData, boundary: .reviewable, minimumRisk: .medium)
        }
        if name == "target", hasMarker(["Cargo.toml"]) {
            return DiskAIInputPolicy(category: .developerArtifacts, boundary: .reviewable, minimumRisk: .low)
        }
        if ["build", "dist", ".next", "coverage"].contains(name),
           hasMarker(["Package.swift", "package.json", "Cargo.toml", "project.yml"]) {
            return DiskAIInputPolicy(category: .developerArtifacts, boundary: .reviewable, minimumRisk: .medium)
        }
        return nil
    }
}

public enum DiskAIRequestBuilder {
    public static let maximumEntries = 16
    public static let maximumDeepEntries = 4
    public static let maximumChildSamples = 8

    public static func makeSnapshot(
        report: DiskReport,
        childContexts: [String: DiskAIChildContext] = [:],
        homeDirectory: URL,
        limit: Int = maximumEntries
    ) throws -> DiskAIRequestSnapshot {
        let root = report.root.standardizedFileURL
        let boundedLimit = min(max(limit, 1), maximumEntries)
        let selected = report.entries
            .filter { isDirectChild($0.url, of: root) && $0.bytes >= 0 }
            .sorted {
                if $0.bytes == $1.bytes { return $0.name < $1.name }
                return $0.bytes > $1.bytes
            }
            .prefix(boundedLimit)

        guard !selected.isEmpty else {
            throw LocalAIError.requestFailed("当前层级没有可供 AI 解读的项目")
        }

        var tokenToEntryID: [String: String] = [:]
        var tokenPolicies: [String: DiskAIInputPolicy] = [:]
        var encodedItems: [[String: Any]] = []
        var requestedBytes: Int64 = 0
        var deepSampledCount = 0

        for (index, entry) in selected.enumerated() {
            let token = String(format: "d%04d", index + 1)
            let policy = DiskAISafetyPolicy.policy(for: entry.url, homeDirectory: homeDirectory)
            tokenToEntryID[token] = entry.id
            tokenPolicies[token] = policy
            requestedBytes += max(0, entry.bytes)

            let context = childContexts[entry.id]
            let safeChildren = (context?.entries ?? [])
                .filter { isDirectChild($0.url, of: entry.url) && $0.bytes >= 0 }
                .sorted {
                    if $0.bytes == $1.bytes { return $0.name < $1.name }
                    return $0.bytes > $1.bytes
                }
                .prefix(maximumChildSamples)
            if !safeChildren.isEmpty { deepSampledCount += 1 }

            let children: [[String: Any]] = safeChildren.map { child in
                [
                    "name": sanitize(child.name, maximumLength: 120),
                    "entry_type": child.isDirectory ? "directory" : "file",
                    "allocated_bytes": max(0, child.bytes)
                ]
            }
            let share = report.totalBytes > 0
                ? min(10_000, max(0, Int(Double(entry.bytes) / Double(report.totalBytes) * 10_000)))
                : 0
            let directChildCount: Any
            if let context {
                directChildCount = context.totalEntryCount
            } else {
                directChildCount = NSNull()
            }

            encodedItems.append([
                "token": token,
                "name": sanitize(entry.name, maximumLength: 120),
                "relative_hint": sanitize(relativeHint(for: entry.url, root: root), maximumLength: 220),
                "entry_type": entry.isDirectory ? "directory" : "file",
                "allocated_bytes": max(0, entry.bytes),
                "share_basis_points": share,
                "local_role": policy.category.rawValue,
                "cleanup_boundary": policy.boundary.rawValue,
                "minimum_risk": policy.minimumRisk.rawValue,
                "direct_child_count": directChildCount,
                "sampled_children": children
            ])
        }

        let object: [String: Any] = [
            "schema_version": 1,
            "scope": [
                "root_hint": sanitize(redactedPath(for: root, homeDirectory: homeDirectory), maximumLength: 220),
                "total_bytes": max(0, report.totalBytes),
                "current_level_entries": report.entries.count,
                "observation": "当前层级及最多四个大目录的直接子项元数据；未读取文件内容，结果可能不完整"
            ],
            "items": encodedItems
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let payload = String(data: data, encoding: .utf8) else {
            throw LocalAIError.requestFailed("无法编码磁盘元数据")
        }
        return DiskAIRequestSnapshot(
            payloadJSON: payload,
            tokenToEntryID: tokenToEntryID,
            tokenPolicies: tokenPolicies,
            sourceRootID: root.path,
            requestedCount: encodedItems.count,
            requestedBytes: requestedBytes,
            deepSampledCount: deepSampledCount
        )
    }

    private static func isDirectChild(_ child: URL, of parent: URL) -> Bool {
        child.standardizedFileURL.deletingLastPathComponent().path == parent.standardizedFileURL.path
    }

    private static func relativeHint(for url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func redactedPath(for url: URL, homeDirectory: URL) -> String {
        let path = url.standardizedFileURL.path
        let homePath = homeDirectory.standardizedFileURL.path
        if path == homePath { return "~" }
        if path.hasPrefix(homePath + "/") { return "~" + String(path.dropFirst(homePath.count)) }
        return url.lastPathComponent.isEmpty ? "所选位置" : url.lastPathComponent
    }

    private static func sanitize(_ value: String, maximumLength: Int) -> String {
        let cleaned = value.unicodeScalars.map { scalar -> String in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(maximumLength))
    }
}

public enum DiskAIResponseValidator {
    private static let rootKeys: Set<String> = ["schema_version", "summary", "items", "cautions"]
    private static let itemKeys: Set<String> = [
        "token", "category", "confidence", "verdict", "risk", "priority", "suggestion", "explanation"
    ]

    public static func validate(
        content: String,
        snapshot: DiskAIRequestSnapshot,
        modelID: String,
        now: Date = Date()
    ) throws -> DiskAIAnalysis {
        guard let data = content.data(using: .utf8), data.count <= 128 * 1_024 else {
            throw LocalAIError.invalidResponse("磁盘 AI 响应过大或不是 UTF-8")
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else {
            throw LocalAIError.invalidResponse("磁盘 AI 必须只返回一个 JSON 对象")
        }

        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw LocalAIError.invalidResponse("磁盘 AI JSON 无法解析")
        }
        guard let root = raw as? [String: Any], Set(root.keys) == rootKeys else {
            throw LocalAIError.invalidResponse("磁盘 AI 顶层字段缺失或包含未允许字段")
        }
        guard integer(root["schema_version"]) == 1 else {
            throw LocalAIError.invalidResponse("磁盘 AI schema_version 不受支持")
        }
        _ = try boundedDescriptiveString(root["summary"], name: "summary", range: 1...360)
        guard let rawItems = root["items"] as? [Any], rawItems.count == snapshot.requestedCount else {
            throw LocalAIError.invalidResponse("磁盘 AI 项目数量与请求不一致")
        }
        guard let rawCautions = root["cautions"] as? [Any], rawCautions.count <= 5 else {
            throw LocalAIError.invalidResponse("磁盘 AI cautions 格式不正确")
        }

        var seenTokens = Set<String>()
        var safetyAdjustedTokens = Set<String>()
        var advice: [DiskAIAdvice] = []
        for rawItem in rawItems {
            guard let item = rawItem as? [String: Any], Set(item.keys) == itemKeys else {
                throw LocalAIError.invalidResponse("磁盘 AI 项目字段缺失或包含未允许字段")
            }
            let token = try boundedSafeString(item["token"], name: "token", range: 1...16)
            guard seenTokens.insert(token).inserted else {
                throw LocalAIError.invalidResponse("磁盘 AI 出现重复 token")
            }
            guard let entryID = snapshot.tokenToEntryID[token], let policy = snapshot.tokenPolicies[token] else {
                throw LocalAIError.invalidResponse("磁盘 AI 返回了当前层级之外的项目")
            }
            guard let categoryText = item["category"] as? String,
                  let category = DiskAIContentCategory(rawValue: categoryText),
                  let confidenceText = item["confidence"] as? String,
                  let confidence = DiskAIConfidence(rawValue: confidenceText),
                  let verdictText = item["verdict"] as? String,
                  let verdict = DiskAIVerdict(rawValue: verdictText),
                  let riskText = item["risk"] as? String,
                  let risk = DiskAIRisk(rawValue: riskText),
                  let suggestionText = item["suggestion"] as? String,
                  let suggestion = DiskAISuggestion(rawValue: suggestionText),
                  let priority = integer(item["priority"]),
                  (1...3).contains(priority) else {
                throw LocalAIError.invalidResponse("磁盘 AI 枚举或优先级无效")
            }
            let reconciled = reconcileSafety(
                verdict: verdict,
                risk: risk,
                suggestion: suggestion,
                policy: policy
            )
            if category != policy.category || reconciled.adjusted {
                safetyAdjustedTokens.insert(token)
            }
            try validateSafety(
                verdict: reconciled.verdict,
                risk: reconciled.risk,
                suggestion: reconciled.suggestion,
                policy: policy
            )
            _ = try boundedDescriptiveString(item["explanation"], name: "explanation", range: 1...360)
            advice.append(
                DiskAIAdvice(
                    entryID: entryID,
                    category: policy.category,
                    confidence: safetyAdjustedTokens.contains(token) ? .low : confidence,
                    verdict: reconciled.verdict,
                    risk: reconciled.risk,
                    priority: priority,
                    suggestion: reconciled.suggestion,
                    explanation: safePurposeDescription(for: policy.category)
                )
            )
        }

        guard seenTokens == Set(snapshot.tokenToEntryID.keys) else {
            throw LocalAIError.invalidResponse("磁盘 AI 没有覆盖全部 token")
        }
        _ = try rawCautions.map {
            try boundedDescriptiveString($0, name: "caution", range: 1...260)
        }
        let summary = "基于当前层级元数据，已完成 \(snapshot.requestedCount) 项用途与风险分类；其中 \(snapshot.deepSampledCount) 个大目录还使用了实际子项样本。"
        var cautions = ["结果只依据目录名称、层级、类型与体积等元数据，没有读取文件内容。"]
        if !safetyAdjustedTokens.isEmpty {
            cautions.append(
                "模型有 \(safetyAdjustedTokens.count) 项判断与本机安全规则不一致，已自动采用更保守的本机结论。"
            )
        }
        return DiskAIAnalysis(
            modelID: modelID,
            summary: summary,
            advice: advice.sorted {
                if $0.priority == $1.priority { return $0.entryID < $1.entryID }
                return $0.priority < $1.priority
            },
            cautions: cautions,
            requestedCount: snapshot.requestedCount,
            coveredBytes: snapshot.requestedBytes,
            deepSampledCount: snapshot.deepSampledCount,
            generatedAt: now
        )
    }

    private struct ReconciledSafety {
        let verdict: DiskAIVerdict
        let risk: DiskAIRisk
        let suggestion: DiskAISuggestion
        let adjusted: Bool
    }

    private static func reconcileSafety(
        verdict: DiskAIVerdict,
        risk: DiskAIRisk,
        suggestion: DiskAISuggestion,
        policy: DiskAIInputPolicy
    ) -> ReconciledSafety {
        var safeVerdict = verdict
        var safeRisk = higherRisk(risk, policy.minimumRisk)
        var safeSuggestion = suggestion

        switch policy.boundary {
        case .protected:
            safeVerdict = .keep
            safeRisk = .high
            safeSuggestion = suggestion == .cleanInOwnerApp ? .cleanInOwnerApp : .keep

        case .inspectOnly:
            if safeVerdict == .likelyReclaimable {
                safeVerdict = .review
            }
            if safeSuggestion == .reviewForCleanup {
                safeSuggestion = .inspectFurther
            }

        case .reviewable:
            if safeVerdict == .likelyReclaimable {
                let isValidLowRiskCandidate = policy.minimumRisk == .low
                    && risk == .low
                    && suggestion == .reviewForCleanup
                if !isValidLowRiskCandidate {
                    safeVerdict = .review
                    safeSuggestion = .inspectFurther
                }
            }
            if safeVerdict == .keep, safeSuggestion == .reviewForCleanup {
                safeSuggestion = .keep
            }
        }

        return ReconciledSafety(
            verdict: safeVerdict,
            risk: safeRisk,
            suggestion: safeSuggestion,
            adjusted: safeVerdict != verdict || safeRisk != risk || safeSuggestion != suggestion
        )
    }

    private static func validateSafety(
        verdict: DiskAIVerdict,
        risk: DiskAIRisk,
        suggestion: DiskAISuggestion,
        policy: DiskAIInputPolicy
    ) throws {
        guard riskRank(risk) >= riskRank(policy.minimumRisk) else {
            throw LocalAIError.invalidResponse("磁盘 AI 风险低于本机安全下限")
        }
        switch policy.boundary {
        case .protected:
            guard verdict == .keep,
                  risk == .high,
                  suggestion == .keep || suggestion == .cleanInOwnerApp else {
                throw LocalAIError.invalidResponse("受保护目录不能被建议清理")
            }
        case .inspectOnly:
            guard verdict != .likelyReclaimable,
                  suggestion != .reviewForCleanup else {
                throw LocalAIError.invalidResponse("当前目录只能继续检查，不能标记为可清理")
            }
        case .reviewable:
            if verdict == .likelyReclaimable {
                guard risk == .low, suggestion == .reviewForCleanup else {
                    throw LocalAIError.invalidResponse("低风险候选的风险或建议组合无效")
                }
            }
        }
        if verdict == .keep, suggestion == .reviewForCleanup {
            throw LocalAIError.invalidResponse("建议保留的项目不能同时建议清理")
        }
    }

    private static func safePurposeDescription(for category: DiskAIContentCategory) -> String {
        switch category {
        case .cache:
            return "通常是应用为了加快载入而生成的临时或可重建数据。"
        case .logs:
            return "通常是应用或系统记录的运行、诊断与故障排查信息。"
        case .developerArtifacts:
            return "通常是构建中间产物、下载依赖或其他开发工具生成的数据。"
        case .packageManagerData:
            return "通常是包管理器的依赖存储、工具运行时、全局包或下载数据。"
        case .appSandboxData:
            return "通常是应用隔离保存的数据库、配置、容器资源与用户资料。"
        case .appSupportData:
            return "通常是应用运行所需的配置、数据库、模型资源与用户资料。"
        case .cloudDocuments:
            return "通常是由云服务同步的用户文档，可能与其他设备保持一致。"
        case .userContent:
            return "通常是由用户创建、下载或保存的个人内容，具有不可替代性。"
        case .systemData:
            return "通常是系统与多个应用共同使用的数据，具体用途需要继续查看。"
        case .installerOrArchive:
            return "通常是安装介质、压缩归档或用于离线恢复的文件。"
        case .unknown:
            return "仅凭当前元数据无法可靠确定用途，需要继续查看内部构成。"
        }
    }

    private static func riskRank(_ risk: DiskAIRisk) -> Int {
        switch risk {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    private static func higherRisk(_ lhs: DiskAIRisk, _ rhs: DiskAIRisk) -> DiskAIRisk {
        riskRank(lhs) >= riskRank(rhs) ? lhs : rhs
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        let type = String(cString: number.objCType)
        guard type != "c", type != "B" else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return Int(double)
    }

    private static func boundedSafeString(
        _ value: Any?,
        name: String,
        range: ClosedRange<Int>
    ) throws -> String {
        guard let string = value as? String,
              range.contains(string.count),
              !string.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\r" && $0 != "\t"
              }),
              !containsOperationalText(string) else {
            throw LocalAIError.invalidResponse("磁盘 AI \(name) 文本无效")
        }
        return string
    }

    private static func boundedDescriptiveString(
        _ value: Any?,
        name: String,
        range: ClosedRange<Int>
    ) throws -> String {
        let string = try boundedSafeString(value, name: name, range: range)
        guard !containsCleanupActionText(string) else {
            throw LocalAIError.invalidResponse("磁盘 AI \(name) 只能描述用途，不能生成处理动作")
        }
        return string
    }

    private static func containsCleanupActionText(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let forbidden = [
            "删", "清理", "清空", "移除", "释放空间", "丢弃", "废纸篓", "卸载", "抹掉",
            "脚本", "命令", "终端", "delete", "remove", "clean up", "cleanup", "purge",
            "erase", "trash", "shell", "terminal", "script", "command"
        ]
        return forbidden.contains { lowered.contains($0) }
    }

    private static func containsOperationalText(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let forbidden = [
            "file://", "~/", "/users/", "/system/", "/library/", "`", "$(", ";", "&&",
            "rm -", "sudo ", "xargs ", "osascript "
        ]
        return forbidden.contains { lowered.contains($0) }
    }
}
