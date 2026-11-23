import Foundation
import CleanNestCore

@main
struct CleanNestMCPMain {
    static func main() async {
        let server = ReadOnlyMCPServer()
        let input = FileHandle.standardInput
        var buffer = MCPBoundedLineBuffer()

        while let chunk = try? input.read(upToCount: 65_536), !chunk.isEmpty {
            buffer.append(chunk)
            await processBufferedLines(from: &buffer, using: server)
        }
        buffer.finish()
        await processBufferedLines(from: &buffer, using: server)
    }

    private static func processBufferedLines(
        from buffer: inout MCPBoundedLineBuffer,
        using server: ReadOnlyMCPServer
    ) async {
        while let line = buffer.nextLine() {
            if let response = await server.response(to: line) {
                FileHandle.standardOutput.write(response)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        }
    }
}
