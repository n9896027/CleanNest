import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import CleanNestCore

extension MenuBarMetric {
    var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .temperature: return "温度"
        case .network: return "网络"
        case .disk: return "磁盘"
        case .gpu: return "GPU"
        case .fan: return "风扇"
        case .battery: return "电池"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .temperature: return "thermometer.medium"
        case .network: return "arrow.up.arrow.down"
        case .disk: return "internaldrive"
        case .gpu: return "rectangle.3.group"
        case .fan: return "fan"
        case .battery: return "battery.75percent"
        }
    }

    var tint: Color {
        switch self {
        case .cpu: return CNTheme.accent
        case .memory: return CNTheme.violet
        case .temperature: return CNTheme.warning
        case .network: return CNTheme.cyan
        case .disk: return CNTheme.success
        case .gpu: return CNTheme.mint
        case .fan: return Color.teal
        case .battery: return CNTheme.success
        }
    }

    var normalizedGraphRange: ClosedRange<Double>? {
        switch self {
        case .cpu, .memory, .disk, .gpu, .battery: return 0...100
        case .temperature: return 20...105
        case .network, .fan: return nil
        }
    }

    var compactLabel: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "MEM"
        case .temperature: return "TEMP"
        case .network: return "NET"
        case .disk: return "SSD"
        case .gpu: return "GPU"
        case .fan: return "FAN"
        case .battery: return "BAT"
        }
    }
}

extension NativeMetricHealthLevel {
    var menuBarMarker: String {
        switch self {
        case .normal: return ""
        case .warning: return "!"
        case .critical: return "!!"
        }
    }

    var highlightColor: Color? {
        switch self {
        case .normal: return nil
        case .warning: return CNTheme.warning
        case .critical: return CNTheme.danger
        }
    }

