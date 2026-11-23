import Darwin
import Foundation

public enum ModelConfigurationReferenceStatus: String, Codable, Equatable, Sendable {
    case existingTarget
    case missingTarget
    case directoryTraversal
    case externalTarget
    case unresolvedText
}

public struct ModelConfigurationReference: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let configurationURL: URL
    public let key: String
    public let rawValue: String
    public let resolvedURL: URL?
    public let status: ModelConfigurationReferenceStatus
    public let detail: String

    public init(
        configurationURL: URL,
        key: String,
        rawValue: String,
        resolvedURL: URL?,
        status: ModelConfigurationReferenceStatus,
        detail: String
    ) {
        self.configurationURL = configurationURL
        self.key = key
        self.rawValue = rawValue
        self.resolvedURL = resolvedURL
        self.status = status
        self.detail = detail
        id = [configurationURL.path, key, rawValue, status.rawValue].joined(separator: "|")
    }
}

public struct ModelConfigurationIssue: Codable, Equatable, Identifiable, Sendable {
    public let configurationURL: URL
    public let line: Int?
    public let message: String

    public var id: String { "\(configurationURL.path)|\(line ?? 0)|\(message)" }

    public init(configurationURL: URL, line: Int? = nil, message: String) {
        self.configurationURL = configurationURL
        self.line = line
        self.message = message
    }
}

public struct ModelConfigurationReferenceReport: Codable, Equatable, Sendable {
    public let rootURL: URL
    public let scannedConfigurationCount: Int
    public let references: [ModelConfigurationReference]
    public let issues: [ModelConfigurationIssue]
    public let isComplete: Bool

    public init(
        rootURL: URL,
        scannedConfigurationCount: Int,
        references: [ModelConfigurationReference],
        issues: [ModelConfigurationIssue],
        isComplete: Bool
    ) {
        self.rootURL = rootURL
        self.scannedConfigurationCount = max(0, scannedConfigurationCount)
        self.references = references
        self.issues = issues
        self.isComplete = isComplete
    }

    public var requiresReview: Bool { !references.isEmpty || !issues.isEmpty || !isComplete }

    public var summary: String {
        if !issues.isEmpty || !isComplete {
            return "配置解析或读取不完整；相关项目保持复核，不能据此扩大清理范围。"
        }
        if references.isEmpty {
            return "限定范围内未发现已知路径键；这不等于证明项目没有外部引用。"
        }
        let existing = references.filter { $0.status == .existingTarget || $0.status == .externalTarget }.count
        let missing = references.filter { $0.status == .missingTarget }.count
        return "读取到 \(references.count) 条路径引用：\(existing) 条目标存在，\(missing) 条目标缺失；命中后保持复核。"
    }
}

/// Bounded, read-only inspection for model and agent configuration. It supports
/// strict JSON plus the common mapping/array subset of YAML and TOML. Unsupported
/// syntax is an explicit parse issue, never an excuse to ignore references.
public struct ModelConfigurationReferenceInspector: Sendable {
    public let maximumConfigurations: Int
    public let maximumBytesPerConfiguration: Int
    public let maximumVisitedEntries: Int

    public init(
        maximumConfigurations: Int = 32,
        maximumBytesPerConfiguration: Int = 1_048_576,
        maximumVisitedEntries: Int = 2_000
    ) {
        self.maximumConfigurations = max(1, min(maximumConfigurations, 128))
        self.maximumBytesPerConfiguration = max(1_024, min(maximumBytesPerConfiguration, 8 * 1_048_576))
        self.maximumVisitedEntries = max(32, min(maximumVisitedEntries, 20_000))
    }

    public func inspect(root: URL) -> ModelConfigurationReferenceReport {
        let root = root.standardizedFileURL
        var issues: [ModelConfigurationIssue] = []
        var references: [ModelConfigurationReference] = []
        var visited = 0
        var configurations: [URL] = []
        var complete = true
        guard CleanupScanRootInspector.isSafeDirectory(root) else {
            return ModelConfigurationReferenceReport(
                rootURL: root,
                scannedConfigurationCount: 0,
                references: [],
                issues: [ModelConfigurationIssue(configurationURL: root, message: "配置根目录不存在、不可读或不安全。")],
                isComplete: false
            )
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { url, _ in
                issues.append(ModelConfigurationIssue(configurationURL: url, message: "配置目录中的路径无法读取。"))
                complete = false
                return true
            }
        ) else {
            return ModelConfigurationReferenceReport(
                rootURL: root,
                scannedConfigurationCount: 0,
                references: [],
                issues: [ModelConfigurationIssue(configurationURL: root, message: "无法建立配置目录只读遍历。")],
                isComplete: false
            )
        }
        let rootDepth = root.pathComponents.count
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited > maximumVisitedEntries || configurations.count >= maximumConfigurations {
                complete = false
                issues.append(ModelConfigurationIssue(configurationURL: root, message: "配置检查达到有界扫描上限。"))
                break
            }
            let depth = url.pathComponents.count - rootDepth
            if depth >= 4, (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
                issues.append(ModelConfigurationIssue(configurationURL: url, message: "无法读取配置路径元数据。"))
                complete = false
                continue
            }
            if values.isSymbolicLink == true {
                if ["json", "yaml", "yml", "toml"].contains(url.pathExtension.lowercased()) {
                    issues.append(ModelConfigurationIssue(configurationURL: url, message: "符号链接配置不会被跟随或解析。"))
                    complete = false
                }
                continue
            }
            guard values.isRegularFile == true,
                  ["json", "yaml", "yml", "toml"].contains(url.pathExtension.lowercased()) else { continue }
            configurations.append(url)
        }

