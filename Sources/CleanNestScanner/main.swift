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
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        let session = ScannerServiceSession()
        connection.exportedInterface = NSXPCInterface(with: CleanNestScannerXPCProtocol.self)
        connection.exportedObject = session
        connection.invalidationHandler = { [weak session] in
            session?.cancelAll()
            // The scanner is intentionally disposable. Once its only App
            // connection closes, release the process instead of retaining an
            // idle Swift runtime and file-system buffers until memory pressure.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.05) {
                exit(EXIT_SUCCESS)
            }
        }
        connection.interruptionHandler = { [weak session] in
            session?.cancelAll()
        }
        connection.resume()
        return true
    }
}

private let delegate = ScannerServiceDelegate()
private let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
