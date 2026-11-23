import Foundation

/// Incremental, order-preserving JSON-RPC line buffering for the stdio transport.
/// An oversized line is drained to its newline without being retained in full.
public struct MCPBoundedLineBuffer {
    public static let maximumLineBytes = 1_048_576

    private var currentLine = Data()
    private var completedLines: [Data] = []
    private var oversized = false
    private var finished = false

    public init() {}

    public mutating func append(_ chunk: Data) {
        guard !finished, !chunk.isEmpty else { return }

        var segmentStart = chunk.startIndex
        while segmentStart < chunk.endIndex {
            if let newlineIndex = chunk[segmentStart...].firstIndex(of: 0x0A) {
                consume(chunk[segmentStart..<newlineIndex])
                completeLine()
                segmentStart = chunk.index(after: newlineIndex)
            } else {
                consume(chunk[segmentStart..<chunk.endIndex])
                break
            }
        }
    }

    public mutating func nextLine() -> Data? {
        guard !completedLines.isEmpty else { return nil }
        return completedLines.removeFirst()
    }

    public mutating func finish() {
        guard !finished else { return }
        finished = true
        guard oversized || !currentLine.isEmpty else { return }
        if oversized { currentLine.append(0x20) }
        completedLines.append(currentLine)
        currentLine = Data()
        oversized = false
    }

    private mutating func consume(_ bytes: Data.SubSequence) {
        guard !oversized else { return }
        let remaining = Self.maximumLineBytes - currentLine.count
        if remaining > 0 {
            currentLine.append(contentsOf: bytes.prefix(remaining))
        }
        oversized = bytes.count > remaining
    }

    private mutating func completeLine() {
        if oversized { currentLine.append(0x20) }
        completedLines.append(currentLine)
        currentLine = Data()
        oversized = false
    }
}
