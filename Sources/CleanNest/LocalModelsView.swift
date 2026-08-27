import SwiftUI
import CleanNestCore

struct LocalModelsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var externalStopRequest: ExternalLocalModelStopRequest?

    private var phase: LocalModelRuntimePhase { store.localModelDiscoveryPhase }
    private var tint: Color { phase.tint }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: "本地模型",
                    subtitle: "看清模型、监听地址与自动拉起来源；外部服务可连同精确 launchd 守护一起安全停用。"
                ) {
                    HStack(spacing: 9) {
                        Toggle("菜单栏状态", isOn: Binding(
                            get: { store.localModelMenuBarEnabled },
                            set: { store.setLocalModelMenuBarEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Button {
                            Task { await store.refreshLocalModelRuntimes() }
                        } label: {
                            if store.localModelDiscoveryIsRunning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("重新发现", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(store.localModelDiscoveryIsRunning)
                    }
                }

                runtimeSignalDeck

                if !store.localModelRuntimeSnapshot.instances.isEmpty {
                    runtimeTopologyCard
                }

                if phase == .runningUnverified {
                    InlineBanner(
                        title: "只确认到运行迹象",
                        detail: "进程或端口存在，但模型 API 尚未返回可用短 ID。CleanNest 不会把它误报为健康。",
                        kind: .warning,
                        actionTitle: "重新检查",
                        action: { Task { await store.refreshLocalModelRuntimes() } }
                    )
                } else if phase == .failed {
                    InlineBanner(
                        title: "运行时检查失败",
                        detail: store.localModelRuntimeDiagnostic,
                        kind: .error,
                        actionTitle: "重试",
                        action: { Task { await store.refreshLocalModelRuntimes() } }
                    )
                }

                externalStopResultBanner

                if store.localModelRuntimeSnapshot.instances.isEmpty {
                    stoppedConfiguration
                } else {
                    runtimeList
                }

                runtimeTransitionCard
                modelDiagnosticsCard
                platformCoverage

                InlineBanner(
                    title: "发现过程保持只读",
                    detail: "只检查本机进程、监听端口、平台健康 API 与 launchd 配置元数据；不扫描局域网、不发送提示词、不保存内网地址，也不读取环境变量。",
                    kind: .info
                )
            }
            .frame(maxWidth: CNTheme.contentMaxWidth, alignment: .leading)
            .padding(CNTheme.pagePadding)
        }
        .task {
            if store.localModelRuntimeSnapshot.capturedAt == .distantPast {
                await store.refreshLocalModelRuntimes()
            }
        }
        .sheet(item: $externalStopRequest) { request in
            ExternalLocalModelStopConfirmation(request: request)
                .environmentObject(store)
        }
    }

    private var runtimeSignalDeck: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 22) {
                    signalGlyph
                    signalSummary
                    Spacer(minLength: 20)
                    primaryAction
                }
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 18) {
                        signalGlyph
                        signalSummary
                    }
                    primaryAction
                }
            }
            .padding(24)

            Divider().opacity(0.65)

            evidenceRail
                .padding(.horizontal, 24)
                .padding(.vertical, 17)
        }
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(.thinMaterial)
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.22), tint.opacity(0.055), Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.8)
        )
        .shadow(color: tint.opacity(0.12), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var signalGlyph: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.12), lineWidth: 1)
                .frame(width: 82, height: 82)
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)
            Circle()
                .fill(tint.opacity(0.16))
                .frame(width: 48, height: 48)
            Image(systemName: phase.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
            Circle()
                .fill(tint)
                .frame(width: 11, height: 11)
                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                .offset(x: 27, y: -25)
        }
        .accessibilityLabel(phase.accessibilityLabel)
    }

    private var signalSummary: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(store.localModelRuntimeStatusTitle)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                if let runtime = store.primaryLocalModelRuntime {
                    StatusPill(
                        text: runtime.platform.shortName,
                        symbol: "server.rack",
                        style: runtime.phase == .runningHealthy ? .success : .warning
                    )
                }
            }
            Text(store.primaryLocalModelRuntime?.primaryModelID ?? "没有确认到正在运行的模型")
                .font(.system(size: 27, weight: .semibold, design: .rounded))
                .tracking(-0.45)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(store.localModelRuntimeDiagnostic)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 660, alignment: .leading)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let runtime = store.primaryLocalModelRuntime, runtime.canStopDirectly {
            VStack(alignment: .trailing, spacing: 7) {
                Button(role: .destructive) {
                    Task { await store.stopOwnedLocalModelRuntime() }
                } label: {
                    Label("停止模型服务", systemImage: "stop.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.localAIServiceState.isBusy)
                Text("先发送正常终止；不会批量结束同名进程。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let runtime = store.primaryLocalModelRuntime,
                  runtime.supervisor?.canDisableAndStop == true {
            VStack(alignment: .trailing, spacing: 7) {
                Button(role: .destructive) {
                    externalStopRequest = ExternalLocalModelStopRequest(
                        runtime: runtime,
                        force: false,
                        disableSupervisor: true
                    )
                } label: {
                    Label("停用并关闭…", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.stoppingExternalLocalModelRuntimeID != nil)
                Text("已发现自动拉起来源；停用后可在本页重新启用。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 230, alignment: .trailing)
            }
        } else if let runtime = store.primaryLocalModelRuntime,
                  runtime.canRequestExternalStop {
            VStack(alignment: .trailing, spacing: 7) {
                Button(role: .destructive) {
                    externalStopRequest = ExternalLocalModelStopRequest(
                        runtime: runtime,
                        force: false
                    )
                } label: {
                    Label("关闭外部服务…", systemImage: "stop.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.stoppingExternalLocalModelRuntimeID != nil)
                Text("先显示风险并复核精确 PID，再发送正常退出。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        } else if let runtime = store.primaryLocalModelRuntime,
                  runtime.supervisor?.canEnable == true {
            VStack(alignment: .trailing, spacing: 7) {
                Button {
                    Task { await store.enableLocalModelSupervisor(runtime) }
                } label: {
                    Label("重新启用守护", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.stoppingExternalLocalModelRuntimeID != nil)
                Text("重新允许 launchd 启动这个模型服务。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if store.localModelRuntimeSnapshot.healthyInstances.isEmpty,
                  store.configuredLocalModelCanStart {
            VStack(alignment: .trailing, spacing: 7) {
                Button {
                    Task { await store.startConfiguredLocalModelRuntime() }
                } label: {
                    Label("启动已配置模型", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.localAIServiceState.isBusy)
                Text("启动后由 CleanNest 持有并可安全停止。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if store.localModelRuntimeSnapshot.healthyInstances.isEmpty {
            Button {
                store.selection = .settings
            } label: {
                Label("完善启动配置", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
        } else {
            VStack(alignment: .trailing, spacing: 7) {
                StatusPill(text: "身份不足 · 只读", symbol: "lock", style: .neutral)
                Text("缺少可防止 PID 复用的身份依据，暂不提供关闭。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220, alignment: .trailing)
            }
        }
    }

    @ViewBuilder
    private var externalStopResultBanner: some View {
        if let message = store.externalLocalModelStopMessage {
            let forceRuntime = store.externalLocalModelForceCandidateID.flatMap { id in
                store.localModelRuntimeSnapshot.instances.first { $0.id == id }
            }
            InlineBanner(
                title: store.externalLocalModelStopMessageIsWarning
                    ? "外部服务关闭需要处理"
                    : "外部服务状态已更新",
                detail: message,
                kind: store.externalLocalModelStopMessageIsWarning ? .warning : .success,
                actionTitle: forceRuntime == nil ? "关闭提示" : "进一步强制结束…",
                action: {
                    if let forceRuntime {
                        externalStopRequest = ExternalLocalModelStopRequest(
                            runtime: forceRuntime,
                            force: true
                        )
                    } else {
                        store.clearExternalLocalModelStopMessage()
                    }
                }
            )
        }
    }

    private var evidenceRail: some View {
        let evidence = Set(store.primaryLocalModelRuntime?.evidence ?? [])
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                evidenceNode(
                    title: "进程",
                    value: store.primaryLocalModelRuntime?.process.map { "PID \($0.pid)" } ?? "未发现",
                    symbol: "gearshape.2",
                    confirmed: evidence.contains(.process)
                )
                railConnector(confirmed: evidence.contains(.process) && evidence.contains(.supervisor))
                evidenceNode(
                    title: "守护",
                    value: store.primaryLocalModelRuntime?.supervisor?.label ?? "未发现",
                    symbol: "arrow.triangle.2.circlepath",
                    confirmed: evidence.contains(.supervisor)
                )
                railConnector(confirmed: evidence.contains(.supervisor) && evidence.contains(.listener))
                evidenceNode(
                    title: "监听",
                    value: store.primaryLocalModelRuntime?.primaryAddress ?? "未确认",
                    symbol: "network",
                    confirmed: evidence.contains(.listener)
                )
                railConnector(confirmed: evidence.contains(.listener) && evidence.contains(.platformAPI))
                evidenceNode(
                    title: "模型 API",
                    value: store.primaryLocalModelRuntime?.primaryModelID == nil ? "未确认" : "短 ID 已确认",
                    symbol: "checkmark.seal",
                    confirmed: evidence.contains(.platformAPI)
                        && store.primaryLocalModelRuntime?.primaryModelID != nil
                )
            }
            .frame(minWidth: 780)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 14)],
                alignment: .leading,
                spacing: 12
            ) {
                evidenceNode(
                    title: "进程",
                    value: store.primaryLocalModelRuntime?.process.map { "PID \($0.pid)" } ?? "未发现",
                    symbol: "gearshape.2",
                    confirmed: evidence.contains(.process),
                    allowsWrapping: true
                )
                evidenceNode(
                    title: "守护",
                    value: store.primaryLocalModelRuntime?.supervisor?.label ?? "未发现",
                    symbol: "arrow.triangle.2.circlepath",
                    confirmed: evidence.contains(.supervisor),
                    allowsWrapping: true
                )
                evidenceNode(
                    title: "监听",
                    value: store.primaryLocalModelRuntime?.primaryAddress ?? "未确认",
                    symbol: "network",
                    confirmed: evidence.contains(.listener),
                    allowsWrapping: true
                )
                evidenceNode(
                    title: "模型 API",
                    value: store.primaryLocalModelRuntime?.primaryModelID == nil ? "未确认" : "短 ID 已确认",
                    symbol: "checkmark.seal",
                    confirmed: evidence.contains(.platformAPI)
                        && store.primaryLocalModelRuntime?.primaryModelID != nil,
                    allowsWrapping: true
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func evidenceNode(
        title: String,
        value: String,
        symbol: String,
        confirmed: Bool,
        allowsWrapping: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: confirmed ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(confirmed ? CNTheme.success : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.medium))
                    .lineLimit(allowsWrapping ? 2 : 1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: allowsWrapping)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func railConnector(confirmed: Bool) -> some View {
        Capsule()
            .fill(confirmed ? CNTheme.success.opacity(0.48) : Color.secondary.opacity(0.16))
            .frame(width: 38, height: 2)
            .padding(.horizontal, 7)
            .accessibilityHidden(true)
    }

    private var runtimeList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ContentSectionHeader(
                "运行实例",
                detail: "模型短名来自平台 API；完整命令行与环境变量不会显示。",
                symbol: "server.rack",
                tint: CNTheme.cyan
            )
            ForEach(store.localModelRuntimeSnapshot.instances) { runtime in
                runtimeRow(runtime)
            }
        }
    }

    private func runtimeRow(_ runtime: LocalModelRuntimeInstance) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 13) {
                CNIconTile(symbol: "rectangle.stack.badge.play", tint: runtime.phase.tint, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(runtime.platform.displayName)
                            .font(.system(size: 16, weight: .semibold))
                        StatusPill(
                            text: runtime.phase.shortLabel,
                            symbol: runtime.phase.symbol,
                            style: runtime.phase.pillStyle
                        )
                        if let supervisor = runtime.supervisor {
                            StatusPill(
                                text: supervisor.isDisabled ? "守护已停用" : "launchd 守护",
                                symbol: supervisor.isDisabled
                                    ? "pause.circle"
                                    : "arrow.triangle.2.circlepath",
                                style: supervisor.isDisabled ? .neutral : .warning
                            )
                        }
                        StatusPill(
                            text: runtime.controlLevel.title,
                            symbol: controlLevelSymbol(runtime.controlLevel),
                            style: controlLevelStyle(runtime.controlLevel)
                        )
                    }
                    Text(runtime.primaryModelID ?? "模型短 ID 尚未确认")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .textSelection(.enabled)
                    Text(runtime.diagnostic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if runtime.canStopDirectly {
                    Button(role: .destructive) {
                        Task { await store.stopOwnedLocalModelRuntime() }
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                    }
                    .disabled(store.localAIServiceState.isBusy)
                } else if runtime.supervisor?.canDisableAndStop == true {
                    Button(role: .destructive) {
                        externalStopRequest = ExternalLocalModelStopRequest(
                            runtime: runtime,
                            force: false,
                            disableSupervisor: true
                        )
                    } label: {
                        Label("停用守护…", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(store.stoppingExternalLocalModelRuntimeID != nil)
                } else if runtime.supervisor?.canEnable == true {
                    Button {
                        Task { await store.enableLocalModelSupervisor(runtime) }
                    } label: {
                        Label("重新启用", systemImage: "play.circle")
                    }
                    .disabled(store.stoppingExternalLocalModelRuntimeID != nil)
                } else if runtime.canRequestExternalStop {
                    Button(role: .destructive) {
                        externalStopRequest = ExternalLocalModelStopRequest(
                            runtime: runtime,
                            force: false
                        )
                    } label: {
                        Label("关闭…", systemImage: "stop.circle")
                    }
                    .disabled(store.stoppingExternalLocalModelRuntimeID != nil)
                }
            }

            Divider()

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 210), spacing: 12)],
                alignment: .leading,
                spacing: 12
            ) {
                fact(
                    "进程",
                    value: runtime.process.map { "PID \($0.pid) · \($0.commandName)" }
                        ?? (runtime.phase == .stopped ? "未运行" : "API 可达，进程未关联"),
                    symbol: "gearshape.2"
                )
                fact(
                    "实际内存",
                    value: memoryDescription(runtime),
                    symbol: "memorychip"
                )
                fact(
                    "监听地址",
                    value: runtime.listeners.map(\.displayAddress).joined(separator: " · ").nilIfEmpty ?? "尚未确认",
                    symbol: "network"
                )
                fact(
                    "暴露级别",
                    value: runtime.exposure.displayName,
                    symbol: runtime.exposure == .localNetwork ? "exclamationmark.shield" : "lock.shield"
                )
                fact(
                    "启动时间",
                    value: runtime.process?.startedAt?.formatted(date: .abbreviated, time: .standard) ?? "未读取",
                    symbol: "clock"
                )
                fact(
                    "证据",
                    value: runtime.evidence.map(\.displayName).joined(separator: " + "),
                    symbol: "checkmark.seal"
                )
                fact(
                    "控制边界",
                    value: runtime.controlLevel.capability,
                    symbol: controlLevelSymbol(runtime.controlLevel)
                )
                fact(
                    "客户端实连",
                    value: runtime.clients.isEmpty
                        ? "当前未观察到"
                        : runtime.clients.map { "\($0.commandName) · PID \($0.processID)" }.joined(separator: " · "),
                    symbol: "point.3.connected.trianglepath.dotted"
                )
                if let supervisor = runtime.supervisor {
                    fact(
                        "自动拉起来源",
                        value: "\(supervisor.label) · \(CNL10n.string(supervisor.restartDescription))",
                        symbol: "arrow.triangle.2.circlepath"
                    )
                    fact(
                        "守护配置",
                        value: supervisor.displaySourcePath ?? "路径未确认",
                        symbol: "doc.badge.gearshape"
                    )
                }
            }

            if let supervisor = runtime.supervisor {
                InlineBanner(
                    title: supervisor.isDisabled ? "守护服务已停用" : "检测到自动重启来源",
                    detail: supervisor.isDisabled
                        ? CNL10n.format(
                            "%@ 当前被 launchd 禁用；配置文件仍保留，可从这里重新启用。",
                            supervisor.label
                        )
                        : CNL10n.format(
                            "%@ · %@。只结束 PID 可能马上出现新进程。",
                            supervisor.label,
                            CNL10n.string(supervisor.restartDescription)
                        ),
                    kind: supervisor.isDisabled ? .info : .warning
                )
            }

            if runtime.modelIDs.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("服务列出的模型短 ID")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(runtime.modelIDs.joined(separator: "  ·  "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(runtime.issues) { issue in
                InlineBanner(
                    title: issue.title,
                    detail: issue.detail,
                    kind: issue.isWarning ? .warning : .info
                )
            }

            if runtime.exposure == .localNetwork {
                InlineBanner(
                    title: "该服务可能被局域网访问",
                    detail: runtime.localNetworkAddresses.isEmpty
                        ? "监听地址不是回环地址；CleanNest 不会擅自修改防火墙。"
                        : "本机地址：\(runtime.localNetworkAddresses.joined(separator: "、"))。CleanNest 不会保存这些地址或修改防火墙。",
                    kind: .warning
                )
            }

            if runtime.platform == .omlx {
                Text("DFlash2：当前 oMLX 健康接口没有返回可验证的启用状态，因此这里只展示模型短 ID，不猜测加速配置。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cnCard(tint: runtime.phase.tint)
        .accessibilityElement(children: .contain)
    }

    private var runtimeTopologyCard: some View {
        SurfaceCard(
            title: "运行拓扑",
            symbol: "point.3.connected.trianglepath.dotted",
            prominence: .prominent,
            tint: CNTheme.cyan
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Text("每条链都来自当前进程、TCP、平台 API 与 launchd 证据；没有连接就显示“未观察到”，不会猜测谁在使用模型。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(store.localModelRuntimeSnapshot.topology) { platform in
                    VStack(alignment: .leading, spacing: 9) {
                        Label(platform.platform.displayName, systemImage: "square.stack.3d.up.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CNTheme.cyan)

                        ForEach(platform.services) { service in
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 7) {
                                    topologyNode(
                                        "服务",
                                        service.address ?? (service.phase == .stopped ? "未运行" : "地址未确认"),
                                        symbol: "server.rack"
                                    )
                                    topologyArrow
                                    topologyNode(
                                        "模型",
                                        service.modelIDs.first ?? "短 ID 未确认",
                                        symbol: "brain.head.profile"
                                    )
                                    topologyArrow
                                    topologyNode(
                                        "客户端",
                                        service.clients.isEmpty ? "未观察到" : "\(service.clients.count) 个实连",
                                        symbol: "link"
                                    )
                                    topologyArrow
                                    topologyNode(
                                        "守护",
                                        service.supervisorLabel ?? "未发现",
                                        symbol: "arrow.triangle.2.circlepath"
                                    )
                                }
                                .frame(minWidth: 720)

                                VStack(alignment: .leading, spacing: 7) {
                                    topologyCompactRow("服务", service.address ?? "地址未确认", "server.rack")
                                    topologyCompactRow("模型", service.modelIDs.first ?? "短 ID 未确认", "brain.head.profile")
                                    topologyCompactRow(
                                        "客户端",
                                        service.clients.isEmpty ? "未观察到" : "\(service.clients.count) 个实连",
                                        "link"
                                    )
                                    topologyCompactRow("守护", service.supervisorLabel ?? "未发现", "arrow.triangle.2.circlepath")
                                }
                            }
                            .padding(11)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.07), lineWidth: 0.7)
                            }
                        }
                    }
                }
            }
        }
    }

    private func topologyNode(_ title: String, _ value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var topologyArrow: some View {
        Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func topologyCompactRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .textSelection(.enabled)
        }
    }

    private var runtimeTransitionCard: some View {
        SurfaceCard(title: "运行诊断", symbol: "waveform.path.ecg.rectangle", tint: CNTheme.violet) {
            VStack(alignment: .leading, spacing: 10) {
                if store.localModelRuntimeTransitions.isEmpty {
                    Label("本次运行还没有服务启停、PID 替换、模型切换或唤醒复核事件。", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(store.localModelRuntimeTransitions.prefix(8))) { transition in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: transitionSymbol(transition.kind))
                                .foregroundStyle(transition.kind == .startFailed ? CNTheme.warning : CNTheme.violet)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 7) {
                                    Text(transition.title)
                                        .font(.caption.weight(.semibold))
                                    Text(transition.date, style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(transition.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                if let checkedAt = store.localModelLastWakeCheckAt {
                    Label("最近一次唤醒复核：\(checkedAt.formatted(date: .abbreviated, time: .standard))", systemImage: "sun.max.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func controlLevelSymbol(_ level: LocalModelControlLevel) -> String {
        switch level {
        case .cleanNestOwned: return "checkmark.shield.fill"
        case .currentUserProcess: return "person.crop.circle"
        case .currentUserLaunchAgent: return "arrow.triangle.2.circlepath"
        case .protectedReadOnly: return "lock.shield"
        }
    }

    private func controlLevelStyle(_ level: LocalModelControlLevel) -> StatusPill.Style {
        switch level {
        case .cleanNestOwned: return .success
        case .currentUserProcess: return .warning
        case .currentUserLaunchAgent: return .warning
        case .protectedReadOnly: return .neutral
        }
    }

    private func transitionSymbol(_ kind: LocalModelRuntimeTransitionKind) -> String {
        switch kind {
        case .appeared: return "play.circle.fill"
        case .disappeared: return "stop.circle"
        case .processReplaced: return "arrow.triangle.2.circlepath"
        case .modelChanged: return "arrow.left.arrow.right.circle"
        case .wakeRecheck: return "sun.max.fill"
        case .startFailed: return "exclamationmark.triangle.fill"
        }
    }

    private var stoppedConfiguration: some View {
        SurfaceCard(
            title: "启动配置",
            symbol: "play.square.stack",
            prominence: .prominent,
            tint: CNTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 15) {
                Text("当前没有确认到健康模型服务。你可以启动已经在设置中选定的模型；CleanNest 只会保存结构化路径和端口，不执行拼接的终端命令。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    fact("模型", value: store.localAIModelDisplayName, symbol: "brain.head.profile")
                    fact("服务地址", value: store.localAIEndpoint, symbol: "network")
                    fact(
                        "服务程序",
                        value: URL(fileURLWithPath: store.localAIExecutablePath).lastPathComponent.nilIfEmpty ?? "未选择",
                        symbol: "terminal"
                    )
                }

                InlineBanner(
                    title: store.localModelStartReadiness.canStart ? "启动前检查通过" : "启动前仍有条件未满足",
                    detail: store.localModelStartReadiness.detail,
                    kind: store.localModelStartReadiness.canStart ? .info : .warning
                )

                HStack(spacing: 9) {
                    Button {
                        Task { await store.startConfiguredLocalModelRuntime() }
                    } label: {
                        Label("启动已配置模型", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.configuredLocalModelCanStart)

                    Button("更换模型或平台") { store.selection = .settings }
                    Spacer()
                }
            }
        }
    }

    private var modelDiagnosticsCard: some View {
        SurfaceCard(
            title: "最小推理测速",
            symbol: "gauge.with.dots.needle.67percent",
            tint: CNTheme.violet
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("只对当前配置的模型短 ID 发出一个“OK”最小请求。")
                            .font(.subheadline.weight(.medium))
                        Text("不发送扫描结果、文件名或文件内容；结果只代表当前机器负载。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 10)
                    if store.localAIBenchmarkPhase.isRunning {
                        ProgressView().controlSize(.small)
                    }
                    Button(store.localAIBenchmarkResult == nil ? "运行最小测速" : "重新测速") {
                        Task { await store.runLocalAIBenchmark() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.localAIIsReady || store.localAIBenchmarkPhase.isRunning)
                    .accessibilityHint("发送一个仅包含 OK 的本机推理请求")
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        benchmarkFact(
                            "健康检查",
                            value: store.localAIProbeLatencyMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—",
                            detail: store.localAIIsReady ? "回环服务可达" : "等待连接"
                        )
                        benchmarkFact(
                            "首字延迟",
                            value: store.localAIBenchmarkResult.map { "\(Int($0.firstTokenMilliseconds.rounded())) ms" } ?? "—",
                            detail: "真实流式首个输出"
                        )
                        benchmarkFact(
                            "完整响应",
                            value: benchmarkTotalValue,
                            detail: benchmarkThroughputDetail
                        )
                    }
                    VStack(spacing: 10) {
                        benchmarkFact(
                            "健康检查",
                            value: store.localAIProbeLatencyMilliseconds.map { "\(Int($0.rounded())) ms" } ?? "—",
                            detail: store.localAIIsReady ? "回环服务可达" : "等待连接"
                        )
                        benchmarkFact(
                            "首字延迟",
                            value: store.localAIBenchmarkResult.map { "\(Int($0.firstTokenMilliseconds.rounded())) ms" } ?? "—",
                            detail: "真实流式首个输出"
                        )
                        benchmarkFact(
                            "完整响应",
                            value: benchmarkTotalValue,
                            detail: benchmarkThroughputDetail
                        )
                    }
                }

                if let model = configuredLocalAIModel {
                    Label(modelMemoryGuidance(model), systemImage: "memorychip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch store.localAIBenchmarkPhase {
                case .failed(let detail):
                    InlineBanner(
                        title: "最小推理测速未完成",
                        detail: detail,
                        kind: .warning
                    )
                case .completed:
                    if let result = store.localAIBenchmarkResult {
                        Text("本次实测对象：\(result.modelID)。这不是长文本吞吐或峰值内存承诺。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                case .idle, .running:
                    if !store.localAIIsReady {
                        HStack(spacing: 10) {
                            Label("先确认设置中的回环服务与模型短 ID，才能运行测速。", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                            Button("检测连接") {
                                Task { await store.probeLocalAI() }
                            }
                            .disabled(!store.localAIEnabled || store.localAIServiceState.isBusy)
                        }
                    }
                }
            }
        }
    }

    private var platformCoverage: some View {
        SurfaceCard(title: "平台覆盖", symbol: "square.stack.3d.up", tint: CNTheme.violet) {
            VStack(alignment: .leading, spacing: 12) {
                Text("五类本地运行时共享同一套证据门；除进程与 API 外，还会识别 launchd 守护、自动重启和登录启动状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 185), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(LocalModelPlatform.allCases.filter { $0 != .openAICompatible }) { platform in
                        let detected = store.localModelRuntimeSnapshot.instances.contains {
                            $0.platform == platform
                        }
                        HStack(spacing: 9) {
                            Circle()
                                .fill(detected ? CNTheme.success : Color.secondary.opacity(0.25))
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(platform.displayName)
                                    .font(.caption.weight(.semibold))
                                Text(detected
                                    ? "已发现"
                                    : (platform == .omlx || platform == .mlxLM ? "可发现 · 可控启动" : "可发现 · 确认后可关闭"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(11)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }

    private func benchmarkFact(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedMetric()
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var benchmarkTotalValue: String {
        store.localAIBenchmarkResult.map { "\(Int($0.totalMilliseconds.rounded())) ms" } ?? "—"
    }

    private var benchmarkThroughputDetail: String {
        guard let result = store.localAIBenchmarkResult else { return "等待用户主动测速" }
        if let rate = result.tokensPerSecond {
            return String(format: "%.1f token/s · %d token", rate, result.outputTokens ?? 0)
        }
        return "\(result.outputCharacters) 个输出字符"
    }

    private var configuredLocalAIModel: LocalModelDescriptor? {
        store.localAIModelDescriptor(path: store.localAIModelPath)
    }

    private func modelMemoryGuidance(_ model: LocalModelDescriptor) -> String {
        let physical = store.systemSnapshot?.memoryTotalBytes
            ?? Int64(clamping: ProcessInfo.processInfo.physicalMemory)
        guard model.weightBytes > 0, physical > 0 else {
            return "未取得完整权重或物理内存数据；是否可运行仍以实际载入结果为准。"
        }
        let ratio = Double(model.weightBytes) / Double(physical)
        let verdict: String
        if ratio <= 0.55 {
            verdict = "权重仍为系统、KV 缓存和其他 App 留有较明显空间"
        } else if ratio <= 0.75 {
            verdict = "可用余量有限，长上下文或同时运行多个重型 App 时应观察内存压力"
        } else {
            verdict = "权重已接近本机物理内存，实际载入和长上下文可能出现明显压力"
        }
        return "模型权重约 \(CleanNestFormatting.bytes(model.weightBytes))，本机物理内存 \(CleanNestFormatting.bytes(physical))：\(verdict)。这不是峰值内存承诺。"
    }

    private func fact(_ title: String, value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CNTheme.cyan)
                .frame(width: 19, height: 19)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func memoryDescription(_ runtime: LocalModelRuntimeInstance) -> String {
        var parts: [String] = []
        if let resident = runtime.process?.residentMemoryBytes {
            parts.append("进程 RSS \(CleanNestFormatting.bytes(resident))")
        }
        if let engine = runtime.engineMemoryBytes {
            parts.append("引擎报告 \(CleanNestFormatting.bytes(engine))")
        }
        return parts.nilIfEmpty ?? "平台未提供"
    }
}

private extension LocalModelRuntimePhase {
    var tint: Color {
        switch self {
        case .runningHealthy: return CNTheme.success
        case .runningUnverified: return CNTheme.warning
        case .failed: return CNTheme.danger
        case .discovering: return CNTheme.cyan
        case .unknown, .stopped: return .secondary
        }
    }

    var symbol: String {
        switch self {
        case .runningHealthy: return "wave.3.right.circle.fill"
        case .runningUnverified: return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .failed: return "xmark.octagon.fill"
        case .discovering: return "dot.radiowaves.left.and.right"
        case .unknown: return "questionmark.circle"
        case .stopped: return "stop.circle"
        }
    }

    var shortLabel: String {
        switch self {
        case .runningHealthy: return "健康"
        case .runningUnverified: return "待确认"
        case .failed: return "失败"
        case .discovering: return "发现中"
        case .unknown: return "未知"
        case .stopped: return "未运行"
        }
    }

    var accessibilityLabel: String { "本地模型状态：\(shortLabel)" }

    var pillStyle: StatusPill.Style {
        switch self {
        case .runningHealthy: return .success
        case .runningUnverified, .discovering: return .warning
        case .failed: return .danger
        case .unknown, .stopped: return .neutral
        }
    }
}

private extension Array where Element == String {
    var nilIfEmpty: String? {
        isEmpty ? nil : joined(separator: " · ")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
