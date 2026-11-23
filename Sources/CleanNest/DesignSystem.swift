import AppKit
import SwiftUI
import CleanNestCore

enum CNTheme {
    static let accent = Color(red: 0.30, green: 0.55, blue: 0.98)
    static let accentStrong = Color(red: 0.20, green: 0.39, blue: 0.91)
    static let cyan = Color(red: 0.16, green: 0.76, blue: 0.86)
    static let mint = Color(red: 0.20, green: 0.72, blue: 0.53)
    static let violet = Color(red: 0.57, green: 0.43, blue: 0.96)
    static let success = Color(red: 0.20, green: 0.67, blue: 0.46)
    static let warning = Color(red: 0.82, green: 0.53, blue: 0.10)
    static let danger = Color(red: 0.83, green: 0.31, blue: 0.30)

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color.clear
    static let surface = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let surfaceElevated = Color(nsColor: .textBackgroundColor).opacity(0.66)
    static let surfaceSubtle = Color(nsColor: .underPageBackgroundColor)
    static let divider = Color(nsColor: .separatorColor).opacity(0.54)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    static let pagePadding: CGFloat = 24
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 11
    static let contentMaxWidth: CGFloat = 1_280
}

enum AppMetadata {
    static var shortVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    static var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static var displayVersion: String {
        guard let shortVersion, !shortVersion.isEmpty else {
            return CNL10n.string("CleanNest · 开发构建")
        }
        guard let build, !build.isEmpty else {
            return "CleanNest \(shortVersion)"
        }
        return CNL10n.format("CleanNest %@ · 构建 %@", shortVersion, build)
    }

    static var compactDisplayVersion: String {
        guard let shortVersion, !shortVersion.isEmpty else {
            return CNL10n.string("CleanNest · 开发构建")
        }
        guard let build, !build.isEmpty else {
            return "CleanNest \(shortVersion)"
        }
        return "CleanNest \(shortVersion) (\(build))"
    }
}

struct AppCanvas: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                CNVisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow)
            }

            Color(nsColor: .windowBackgroundColor)
                .opacity(colorScheme == .dark ? 0.55 : 0.30)

            LinearGradient(
                colors: [CNTheme.cyan.opacity(reduceTransparency ? 0 : 0.045), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }
}

struct CNVisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.isEmphasized = false
        view.material = material
        view.blendingMode = blendingMode
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

struct CNWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { configure(view.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
    }
}

struct CNIconTile: View {
    let symbol: String
    var tint: Color = CNTheme.accent
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.19), tint.opacity(0.07)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.24), tint.opacity(0.15), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
        )
    }
}

enum CNSurfaceProminence {
    case standard
    case prominent
    case quiet
}

private struct CNGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominence: CNSurfaceProminence
    let tint: Color

    private var radius: CGFloat {
        prominence == .prominent ? 20 : CNTheme.cardRadius
    }

    private var shadowOpacity: Double {
        switch prominence {
        case .prominent: return 0.07
        case .standard: return 0.025
        case .quiet: return 0
        }
    }

    func body(content: Content) -> some View {
        content
            .padding(prominence == .prominent ? 20 : CNTheme.cardPadding)
            .background {
                ZStack {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(prominence == .quiet ? .ultraThinMaterial : .thinMaterial)
                    }
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: prominence == .prominent
                                    ? [tint.opacity(0.09), tint.opacity(0.025), Color.clear]
                                    : [Color.white.opacity(colorScheme == .dark ? 0.045 : 0.22), tint.opacity(0.018), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.17 : 0.50),
                                tint.opacity(prominence == .prominent ? 0.24 : 0.08),
                                Color.primary.opacity(0.035)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            }
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 8, y: 3)
    }
}

extension View {
    func cnCard(
        prominence: CNSurfaceProminence = .standard,
        tint: Color = CNTheme.accent
    ) -> some View {
        modifier(CNGlassSurfaceModifier(prominence: prominence, tint: tint))
    }

    func cnHeroPanel() -> some View {
        cnCard(prominence: .prominent, tint: CNTheme.accent)
    }

    func cnInsetPanel() -> some View {
        self
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.65)
            )
    }

    func monospacedMetric() -> some View {
        self.monospacedDigit()
    }
}

extension Color {
    static func outcome(_ outcome: ActivityEntry.Outcome) -> Color {
        switch outcome {
        case .success: return CNTheme.success
        case .partial: return CNTheme.warning
        case .failed: return CNTheme.danger
        }
    }
}
