import Foundation

public enum CleanupActivityError: LocalizedError, Equatable, Sendable {
    case activeFile(path: String, processName: String, processID: Int32)
    case probeUnavailable(diagnostic: String)

    public var errorDescription: String? {
        switch self {
        case let .activeFile(path, processName, processID):
            return "检测到 \(processName)（PID \(processID)）正在使用 \(path)。为避免清理活跃文件，该项目未移动；请关闭相关文件后重试。"
        case let .probeUnavailable(diagnostic):
            return "无法确认当前打开文件状态，已停止清理，所选文件未移动。\(diagnostic)"
        }
    }
}

/// Execution-time protection shared by every general cleanup entry point.
/// A successful snapshot is evidence only about the current user's open-file
/// table at that instant; an unavailable snapshot is never treated as empty.
public enum CleanupActivityPreflight {
    public static func validate(
        targets: [URL],
        snapshot: AgentWorkspaceOpenFileProbe.Result
    ) throws {
        guard snapshot.succeeded else {
            throw CleanupActivityError.probeUnavailable(diagnostic: snapshot.diagnostic)
        }
        for target in targets {
            try validate(target: target, snapshot: snapshot)
        }
    }

    public static func validate(
        target: URL,
        snapshot: AgentWorkspaceOpenFileProbe.Result
    ) throws {
        guard snapshot.succeeded else {
            throw CleanupActivityError.probeUnavailable(diagnostic: snapshot.diagnostic)
        }
        let targetPath = normalizedPath(target)
        let matches = snapshot.records
            .filter { record in
                let openPath = normalizedPath(URL(fileURLWithPath: record.path))
                return openPath == targetPath || openPath.hasPrefix(targetPath + "/")
            }
            .sorted {
                if $0.path == $1.path { return $0.processID < $1.processID }
                return $0.path < $1.path
            }
        guard let match = matches.first else { return }
        throw CleanupActivityError.activeFile(
            path: normalizedPath(URL(fileURLWithPath: match.path)),
            processName: match.commandName,
            processID: match.processID
        )
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}
