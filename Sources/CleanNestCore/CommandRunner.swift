import Darwin
import Dispatch
import Foundation

public enum CommandRunnerError: LocalizedError {
    case executableMissing(URL)
    case launchFailed(String)
    case nonZeroExit(CommandResult)
    case invalidTimeout(TimeInterval)
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .executableMissing(let url):
            return "找不到可执行文件：\(url.path)"
        case .launchFailed(let detail):
            return "无法启动任务：\(detail)"
        case .nonZeroExit(let result):
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty ? "任务退出码为 \(result.exitCode)" : detail
        case .invalidTimeout(let timeout):
            return "任务超时时间无效：\(timeout) 秒"
        case .timedOut(let timeout):
            return "任务超过 \(Self.formattedTimeout(timeout)) 秒，已停止"
        }
    }

    private static func formattedTimeout(_ timeout: TimeInterval) -> String {
        timeout.rounded() == timeout ? String(Int(timeout)) : String(format: "%.1f", timeout)
    }
}

public struct CommandRunner: Sendable {
    private let processRegistry: CommandProcessRegistry

    public init() {
        processRegistry = CommandProcessRegistry()
    }

    /// Synchronously terminates every process launched by this runner and the
    /// descendants that belonged to those processes at termination time.
    ///
    /// This is intentionally a terminal operation for the runner: commands
    /// started after it is called are rejected. It is designed for application
    /// shutdown, where allowing a late launch could otherwise create an orphan.
    public func terminateAll() {
        processRegistry.terminateAll()
    }

    public func run(
        executable: URL,
        arguments: [String] = [],
        environment additions: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw CommandRunnerError.executableMissing(executable)
        }
        if let timeout, !timeout.isFinite || timeout <= 0 {
            throw CommandRunnerError.invalidTimeout(timeout)
        }

        guard processRegistry.beginCommand() else { throw CancellationError() }
        defer { processRegistry.endCommand() }

        let state = CommandProcessState(registry: processRegistry)
        let worker = Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let startedAt = Date()

            state.install(process)
            defer { state.markFinished() }

            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            process.standardInput = FileHandle.nullDevice
            process.environment = ProcessInfo.processInfo.environment.merging(additions) { _, new in new }

            return try await withTaskCancellationHandler {
                try Task.checkCancellation()
                do {
                    try process.run()
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    throw CommandRunnerError.launchFailed(error.localizedDescription)
                }
                state.processDidLaunch()

                async let outputData = Task.detached(priority: .userInitiated) {
                    stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                }.value
                async let errorData = Task.detached(priority: .userInitiated) {
                    stderrPipe.fileHandleForReading.readDataToEndOfFile()
                }.value

                process.waitUntilExit()
                let (collectedOutput, collectedError) = await (outputData, errorData)
                try Task.checkCancellation()

                return CommandResult(
                    executable: executable,
                    arguments: arguments,
                    exitCode: process.terminationStatus,
                    standardOutput: String(decoding: collectedOutput, as: UTF8.self),
                    standardError: String(decoding: collectedError, as: UTF8.self),
                    duration: Date().timeIntervalSince(startedAt)
                )
            } onCancel: {
                state.terminateIfRequested()
            }
        }

        let timeoutTask: Task<Void, Never>?
        if let timeout {
            timeoutTask = Task.detached(priority: .utility) {
                do {
                    try await Task.sleep(for: .seconds(timeout))
                } catch {
                    return
                }
                if state.requestStop(.timedOut) {
                    worker.cancel()
                }
            }
        } else {
            timeoutTask = nil
        }
        defer { timeoutTask?.cancel() }

        return try await withTaskCancellationHandler {
            do {
                let result = try await worker.value
                try Task.checkCancellation()
                if state.stopReason == .timedOut, let timeout {
                    throw CommandRunnerError.timedOut(timeout)
                }
                return result
            } catch is CancellationError {
                if state.stopReason == .timedOut, let timeout {
                    throw CommandRunnerError.timedOut(timeout)
                }
                throw CancellationError()
            }
        } onCancel: {
            if state.requestStop(.cancelled) {
                worker.cancel()
            }
        }
    }

    public func runChecked(
        executable: URL,
        arguments: [String] = [],
        environment: [String: String] = [:],
        timeout: TimeInterval? = nil
    ) async throws -> CommandResult {
        let result = try await run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            timeout: timeout
        )
        guard result.exitCode == 0 else {
            throw CommandRunnerError.nonZeroExit(result)
        }
        return result
    }
}

