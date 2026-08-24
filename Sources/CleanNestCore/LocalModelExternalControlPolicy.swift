import Foundation

public enum LocalModelExternalControlPolicy {
    public static func refusalReason(for runtime: LocalModelRuntimeInstance) -> String? {
        if runtime.isOwnedByCleanNest {
            return "该进程由 CleanNest 启动，请使用普通停止流程。"
        }
        guard let process = runtime.process else {
            return "没有找到可精确定位的进程，不能只根据端口关闭服务。"
        }
        guard process.pid > 1 else {
            return "进程身份不安全，CleanNest 拒绝发送终止信号。"
        }
        guard runtime.evidence.contains(.process) else {
            return "缺少进程证据，无法安全关闭。"
        }
        guard process.startedAt != nil || process.executablePath != nil else {
            return "缺少启动时间和可执行文件证据，无法防止 PID 复用。"
        }
        if runtime.platform == .openAICompatible,
           !runtime.evidence.contains(.platformAPI) {
            return "未知平台的模型 API 尚未确认，不直接关闭。"
        }
        return nil
    }

    public static func identityMismatchReason(
        expected: LocalModelProcessSnapshot,
        observed: LocalModelProcessSnapshot
    ) -> String? {
        guard expected.pid == observed.pid else {
            return "进程 PID 已改变。"
        }
        if let expectedPath = expected.executablePath,
           observed.executablePath != expectedPath {
            return "可执行文件已改变，可能发生了 PID 复用。"
        }
        if let expectedStart = expected.startedAt {
            guard let observedStart = observed.startedAt,
                  abs(expectedStart.timeIntervalSince(observedStart)) <= 2 else {
                return "进程启动时间已改变，可能是新进程。"
            }
        }
        return nil
    }

    public static func identityMismatchReason(
        expected: LocalModelProcessSnapshot,
        observed: MemoryProcessSnapshot
    ) -> String? {
        guard expected.pid == observed.pid else {
            return "进程 PID 已改变。"
        }
        if let expectedPath = expected.executablePath,
           observed.executablePath != expectedPath {
            return "可执行文件已改变，可能发生了 PID 复用。"
        }
        if let expectedStart = expected.startedAt {
            let observedStart = Date(
                timeIntervalSince1970: TimeInterval(observed.startSeconds)
                    + TimeInterval(observed.startMicroseconds) / 1_000_000
            )
            guard abs(expectedStart.timeIntervalSince(observedStart)) <= 2 else {
                return "进程启动时间已改变，可能是新进程。"
            }
        }
        return nil
    }
}

public extension LocalModelRuntimeInstance {
    var canRequestExternalStop: Bool {
        !isOwnedByCleanNest
            && LocalModelExternalControlPolicy.refusalReason(for: self) == nil
    }
}
