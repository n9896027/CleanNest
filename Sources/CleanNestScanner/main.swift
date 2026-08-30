import Foundation
import Darwin
import CleanNestCore

private enum ScannerServiceFailure {
    static let domain = "com.zone.cleannest.scanner"

    static func error(_ code: Int, _ description: String) -> NSError {
        NSError(
            domain: domain,
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

private final class ScannerServiceSession: NSObject, CleanNestScannerXPCProtocol {
    private let lock = NSLock()
    private let worker = ScannerWorker()
    private var activeRequestID: String?
    private var activeTask: Task<Void, Never>?
    private var progressData: [String: Data] = [:]
    private var invalidated = false

    func protocolVersion(withReply reply: @escaping (Int) -> Void) {
        reply(CleanNestScannerService.protocolVersion)
    }

    func scanCleanup(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let request: CleanupScannerRequest
        do {
            request = try ScannerServiceCodec.decode(CleanupScannerRequest.self, from: requestData)
        } catch {
            reply(nil, ScannerServiceFailure.error(10, "清理扫描请求无法解析。"))
            return
        }
        guard begin(requestID: request.requestID, operation: .cleanup) else {
            reply(nil, ScannerServiceFailure.error(11, "扫描服务正在处理另一个任务。"))
            return
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.worker.scanCleanup(request) { [weak self] progress in
                    self?.store(progress)
                }
                let data = try ScannerServiceCodec.encode(response)
                self.finish(requestID: request.requestID)
                reply(data, nil)
            } catch is CancellationError {
                self.finish(requestID: request.requestID)
                reply(nil, ScannerServiceFailure.error(12, "清理扫描已取消。"))
            } catch {
                self.finish(requestID: request.requestID)
                reply(nil, ScannerServiceFailure.error(13, "清理扫描失败：\(error.localizedDescription)"))
            }
        }
        install(task, for: request.requestID)
    }

    func scanDisk(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let request: DiskScannerRequest
        do {
            request = try ScannerServiceCodec.decode(DiskScannerRequest.self, from: requestData)
        } catch {
            reply(nil, ScannerServiceFailure.error(20, "磁盘扫描请求无法解析。"))
            return
        }
        guard begin(requestID: request.requestID, operation: .disk) else {
            reply(nil, ScannerServiceFailure.error(21, "扫描服务正在处理另一个任务。"))
            return
        }

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.worker.scanDisk(request) { [weak self] progress in
                    self?.store(progress)
                }
                let data = try ScannerServiceCodec.encode(response)
                self.finish(requestID: request.requestID)
                reply(data, nil)
            } catch is CancellationError {
                self.finish(requestID: request.requestID)
                reply(nil, ScannerServiceFailure.error(22, "磁盘扫描已取消。"))
            } catch {
                self.finish(requestID: request.requestID)
                reply(nil, ScannerServiceFailure.error(23, "磁盘扫描失败：\(error.localizedDescription)"))
            }
        }
        install(task, for: request.requestID)
    }

    func scanAgentWorkspace(
        _ requestData: Data,
        withReply reply: @escaping (Data?, NSError?) -> Void
    ) {
        let request: AgentWorkspaceScannerRequest
        do {
            request = try ScannerServiceCodec.decode(AgentWorkspaceScannerRequest.self, from: requestData)
        } catch {
            reply(nil, ScannerServiceFailure.error(30, "Agent 工作区扫描请求无法解析。"))
            return
        }
        guard begin(requestID: request.requestID, operation: .agentWorkspace) else {
            reply(nil, ScannerServiceFailure.error(31, "扫描服务正在处理另一个任务。"))
            return
        }

        let task = Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let response = try await self.worker.scanAgentWorkspace(request) { [weak self] progress in
                    self?.store(progress)
                }
                let data = try ScannerServiceCodec.encode(response)
                self.finish(requestID: request.requestID)
                reply(data, nil)
            } catch is CancellationError {
                self.finish(requestID: request.requestID)
                reply(nil, ScannerServiceFailure.error(32, "Agent 工作区扫描已取消。"))
            } catch {
                self.finish(requestID: request.requestID)
                reply(nil, ScannerServiceFailure.error(33, "Agent 工作区扫描失败：\(error.localizedDescription)"))
            }
        }
        install(task, for: request.requestID)
    }

    func progress(for requestID: String, withReply reply: @escaping (Data?) -> Void) {
        lock.lock()
        let data = progressData[requestID]
        lock.unlock()
        reply(data)
    }

    func cancel(requestID: String, withReply reply: @escaping () -> Void) {
        lock.lock()
        let task = activeRequestID == requestID ? activeTask : nil
        lock.unlock()
        task?.cancel()
        reply()
    }

    func cancelAll() {
        lock.lock()
        invalidated = true
        let task = activeTask
        activeTask = nil
        activeRequestID = nil
        progressData.removeAll(keepingCapacity: false)
        lock.unlock()
        task?.cancel()
    }

    private func begin(requestID: String, operation: ScannerOperationKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidated, activeRequestID == nil else { return false }
        activeRequestID = requestID
        progressData[requestID] = try? ScannerServiceCodec.encode(
            ScannerServiceProgress(
                requestID: requestID,
                operation: operation,
                stage: .preparing
            )
        )
        return true
    }

    private func install(_ task: Task<Void, Never>, for requestID: String) {
        lock.lock()
        let shouldCancel = invalidated || activeRequestID != requestID
        if !shouldCancel { activeTask = task }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    private func store(_ progress: ScannerServiceProgress) {
        guard let data = try? ScannerServiceCodec.encode(progress) else { return }
        lock.lock()
        if !invalidated, activeRequestID == progress.requestID {
            progressData[progress.requestID] = data
        }
        lock.unlock()
    }

    private func finish(requestID: String) {
        lock.lock()
        if activeRequestID == requestID {
            activeRequestID = nil
            activeTask = nil
        }
        progressData.removeValue(forKey: requestID)
        lock.unlock()
    }
}

private final class ScannerServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let lock = NSLock()
    private var liveConnections = 0

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let session = ScannerServiceSession()
        connection.exportedInterface = NSXPCInterface(with: CleanNestScannerXPCProtocol.self)
        connection.exportedObject = session
        lock.lock()
        liveConnections += 1
        lock.unlock()
        connection.invalidationHandler = { [weak self, weak session] in
            session?.cancelAll()
            // The scanner is intentionally disposable, but App 可能同时持有多个
            // 连接（清理/磁盘与 Agent 工作区各有独立客户端）。只有最后一条连接
            // 关闭后才退出进程，否则会腰斩其他连接上的在途扫描。
            self?.connectionDidInvalidate()
        }
        connection.interruptionHandler = { [weak session] in
            session?.cancelAll()
        }
        connection.resume()
        return true
    }

    private func connectionDidInvalidate() {
        lock.lock()
        liveConnections = max(0, liveConnections - 1)
        lock.unlock()
        // 留出短窗口：背靠背"取消→重扫"的新连接可能正在投递途中，
        // 到期时按当时的真实连接数决定，而不是按失效瞬间的快照。
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let shouldExit = self.liveConnections == 0
            self.lock.unlock()
            if shouldExit { exit(EXIT_SUCCESS) }
        }
    }
}

private let delegate = ScannerServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
