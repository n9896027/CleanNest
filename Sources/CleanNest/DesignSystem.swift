import AppKit
import SwiftUI

enum CNTheme {
    static let accent = Color(red: 0.29, green: 0.40, blue: 0.82)
    static let success = Color(red: 0.18, green: 0.53, blue: 0.35)
    static let warning = Color(red: 0.75, green: 0.45, blue: 0.04)
    static let danger = Color(red: 0.78, green: 0.27, blue: 0.27)

    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceSubtle = Color(nsColor: .underPageBackgroundColor)
    static let divider = Color(nsColor: .separatorColor).opacity(0.75)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    static let pagePadding: CGFloat = 24
    static let cardPadding: CGFloat = 18
    static let cardRadius: CGFloat = 13
    static let controlRadius: CGFloat = 8
}

extension View {
    func cnCard() -> some View {
        self
            .padding(CNTheme.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: CNTheme.cardRadius, style: .continuous)
                    .fill(CNTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: CNTheme.cardRadius, style: .continuous)
                            .stroke(CNTheme.divider, lineWidth: 0.7)
                    )
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
