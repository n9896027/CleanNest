import AppKit
import CleanNestCore
import SwiftUI

/// Uses the icon from the locally installed App bundle. CleanNest does not
/// redistribute third-party artwork; a neutral symbol is shown when no exact
/// App identity can be resolved on this Mac.
struct AgentProviderIcon: View {
    let provider: AgentWorkspaceProvider
    let rule: AgentProviderRule?
    let size: CGFloat
    let fallbackTint: Color

    var body: some View {
        AgentLocalAppIcon(size: size, fallbackSymbol: fallbackSymbol, fallbackTint: fallbackTint) {
            AgentAppIconResolver.icon(for: provider, rule: rule)
        }
    }

    private var fallbackSymbol: String {
        switch provider {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .claude: return "terminal"
        case .piAgent: return "circle.hexagongrid"
        case .kimi: return "moon.stars"
        case .workBuddy: return "person.2"
        case .hermes: return "wing"
        case .openClaw: return "pawprint.fill"
        case .trae: return "chevron.left.forwardslash.chevron.right"
        case .miniMaxHub: return "square.grid.2x2"
        case .xiaoyunque: return "bird.fill"
        }
    }
}

struct AgentDesktopProductIcon: View {
    let installation: AgentDesktopInstallation
    let size: CGFloat

    var body: some View {
        AgentLocalAppIcon(size: size, fallbackSymbol: "desktopcomputer", fallbackTint: CNTheme.accent) {
            AgentAppIconResolver.icon(for: installation)
        }
    }
}

private struct AgentLocalAppIcon: View {
    let size: CGFloat
    let fallbackSymbol: String
    let fallbackTint: Color
    let resolve: () -> NSImage?

    var body: some View {
        Group {
            if let icon = resolve() {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: .black.opacity(0.16), radius: max(1, size * 0.08), y: 1)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(fallbackTint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        fallbackTint.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

@MainActor
private enum AgentAppIconResolver {
    private struct Cached {
        let signature: String
        let image: NSImage?
    }

    private static var cache: [String: Cached] = [:]
    private static var ruleRevision = AgentRuleCatalog.builtIn.revision

    static func refreshRules(revision: String) {
        guard ruleRevision != revision else { return }
        ruleRevision = revision
        cache.removeAll()
    }

    static func icon(for installation: AgentDesktopInstallation) -> NSImage? {
        refreshRules(revision: installation.ruleRevision)
        let signature = fileSignature(at: installation.application.url)
        return cached(
            key: installation.cacheKey,
            signature: signature,
            appURL: installation.application.url
        )
    }

    static func icon(for provider: AgentWorkspaceProvider, rule suppliedRule: AgentProviderRule?) -> NSImage? {
        guard let rule = suppliedRule ?? AgentRuleCatalog.builtIn.rule(for: provider) else { return nil }
        for identifier in rule.bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                let key = ([provider.rawValue, identifier, appURL.standardizedFileURL.path] + [ruleRevision])
                    .joined(separator: "|")
                return cached(key: key, signature: fileSignature(at: appURL), appURL: appURL)
            }
        }

        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for name in rule.applicationNames {
            for root in applicationRoots {
                let appURL = root.appendingPathComponent(name).appendingPathExtension("app")
                guard FileManager.default.fileExists(atPath: appURL.path) else { continue }
                let key = ([provider.rawValue, name, appURL.standardizedFileURL.path, ruleRevision]).joined(separator: "|")
                return cached(key: key, signature: fileSignature(at: appURL), appURL: appURL)
            }
        }
        return nil
    }

    private static func cached(key: String, signature: String, appURL: URL) -> NSImage? {
        if let cached = cache[key], cached.signature == signature { return cached.image }
        cache.removeValue(forKey: key)
        guard appURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              FileManager.default.fileExists(atPath: appURL.path) else {
            cache[key] = Cached(signature: signature, image: nil)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: appURL.path)
        cache[key] = Cached(signature: signature, image: image)
        return image
    }

    private static func fileSignature(at url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let file = (attributes?[.systemFileNumber] as? NSNumber)?.stringValue ?? "missing"
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let bundle = Bundle(url: url)
        let build = bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return [file, String(modified), build].joined(separator: ":")
    }
}