private enum CommandStopReason: Equatable, Sendable {
    case cancelled
    case timedOut
}

private final class CommandProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private let registry: CommandProcessRegistry
    private var process: Process?
    private var registeredProcess: Process?
    private var reason: CommandStopReason?
    private var finished = false

    init(registry: CommandProcessRegistry) {
        self.registry = registry
    }

    var stopReason: CommandStopReason? {
        lock.lock()
        defer { lock.unlock() }
        return reason
    }

    func install(_ process: Process) {
        lock.lock()
        self.process = process
        let shouldTerminate = reason != nil
        lock.unlock()

        if shouldTerminate, process.isRunning {
            ProcessTreeTerminator.terminate(rootPIDs: [process.processIdentifier])
        }
    }

    func processDidLaunch() {
        lock.lock()
        guard !finished, let process else {
            lock.unlock()
            return
        }
        let stopWasRequested = reason != nil
        lock.unlock()

        let registryRequestedStop = registry.register(process)

        lock.lock()
        registeredProcess = process
        let shouldTerminate = stopWasRequested || reason != nil || registryRequestedStop
        lock.unlock()

        if shouldTerminate, process.isRunning {
            ProcessTreeTerminator.terminate(rootPIDs: [process.processIdentifier])
        }
    }

    @discardableResult
    func requestStop(_ requestedReason: CommandStopReason) -> Bool {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return false
        }
        if reason == nil {
            reason = requestedReason
        }
        let runningProcess = process
        lock.unlock()

        if let runningProcess, runningProcess.isRunning {
            ProcessTreeTerminator.terminate(rootPIDs: [runningProcess.processIdentifier])
        }
        return true
    }

    func terminateIfRequested() {
        lock.lock()
        let runningProcess = reason == nil ? nil : process
        lock.unlock()

        if let runningProcess, runningProcess.isRunning {
            ProcessTreeTerminator.terminate(rootPIDs: [runningProcess.processIdentifier])
        }
    }

    func markFinished() {
        lock.lock()
        let processToUnregister = registeredProcess
        finished = true
        process = nil
        registeredProcess = nil
        lock.unlock()

        if let processToUnregister {
            registry.unregister(processToUnregister)
        }
    }
}

private final class CommandProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private let terminationLock = NSLock()
    private var processes: [pid_t: Process] = [:]
    private var inFlightCommands = 0
    private var shutdownRequested = false

    func beginCommand() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !shutdownRequested else { return false }
        inFlightCommands += 1
        return true
    }

    func endCommand() {
        lock.lock()
        inFlightCommands = max(0, inFlightCommands - 1)
        lock.unlock()
    }

    /// Returns true when shutdown had already started and this newly launched
    /// process therefore needs to stop immediately.
    @discardableResult
    func register(_ process: Process) -> Bool {
        let pid = process.processIdentifier
        guard pid > 1 else { return true }

        lock.lock()
        processes[pid] = process
        let shouldTerminate = shutdownRequested
        lock.unlock()
        return shouldTerminate
    }

    func unregister(_ process: Process) {
        let pid = process.processIdentifier
        lock.lock()
        if let registered = processes[pid], registered === process {
            processes.removeValue(forKey: pid)
        }
        lock.unlock()
    }

    func terminateAll() {
        terminationLock.lock()
        defer { terminationLock.unlock() }

        lock.lock()
        shutdownRequested = true
        lock.unlock()

        let overallDeadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
        repeat {
            let snapshot = activeSnapshot()
            if !snapshot.pids.isEmpty {
                ProcessTreeTerminator.terminate(rootPIDs: snapshot.pids)
            }
            if snapshot.inFlightCommands == 0 && activeSnapshot().pids.isEmpty {
                return
            }
            if DispatchTime.now().uptimeNanoseconds >= overallDeadline { break }
            usleep(20_000)
        } while true

        // One bounded final sweep catches a process that completed launch while
        // the first process-tree snapshot was being terminated.
        let finalPIDs = activeSnapshot().pids
        if !finalPIDs.isEmpty {
            ProcessTreeTerminator.terminate(rootPIDs: finalPIDs)
        }
    }

    private func activeSnapshot() -> (pids: [pid_t], inFlightCommands: Int) {
        lock.lock()
        processes = processes.filter { $0.value.isRunning }
        let result = (Array(processes.keys), inFlightCommands)
        lock.unlock()
        return result
    }
}