    var highlightNSColor: NSColor? {
        switch self {
        case .normal: return nil
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    var badgeText: String? {
        switch self {
        case .normal: return nil
        case .warning: return "警告"
        case .critical: return "严重"
        }
    }

    var badgeSymbol: String? {
        switch self {
        case .normal: return nil
        case .warning: return "exclamationmark"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    var badgeStyle: StatusPill.Style {
        switch self {
        case .normal: return .neutral
        case .warning: return .warning
        case .critical: return .danger
        }
    }
}

struct NativeMetricReading: Equatable {
    let values: [String]
    let accessibilityValue: String
}

extension NativeMonitorSample {
    func healthSummary(_ metric: MenuBarMetric) -> String? {
        switch (metric, healthLevel(for: metric)) {
        case (_, .normal): return nil
        case (.memory, .warning): return "内存压力警告"
        case (.memory, .critical): return "内存压力严重"
        case (.temperature, .warning): return "温度偏高"
        case (.temperature, .critical): return "温度过高"
        case (.disk, .warning): return "磁盘空间紧张"
        case (.disk, .critical): return "磁盘空间严重不足"
        case (.fan, .warning): return "风扇高速散热"
        case (.fan, .critical): return "高温与风扇高负载"
        case (.battery, .warning): return "电量较低"
        case (.battery, .critical): return "电量严重不足"
        case (.cpu, _), (.network, _), (.gpu, _): return nil
        }
    }

    func isAvailable(_ metric: MenuBarMetric) -> Bool {
        switch metric {
        case .temperature:
            return temperatureCelsius != nil || batteryTemperatureCelsius != nil
        case .fan:
            return fanCount.map { $0 > 0 } == true && fanRPM != nil
        case .battery:
            return batteryLevel != nil
        default:
            return value(for: metric) != nil
        }
    }

    func menuBarValue(
        _ metric: MenuBarMetric,
        temperatureUnit: MenuBarTemperatureUnit = .celsius
    ) -> String {
        switch metric {
        case .cpu:
            return "CPU " + compactPercent(cpuUsage)
        case .memory:
            return "内存 " + compactPercent(memoryUsedPercent)
        case .temperature:
            return "温度 " + compactTemperature(temperatureUnit)
        case .network:
            return "↓" + compactRate(networkDownloadBytesPerSecond)
                + " ↑" + compactRate(networkUploadBytesPerSecond)
        case .disk:
            return "磁盘 " + compactPercent(diskUsedPercent)
        case .gpu:
            return "GPU " + compactPercent(gpuUsage)
        case .fan:
            return fanRPM.map { "风扇 " + String(Int($0.rounded())) } ?? "风扇 —"
        case .battery:
            return "电池 " + compactPercent(batteryLevel)
        }
    }

    func compactTopValue(
        _ metric: MenuBarMetric,
        temperatureUnit: MenuBarTemperatureUnit
    ) -> String {
        switch metric {
        case .cpu: return compactPercent(cpuUsage)
        case .memory: return compactPercent(memoryUsedPercent)
        case .temperature: return compactTemperature(temperatureUnit)
        case .network:
            return "↓" + compactRate(networkDownloadBytesPerSecond)
                + " ↑" + compactRate(networkUploadBytesPerSecond)
        case .disk: return compactPercent(diskUsedPercent)
        case .gpu: return compactPercent(gpuUsage)
        case .fan: return fanRPM.map { String(Int($0.rounded())) } ?? "—"
        case .battery: return compactPercent(batteryLevel)
        }
    }

    func detailedValue(
        _ metric: MenuBarMetric,
        temperatureUnit: MenuBarTemperatureUnit = .celsius
    ) -> String {
        metricReading(metric, temperatureUnit: temperatureUnit).accessibilityValue
    }

    func metricReading(
        _ metric: MenuBarMetric,
        temperatureUnit: MenuBarTemperatureUnit = .celsius
    ) -> NativeMetricReading {
        switch metric {
        case .cpu:
            let value = compactPercent(cpuUsage)
            return NativeMetricReading(values: [value], accessibilityValue: value)
        case .memory:
            guard let percent = memoryUsedPercent else {
                return NativeMetricReading(values: ["暂不可用"], accessibilityValue: "暂不可用")
            }
            let percentText = compactPercent(percent)
            if let used = memoryUsedBytes, let total = memoryTotalBytes {
                let usedText = CleanNestFormatting.bytes(used)
                let totalText = CleanNestFormatting.bytes(total)
                return NativeMetricReading(
                    values: [percentText, usedText + " / " + totalText],
                    accessibilityValue: percentText + "，已用 " + usedText + "，总计 " + totalText
                )
            }
            return NativeMetricReading(values: [percentText], accessibilityValue: percentText)
        case .temperature:
            var values: [String] = []
            var accessibility: [String] = []
            if let temperatureCelsius {
                let value = temperatureText(temperatureCelsius, unit: temperatureUnit)
                values.append("CPU " + value)
                accessibility.append("CPU 温度 " + value)
            }
            if let batteryTemperatureCelsius {
                let value = temperatureText(batteryTemperatureCelsius, unit: temperatureUnit)
                values.append("电池 " + value)
                accessibility.append("电池温度 " + value)
            }
            guard !values.isEmpty else {
                return NativeMetricReading(values: ["暂不可用"], accessibilityValue: "暂不可用")
            }
            return NativeMetricReading(
                values: values,
                accessibilityValue: accessibility.joined(separator: "，")
            )
        case .network:
            guard networkDownloadBytesPerSecond != nil || networkUploadBytesPerSecond != nil else {
                return NativeMetricReading(values: ["暂不可用"], accessibilityValue: "暂不可用")
            }
            let download = readableRate(networkDownloadBytesPerSecond)
            let upload = readableRate(networkUploadBytesPerSecond)
            return NativeMetricReading(
                values: ["↓ " + download, "↑ " + upload],
                accessibilityValue: "下载 " + download + "，上传 " + upload
            )
        case .disk:
            guard let percent = diskUsedPercent else {
                return NativeMetricReading(values: ["暂不可用"], accessibilityValue: "暂不可用")
            }
            let percentText = compactPercent(percent)
            if let free = diskFreeBytes {
                let freeText = CleanNestFormatting.bytes(free)
                return NativeMetricReading(
                    values: [percentText, "可用 " + freeText],
                    accessibilityValue: percentText + "，可用 " + freeText
                )
            }
            return NativeMetricReading(values: [percentText], accessibilityValue: percentText)
        case .gpu:
            let renderer = gpuRendererUsage.map { "R " + compactPercent($0) }
            let tiler = gpuTilerUsage.map { "T " + compactPercent($0) }
            let parts = [renderer, tiler].compactMap { $0 }
            let total = compactPercent(gpuUsage)
            let values = [total] + (parts.isEmpty ? [] : [parts.joined(separator: " / ")])
            return NativeMetricReading(
                values: values,
                accessibilityValue: values.joined(separator: "，")
            )
        case .fan:
            if fanCount == 0 {
                return NativeMetricReading(
                    values: ["这台 Mac 没有风扇"],
                    accessibilityValue: "这台 Mac 没有风扇"
                )
            }
            if !fanSpeedsRPM.isEmpty {
                let values = fanSpeedsRPM.enumerated().map {
                    "F\($0.offset + 1) " + String(Int($0.element.rounded())) + " RPM"
                }
                return NativeMetricReading(
                    values: values,
                    accessibilityValue: values.joined(separator: "，")
                )
            }
            let value = fanRPM.map { String(Int($0.rounded())) + " RPM" } ?? "暂不可用"
            return NativeMetricReading(values: [value], accessibilityValue: value)
        case .battery:
            guard let level = batteryLevel else {
                let value = batteryStatus ?? "暂不可用"
                return NativeMetricReading(values: [value], accessibilityValue: value)
            }
            let time = batteryTimeRemainingMinutes.map {
                String(format: "%d:%02d", $0 / 60, $0 % 60)
            }
            let values = [compactPercent(level), batteryStatus, time].compactMap { $0 }
            return NativeMetricReading(
                values: values,
                accessibilityValue: values.joined(separator: "，")
            )
        }
    }

    func sourceDescription(_ metric: MenuBarMetric) -> String {
        let stale = Date().timeIntervalSince(sampledAt) > 6 ? " · 样本已过期" : ""
        let source: String
        switch metric {
        case .cpu:
            let parts = [
                cpuUserPercent.map { "用户 " + compactPercent($0) },
                cpuSystemPercent.map { "系统 " + compactPercent($0) },
                cpuIdlePercent.map { "空闲 " + compactPercent($0) }
            ].compactMap { $0 }
            source = parts.isEmpty ? "Mach 处理器计数" : parts.joined(separator: " · ")
        case .memory:
            let pressure: String
            switch memoryPressureLevel {
            case .normal: pressure = "压力正常"
            case .warning: pressure = "压力警告"
            case .critical: pressure = "压力严重"
            case .unknown: pressure = "压力未知"
            }
            source = "Mach VM · " + pressure
        case .temperature:
            var sources: [String] = []
            if temperatureCelsius != nil {
                sources.append(temperatureSource ?? "AppleSMC CPU 温度")
            }
            if batteryTemperatureCelsius != nil {
                sources.append(batteryTemperatureSource ?? "IOKit 电池温度")
            }
            switch thermalState {
            case .fair: sources.append(CNL10n.string("macOS 热状态：需要留意"))
            case .serious: sources.append(CNL10n.string("macOS 热状态：严重"))
            case .critical: sources.append(CNL10n.string("macOS 热状态：临界"))
            case .nominal, .unknown: break
            }
            source = sources.isEmpty ? "未返回有效温度" : sources.joined(separator: " · ")
        case .network:
            if let networkInterfaceName {
                let interfaces = networkInterfaceName.components(separatedBy: " + ")
                source = interfaces.count > 1
                    ? String(interfaces.count) + " 个物理接口合计"
                    : networkInterfaceName + " · 当前统计接口"
            } else {
                source = "未找到选定的活动接口"
            }
        case .disk:
            let read = diskReadBytesPerSecond.map { "读 " + readableRate($0) }
            let write = diskWriteBytesPerSecond.map { "写 " + readableRate($0) }
            let throughput = [read, write].compactMap { $0 }.joined(separator: " · ")
            source = throughput.isEmpty ? "macOS 启动卷容量" : "启动卷 · " + throughput
        case .gpu:
            source = "IOAccelerator 性能计数"
        case .fan:
            if fanCount == 0 {
                source = "AppleSMC 报告 0 个风扇"
            } else if let fanCount {
                let load = fanLoadPercent.map { " · 约 " + compactPercent($0) + " 最大转速" } ?? ""
                source = "AppleSMC · " + String(fanCount) + " 个风扇" + load
            } else {
                source = "AppleSMC 未返回风扇信息"
            }
        case .battery:
            source = batteryStatus ?? "IOKit 未返回内置电池"
        }
        return source + stale
    }

    private func compactPercent(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) + "%" } ?? "—"
    }

    private func compactRate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value >= 1_000_000_000 { return String(format: "%.1fG", value / 1_000_000_000) }
        if value >= 1_000_000 { return String(format: "%.1fM", value / 1_000_000) }
        if value >= 1_000 { return String(format: "%.0fK", value / 1_000) }
        return String(Int(max(0, value))) + "B"
    }

    private func compactTemperature(_ unit: MenuBarTemperatureUnit) -> String {
        guard let value = temperatureCelsius ?? batteryTemperatureCelsius else { return "—" }
        let converted = unit == .celsius ? value : value * 9 / 5 + 32
        return String(Int(converted.rounded())) + "°"
    }

    private func temperatureText(_ value: Double, unit: MenuBarTemperatureUnit) -> String {
        let converted = unit == .celsius ? value : value * 9 / 5 + 32
        let suffix = unit == .celsius ? "°C" : "°F"
        return String(format: "%.1f", converted) + suffix
    }

    private func readableRate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return CleanNestFormatting.bytes(Int64(max(0, value))) + "/s"
    }
}

