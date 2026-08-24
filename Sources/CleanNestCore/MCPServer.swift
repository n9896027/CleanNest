import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var numberValue: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }
}

private struct MCPRequest: Decodable {
    let jsonrpc: String
    let id: JSONValue?
    let method: String
    let params: JSONValue?
}

private struct MCPActivityRecord: Codable {
    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let outcome: String
    let affectedItems: Int
    let bytes: Int64
}

public actor ReadOnlyMCPServer {
    public static let modernProtocolVersion = "2026-07-28"
    public static let legacyProtocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26"]
    public static let maximumMessageBytes = 1_048_576

    private let metrics: MetricsStore
    private let metricsURL: URL
    private let evidenceURL: URL
    private let cleanupURL: URL
    private let activityURL: URL
    private let processInspector: ProcessMemoryInspector
    private let homeDirectory: URL
    private var negotiatedLegacyVersion: String?

    public init(
        metricsDatabaseURL: URL = CleanNestDataPaths.metricsDatabase(),
        evidenceURL: URL = CleanNestDataPaths.diskEvidenceSnapshot(),
        cleanupURL: URL = CleanNestDataPaths.cleanupPreviewSnapshot(),
        activityURL: URL = CleanNestDataPaths.activityLog(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        metrics = MetricsStore(databaseURL: metricsDatabaseURL, access: .readOnly)
        metricsURL = metricsDatabaseURL.standardizedFileURL
        self.evidenceURL = evidenceURL.standardizedFileURL
        self.cleanupURL = cleanupURL.standardizedFileURL
        self.activityURL = activityURL.standardizedFileURL
        processInspector = ProcessMemoryInspector()
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    /// Handles one newline-delimited JSON-RPC message. A nil result means the
    /// input was a notification and must not receive a response.
    public func response(to data: Data) async -> Data? {
        guard data.count <= Self.maximumMessageBytes else {
            return encode(error(id: .null, code: -32600, message: "Request exceeds 1 MiB limit"))
        }

        let request: MCPRequest
        do {
            request = try JSONDecoder().decode(MCPRequest.self, from: data)
        } catch {
            return encode(self.error(id: .null, code: -32700, message: "Parse error"))
        }
        guard request.jsonrpc == "2.0", !request.method.isEmpty else {
            return encode(error(id: request.id ?? .null, code: -32600, message: "Invalid Request"))
        }

        if request.method == "notifications/initialized" || request.method == "notifications/cancelled" {
            return nil
        }
        if request.id == nil {
            return nil
        }
        let id = request.id ?? .null

        switch request.method {
        case "server/discover":
            return encode(success(id: id, result: discoverResult(), modern: true))

        case "initialize":
            let requested = request.params?.objectValue?["protocolVersion"]?.stringValue
            let selected = Self.legacyProtocolVersions.contains(requested ?? "")
                ? requested!
                : Self.legacyProtocolVersions[0]
            negotiatedLegacyVersion = selected
            let result: JSONValue = .object([
                "protocolVersion": .string(selected),
                "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
                "serverInfo": .object(["name": .string("CleanNest"), "version": .string("0.5.3")]),
                "instructions": .string(Self.instructions)
            ])
            return encode(success(id: id, result: result, modern: false))

        case "ping":
            guard let modern = requestEra(request) else {
                return encode(notInitialized(id: id))
            }
            return encode(success(id: id, result: .object([:]), modern: modern))

        case "tools/list":
            guard let modern = requestEra(request) else {
                return encode(notInitialized(id: id))
            }
            var result: [String: JSONValue] = ["tools": .array(Self.tools)]
            if modern {
                result["resultType"] = .string("complete")
                result["ttlMs"] = .number(300_000)
                result["cacheScope"] = .string("public")
            }
            return encode(success(id: id, result: .object(result), modern: modern))

        case "tools/call":
            guard let modern = requestEra(request) else {
                return encode(notInitialized(id: id))
            }
            guard let params = request.params?.objectValue,
                  let name = params["name"]?.stringValue else {
                return encode(error(id: id, code: -32602, message: "tools/call requires a tool name"))
            }
            let arguments = params["arguments"]?.objectValue ?? [:]
            guard Self.toolNames.contains(name) else {
                return encode(error(id: id, code: -32602, message: "Unknown tool: \(name)"))
            }
            do {
                let output = try await call(name: name, arguments: arguments)
                return encode(success(id: id, result: toolResult(output, modern: modern), modern: modern))
            } catch {
                let safeMessage = Self.sanitize(error.localizedDescription, maximumLength: 500)
                return encode(
                    success(
                        id: id,
                        result: toolErrorResult(safeMessage, modern: modern),
                        modern: modern
                    )
                )
            }

        default:
            return encode(error(id: id, code: -32601, message: "Method not found"))
        }
    }

    private func requestEra(_ request: MCPRequest) -> Bool? {
        let version = request.params?.objectValue?["_meta"]?
            .objectValue?["io.modelcontextprotocol/protocolVersion"]?.stringValue
        if let version {
            return version == Self.modernProtocolVersion ? true : nil
        }
        return negotiatedLegacyVersion == nil ? nil : false
    }

    private func call(name: String, arguments: [String: JSONValue]) async throws -> JSONValue {
        switch name {
        case "cleannest.server_status":
            try rejectUnknown(arguments, allowed: [])
            return .object([
                "server": .string("CleanNest read-only MCP"),
                "version": .string("0.5.3"),
                "transport": .string("stdio"),
                "read_only": .bool(true),
                "metrics_available": .bool(FileManager.default.fileExists(atPath: metricsURL.path)),
                "disk_evidence_available": .bool(FileManager.default.fileExists(atPath: evidenceURL.path)),
                "cleanup_preview_available": .bool(FileManager.default.fileExists(atPath: cleanupURL.path)),
                "activity_available": .bool(FileManager.default.fileExists(atPath: activityURL.path))
            ])

        case "cleannest.latest_snapshot":
            try rejectUnknown(arguments, allowed: [])
            guard let sample = try await metrics.latest() else {
                throw MCPDataError.unavailable("CleanNest 尚未保存系统指标。")
            }
            return Self.metricObject(sample)

        case "cleannest.metric_history":
            try rejectUnknown(arguments, allowed: ["range", "limit"])
            let rawRange = arguments["range"]?.stringValue ?? MetricHistoryRange.day.rawValue
            guard let range = MetricHistoryRange(rawValue: rawRange) else {
                throw MCPDataError.invalidArgument("range 只能是 hour、day、week 或 month。")
            }
            let requestedLimit = try integer(arguments["limit"], default: range.maximumSamples, range: 1...2_000)
            let samples = try await metrics.samples(
                since: Date().addingTimeInterval(-range.duration),
                limit: requestedLimit
            )
            return .object([
                "range": .string(range.rawValue),
                "sample_count": .number(Double(samples.count)),
                "samples": .array(samples.map(Self.metricObject))
            ])

        case "cleannest.top_processes":
            try rejectUnknown(arguments, allowed: ["limit"])
            let limit = try integer(arguments["limit"], default: 10, range: 1...20)
            let inspector = processInspector
            let processes = await Task.detached(priority: .utility) {
                inspector.topProcesses(limit: limit)
            }.value
            return .object([
                "sampled_at": .string(Self.iso8601(Date())),
                "processes": .array(processes.map { process in
                    .object([
                        "pid": .number(Double(process.pid)),
                        "name": .string(Self.sanitize(process.name, maximumLength: 160)),
                        "application": process.applicationName.map { .string(Self.sanitize($0, maximumLength: 160)) } ?? .null,
                        "physical_footprint_bytes": .number(Double(process.physicalFootprintBytes)),
                        "resident_bytes": .number(Double(process.residentBytes)),
                        "purpose": .string(Self.sanitize(process.purpose, maximumLength: 600)),
                        "protected": .bool(!process.canTerminate)
                    ])
                })
            ])

        case "cleannest.disk_evidence":
            try rejectUnknown(arguments, allowed: ["limit"])
            let limit = try integer(arguments["limit"], default: 16, range: 1...32)
            guard let report = try DiskEvidencePersistence.load(from: evidenceURL) else {
                throw MCPDataError.unavailable("请先在 CleanNest 中完成一次磁盘分析。")
            }
            let trimmed = DiskEvidenceReport(
                schemaVersion: report.schemaVersion,
                generatedAt: report.generatedAt,
                rootHint: report.rootHint,
                entries: Array(report.entries.prefix(limit))
            )
            return try Self.encodedJSONValue(trimmed)

        case "cleannest.cleanup_preview":
            try rejectUnknown(arguments, allowed: ["limit"])
            let limit = try integer(arguments["limit"], default: 32, range: 1...64)
            guard let snapshot = try CleanupPreviewPersistence.load(from: cleanupURL) else {
                throw MCPDataError.unavailable("请先在 CleanNest 中完成一次清理候选扫描。")
            }
            let trimmed = CleanupPreviewSnapshot(
                schemaVersion: snapshot.schemaVersion,
                generatedAt: snapshot.generatedAt,
                items: Array(snapshot.items.prefix(limit))
            )
            return try Self.encodedJSONValue(trimmed)

        case "cleannest.activity_log":
            try rejectUnknown(arguments, allowed: ["limit"])
            let limit = try integer(arguments["limit"], default: 20, range: 1...50)
            guard FileManager.default.fileExists(atPath: activityURL.path) else {
                return .object(["activities": .array([])])
            }
            let data = try Data(contentsOf: activityURL, options: [.mappedIfSafe])
            guard data.count <= Self.maximumMessageBytes else {
                throw MCPDataError.unavailable("活动记录超过读取上限。")
            }
            let records = try JSONDecoder().decode([MCPActivityRecord].self, from: data)
            return .object([
                "activities": .array(records.prefix(limit).map { record in
                    .object([
                        "date": .string(Self.iso8601(record.date)),
                        "title": .string(redact(record.title, maximumLength: 240)),
                        "detail": .string(redact(record.detail, maximumLength: 800)),
                        "outcome": .string(Self.sanitize(record.outcome, maximumLength: 80)),
                        "affected_items": .number(Double(record.affectedItems)),
                        "bytes": .number(Double(record.bytes))
                    ])
                })
            ])

        default:
            throw MCPDataError.invalidArgument("未知工具。")
        }
    }

    private func rejectUnknown(_ arguments: [String: JSONValue], allowed: Set<String>) throws {
        let unknown = Set(arguments.keys).subtracting(allowed)
        if let first = unknown.sorted().first {
            throw MCPDataError.invalidArgument("不支持参数 \(first)。")
        }
    }

    private func integer(
        _ value: JSONValue?,
        default fallback: Int,
        range: ClosedRange<Int>
    ) throws -> Int {
        guard let value else { return fallback }
        guard let number = value.numberValue,
              number.isFinite,
              number.rounded() == number,
              let integer = Int(exactly: number),
              range.contains(integer) else {
            throw MCPDataError.invalidArgument("整数参数必须位于 \(range.lowerBound)...\(range.upperBound)。")
        }
        return integer
    }

    private func redact(_ value: String, maximumLength: Int) -> String {
        Self.sanitize(
            value.replacingOccurrences(of: homeDirectory.path, with: "~"),
            maximumLength: maximumLength
        )
    }

    private func discoverResult() -> JSONValue {
        .object([
            "resultType": .string("complete"),
            "supportedVersions": .array([.string(Self.modernProtocolVersion)]),
            "capabilities": .object(["tools": .object(["listChanged": .bool(false)])]),
            "instructions": .string(Self.instructions),
            "ttlMs": .number(3_600_000),
            "cacheScope": .string("public")
        ])
    }

    private func toolResult(_ output: JSONValue, modern: Bool) -> JSONValue {
        var result: [String: JSONValue] = [
            "content": .array([.object(["type": .string("text"), "text": .string(Self.pretty(output))])]),
            "structuredContent": output,
            "isError": .bool(false)
        ]
        if modern { result["resultType"] = .string("complete") }
        return .object(result)
    }

    private func toolErrorResult(_ message: String, modern: Bool) -> JSONValue {
        var result: [String: JSONValue] = [
            "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
            "isError": .bool(true)
        ]
        if modern { result["resultType"] = .string("complete") }
        return .object(result)
    }

    private func success(id: JSONValue, result: JSONValue, modern: Bool) -> JSONValue {
        let resultWithIdentity: JSONValue
        if modern, case .object(var object) = result {
            object["_meta"] = .object([
                "io.modelcontextprotocol/serverInfo": .object([
                    "name": .string("CleanNest"),
                    "version": .string("0.5.3")
                ])
            ])
            resultWithIdentity = .object(object)
        } else {
            resultWithIdentity = result
        }
        return .object(["jsonrpc": .string("2.0"), "id": id, "result": resultWithIdentity])
    }

    private func error(id: JSONValue, code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "error": .object(["code": .number(Double(code)), "message": .string(message)])
        ])
    }

    private func notInitialized(id: JSONValue) -> JSONValue {
        error(id: id, code: -32002, message: "Server is not initialized or request metadata is missing")
    }

    private func encode(_ value: JSONValue) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try? encoder.encode(value)
    }

    private static func metricObject(_ sample: MetricSample) -> JSONValue {
        .object([
            "sampled_at": .string(iso8601(sample.sampledAt)),
            "health_score": sample.healthScore.map { .number(Double($0)) } ?? .null,
            "cpu_usage_percent": sample.cpuUsage.map(JSONValue.number) ?? .null,
            "memory_used_percent": sample.memoryUsedPercent.map(JSONValue.number) ?? .null,
            "memory_pressure": .string(sample.memoryPressureLevel.rawValue),
            "memory_used_bytes": sample.memoryUsedBytes.map { .number(Double($0)) } ?? .null,
            "memory_available_bytes": sample.memoryAvailableBytes.map { .number(Double($0)) } ?? .null,
            "memory_compressed_bytes": sample.memoryCompressedBytes.map { .number(Double($0)) } ?? .null,
            "memory_swap_used_bytes": sample.memorySwapUsedBytes.map { .number(Double($0)) } ?? .null,
            "disk_used_percent": sample.diskUsedPercent.map(JSONValue.number) ?? .null,
            "disk_free_bytes": sample.diskFreeBytes.map { .number(Double($0)) } ?? .null,
            "battery_level_percent": sample.batteryLevel.map(JSONValue.number) ?? .null,
            "temperature_celsius": sample.temperatureCelsius.map(JSONValue.number) ?? .null,
            "process_count": sample.processCount.map { .number(Double($0)) } ?? .null
        ])
    }

    private static func encodedJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private static func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func sanitize(_ value: String, maximumLength: Int) -> String {
        let clean = value.unicodeScalars.map { scalar -> String in
            if scalar == "\n" { return "\n" }
            return CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        return String(clean.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).prefix(maximumLength))
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static let instructions = "CleanNest exposes local read-only Mac health, disk evidence, cleanup previews, and audit history. No tool can delete files, stop processes, change settings, or access file contents."

    private static let toolNames: Set<String> = Set([
        "cleannest.server_status",
        "cleannest.latest_snapshot",
        "cleannest.metric_history",
        "cleannest.top_processes",
        "cleannest.disk_evidence",
        "cleannest.cleanup_preview",
        "cleannest.activity_log"
    ])

    private static let tools: [JSONValue] = [
        tool(
            name: "cleannest.server_status",
            title: "CleanNest data status",
            description: "Reports which local CleanNest read-only data stores currently exist.",
            properties: [:]
        ),
        tool(
            name: "cleannest.latest_snapshot",
            title: "Latest Mac health snapshot",
            description: "Returns the latest locally persisted CPU, memory, disk, battery, temperature, and process-count sample.",
            properties: [:]
        ),
        tool(
            name: "cleannest.metric_history",
            title: "Mac metric history",
            description: "Returns bounded local metric history for one hour, day, week, or month.",
            properties: [
                "range": .object(["type": .string("string"), "enum": .array([.string("hour"), .string("day"), .string("week"), .string("month")])]),
                "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(2_000)])
            ]
        ),
        tool(
            name: "cleannest.top_processes",
            title: "Top memory processes",
            description: "Samples up to 20 local processes by physical memory footprint without exposing command-line arguments or executable paths.",
            properties: ["limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(20)])]
        ),
        tool(
            name: "cleannest.disk_evidence",
            title: "Last disk evidence report",
            description: "Returns the latest redacted, metadata-only disk evidence generated explicitly in the CleanNest app.",
            properties: ["limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(32)])]
        ),
        tool(
            name: "cleannest.cleanup_preview",
            title: "Last cleanup preview",
            description: "Returns the last tokenized cleanup candidate preview. It never performs cleanup or changes selection.",
            properties: ["limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(64)])]
        ),
        tool(
            name: "cleannest.activity_log",
            title: "CleanNest activity log",
            description: "Returns bounded local audit records with the home-directory path redacted.",
            properties: ["limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(50)])]
        )
    ]

    private static func tool(
        name: String,
        title: String,
        description: String,
        properties: [String: JSONValue]
    ) -> JSONValue {
        .object([
            "name": .string(name),
            "title": .string(title),
            "description": .string(description),
            "inputSchema": .object([
                "$schema": .string("https://json-schema.org/draft/2020-12/schema"),
                "type": .string("object"),
                "properties": .object(properties),
                "additionalProperties": .bool(false)
            ]),
            "outputSchema": .object(["type": .string("object")]),
            "annotations": .object([
                "readOnlyHint": .bool(true),
                "destructiveHint": .bool(false),
                "idempotentHint": .bool(true),
                "openWorldHint": .bool(false)
            ])
        ])
    }
}

private enum MCPDataError: LocalizedError {
    case unavailable(String)
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidArgument(let message): return message
        }
    }
}
