import Foundation
import CleanNestCore

@main
struct CleanNestMCPMain {
    static func main() async {
        let server = ReadOnlyMCPServer()
        while let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8) else { continue }
            if let response = await server.response(to: data) {
                FileHandle.standardOutput.write(response)
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        }
    }
}
