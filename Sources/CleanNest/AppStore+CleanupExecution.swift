import Foundation
import CleanNestCore

@MainActor
extension AppStore {
    func loadCleanupExecutionLedger() {
        do {
            let result = try CleanupExecutionLedgerPersistence.load(
                from: CleanNestDataPaths.cleanupExecutionLedger()
            )
            cleanupExecutionLedger = result.snapshot
            cleanupExecutionLedgerDiagnostic = result.diagnostic
        } catch {
            cleanupExecutionLedger = CleanupExecutionLedgerSnapshot()
            cleanupExecutionLedgerDiagnostic = CNL10n.format(
                "执行账本无法读取；不会据此恢复任何文件：%@",
                error.localizedDescription
            )
        }
    }

    func beginCleanupExecution(
        candidates: [CleanupCandidate],
        freeBytesBefore: Int64
    ) -> CleanupExecutionRecord {
        let record = CleanupExecutionRecord(
            candidates: candidates,
            freeBytesBefore: freeBytesBefore
        )
        cleanupExecutionLedger.insert(record)
        persistCleanupExecutionLedger()
        return record
    }

    func completeCleanupExecution(
        _ record: CleanupExecutionRecord,
        outcomes: [TrashOutcome],
        freeBytesAfter: Int64?
    ) -> CleanupExecutionRecord {
        let completed = record.applying(
            outcomes: outcomes,
            trashDirectory: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".Trash", isDirectory: true),
            freeBytesAfter: freeBytesAfter
        )
        cleanupExecutionLedger.update(completed)
        persistCleanupExecutionLedger()
        return completed
    }

    func persistCleanupExecutionLedger() {
        guard !demoMode else { return }
        do {
            try CleanupExecutionLedgerPersistence.save(
                cleanupExecutionLedger,
                to: CleanNestDataPaths.cleanupExecutionLedger()
            )
        } catch {
            cleanupExecutionLedgerDiagnostic = CNL10n.format(
                "执行账本未能持久化；请保留技术详情，不要仅依赖恢复入口：%@",
                error.localizedDescription
            )
        }
    }

    func restoreCleanupExecutionItem(recordID: String, itemID: String) async {
        guard !demoMode, cleanupRestoringItemID == nil, !isWorking else { return }
        guard let record = cleanupExecutionLedger.records.first(where: { $0.id == recordID }),
              let item = record.items.first(where: { $0.id == itemID }) else {
            phase = .failed("恢复记录已变化，请重新打开执行账本")
            return
        }
        cleanupRestoringItemID = itemID
        defer { cleanupRestoringItemID = nil }
        phase = .executing(CNL10n.format("正在复核并恢复“%@”…", item.name))
        let service = CleanupRestoreService()
        let updated = await Task.detached(priority: .userInitiated) {
            service.restore(item)
        }.value
        cleanupExecutionLedger.update(record.updatingItem(updated))
        persistCleanupExecutionLedger()

        if updated.status == .restored {
            phase = .success(CNL10n.format("已恢复“%@”", item.name))
            addActivity(
                title: "恢复清理项目",
                detail: CNL10n.format("执行 %@ · 已按身份复核放回原位置", record.id),
                outcome: .success,
                affectedItems: 1,
                category: .other,
                executionID: record.id
            )
        } else {
            phase = .failed(updated.errorDescription ?? "未能恢复项目")
            lastTechnicalDetail = CNL10n.format(
                "执行：%@\n项目：%@\n源路径：%@\n废纸篓目标：%@\n状态：%@",
                record.id,
                item.name,
                item.sourceURL.path,
                item.trashURL?.path ?? "未知",
                updated.status.rawValue
            )
        }
    }

    func reconcileCleanupExecution(recordID: String) {
        guard let record = cleanupExecutionLedger.records.first(where: { $0.id == recordID }) else { return }
        guard let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: FileManager.default.homeDirectoryForCurrentUser.path
        ), let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else {
            cleanupExecutionLedgerDiagnostic = "当前 APFS 可用空间未知，最终释放量保持未知。"
            return
        }
        let updated = record.confirmingFinalObservation(currentFreeBytes: free)
        cleanupExecutionLedger.update(updated)
        persistCleanupExecutionLedger()
        if updated.finalAPFSFreeBytesDelta == nil {
            phase = .success("记录中的废纸篓项目仍存在；最终释放量仍需等待清空后复核")
        } else {
            phase = .success("已记录清空废纸篓后的 APFS 观测增量；该数值包含同期系统变化，不作独占归因")
        }
    }
}