struct NativeMetricReadingView: View {
    let reading: NativeMetricReading
    var font: Font
    var spacing: CGFloat = 7

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: spacing) {
                ForEach(reading.values.indices, id: \.self) { index in
                    if index > 0 {
                        Text("·")
                            .font(font)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    Text(reading.values[index])
                        .font(font)
                        .monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                ForEach(reading.values.indices, id: \.self) { index in
                    Text(reading.values[index])
                        .font(font)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.accessibilityValue)
    }
}

@MainActor
final class MenuBarMonitorController: NSObject, NSPopoverDelegate {
    private weak var store: AppStore?
    private var statusItems: [MenuBarMetric: NSStatusItem] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let popover = NSPopover()
    private var lastMetricOrder: [MenuBarMetric] = []
    private var hotKeyController: GlobalHotKeyController?

    func connect(store: AppStore) {
        guard self.store !== store else { return }
        self.store = store
        cancellables.removeAll()
        if hotKeyController == nil {
            hotKeyController = GlobalHotKeyController { [weak self] in
                self?.togglePopover()
            }
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 390, height: 500)

        Publishers.CombineLatest(
            store.$menuBarConfiguration,
            store.$nativeMonitorSample
        )
        .receive(on: RunLoop.main)
        .sink { [weak self, weak store] configuration, sample in
            self?.updateStatusItems(
                configuration: configuration,
                sample: sample,
                history: store?.nativeMonitorHistory ?? []
            )
        }
        .store(in: &cancellables)
    }

    private func updateStatusItems(
        configuration: MenuBarMonitorConfiguration,
        sample: NativeMonitorSample?,
        history: [NativeMonitorSample]
    ) {
        let hotKeyStatus = hotKeyController?.setEnabled(
            configuration.isEnabled && configuration.globalHotKeyEnabled
        ) ?? OSStatus(eventNotHandledErr)
        if !configuration.globalHotKeyEnabled {
            store?.setGlobalHotKeyDiagnostic("全局快捷键已关闭。")
        } else if hotKeyStatus == noErr {
            store?.setGlobalHotKeyDiagnostic("⌘⌥M 已由 macOS 注册，不需要辅助功能权限。")
        } else {
            store?.setGlobalHotKeyDiagnostic(
                "⌘⌥M 注册失败（系统状态 \(hotKeyStatus)），可能已被其他 App 占用。"
            )
        }
        guard configuration.isEnabled else {
            removeAllStatusItems()
            return
        }

        let desiredOrder = configuration.metrics.compactMap { preference -> MenuBarMetric? in
            guard preference.isEnabled, sample?.isAvailable(preference.metric) == true else { return nil }
            return preference.metric
        }
        let desired = Set(desiredOrder)
        if desiredOrder != lastMetricOrder {
            removeAllStatusItems()
            lastMetricOrder = desiredOrder
        }
        for metric in statusItems.keys where !desired.contains(metric) {
            removeStatusItem(metric)
        }

        // NSStatusBar inserts newly created items from right to left. Creating
        // them in reverse preserves the order shown in Settings from left to right.
        for metric in desiredOrder.reversed() {
            let item = statusItems[metric] ?? makeStatusItem(metric)
            guard let button = item.button, let sample else { continue }
            let preference = configuration.preference(for: metric)
            let healthLevel = sample.healthLevel(for: metric)
            let healthSummary = sample.healthSummary(metric).map(CNL10n.string)
            button.target = self
            button.action = #selector(statusItemPressed(_:))
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = metric.displayName + " · " + sample.detailedValue(
                metric,
                temperatureUnit: configuration.temperatureUnit
            )
                + (healthSummary.map { "\n" + $0 } ?? "")
                + "\n" + sample.sourceDescription(metric)
            button.setAccessibilityLabel(
                metric.displayName + " " + sample.detailedValue(
                    metric,
                    temperatureUnit: configuration.temperatureUnit
                )
                    + (healthSummary.map { "，" + $0 } ?? "")
            )

            switch preference.style {
            case .text:
                switch configuration.presentationMode {
                case .compact:
                    let image = compactMetricImage(
                        topValue: sample.compactTopValue(
                            metric,
                            temperatureUnit: configuration.temperatureUnit
                        ),
                        bottomLabel: metric.compactLabel,
                        healthLevel: healthLevel
                    )
                    item.length = image.size.width + 4
                    button.title = ""
                    button.attributedTitle = NSAttributedString(string: "")
                    button.imagePosition = .imageOnly
                    button.image = image
                case .separate:
                    item.length = NSStatusItem.variableLength
                    button.image = nil
                    button.imagePosition = .noImage
                    let title = sample.menuBarValue(
                        metric,
                        temperatureUnit: configuration.temperatureUnit
                    ) + (healthLevel.menuBarMarker.isEmpty ? "" : " " + healthLevel.menuBarMarker)
                    button.attributedTitle = NSAttributedString(
                        string: title,
                        attributes: [
                            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                            .foregroundColor: healthLevel.highlightNSColor ?? NSColor.labelColor
                        ]
                    )
                }
            case .graph:
                item.length = configuration.presentationMode == .compact ? 44 : 42
                button.title = ""
                button.attributedTitle = NSAttributedString(string: "")
                button.imagePosition = .imageOnly
                button.image = sparklineImage(
                    values: history.compactMap { $0.value(for: metric) },
                    range: metric.normalizedGraphRange,
                    label: configuration.presentationMode == .compact ? metric.compactLabel : nil,
                    healthLevel: healthLevel
                )
            }
        }

        DispatchQueue.main.async { [weak self] in
            self?.publishVisibilityDiagnostic(configuration: configuration, order: desiredOrder)
        }
    }

    private func makeStatusItem(_ metric: MenuBarMetric) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "CleanNest.MenuBar." + metric.rawValue
        statusItems[metric] = item
        return item
    }

    private func removeStatusItem(_ metric: MenuBarMetric) {
        guard let item = statusItems.removeValue(forKey: metric) else { return }
        NSStatusBar.system.removeStatusItem(item)
    }

    private func removeAllStatusItems() {
        for metric in Array(statusItems.keys) { removeStatusItem(metric) }
        popover.performClose(nil)
    }

    func togglePopover() {
        guard let store else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        let order = store.menuBarConfiguration.metrics.filter(\.isEnabled).map(\.metric)
        let preferred = store.menuBarConfiguration.compactMetric
        let metric = statusItems[preferred] != nil
            ? preferred
            : (order.first(where: { statusItems[$0] != nil }) ?? .cpu)
        guard let button = statusItems[metric]?.button else {
            store.showMainWindow(selection: .status)
            return
        }
        showPopover(metric: metric, relativeTo: button)
    }

    @objc private func statusItemPressed(_ sender: NSStatusBarButton) {
        guard store != nil,
              let metric = statusItems.first(where: { $0.value.button === sender })?.key else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        showPopover(metric: metric, relativeTo: sender)
    }

    private func showPopover(metric: MenuBarMetric, relativeTo sender: NSStatusBarButton) {
        guard let store else { return }
        popover.contentViewController = NSHostingController(
            rootView: MenuBarMonitorPopover(focusedMetric: metric)
                .environmentObject(store)
        )
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func publishVisibilityDiagnostic(
        configuration: MenuBarMonitorConfiguration,
        order: [MenuBarMetric]
    ) {
        guard let store else { return }
        let hidden = order.filter { statusItems[$0]?.isVisible == false }
        if !hidden.isEmpty {
            store.setMenuBarVisibilityDiagnostic(
                "macOS 已隐藏 " + hidden.map(\.displayName).joined(separator: "、")
                    + "；可关闭部分项目，或保持“双层紧凑”。"
            )
        } else if configuration.presentationMode == .compact {
            store.setMenuBarVisibilityDiagnostic(
                "\(order.count) 项已以双层短标签显示，比展开文字更节省宽度。"
            )
        } else {
            store.setMenuBarVisibilityDiagnostic("\(order.count) 项已以展开文字显示。")
        }
    }

    private func compactMetricImage(
        topValue: String,
        bottomLabel: String,
        healthLevel: NativeMetricHealthLevel
    ) -> NSImage {
        let displayedLabel = bottomLabel + healthLevel.menuBarMarker
        let width = max(30, min(70, CGFloat(max(topValue.count, displayedLabel.count)) * 7 + 8))
        let size = NSSize(width: width, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let stateColor = healthLevel.highlightNSColor
            if let stateColor {
                stateColor.setFill()
                NSBezierPath(
                    roundedRect: NSRect(x: 1, y: 8.5, width: rect.width - 2, height: 13),
                    xRadius: 4.5,
                    yRadius: 4.5
                ).fill()
            }
            (topValue as NSString).draw(
                in: NSRect(x: 0, y: 9, width: rect.width, height: 12),
                withAttributes: [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10.2, weight: .semibold),
                    .foregroundColor: stateColor == nil ? NSColor.labelColor : NSColor.white,
                    .paragraphStyle: paragraph
                ]
            )
            (displayedLabel as NSString).draw(
                in: NSRect(x: 0, y: 0, width: rect.width, height: 9),
                withAttributes: [
                    .font: NSFont.systemFont(
                        ofSize: 6.8,
                        weight: healthLevel == .normal ? .medium : .bold
                    ),
                    .foregroundColor: stateColor ?? NSColor.labelColor,
                    .paragraphStyle: paragraph,
                    .kern: 0.25
                ]
            )
            return true
        }
        image.isTemplate = healthLevel == .normal
        return image
    }

    private func sparklineImage(
        values: [Double],
        range fixedRange: ClosedRange<Double>?,
        label: String? = nil,
        healthLevel: NativeMetricHealthLevel
    ) -> NSImage {
        let size = NSSize(width: 38, height: label == nil ? 16 : 22)
        let recent = Array(values.suffix(36))
        let image = NSImage(size: size, flipped: false) { rect in
            let graphBottom: CGFloat = label == nil ? 1 : 8
            guard recent.count > 1 else {
                (healthLevel.highlightNSColor ?? NSColor.secondaryLabelColor).setStroke()
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 2, y: graphBottom + 5))
                line.line(to: NSPoint(x: rect.maxX - 2, y: graphBottom + 5))
                line.lineWidth = 1
                line.stroke()
                if let label {
                    self.drawCompactLabel(
                        label + healthLevel.menuBarMarker,
                        in: rect,
                        color: healthLevel.highlightNSColor
                    )
                }
                return true
            }
            let lower = fixedRange?.lowerBound ?? recent.min() ?? 0
            let upperCandidate = fixedRange?.upperBound ?? recent.max() ?? 1
            let upper = upperCandidate > lower ? upperCandidate : lower + 1
            let path = NSBezierPath()
            for (index, value) in recent.enumerated() {
                let fraction = CGFloat(index) / CGFloat(max(1, recent.count - 1))
                let normalized = CGFloat(min(1, max(0, (value - lower) / (upper - lower))))
                let point = NSPoint(
                    x: 1 + fraction * (rect.width - 2),
                    y: graphBottom + normalized * (rect.height - graphBottom - 1)
                )
                index == 0 ? path.move(to: point) : path.line(to: point)
            }
            (healthLevel.highlightNSColor ?? NSColor.labelColor).setStroke()
            path.lineWidth = 1.45
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            path.stroke()
            if let label {
                self.drawCompactLabel(
                    label + healthLevel.menuBarMarker,
                    in: rect,
                    color: healthLevel.highlightNSColor
                )
            }
            return true
        }
        image.isTemplate = healthLevel == .normal
        return image
    }

    private func drawCompactLabel(_ label: String, in rect: NSRect, color: NSColor?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (label as NSString).draw(
            in: NSRect(x: 0, y: 0, width: rect.width, height: 8),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 6.6, weight: .medium),
                .foregroundColor: color ?? NSColor.labelColor,
                .paragraphStyle: paragraph,
                .kern: 0.2
            ]
        )
    }
}

