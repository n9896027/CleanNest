import Foundation

public enum ScannerServiceClientError: LocalizedError, Equatable {
    case unavailable
    case interrupted
    case protocolMismatch(expected: Int, received: Int)
    case invalidResponse
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "独立扫描服务未响应；CleanNest 没有回退到主进程扫描，上一次完整结果已保留。"
        case .interrupted:
            return "独立扫描服务已中断；CleanNest 界面仍可用，上一次完整结果已保留。"
        case .protocolMismatch(let expected, let received):
            return "扫描服务协议不匹配（App \(expected)，服务 \(received)），请重新安装完整 App。"
        case .invalidResponse:
            return "独立扫描服务返回了无效结果；上一次完整结果已保留。"
        case .remote(let message):
            return message
        }
    }
}

private final class ScannerContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Value, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(with: result)
    }
}

private final class ScannerValueContinuationGate<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

/// Minimal NSXPCConnection surface used by the client. The production factory
/// still creates a real embedded-service connection; tests can substitute a
/// deterministic connection without touching user files or launchd services.
protocol ScannerServiceConnection: AnyObject {
    var interruptionHandler: (() -> Void)? { get set }
    var invalidationHandler: (() -> Void)? { get set }

    func resume()
    func invalidate()
    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any
}

extension NSXPCConnection: ScannerServiceConnection {}

private final class ScannerConnectionBox: @unchecked Sendable {
    let value: ScannerServiceConnection

    init(_ value: ScannerServiceConnection) {
        self.value = value
    }
}

public final class ScannerServiceClient: @unchecked Sendable {
    public typealias ProgressHandler = @Sendable (ScannerServiceProgress) async -> Void

    private let lock = NSLock()
    private let connectionFactory: () -> ScannerServiceConnection
    private let handshakeTimeout: TimeInterval
    private var connection: ScannerServiceConnection?

    public init() {
        handshakeTimeout = 10
        connectionFactory = {
            let connection = NSXPCConnection(serviceName: CleanNestScannerService.bundleIdentifier)
            connection.remoteObjectInterface = NSXPCInterface(with: CleanNestScannerXPCProtocol.self)
            return connection
        }
    }

    init(
        connectionFactory: @escaping () -> ScannerServiceConnection,
        handshakeTimeout: TimeInterval = 10
    ) {
        self.connectionFactory = connectionFactory
        self.handshakeTimeout = handshakeTimeout
    }

    public func scanCleanup(
        _ request: CleanupScannerRequest,
        progress: ProgressHandler? = nil
    ) async throws -> CleanupScannerResponse {
        let requestData = try ScannerServiceCodec.encode(request)
        return try await run(requestID: request.requestID, progress: progress) { proxy, reply in
            proxy.scanCleanup(requestData, withReply: reply)
        }
    }

    public func scanDisk(
        _ request: DiskScannerRequest,
        progress: ProgressHandler? = nil
    ) async throws -> DiskScannerResponse {
        let requestData = try ScannerServiceCodec.encode(request)
        return try await run(requestID: request.requestID, progress: progress) { proxy, reply in
            proxy.scanDisk(requestData, withReply: reply)
        }
    }

    public func scanSystemData(
        _ request: SystemDataScannerRequest,
        progress: ProgressHandler? = nil
    ) async throws -> SystemDataScannerResponse {
        let requestData = try ScannerServiceCodec.encode(request)
        return try await run(requestID: request.requestID, progress: progress) { proxy, reply in
            proxy.scanSystemData(requestData, withReply: reply)
        }
    }

    public func scanAgentWorkspace(
        _ request: AgentWorkspaceScannerRequest,
        progress: ProgressHandler? = nil
    ) async throws -> AgentWorkspaceScannerResponse {
        let requestData = try ScannerServiceCodec.encode(request)
        return try await run(requestID: request.requestID, progress: progress) { proxy, reply in
            proxy.scanAgentWorkspace(requestData, withReply: reply)
        }
    }

