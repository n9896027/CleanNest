import Foundation

/// Pure scanner orchestration shared by the XPC executable and unit tests.
/// The GUI target does not call this worker directly: production scans must
/// cross the process boundary so a failed worker cannot take down the UI.
public struct ScannerWorker: Sendable {
    private let diskAnalyzer: NativeDiskAnalyzer
    private let diskEvidenceIndexer: DiskEvidenceIndexer
    private let agentWorkspaceScanner: AgentWorkspaceScanner

    public init(
        diskAnalyzer: NativeDiskAnalyzer = NativeDiskAnalyzer(),
        diskEvidenceIndexer: DiskEvidenceIndexer = DiskEvidenceIndexer(),
        agentWorkspaceScanner: AgentWorkspaceScanner = AgentWorkspaceScanner()
    ) {
        self.diskAnalyzer = diskAnalyzer
        self.diskEvidenceIndexer = diskEvidenceIndexer
        self.agentWorkspaceScanner = agentWorkspaceScanner
    }

    public func scanCleanup(
        _ request: CleanupScannerRequest,
        progress: (@Sendable (ScannerServiceProgress) -> Void)? = nil
    ) async throws -> CleanupScannerResponse {
        let sessionStartedAt = Date()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        try Task.checkCancellation()
        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .cleanup,
                stage: .cleanupCaches,
                currentName: "Caches"
            )
        )

        let standard = await CleanupScanner(homeDirectory: request.homeDirectory).scanWithEvidence(
            includeApplicationCaches: request.includeApplicationCaches
        )
        try Task.checkCancellation()

        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .cleanup,
                stage: .cleanupPersonalFiles,
                currentName: "Downloads"
            )
        )
        let personal = await DownloadMediaScanner(homeDirectory: request.homeDirectory).scan(
            includeMediaAndDuplicates: request.includeMediaAndDuplicates
        )
        try Task.checkCancellation()

        let visibleStandard = request.developerMode
            ? standard.candidates
            : standard.candidates.filter { $0.kind != .developer && $0.kind != .packageManager }
        var candidatesByPath = Dictionary(
            uniqueKeysWithValues: visibleStandard.map { ($0.url.standardizedFileURL.path, $0) }
        )
        for candidate in personal.candidates {
            candidatesByPath[candidate.url.standardizedFileURL.path] = candidate
        }
        let candidates = candidatesByPath.values.sorted {
            if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
            if $0.allocatedBytes != $1.allocatedBytes { return $0.allocatedBytes > $1.allocatedBytes }
            return $0.url.path < $1.url.path
        }
        let endedAt = DispatchTime.now().uptimeNanoseconds
        let elapsedSeconds = Double(endedAt - startedAt) / 1_000_000_000
        let insights = standard.insights
            .mergingTraversalEvidence(personal.insights)
            .updatingCandidateCounts(from: candidates)
        var seenRoots = Set<String>()
        let roots = (standard.roots + personal.roots).filter {
            seenRoots.insert($0.id).inserted
        }
        let completedAt = Date()
        let session = CleanupScanSession(
            requestID: request.requestID,
            startedAt: sessionStartedAt,
            completedAt: completedAt,
            elapsedSeconds: elapsedSeconds,
            roots: roots,
            insights: insights,
            candidates: candidates
        )
        let response = CleanupScannerResponse(
            requestID: request.requestID,
            candidates: candidates,
            insights: insights,
            session: session,
            elapsedSeconds: elapsedSeconds
        )
        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .cleanup,
                stage: .completed,
                completed: candidates.count,
                total: candidates.count
            )
        )
        return response
    }

    public func scanDisk(
        _ request: DiskScannerRequest,
        progress: (@Sendable (ScannerServiceProgress) -> Void)? = nil
    ) async throws -> DiskScannerResponse {
        try Task.checkCancellation()
        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .disk,
                stage: .preparing,
                currentName: request.root.lastPathComponent
            )
        )

        let outcome = try await diskAnalyzer.analyze(
            root: request.root,
            cache: request.cache,
            mode: request.mode
        ) { scanProgress in
            progress?(
                ScannerServiceProgress(
                    requestID: request.requestID,
                    operation: .disk,
                    stage: .diskContents,
                    completed: scanProgress.completed,
                    total: scanProgress.total,
                    currentName: scanProgress.currentName,
                    partialReport: scanProgress.partialReport,
                    cacheHitCount: scanProgress.cacheHitCount,
                    scannedCount: scanProgress.scannedCount
                )
            )
        }
        try Task.checkCancellation()

        let evidence = try await diskEvidenceIndexer.build(
            report: outcome.report,
            previous: request.previousEvidence,
            homeDirectory: request.homeDirectory
        ) { evidenceProgress in
            progress?(
                ScannerServiceProgress(
                    requestID: request.requestID,
                    operation: .disk,
                    stage: .diskEvidence,
                    completed: evidenceProgress.completed,
                    total: evidenceProgress.total,
                    currentName: evidenceProgress.currentName,
                    cacheHitCount: outcome.cacheHitCount,
                    scannedCount: outcome.scannedCount
                )
            )
        }
        try Task.checkCancellation()
        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .disk,
                stage: .completed,
                completed: evidence.entries.count,
                total: evidence.entries.count,
                cacheHitCount: outcome.cacheHitCount,
                scannedCount: outcome.scannedCount
            )
        )
        return DiskScannerResponse(
            requestID: request.requestID,
            outcome: outcome,
            evidence: evidence
        )
    }

    public func scanAgentWorkspace(
        _ request: AgentWorkspaceScannerRequest,
        progress: (@Sendable (ScannerServiceProgress) -> Void)? = nil
    ) async throws -> AgentWorkspaceScannerResponse {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        try Task.checkCancellation()
        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .agentWorkspace,
                stage: .agentWorkspaceMetadata,
                currentName: "\(request.ruleCatalog.providers.count) 个 Agent 适配器"
            )
        )
        let result = try await agentWorkspaceScanner.scan(
            homeDirectory: request.homeDirectory,
            previous: request.previousObservation,
            catalog: request.ruleCatalog
        )
        try Task.checkCancellation()
        let endedAt = DispatchTime.now().uptimeNanoseconds
        progress?(
            ScannerServiceProgress(
                requestID: request.requestID,
                operation: .agentWorkspace,
                stage: .completed,
                completed: result.snapshot.detectedAgents.count,
                total: AgentWorkspaceProvider.allCases.count
            )
        )
        return AgentWorkspaceScannerResponse(
            requestID: request.requestID,
            result: result,
            elapsedSeconds: Double(endedAt - startedAt) / 1_000_000_000
        )
    }
}
