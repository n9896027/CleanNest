import Foundation
import CleanNestCore

@main
struct CleanNestMCPMain {
    /// 与 ReadOnlyMCPServer 的 1 MiB 消息上限一致；区别在于这里在整行进入内存
    /// 之前就截断，超限行继续排空到换行符以保持流同步，再交给服务端回标准错误。
    private static let maximumLineBytes = 1_048_576

    static func main() async {
        let server = ReadOnlyMCPServer()
        let input = FileHandle.standardInput
        while let line = readBoundedLine(from: input) {
            if let response = await server.response(to: line) {
                FileHandle.standardOutput.write(response)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        }
    }

    /// 逐块读取一行。行内容超过上限时截断并标记，继续排空到换行以保持流同步；
    /// 超限行返回时额外补一个字节，使服务端按超限消息回标准错误而非解析错误。
    /// 返回 nil 表示 EOF。
    private static func readBoundedLine(from input: FileHandle) -> Data? {
        var line = Data()
        var oversized = false
        while true {
            guard let chunk = try? input.read(upToCount: 65_536), !chunk.isEmpty else {
                // EOF：有残留内容则按最后一行处理。
                return line.isEmpty && !oversized ? nil : line
            }
            let newlineIndex = chunk.firstIndex(of: 0x0A)
            if !oversized {
                let end = newlineIndex ?? chunk.endIndex
                let remaining = maximumLineBytes - line.count
                let available = end - chunk.startIndex
                if remaining > 0 {
                    line.append(contentsOf: chunk[chunk.startIndex..<end].prefix(remaining))
                }
                oversized = available > remaining
            }
            guard let newlineIndex else { continue }
            if oversized { line.append(0x20) }
            return line
        }
    }
}
