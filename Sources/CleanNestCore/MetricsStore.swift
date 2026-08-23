import Foundation
import SQLite3

public enum MetricHistoryRange: String, CaseIterable, Codable, Sendable {
    case hour
    case day
    case week
    case month

    public var duration: TimeInterval {
        switch self {
        case .hour: return 60 * 60
        case .day: return 24 * 60 * 60
        case .week: return 7 * 24 * 60 * 60
        case .month: return 30 * 24 * 60 * 60
        }
    }

    public var maximumSamples: Int {
        switch self {
        case .hour: return 180
        case .day: return 720
        case .week: return 1_200
        case .month: return 1_500
        }
    }
}

public struct MetricSample: Identifiable, Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let healthScore: Int?
    public let cpuUsage: Double?
    public let memoryUsedPercent: Double?
    public let memoryPressureLevel: MemoryPressureLevel
    public let memoryUsedBytes: Int64?
    public let memoryAvailableBytes: Int64?
    public let memoryCompressedBytes: Int64?
    public let memorySwapUsedBytes: Int64?
    public let diskUsedPercent: Double?
    public let diskFreeBytes: Int64?
    public let batteryLevel: Double?
    public let temperatureCelsius: Double?
    public let processCount: Int?

    public var id: Date { sampledAt }

    public init(
        sampledAt: Date,
        healthScore: Int?,
        cpuUsage: Double?,
        memoryUsedPercent: Double?,
        memoryPressureLevel: MemoryPressureLevel,
        memoryUsedBytes: Int64?,
        memoryAvailableBytes: Int64?,
        memoryCompressedBytes: Int64?,
        memorySwapUsedBytes: Int64?,
        diskUsedPercent: Double?,
        diskFreeBytes: Int64?,
        batteryLevel: Double?,
        temperatureCelsius: Double?,
        processCount: Int?
    ) {
        self.sampledAt = sampledAt
        self.healthScore = healthScore
        self.cpuUsage = cpuUsage
        self.memoryUsedPercent = memoryUsedPercent
        self.memoryPressureLevel = memoryPressureLevel
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryAvailableBytes = memoryAvailableBytes
        self.memoryCompressedBytes = memoryCompressedBytes
        self.memorySwapUsedBytes = memorySwapUsedBytes
        self.diskUsedPercent = diskUsedPercent
        self.diskFreeBytes = diskFreeBytes
        self.batteryLevel = batteryLevel
        self.temperatureCelsius = temperatureCelsius
        self.processCount = processCount
    }

    public init(snapshot: SystemSnapshot) {
        self.init(
            sampledAt: snapshot.sampledAt,
            healthScore: snapshot.healthScore,
            cpuUsage: snapshot.cpuUsage,
            memoryUsedPercent: snapshot.memoryUsedPercent,
            memoryPressureLevel: snapshot.memoryPressureLevel,
            memoryUsedBytes: snapshot.memoryUsedBytes,
            memoryAvailableBytes: snapshot.memoryAvailableBytes,
            memoryCompressedBytes: snapshot.memoryCompressedBytes,
            memorySwapUsedBytes: snapshot.memorySwapUsedBytes,
            diskUsedPercent: snapshot.diskUsedPercent,
            diskFreeBytes: snapshot.diskFreeBytes,
            batteryLevel: snapshot.batteryLevel,
            temperatureCelsius: snapshot.temperatureCelsius,
            processCount: snapshot.processCount
        )
    }
}

public enum MetricsStoreError: LocalizedError, Equatable {
    case cannotCreateDirectory(String)
    case cannotOpenDatabase(String)
    case readOnly
    case sqlite(code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let detail):
            return "无法创建指标存储目录：\(detail)"
        case .cannotOpenDatabase(let detail):
            return "无法打开指标数据库：\(detail)"
        case .readOnly:
            return "指标数据库以只读方式打开，拒绝写入。"
        case .sqlite(_, let message):
            return "指标数据库操作失败：\(message)"
        }
    }
}

public enum MetricsStoreAccess: Equatable, Sendable {
    case readWrite
    case readOnly
}

