import Foundation

public enum MaintenanceEvidenceState: String, Codable, Equatable, Sendable {
    case noAnomalyDetected
    case anomalyDetected
    case uncertain

    public var title: String {
        switch self {
        case .noAnomalyDetected: return "基础检查未发现异常"
        case .anomalyDetected: return "发现可验证异常"
        case .uncertain: return "自动检查无法确认"
        }
    }
}

public struct MaintenanceEvidence: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let action: MaintenanceAction
    public let checkedAt: Date
    public let state: MaintenanceEvidenceState
    public let headline: String
    public let detail: String
    public let processIDs: [Int32]

    public init(
        id: UUID = UUID(),
        action: MaintenanceAction,
        checkedAt: Date = Date(),
        state: MaintenanceEvidenceState,
        headline: String,
        detail: String,
        processIDs: [Int32] = []
    ) {
        self.id = id
        self.action = action
        self.checkedAt = checkedAt
        self.state = state
        self.headline = headline
        self.detail = detail
        self.processIDs = processIDs.sorted()
    }
}

public enum MaintenanceRunOutcome: String, Codable, Equatable, Sendable {
    case verifiedRecovered
    case basicVerificationPassed
    case notRecovered
    case commandFailed
    case inconclusive

    public var title: String {
        switch self {
        case .verifiedRecovered: return "服务已验证恢复"
        case .basicVerificationPassed: return "基础复核通过"
        case .notRecovered: return "执行后仍未恢复"
        case .commandFailed: return "任务没有执行成功"
        case .inconclusive: return "执行完成，但无法确认恢复"
        }
    }

    public var isSuccessful: Bool {
        self == .verifiedRecovered || self == .basicVerificationPassed
    }
}

public struct MaintenanceRunRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let action: MaintenanceAction
    public let startedAt: Date
    public let finishedAt: Date
    public let before: MaintenanceEvidence
    public let after: MaintenanceEvidence
    public let commandSucceeded: Bool
    public let outcome: MaintenanceRunOutcome
    public let summary: String

    public init(
        id: UUID = UUID(),
        action: MaintenanceAction,
        startedAt: Date,
        finishedAt: Date = Date(),
        before: MaintenanceEvidence,
        after: MaintenanceEvidence,
        commandSucceeded: Bool,
        outcome: MaintenanceRunOutcome,
        summary: String
    ) {
        self.id = id
        self.action = action
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.before = before
        self.after = after
        self.commandSucceeded = commandSucceeded
        self.outcome = outcome
        self.summary = summary
    }
}

public enum MaintenanceDiagnosticPolicy {
    public static func assess(
        action: MaintenanceAction,
        processIDs: [Int32] = [],
        readOnlyProbeSucceeded: Bool?,
        checkedAt: Date = Date()
    ) -> MaintenanceEvidence {
        switch action {
        case .quickLook:
            guard let readOnlyProbeSucceeded else {
                return MaintenanceEvidence(
                    action: action,
                    checkedAt: checkedAt,
                    state: .uncertain,
                    headline: "CleanNest 无法完成 Quick Look 只读检查。",
                    detail: "仍可由你确认重建缓存，但不能把未知状态写成已经诊断出故障。"
                )
            }
            if readOnlyProbeSucceeded {
                return MaintenanceEvidence(
                    action: action,
                    checkedAt: checkedAt,
                    state: .noAnomalyDetected,
                    headline: "Quick Look 基础接口可以响应。",
                    detail: "这只能证明基础接口可用，不能判断你正在看的某个文件是否仍用了旧缩略图。"
                )
            }
            return MaintenanceEvidence(
                action: action,
                checkedAt: checkedAt,
                state: .anomalyDetected,
                headline: "Quick Look 基础接口没有正常响应。",
                detail: "重建缓存有明确依据；原文件不会被修改。"
            )

        case .finder, .dock, .menuBar:
            let processName = action.verificationProcessName ?? action.rawValue
            guard let readOnlyProbeSucceeded else {
                return MaintenanceEvidence(
                    action: action,
                    checkedAt: checkedAt,
                    state: .uncertain,
                    headline: "无法读取 \(processName) 的进程状态。",
                    detail: "CleanNest 不会假装已诊断；你仍可在了解影响后确认重启。"
                )
            }
            if readOnlyProbeSucceeded, !processIDs.isEmpty {
                return MaintenanceEvidence(
                    action: action,
                    checkedAt: checkedAt,
                    state: .noAnomalyDetected,
                    headline: "\(processName) 正在运行（PID \(processIDs.sorted().map(String.init).joined(separator: ", "))）。",
                    detail: "进程存在不等于界面一定响应；CleanNest 无法读取你的点击或窗口内容。",
                    processIDs: processIDs
                )
            }
            return MaintenanceEvidence(
                action: action,
                checkedAt: checkedAt,
                state: .anomalyDetected,
                headline: "没有发现当前用户的 \(processName) 进程。",
                detail: "这是可验证的异常；执行后会检查它是否以新进程返回。"
            )
        }
    }

    public static func verify(
        action: MaintenanceAction,
        startedAt: Date,
        before: MaintenanceEvidence,
        after: MaintenanceEvidence,
        commandSucceeded: Bool,
        finishedAt: Date = Date()
    ) -> MaintenanceRunRecord {
        let outcome: MaintenanceRunOutcome
        let summary: String

        if !commandSucceeded {
            outcome = .commandFailed
            summary = "命令没有成功完成；CleanNest 没有把它记录成修复。"
        } else if action == .quickLook {
            switch after.state {
            case .noAnomalyDetected:
                outcome = .basicVerificationPassed
                summary = "缓存重建命令已完成，Quick Look 基础接口也能响应；请重新按空格确认目标文件的预览是否更新。"
            case .anomalyDetected:
                outcome = .notRecovered
                summary = "缓存重建命令已完成，但 Quick Look 基础复核仍失败。"
            case .uncertain:
                outcome = .inconclusive
                summary = "缓存重建命令已完成，但自动复核无法确认结果。"
            }
        } else if after.state == .noAnomalyDetected,
                  !Set(after.processIDs).subtracting(Set(before.processIDs)).isEmpty {
            outcome = .verifiedRecovered
            summary = "旧进程已退出，\(action.verificationProcessName ?? "界面服务") 已以新 PID 恢复；如果画面仍卡住，请按恢复说明处理。"
        } else if after.state == .anomalyDetected {
            outcome = .notRecovered
            summary = "命令已完成，但预期服务没有在复核时间内返回。"
        } else {
            outcome = .inconclusive
            summary = "命令已完成，但没有取得足以证明服务已换成新进程的证据。"
        }

        return MaintenanceRunRecord(
            action: action,
            startedAt: startedAt,
            finishedAt: finishedAt,
            before: before,
            after: after,
            commandSucceeded: commandSucceeded,
            outcome: outcome,
            summary: summary
        )
    }
}

public enum MaintenanceHistoryPersistence {
    public static let maximumRecords = 40

    public static func load(from url: URL) throws -> [MaintenanceRunRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return Array(try decoder.decode([MaintenanceRunRecord].self, from: Data(contentsOf: url)).prefix(maximumRecords))
    }

    public static func save(_ records: [MaintenanceRunRecord], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(Array(records.prefix(maximumRecords)))
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
