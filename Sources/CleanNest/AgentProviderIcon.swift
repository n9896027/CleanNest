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
        Group {
            if let icon = AgentAppIconResolver.icon(for: provider, rule: rule) {
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

@MainActor
private enum AgentAppIconResolver {
    private static var cache: [String: NSImage] = [:]
    private static var misses = Set<String>()

    static func icon(for provider: AgentWorkspaceProvider, rule suppliedRule: AgentProviderRule?) -> NSImage? {
        let rule = suppliedRule ?? AgentRuleCatalog.builtIn.rule(for: provider)
        guard let rule else { return nil }
        let key = ([provider.rawValue] + rule.bundleIdentifiers + rule.applicationNames)
            .joined(separator: "|")
            .lowercased()
        if let cached = cache[key] { return cached }
        if misses.contains(key) { return nil }

        for identifier in rule.bundleIdentifiers {
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
               let image = icon(at: appURL) {
                cache[key] = image
                return image
            }
        }

        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        for name in rule.applicationNames {
            for root in applicationRoots {
                let appURL = root.appendingPathComponent(name).appendingPathExtension("app")
                if let image = icon(at: appURL) {
                    cache[key] = image
                    return image
                }
            }
        }

        misses.insert(key)
        return nil
    }

    private static func icon(at appURL: URL) -> NSImage? {
        guard appURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              FileManager.default.fileExists(atPath: appURL.path) else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}
