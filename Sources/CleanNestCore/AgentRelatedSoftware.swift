import Foundation

/// Functional classification is independent from code-signing trust. A valid
/// signature identifies the developer; it does not turn a launcher, provider
/// switcher or bundled helper into a standalone Agent.
public enum AgentRelatedSoftwareRole: String, Codable, Sendable {
    case bundledComponent
    case configurationTool
    case localLauncher
    case automationLauncher
    case urlHandler
    case helperShell
    case localModelRunner
    case automationWorkbench

    public var displayName: String {
        switch self {
        case .bundledComponent: return "宿主产品的附带自动化组件"
        case .configurationTool: return "API 与提供商配置切换工具"
        case .localLauncher: return "本地启动器"
        case .automationLauncher: return "自动化启动器"
        case .urlHandler: return "辅助 URL 跳转工具"
        case .helperShell: return "宿主产品的辅助 shell"
        case .localModelRunner: return "本地模型运行器"
        case .automationWorkbench: return "内容运营工作台（内置 AI 助手）"
        }
    }
}

/// Deliberately has no private-data rules or uninstall capability. Related
/// software can still appear in ordinary App uninstall, but never inherits
/// Agent product authority merely because its signature is valid.
public struct AgentRelatedSoftwareRule: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String
    public let role: AgentRelatedSoftwareRole
    public let owningProductID: String?

    public init(
        id: String,
        displayName: String,
        bundleIdentifier: String,
        role: AgentRelatedSoftwareRole,
        owningProductID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.role = role
        self.owningProductID = owningProductID
    }

    func validate() throws {
        let identifiers = [id, bundleIdentifier]
        guard !id.isEmpty, !displayName.isEmpty,
              id.count <= 80, displayName.count <= 120,
              id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }),
              identifiers.allSatisfy({ !$0.isEmpty && $0.count <= 160 && !$0.contains("/") && !$0.contains("\0") }),
              owningProductID?.isEmpty != true else {
            throw AgentRuleCatalogError.emptyDetectionRule(displayName)
        }
    }
}

public struct AgentRelatedSoftwareInstallation: Identifiable, Equatable, Sendable {
    public let softwareID: String
    public let copyID: String
    public let displayName: String
    public let application: InstalledApplication
    public let role: AgentRelatedSoftwareRole
    public let owningProductID: String?
    public let signature: AgentDesktopSignatureEvidence

    public init(
        rule: AgentRelatedSoftwareRule,
        application: InstalledApplication,
        signature: AgentDesktopSignatureEvidence
    ) {
        softwareID = rule.id
        copyID = rule.id + ":" + application.id
        displayName = rule.displayName
        self.application = application
        role = rule.role
        owningProductID = rule.owningProductID
        self.signature = signature
    }

    public var id: String { copyID }
}
