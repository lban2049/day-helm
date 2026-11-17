import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator

    var body: some View {
        Text(pillText)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .monospacedDigit()
    }

    private var pillText: String {
        guard case .focusing(let taskId, _) = coordinator.sessionState,
              let progress = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId }) else {
            return "○ DayHelm · 待命"
        }

        let focused = Int(progress.focusedMinutes.rounded())
        let shortName = compactTaskName(progress.budget.displayName)

        if case .capReached = progress.status, let cap = progress.budget.capMinutes {
            return "▲ \(shortName) · \(focused)/\(cap)m"
        }
        if let target = progress.budget.targetMinutes {
            return "● \(shortName) · \(focused)/\(target)m"
        }
        if let cap = progress.budget.capMinutes {
            return "● \(shortName) · \(focused)/\(cap)m"
        }
        return "● \(shortName) · \(focused)m"
    }

    private func compactTaskName(_ name: String) -> String {
        if name == "电商日常运营" { return "日常运营" }
        return name
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    @State private var noteText: String = ""
    @State private var editingBudgetTaskId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            headerSection
            activeFocusBox
            budgetListSection
            DaySpectrumRibbonView(
                segments: coordinator.spectrumSegments,
                budgets: coordinator.taskProgressList.map(\.budget)
            )
            telemetryGrid
            Divider()
            footerSection
        }
        .padding(14)
        .frame(width: 330)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 1. Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "helm")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DayHelmColors.primaryBlue)
                .frame(width: 24, height: 24)
                .background(DayHelmColors.primaryBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("DayHelm")
                        .font(.system(size: 13.5, weight: .bold))
                    if coordinator.isSyntheticDemo {
                        Text("DEMO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(DayHelmColors.warningAmber)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(DayHelmColors.warningAmber.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text("今日时间预算与实时监督")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if coordinator.axTrusted {
                HStack(spacing: 4) {
                    Circle()
                        .fill(coordinator.almaConnected ? DayHelmColors.successEmerald : DayHelmColors.primaryBlue)
                        .frame(width: 6, height: 6)
                    Text(coordinator.almaConnected ? "Alma + AX 采集中" : "AX 本机采集中")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.05), in: Capsule())
            } else {
                Button(action: { coordinator.openAccessibilitySettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                        Text("AX 权限待开启")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DayHelmColors.warningAmber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(DayHelmColors.warningAmber.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 2. Active Focus Control Box

    private var activeFocusBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeFocusTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isFocusing ? .primary : .secondary)
                    Text(liveContextLine)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text(formattedTimer(coordinator.elapsedFocusSeconds))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(timerColor)
            }

            // Quick Task Switcher Pills
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 5)], alignment: .leading, spacing: 5) {
                ForEach(coordinator.taskProgressList) { progress in
                    let isSelected = activeTaskId == progress.budget.taskId
                    Button {
                        let submitted = noteText
                        noteText = ""
                        coordinator.selectTask(progress.budget.taskId, note: submitted.isEmpty ? nil : submitted)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(hex: progress.budget.colorHex))
                                .frame(width: 6, height: 6)
                            Text(shortButtonName(progress.budget.displayName))
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4.5)
                        .background(
                            isSelected
                                ? Color(hex: progress.budget.colorHex).opacity(0.18)
                                : Color.primary.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color(hex: progress.budget.colorHex).opacity(0.75) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    let submitted = noteText
                    noteText = ""
                    coordinator.pauseFocus(note: submitted.isEmpty ? nil : submitted)
                } label: {
                    HStack(spacing: 3) {
                        Text("⏸ 杂事/休息")
                            .font(.system(size: 10.5, weight: !isFocusing ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4.5)
                    .background(
                        !isFocusing ? Color.secondary.opacity(0.20) : Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            // Optional 1-line note field
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField(
                    coordinator.lastTaskNote ?? "刚才停在哪 / 一句话备注",
                    text: $noteText
                )
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .onSubmit {
                    guard !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    if let currentId = activeTaskId {
                        coordinator.selectTask(currentId, note: noteText)
                        noteText = ""
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: - 3. Daily Quota Budget Bars

    private var budgetListSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("今日事项配额")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            ForEach(coordinator.taskProgressList) { progress in
                BudgetProgressRow(
                    progress: progress,
                    isEditing: editingBudgetTaskId == progress.budget.taskId,
                    onToggleEdit: {
                        editingBudgetTaskId = (editingBudgetTaskId == progress.budget.taskId) ? nil : progress.budget.taskId
                    },
                    onSaveBudget: { target, cap in
                        coordinator.updateBudget(taskId: progress.budget.taskId, targetMinutes: target, capMinutes: cap)
                        editingBudgetTaskId = nil
                    }
                )
            }
        }
    }

    // MARK: - 5. Bottom 3-Cell Telemetry Grid

    private var telemetryGrid: some View {
        HStack(spacing: 6) {
            telemetryCell(
                title: "今日最长连续块",
                value: String(format: "%.0fm", coordinator.metrics.longestBlockMinutes)
            )
            telemetryCell(
                title: "近期切换热度",
                value: String(format: "%.0f/h", coordinator.metrics.recentSwitchesPerHour)
            )
            telemetryCell(
                title: "≥12m 有效块",
                value: "\(coordinator.metrics.solidBlocksCount) 个"
            )
        }
    }

    private func telemetryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - 6. Footer

    private var footerSection: some View {
        HStack {
            Button("模拟触发提醒测试") {
                coordinator.triggerDemoAlert()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(DayHelmColors.primaryBlue)

            Spacer()

            Button("配置目录") {
                coordinator.openConfigDirectory()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)

            Text("·")
                .font(.system(size: 10.5))
                .foregroundStyle(.quaternary)

            Button("退出") {
                coordinator.stop()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private var isFocusing: Bool {
        if case .focusing = coordinator.sessionState { return true }
        return false
    }

    private var activeTaskId: String? {
        if case .focusing(let taskId, _) = coordinator.sessionState {
            return taskId
        }
        return nil
    }

    private var activeFocusTitle: String {
        switch coordinator.sessionState {
        case .focusing(let taskId, _):
            let name = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId })?.budget.displayName ?? taskId
            return "专注中 · \(name)"
        case .paused(let taskId, _):
            let name = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId })?.budget.displayName ?? taskId
            return "已暂停 · \(name)"
        case .unassigned:
            return "待命 · 未指定专注"
        }
    }

    private var timerColor: Color {
        guard case .focusing(let taskId, _) = coordinator.sessionState,
              let progress = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId }) else {
            return .secondary
        }
        switch progress.status {
        case .capReached, .approachingCap:
            return DayHelmColors.warningAmber
        case .targetMet:
            return DayHelmColors.successEmerald
        case .underTarget, .noBudget:
            return DayHelmColors.primaryBlue
        }
    }

    private var liveContextLine: String {
        guard let sample = coordinator.latestSample else {
            return "当前窗口: 等待采样..."
        }
        if sample.screenLocked {
            return "当前窗口: 屏幕已锁定"
        }
        if sample.redacted {
            return "当前窗口: \(sample.appName) (隐私已脱敏)"
        }
        if let title = sample.windowTitle, !title.isEmpty {
            return "当前窗口: \(sample.appName) - \(title)"
        }
        return "当前窗口: \(sample.appName)"
    }

    private func shortButtonName(_ name: String) -> String {
        switch name {
        case "电商日常运营": return "电商运营"
        case "Hermes 投研": return "Hermes"
        default: return name
        }
    }

    private func formattedTimer(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

private struct BudgetProgressRow: View {
    let progress: TaskProgress
    let isEditing: Bool
    let onToggleEdit: () -> Void
    let onSaveBudget: (Int?, Int?) -> Void

    @State private var draftTarget: Int = 60
    @State private var draftCap: Int = 90
    @State private var hasTarget: Bool = false
    @State private var hasCap: Bool = false

    private var ratio: Double {
        let denom = Double(progress.budget.capMinutes ?? progress.budget.targetMinutes ?? 60)
        guard denom > 0 else { return 0 }
        return min(1.0, max(0.0, progress.focusedMinutes / denom))
    }

    private var barColor: Color {
        switch progress.status {
        case .capReached, .approachingCap:
            return DayHelmColors.warningAmber
        case .targetMet:
            return DayHelmColors.successEmerald
        case .underTarget:
            return DayHelmColors.primaryBlue
        case .noBudget:
            return Color(hex: progress.budget.colorHex)
        }
    }

    private var quotaFractionText: String {
        let focused = Int(progress.focusedMinutes.rounded())
        if let target = progress.budget.targetMinutes {
            return "\(focused) / \(target)m"
        }
        if let cap = progress.budget.capMinutes {
            return "\(focused) / \(cap)m"
        }
        return "\(focused)m"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(progress.budget.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)

                Spacer()

                statusBadge

                Text(quotaFractionText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Button(action: {
                    draftTarget = progress.budget.targetMinutes ?? 60
                    hasTarget = progress.budget.targetMinutes != nil
                    draftCap = progress.budget.capMinutes ?? 60
                    hasCap = progress.budget.capMinutes != nil
                    onToggleEdit()
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(get: { isEditing }, set: { if !$0 { onToggleEdit() } })) {
                    budgetEditorPopover
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(barColor)
                        .frame(width: max(ratio > 0 ? 4 : 0, geo.size.width * ratio))
                }
            }
            .frame(height: 7)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch progress.status {
        case .underTarget(let remaining):
            Text("保底差 \(max(1, Int(remaining.rounded())))m")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DayHelmColors.primaryBlue)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.primaryBlue.opacity(0.12), in: Capsule())
        case .targetMet:
            Text("✓ 已达标")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DayHelmColors.successEmerald)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.successEmerald.opacity(0.14), in: Capsule())
        case .approachingCap(let remaining):
            Text("余 \(max(1, Int(remaining.rounded())))m")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DayHelmColors.warningAmber)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.warningAmber.opacity(0.14), in: Capsule())
        case .capReached:
            Text("⚠️ 已达上限")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DayHelmColors.warningAmber)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.warningAmber.opacity(0.16), in: Capsule())
        case .noBudget:
            EmptyView()
        }
    }

    private var budgetEditorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("调整「\(progress.budget.displayName)」配额")
                .font(.system(size: 12, weight: .semibold))

            Toggle(isOn: $hasTarget) {
                HStack {
                    Text("保底目标")
                        .font(.system(size: 11))
                    Spacer()
                    if hasTarget {
                        Stepper("\(draftTarget)m", value: $draftTarget, in: 5...480, step: 5)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }

            Toggle(isOn: $hasCap) {
                HStack {
                    Text("封顶上限")
                        .font(.system(size: 11))
                    Spacer()
                    if hasCap {
                        Stepper("\(draftCap)m", value: $draftCap, in: 5...480, step: 5)
                            .font(.system(size: 11, design: .monospaced))
                            .monospacedDigit()
                    }
                }
            }

            HStack {
                Spacer()
                Button("保存") {
                    onSaveBudget(hasTarget ? draftTarget : nil, hasCap ? draftCap : nil)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(width: 220)
    }
}
