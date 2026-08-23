import Darwin
import Foundation
import CleanNestCore

enum SelfTestFailure: Error, CustomStringConvertible {
    case assertion(String)

    var description: String {
        switch self {
        case .assertion(let message): return message
        }
    }
}

func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw SelfTestFailure.assertion(message) }
}

final class LiveAIResultBox: @unchecked Sendable {
    var result: Result<CleanupAIAnalysis, Error>?
}

final class LiveScanResultBox: @unchecked Sendable {
    var candidates: [CleanupCandidate]?
}

final class LiveDiskAIResultBox: @unchecked Sendable {
    var result: Result<DiskAIAnalysis, Error>?
}

final class LiveAIProbeResultBox: @unchecked Sendable {
    var result: Result<LocalAIProbeResult, Error>?
}

final class P0FoundationResultBox: @unchecked Sendable {
    var result: Result<Void, Error>?
}

func processIsAlive(_ pid: pid_t) -> Bool {
    guard pid > 1 else { return false }
    errno = 0
    if Darwin.kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

func waitForProcessExit(_ pid: pid_t, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while processIsAlive(pid), Date() < deadline {
        usleep(20_000)
    }
    return !processIsAlive(pid)
}

func runCommandRunnerTreeTerminationTest() throws {
    let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("CleanNestCommandRunner-\(UUID().uuidString)", isDirectory: true)
    let marker = temporaryRoot.appendingPathComponent("processes.txt")
    try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)

    let runner = CommandRunner()
    let unrelated = Process()
    unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
    unrelated.arguments = ["30"]
    unrelated.standardOutput = FileHandle.nullDevice
    unrelated.standardError = FileHandle.nullDevice
    unrelated.standardInput = FileHandle.nullDevice
    try unrelated.run()
    let unrelatedPID = unrelated.processIdentifier

    defer {
        runner.terminateAll()
        if unrelated.isRunning {
            unrelated.terminate()
            unrelated.waitUntilExit()
        }
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    let finished = DispatchSemaphore(value: 0)
    Task.detached {
        defer { finished.signal() }
        _ = try? await runner.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "sleep 30 & child=$!; printf '%s %s\\n' \"$$\" \"$child\" > \"$1\"; wait",
                "cleannest-command-runner-test",
                marker.path
            ]
        )
    }

    var launchedPIDs: [pid_t] = []
    let markerDeadline = Date().addingTimeInterval(3)
    while Date() < markerDeadline {
        if let contents = try? String(contentsOf: marker, encoding: .utf8) {
            launchedPIDs = contents
                .split(whereSeparator: \Character.isWhitespace)
                .compactMap { pid_t($0) }
            if launchedPIDs.count == 2 { break }
        }
        usleep(20_000)
    }
    try check(launchedPIDs.count == 2, "CommandRunner 父子进程没有按时启动")
    try check(launchedPIDs.allSatisfy(processIsAlive), "CommandRunner 测试进程在终止前已退出")
    try check(processIsAlive(unrelatedPID), "未登记的守卫进程未能启动")

    runner.terminateAll()

    try check(
        finished.wait(timeout: .now() + 3) == .success,
        "CommandRunner terminateAll 后父命令未按时结束"
    )
    for pid in launchedPIDs {
        try check(waitForProcessExit(pid, timeout: 2), "CommandRunner 遗留了 PID \(pid) 孤儿进程")
    }
    try check(
        unrelated.isRunning && processIsAlive(unrelatedPID),
        "CommandRunner terminateAll 误杀了未登记的兄弟进程"
    )
}

func launchHarmlessTestProcess(
    executable: String,
    arguments: [String]
) throws -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    return process
}

func cleanUpHarmlessTestProcess(_ process: Process) {
    guard process.isRunning else { return }
    Darwin.kill(process.processIdentifier, SIGKILL)
    process.waitUntilExit()
}

func waitForMemoryProcessSnapshot(
    inspector: ProcessMemoryInspector,
    pid: pid_t,
    timeout: TimeInterval,
    matching predicate: (MemoryProcessSnapshot) -> Bool = { _ in true }
) -> MemoryProcessSnapshot? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let snapshot = inspector.process(pid: pid), predicate(snapshot) {
            return snapshot
        }
        usleep(20_000)
    }
    return nil
}

func runProcessMemoryInspectorSafetyTest() throws {
    let memoryProbe = SystemMemoryProbe.sample()
    if let compressedBytes = memoryProbe.compressedBytes {
        try check(compressedBytes >= 0, "系统压缩内存采样不应为负数")
    } else {
        throw SelfTestFailure.assertion("系统压缩内存采样失败")
    }

    let inspector = ProcessMemoryInspector()
    guard let currentProcess = inspector.process(pid: getpid()) else {
        throw SelfTestFailure.assertion("无法采样 CleanNestSelfTest 当前进程")
    }
    try check(currentProcess.ownerUserID == UInt32(getuid()), "当前进程用户身份采样错误")
    try check(currentProcess.protectionReason != nil, "当前进程必须受到结束保护")
    try check(!currentProcess.canTerminate, "当前进程不应允许从检查器内结束")
    if case .refused = inspector.terminate(currentProcess) {
        // Expected: the inspector must reject its own process before sending a signal.
    } else {
        throw SelfTestFailure.assertion("检查器没有拒绝结束自身进程")
    }

    let ordinarySleep = try launchHarmlessTestProcess(
        executable: "/bin/sleep",
        arguments: ["30"]
    )
    defer { cleanUpHarmlessTestProcess(ordinarySleep) }
    guard let ordinarySnapshot = waitForMemoryProcessSnapshot(
        inspector: inspector,
        pid: ordinarySleep.processIdentifier,
        timeout: 2,
        matching: { $0.executablePath?.hasSuffix("/sleep") == true }
    ) else {
        throw SelfTestFailure.assertion("无法采样普通 sleep 测试进程")
    }
    try check(ordinarySnapshot.canTerminate, "当前用户启动的普通 sleep 应允许结束")

    let forgedStartMicroseconds = ordinarySnapshot.startMicroseconds == UInt64.max
        ? 0
        : ordinarySnapshot.startMicroseconds + 1
    let forgedIdentity = MemoryProcessSnapshot(
        pid: ordinarySnapshot.pid,
        parentPID: ordinarySnapshot.parentPID,
        name: ordinarySnapshot.name,
        applicationName: ordinarySnapshot.applicationName,
        executablePath: ordinarySnapshot.executablePath,
        physicalFootprintBytes: ordinarySnapshot.physicalFootprintBytes,
        residentBytes: ordinarySnapshot.residentBytes,
        ownerUserID: ordinarySnapshot.ownerUserID,
        startSeconds: ordinarySnapshot.startSeconds,
        startMicroseconds: forgedStartMicroseconds,
        purpose: ordinarySnapshot.purpose,
        terminationImpact: ordinarySnapshot.terminationImpact,
        protectionReason: ordinarySnapshot.protectionReason
    )
    try check(
        inspector.terminate(forgedIdentity) == .identityChanged,
        "伪造启动身份必须返回 identityChanged"
    )
    try check(
        ordinarySleep.isRunning && processIsAlive(ordinarySleep.processIdentifier),
        "身份不匹配时不应向目标进程发送信号"
    )

    try check(
        inspector.terminate(ordinarySnapshot) == .terminated,
        "普通 sleep 应响应正常 SIGTERM 并结束"
    )
    ordinarySleep.waitUntilExit()
    try check(!ordinarySleep.isRunning, "普通 sleep 在正常结束后仍然存活")

    let termIgnoringSleep = try launchHarmlessTestProcess(
        executable: "/bin/sh",
        arguments: ["-c", "trap '' TERM; exec /bin/sleep 30"]
    )
    defer { cleanUpHarmlessTestProcess(termIgnoringSleep) }
    guard let termIgnoringSnapshot = waitForMemoryProcessSnapshot(
        inspector: inspector,
        pid: termIgnoringSleep.processIdentifier,
        timeout: 2,
        matching: { $0.executablePath?.hasSuffix("/sleep") == true }
    ) else {
        throw SelfTestFailure.assertion("无法采样忽略 TERM 的 sleep 测试进程")
    }
    try check(termIgnoringSnapshot.canTerminate, "忽略 TERM 的测试进程应允许结束")
    try check(
        inspector.terminate(termIgnoringSnapshot) == .stillRunning,
        "普通退出不应自动升级为 SIGKILL"
    )
    try check(
        termIgnoringSleep.isRunning && processIsAlive(termIgnoringSleep.processIdentifier),
        "返回 stillRunning 时忽略 TERM 的测试进程必须仍然存活"
    )
    try check(
        inspector.terminate(termIgnoringSnapshot, force: true) == .terminated,
        "显式 force 后应结束忽略 TERM 的测试进程"
    )
    termIgnoringSleep.waitUntilExit()
    try check(!termIgnoringSleep.isRunning, "显式强制结束后测试进程仍然存活")
}

