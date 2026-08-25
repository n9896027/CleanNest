import SwiftUI
import CleanNestCore

struct ExternalLocalModelStopRequest: Identifiable {
    let runtime: LocalModelRuntimeInstance
    let force: Bool
    let disableSupervisor: Bool

    init(
        runtime: LocalModelRuntimeInstance,
        force: Bool,
        disableSupervisor: Bool = false
    ) {
        self.runtime = runtime
        self.force = force
        self.disableSupervisor = disableSupervisor
    }

    var id: String {
        let action = disableSupervisor ? "supervisor" : (force ? "force" : "normal")
        return "\(runtime.id):\(action)"
    }
}

struct ExternalLocalModelStopConfirmation: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let request: ExternalLocalModelStopRequest
    @State private var destructiveRiskAcknowledged = false

    private var runtime: LocalModelRuntimeInstance { request.runtime }
    private var process: LocalModelProcessSnapshot? { runtime.process }
    private var isWorking: Bool {
        store.stoppingExternalLocalModelRuntimeID == runtime.id
    }

    var body: some View {
        ZStack {
            CNVisualEffectBackground(material: .popover)
            LinearGradient(
                colors: [
                    CNTheme.danger.opacity(request.force ? 0.16 : 0.08),
                    Color.clear,
                    CNTheme.cyan.opacity(0.035)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(22)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        identityPanel
                        riskPanel
                        safetyBoundary

                        if request.force || request.disableSupervisor {
                            Toggle(isOn: $destructiveRiskAcknowledged) {
                                Text(request.disableSupervisor
                                    ? "我确认要停用这个守护服务，直到我在 CleanNest 中重新启用。"
                                    : "我确认该进程可能来不及保存状态，仍要强制结束。")
                                    .font(.caption.weight(.semibold))
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityIdentifier(request.disableSupervisor
                                ? "externalModel.supervisorAcknowledgement"
                                : "externalModel.forceAcknowledgement")
                        }
                    }
                    .padding(22)
                }

                Divider()

                HStack(spacing: 10) {
                    Button("取消") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .disabled(isWorking)

                    Spacer()

                    Button(role: .destructive) {
                        Task {
                            if request.disableSupervisor {
                                await store.disableExternalLocalModelSupervisor(runtime)
                            } else {
                                await store.stopExternalLocalModelRuntime(
                                    runtime,
                                    force: request.force
                                )
                            }
                            dismiss()
                        }
                    } label: {
                        if isWorking {
                            HStack(spacing: 7) {
                                ProgressView().controlSize(.small)
                                Text(CNL10n.string(progressTitle))
                            }
                        } else {
                            Label {
                                Text(verbatim: stopActionTitle)
                            } icon: {
                                Image(systemName: request.disableSupervisor
                                    ? "arrow.triangle.2.circlepath.circle.fill"
                                    : (request.force ? "xmark.octagon.fill" : "stop.circle.fill"))
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                            isWorking
                            || process == nil
                            || ((request.force || request.disableSupervisor) && !destructiveRiskAcknowledged)
                    )
                    .accessibilityIdentifier(
                        request.disableSupervisor
                            ? "externalModel.confirmSupervisorStop"
                            : (request.force
                                ? "externalModel.confirmForceStop"
                                : "externalModel.confirmNormalStop")
                    )
                }
                .padding(18)
            }
        }
        .frame(width: 590, height: request.force || request.disableSupervisor ? 650 : 560)
        .interactiveDismissDisabled(isWorking)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            CNIconTile(
                symbol: request.disableSupervisor
                    ? "arrow.triangle.2.circlepath.circle.fill"
                    : (request.force ? "xmark.octagon.fill" : "exclamationmark.shield.fill"),
                tint: request.force ? CNTheme.danger : CNTheme.warning,
                size: 44
            )
            VStack(alignment: .leading, spacing: 5) {
                Text(CNL10n.string(headerTitle))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Text(CNL10n.string(headerDetail))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            StatusPill(
                text: request.disableSupervisor ? "阻止重启" : (request.force ? "高风险" : "需确认"),
                symbol: request.disableSupervisor
                    ? "arrow.counterclockwise.circle"
                    : (request.force ? "exclamationmark.octagon" : "shield.lefthalf.filled"),
                style: request.force ? .danger : .warning
            )
        }
    }

    private var stopActionTitle: String {
        if request.disableSupervisor {
            return CNL10n.format("停用 %@", runtime.supervisor?.label ?? "launchd")
        }
        let pid = String(process?.pid ?? 0)
        return request.force
            ? CNL10n.format("强制结束 PID %@", pid)
            : CNL10n.format("正常关闭 PID %@", pid)
    }

    private var progressTitle: String {
        if request.disableSupervisor { return "正在停用守护并关闭…" }
        return request.force ? "正在强制结束…" : "正在正常关闭…"
    }

    private var headerTitle: String {
        if request.disableSupervisor { return "停用守护并关闭？" }
        return request.force ? "进一步强制结束？" : "关闭外部模型服务？"
    }

    private var headerDetail: String {
        if request.disableSupervisor {
            return "launchd 正在自动拉起这个服务。停用精确守护标签后再关闭，才不会瞬间重启。"
        }
        return request.force
            ? "正常退出没有完成。强制结束是最后手段，需要再次确认。"
            : "这是其他 App 或命令启动的服务。先确认影响，再关闭这个精确进程。"
    }

    private var identityPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("即将操作的真实对象", systemImage: "scope")
                .font(.subheadline.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                identityFact("平台", runtime.platform.displayName, "server.rack")
                identityFact("模型", runtime.primaryModelID ?? "模型短 ID 未确认", "brain.head.profile")
                identityFact(
                    "进程",
                    process.map { "PID \($0.pid) · \($0.commandName)" } ?? "未关联",
                    "gearshape.2"
                )
                identityFact("监听地址", runtime.primaryAddress ?? "未确认", "network")
                identityFact(
                    "启动时间",
                    process?.startedAt?.formatted(date: .abbreviated, time: .standard) ?? "未读取",
                    "clock"
                )
                identityFact(
                    "可执行文件",
                    process?.executablePath ?? process?.commandName ?? "未读取",
                    "terminal"
                )
                if let supervisor = runtime.supervisor {
                    identityFact("守护标签", supervisor.label, "tag")
                    identityFact(
                        "守护配置",
                        supervisor.displaySourcePath ?? "未确认",
                        "doc.badge.gearshape"
                    )
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
        )
    }

    private var riskPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("风险分析", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))

            riskRow(
                "正在生成的回答会被中断，连接这个服务的客户端可能收到错误。",
                symbol: "bolt.horizontal.circle"
            )
            if runtime.exposure == .localNetwork {
                riskRow(
                    "局域网设备也可能正在使用这个地址；它们的连接会同时断开。",
                    symbol: "network.badge.shield.half.filled"
                )
            }
            if runtime.platform == .lmStudio {
                riskRow(
                    "该 PID 可能属于 LM Studio 主程序；关闭服务也可能退出它的窗口。",
                    symbol: "macwindow"
                )
            }
            if let supervisor = runtime.supervisor {
                riskRow(
                    request.disableSupervisor
                        ? CNL10n.format(
                            "%@ 将被标记为停用，重新登录后也不会自动启动，直到你主动重新启用。",
                            supervisor.label
                        )
                        : CNL10n.format(
                            "%@ 设置了 %@；只关 PID 后很可能立刻以新 PID 返回。",
                            supervisor.label,
                            CNL10n.string(supervisor.restartDescription)
                        ),
                    symbol: "arrow.triangle.2.circlepath"
                )
            }
            riskRow(
                "如果服务由登录项、launchd 或平台守护程序管理，它可能以新 PID 自动重启。",
                symbol: "arrow.clockwise.circle"
            )
            if request.force {
                riskRow(
                    "强制结束不会给进程保存缓冲区或释放任务的时间。",
                    symbol: "xmark.octagon.fill",
                    tint: CNTheme.danger
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var safetyBoundary: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(CNTheme.success)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 22)
            Text(CNL10n.string(
                request.disableSupervisor
                    ? "CleanNest 会复核 PID、守护标签、作用域与配置文件身份，只对这个用户 LaunchAgent 执行 disable 与 bootout；不会编辑或删除 plist，也不会影响其他守护服务。"
                    : (request.force
                        ? "CleanNest 会再次核对 PID、启动时间、用户与可执行文件，只向复核通过的进程发送 SIGKILL；不会删除模型、配置或日志。"
                        : "CleanNest 会再次核对 PID、启动时间、用户与可执行文件，只发送正常退出 SIGTERM；不会按名称批量结束，也不会删除模型或配置。")
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(CNTheme.success.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(CNTheme.success.opacity(0.18), lineWidth: 0.7)
        )
        .accessibilityElement(children: .combine)
    }

    private func identityFact(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(CNTheme.cyan)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(CNL10n.string(title))
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

    private func riskRow(_ text: String, symbol: String, tint: Color = CNTheme.warning) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(CNL10n.string(text))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
