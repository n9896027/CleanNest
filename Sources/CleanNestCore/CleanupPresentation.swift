import Foundation

/// User-facing labels must not change the persisted CleanupKind raw values.
/// Older scan sessions therefore remain decodable after copy improvements.
public extension CleanupKind {
    var displayName: String {
        switch self {
        case .logs: return "应用日志"
        default: return rawValue
        }
    }
}

public enum CleanupScanIssueDisposition: String, Equatable, Sendable {
    case needsAttention
    case safetyBoundary
}

public struct CleanupScanIssueGroup: Equatable, Identifiable, Sendable {
    public let reason: CleanupScanSkipReason
    public let issues: [CleanupScanIssue]

    public var id: CleanupScanSkipReason { reason }

    public init(reason: CleanupScanSkipReason, issues: [CleanupScanIssue]) {
        self.reason = reason
        self.issues = issues
    }

    public var disposition: CleanupScanIssueDisposition {
        switch reason {
        case .unreadable, .depthLimit, .fileLimit, .hashLimit, .cloudPlaceholder:
            return .needsAttention
        case .symbolicLink, .packageBoundary, .unsafeRoot:
            return .safetyBoundary
        }
    }

    /// Repeating the same bounded scan cannot resolve depth/count/hash limits or
    /// a permanent safety boundary. Only an access change has a meaningful retry.
    public var allowsAuthorizationAndRescan: Bool { reason == .unreadable }

    public var summary: String {
        switch reason {
        case .unreadable:
            return "读取权限不足或状态无法确认。授权后可重新扫描；这些路径不会直接进入清理。"
        case .depthLimit:
            return "当前有界扫描未继续深入。相同设置下重扫不会扩大扫描范围。"
        case .fileLimit:
            return "当前扫描数量上限已到达。相同设置下重扫不会增加覆盖范围。"
        case .hashLimit:
            return "当前哈希核验上限已到达。相同设置下重扫不会增加核验数量。"
        case .cloudPlaceholder:
            return "云端内容尚未成为可安全处理的本地候选；请先由云端服务管理本地副本。"
        case .unsafeRoot:
            return "路径身份未通过安全检查。重新扫描不会绕过这条安全边界。"
        case .symbolicLink:
            return "为避免触及链接目标，扫描没有跟随这些链接。重新扫描也不会改变这一行为。"
        case .packageBoundary:
            return "为避免破坏 App 或资料库包结构，扫描没有展开其内容；请使用所属 App 管理。"
        }
    }
}

public enum CleanupScanIssuePresentation {
    private static let reasonOrder: [CleanupScanSkipReason] = [
        .unreadable,
        .depthLimit,
        .fileLimit,
        .hashLimit,
        .cloudPlaceholder,
        .unsafeRoot,
        .symbolicLink,
        .packageBoundary
    ]

    public static func groups(for issues: [CleanupScanIssue]) -> [CleanupScanIssueGroup] {
        reasonOrder.compactMap { reason in
            let matches = issues.filter { $0.reason == reason }
            return matches.isEmpty ? nil : CleanupScanIssueGroup(reason: reason, issues: matches)
        }
    }
}

/// Copy is deliberately limited to evidence the scanner actually has. It does
/// not infer an app owner from a directory name or promise log regeneration.
public struct CleanupLogPresentation: Equatable, Sendable {
    public let rowSummary = "应用或服务日志 · 用于运行记录与故障排查"
    public let groupSummary = "应用或服务产生的运行与故障诊断记录。不会自动选择；不再需要历史排查记录时才处理。"
    public let what = "这是 ~/Library/Logs 下的应用或服务日志目录，通常记录运行状态、错误或诊断事件。CleanNest 只检查路径、体积和修改时间，没有读取日志内容；原始目录名不等于已核验的应用归属。"
    public let reason = "此目录至少 30 天未修改，符合应用日志候选规则。只有不再需要这些历史诊断记录时才应选择。"
    public let impact = "处理只会将所选日志目录移到废纸篓，不会卸载应用，也不会删除文稿或项目。历史排查记录将不在原位置；之后是否生成新日志取决于对应应用或服务。"
    public let recovery = "清空废纸篓前，可以从废纸篓放回；清空后 CleanNest 无法恢复。实际空间释放以清空后的 APFS 可用空间为准。"

    public init() {}
}

public extension CleanupCandidate {
    var logPresentation: CleanupLogPresentation? {
        guard kind == .logs else { return nil }
        return CleanupLogPresentation()
    }
}
