import Foundation

public struct LocalModelDescriptor: Identifiable, Equatable, Sendable {
    public let path: String
    public let canonicalPath: String
    public let displayName: String
    public let architecture: String?
    public let modelType: String?
    public let quantization: String?
    public let weightBytes: Int64
    public let serviceAliases: [String]

    public var id: String { path }

    public init(
        path: String,
        canonicalPath: String,
        displayName: String,
        architecture: String?,
        modelType: String?,
        quantization: String?,
        weightBytes: Int64,
        serviceAliases: [String]
    ) {
        self.path = path
        self.canonicalPath = canonicalPath
        self.displayName = displayName
        self.architecture = architecture
        self.modelType = modelType
        self.quantization = quantization
        self.weightBytes = weightBytes
        self.serviceAliases = serviceAliases
    }

    public func matches(serviceModelID rawModelID: String) -> Bool {
        let modelID = rawModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelID.isEmpty else { return false }

        if (modelID as NSString).isAbsolutePath {
            let canonicalServicePath = URL(fileURLWithPath: modelID)
                .standardizedFileURL
                .resolvingSymlinksInPath()
                .path
            return canonicalServicePath == canonicalPath
        }

        return serviceAliases.contains { $0.caseInsensitiveCompare(modelID) == .orderedSame }
    }
}

/// Finds complete MLX model folders without indexing arbitrary user content.
/// Discovery is deliberately bounded and only reads direct model metadata.
public struct LocalModelCatalog: Sendable {
    public let maximumVisitedDirectories: Int
    public let maximumModels: Int
    public let maximumDepth: Int

    public init(
        maximumVisitedDirectories: Int = 800,
        maximumModels: Int = 64,
        maximumDepth: Int = 6
    ) {
        self.maximumVisitedDirectories = max(1, maximumVisitedDirectories)
        self.maximumModels = max(1, maximumModels)
        self.maximumDepth = max(0, maximumDepth)
    }

    public func discover(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        additionalPaths: [String] = [],
        roots customRoots: [URL]? = nil
    ) -> [LocalModelDescriptor] {
        let defaultRoots = [
            homeDirectory.appendingPathComponent("Models/MLX", isDirectory: true),
            homeDirectory.appendingPathComponent("mlx-models", isDirectory: true),
            homeDirectory.appendingPathComponent(".omlx/models", isDirectory: true),
            homeDirectory.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        ]
        let roots = customRoots ?? defaultRoots
        var models: [LocalModelDescriptor] = []
        var canonicalPaths = Set<String>()

        func appendModel(at url: URL) {
            guard models.count < maximumModels,
                  let model = descriptor(at: url),
                  Self.isLikelyTextGenerationModel(model),
                  canonicalPaths.insert(model.canonicalPath).inserted else { return }
            models.append(model)
        }

        for path in additionalPaths where !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            appendModel(at: URL(fileURLWithPath: path, isDirectory: true))
        }

        var queue: [(url: URL, depth: Int)] = roots.map { ($0.standardizedFileURL, 0) }
        var queuedPaths = Set(queue.map { $0.url.path })
        var visited = 0
        var cursor = 0

        while cursor < queue.count,
              visited < maximumVisitedDirectories,
              models.count < maximumModels {
            let item = queue[cursor]
            cursor += 1
            visited += 1

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: item.url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            if descriptor(at: item.url) != nil {
                appendModel(at: item.url)
                continue
            }
            guard item.depth < maximumDepth else { continue }

            let children = (try? FileManager.default.contentsOfDirectory(
                at: item.url,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard queue.count < maximumVisitedDirectories else { break }
                var childIsDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: child.path, isDirectory: &childIsDirectory),
                      childIsDirectory.boolValue,
                      queuedPaths.insert(child.standardizedFileURL.path).inserted else { continue }
                queue.append((child.standardizedFileURL, item.depth + 1))
            }
        }