private struct MenuBarMonitorPopover: View {
    @EnvironmentObject private var store: AppStore
    let focusedMetric: MenuBarMetric

    private var enabledMetrics: [MenuBarMetric] {
        store.menuBarConfiguration.metrics
            .filter(\.isEnabled)
            .map(\.metric)
    }

    var body: some View {
        ZStack {
            CNVisualEffectBackground(material: .popover)
            LinearGradient(
                colors: [CNTheme.accent.opacity(0.10), Color.clear, CNTheme.cyan.opacity(0.045)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    CNNestMark(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CleanNest 实时监测")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(store.nativeMonitorDiagnostic)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Circle()
                        .fill(store.nativeMonitorIsActive ? CNTheme.success : CNTheme.warning)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel(store.nativeMonitorIsActive ? "正在采样" : "采样已停止")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if let sample = store.nativeMonitorSample {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(enabledMetrics, id: \.self) { metric in
                                metricRow(metric, sample: sample)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                    }
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取第一个本机样本…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Divider()

                HStack(spacing: 8) {
                    Button {
                        store.showMainWindow(selection: .status)
                    } label: {
                        Label("打开系统状态", systemImage: "waveform.path.ecg")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Button {
                        store.showMainWindow(selection: .settings)
                    } label: {
                        Label("菜单栏设置", systemImage: "slider.horizontal.3")
                    }
                }
                .controlSize(.small)
                .padding(14)
            }
        }
        .frame(width: 390, height: 500)
    }

    private func metricRow(_ metric: MenuBarMetric, sample: NativeMonitorSample) -> some View {
        let healthLevel = sample.healthLevel(for: metric)
        let tint = healthLevel.highlightColor ?? metric.tint

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                CNIconTile(symbol: metric.symbol, tint: tint, size: 32)
                HStack(spacing: 7) {
                    Text(metric.displayName)
                        .font(.subheadline.weight(.semibold))
                    if let badgeText = healthLevel.badgeText {
                        StatusPill(
                            text: badgeText,
                            symbol: healthLevel.badgeSymbol,
                            style: healthLevel.badgeStyle
                        )
                        .controlSize(.mini)
                    }
                    if !sample.isAvailable(metric) {
                        Text("暂不可用")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                MiniTrend(
                    values: store.nativeMonitorHistory.compactMap { $0.value(for: metric) },
                    range: metric.normalizedGraphRange,
                    tint: tint
                )
                .frame(width: 56, height: 24)
            }

            VStack(alignment: .leading, spacing: 3) {
                NativeMetricReadingView(
                    reading: sample.metricReading(
                        metric,
                        temperatureUnit: store.menuBarConfiguration.temperatureUnit
                    ),
                    font: .system(size: 13, weight: .semibold, design: .rounded),
                    spacing: 6
                )
                .foregroundStyle(healthLevel.highlightColor ?? Color.primary)
                Text(sample.sourceDescription(metric))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 43)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(
            healthLevel != .normal
                ? tint.opacity(0.12)
                : (focusedMetric == metric ? metric.tint.opacity(0.10) : Color.clear),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    healthLevel == .normal ? Color.clear : tint.opacity(0.34),
                    lineWidth: 0.7
                )
        )
        .accessibilityElement(children: .combine)
    }
}

struct MiniTrend: View {
    let values: [Double]
    let range: ClosedRange<Double>?
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let recent = Array(values.suffix(42))
            guard recent.count > 1 else {
                var line = Path()
                line.move(to: CGPoint(x: 1, y: size.height / 2))
                line.addLine(to: CGPoint(x: size.width - 1, y: size.height / 2))
                context.stroke(line, with: .color(.secondary.opacity(0.35)), lineWidth: 1)
                return
            }
            let lower = range?.lowerBound ?? recent.min() ?? 0
            let upperCandidate = range?.upperBound ?? recent.max() ?? 1
            let upper = upperCandidate > lower ? upperCandidate : lower + 1
            var path = Path()
            for (index, value) in recent.enumerated() {
                let x = CGFloat(index) / CGFloat(max(1, recent.count - 1)) * size.width
                let normalized = min(1, max(0, (value - lower) / (upper - lower)))
                let y = size.height - CGFloat(normalized) * (size.height - 2) - 1
                index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(
                path,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.65), tint]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                ),
                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}
