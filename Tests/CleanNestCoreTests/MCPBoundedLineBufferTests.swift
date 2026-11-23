import XCTest
@testable import CleanNestCore

final class MCPBoundedLineBufferTests: XCTestCase {
    func testCoalescedRequestsPreserveEveryLineInOrder() {
        var buffer = MCPBoundedLineBuffer()
        let lines = ["{\"id\":1}", "notification", "{\"id\":2}", "{\"id\":3}"]
        buffer.append(Data((lines.joined(separator: "\n") + "\n").utf8))

        XCTAssertEqual(drain(&buffer), lines.map { Data($0.utf8) })
        XCTAssertNil(buffer.nextLine())
    }

    func testByteByByteInputMatchesCoalescedInput() {
        let input = Data("first\nsecond\nthird".utf8)
        var coalesced = MCPBoundedLineBuffer()
        var bytewise = MCPBoundedLineBuffer()
        coalesced.append(input)
        coalesced.finish()
        for byte in input {
            bytewise.append(Data([byte]))
        }
        bytewise.finish()

        XCTAssertEqual(drain(&bytewise), drain(&coalesced))
    }

    func testOversizedLineIsBoundedAndFollowingLineSurvives() {
        var buffer = MCPBoundedLineBuffer()
        let oversized = Data(repeating: 0x61, count: MCPBoundedLineBuffer.maximumLineBytes + 32)
        buffer.append(oversized + Data("\nnext\n".utf8))

        let truncated = buffer.nextLine()
        XCTAssertEqual(truncated?.count, MCPBoundedLineBuffer.maximumLineBytes + 1)
        XCTAssertEqual(truncated?.prefix(MCPBoundedLineBuffer.maximumLineBytes), oversized.prefix(MCPBoundedLineBuffer.maximumLineBytes))
        XCTAssertEqual(truncated?.last, 0x20)
        XCTAssertEqual(buffer.nextLine(), Data("next".utf8))
        XCTAssertNil(buffer.nextLine())
    }

    func testOversizedUnterminatedLineIsBoundedAtEOF() {
        var buffer = MCPBoundedLineBuffer()
        buffer.append(Data(repeating: 0x62, count: MCPBoundedLineBuffer.maximumLineBytes + 1))
        buffer.finish()
        buffer.finish()

        XCTAssertEqual(buffer.nextLine()?.count, MCPBoundedLineBuffer.maximumLineBytes + 1)
        XCTAssertNil(buffer.nextLine())
    }

    func testExactLimitAndEmptyLinesArePreserved() {
        var buffer = MCPBoundedLineBuffer()
        let exact = Data(repeating: 0x63, count: MCPBoundedLineBuffer.maximumLineBytes)
        buffer.append(exact + Data("\n\nlast".utf8))
        buffer.finish()

        XCTAssertEqual(buffer.nextLine(), exact)
        XCTAssertEqual(buffer.nextLine(), Data())
        XCTAssertEqual(buffer.nextLine(), Data("last".utf8))
        XCTAssertNil(buffer.nextLine())
    }

    private func drain(_ buffer: inout MCPBoundedLineBuffer) -> [Data] {
        var lines: [Data] = []
        while let line = buffer.nextLine() {
            lines.append(line)
        }
        return lines
    }
}