func makeDiskAIFixture(
    home: URL
) throws -> (report: DiskReport, contexts: [String: DiskAIChildContext], snapshot: DiskAIRequestSnapshot) {
    let library = home.appendingPathComponent("Library", isDirectory: true)
    let entries = [
        DiskEntry(name: "Containers", url: library.appendingPathComponent("Containers"), bytes: 92_310_000_000, isDirectory: true),
        DiskEntry(name: "Mobile Documents", url: library.appendingPathComponent("Mobile Documents"), bytes: 35_730_000_000, isDirectory: true),
        DiskEntry(name: "Application Support", url: library.appendingPathComponent("Application Support"), bytes: 33_620_000_000, isDirectory: true),
        DiskEntry(name: "Caches", url: library.appendingPathComponent("Caches"), bytes: 17_200_000_000, isDirectory: true),
        DiskEntry(name: "pnpm", url: library.appendingPathComponent("pnpm"), bytes: 2_040_000_000, isDirectory: true),
        DiskEntry(name: "越界项目", url: URL(fileURLWithPath: "/etc"), bytes: 999_000_000_000, isDirectory: true)
    ]
    let report = DiskReport(
        root: library,
        entries: entries,
        largeFiles: [],
        totalBytes: 180_900_000_000,
        totalFiles: 472_230
    )

    func context(_ parent: DiskEntry, _ rows: [(String, Int64)]) -> DiskAIChildContext {
        let children = rows.map {
            DiskEntry(
                name: $0.0,
                url: parent.url.appendingPathComponent($0.0),
                bytes: $0.1,
                isDirectory: true
            )
        }
        return DiskAIChildContext(
            entries: children,
            totalEntryCount: children.count,
            totalBytes: children.reduce(0) { $0 + $1.bytes }
        )
    }

    let contexts: [String: DiskAIChildContext] = [
        entries[0].id: context(entries[0], [
            ("com.tencent.xinWeChat", 36_866_104_000),
            ("com.docker.docker", 28_344_444_000),
            ("com.baidu.netdisk", 9_287_960_000)
        ]),
        entries[1].id: context(entries[1], [("com~apple~CloudDocs", 34_840_120_000)]),
        entries[2].id: context(entries[2], [
            ("Claude", 10_380_792_000),
            ("Google", 10_181_104_000),
            ("SolanaMemeLab", 4_105_416_000)
        ]),
        entries[3].id: context(entries[3], [
            ("Google", 2_962_760_000),
            ("ms-playwright", 1_925_552_000),
            ("Homebrew", 1_552_160_000)
        ])
    ]
    let snapshot = try DiskAIRequestBuilder.makeSnapshot(
        report: report,
        childContexts: contexts,
        homeDirectory: home
    )
    return (report, contexts, snapshot)
}

func runLiveScannerTestIfRequested() throws {
    guard ProcessInfo.processInfo.environment["CLEANNEST_LIVE_SCAN"] == "1" else { return }

    let semaphore = DispatchSemaphore(value: 0)
    let box = LiveScanResultBox()
    let startedAt = Date()
    Task.detached {
        box.candidates = await CleanupScanner().scan()
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 30) == .success,
          let candidates = box.candidates else {
        throw SelfTestFailure.assertion("真实清理扫描超过 30 秒")
    }
    let elapsed = Date().timeIntervalSince(startedAt)
    print("✓ 真实清理扫描：\(candidates.count) 项，\(String(format: "%.2f", elapsed)) 秒")
}

func runLiveModelCatalogTestIfRequested() throws {
    guard ProcessInfo.processInfo.environment["CLEANNEST_LIVE_MODEL_CATALOG"] == "1" else { return }

    let models = LocalModelCatalog().discover()
    try check(!models.isEmpty, "真实模型目录扫描没有发现完整 MLX 模型")
    for model in models {
        let quantization = model.quantization ?? "量化未知"
        print("✓ 本机模型：\(model.displayName) · \(quantization) · \(CleanNestFormatting.bytes(model.weightBytes))")
    }
}

