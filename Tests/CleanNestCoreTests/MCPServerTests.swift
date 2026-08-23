import Foundation
import XCTest
import CleanNestCore

final class MCPServerTests: XCTestCase {
    func testModernDiscoveryAndToolListExposeOnlyReadOnlyTools() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metrics = root.appendingPathComponent("metrics.sqlite3")
        let server = makeServer(root: root, metrics: metrics)

        let discover = try await response(
            server,
            #"{"jsonrpc":"2.0","id":1,"method":"server/discover","params":{}}"#
        )
        XCTAssertEqual(discover.objectValue?["jsonrpc"], .string("2.0"))
        XCTAssertEqual(
            discover.objectValue?["result"]?.objectValue?["supportedVersions"],
            .array([.string(ReadOnlyMCPServer.modernProtocolVersion)])
        )

        let listed = try await response(
            server,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#
        )
        let tools = try XCTUnwrap(listed.objectValue?["result"]?.objectValue?["tools"]?.arrayValue)
        let names = tools.compactMap { $0.objectValue?["name"]?.stringValue }
        XCTAssertEqual(names.count, 7)
        XCTAssertFalse(names.contains { $0.contains("delete") || $0.contains("trash") || $0.contains("terminate") || $0.contains("write") })
        for tool in tools {
            XCTAssertEqual(
                tool.objectValue?["annotations"]?.objectValue?["readOnlyHint"],
                .bool(true)
            )
            XCTAssertEqual(
                tool.objectValue?["inputSchema"]?.objectValue?["additionalProperties"],
                .bool(false)
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: metrics.path), "MCP discovery must not create the database")
    }

    func testLegacyInitializationStrictArgumentsAndOversizeLimit() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = makeServer(root: root, metrics: root.appendingPathComponent("metrics.sqlite3"))

        let initialized = try await response(
            server,
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#
        )
        XCTAssertEqual(
            initialized.objectValue?["result"]?.objectValue?["protocolVersion"],
            .string("2025-11-25")
        )

        let strict = try await response(
            server,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"cleannest.server_status","arguments":{"unexpected":true}}}"#
        )
        XCTAssertEqual(strict.objectValue?["result"]?.objectValue?["isError"], .bool(true))

        let oversized = Data(repeating: 0x20, count: ReadOnlyMCPServer.maximumMessageBytes + 1)
        let rawOutput = await server.response(to: oversized)
        let output = try XCTUnwrap(rawOutput)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: output)
        XCTAssertEqual(decoded.objectValue?["error"]?.objectValue?["code"], .number(-32600))
    }

    private func makeServer(root: URL, metrics: URL) -> ReadOnlyMCPServer {
        ReadOnlyMCPServer(
            metricsDatabaseURL: metrics,
            evidenceURL: root.appendingPathComponent("evidence.json"),
            cleanupURL: root.appendingPathComponent("cleanup.json"),
            activityURL: root.appendingPathComponent("activity.json"),
            homeDirectory: root
        )
    }

    private func response(_ server: ReadOnlyMCPServer, _ request: String) async throws -> JSONValue {
        let rawData = await server.response(to: Data(request.utf8))
        let data = try XCTUnwrap(rawData)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestMCPTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension JSONValue {
    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }
}