private enum ProcessTreeTerminator {
    private struct Identity: Hashable {
        let pid: pid_t
        let startSeconds: UInt64
        let startMicroseconds: UInt64
    }

    private struct Node {
        let identity: Identity
        let depth: Int
    }

    static func terminate(rootPIDs: [pid_t]) {
        let nodes = recursiveSnapshot(rootPIDs: rootPIDs)
        guard !nodes.isEmpty else { return }

        signal(nodes, with: SIGTERM)
        let survivors = waitForExit(nodes, timeoutNanoseconds: 350_000_000)
        guard !survivors.isEmpty else { return }

        signal(survivors, with: SIGKILL)
        _ = waitForExit(survivors, timeoutNanoseconds: 150_000_000)
    }

    private static func recursiveSnapshot(rootPIDs: [pid_t]) -> [Node] {
        let ownPID = getpid()
        var queue: [Node] = []
        var identities: [pid_t: Identity] = [:]
        var depths: [pid_t: Int] = [:]

        for pid in Set(rootPIDs) where pid > 1 && pid != ownPID {
            guard identities[pid] == nil, let identity = identity(of: pid) else { continue }
            identities[pid] = identity
            depths[pid] = 0
            queue.append(Node(identity: identity, depth: 0))
        }

        var cursor = 0
        while cursor < queue.count {
            let parent = queue[cursor]
            cursor += 1
            guard depths[parent.identity.pid] == parent.depth else { continue }
            for childPID in childPIDs(of: parent.identity.pid) where childPID > 1 && childPID != ownPID {
                let childIdentity: Identity
                if let knownIdentity = identities[childPID] {
                    childIdentity = knownIdentity
                } else if let discoveredIdentity = identity(of: childPID) {
                    identities[childPID] = discoveredIdentity
                    childIdentity = discoveredIdentity
                } else {
                    continue
                }

                let childDepth = parent.depth + 1
                if childDepth > (depths[childPID] ?? -1) {
                    depths[childPID] = childDepth
                    queue.append(Node(identity: childIdentity, depth: childDepth))
                }
            }
        }

        return identities.compactMap { pid, identity in
            depths[pid].map { Node(identity: identity, depth: $0) }
        }.sorted {
            if $0.depth == $1.depth { return $0.identity.pid < $1.identity.pid }
            return $0.depth > $1.depth
        }
    }

    private static func childPIDs(of parentPID: pid_t) -> [pid_t] {
        var capacity = 32
        let maximumCapacity = 16_384

        while capacity <= maximumCapacity {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let count = buffer.withUnsafeMutableBytes { bytes in
                proc_listchildpids(parentPID, bytes.baseAddress, Int32(bytes.count))
            }
            guard count >= 0 else { return [] }
            if Int(count) < capacity {
                return Array(buffer.prefix(Int(count))).filter { $0 > 0 }
            }
            if capacity == maximumCapacity {
                return Array(buffer.prefix(min(Int(count), capacity))).filter { $0 > 0 }
            }
            capacity = min(capacity * 2, maximumCapacity)
        }
        return []
    }

    private static func identity(of pid: pid_t) -> Identity? {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let copied = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedSize)
        }
        guard copied == expectedSize, info.pbi_pid == UInt32(pid) else { return nil }
        return Identity(
            pid: pid,
            startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec
        )
    }

    private static func signal(_ nodes: [Node], with signalNumber: Int32) {
        for node in nodes where identity(of: node.identity.pid) == node.identity {
            _ = Darwin.kill(node.identity.pid, signalNumber)
        }
    }

    private static func waitForExit(_ nodes: [Node], timeoutNanoseconds: UInt64) -> [Node] {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var survivors = nodes.filter { identity(of: $0.identity.pid) == $0.identity }
        while !survivors.isEmpty && DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(20_000)
            survivors = survivors.filter { identity(of: $0.identity.pid) == $0.identity }
        }
        return survivors
    }
}