func runLiveMLXTestIfRequested() throws {
    guard ProcessInfo.processInfo.environment["CLEANNEST_LIVE_MLX"] == "1" else { return }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let endpoint = ProcessInfo.processInfo.environment["CLEANNEST_MLX_ENDPOINT"]
        ?? "http://127.0.0.1:8080/v1"
    guard let model = ProcessInfo.processInfo.environment["CLEANNEST_MLX_MODEL"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !model.isEmpty else {
        throw SelfTestFailure.assertion(
            "CLEANNEST_LIVE_MLX=1 时必须显式设置 CLEANNEST_MLX_MODEL，测试不会替你选择模型"
        )
    }
    let candidates = [
        CleanupCandidate(name: CleanupScanner.npmCacheDisplayName, url: home.appendingPathComponent(".npm/_cacache/content-v2"), kind: .packageManager, allocatedBytes: 5_331_611_648, modifiedAt: Date().addingTimeInterval(-3 * 86_400), isRecommended: false, detail: CleanupScanner.npmCacheDetail),
        CleanupCandidate(name: "DerivedData", url: home.appendingPathComponent("Library/Developer/Xcode/DerivedData/Demo"), kind: .developer, allocatedBytes: 4_820_000_000, modifiedAt: Date().addingTimeInterval(-22 * 86_400), isRecommended: true, detail: "Xcode 可按需重建"),
        CleanupCandidate(name: "旧版安装包", url: home.appendingPathComponent("Downloads/Example.dmg"), kind: .installer, allocatedBytes: 1_430_000_000, modifiedAt: Date().addingTimeInterval(-32 * 86_400), isRecommended: true, detail: "请确认不再需要离线安装"),
        CleanupCandidate(name: "诊断日志", url: home.appendingPathComponent("Library/Logs/DiagnosticReports"), kind: .logs, allocatedBytes: 124_000_000, modifiedAt: Date().addingTimeInterval(-90 * 86_400), isRecommended: false, detail: "排查问题时可能有用")
    ]
    let snapshot = try CleanupAIRequestBuilder.makeSnapshot(
        candidates: candidates,
        diskTotalBytes: 1_000_000_000_000,
        diskFreeBytes: 300_000_000_000,
        homeDirectory: home
    )
    let semaphore = DispatchSemaphore(value: 0)
    let box = LiveAIResultBox()
    Task.detached {
        do {
            let client = try MLXOpenAIClient(endpoint: endpoint)
            box.result = .success(try await client.analyzeCleanup(snapshot: snapshot, modelID: model))
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 180) == .success else {
        throw SelfTestFailure.assertion("真实 MLX 分析超时")
    }
    guard let result = box.result else {
        throw SelfTestFailure.assertion("真实 MLX 分析没有返回结果")
    }
    let analysis = try result.get()
    try check(analysis.advice.count == candidates.count, "真实 MLX 没有覆盖全部测试候选")
    let npmID = candidates[0].id
    guard let npmReason = analysis.advice.first(where: { $0.candidateID == npmID })?.reason else {
        throw SelfTestFailure.assertion("真实 MLX 没有返回 npm 缓存说明")
    }
    let explainsDownloadSource = npmReason.contains("下载")
    let distinguishesInstalledContent = npmReason.contains("卸载")
        || npmReason.contains("已安装")
        || npmReason.contains("项目")
    try check(
        explainsDownloadSource && distinguishesInstalledContent,
        "真实 MLX 没说清 npm 缓存的下载来源与清理边界：\(npmReason)"
    )
    print("✓ npm 缓存说明：\(npmReason)")
    print("✓ 真实 MLX：\(analysis.summary)")
}

func runLiveMLXProbeIfRequested() throws {
    guard ProcessInfo.processInfo.environment["CLEANNEST_LIVE_MLX_PROBE"] == "1" else { return }

    let endpoint = ProcessInfo.processInfo.environment["CLEANNEST_MLX_ENDPOINT"]
        ?? "http://127.0.0.1:8080/v1"
    let expectedModelID = ProcessInfo.processInfo.environment["CLEANNEST_MLX_MODEL"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let semaphore = DispatchSemaphore(value: 0)
    let box = LiveAIProbeResultBox()
    Task.detached {
        do {
            let client = try MLXOpenAIClient(endpoint: endpoint)
            box.result = .success(try await client.probe())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 15) == .success else {
        throw SelfTestFailure.assertion("真实 MLX 服务检测超时")
    }
    guard let result = box.result else {
        throw SelfTestFailure.assertion("真实 MLX 服务没有返回检测结果")
    }
    let probe = try result.get()
    if let expectedModelID, !expectedModelID.isEmpty {
        try check(
            probe.listedModelID(matching: expectedModelID) != nil,
            "真实 MLX 服务没有公布预期短名：\(expectedModelID)"
        )
    }
    let defaultSuffix = probe.defaultModelID.map { "，默认 \($0)" } ?? ""
    print("✓ 真实 MLX 服务：\(probe.modelIDs.count) 个模型\(defaultSuffix)")
}

func runLiveDiskMLXTestIfRequested() throws {
    guard ProcessInfo.processInfo.environment["CLEANNEST_LIVE_DISK_MLX"] == "1" else { return }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let endpoint = ProcessInfo.processInfo.environment["CLEANNEST_MLX_ENDPOINT"]
        ?? "http://127.0.0.1:8080/v1"
    guard let model = ProcessInfo.processInfo.environment["CLEANNEST_MLX_MODEL"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !model.isEmpty else {
        throw SelfTestFailure.assertion(
            "CLEANNEST_LIVE_DISK_MLX=1 时必须显式设置 CLEANNEST_MLX_MODEL，测试不会替你选择模型"
        )
    }
    let fixture = try makeDiskAIFixture(home: home)
    let semaphore = DispatchSemaphore(value: 0)
    let box = LiveDiskAIResultBox()
    Task.detached {
        do {
            let client = try MLXOpenAIClient(endpoint: endpoint)
            box.result = .success(try await client.analyzeDisk(snapshot: fixture.snapshot, modelID: model))
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 180) == .success else {
        throw SelfTestFailure.assertion("真实磁盘 MLX 分析超时")
    }
    guard let result = box.result else {
        throw SelfTestFailure.assertion("真实磁盘 MLX 没有返回结果")
    }
    let analysis = try result.get()
    try check(analysis.advice.count == 5, "真实磁盘 MLX 没有覆盖全部测试项目")

    let byID = Dictionary(uniqueKeysWithValues: analysis.advice.map { ($0.entryID, $0) })
    let orderedEntries = fixture.report.entries.filter { $0.url.path != "/etc" }
    let containers = byID[orderedEntries[0].id]
    let mobileDocuments = byID[orderedEntries[1].id]
    let appSupport = byID[orderedEntries[2].id]
    let caches = byID[orderedEntries[3].id]
    let pnpm = byID[orderedEntries[4].id]
    try check(containers?.verdict == .keep && containers?.risk == .high, "Containers 必须高风险保留")
    try check(mobileDocuments?.verdict == .keep && mobileDocuments?.risk == .high, "Mobile Documents 必须高风险保留")
    try check(appSupport?.verdict != .likelyReclaimable && appSupport?.risk == .high, "Application Support 不能直接清理")
    try check(caches?.verdict != .likelyReclaimable && caches?.risk != .low, "Caches 顶层必须先下钻")
    try check(pnpm?.verdict != .likelyReclaimable && pnpm?.risk != .low, "pnpm 顶层必须先下钻")

    try check(analysis.summary.contains("元数据"), "磁盘 AI 安全摘要没有注明观察边界")
    for entry in orderedEntries {
        if let advice = byID[entry.id] {
            print("✓ 磁盘 AI \(entry.name)：\(advice.verdict.rawValue)/\(advice.risk.rawValue) · \(advice.explanation)")
        }
    }
    print("✓ 真实磁盘 MLX：\(analysis.summary)")
}

func runP0FoundationTests() throws {
    let bounds = CGRect(x: 0, y: 0, width: 600, height: 300)
    let placements = TreemapLayout.layout(
        items: [
            TreemapItem(id: "large", weight: 70),
            TreemapItem(id: "medium", weight: 20),
            TreemapItem(id: "small", weight: 10),
            TreemapItem(id: "ignored", weight: 0)
        ],
        in: bounds
    )
    try check(placements.count == 3, "Treemap 没有过滤零权重项目")
    try check(
        placements.allSatisfy { bounds.contains($0.rect) && $0.rect.width > 0 && $0.rect.height > 0 },
        "Treemap 生成了越界或空矩形"
    )

    let semaphore = DispatchSemaphore(value: 0)
    let box = P0FoundationResultBox()
    Task.detached {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CleanNestP0SelfTest-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }

            let metricsURL = root.appendingPathComponent("metrics.sqlite3")
            let metrics = MetricsStore(databaseURL: metricsURL)
            try await metrics.prepare()
            let sample = MetricSample(
                sampledAt: Date(),
                healthScore: 91,
                cpuUsage: 20,
                memoryUsedPercent: 50,
                memoryPressureLevel: .normal,
                memoryUsedBytes: 5,
                memoryAvailableBytes: 5,
                memoryCompressedBytes: 1,
                memorySwapUsedBytes: 0,
                diskUsedPercent: 60,
                diskFreeBytes: 10,
                batteryLevel: 80,
                temperatureCelsius: 42,
                processCount: 100
            )
            try await metrics.append(sample)
            let latestSample = try await metrics.latest()
            try check(
                latestSample?.cpuUsage == sample.cpuUsage
                    && latestSample?.memoryPressureLevel == sample.memoryPressureLevel
                    && abs((latestSample?.sampledAt.timeIntervalSince(sample.sampledAt)) ?? 1) < 0.001,
                "SQLite 指标往返不一致"
            )

            let cancellationRoot = root.appendingPathComponent("cancel-scan", isDirectory: true)
            for index in 0..<80 {
                try FileManager.default.createDirectory(
                    at: cancellationRoot.appendingPathComponent("item-\(index)", isDirectory: true),
                    withIntermediateDirectories: true
                )
            }
            let scanTask = Task {
                try await NativeDiskAnalyzer().analyze(root: cancellationRoot, progress: nil)
            }
            scanTask.cancel()
            do {
                _ = try await scanTask.value
                throw SelfTestFailure.assertion("取消后的磁盘扫描仍返回了完整结果")
            } catch is CancellationError {
                // Expected: cancellation propagates into the detached worker.
            }

            let cache = root.appendingPathComponent("Library/Caches/npm/_cacache/content-v2", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 64).write(to: cache.appendingPathComponent("package.tgz"))
            let diskEntry = DiskEntry(name: "content-v2", url: cache, bytes: 64, isDirectory: true)
            let diskReport = DiskReport(root: root, entries: [diskEntry], largeFiles: [], totalBytes: 64, totalFiles: 1)
            let evidence = try await DiskEvidenceIndexer().build(report: diskReport, homeDirectory: root)
            guard let evidenceItem = evidence.entries.first else {
                throw SelfTestFailure.assertion("磁盘证据没有返回条目")
            }
            try check(evidenceItem.category == .cache, "npm content-v2 没有识别为缓存")
            try check(evidenceItem.cleanupBoundary == .reviewable, "缓存没有保留逐项复核边界")
            try check(!evidenceItem.relativeHint.contains(root.path), "磁盘证据泄露了绝对测试主目录")

            let project = root.appendingPathComponent("Documents/Project", isDirectory: true)
            let buildDirectory = project.appendingPathComponent(".build", isDirectory: true)
            try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
            try "// package".write(
                to: project.appendingPathComponent("Package.swift"),
                atomically: true,
                encoding: .utf8
            )
            let generatedPolicy = DiskAISafetyPolicy.policy(for: buildDirectory, homeDirectory: root)
            try check(
                generatedPolicy.category == .developerArtifacts
                    && generatedPolicy.boundary == .reviewable,
                "有 Package.swift 证据的 .build 没有识别为可重建开发产物"
            )

            let evidenceURL = root.appendingPathComponent("disk-evidence.json")
            try DiskEvidencePersistence.save(evidence, to: evidenceURL)
            let server = ReadOnlyMCPServer(
                metricsDatabaseURL: metricsURL,
                evidenceURL: evidenceURL,
                cleanupURL: root.appendingPathComponent("cleanup.json"),
                activityURL: root.appendingPathComponent("activity.json"),
                homeDirectory: root
            )
            let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}}}"#
            guard let response = await server.response(to: Data(request.utf8)),
                  let responseText = String(data: response, encoding: .utf8) else {
                throw SelfTestFailure.assertion("只读 MCP 没有返回工具列表")
            }
            try check(responseText.contains("cleannest.metric_history"), "MCP 缺少历史指标工具")
            try check(responseText.contains("cleannest.disk_evidence"), "MCP 缺少磁盘证据工具")
            try check(!responseText.contains("cleannest.delete"), "MCP 暴露了写入或删除工具")
            box.result = .success(())
        } catch {
            box.result = .failure(error)
        }
        semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + 20) == .success else {
        throw SelfTestFailure.assertion("P0 基础能力自检超时")
    }
    guard let result = box.result else {
        throw SelfTestFailure.assertion("P0 基础能力自检没有结果")
    }
    try result.get()
}

func runLocalModelCatalogTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CleanNestModelCatalog-\(UUID().uuidString)", isDirectory: true)
    let modelRoot = root.appendingPathComponent("Qwen-Test-4bit", isDirectory: true)
    let incompleteRoot = root.appendingPathComponent("Incomplete", isDirectory: true)
    let unsupportedRoot = root.appendingPathComponent("Whisper-Test", isDirectory: true)
    try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: incompleteRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unsupportedRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let config = #"{"architectures":["QwenTestForCausalLM"],"model_type":"qwen_test","_name_or_path":"example/Qwen-Test","quantization":{"bits":4}}"#
    try config.write(
        to: modelRoot.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    try Data(repeating: 0, count: 128).write(
        to: modelRoot.appendingPathComponent("model-00001-of-00001.safetensors")
    )
    try "{}".write(
        to: incompleteRoot.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    try #"{"model_type":"whisper"}"#.write(
        to: unsupportedRoot.appendingPathComponent("config.json"),
        atomically: true,
        encoding: .utf8
    )
    try Data([0]).write(to: unsupportedRoot.appendingPathComponent("weights.safetensors"))

    let catalog = LocalModelCatalog(maximumVisitedDirectories: 20, maximumModels: 8, maximumDepth: 2)
    let models = catalog.discover(homeDirectory: root, roots: [root])
    try check(models.count == 1, "模型目录扫描没有排除不完整或非文本生成模型")
    guard let model = models.first else {
        throw SelfTestFailure.assertion("模型目录扫描没有返回完整模型")
    }
    try check(model.displayName == "Qwen-Test-4bit", "模型显示名称不正确")
    try check(model.architecture == "QwenTestForCausalLM", "模型架构元数据没有解析")
    try check(model.quantization == "4-bit", "模型量化位数没有解析")
    try check(model.weightBytes == 128, "模型权重大小没有汇总")
    try check(model.matches(serviceModelID: model.path), "模型服务绝对路径没有匹配")
    try check(model.matches(serviceModelID: "example/Qwen-Test"), "模型仓库别名没有匹配")
    try check(!model.matches(serviceModelID: "other/model"), "模型服务错误匹配了其他模型")
    try check(LocalAIHealthStatus.isReady("healthy"), "oMLX healthy 健康状态没有被接受")
    let omlxProbe = LocalAIProbeResult(
        modelIDs: ["Qwen3.8-27B-Uncensored-8bit", "z-lab--Qwen3.8-27B-DFlash2"],
        defaultModelID: "Qwen3.8-27B-Uncensored-8bit"
    )
    try check(
        omlxProbe.resolvedModelID(preferredModelID: nil, selectedLocalModel: nil)
            == "Qwen3.8-27B-Uncensored-8bit",
        "oMLX 默认短名没有被解析"
    )
    try check(
        omlxProbe.resolvedModelID(preferredModelID: "/Users/example/model", selectedLocalModel: model) == nil,
        "无效的显式文件路径不应静默切换到其他服务模型"
    )
}

func runEvolutionMemoryTests() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("CleanNestEvolution-\(UUID().uuidString)", isDirectory: true)
    let memoryURL = root.appendingPathComponent("evolution-memory.json")
    let privatePath = root.appendingPathComponent("Library/Caches/content-v2", isDirectory: true)
    let candidate = CleanupCandidate(
        name: "content-v2",
        url: privatePath,
        kind: .packageManager,
        allocatedBytes: 5_330_000_000,
        modifiedAt: Date(),
        isRecommended: false,
        detail: "npm 下载内容缓存"
    )
    defer { try? FileManager.default.removeItem(at: root) }

    var memory = EvolutionMemory()
    memory.recordCleanup(candidate, decision: .preferKeep)
    try check(memory.cleanupPreference(for: candidate) == .preferKeep, "本机学习没有记住明确保留偏好")
    memory.recordCleanup(candidate, decision: .cleaned)
    try check(memory.successfulCleanupCount == 1, "本机学习没有记录成功清理")
    try check(memory.cleanupPreference(for: candidate) == .preferKeep, "安全清理记录不应覆盖用户的明确保留偏好")

    memory.clearExplicitPreference(for: candidate)
    try check(memory.cleanupPreference(for: candidate) == .preferCleanup, "撤销明确偏好后应保留成功清理证据")
    try check(memory.events.first?.title == "已撤销清理偏好", "撤销清理偏好没有留下可审计记录")
    memory.recordModelFeedback(
        modelID: "/Users/private-selftest/models/Qwen-27B",
        displayName: "Qwen 27B",
        helpful: true,
        scope: "清理建议"
    )
    memory.recordModelFeedback(
        modelID: "/Users/private-selftest/models/Qwen-27B",
        displayName: "Qwen 27B",
        helpful: false,
        scope: "磁盘解读"
    )
    try check(memory.modelFeedbackCount == 2, "本机学习没有汇总模型评价")
    try check(memory.sortedModelSignals.first?.helpfulRatio == 0.5, "模型有效率计算错误")

    try EvolutionMemoryPersistence.save(memory, to: memoryURL)
    let persistedText = try String(contentsOf: memoryURL, encoding: .utf8)
    try check(!persistedText.contains(root.path), "本机学习文件泄露了清理项完整路径")
    try check(!persistedText.contains("/Users/private-selftest"), "本机学习文件泄露了模型完整路径")

    let loaded = try EvolutionMemoryPersistence.load(from: memoryURL)
    try check(loaded.cleanupPreference(for: candidate) == .preferCleanup, "本机学习偏好持久化往返失败")
    try check(loaded.modelFeedbackCount == 2, "模型评价持久化往返失败")
}

