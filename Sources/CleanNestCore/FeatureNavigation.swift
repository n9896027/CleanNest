import Foundation

/// Navigation only: results never execute a cleanup, stop, or settings write.
public struct FeatureDestination: Identifiable, Equatable, Sendable {
    public let id: String
    public let page: String
    public let title: String
    public let detail: String
    public let symbol: String
    public let keywords: String
    public let settingsSection: CleanNestSettingsSection?
}

public enum FeatureDirectory {
    public static let destinations: [FeatureDestination] = [
        .init(id: "overview", page: "总览", title: "总览", detail: "Mac 当前状态和常用操作", symbol: "square.grid.2x2", keywords: "overview home 首页 zonglan", settingsSection: nil),
        .init(id: "cleanup", page: "清理空间", title: "清理空间", detail: "缓存、安装包、截图、媒体和重复文件", symbol: "sparkles", keywords: "clean cache dmg zip screenshot duplicate qingli 清理垃圾 下载 图片 视频 音频 重复", settingsSection: nil),
        .init(id: "applications", page: "应用卸载", title: "应用卸载", detail: "查找 App 并预览卸载内容", symbol: "app.dashed", keywords: "uninstall apps xiezai 删除软件", settingsSection: nil),
        .init(id: "disk", page: "磁盘浏览", title: "磁盘浏览", detail: "大文件、空间分布和系统数据占用", symbol: "chart.pie", keywords: "disk storage system data docker xcode pip npm 空间 硬盘 c盘", settingsSection: nil),
        .init(id: "status", page: "系统状态", title: "系统状态", detail: "实时监测、内存进程、趋势和告警", symbol: "waveform.path.ecg", keywords: "cpu gpu ram memory fan temperature battery network monitor 内存 温度 风扇 电池 网络", settingsSection: nil),
        .init(id: "maintenance", page: "系统维护", title: "系统维护", detail: "诊断与修复预览、Dock 或 Finder 异常", symbol: "wrench.and.screwdriver", keywords: "repair maintenance fix 重启 维护 图标 快速查看", settingsSection: nil),
        .init(id: "agents", page: "Agent 工作区", title: "Agent 工作区", detail: "查看编程助手占用、清理计划和恢复包", symbol: "folder.badge.gearshape", keywords: "codex claude pi kimi hermes openclaw agent workbuddy trae 恢复 备份 编程助手", settingsSection: nil),
        .init(id: "models", page: "本地模型", title: "本地模型", detail: "发现、启停模型服务并查看守护进程", symbol: "rectangle.stack.badge.play", keywords: "mlx omlx ollama lm studio qwen gemma 模型 服务 内网 端口 停止 启动", settingsSection: nil),
        .init(id: "habits", page: "清理习惯", title: "清理习惯", detail: "管理保留偏好与待确认建议", symbol: "sparkles.rectangle.stack", keywords: "learning evolution preferences rules 习惯 学习 规则", settingsSection: nil),
        .init(id: "activity", page: "活动记录", title: "活动记录", detail: "操作结果、累计统计和失败详情", symbol: "clock.arrow.circlepath", keywords: "activity history log record 历史 日志 统计 记录", settingsSection: nil),
        .init(id: "settings", page: "设置", title: "设置", detail: "连接、扫描范围、语言与应用设置", symbol: "gearshape", keywords: "settings preferences language 设置 语言", settingsSection: nil),
        .init(id: "permissions", page: "设置", title: "文件访问与扫描范围", detail: "设置 · 访问检测、媒体和重复文件开关", symbol: "lock.shield", keywords: "privacy permission access 权限 授权 完全磁盘 扫描范围 隐私", settingsSection: .scanAndPrivacy),
        .init(id: "menubar", page: "设置", title: "菜单栏与告警", detail: "设置 · 指标、刷新频率与异常阈值", symbol: "menubar.rectangle", keywords: "menubar alerts threshold 菜单栏 状态栏 告警 阈值", settingsSection: .menuBar),
        .init(id: "ai", page: "设置", title: "AI 连接设置", detail: "设置 · 本机模型地址、模型名和连接测试", symbol: "brain.head.profile", keywords: "AI endpoint api connection omlx 连接测试 地址 端口 id", settingsSection: .localAI),
        .init(id: "history-settings", page: "设置", title: "历史与存储设置", detail: "设置 · 采样保留期限与记录管理", symbol: "clock", keywords: "retention storage history 历史 保留 清空", settingsSection: .historyAndStorage),
        .init(id: "mcp", page: "设置", title: "只读 MCP", detail: "设置 · 把本机状态接入 AI 客户端", symbol: "terminal", keywords: "advanced mcp client 高级 客户端", settingsSection: .advanced),
        .init(id: "about", page: "设置", title: "关于与更新", detail: "设置 · 当前版本和检查更新", symbol: "info.circle", keywords: "update version about release 更新 版本 升级", settingsSection: .about)
    ]

    public static func search(_ query: String) -> [FeatureDestination] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return destinations }
        let phrase = terms.joined(separator: " ")
        func relevance(_ item: FeatureDestination) -> Int {
            if item.title.localizedCaseInsensitiveCompare(phrase) == .orderedSame { return 0 }
            if item.title.localizedStandardContains(phrase) { return 1 }
            if terms.allSatisfy({ item.title.localizedStandardContains($0) }) { return 2 }
            if item.detail.localizedStandardContains(phrase) { return 3 }
            return 4
        }
        return destinations.enumerated().filter { _, item in
            let text = [item.title, item.detail, item.keywords].joined(separator: " ")
            return terms.allSatisfy { text.localizedStandardContains($0) }
        }.sorted { lhs, rhs in
            let a = relevance(lhs.element), b = relevance(rhs.element)
            return a == b ? lhs.offset < rhs.offset : a < b
        }.map(\.element)
    }
}

/// Bounded per-window history. Revisiting the current page is not a new entry;
/// a new visit after Back discards only forward navigation, never app data.
public struct PageNavigationHistory: Equatable, Sendable {
    public private(set) var pages: [String]
    public private(set) var index: Int
    public var current: String { pages[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < pages.count }

    public init(initial: String) { pages = [initial]; index = 0 }

    public mutating func visit(_ page: String) {
        guard page != current else { return }
        pages = Array(pages.prefix(index + 1))
        pages.append(page)
        if pages.count > 40 { pages.removeFirst(pages.count - 40) }
        index = pages.count - 1
    }

    public mutating func back() -> String? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    public mutating func forward() -> String? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }
}
