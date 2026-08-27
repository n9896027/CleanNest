import Foundation
import Security
import CleanNestCore

enum AgentRuleCatalogSource: Equatable {
    case builtIn
    case signedBundle(URL)
    case rejectedBundle(URL)

    var displayName: String {
        switch self {
        case .builtIn: return "内置签名基线"
        case .signedBundle: return "已验证外部规则"
        case .rejectedBundle: return "外部规则已拒绝·内置回退"
        }
    }

    var isExternal: Bool {
        switch self {
        case .builtIn: return false
        case .signedBundle, .rejectedBundle: return true
        }
    }
}

enum AgentRuleCatalogStoreError: LocalizedError {
    case invalidBundle
    case symbolicLink
    case unsignedBundle(String)
    case signerMismatch
    case missingCatalog
    case catalogTooLarge
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidBundle: return "所选项目不是有效的 CleanNest 规则包。"
        case .symbolicLink: return "规则包或规则文件是符号链接，已拒绝导入。"
        case .unsignedBundle(let detail): return "规则包签名无效：\(detail)"
        case .signerMismatch: return "规则包与当前 CleanNest 不是同一签名者，已拒绝导入。"
        case .missingCatalog: return "规则包缺少 Contents/Resources/AgentRules.json。"
        case .catalogTooLarge: return "规则文件超过 1 MB 安全上限。"
        case .installFailed(let detail): return "规则包安装失败：\(detail)"
        }
    }
}

/// Installs only a code-signed bundle whose leaf certificate matches the
/// currently running CleanNest bundle. Catalog data can extend read-only
/// detection; mutation authority is not represented in this format.
struct AgentRuleCatalogStore {
    private let fileManager = FileManager.default

    var installedBundleURL: URL {
        CleanNestDataPaths.applicationSupportDirectory()
            .appendingPathComponent("AgentRules.bundle", isDirectory: true)
    }

    func load() -> (AgentRuleCatalog, AgentRuleCatalogSource, String) {
        guard fileManager.fileExists(atPath: installedBundleURL.path) else {
            return (.builtIn, .builtIn, "正在使用随 App 发布并经过测试的内置规则。")
        }
        do {
            let catalog = try verifiedCatalog(at: installedBundleURL)
            return (catalog, .signedBundle(installedBundleURL), "外部规则签名与内容校验均已通过。")
        } catch {
            return (.builtIn, .rejectedBundle(installedBundleURL), "外部规则未通过校验，已失败关闭并回退内置规则：\(error.localizedDescription)")
        }
    }

    func install(from source: URL) throws -> AgentRuleCatalog {
        let source = source.standardizedFileURL
        guard source.pathExtension.lowercased() == "bundle"
                || source.pathExtension.lowercased() == "cleannestrules" else {
            throw AgentRuleCatalogStoreError.invalidBundle
        }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true else { throw AgentRuleCatalogStoreError.invalidBundle }
        guard values.isSymbolicLink != true else { throw AgentRuleCatalogStoreError.symbolicLink }
        let catalog = try verifiedCatalog(at: source)

        let parent = installedBundleURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        let staging = parent.appendingPathComponent(".AgentRules-\(UUID().uuidString).bundle", isDirectory: true)
        do {
            try fileManager.copyItem(at: source, to: staging)
            _ = try verifiedCatalog(at: staging)
            if fileManager.fileExists(atPath: installedBundleURL.path) {
                _ = try fileManager.replaceItemAt(
                    installedBundleURL,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: staging, to: installedBundleURL)
            }
            _ = try verifiedCatalog(at: installedBundleURL)
            return catalog
        } catch {
            try? fileManager.removeItem(at: staging)
            if let known = error as? AgentRuleCatalogStoreError { throw known }
            throw AgentRuleCatalogStoreError.installFailed(error.localizedDescription)
        }
    }

    func reset() throws {
        guard fileManager.fileExists(atPath: installedBundleURL.path) else { return }
        let parent = installedBundleURL.deletingLastPathComponent().standardizedFileURL
        let expectedParent = CleanNestDataPaths.applicationSupportDirectory().standardizedFileURL
        guard parent.path == expectedParent.path,
              installedBundleURL.lastPathComponent == "AgentRules.bundle" else {
            throw AgentRuleCatalogStoreError.installFailed("规则包路径不在 CleanNest 数据目录。")
        }
        try fileManager.removeItem(at: installedBundleURL)
    }

    private func verifiedCatalog(at bundleURL: URL) throws -> AgentRuleCatalog {
        try verifySignature(bundleURL)
        let catalogURL = bundleURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent("AgentRules.json", isDirectory: false)
        guard fileManager.fileExists(atPath: catalogURL.path) else {
            throw AgentRuleCatalogStoreError.missingCatalog
        }
        let values = try catalogURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw AgentRuleCatalogStoreError.symbolicLink
        }
        guard (values.fileSize ?? 0) <= 1_048_576 else {
            throw AgentRuleCatalogStoreError.catalogTooLarge
        }
        let data = try Data(contentsOf: catalogURL, options: [.mappedIfSafe])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(AgentRuleCatalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    private func verifySignature(_ candidateURL: URL) throws {
        let hostURL = Bundle.main.bundleURL.standardizedFileURL
        let hostCertificates = try certificates(at: hostURL)
        let candidateCertificates = try certificates(at: candidateURL)
        guard let hostLeaf = hostCertificates.first,
              let candidateLeaf = candidateCertificates.first,
              SecCertificateCopyData(hostLeaf) as Data == SecCertificateCopyData(candidateLeaf) as Data else {
            throw AgentRuleCatalogStoreError.signerMismatch
        }
    }

    private func certificates(at url: URL) throws -> [SecCertificate] {
        var code: SecStaticCode?
        let creation = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        guard creation == errSecSuccess, let code else {
            throw AgentRuleCatalogStoreError.unsignedBundle("无法读取代码签名（\(creation)）。")
        }
        let validation = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures),
            nil
        )
        guard validation == errSecSuccess else {
            throw AgentRuleCatalogStoreError.unsignedBundle("系统校验状态 \(validation)。")
        }
        var rawInformation: CFDictionary?
        let copied = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &rawInformation
        )
        guard copied == errSecSuccess,
              let information = rawInformation as? [CFString: Any],
              let certificates = information[kSecCodeInfoCertificates] as? [SecCertificate],
              !certificates.isEmpty else {
            throw AgentRuleCatalogStoreError.unsignedBundle("签名证书链不可用。")
        }
        return certificates
    }
}