        for url in configurations {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                guard let size = (attributes[.size] as? NSNumber)?.intValue, size <= maximumBytesPerConfiguration else {
                    throw ConfigurationParsingError("配置文件超过大小上限。")
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                let text = String(decoding: data, as: UTF8.self)
                let parsed = try parse(text: text, format: url.pathExtension.lowercased(), configurationURL: url, root: root)
                references.append(contentsOf: parsed)
            } catch {
                complete = false
                let line = (error as? ConfigurationParsingError)?.line
                issues.append(ModelConfigurationIssue(
                    configurationURL: url,
                    line: line,
                    message: error.localizedDescription
                ))
            }
        }
        return ModelConfigurationReferenceReport(
            rootURL: root,
            scannedConfigurationCount: configurations.count,
            references: references,
            issues: issues,
            isComplete: complete
        )
    }

    private struct ConfigurationParsingError: LocalizedError {
        let message: String
        let line: Int?

        init(_ message: String, line: Int? = nil) {
            self.message = message
            self.line = line
        }

        var errorDescription: String? {
            line.map { "第 \($0) 行：\(message)" } ?? message
        }
    }

    private func parse(text: String, format: String, configurationURL: URL, root: URL) throws -> [ModelConfigurationReference] {
        switch format {
        case "json": return try parseJSON(text: text, configurationURL: configurationURL, root: root)
        case "yaml", "yml": return try parseYAML(text: text, configurationURL: configurationURL, root: root)
        case "toml": return try parseTOML(text: text, configurationURL: configurationURL, root: root)
        default: return []
        }
    }

    private func parseJSON(text: String, configurationURL: URL, root: URL) throws -> [ModelConfigurationReference] {
        let data = Data(text.utf8)
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []) else {
            throw ConfigurationParsingError("JSON 语法无法解析；已失败关闭。")
        }
        var pairs: [(String, String)] = []
        func walk(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, child) in dictionary {
                    if let string = child as? String { pairs.append((key, string)) }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(object)
        return references(from: pairs, configurationURL: configurationURL, root: root)
    }

    private func parseYAML(text: String, configurationURL: URL, root: URL) throws -> [ModelConfigurationReference] {
        var pairs: [(String, String)] = []
        var lastKey: String?
        for (index, sourceLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let trimmed = try stripYAMLComment(from: sourceLine, line: lineNumber)
                .trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == "---" || trimmed == "..." { continue }
            if trimmed.contains("&") || trimmed.contains("*") || trimmed.hasSuffix(": |") || trimmed.hasSuffix(": >") {
                throw ConfigurationParsingError("包含当前只读解析器不支持的 YAML 锚点、别名或块文本。", line: lineNumber)
            }
            if trimmed.hasPrefix("-") {
                let item = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if item.contains(":") {
                    let pair = try splitMapping(String(item), line: lineNumber)
                    pairs.append(pair)
                    lastKey = pair.0
                } else if let lastKey {
                    pairs.append((lastKey, try unquote(item, line: lineNumber)))
                } else {
                    throw ConfigurationParsingError("YAML 列表缺少所属键。", line: lineNumber)
                }
                continue
            }
            guard trimmed.contains(":") else {
                throw ConfigurationParsingError("YAML 映射缺少冒号或语法不完整。", line: lineNumber)
            }
            let pair = try splitMapping(trimmed, line: lineNumber)
            lastKey = pair.0
            if !pair.1.isEmpty { pairs.append(pair) }
        }
        return references(from: pairs, configurationURL: configurationURL, root: root)
    }

    private func parseTOML(text: String, configurationURL: URL, root: URL) throws -> [ModelConfigurationReference] {
        var pairs: [(String, String)] = []
        for (index, sourceLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            let trimmed = try stripTOMLComment(from: sourceLine, line: lineNumber)
                .trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") {
                guard trimmed.hasSuffix("]"), !trimmed.hasPrefix("[[") || trimmed.hasSuffix("]]" ) else {
                    throw ConfigurationParsingError("TOML 表头括号不完整。", line: lineNumber)
                }
                continue
            }
            guard let equals = firstUnquotedEquals(in: trimmed) else {
                throw ConfigurationParsingError("TOML 键值缺少等号。", line: lineNumber)
            }
            let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
            let value = trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else {
                throw ConfigurationParsingError("TOML 键或值为空。", line: lineNumber)
            }
            let finalKey = key.split(separator: ".").last.map(String.init) ?? key
            if value.hasPrefix("[") {
                guard value.hasSuffix("]") else {
                    throw ConfigurationParsingError("TOML 数组括号不完整。", line: lineNumber)
                }
                for item in try splitArray(String(value.dropFirst().dropLast()), line: lineNumber) {
                    pairs.append((finalKey, item))
                }
            } else if value.hasPrefix("{") {
                throw ConfigurationParsingError("内联表需要展开后再做引用检查；当前失败关闭。", line: lineNumber)
            } else if value.hasPrefix("\"") || value.hasPrefix("'") {
                pairs.append((finalKey, try unquote(value, line: lineNumber)))
            } else if !["true", "false"].contains(value), Int64(value) == nil, Double(value) == nil {
                throw ConfigurationParsingError("TOML 包含无法确认的未加引号值。", line: lineNumber)
            }
        }
        return references(from: pairs, configurationURL: configurationURL, root: root)
    }

    private func splitMapping(_ text: String, line: Int) throws -> (String, String) {
        guard let colon = text.firstIndex(of: ":") else {
            throw ConfigurationParsingError("映射缺少冒号。", line: line)
        }
        let key = text[..<colon].trimmingCharacters(in: .whitespaces)
        let raw = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { throw ConfigurationParsingError("映射键为空。", line: line) }
        if raw.isEmpty { return (key, "") }
        if raw.hasPrefix("[") {
            guard raw.hasSuffix("]") else { throw ConfigurationParsingError("YAML 数组括号不完整。", line: line) }
            return (key, try splitArray(String(raw.dropFirst().dropLast()), line: line).joined(separator: "\n"))
        }
        return (key, try unquote(raw, line: line))
    }

    private func stripYAMLComment(from line: String, line lineNumber: Int) throws -> String {
        try stripComment(from: line, marker: "#", requireWhitespaceBeforeMarker: true, line: lineNumber)
    }

    private func stripTOMLComment(from line: String, line lineNumber: Int) throws -> String {
        try stripComment(from: line, marker: "#", requireWhitespaceBeforeMarker: false, line: lineNumber)
    }

    private func stripComment(from line: String, marker: Character, requireWhitespaceBeforeMarker: Bool, line lineNumber: Int) throws -> String {
        var quote: Character?
        var escaped = false
        var previous: Character?
        for index in line.indices {
            let character = line[index]
            if escaped { escaped = false; previous = character; continue }
            if character == "\\", quote == "\"" { escaped = true; previous = character; continue }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil } else if quote == nil { quote = character }
            }
            if character == marker, quote == nil {
                if requireWhitespaceBeforeMarker, let previousValue = previous, !previousValue.isWhitespace {
                    previous = character
                    continue
                }
                return String(line[..<index])
            }
            previous = character
        }
        guard quote == nil, !escaped else { throw ConfigurationParsingError("字符串引号或转义不完整。", line: lineNumber) }
        return line
    }

    private func firstUnquotedEquals(in text: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil } else if quote == nil { quote = character }
            }
            if character == "=", quote == nil { return index }
        }
        return nil
    }

    private func splitArray(_ text: String, line: Int) throws -> [String] {
        var values: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in text {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\", quote == "\"" { current.append(character); escaped = true; continue }
            if character == "\"" || character == "'" {
                current.append(character)
                if quote == character { quote = nil } else if quote == nil { quote = character }
                continue
            }
            if character == ",", quote == nil {
                values.append(try unquote(current.trimmingCharacters(in: .whitespaces), line: line))
                current = ""
            } else {
                current.append(character)
            }
        }
        guard quote == nil, !escaped else { throw ConfigurationParsingError("数组字符串不完整。", line: line) }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            values.append(try unquote(current.trimmingCharacters(in: .whitespaces), line: line))
        }
        return values
    }

    private func unquote(_ value: String, line: Int) throws -> String {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard let first = value.first else { return "" }
        if first == "\"" {
            guard value.count >= 2, value.last == "\"",
                  let decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) else {
                throw ConfigurationParsingError("双引号字符串或转义无效。", line: line)
            }
            return decoded
        }
        if first == "'" {
            guard value.count >= 2, value.last == "'" else {
                throw ConfigurationParsingError("单引号字符串不完整。", line: line)
            }
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if value.hasSuffix("\"") || value.hasSuffix("'") {
            throw ConfigurationParsingError("字符串引号不匹配。", line: line)
        }
        return value
    }

    private func references(from pairs: [(String, String)], configurationURL: URL, root: URL) -> [ModelConfigurationReference] {
        var output: [ModelConfigurationReference] = []
        let rootPaths = [
            root.standardizedFileURL.path,
            root.resolvingSymlinksInPath().standardizedFileURL.path,
            canonicalPath(root)
        ].compactMap { $0 }
        for (key, combinedValue) in pairs {
            for raw in combinedValue.components(separatedBy: "\n") {
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                let pathKey = isPathKey(key)
                guard pathKey, looksLikePath(value, key: key), !value.contains("$") else {
                    if pathKey, value.contains("$") {
                        output.append(ModelConfigurationReference(
                            configurationURL: configurationURL,
                            key: key,
                            rawValue: value,
                            resolvedURL: nil,
                            status: .unresolvedText,
                            detail: "包含未展开变量，不能证明目标位置。"
                        ))
                    }
                    continue
                }
                if value.hasPrefix("http://") || value.hasPrefix("https://") { continue }
                let path: String
                if value.hasPrefix("file://"), let url = URL(string: value) { path = url.path } else { path = value }
                let expanded = path.hasPrefix("~")
                    ? FileManager.default.homeDirectoryForCurrentUser.path + String(path.dropFirst(1))
                    : path
                let url = expanded.hasPrefix("/")
                    ? URL(fileURLWithPath: expanded).standardizedFileURL
                    : configurationURL.deletingLastPathComponent().appendingPathComponent(expanded).standardizedFileURL
                let targetPaths = [url.path, url.resolvingSymlinksInPath().standardizedFileURL.path]
                let lexicalInRoot = targetPaths.contains { target in
                    rootPaths.contains { rootPath in target == rootPath || target.hasPrefix(rootPath + "/") }
                }
                let traversal = expanded.split(separator: "/").contains("..") && !lexicalInRoot
                let exists = lexists(url)
                let status: ModelConfigurationReferenceStatus
                let detail: String
                if traversal {
                    status = .directoryTraversal
                    detail = "相对引用通过 .. 离开配置根目录；只记录证据，不跟随清理。"
                } else if !lexicalInRoot {
                    status = .externalTarget
                    detail = exists ? "绝对或外部引用目标存在；相关项目保持复核。" : "外部路径文本目标当前不存在，仍需人工确认。"
                } else if exists {
                    status = .existingTarget
                    detail = "配置路径文本对应的真实目录项存在；不代表可以删除任一侧。"
                } else {
                    status = .missingTarget
                    detail = "配置引用的目标当前不存在；只作为缺失引用证据。"
                }
                output.append(ModelConfigurationReference(
                    configurationURL: configurationURL,
                    key: key,
                    rawValue: value,
                    resolvedURL: url,
                    status: status,
                    detail: detail
                ))
            }
        }
        return output
    }

    private func isPathKey(_ key: String) -> Bool {
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        let keys = [
            "path", "model", "modelpath", "weights", "weightspath", "tokenizer", "tokenizerpath",
            "config", "configpath", "checkpoint", "checkpointpath", "adapter", "adapterpath",
            "file", "filename", "directory", "root", "cachedir", "cachepath", "vocab", "vocabpath",
            "gguf", "safetensors", "snapshot", "snapshotpath"
        ]
        return keys.contains(normalized) || normalized.hasSuffix("path") || normalized.hasSuffix("paths")
    }

    private func looksLikePath(_ value: String, key: String) -> Bool {
        guard !value.isEmpty, value.count <= 4_096 else { return false }
        let normalized = key.lowercased().filter { $0.isLetter || $0.isNumber }
        if normalized != "model" && normalized != "config" && normalized != "file" && normalized != "filename" { return true }
        let extensions = ["gguf", "safetensors", "bin", "pt", "pth", "onnx", "mlmodel", "mlpackage", "json"]
        return value.contains("/") || value.contains("\\") || value.hasPrefix(".") || value.hasPrefix("~")
            || extensions.contains(URL(fileURLWithPath: value).pathExtension.lowercased())
    }

    private func canonicalPath(_ url: URL) -> String? {
        guard let pointer = url.path.withCString({ realpath($0, nil) }) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    private func lexists(_ url: URL) -> Bool {
        var information = stat()
        return url.path.withCString { lstat($0, &information) } == 0
    }
}