func runAppUpdatePolicyTests() throws {
    guard let current = SemanticVersion(parsing: "0.4.0"),
          let next = SemanticVersion(parsing: "v0.4.1+universal"),
          let releaseCandidate2 = SemanticVersion(parsing: "1.0.0-rc.2"),
          let releaseCandidate10 = SemanticVersion(parsing: "1.0.0-rc.10"),
          let final = SemanticVersion(parsing: "1.0.0") else {
        throw SelfTestFailure.assertion("版本号解析失败")
    }
    try check(current < next, "补丁版本比较错误")
    try check(releaseCandidate2 < releaseCandidate10, "预发布数字标识比较错误")
    try check(releaseCandidate10 < final, "正式版本应高于预发布版本")
    try check(SemanticVersion(parsing: "main") == nil, "分支名不应被识别为版本号")

    let releaseJSON = """
    {
      "tag_name": "v0.4.1",
      "name": "CleanNest v0.4.1",
      "body": "安全更新。",
      "html_url": "https://github.com/n9896027/CleanNest/releases/tag/v0.4.1",
      "draft": false,
      "prerelease": false,
      "published_at": "2026-08-23T12:00:00Z"
    }
    """
    let release = try GitHubReleaseParser.parse(
        data: Data(releaseJSON.utf8),
        owner: "n9896027",
        repository: "CleanNest"
    )
    try check(release.version.description == "0.4.1", "GitHub Release 版本解析错误")
    let updateDecision = try AppUpdatePolicy.decision(
        localVersion: "0.4.0",
        release: release
    )
    try check(
        updateDecision == .updateAvailable,
        "旧版本没有识别出可用更新"
    )

    let redirectedJSON = releaseJSON.replacingOccurrences(
        of: "https://github.com/n9896027/CleanNest/releases/tag/v0.4.1",
        with: "https://example.com/n9896027/CleanNest/releases/tag/v0.4.1"
    )
    do {
        _ = try GitHubReleaseParser.parse(
            data: Data(redirectedJSON.utf8),
            owner: "n9896027",
            repository: "CleanNest"
        )
        throw SelfTestFailure.assertion("更新检查接受了非官方发布地址")
    } catch GitHubReleaseParsingError.untrustedReleaseURL {
        // Expected: only the official repository's HTTPS release page may be opened.
    }
}