/// Serialized SQLite/WAL storage for local, point-in-time system metrics.
///
/// The actor opens a short-lived connection for each operation. This keeps the
/// SQLite handle out of Sendable state while WAL still permits the separate
/// read-only MCP process to query history concurrently with the GUI writer.
public actor MetricsStore {
    public static let schemaVersion = 1

    public let databaseURL: URL
    public let access: MetricsStoreAccess

    public init(
        databaseURL: URL = CleanNestDataPaths.metricsDatabase(),
        access: MetricsStoreAccess = .readWrite
    ) {
        self.databaseURL = databaseURL.standardizedFileURL
        self.access = access
    }

    public func prepare() throws {
        guard access == .readWrite else { throw MetricsStoreError.readOnly }
        try withDatabase { _ in }
    }

    public func append(_ sample: MetricSample) throws {
        guard access == .readWrite else { throw MetricsStoreError.readOnly }
        try withDatabase { database in
            let sql = """
            INSERT OR REPLACE INTO metric_samples (
                sampled_at, health_score, cpu_usage, memory_used_percent,
                memory_pressure, memory_used_bytes, memory_available_bytes,
                memory_compressed_bytes, memory_swap_used_bytes,
                disk_used_percent, disk_free_bytes, battery_level,
                temperature_celsius, process_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            let statement = try prepare(sql, database: database)
            defer { sqlite3_finalize(statement) }

            try bind(sample.sampledAt.timeIntervalSince1970, to: 1, statement: statement, database: database)
            try bind(sample.healthScore, to: 2, statement: statement, database: database)
            try bind(sample.cpuUsage, to: 3, statement: statement, database: database)
            try bind(sample.memoryUsedPercent, to: 4, statement: statement, database: database)
            try bind(Self.pressureCode(sample.memoryPressureLevel), to: 5, statement: statement, database: database)
            try bind(sample.memoryUsedBytes, to: 6, statement: statement, database: database)
            try bind(sample.memoryAvailableBytes, to: 7, statement: statement, database: database)
            try bind(sample.memoryCompressedBytes, to: 8, statement: statement, database: database)
            try bind(sample.memorySwapUsedBytes, to: 9, statement: statement, database: database)
            try bind(sample.diskUsedPercent, to: 10, statement: statement, database: database)
            try bind(sample.diskFreeBytes, to: 11, statement: statement, database: database)
            try bind(sample.batteryLevel, to: 12, statement: statement, database: database)
            try bind(sample.temperatureCelsius, to: 13, statement: statement, database: database)
            try bind(sample.processCount, to: 14, statement: statement, database: database)
            try stepDone(statement, database: database)
        }
    }

    public func latest() throws -> MetricSample? {
        try withDatabase { database in
            let statement = try prepare(
                Self.selectColumns + " ORDER BY sampled_at DESC LIMIT 1;",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return Self.decodeSample(statement)
        }
    }

    public func samples(
        since: Date,
        limit: Int = 1_500
    ) throws -> [MetricSample] {
        let safeLimit = min(max(limit, 1), 10_000)
        return try withDatabase { database in
            let statement = try prepare(
                Self.selectColumns
                    + " WHERE sampled_at >= ? ORDER BY sampled_at DESC LIMIT ?;",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(since.timeIntervalSince1970, to: 1, statement: statement, database: database)
            try bind(safeLimit, to: 2, statement: statement, database: database)

            var result: [MetricSample] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(Self.decodeSample(statement))
            }
            return result.reversed()
        }
    }

    public func samples(
        range: MetricHistoryRange,
        now: Date = Date()
    ) throws -> [MetricSample] {
        try samples(
            since: now.addingTimeInterval(-range.duration),
            limit: range.maximumSamples
        )
    }

    @discardableResult
    public func prune(retainingDays days: Int, now: Date = Date()) throws -> Int {
        guard access == .readWrite else { throw MetricsStoreError.readOnly }
        let safeDays = min(max(days, 1), 365)
        let cutoff = now.addingTimeInterval(-TimeInterval(safeDays) * 86_400)
        return try withDatabase { database in
            let statement = try prepare(
                "DELETE FROM metric_samples WHERE sampled_at < ?;",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(cutoff.timeIntervalSince1970, to: 1, statement: statement, database: database)
            try stepDone(statement, database: database)
            return Int(sqlite3_changes(database))
        }
    }

    public func clear() throws {
        guard access == .readWrite else { throw MetricsStoreError.readOnly }
        try withDatabase { database in
            try execute("DELETE FROM metric_samples;", database: database)
            try execute("PRAGMA wal_checkpoint(TRUNCATE);", database: database)
        }
    }

    public func count() throws -> Int {
        try withDatabase { database in
            let statement = try prepare(
                "SELECT COUNT(*) FROM metric_samples;",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    private static let selectColumns = """
    SELECT sampled_at, health_score, cpu_usage, memory_used_percent,
           memory_pressure, memory_used_bytes, memory_available_bytes,
           memory_compressed_bytes, memory_swap_used_bytes,
           disk_used_percent, disk_free_bytes, battery_level,
           temperature_celsius, process_count
    FROM metric_samples
    """

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        if access == .readWrite {
            do {
                try FileManager.default.createDirectory(
                    at: databaseURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw MetricsStoreError.cannotCreateDirectory(error.localizedDescription)
            }
        } else if !FileManager.default.fileExists(atPath: databaseURL.path) {
            throw MetricsStoreError.cannotOpenDatabase("数据库尚未由 CleanNest 创建")
        }

        var database: OpaquePointer?
        let flags = access == .readWrite
            ? SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            : SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &database, flags, nil)
        guard openResult == SQLITE_OK, let database else {
            let detail = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "SQLite 返回 \(openResult)"
            if let database { sqlite3_close(database) }
            throw MetricsStoreError.cannotOpenDatabase(detail)
        }
        defer { sqlite3_close(database) }

        sqlite3_busy_timeout(database, 2_000)
        if access == .readWrite {
            try execute("PRAGMA journal_mode=WAL;", database: database)
            try execute("PRAGMA synchronous=NORMAL;", database: database)
            try execute("PRAGMA foreign_keys=ON;", database: database)
            try execute(
                """
                CREATE TABLE IF NOT EXISTS metric_samples (
                    sampled_at REAL PRIMARY KEY NOT NULL,
                    health_score INTEGER,
                    cpu_usage REAL,
                    memory_used_percent REAL,
                    memory_pressure INTEGER NOT NULL,
                    memory_used_bytes INTEGER,
                    memory_available_bytes INTEGER,
                    memory_compressed_bytes INTEGER,
                    memory_swap_used_bytes INTEGER,
                    disk_used_percent REAL,
                    disk_free_bytes INTEGER,
                    battery_level REAL,
                    temperature_celsius REAL,
                    process_count INTEGER
                );
                """,
                database: database
            )
            try execute(
                "CREATE INDEX IF NOT EXISTS metric_samples_time ON metric_samples(sampled_at);",
                database: database
            )
            try execute("PRAGMA user_version=\(Self.schemaVersion);", database: database)
        }
        return try body(database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        guard result == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            if let errorMessage { sqlite3_free(errorMessage) }
            throw MetricsStoreError.sqlite(code: result, message: message)
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            throw MetricsStoreError.sqlite(
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer, database: OpaquePointer) throws {
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw MetricsStoreError.sqlite(
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
    }

    private func bind(
        _ value: Double?,
        to index: Int32,
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        let result = value.map { sqlite3_bind_double(statement, index, $0) }
            ?? sqlite3_bind_null(statement, index)
        try validateBind(result, database: database)
    }

    private func bind(
        _ value: Int?,
        to index: Int32,
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        let result = value.map { sqlite3_bind_int64(statement, index, sqlite3_int64($0)) }
            ?? sqlite3_bind_null(statement, index)
        try validateBind(result, database: database)
    }

    private func bind(
        _ value: Int64?,
        to index: Int32,
        statement: OpaquePointer,
        database: OpaquePointer
    ) throws {
        let result = value.map { sqlite3_bind_int64(statement, index, sqlite3_int64($0)) }
            ?? sqlite3_bind_null(statement, index)
        try validateBind(result, database: database)
    }

    private func validateBind(_ result: Int32, database: OpaquePointer) throws {
        guard result == SQLITE_OK else {
            throw MetricsStoreError.sqlite(
                code: result,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
    }

    private static func decodeSample(_ statement: OpaquePointer) -> MetricSample {
        MetricSample(
            sampledAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
            healthScore: optionalInt(statement, column: 1),
            cpuUsage: optionalDouble(statement, column: 2),
            memoryUsedPercent: optionalDouble(statement, column: 3),
            memoryPressureLevel: pressureLevel(Int(sqlite3_column_int64(statement, 4))),
            memoryUsedBytes: optionalInt64(statement, column: 5),
            memoryAvailableBytes: optionalInt64(statement, column: 6),
            memoryCompressedBytes: optionalInt64(statement, column: 7),
            memorySwapUsedBytes: optionalInt64(statement, column: 8),
            diskUsedPercent: optionalDouble(statement, column: 9),
            diskFreeBytes: optionalInt64(statement, column: 10),
            batteryLevel: optionalDouble(statement, column: 11),
            temperatureCelsius: optionalDouble(statement, column: 12),
            processCount: optionalInt(statement, column: 13)
        )
    }

    private static func optionalDouble(_ statement: OpaquePointer, column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL
            ? nil
            : sqlite3_column_double(statement, column)
    }

    private static func optionalInt64(_ statement: OpaquePointer, column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL
            ? nil
            : Int64(sqlite3_column_int64(statement, column))
    }

    private static func optionalInt(_ statement: OpaquePointer, column: Int32) -> Int? {
        optionalInt64(statement, column: column).flatMap(Int.init(exactly:))
    }

    private static func pressureCode(_ level: MemoryPressureLevel) -> Int {
        switch level {
        case .normal: return 0
        case .warning: return 1
        case .critical: return 2
        case .unknown: return 3
        }
    }

    private static func pressureLevel(_ code: Int) -> MemoryPressureLevel {
        switch code {
        case 0: return .normal
        case 1: return .warning
        case 2: return .critical
        default: return .unknown
        }
    }
}
