import Foundation
import XCTest
@testable import CleanNestCore

final class ScannerServiceClientTests: XCTestCase {
    func testSuccessfulResponseUsesVersionedJSONAndClosesConnection() async throws {
        let request = makeRequest()
        let response = CleanupScannerResponse(
            requestID: request.requestID,
            candidates: [],
            insights: .empty,
            session: CleanupScanSession(
                requestID: request.requestID,
                startedAt: Date(timeIntervalSince1970: 1),
                completedAt: Date(timeIntervalSince1970: 2),
                elapsedSeconds: 1,
                roots: [],
                insights: .empty,
                candidates: []
            ),
            elapsedSeconds: 1
        )
        let proxy = FakeScannerProxy()
        proxy.cleanupData = try ScannerServiceCodec.encode(response)
        let connection = FakeScannerConnection(proxy: proxy)
        let client = ScannerServiceClient { connection }

        let decoded = try await client.scanCleanup(request)

        XCTAssertEqual(decoded, response)
        XCTAssertTrue(connection.didResume)
        XCTAssertTrue(connection.didInvalidate)
    }

    func testProtocolMismatchFailsBeforeInvokingScan() async {
        let proxy = FakeScannerProxy()
        proxy.version = CleanNestScannerService.protocolVersion + 1
        let connection = FakeScannerConnection(proxy: proxy)
        let client = ScannerServiceClient { connection }

        do {
            _ = try await client.scanCleanup(makeRequest())
            XCTFail("A protocol mismatch must not invoke the scan")
        } catch {
            XCTAssertEqual(
                error as? ScannerServiceClientError,
                .protocolMismatch(
                    expected: CleanNestScannerService.protocolVersion,
                    received: CleanNestScannerService.protocolVersion + 1
                )
            )
        }
        XCTAssertEqual(proxy.cleanupCallCount, 0)
        XCTAssertTrue(connection.didInvalidate)
    }

    func testInvalidResponseDoesNotPublishPartialResult() async {
        let proxy = FakeScannerProxy()
        proxy.cleanupData = Data("not-json".utf8)
        let connection = FakeScannerConnection(proxy: proxy)
        let client = ScannerServiceClient { connection }

        do {
            _ = try await client.scanCleanup(makeRequest())
            XCTFail("Invalid JSON must not produce a response")
        } catch {
            XCTAssertEqual(error as? ScannerServiceClientError, .invalidResponse)
        }
        XCTAssertTrue(connection.didInvalidate)
    }

    func testInterruptionFinishesRequestAndClosesConnection() async {
        let proxy = FakeScannerProxy()
        proxy.holdsCleanup = true
        let connection = FakeScannerConnection(proxy: proxy)
        proxy.onCleanup = { connection.interruptionHandler?() }
        let client = ScannerServiceClient { connection }

        do {
            _ = try await client.scanCleanup(makeRequest())
            XCTFail("An interrupted connection must fail")
        } catch {
            XCTAssertEqual(error as? ScannerServiceClientError, .interrupted)
        }
        XCTAssertTrue(connection.didInvalidate)
    }

    func testInvalidationFinishesRequestAndDoesNotFallback() async {
        let proxy = FakeScannerProxy()
        proxy.holdsCleanup = true
        let connection = FakeScannerConnection(proxy: proxy)
        proxy.onCleanup = { connection.invalidationHandler?() }
        let client = ScannerServiceClient { connection }

        do {
            _ = try await client.scanCleanup(makeRequest())
            XCTFail("An invalidated connection must fail")
        } catch {
            XCTAssertEqual(error as? ScannerServiceClientError, .unavailable)
        }
        XCTAssertTrue(connection.didInvalidate)
    }

    func testCancellationReachesServiceAndReturnsCancellationError() async {
        let request = makeRequest()
        let proxy = FakeScannerProxy()
        proxy.holdsCleanup = true
        let connection = FakeScannerConnection(proxy: proxy)
        let started = expectation(description: "scan started")
        proxy.onCleanup = { started.fulfill() }
        let client = ScannerServiceClient { connection }
        let task = Task {
            try await client.scanCleanup(request)
        }

        await fulfillment(of: [started], timeout: 1)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Cancellation must not publish a completed response")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(proxy.cancelledRequestIDs, [request.requestID])
        XCTAssertTrue(connection.didInvalidate)
    }

    func testUnansweredHandshakeTimesOutWithoutInvokingScan() async {
        let proxy = FakeScannerProxy()
        proxy.holdsProtocolVersion = true
        let connection = FakeScannerConnection(proxy: proxy)
        let client = ScannerServiceClient(
            connectionFactory: { connection },
            handshakeTimeout: 0.02
        )

        do {
            _ = try await client.scanCleanup(makeRequest())
            XCTFail("An unanswered handshake must fail closed")
        } catch {
            XCTAssertEqual(error as? ScannerServiceClientError, .unavailable)
        }
        XCTAssertEqual(proxy.cleanupCallCount, 0)
        XCTAssertTrue(connection.didInvalidate)
    }

    private func makeRequest() -> CleanupScannerRequest {
        CleanupScannerRequest(
            requestID: "client-test",
            homeDirectory: URL(fileURLWithPath: "/tmp/CleanNestClientTests", isDirectory: true),
            includeApplicationCaches: false,
            includeMediaAndDuplicates: false,
            developerMode: false
        )
    }
}

private final class FakeScannerConnection: ScannerServiceConnection {
    let proxy: FakeScannerProxy
    var interruptionHandler: (() -> Void)?
    var invalidationHandler: (() -> Void)?
    private(set) var didResume = false
    private(set) var didInvalidate = false

    init(proxy: FakeScannerProxy) {
        self.proxy = proxy
    }

    func resume() {
        didResume = true
    }

    func invalidate() {
        didInvalidate = true
    }

    func remoteObjectProxyWithErrorHandler(_ handler: @escaping (Error) -> Void) -> Any {
        proxy
    }
}

private final class FakeScannerProxy: NSObject, CleanNestScannerXPCProtocol {
    var version = CleanNestScannerService.protocolVersion
    var cleanupData: Data?
    var cleanupError: NSError?
    var holdsProtocolVersion = false
    var holdsCleanup = false
    var onCleanup: (() -> Void)?
    private(set) var cleanupCallCount = 0
    private(set) var cancelledRequestIDs: [String] = []
    private var pendingCleanupReply: ((Data?, NSError?) -> Void)?

    func protocolVersion(withReply reply: @escaping (Int) -> Void) {
        if !holdsProtocolVersion { reply(version) }
    }

    func scanCleanup(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        cleanupCallCount += 1
        if holdsCleanup {
            pendingCleanupReply = reply
            onCleanup?()
            return
        }
        reply(cleanupData, cleanupError)
    }

    func scanDisk(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, nil)
    }

    func scanSystemData(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, nil)
    }

    func scanAgentWorkspace(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        reply(nil, nil)
    }

    func progress(for requestID: String, withReply reply: @escaping (Data?) -> Void) {
        reply(nil)
    }

    func cancel(requestID: String, withReply reply: @escaping () -> Void) {
        cancelledRequestIDs.append(requestID)
        pendingCleanupReply?(
            nil,
            NSError(domain: "com.zone.cleannest.scanner", code: 12)
        )
        pendingCleanupReply = nil
        reply()
    }
}