    private func run<Response: Decodable & Sendable>(
        requestID: String,
        progress: ProgressHandler?,
        invoke: @escaping (CleanNestScannerXPCProtocol, @escaping (Data?, NSError?) -> Void) -> Void
    ) async throws -> Response {
        let currentConnection = makeConnection()
        let connectionBox = ScannerConnectionBox(currentConnection)
        let pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard !Task.isCancelled,
                      let data = await self?.fetchProgress(requestID, connection: currentConnection),
                      let value = try? ScannerServiceCodec.decode(ScannerServiceProgress.self, from: data) else {
                    continue
                }
                await progress?(value)
            }
        }

        defer {
            pollingTask.cancel()
            invalidate(currentConnection)
        }

        do {
            return try await withTaskCancellationHandler {
                try await perform(Response.self, connection: currentConnection, invoke: invoke)
            } onCancel: { [weak self] in
                self?.cancel(requestID, connection: connectionBox.value)
            }
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }

    private func perform<Response: Decodable & Sendable>(
        _ responseType: Response.Type,
        connection: ScannerServiceConnection,
        invoke: @escaping (CleanNestScannerXPCProtocol, @escaping (Data?, NSError?) -> Void) -> Void
    ) async throws -> Response {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ScannerContinuationGate<Response>(continuation)
            connection.interruptionHandler = {
                gate.finish(.failure(ScannerServiceClientError.interrupted))
            }
            connection.invalidationHandler = {
                gate.finish(.failure(ScannerServiceClientError.unavailable))
            }
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                gate.finish(.failure(ScannerServiceClientError.remote(error.localizedDescription)))
            }) as? CleanNestScannerXPCProtocol else {
                gate.finish(.failure(ScannerServiceClientError.unavailable))
                return
            }

            // Bound only the service handshake. Long deep scans remain user-cancellable
            // and are never cut off by an arbitrary whole-scan deadline.
            let handshakeTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0.001, handshakeTimeout) * 1_000_000_000))
                guard !Task.isCancelled else { return }
                gate.finish(.failure(ScannerServiceClientError.unavailable))
            }
            proxy.protocolVersion { version in
                handshakeTask.cancel()
                guard version == CleanNestScannerService.protocolVersion else {
                    gate.finish(
                        .failure(
                            ScannerServiceClientError.protocolMismatch(
                                expected: CleanNestScannerService.protocolVersion,
                                received: version
                            )
                        )
                    )
                    return
                }
                invoke(proxy) { data, error in
                    if let error {
                        if error.domain == "com.zone.cleannest.scanner",
                           [12, 22, 32, 42].contains(error.code) {
                            gate.finish(.failure(CancellationError()))
                        } else {
                            gate.finish(.failure(ScannerServiceClientError.remote(error.localizedDescription)))
                        }
                        return
                    }
                    guard let data,
                          let response = try? ScannerServiceCodec.decode(responseType, from: data) else {
                        gate.finish(.failure(ScannerServiceClientError.invalidResponse))
                        return
                    }
                    gate.finish(.success(response))
                }
            }
        }
    }

    private func makeConnection() -> ScannerServiceConnection {
        let newConnection = connectionFactory()
        lock.lock()
        connection?.invalidate()
        connection = newConnection
        lock.unlock()
        newConnection.resume()
        return newConnection
    }

    private func fetchProgress(_ requestID: String, connection: ScannerServiceConnection) async -> Data? {
        await withCheckedContinuation { continuation in
            let gate = ScannerValueContinuationGate<Data?>(continuation)
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                gate.finish(nil)
            }) as? CleanNestScannerXPCProtocol else {
                gate.finish(nil)
                return
            }
            proxy.progress(for: requestID) { data in
                gate.finish(data)
            }
        }
    }

    private func cancel(_ requestID: String, connection: ScannerServiceConnection) {
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in })
            as? CleanNestScannerXPCProtocol else {
            connection.invalidate()
            return
        }
        proxy.cancel(requestID: requestID) { [weak self] in
            self?.invalidate(connection)
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.invalidate(connection)
        }
    }

    private func invalidate(_ candidate: ScannerServiceConnection) {
        lock.lock()
        if connection === candidate { connection = nil }
        lock.unlock()
        candidate.interruptionHandler = nil
        candidate.invalidationHandler = nil
        candidate.invalidate()
    }
}
