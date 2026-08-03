import Foundation

enum LocalMLXRuntimeError: LocalizedError {
    case alreadyRunning
    case invalidExecutable
    case incompleteModel

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: return "CleanNest 已经启动了一个本机模型进程"
        case .invalidExecutable: return "所选 mlx_lm.server 不存在或不可执行"
        case .incompleteModel: return "模型目录不完整，需要 config.json 与 safetensors 权重"
        }
    }
}

@MainActor
final class LocalMLXRuntime {
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private(set) var recentLog = ""
    var onTermination: ((Int32) -> Void)?

    var ownsRunningProcess: Bool { process?.isRunning == true }

    func start(executable: URL, modelDirectory: URL, port: Int) throws {
        guard !ownsRunningProcess else { throw LocalMLXRuntimeError.alreadyRunning }
        guard executable.isFileURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw LocalMLXRuntimeError.invalidExecutable
        }

        var isDirectory: ObjCBool = false
        let modelExists = FileManager.default.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory)
        let modelFiles = (try? FileManager.default.contentsOfDirectory(atPath: modelDirectory.path)) ?? []
        guard modelDirectory.isFileURL,
              modelExists,
              isDirectory.boolValue,
              modelFiles.contains("config.json"),
              modelFiles.contains(where: { $0.hasSuffix(".safetensors") }) else {
            throw LocalMLXRuntimeError.incompleteModel
        }

        let output = Pipe()
        let errors = Pipe()
        installDrain(for: output)
        installDrain(for: errors)

        let child = Process()
        child.executableURL = executable.standardizedFileURL
        child.arguments = [
            "--model", modelDirectory.standardizedFileURL.path,
            "--host", "127.0.0.1",
            "--port", String(port),
            "--log-level", "INFO"
        ]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = output
        child.standardError = errors
        child.terminationHandler = { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.process === finished else { return }
                self.appendLog("\n模型进程已退出（状态 \(finished.terminationStatus)）。")
                self.clearProcessHandles()
                self.onTermination?(finished.terminationStatus)
            }
        }

        recentLog = ""
        process = child
        outputPipe = output
        errorPipe = errors
        do {
            try child.run()
        } catch {
            clearProcessHandles()
            throw error
        }
    }

    func stopOwnedProcess() {
        guard let process, process.isRunning else {
            clearProcessHandles()
            return
        }
        process.terminate()
    }

    func stopOwnedProcessAndWait(timeout: TimeInterval = 5) async -> Bool {
        guard let running = process, running.isRunning else {
            clearProcessHandles()
            return true
        }
        running.terminate()
        let deadline = Date().addingTimeInterval(timeout)
        while running.isRunning, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !running.isRunning
    }

    private func installDrain(for pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in self?.appendLog(text) }
        }
    }

    private func appendLog(_ text: String) {
        recentLog.append(text)
        if recentLog.count > 12_000 {
            recentLog = String(recentLog.suffix(12_000))
        }
    }

    private func clearProcessHandles() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
    }
}
