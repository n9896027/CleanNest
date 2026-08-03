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
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 27, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            accessory
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
    @ViewBuilder let content: Content

    init(title: String? = nil, symbol: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 7) {
                    if let symbol {
                        Image(systemName: symbol)
                            .foregroundStyle(CNTheme.accent)
                    }
                    Text(title)
                        .font(.headline)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cnCard()
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let symbol: String
    var tint: Color = CNTheme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedMetric()
            Text(detail)
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
                    .fill(tint)
                    .frame(width: max(6, proxy.size.width * fraction))
            }
        }
        .frame(height: 8)
        .accessibilityLabel("磁盘已使用 \(Int(fraction * 100)) 百分比")
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
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.1), in: Capsule())
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
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
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
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(CNTheme.accent)
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
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
            .background(tint.opacity(0.08))
            .overlay(alignment: .top) { Divider() }
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
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(disabled)
        }
        .padding(.horizontal, CNTheme.pagePadding)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
