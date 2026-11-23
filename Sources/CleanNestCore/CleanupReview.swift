import Foundation

public enum CleanupReviewAction: String, Equatable, Sendable {
    case retry
    case rescan
}

/// A path-specific execution failure. Retry never bypasses TrashService:
/// it only offers another execution when the original evidence can still be
/// valid. Changed identities and invalid paths require a fresh scan instead.
public struct CleanupReviewItem: Identifiable, Equatable, Sendable {
    public let candidate: CleanupCandidate
    public let failureKind: TrashFailureKind
    public let detail: String
    public let technicalDescription: String?

    public var id: String { candidate.id }
    public var action: CleanupReviewAction {
        switch failureKind {
        case .activeFile, .activityProbeUnavailable, .permissionDenied, .operationFailed:
            return .retry
        case .validation, .targetChanged, .missingResult,
             .authorizationCancelled, .authorizationDenied, .automationDenied:
            return .rescan
        }
    }

    public var title: String {
        switch failureKind {
        case .activeFile: return "文件正在使用"
        case .activityProbeUnavailable: return "无法确认活跃状态"
        case .permissionDenied: return "没有移动权限"
        case .targetChanged: return "扫描证据已变化"
        case .validation: return "路径未通过安全校验"
        case .missingResult: return "移动结果无法确认"
        case .operationFailed: return "系统未完成移动"
        case .authorizationCancelled: return "系统认证已取消"
        case .authorizationDenied: return "系统认证未通过"
        case .automationDenied: return "系统自动化权限未开启"
        }
    }

    public var guidance: String {
        switch action {
        case .retry:
            switch failureKind {
            case .activeFile:
                return "关闭提示中的文件或所属 App 后，只重试这一项。"
            case .activityProbeUnavailable:
                return "系统状态恢复后可重试；无法读取打开文件表时不会移动。"
            case .permissionDenied:
                return "检查 macOS 文件访问权限后，只重试这一项。"
            default:
                return "确认目标仍在原位置后，可重新执行完整安全复核。"
            }
        case .rescan:
            return "旧候选不能直接重试。重新扫描取得新身份和安全证据后再决定。"
        }
    }

    public init?(candidate: CleanupCandidate, outcome: TrashOutcome) {
        guard !outcome.succeeded, let failureKind = outcome.failureKind else { return nil }
        self.candidate = candidate
        self.failureKind = failureKind
        self.detail = outcome.errorDescription ?? "未知错误"
        self.technicalDescription = outcome.technicalDescription
    }

    public static func reconciling(
        current: [CleanupReviewItem],
        candidates: [CleanupCandidate],
        outcomes: [TrashOutcome]
    ) -> [CleanupReviewItem] {
        let candidatesByPath = Dictionary(
            candidates.map { ($0.url.standardizedFileURL.path, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var next = current.filter { item in
            guard let candidate = candidatesByPath[item.candidate.url.standardizedFileURL.path] else {
                return false
            }
            return candidate.id == item.id
        }

        for outcome in outcomes {
            let path = outcome.source.standardizedFileURL.path
            next.removeAll { $0.candidate.url.standardizedFileURL.path == path }
            guard let candidate = candidatesByPath[path],
                  let item = CleanupReviewItem(candidate: candidate, outcome: outcome) else {
                continue
            }
            next.append(item)
        }
        return next
    }
}
