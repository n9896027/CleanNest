import SwiftUI

/// CleanNest's canonical brand mark. Its colors and geometry are intentionally
/// fixed so the sidebar, About surface, Dock icon, and release artwork cannot
/// drift into separate logo variants.
struct CNNestMark: View {
    var size: CGFloat = 40
    var castsShadow = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [CNNestBrandPalette.cyan, CNNestBrandPalette.mint, CNNestBrandPalette.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            ForEach(0..<3, id: \.self) { index in
                Ellipse()
                    .trim(from: 0.08, to: 0.84)
                    .stroke(
                        Color.white.opacity(0.52 - Double(index) * 0.10),
                        style: StrokeStyle(
                            lineWidth: max(0.8, size * 0.045),
                            lineCap: .round
                        )
                    )
                    .frame(
                        width: size * (0.68 - CGFloat(index) * 0.14),
                        height: size * (0.42 - CGFloat(index) * 0.07)
                    )
                    .rotationEffect(.degrees(-12))
                    .offset(y: size * (0.11 + CGFloat(index) * 0.015))
            }

            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.white)
                .offset(x: size * 0.13, y: -size * 0.12)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .stroke(Color.white.opacity(0.30), lineWidth: max(0.7, size * 0.012))
        }
        .shadow(
            color: castsShadow ? CNNestBrandPalette.mint.opacity(0.24) : .clear,
            radius: castsShadow ? size * 0.22 : 0,
            y: castsShadow ? size * 0.10 : 0
        )
        .accessibilityHidden(true)
    }
}

/// Square artwork used by the icon generator. The transparent outer inset is
/// part of the canonical macOS app-icon composition, not a second logo.
struct CNNestAppIconArtwork: View {
    let size: CGFloat

    var body: some View {
        CNNestMark(size: size * 0.89, castsShadow: false)
            .frame(width: size, height: size)
    }
}

private enum CNNestBrandPalette {
    static let cyan = Color(red: 0.16, green: 0.76, blue: 0.86)
    static let mint = Color(red: 0.20, green: 0.72, blue: 0.53)
    static let blue = Color(red: 0.20, green: 0.39, blue: 0.91)
}
