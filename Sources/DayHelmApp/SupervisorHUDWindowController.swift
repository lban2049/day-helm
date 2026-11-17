import AppKit
import Combine
import DayHelmCapture
import DayHelmCore
import SwiftUI

private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SupervisorHUDWindowController {
    private let panelWidth: CGFloat = 350
    private var panel: NonActivatingPanel?
    private var cancellable: AnyCancellable?
    private weak var coordinator: HybridActivityCoordinator?

    init(coordinator: HybridActivityCoordinator) {
        self.coordinator = coordinator
        self.cancellable = coordinator.$activeAlert
            .receive(on: DispatchQueue.main)
            .sink { [weak self] alert in
                if let alert {
                    self?.show(alert: alert)
                } else {
                    self?.hide()
                }
            }
    }

    func show(alert: SupervisorAlert) {
        guard let coordinator else { return }

        let contentView = SupervisorHUDToastView(
            alert: alert,
            onAction: { [weak coordinator] action in
                coordinator?.handleAlertAction(action)
            },
            onClose: { [weak coordinator] in
                coordinator?.handleAlertAction(.dismiss(label: "关闭"))
            }
        )

        let hosting = NSHostingView(rootView: contentView)
        hosting.setFrameSize(NSSize(width: panelWidth, height: 10))
        let fittingSize = hosting.fittingSize
        let height = max(96, fittingSize.height)
        hosting.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)

        let targetPanel: NonActivatingPanel
        if let existing = panel {
            targetPanel = existing
        } else {
            let created = NonActivatingPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: height),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            created.level = .floating
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = true
            created.hidesOnDeactivate = false
            created.becomesKeyOnlyIfNeeded = true
            self.panel = created
            targetPanel = created
        }

        targetPanel.contentView = hosting
        positionTopRight(panel: targetPanel, size: NSSize(width: panelWidth, height: height))
        targetPanel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func positionTopRight(panel: NSPanel, size: NSSize) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }
        let originX = visibleFrame.maxX - size.width - 16
        let originY = visibleFrame.maxY - size.height - 12
        panel.setFrame(NSRect(origin: NSPoint(x: originX, y: originY), size: size), display: true)
    }
}

struct SupervisorHUDToastView: View {
    let alert: SupervisorAlert
    let onAction: (SupervisorAction) -> Void
    let onClose: () -> Void

    private var accentColor: Color {
        switch alert.kind {
        case .quotaCapReached:
            return DayHelmColors.warningAmber
        case .quotaTargetMet:
            return DayHelmColors.successEmerald
        case .taskDrift, .highFrequencySwitch, .unassignedActivePrompt:
            return DayHelmColors.primaryBlue
        }
    }

    private var badgeText: String {
        switch alert.kind {
        case .quotaCapReached:
            return "配额到点"
        case .quotaTargetMet:
            return "保底达标"
        case .taskDrift:
            return "项目偏离"
        case .highFrequencySwitch:
            return "高频切换"
        case .unassignedActivePrompt:
            return "未指定专注"
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(badgeText)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(accentColor.opacity(0.14), in: Capsule())

                            Spacer()

                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Text(alert.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text(alert.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !alert.actions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(alert.actions.enumerated()), id: \.offset) { index, action in
                            Button(action: { onAction(action) }) {
                                Text(actionLabel(action))
                                    .font(.system(size: 11, weight: index == 0 ? .semibold : .medium))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        index == 0 ? accentColor : Color.primary.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .foregroundStyle(index == 0 ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .frame(width: 350)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 14, x: 0, y: 6)
    }

    private func actionLabel(_ action: SupervisorAction) -> String {
        switch action {
        case .switchTask(_, let label),
             .snooze(_, let label),
             .pauseFocus(let label),
             .dismiss(let label):
            return label
        }
    }
}
