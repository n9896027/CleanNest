import SwiftUI
import CleanNestCore

struct PageHeader<Accessory: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let accessory: Accessory

    init(title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                titleBlock
                Spacer(minLength: 12)
                accessory
            }
            VStack(alignment: .leading, spacing: 13) {
                titleBlock
                accessory
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [CNTheme.cyan, CNTheme.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 18, height: 3)
                Text(CNL10n.string("本机工作台"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.tertiary)
            }
            Text(CNL10n.string(title))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .tracking(-0.72)
            Text(CNL10n.string(subtitle))
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 680, alignment: .leading)
        }
    }
}

extension PageHeader where Accessory == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SurfaceCard<Content: View>: View {
    let title: String?
    let symbol: String?
    let prominence: CNSurfaceProminence
    let tint: Color
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        symbol: String? = nil,
        prominence: CNSurfaceProminence = .standard,
        tint: Color = CNTheme.accent,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.prominence = prominence
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let title {
                HStack(spacing: 10) {
                    if let symbol {
                        CNIconTile(symbol: symbol, tint: tint, size: 29)
                    }
                    Text(CNL10n.string(title))
                        .font(.system(size: 15.5, weight: .semibold))
                        .tracking(-0.08)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cnCard(prominence: prominence, tint: tint)
    }
}

struct ContentSectionHeader<Accessory: View>: View {
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color
    @ViewBuilder let accessory: Accessory

    init(
        _ title: String,
        detail: String? = nil,
        symbol: String,
        tint: Color = CNTheme.accent,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 11) {
            CNIconTile(symbol: symbol, tint: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(CNL10n.string(title))
                    .font(.system(size: 15, weight: .semibold))
                if let detail {
                    Text(CNL10n.string(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
    }
}

extension ContentSectionHeader where Accessory == EmptyView {
    init(_ title: String, detail: String? = nil, symbol: String, tint: Color = CNTheme.accent) {
        self.init(title, detail: detail, symbol: symbol, tint: tint) { EmptyView() }
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String
    var tint: Color = CNTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                CNIconTile(symbol: symbol, tint: tint, size: 34)
                Spacer()
                Text(CNL10n.string(label))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .tracking(-0.25)
                .monospacedMetric()
            Text(CNL10n.string(detail))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cnCard()
    }
}

struct CapacityBar: View {
    let used: Int64
    let total: Int64
    var tint: Color = CNTheme.accent

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.13))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint, tint.opacity(0.72)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
        .accessibilityLabel(CNL10n.format("磁盘已使用 %d 百分比", Int(fraction * 100)))
    }
}

struct StatusPill: View {
    enum Style { case neutral, success, warning, danger }

    let text: String
    let symbol: String?
    var style: Style = .neutral

    private var tint: Color {
        switch style {
        case .neutral: return CNTheme.accent
        case .success: return CNTheme.success
        case .warning: return CNTheme.warning
        case .danger: return CNTheme.danger
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol) }
            Text(CNL10n.string(text))
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            Capsule().fill(.ultraThinMaterial)
            Capsule().fill(tint.opacity(0.105))
        }
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 0.65))
    }
}

struct AIFeedbackControl: View {
    let feedback: Bool?
    let onSelect: (Bool) -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(feedback == nil ? "这次建议有帮助吗？" : "已记住本次评价")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                onSelect(true)
            } label: {
                Label("有帮助", systemImage: "hand.thumbsup")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(feedback == true ? CNTheme.success : nil)
            .disabled(feedback != nil)

            Button {
                onSelect(false)
            } label: {
                Label("不准确", systemImage: "hand.thumbsdown")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(feedback == false ? CNTheme.warning : nil)
            .disabled(feedback != nil)
        }
        .accessibilityElement(children: .contain)
    }
}

struct InlineBanner: View {
    enum Kind { case info, success, warning, error }

    let title: String
    let detail: String
    let kind: Kind
    var actionTitle: String?
    var action: (() -> Void)?

    private var tint: Color {
        switch kind {
        case .info: return CNTheme.accent
        case .success: return CNTheme.success
        case .warning: return CNTheme.warning
        case .error: return CNTheme.danger
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 17))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(CNL10n.string(title)).font(.subheadline.weight(.semibold))
                Text(CNL10n.string(detail)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let actionTitle, let action {
                Button(action: action) { Text(CNL10n.string(actionTitle)) }
                    .controlSize(.small)
            }
        }
        .padding(13)
        .background(tint.opacity(0.075), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(tint.opacity(0.2), lineWidth: 0.7))
    }
}

struct EmptyPanel: View {
    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(symbol: String, title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(CNTheme.accent.opacity(0.13))
                    .frame(width: 96, height: 96)
                    .blur(radius: 18)
                Circle()
                    .stroke(CNTheme.accent.opacity(0.16), lineWidth: 1)
                    .frame(width: 82, height: 82)
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 62, height: 62)
                    .overlay(Circle().stroke(Color.white.opacity(0.13), lineWidth: 0.7))
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [CNTheme.cyan, CNTheme.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            Text(CNL10n.string(title))
                .font(.system(size: 17, weight: .semibold))
            Text(CNL10n.string(detail))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(action: action) { Text(CNL10n.string(actionTitle)) }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 310)
        .cnCard()
    }
}

struct OperationBanner: View {
    @EnvironmentObject private var store: AppStore

    private var tint: Color {
        switch store.phase {
        case .success: return CNTheme.success
        case .failed: return CNTheme.danger
        case .checking, .scanning, .executing: return CNTheme.accent
        case .idle: return .clear
        }
    }

    var body: some View {
        if let message = store.phase.message {
            HStack(spacing: 10) {
                if store.phase.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: store.phase == .success(message) ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(tint)
                }
                Text(message).font(.subheadline.weight(.medium))
                Spacer()
                if !store.lastTechnicalDetail.isEmpty && !store.phase.isBusy {
                    Button("详情") { store.showTechnicalDetail() }
                        .buttonStyle(.plain)
                        .foregroundStyle(CNTheme.accent)
                }
                if !store.phase.isBusy {
                    Button { store.dismissPhase() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("关闭提示")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Rectangle().fill(tint.opacity(0.075))
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(tint.opacity(0.22)).frame(height: 0.7)
            }
        }
    }
}

struct ReviewBar: View {
    let count: Int
    let bytes: Int64
    let actionTitle: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(count) 项")
                    .font(.subheadline.weight(.semibold))
                Text("预计可释放 \(CleanNestFormatting.bytes(bytes)) · 移到废纸篓")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: action) { Text(CNL10n.string(actionTitle)) }
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
        }
        .padding(.horizontal, CNTheme.pagePadding)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