do {
    let candidates = EngineLocator.candidates(customPath: "/tmp/custom-mo")
    try check(candidates.first?.path == "/tmp/custom-mo", "自定义引擎路径没有最高优先级")

    let statusJSON = """
    {
      "host": "MacBook-Pro",
      "procs": 1280,
      "health_score": 92,
      "cpu": {"usage": 45.2, "logical_cpu": 8},
      "memory": {
        "total": 24000000000,
        "used": 14000000000,
        "available": 10000000000,
        "cached": 4200000000,
        "used_percent": 58.4,
        "swap_used": 640000000,
        "swap_total": 4000000000,
        "pressure": "normal"
      },
      "disks": [{"used_percent": 67.2, "free": 156000000000}],
      "batteries": [{
        "percent": 80,
        "status": "AC",
        "health": "Good",
        "cycle_count": 61,
        "capacity": 100
      }],
      "battery": {"level": 12, "status": "discharging"},
      "thermal": {"cpu_temp": 0, "gpu_temp": 0, "battery_temp": 30.4},
      "uptime": "3d 12h"
    }
    """
    let snapshot = try MoleJSONDecoder.systemSnapshot(from: Data(statusJSON.utf8))
    try check(snapshot.host == "MacBook-Pro", "状态 JSON 主机名解析失败")
    try check(snapshot.healthScore == 92, "状态 JSON 健康分解析失败")
    try check(snapshot.cpuUsage == 45.2, "状态 JSON CPU 解析失败")
    try check(snapshot.memoryUsedPercent == 58.4, "状态 JSON 内存解析失败")
    try check(snapshot.memoryAvailableBytes == 10_000_000_000, "状态 JSON 可用内存解析失败")
    try check(snapshot.memoryCachedBytes == 4_200_000_000, "状态 JSON 缓存内存解析失败")
    try check(snapshot.memorySwapUsedBytes == 640_000_000, "状态 JSON 交换空间解析失败")
    try check(snapshot.memorySwapTotalBytes == 4_000_000_000, "状态 JSON 交换空间总量解析失败")
    try check(snapshot.memoryPressureLevel == .normal, "状态 JSON 内存压力解析失败")
    try check(snapshot.processCount == 1_280, "状态 JSON 进程数解析失败")
    try check(snapshot.diskFreeBytes == 156_000_000_000, "状态 JSON 磁盘解析失败")
    try check(snapshot.batteryLevel == 80, "状态 JSON batteries 数组电量解析失败")
    try check(
        snapshot.batteryStatus == "已连接电源 · 健康良好 · 最大容量 100% · 61 次循环",
        "状态 JSON 电池状态中文解释失败"
    )
    try check(snapshot.temperatureCelsius == 30.4, "状态 JSON 电池温度解析失败")
    try check(snapshot.temperatureSource == "电池温度", "状态 JSON 温度来源解析失败")

    let legacyBatteryJSON = """
    {
      "batteries": [],
      "battery": {"level": 42, "status": "charging", "temperature": 31.5}
    }
    """
    let legacyBattery = try MoleJSONDecoder.systemSnapshot(from: Data(legacyBatteryJSON.utf8))
    try check(legacyBattery.batteryLevel == 42, "空 batteries 数组没有回退旧 battery 字段")
    try check(legacyBattery.batteryStatus == "正在充电", "旧 battery 状态没有中文化")
    try check(legacyBattery.temperatureCelsius == 31.5, "旧 battery 温度解析失败")
    try check(legacyBattery.temperatureSource == "电池温度", "旧 battery 温度来源解析失败")

    let legacyPowerJSON = """
    {
      "power": {"percent": 73, "state": "not charging", "health": "Check Battery"},
      "temperature": {"celsius": 44.5}
    }
    """
    let legacyPower = try MoleJSONDecoder.systemSnapshot(from: Data(legacyPowerJSON.utf8))
    try check(legacyPower.batteryLevel == 73, "旧 power 电量解析失败")
    try check(
        legacyPower.batteryStatus == "已连接电源，暂未充电 · 建议检修",
        "旧 power 状态或健康度中文化失败"
    )
    try check(legacyPower.temperatureCelsius == 44.5, "旧 temperature.celsius 解析失败")
    try check(legacyPower.temperatureSource == "设备温度", "旧 temperature 来源解析失败")

    let invalidTemperatureJSON = """
    {"thermal": {"cpu_temp": 0, "gpu_temp": -2, "battery_temp": 150}}
    """
    let invalidTemperature = try MoleJSONDecoder.systemSnapshot(from: Data(invalidTemperatureJSON.utf8))
    try check(invalidTemperature.temperatureCelsius == nil, "无效温度不应显示")
    try check(invalidTemperature.temperatureSource == nil, "无效温度不应声明来源")

    let cpuTemperatureJSON = """
    {"thermal": {"cpu_temp": 72.5, "gpu_temp": 61, "battery_temp": 30.2}}
    """
    let cpuTemperature = try MoleJSONDecoder.systemSnapshot(from: Data(cpuTemperatureJSON.utf8))
    try check(cpuTemperature.temperatureCelsius == 72.5, "有效 CPU 温度没有优先使用")
    try check(cpuTemperature.temperatureSource == "CPU 温度", "CPU 温度来源解析失败")
    let memoryAnalysis = MemoryAnalyzer.analyze(snapshot: snapshot, processes: [])
    try check(memoryAnalysis.level == .normal, "内存分析没有采用压力等级")
    try check(memoryAnalysis.detail.contains("无需为了降低"), "正常内存中文解释不清晰")
    try check(memoryAnalysis.notes.contains { $0.contains("交换空间") }, "内存分析没有解释交换空间")

    let diskJSON = """
    {
      "path": "/tmp/demo",
      "entries": [
        {"name":"Small", "path":"/tmp/demo/small", "size":10, "is_dir":true},
        {"name":"Large", "path":"/tmp/demo/large", "size":90, "is_dir":true}
      ],
      "large_files": [],
      "total_size": 100,
      "total_files": 2
    }
    """
    let report = try MoleJSONDecoder.diskReport(
        from: Data(diskJSON.utf8),
        fallbackRoot: URL(fileURLWithPath: "/tmp")
    )
    try check(report.entries.map(\.name) == ["Large", "Small"], "磁盘项目没有按大小排序")
    try check(report.totalBytes == 100, "磁盘总量解析失败")

    let localAIEndpoint = try LocalAIEndpoint(rawValue: "http://127.0.0.1:8080/v1")
    try check(localAIEndpoint.port == 8080, "本机 AI 回环地址解析失败")
    do {
        _ = try LocalAIEndpoint(rawValue: "https://example.com/v1")
        throw SelfTestFailure.assertion("本机 AI 不应接受公网地址")
    } catch LocalAIError.invalidEndpoint {
        // Expected: local analysis cannot be redirected to a remote host.
    }

    try runCommandRunnerTreeTerminationTest()
    try runProcessMemoryInspectorSafetyTest()
    try runP0FoundationTests()
    try runLocalModelCatalogTests()
    try runEvolutionMemoryTests()
    try runAppUpdatePolicyTests()

    let privateHome = URL(fileURLWithPath: "/Users/private-selftest", isDirectory: true)

    let homePrivacy = DiskPrivacyPolicy.assessTraversal(root: privateHome, homeDirectory: privateHome)
    try check(
        homePrivacy.sensitiveAreas == DiskPrivacySensitiveArea.allCases,
        "从主目录遍历应覆盖全部隐私目录"
    )
    let libraryPrivacy = DiskPrivacyPolicy.assessTraversal(
        root: privateHome.appendingPathComponent("Library", isDirectory: true),
        homeDirectory: privateHome
    )
    try check(
        libraryPrivacy.sensitiveAreas == DiskPrivacySensitiveArea.allCases,
        "从 Library 遍历应覆盖全部隐私目录"
    )
    for area in DiskPrivacySensitiveArea.allCases {
        let nestedRoot = privateHome
            .appendingPathComponent(area.rawValue, isDirectory: true)
            .appendingPathComponent("Nested", isDirectory: true)
        let nestedPrivacy = DiskPrivacyPolicy.assessTraversal(root: nestedRoot, homeDirectory: privateHome)
        try check(
            nestedPrivacy.sensitiveAreas == [area],
            "隐私目录内部路径分类错误：\(area.rawValue)"
        )
    }
    let ordinaryCachesPrivacy = DiskPrivacyPolicy.assessTraversal(
        root: privateHome.appendingPathComponent("Library/Caches", isDirectory: true),
        homeDirectory: privateHome
    )
    try check(
        !ordinaryCachesPrivacy.mayRequireFullDiskAccess && ordinaryCachesPrivacy.sensitiveAreas.isEmpty,
        "普通 Library/Caches 不应被当成 FDA 隐私目录"
    )
    let similarlyNamedPrivacy = DiskPrivacyPolicy.assessTraversal(
        root: privateHome.appendingPathComponent("Library/ContainersBackup", isDirectory: true),
        homeDirectory: privateHome
    )
    try check(similarlyNamedPrivacy.sensitiveAreas.isEmpty, "目录名前缀不应误命中 Containers")
    let externalPrivacy = DiskPrivacyPolicy.assessTraversal(
        root: URL(fileURLWithPath: "/Volumes/ExternalDisk/Library/Containers", isDirectory: true),
        homeDirectory: privateHome
    )
    try check(externalPrivacy.sensitiveAreas.isEmpty, "外接盘同名目录不应被当成用户 Library 隐私目录")

    let privacySymlinkRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("CleanNestPrivacy-\(UUID().uuidString)", isDirectory: true)
    let privacyHome = privacySymlinkRoot.appendingPathComponent("home", isDirectory: true)
    let privacyContainers = privacyHome.appendingPathComponent("Library/Containers", isDirectory: true)
    let privacyCaches = privacyHome.appendingPathComponent("Library/Caches", isDirectory: true)
    let privacyExternal = privacySymlinkRoot.appendingPathComponent("external", isDirectory: true)
    try FileManager.default.createDirectory(at: privacyContainers, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: privacyCaches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: privacyExternal, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: privacySymlinkRoot) }

    let linkIntoContainers = privacyExternal.appendingPathComponent("containers-link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkIntoContainers, withDestinationURL: privacyContainers)
    let linkedPrivacy = DiskPrivacyPolicy.assessTraversal(root: linkIntoContainers, homeDirectory: privacyHome)
    try check(linkedPrivacy.sensitiveAreas == [.containers], "指向 Containers 的软链接必须保持隐私分类")

    let linkOutOfContainers = privacyContainers.appendingPathComponent("external-link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkOutOfContainers, withDestinationURL: privacyExternal)
    let conservativeLinkedPrivacy = DiskPrivacyPolicy.assessTraversal(
        root: linkOutOfContainers,
        homeDirectory: privacyHome
    )
    try check(
        conservativeLinkedPrivacy.sensitiveAreas == [.containers],
        "隐私目录内的软链接不应绕过词法路径保护"
    )

    try check(FullDiskAccessProbeResult.classify(errno: 0) == .accessible, "成功访问应分类为 accessible")
    try check(FullDiskAccessProbeResult.classify(errno: EACCES) == .permissionDenied, "EACCES 应分类为 permissionDenied")
    try check(FullDiskAccessProbeResult.classify(errno: EPERM) == .permissionDenied, "EPERM 应分类为 permissionDenied")
    for code in [ENOENT, ENOTDIR, EIO, EROFS] {
        try check(
            FullDiskAccessProbeResult.classify(errno: code) == .indeterminate,
            "errno \(code) 不应被误报为 FDA 权限拒绝"
        )
    }
    try check(FullDiskAccessProbeResult.classify(error: nil) == .accessible, "无错误的访问结果应为 accessible")
    try check(
        FullDiskAccessProbeResult.classify(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        ) == .permissionDenied,
        "Foundation POSIX 权限错误分类失败"
    )
    try check(
        FullDiskAccessProbeResult.classify(
            error: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))
        ) == .indeterminate,
        "Foundation 目标不存在错误不应误报权限拒绝"
    )

    let diskAIFixture = try makeDiskAIFixture(home: privateHome)
    let diskAISnapshot = diskAIFixture.snapshot
    try check(diskAISnapshot.requestedCount == 5, "磁盘 AI 不应包含越界项目")
    try check(diskAISnapshot.deepSampledCount == 4, "磁盘 AI 没有记录深度采样目录")
    try check(!diskAISnapshot.payloadJSON.contains(privateHome.path), "磁盘 AI 请求泄露了绝对主目录")
    try check(!diskAISnapshot.payloadJSON.contains("/etc"), "磁盘 AI 请求包含根目录之外的项目")
    try check(diskAISnapshot.payloadJSON.contains("com.tencent.xinWeChat"), "磁盘 AI 请求没有包含实际子项构成")

    let containersPolicy = DiskAISafetyPolicy.policy(
        for: privateHome.appendingPathComponent("Library/Containers"),
        homeDirectory: privateHome
    )
    let mobileDocumentsPolicy = DiskAISafetyPolicy.policy(
        for: privateHome.appendingPathComponent("Library/Mobile Documents"),
        homeDirectory: privateHome
    )
    let appSupportPolicy = DiskAISafetyPolicy.policy(
        for: privateHome.appendingPathComponent("Library/Application Support"),
        homeDirectory: privateHome
    )
    let cachesPolicy = DiskAISafetyPolicy.policy(
        for: privateHome.appendingPathComponent("Library/Caches"),
        homeDirectory: privateHome
    )
    let pnpmPolicy = DiskAISafetyPolicy.policy(
        for: privateHome.appendingPathComponent("Library/pnpm"),
        homeDirectory: privateHome
    )
    try check(containersPolicy.boundary == .protected && containersPolicy.minimumRisk == .high, "Containers 安全下限错误")
    try check(mobileDocumentsPolicy.boundary == .protected && mobileDocumentsPolicy.minimumRisk == .high, "Mobile Documents 安全下限错误")
    try check(appSupportPolicy.boundary == .inspectOnly && appSupportPolicy.minimumRisk == .high, "Application Support 安全下限错误")
    try check(cachesPolicy.boundary == .inspectOnly && cachesPolicy.minimumRisk == .medium, "Caches 顶层安全下限错误")
    try check(pnpmPolicy.boundary == .inspectOnly && pnpmPolicy.minimumRisk == .medium, "pnpm 顶层安全下限错误")

    let symlinkHome = FileManager.default.temporaryDirectory
        .appendingPathComponent("CleanNestDiskAISymlink-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: symlinkHome) }
    let symlinkCaches = symlinkHome.appendingPathComponent("Library/Caches", isDirectory: true)
    let symlinkDocuments = symlinkHome.appendingPathComponent("Documents", isDirectory: true)
    try FileManager.default.createDirectory(at: symlinkCaches, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: symlinkDocuments, withIntermediateDirectories: true)
    let protectedLink = symlinkCaches.appendingPathComponent("looks-like-cache", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: protectedLink, withDestinationURL: symlinkDocuments)
    let protectedLinkPolicy = DiskAISafetyPolicy.policy(for: protectedLink, homeDirectory: symlinkHome)
    try check(
        protectedLinkPolicy.category == .userContent
            && protectedLinkPolicy.boundary == .protected
            && protectedLinkPolicy.minimumRisk == .high,
        "指向用户文档的缓存软链接不应被判为低风险"
    )

    let diskAIResponse = """
    {
      "schema_version": 1,
      "summary": "这是基于当前层级及直接子项元数据的用途推断；空间主要由应用沙盒、云端文档、应用支持数据和多类缓存构成。",
      "items": [
        {"token":"d0001","category":"app_sandbox_data","confidence":"high","verdict":"keep","risk":"high","priority":1,"suggestion":"clean_in_owner_app","explanation":"应用私有沙盒，样本主要来自微信、Docker 和百度网盘，常见内容包括数据库、容器镜像及用户资料。"},
        {"token":"d0002","category":"cloud_documents","confidence":"high","verdict":"keep","risk":"high","priority":2,"suggestion":"keep","explanation":"云端同步文件，样本主要由 iCloud Drive 文档构成，并可能在多台设备间保持一致。"},
        {"token":"d0003","category":"app_support_data","confidence":"high","verdict":"review","risk":"high","priority":1,"suggestion":"inspect_further","explanation":"应用支持数据主要来自 Claude、Google 等应用，常见内容包括模型、数据库、配置与用户资料。"},
        {"token":"d0004","category":"cache","confidence":"high","verdict":"review","risk":"medium","priority":1,"suggestion":"inspect_further","explanation":"多个应用的缓存集合，样本包括 Google、Playwright 和 Homebrew 产生的数据。"},
        {"token":"d0005","category":"package_manager_data","confidence":"high","verdict":"review","risk":"medium","priority":2,"suggestion":"inspect_further","explanation":"pnpm 的混合数据区，常见构成包括依赖存储、工具运行时和全局包。"}
      ],
      "cautions": ["以上仅依据名称、体积和目录层级推断，没有读取文件内容。"]
    }
    """
    let diskAIAnalysis = try DiskAIResponseValidator.validate(
        content: diskAIResponse,
        snapshot: diskAISnapshot,
        modelID: "/local/model"
    )
    try check(diskAIAnalysis.advice.count == 5, "磁盘 AI 响应没有覆盖所有项目")
    try check(
        diskAIAnalysis.advice.contains { $0.entryID == diskAIFixture.report.entries[0].id },
        "磁盘 AI token 没有映回原始目录"
    )

    let categoryMismatchDiskAIResponse = diskAIResponse.replacingOccurrences(
        of: "\"category\":\"app_sandbox_data\"",
        with: "\"category\":\"cache\"",
        options: [],
        range: diskAIResponse.range(of: "\"category\":\"app_sandbox_data\"")
    )
    let categoryMismatchAnalysis = try DiskAIResponseValidator.validate(
        content: categoryMismatchDiskAIResponse,
        snapshot: diskAISnapshot,
        modelID: "/local/model"
    )
    let categoryMismatchAdvice = categoryMismatchAnalysis.advice.first {
        $0.entryID == diskAIFixture.report.entries[0].id
    }
    try check(
        categoryMismatchAdvice?.category == .appSandboxData
            && categoryMismatchAdvice?.confidence == .low,
        "模型用途分类冲突时必须采用本机分类并降低置信度"
    )
    try check(
        categoryMismatchAnalysis.cautions.contains { $0.contains("1 项") && $0.contains("本机安全规则") },
        "用途分类冲突应显示本机保守修正提示"
    )

    let unsafeDiskAIResponse = diskAIResponse
        .replacingOccurrences(of: "\"verdict\":\"keep\",\"risk\":\"high\"", with: "\"verdict\":\"likely_reclaimable\",\"risk\":\"low\"", options: [], range: diskAIResponse.range(of: "\"verdict\":\"keep\",\"risk\":\"high\""))
    let unsafeDiskAIAnalysis = try DiskAIResponseValidator.validate(
        content: unsafeDiskAIResponse,
        snapshot: diskAISnapshot,
        modelID: "/local/model"
    )
    let reconciledContainers = unsafeDiskAIAnalysis.advice.first {
        $0.entryID == diskAIFixture.report.entries[0].id
    }
    try check(
        reconciledContainers?.category == .appSandboxData
            && reconciledContainers?.verdict == .keep
            && reconciledContainers?.risk == .high
            && reconciledContainers?.suggestion == .cleanInOwnerApp
            && reconciledContainers?.confidence == .low,
        "模型把 Containers 标为低风险候选时必须自动恢复本机保护结论"
    )

    let unsafeInspectOnlyDiskAIResponse = diskAIResponse.replacingOccurrences(
        of: "\"category\":\"app_support_data\",\"confidence\":\"high\",\"verdict\":\"review\",\"risk\":\"high\",\"priority\":1,\"suggestion\":\"inspect_further\"",
        with: "\"category\":\"cache\",\"confidence\":\"high\",\"verdict\":\"likely_reclaimable\",\"risk\":\"low\",\"priority\":1,\"suggestion\":\"review_for_cleanup\""
    )
    let unsafeInspectOnlyAnalysis = try DiskAIResponseValidator.validate(
        content: unsafeInspectOnlyDiskAIResponse,
        snapshot: diskAISnapshot,
        modelID: "/local/model"
    )
    let reconciledAppSupport = unsafeInspectOnlyAnalysis.advice.first {
        $0.entryID == diskAIFixture.report.entries[2].id
    }
    try check(
        reconciledAppSupport?.category == .appSupportData
            && reconciledAppSupport?.verdict == .review
            && reconciledAppSupport?.risk == .high
            && reconciledAppSupport?.suggestion == .inspectFurther
            && reconciledAppSupport?.confidence == .low,
        "模型越过 inspect-only 边界时必须自动降级为继续检查"
    )

    let contradictoryDiskAIResponse = diskAIResponse.replacingOccurrences(
        of: "应用私有沙盒，样本主要来自微信、Docker 和百度网盘，常见内容包括数据库、容器镜像及用户资料。",
        with: "这是缓存，可以直接删除整个目录。"
    )
    do {
        _ = try DiskAIResponseValidator.validate(
            content: contradictoryDiskAIResponse,
            snapshot: diskAISnapshot,
            modelID: "/local/model"
        )
        throw SelfTestFailure.assertion("磁盘 AI 的正文不应绕过结构化安全结论")
    } catch LocalAIError.invalidResponse {
        // Expected: model text is descriptive only; handling copy is generated locally.
    }

    let semanticBypassDiskAIResponse = diskAIResponse.replacingOccurrences(
        of: "应用私有沙盒，样本主要来自微信、Docker 和百度网盘，常见内容包括数据库、容器镜像及用户资料。",
        with: "此目录无需保留，放心舍弃即可。"
    )
    let semanticBypassAnalysis = try DiskAIResponseValidator.validate(
        content: semanticBypassDiskAIResponse,
        snapshot: diskAISnapshot,
        modelID: "/local/model"
    )
    let safeContainersText = semanticBypassAnalysis.advice
        .first { $0.entryID == diskAIFixture.report.entries[0].id }?
        .explanation ?? ""
    try check(
        !safeContainersText.contains("舍弃") && safeContainersText.contains("应用隔离保存"),
        "磁盘 AI 展示文本必须由本机安全模板生成"
    )

    let pathInjectingDiskAIResponse = diskAIResponse.replacingOccurrences(
        of: "\"explanation\":\"应用私有沙盒",
        with: "\"path\":\"/tmp/target\",\"explanation\":\"应用私有沙盒",
        options: [],
        range: diskAIResponse.range(of: "\"explanation\":\"应用私有沙盒")
    )
    do {
        _ = try DiskAIResponseValidator.validate(
            content: pathInjectingDiskAIResponse,
            snapshot: diskAISnapshot,
            modelID: "/local/model"
        )
        throw SelfTestFailure.assertion("磁盘 AI 不应接受额外路径字段")
    } catch LocalAIError.invalidResponse {
        // Expected: model output can annotate only known tokens and exact fields.
    }

    let commandDiskAIResponse = diskAIResponse.replacingOccurrences(
        of: "这是基于当前层级及直接子项元数据的用途推断",
        with: "请运行 rm -rf 后再检查"
    )
    do {
        _ = try DiskAIResponseValidator.validate(
            content: commandDiskAIResponse,
            snapshot: diskAISnapshot,
            modelID: "/local/model"
        )
        throw SelfTestFailure.assertion("磁盘 AI 不应输出命令式建议")
    } catch LocalAIError.invalidResponse {
        // Expected: disk advice never becomes an executable command channel.
    }

    let privateCandidate = CleanupCandidate(
        name: "DerivedData",
        url: privateHome.appendingPathComponent("Library/Developer/Xcode/DerivedData/Demo"),
        kind: .developer,
        allocatedBytes: 4_096,
        modifiedAt: nil,
        isRecommended: true,
        detail: "可重新生成"
    )
    let aiSnapshot = try CleanupAIRequestBuilder.makeSnapshot(
        candidates: [privateCandidate],
        diskTotalBytes: 10_000,
        diskFreeBytes: 2_000,
        homeDirectory: privateHome
    )
    try check(!aiSnapshot.payloadJSON.contains(privateHome.path), "AI 请求泄露了绝对主目录")
    let npmFactCandidate = CleanupCandidate(
        name: CleanupScanner.npmCacheDisplayName,
        url: privateHome.appendingPathComponent(".npm/_cacache/content-v2"),
        kind: .packageManager,
        allocatedBytes: 5_331_611_648,
        modifiedAt: Date(),
        isRecommended: false,
        detail: CleanupScanner.npmCacheDetail
    )
    let npmFactSnapshot = try CleanupAIRequestBuilder.makeSnapshot(
        candidates: [npmFactCandidate],
        diskTotalBytes: 10_000,
        diskFreeBytes: 2_000,
        homeDirectory: privateHome
    )
    try check(npmFactSnapshot.payloadJSON.contains("下载并留存"), "AI 请求没有包含 npm 缓存来源")
    try check(npmFactSnapshot.payloadJSON.contains("不是已安装"), "AI 请求没有包含 npm 缓存边界")
    try check(npmFactSnapshot.payloadJSON.contains("不会卸载"), "AI 请求没有包含 npm 清理影响")
    let aiResponse = """
    {"schema_version":1,"summary":"可优先处理开发缓存。","items":[{"token":"c0001","verdict":"reclaimable","risk":"low","priority":1,"reason":"可重新生成。"}],"cautions":[]}
    """
    let aiAnalysis = try CleanupAIResponseValidator.validate(
        content: aiResponse,
        snapshot: aiSnapshot,
        modelID: "/local/model"
    )
    try check(aiAnalysis.advice.first?.candidateID == privateCandidate.id, "AI token 没有安全映回候选项")
    let injectedAIResponse = """
    {"schema_version":1,"summary":"测试","items":[{"token":"c9999","verdict":"keep","risk":"high","priority":3,"reason":"测试","path":"/tmp/new-target"}],"cautions":[]}
    """
    do {
        _ = try CleanupAIResponseValidator.validate(
            content: injectedAIResponse,
            snapshot: aiSnapshot,
            modelID: "/local/model"
        )
        throw SelfTestFailure.assertion("AI 响应不应接受陌生 token 或额外路径字段")
    } catch LocalAIError.invalidResponse {
        // Expected: model output can annotate only the exact request tokens and schema.
    }
    try runLiveMLXTestIfRequested()
    try runLiveDiskMLXTestIfRequested()
    try runLiveMLXProbeIfRequested()
    try runLiveScannerTestIfRequested()
    try runLiveModelCatalogTestIfRequested()

    let uniqueRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("cleannest-selftest-\(UUID().uuidString)", isDirectory: true)
    let cacheRoot = uniqueRoot.appendingPathComponent("Library/Caches", isDirectory: true)
    let allowedTarget = cacheRoot.appendingPathComponent("example-cache", isDirectory: true)
    try FileManager.default.createDirectory(at: allowedTarget, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: uniqueRoot) }

    let policy = SafePathPolicy(homeDirectory: uniqueRoot)
    try policy.validateCleanupTarget(allowedTarget)

    do {
        try policy.validateCleanupTarget(cacheRoot)
        throw SelfTestFailure.assertion("清理范围根目录不应通过校验")
    } catch SafePathError.protectedPath {
        throw SelfTestFailure.assertion("清理范围根目录应作为非严格后代被拒绝，而不是系统保护路径")
    } catch SafePathError.outsideAllowedRoots {
        // Expected: roots themselves are never valid targets.
    }

    print("✓ CleanNestSelfTest：全部检查通过")
} catch {
    fputs("✗ CleanNestSelfTest：\(error)\n", stderr)
    exit(1)
}