        return models.sorted {
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if comparison == .orderedSame { return $0.path < $1.path }
            return comparison == .orderedAscending
        }
    }

    public func descriptor(at modelDirectory: URL) -> LocalModelDescriptor? {
        let sourceURL = modelDirectory.standardizedFileURL
        let canonicalURL = sourceURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonicalURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: canonicalURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let weightFiles = files.filter {
            $0.pathExtension.caseInsensitiveCompare("safetensors") == .orderedSame
        }
        let readableWeightSizes = weightFiles.compactMap { file -> Int64? in
            let target = file.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size > 0 else { return nil }
            return Int64(size)
        }
        let expectedWeightNames = Self.expectedWeightNames(in: canonicalURL)
        let presentWeightNames = Set(weightFiles.map(\.lastPathComponent))
        guard files.contains(where: { $0.lastPathComponent == "config.json" }),
              !weightFiles.isEmpty,
              readableWeightSizes.count == weightFiles.count,
              expectedWeightNames.isSubset(of: presentWeightNames) else {
            return nil
        }

        let configURL = canonicalURL.appendingPathComponent("config.json", isDirectory: false)
        let configSize = (try? configURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let configData = configSize <= 4 * 1_024 * 1_024 ? try? Data(contentsOf: configURL) : nil
        let config = (configData
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        let architecture = (config["architectures"] as? [String])?.first
        let modelType = config["model_type"] as? String
        let repositoryName = config["_name_or_path"] as? String
        let quantization = Self.quantizationDescription(config: config)
        let weightBytes = readableWeightSizes.reduce(0, +)
        let repositoryAlias = Self.huggingFaceRepositoryAlias(for: canonicalURL)
        let displayName = Self.displayName(
            sourceURL: sourceURL,
            repositoryName: repositoryName,
            repositoryAlias: repositoryAlias
        )
        let aliases = Self.uniqueNonempty([
            sourceURL.path,
            canonicalURL.path,
            sourceURL.lastPathComponent,
            canonicalURL.lastPathComponent,
            repositoryName,
            repositoryAlias
        ])

        return LocalModelDescriptor(
            path: sourceURL.path,
            canonicalPath: canonicalURL.path,
            displayName: displayName,
            architecture: architecture,
            modelType: modelType,
            quantization: quantization,
            weightBytes: weightBytes,
            serviceAliases: aliases
        )
    }

    private static func displayName(
        sourceURL: URL,
        repositoryName: String?,
        repositoryAlias: String?
    ) -> String {
        let sourceName = sourceURL.lastPathComponent
        if sourceURL.path.contains("/models--"), let repositoryAlias, !repositoryAlias.isEmpty {
            let bitVariant = sourceName.lowercased().hasSuffix("-bit")
                && Int(sourceName.dropLast("-bit".count)) != nil
            if ["snapshots", "main"].contains(sourceName)
                || Self.looksLikeRevision(sourceName)
                || bitVariant {
                return repositoryAlias
            }
            return "\(repositoryAlias) · \(sourceName)"
        }
        if sourceName != "snapshots", sourceName.count >= 3, !Self.looksLikeRevision(sourceName) {
            return sourceName
        }
        if let repositoryName, !repositoryName.isEmpty { return repositoryName }
        if let repositoryAlias, !repositoryAlias.isEmpty { return repositoryAlias }
        return sourceName
    }

    private static func huggingFaceRepositoryAlias(for url: URL) -> String? {
        for component in url.pathComponents.reversed() where component.hasPrefix("models--") {
            let value = String(component.dropFirst("models--".count))
            let pieces = value.components(separatedBy: "--").filter { !$0.isEmpty }
            guard pieces.count >= 2 else { continue }
            return pieces.joined(separator: "/")
        }
        return nil
    }

    private static func quantizationDescription(config: [String: Any]) -> String? {
        let value = (config["quantization_config"] as? [String: Any])
            ?? (config["quantization"] as? [String: Any])
        guard let value else { return nil }

        if let bits = value["bits"] as? Int { return "\(bits)-bit" }
        if let bits = value["bits"] as? NSNumber { return "\(bits.intValue)-bit" }
        if let method = value["quant_method"] as? String, !method.isEmpty { return method }
        return "quantized"
    }

    private static func expectedWeightNames(in modelDirectory: URL) -> Set<String> {
        let indexURL = modelDirectory.appendingPathComponent("model.safetensors.index.json")
        guard let size = try? indexURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size > 0,
              size <= 4 * 1_024 * 1_024,
              let data = try? Data(contentsOf: indexURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let weightMap = root["weight_map"] as? [String: String] else { return [] }
        return Set(weightMap.values)
    }

    private static func looksLikeRevision(_ value: String) -> Bool {
        value.count >= 32 && value.allSatisfy { $0.isHexDigit }
    }

    private static func isLikelyTextGenerationModel(_ model: LocalModelDescriptor) -> Bool {
        let modelType = model.modelType?.lowercased() ?? ""
        let unsupportedTypeFragments = ["whisper", "bert", "clip", "wav2vec", "sentence-transformer"]
        if unsupportedTypeFragments.contains(where: modelType.contains) { return false }

        guard let architecture = model.architecture, !architecture.isEmpty else {
            // Older MLX conversions may omit architectures. Keep them visible;
            // the explicit save/start validation remains the final authority.
            return true
        }
        if architecture.localizedCaseInsensitiveContains("DraftModel") { return false }
        return architecture.localizedCaseInsensitiveContains("CausalLM")
            || architecture.localizedCaseInsensitiveContains("ConditionalGeneration")
    }

    private static func uniqueNonempty(_ values: [String?]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { raw in
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  seen.insert(value.lowercased()).inserted else { return nil }
            return value
        }
    }
}
