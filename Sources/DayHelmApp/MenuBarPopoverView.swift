import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: DayHelmMenuBarIcon.templateImage)
                .renderingMode(.template)
            Text(pillText)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .monospacedDigit()
        }
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
    @State private var editingTaskId: String?
    @State private var isCreatingTask: Bool = false
    @State private var isManagingTasks: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            headerSection
            recorderEngineBar
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
            DayHelmHeaderLogoView(size: 26)

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
                    Text(coordinator.almaConnected ? "Alma + 原生采集中" : "原生独立采集中")
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

    private var recorderEngineBar: some View {
        HStack(spacing: 6) {
            Text("采集与 OCR 引擎")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 2)

            // 1. AX Title Status
            if coordinator.axTrusted {
                HStack(spacing: 3) {
                    Circle()
                        .fill(DayHelmColors.successEmerald)
                        .frame(width: 5, height: 5)
                    Text("AX 标题")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    coordinator.openAccessibilitySettings()
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(DayHelmColors.warningAmber)
                            .frame(width: 5, height: 5)
                        Text("AX 标题")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(DayHelmColors.warningAmber)
                    }
                }
                .buttonStyle(.plain)
                .help("点击前往辅助功能授权")
            }

            Text("·")
                .font(.system(size: 9.5))
                .foregroundStyle(.quaternary)

            // 2. Screen OCR Toggle / Permission Button
            if !coordinator.deepRecordingEnabled {
                Button {
                    coordinator.setDeepRecordingEnabled(true)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 5, height: 5)
                        Text("屏幕 OCR 已关")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("点击开启去重屏幕快照与 Vision OCR")
            } else if coordinator.screenCaptureTrusted {
                Button {
                    coordinator.setDeepRecordingEnabled(false)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(DayHelmColors.primaryBlue)
                            .frame(width: 5, height: 5)
                        Text("屏幕 OCR (\(coordinator.todayOCRCount) 帧)")
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .help("今日已捕获 \(coordinator.todaySnapshotCount) 张去重快照，\(coordinator.todayOCRCount) 帧 OCR；点击可暂停深度录屏")
            } else {
                HStack(spacing: 3) {
                    Button {
                        _ = coordinator.requestScreenCapturePermission()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 8.5))
                            Text("授权录屏 OCR")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(DayHelmColors.warningAmber)
                    }
                    .buttonStyle(.plain)
                    .help("点击申请 Screen Recording 权限以启用去重快照与 Apple Vision OCR")

                    Button {
                        coordinator.setDeepRecordingEnabled(false)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("仅使用 AX 标题录制，关闭屏幕 OCR")
                }
            }

            Text("·")
                .font(.system(size: 9.5))
                .foregroundStyle(.quaternary)

            // 3. Agent HTTP API Indicator
            HStack(spacing: 3) {
                Circle()
                    .fill(coordinator.apiServerPort != nil ? DayHelmColors.successEmerald : Color.secondary.opacity(0.35))
                    .frame(width: 5, height: 5)
                Text("API :\(coordinator.apiServerPort.map(String.init) ?? "23002")")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .help(apiServerHelpText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var apiServerHelpText: String {
        if coordinator.apiServerPorts.isEmpty {
            return "本地 Agent HTTP API 未启动"
        }
        let portsStr = coordinator.apiServerPorts.map { "127.0.0.1:\($0)" }.joined(separator: ", ")
        return "Agent 与 alma-time-audit 本地兼容 API 运行中：\(portsStr)"
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

    // MARK: - 3. Daily Quota Budget Bars & Task CRUD

    private var budgetListSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("今日事项配额")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if coordinator.taskProgressList.count > 1 {
                    Button {
                        isManagingTasks.toggle()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isManagingTasks ? "checkmark" : "arrow.up.arrow.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isManagingTasks ? "完成" : "管理")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(isManagingTasks ? DayHelmColors.primaryBlue : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            isManagingTasks ? DayHelmColors.primaryBlue.opacity(0.12) : Color.primary.opacity(0.05),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    editingTaskId = nil
                    isCreatingTask = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("新增事项")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DayHelmColors.primaryBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(DayHelmColors.primaryBlue.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isCreatingTask) {
                    TaskEditorPopover(
                        mode: .create,
                        initialName: "",
                        initialColorHex: nextSuggestedColorHex(),
                        initialKeywords: [],
                        initialTargetMinutes: 60,
                        initialHasTarget: true,
                        initialCapMinutes: 90,
                        initialHasCap: false,
                        onSave: { name, colorHex, target, cap, keywords in
                            coordinator.addTask(
                                displayName: name,
                                colorHex: colorHex,
                                targetMinutes: target,
                                capMinutes: cap,
                                keywords: keywords
                            )
                            isCreatingTask = false
                        },
                        onDelete: nil,
                        onCancel: {
                            isCreatingTask = false
                        }
                    )
                }
            }

            if coordinator.taskProgressList.isEmpty {
                Text("暂无事项，点击右上角「+ 新增事项」开始规划")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                let items = coordinator.taskProgressList
                ForEach(Array(items.enumerated()), id: \.element.id) { index, progress in
                    BudgetProgressRow(
                        progress: progress,
                        isManaging: isManagingTasks,
                        canMoveUp: index > 0,
                        canMoveDown: index < items.count - 1,
                        isEditing: editingTaskId == progress.budget.taskId,
                        onToggleEdit: {
                            isCreatingTask = false
                            editingTaskId = (editingTaskId == progress.budget.taskId) ? nil : progress.budget.taskId
                        },
                        onMoveUp: {
                            guard index > 0 else { return }
                            coordinator.moveTask(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                        },
                        onMoveDown: {
                            guard index < items.count - 1 else { return }
                            coordinator.moveTask(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                        },
                        onSaveTask: { name, colorHex, target, cap, keywords in
                            coordinator.updateTask(
                                TaskBudget(
                                    taskId: progress.budget.taskId,
                                    displayName: name,
                                    colorHex: colorHex,
                                    targetMinutes: target,
                                    capMinutes: cap,
                                    keywords: keywords
                                )
                            )
                            editingTaskId = nil
                        },
                        onDeleteTask: {
                            editingTaskId = nil
                            coordinator.deleteTask(taskId: progress.budget.taskId)
                            if coordinator.taskProgressList.count <= 1 {
                                isManagingTasks = false
                            }
                        }
                    )
                }
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

    private func nextSuggestedColorHex() -> String {
        let idx = coordinator.taskProgressList.count % DayHelmColors.taskPalette.count
        return DayHelmColors.taskPalette[idx].hex
    }

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
    let isManaging: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let isEditing: Bool
    let onToggleEdit: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSaveTask: (String, String, Int?, Int?, [String]) -> Void
    let onDeleteTask: () -> Void

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
                Circle()
                    .fill(Color(hex: progress.budget.colorHex))
                    .frame(width: 6, height: 6)

                Text(progress.budget.displayName)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if isManaging {
                    HStack(spacing: 4) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9.5, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveUp)
                        .opacity(canMoveUp ? 1.0 : 0.35)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9.5, weight: .semibold))
                                .frame(width: 18, height: 18)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveDown)
                        .opacity(canMoveDown ? 1.0 : 0.35)

                        Button(action: onDeleteTask) {
                            Image(systemName: "trash")
                                .font(.system(size: 9.5))
                                .foregroundStyle(DayHelmColors.destructiveRed)
                                .frame(width: 18, height: 18)
                                .background(DayHelmColors.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    statusBadge

                    Text(quotaFractionText)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Button(action: onToggleEdit) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10))
                        .foregroundStyle(isEditing ? DayHelmColors.primaryBlue : .secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(get: { isEditing }, set: { if !$0 { onToggleEdit() } })) {
                    TaskEditorPopover(
                        mode: .edit,
                        initialName: progress.budget.displayName,
                        initialColorHex: progress.budget.colorHex,
                        initialKeywords: progress.budget.keywords,
                        initialTargetMinutes: progress.budget.targetMinutes ?? 60,
                        initialHasTarget: progress.budget.targetMinutes != nil,
                        initialCapMinutes: progress.budget.capMinutes ?? 90,
                        initialHasCap: progress.budget.capMinutes != nil,
                        onSave: onSaveTask,
                        onDelete: onDeleteTask,
                        onCancel: onToggleEdit
                    )
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
}

private struct TaskEditorPopover: View {
    enum Mode {
        case create
        case edit
    }

    let mode: Mode
    let initialName: String
    let initialColorHex: String
    let initialKeywords: [String]
    let initialTargetMinutes: Int
    let initialHasTarget: Bool
    let initialCapMinutes: Int
    let initialHasCap: Bool
    let onSave: (String, String, Int?, Int?, [String]) -> Void
    let onDelete: (() -> Void)?
    let onCancel: () -> Void

    @State private var displayName: String = ""
    @State private var selectedColorHex: String = "#3B82F6"
    @State private var keywordsText: String = ""
    @State private var hasTarget: Bool = true
    @State private var targetMinutes: Int = 60
    @State private var hasCap: Bool = false
    @State private var capMinutes: Int = 90

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(mode == .create ? "新增今日事项" : "编辑事项与配额")
                .font(.system(size: 12.5, weight: .semibold))

            // 1. Task name + Color dots
            VStack(alignment: .leading, spacing: 6) {
                Text("事项名称")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("例如：电商做深 / 深度写作", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                HStack(spacing: 8) {
                    Text("标识颜色")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach(DayHelmColors.taskPalette, id: \.hex) { item in
                        let isSelected = selectedColorHex.caseInsensitiveCompare(item.hex) == .orderedSame
                        Button {
                            selectedColorHex = item.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: item.hex))
                                .frame(width: 16, height: 16)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: isSelected ? 2 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(isSelected ? 0.55 : 0.15), lineWidth: 1)
                                        .padding(-1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
                .padding(.top, 2)
            }

            // 2. Keywords
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("匹配关键词（可选）")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("逗号分隔")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }

                TextField("如：抖店, 1688, 主图", text: $keywordsText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            // 3. Target Minutes (Slider + direct TextField)
            QuotaDurationEditor(
                title: "保底目标 (Target)",
                accentColor: DayHelmColors.primaryBlue,
                isEnabled: $hasTarget,
                minutes: $targetMinutes
            )

            // 4. Cap Minutes (Slider + direct TextField)
            QuotaDurationEditor(
                title: "封顶上限 (Cap)",
                accentColor: DayHelmColors.warningAmber,
                isEnabled: $hasCap,
                minutes: $capMinutes
            )

            // 5. Footer actions
            HStack(spacing: 8) {
                if mode == .edit, let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Text("删除")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DayHelmColors.destructiveRed)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

                Button("保存") {
                    let parsedKeywords = keywordsText
                        .replacingOccurrences(of: "，", with: ",")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    onSave(
                        trimmedName,
                        selectedColorHex,
                        hasTarget ? targetMinutes : nil,
                        hasCap ? capMinutes : nil,
                        parsedKeywords
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(trimmedName.isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(14)
        .frame(width: 300)
        .onAppear {
            displayName = initialName
            selectedColorHex = initialColorHex
            keywordsText = initialKeywords.joined(separator: ", ")
            hasTarget = initialHasTarget
            targetMinutes = initialTargetMinutes
            hasCap = initialHasCap
            capMinutes = initialCapMinutes
        }
    }
}

private struct QuotaDurationEditor: View {
    let title: String
    let accentColor: Color
    @Binding var isEnabled: Bool
    @Binding var minutes: Int

    @State private var textValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle(isOn: $isEnabled) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .toggleStyle(.checkbox)

                Spacer()

                if isEnabled {
                    HStack(spacing: 4) {
                        TextField("60", text: $textValue)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                            .onChange(of: textValue) { _, newValue in
                                let digits = newValue.filter(\.isNumber)
                                if digits != newValue {
                                    textValue = digits
                                }
                                if let parsed = Int(digits), parsed > 0 {
                                    minutes = min(720, parsed)
                                }
                            }
                            .onSubmit {
                                commitText()
                            }

                        Text("分钟")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("未启用")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }

            if isEnabled {
                HStack(spacing: 7) {
                    Text("5m")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Slider(
                        value: Binding(
                            get: { Double(min(240, max(5, minutes))) },
                            set: { newValue in
                                let rounded = Int(newValue.rounded())
                                minutes = rounded
                                textValue = "\(rounded)"
                            }
                        ),
                        in: 5...240,
                        step: 5
                    )
                    .tint(accentColor)

                    Text("240m")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onAppear {
            textValue = "\(minutes)"
        }
        .onChange(of: minutes) { _, newValue in
            if Int(textValue) != newValue {
                textValue = "\(newValue)"
            }
        }
    }

    private func commitText() {
        if let parsed = Int(textValue), parsed > 0 {
            let clamped = min(720, max(1, parsed))
            minutes = clamped
            textValue = "\(clamped)"
        } else {
            textValue = "\(minutes)"
        }
    }
}
