import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var pillModel: MenuBarPillModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: pillModel.text.isEmpty ? 0 : 4) {
            Image(nsImage: DayHelmMenuBarIcon.image(for: pillModel.visualState, isDark: colorScheme == .dark))
            if !pillModel.text.isEmpty {
                Text(pillModel.text)
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
            }
        }
        .help(pillModel.helpText)
    }
}

struct MenuBarPopoverView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var noteText: String = ""

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
        .onAppear {
            coordinator.setPopoverVisible(true)
        }
        .onDisappear {
            coordinator.setPopoverVisible(false)
        }
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

            if !coordinator.axTrusted {
                Button(action: { coordinator.openAccessibilitySettings() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                        Text("AX 待授权")
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
            if !coordinator.recorderSettings.activityRecorderEnabled {
                Button {
                    openRecorderWindow(section: .capture)
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 5.5, height: 5.5)
                        Text("活动记录器已暂停")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("活动记录器已暂停，点击打开设置")
            } else {
                // 1. AX Title Status
                if coordinator.axTrusted {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DayHelmColors.successEmerald)
                            .frame(width: 5.5, height: 5.5)
                        Text("AX")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                } else {
                    Button {
                        coordinator.openAccessibilitySettings()
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DayHelmColors.warningAmber)
                                .frame(width: 5.5, height: 5.5)
                            Text("AX 待授权")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DayHelmColors.warningAmber)
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("点击前往辅助功能授权")
                }

                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)

                // 2. Screen OCR Toggle / Permission Button
                if !coordinator.deepRecordingEnabled {
                    Button {
                        coordinator.setDeepRecordingEnabled(true)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.secondary.opacity(0.45))
                                .frame(width: 5.5, height: 5.5)
                            Text("OCR 已关")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("点击开启去重屏幕快照与 Vision OCR")
                } else if coordinator.screenCaptureTrusted {
                    Button {
                        coordinator.setDeepRecordingEnabled(false)
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(DayHelmColors.primaryBlue)
                                .frame(width: 5.5, height: 5.5)
                            Text("OCR \(coordinator.todayOCRCount) 帧")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("今日已捕获 \(coordinator.todaySnapshotCount) 张去重快照，\(coordinator.todayOCRCount) 帧 OCR；点击可暂停屏幕快照")
                } else {
                    HStack(spacing: 4) {
                        Button {
                            _ = coordinator.requestScreenCapturePermission()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "camera.viewfinder")
                                    .font(.system(size: 9))
                                Text("授权录屏")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(DayHelmColors.warningAmber)
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
                        .help("点击申请 Screen Recording 权限以启用去重快照与 Apple Vision OCR")

                        Button {
                            coordinator.setDeepRecordingEnabled(false)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("仅使用 AX 标题录制，关闭屏幕 OCR")
                    }
                }
            }

            Text("·")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)

            // 3. Agent HTTP API Indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(coordinator.apiServerPort != nil ? DayHelmColors.successEmerald : Color.secondary.opacity(0.35))
                    .frame(width: 5.5, height: 5.5)
                Text("API :\(coordinator.apiServerPort.map(String.init) ?? String(LocalActivityHTTPServer.defaultPrimaryPort))")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
            .help(apiServerHelpText)

            if coordinator.jevNeedsAPIKey {
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)

                Button {
                    openRecorderWindow(section: .jev)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(DayHelmColors.warningAmber)
                            .frame(width: 5.5, height: 5.5)
                        Text("Jev 待配Key")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DayHelmColors.warningAmber)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help("已开启 Jev 自动识别，点击前往配置 JEV_API_KEY")
            } else if coordinator.recorderSettings.jevAutoTrackingEnabled && coordinator.jevAPIKeyConfigured {
                Text("·")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)

                Button {
                    openRecorderWindow(section: .jev)
                } label: {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(coordinator.jevLastError == nil ? DayHelmColors.successEmerald : DayHelmColors.warningAmber)
                            .frame(width: 5.5, height: 5.5)
                        Text("Jev")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
                .help(jevStatusHelpText)
            }

            Spacer(minLength: 4)

            Button {
                openRecorderWindow(preferSettingsIfOnHistory: true)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("打开设置与历史会话")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4.5)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
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
                    HStack(spacing: 5) {
                        Text(activeFocusTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isFocusing || coordinator.activeActivityMode != nil || coordinator.activeNonBudgetActivity != nil ? .primary : .secondary)

                        if coordinator.recorderSettings.jevAutoTrackingEnabled && coordinator.jevIsManualPinned {
                            Button {
                                coordinator.resumeAutoTracking()
                            } label: {
                                Text("恢复自动")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(DayHelmColors.primaryBlue)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(DayHelmColors.primaryBlue.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .help("解除手动锁定，交回 Jev 自动识别")
                        }
                    }
                    Text(liveContextLine)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text(formattedTimer(displayedTimerSeconds))
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

            // Compact Layer-1 Activity Mode breakdown when auto-tracking has recorded mode minutes
            let activeModes = ActivityMode.allCases.compactMap { mode -> (ActivityMode, Int)? in
                let m = Int((coordinator.activityModeMinutes[mode.rawValue] ?? 0).rounded())
                return m > 0 ? (mode, m) : nil
            }
            if !activeModes.isEmpty {
                HStack(spacing: 5) {
                    ForEach(activeModes.prefix(4), id: \.0.rawValue) { mode, mins in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(hex: mode.colorHex))
                                .frame(width: 5, height: 5)
                            Text("\(mode.compactLabel) \(mins)m")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.045), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("今日事项配额")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                if !coordinator.taskProgressList.isEmpty {
                    Text(budgetSummaryPillText)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                }

                Spacer()
            }

            if coordinator.taskProgressList.isEmpty {
                Button {
                    openRecorderWindow(section: .tasks)
                } label: {
                    Text("暂无事项，前往「设置」添加")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 5) {
                    ForEach(coordinator.taskProgressList) { progress in
                        BudgetProgressRow(
                            progress: progress,
                            isActive: activeTaskId == progress.budget.taskId,
                            onSelectTask: {
                                let submitted = noteText
                                noteText = ""
                                coordinator.selectTask(progress.budget.taskId, note: submitted.isEmpty ? nil : submitted)
                            }
                        )
                    }
                }
            }
        }
    }

    private var budgetSummaryPillText: String {
        let totalFocused = Int(coordinator.taskProgressList.reduce(0.0) { $0 + $1.focusedMinutes }.rounded())
        let targetTasks = coordinator.taskProgressList.filter { $0.budget.targetMinutes != nil }
        if !targetTasks.isEmpty {
            let metCount = targetTasks.filter {
                if case .targetMet = $0.status { return true }
                return false
            }.count
            return "已投 \(totalFocused)m · 达标 \(metCount)/\(targetTasks.count)"
        }
        return "已投 \(totalFocused)m"
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
        HStack(spacing: 4) {
            Button {
                coordinator.triggerDemoAlert()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bell.badge")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("提醒测试")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(DayHelmColors.primaryBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(DayHelmColors.primaryBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help("模拟触发监督提醒测试")

            Spacer(minLength: 2)

            Button {
                openRecorderWindow(preferSettingsIfOnHistory: true)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("设置")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 5.5)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                openRecorderWindow(section: .dailyStats)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("统计")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 5.5)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .help("打开每日确定性统计报表")

            Button {
                openRecorderWindow(section: .history)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 9.5, weight: .medium))
                    Text("历史会话")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.primary.opacity(0.85))
                .padding(.horizontal, 5.5)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)

            Button {
                coordinator.openConfigDirectory()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.8))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("在 Finder 中打开配置与数据目录")

            Button {
                coordinator.stop()
                NSApplication.shared.terminate(nil)
            } label: {
                Text("退出")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.78))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Helpers

    private func openRecorderWindow(
        section: ActivityRecorderSection? = nil,
        preferSettingsIfOnHistory: Bool = false
    ) {
        dismiss()
        DispatchQueue.main.async { [coordinator] in
            ActivityRecorderWindowController.shared.show(
                coordinator: coordinator,
                section: section,
                preferSettingsIfOnHistory: preferSettingsIfOnHistory
            )
        }
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

    private var jevStatusHelpText: String {
        if let err = coordinator.jevLastError, !err.isEmpty {
            return "Jev 自动识别异常：\(err)"
        }
        if let cls = coordinator.jevLastClassification {
            let pct = Int((cls.confidence * 100).rounded())
            return "Jev 自动识别运行中 · 最近置信度 \(pct)%"
        }
        return "Jev 智能自动识别已就绪"
    }

    private var displayedTimerSeconds: TimeInterval {
        if isFocusing {
            return coordinator.elapsedFocusSeconds
        }
        if let mode = coordinator.activeActivityMode {
            let mins = coordinator.activityModeMinutes[mode.rawValue] ?? (mode.isDistraction ? coordinator.nonWorkMinutes : coordinator.otherWorkMinutes)
            return mins * 60.0
        }
        if let nonBudget = coordinator.activeNonBudgetActivity {
            switch nonBudget {
            case .otherWork:
                return coordinator.otherWorkMinutes * 60.0
            case .nonWork:
                return coordinator.nonWorkMinutes * 60.0
            }
        }
        return 0
    }

    private var activeFocusTitle: String {
        let isJevLive = coordinator.recorderSettings.jevAutoTrackingEnabled && coordinator.jevAPIKeyConfigured
        switch coordinator.sessionState {
        case .focusing(let taskId, _):
            let name = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId })?.budget.displayName ?? taskId
            if isJevLive {
                return coordinator.jevIsManualPinned ? "手动纠偏 · \(name)" : "自动追踪 · \(name)"
            }
            return "专注中 · \(name)"
        case .paused(let taskId, _):
            let name = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId })?.budget.displayName ?? taskId
            return "已暂停 · \(name)"
        case .unassigned:
            if let mode = coordinator.activeActivityMode {
                return "自动追踪 · \(mode.displayName)"
            }
            if let nonBudget = coordinator.activeNonBudgetActivity {
                switch nonBudget {
                case .otherWork:
                    return "自动追踪 · 其他事务"
                case .nonWork:
                    return "自动追踪 · 分心/休息"
                }
            }
            return isJevLive ? "自动追踪 · 等待识别" : "待命 · 未指定专注"
        }
    }

    private var timerColor: Color {
        if case .focusing(let taskId, _) = coordinator.sessionState,
           let progress = coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId }) {
            switch progress.status {
            case .capReached, .approachingCap:
                return DayHelmColors.warningAmber
            case .targetMet:
                return DayHelmColors.successEmerald
            case .underTarget, .noBudget:
                return DayHelmColors.primaryBlue
            }
        }
        if let mode = coordinator.activeActivityMode {
            return Color(hex: mode.colorHex)
        }
        if let nonBudget = coordinator.activeNonBudgetActivity {
            switch nonBudget {
            case .otherWork:
                return .secondary
            case .nonWork:
                return DayHelmColors.destructiveRed
            }
        }
        return .secondary
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
    let isActive: Bool
    let onSelectTask: () -> Void

    private var taskColor: Color {
        Color(hex: progress.budget.colorHex)
    }

    private var ratio: Double {
        let denom = Double(progress.budget.capMinutes ?? progress.budget.targetMinutes ?? 60)
        guard denom > 0 else { return 0 }
        return min(1.0, max(0.0, progress.focusedMinutes / denom))
    }

    private var targetMarkerRatio: Double? {
        guard let target = progress.budget.targetMinutes,
              let cap = progress.budget.capMinutes,
              target > 0, cap > 0, target < cap else {
            return nil
        }
        return Double(target) / Double(cap)
    }

    private var percentageText: String {
        let denom = Double(progress.budget.capMinutes ?? progress.budget.targetMinutes ?? 60)
        guard denom > 0 else { return "0%" }
        let pct = Int(((progress.focusedMinutes / denom) * 100.0).rounded())
        return "\(max(0, pct))%"
    }

    private var barColor: Color {
        switch progress.status {
        case .capReached, .approachingCap:
            return DayHelmColors.warningAmber
        case .targetMet:
            return DayHelmColors.successEmerald
        case .underTarget, .noBudget:
            return taskColor
        }
    }

    private var focusedText: String {
        "\(Int(progress.focusedMinutes.rounded()))"
    }

    private var denominatorText: String {
        if let target = progress.budget.targetMinutes, let cap = progress.budget.capMinutes {
            if progress.focusedMinutes >= Double(target) {
                return "/\(cap)m"
            }
            return "/\(target)m"
        }
        if let target = progress.budget.targetMinutes {
            return "/\(target)m"
        }
        if let cap = progress.budget.capMinutes {
            return "/\(cap)m"
        }
        return "m"
    }

    var body: some View {
        Button(action: onSelectTask) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    headerLabelContent
                    Spacer(minLength: 4)
                    statusBadge
                    fractionLabel
                }

                telemetryBarRow
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击切换到「\(progress.budget.displayName)」")
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            isActive ? taskColor.opacity(0.08) : Color.primary.opacity(0.03),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isActive ? taskColor.opacity(0.50) : Color.primary.opacity(0.07),
                    lineWidth: isActive ? 1.0 : 0.5
                )
        )
    }

    private var headerLabelContent: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(taskColor)
                .frame(width: 6.5, height: 6.5)

            Text(progress.budget.displayName)
                .font(.system(size: 11.5, weight: isActive ? .semibold : .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            if isActive {
                Text("专注中")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(taskColor)
                    .padding(.horizontal, 4.5)
                    .padding(.vertical, 1.5)
                    .background(taskColor.opacity(0.14), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private var fractionLabel: some View {
        HStack(spacing: 0) {
            Text(focusedText)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(denominatorText)
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var telemetryBarRow: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(barColor)
                        .frame(width: max(ratio > 0 ? 4 : 0, geo.size.width * ratio))

                    if let marker = targetMarkerRatio {
                        Rectangle()
                            .fill(Color.primary.opacity(0.32))
                            .frame(width: 1.5, height: 6)
                            .offset(x: max(0, min(geo.size.width - 1.5, geo.size.width * marker - 0.75)))
                    }
                }
            }
            .frame(height: 6)

            Text(percentageText)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch progress.status {
        case .underTarget(let remaining):
            Text("保底差 \(max(1, Int(remaining.rounded())))m")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DayHelmColors.primaryBlue)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.primaryBlue.opacity(0.12), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        case .targetMet:
            Text("✓ 已达标")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DayHelmColors.successEmerald)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.successEmerald.opacity(0.14), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        case .approachingCap(let remaining):
            Text("余 \(max(1, Int(remaining.rounded())))m")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DayHelmColors.warningAmber)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.warningAmber.opacity(0.14), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        case .capReached:
            Text("已达上限")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(DayHelmColors.warningAmber)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(DayHelmColors.warningAmber.opacity(0.16), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
        case .noBudget:
            if let cap = progress.budget.capMinutes {
                Text("上限 \(cap)m")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            } else {
                Text("自由计时")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
}
