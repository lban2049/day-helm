import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

struct ActivityRecorderTitlebarNavView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    @ObservedObject var navState: ActivityRecorderNavigationState
    @State private var hoveredSection: ActivityRecorderSection?

    var body: some View {
        HStack(spacing: 14) {
            if navState.activeSection == .history {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        navState.isHistorySidebarVisible.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 24)
                        .background(
                            Color.primary.opacity(navState.isHistorySidebarVisible ? 0.06 : 0.0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help(navState.isHistorySidebarVisible ? "收起会话列表" : "展开会话列表")
            }

            HStack(spacing: 7) {
                DayHelmHeaderLogoView(size: 20)
                Text("DayHelm")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 4) {
                ForEach(ActivityRecorderSection.allCases, id: \.self) { section in
                    let isSelected = navState.activeSection == section
                    let isHovered = hoveredSection == section
                    Button {
                        navState.activeSection = section
                    } label: {
                        HStack(spacing: 4) {
                            Text(section.rawValue)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .primary : .secondary)

                            if section == .jev && coordinator.jevNeedsAPIKey {
                                Circle()
                                    .fill(DayHelmColors.warningAmber)
                                    .frame(width: 5.5, height: 5.5)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Color.primary.opacity(isSelected ? 0.08 : (isHovered ? 0.045 : 0.0)),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredSection = hovering ? section : (hoveredSection == section ? nil : hoveredSection)
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(.vertical, 2)
        .fixedSize()
    }
}

struct ActivityRecorderTitlebarStatusView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    @ObservedObject var navState: ActivityRecorderNavigationState

    var body: some View {
        HStack(spacing: 8) {
            if coordinator.isSyntheticDemo {
                Text("DEMO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DayHelmColors.warningAmber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DayHelmColors.warningAmber.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }

            statusBadge

            Button {
                navState.refreshNonce += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("刷新权限状态、统计与会话列表")
        }
        .padding(.vertical, 2)
        .fixedSize()
    }

    private var statusBadge: some View {
        let isEnabled = coordinator.recorderSettings.activityRecorderEnabled
        let isActiveSession = isEnabled && coordinator.recorderStats.activeSessionId != nil
        let dotColor: Color = !isEnabled
            ? .secondary.opacity(0.5)
            : (isActiveSession ? DayHelmColors.successEmerald : DayHelmColors.primaryBlue)
        let labelText = !isEnabled ? "已暂停" : (isActiveSession ? "采集中" : "空闲")

        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(labelText)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isEnabled ? .primary : .secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}

struct ActivityRecorderView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    @ObservedObject var navState: ActivityRecorderNavigationState

    @State private var searchQuery: String = ""
    @State private var selectedDetail: RecordedSessionDetail?

    var body: some View {
        Group {
            if navState.activeSection == .history {
                ActivityRecorderHistoryTab(
                    coordinator: coordinator,
                    showSidebar: navState.isHistorySidebarVisible,
                    selectedSessionId: $navState.selectedSessionId,
                    searchQuery: $searchQuery,
                    selectedDetail: $selectedDetail
                )
            } else {
                ActivityRecorderSettingsTab(
                    coordinator: coordinator,
                    selectedSection: $navState.activeSection,
                    onOpenSession: { sessionId in
                        navState.selectedSessionId = sessionId
                        navState.activeSection = .history
                        selectedDetail = coordinator.loadSessionDetail(sessionId: sessionId)
                    },
                    onOpenAllHistory: {
                        coordinator.refreshRecorderSessions(searchQuery: searchQuery)
                        if navState.selectedSessionId == nil {
                            navState.selectedSessionId = coordinator.recentSessions.first?.id
                        }
                        navState.activeSection = .history
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            refreshAll()
        }
        .onChange(of: navState.activeSection) { _, newSection in
            if newSection == .history {
                coordinator.refreshRecorderSessions(searchQuery: searchQuery)
                ensureSelection()
            } else {
                coordinator.refreshPermissions()
                coordinator.refreshRecorderCounts()
            }
        }
        .onChange(of: navState.refreshNonce) { _, _ in
            refreshAll()
        }
        .onChange(of: navState.selectedSessionId) { _, newId in
            if let newId {
                selectedDetail = coordinator.loadSessionDetail(sessionId: newId)
            } else {
                selectedDetail = nil
            }
        }
    }

    private func refreshAll() {
        coordinator.refreshPermissions()
        coordinator.refreshRecorderCounts()
        coordinator.refreshRecorderSessions(searchQuery: searchQuery)
        ensureSelection()
        if let id = navState.selectedSessionId {
            selectedDetail = coordinator.loadSessionDetail(sessionId: id)
        }
    }

    private func ensureSelection() {
        if let current = navState.selectedSessionId,
           coordinator.recentSessions.contains(where: { $0.id == current }) {
            if selectedDetail?.session.id != current {
                selectedDetail = coordinator.loadSessionDetail(sessionId: current)
            }
            return
        }
        if let first = coordinator.recentSessions.first {
            navState.selectedSessionId = first.id
            selectedDetail = coordinator.loadSessionDetail(sessionId: first.id)
        } else {
            navState.selectedSessionId = nil
            selectedDetail = nil
        }
    }
}

// MARK: - Settings Tab

private struct RecorderDraftSettings: Equatable {
    var activityRecorderEnabled: Bool
    var deepRecordingEnabled: Bool
    var visionOCREnabled: Bool
    var inputMonitoringEnabled: Bool
    var appFocusDebounceMsText: String
    var heartbeatIntervalMsText: String
    var recorderIdleThresholdMsText: String
    var typingPauseQuietMsText: String
    var visualCheckIntervalMsText: String
    var jpegQualityText: String
    var ocrLanguagesText: String
    var ocrEveryNText: String
    var sensitiveBundleIdsText: String
    var maxStorageMBText: String
    var retentionDaysText: String
    var menuBarDisplayMode: MenuBarDisplayMode
    var jevAutoTrackingEnabled: Bool
    var jevModelText: String
    var jevSendOCRSnippet: Bool

    init(from settings: DayHelmSettings) {
        self.activityRecorderEnabled = settings.activityRecorderEnabled
        self.deepRecordingEnabled = settings.deepRecordingEnabled
        self.visionOCREnabled = settings.visionOCREnabled
        self.inputMonitoringEnabled = settings.inputMonitoringEnabled
        self.appFocusDebounceMsText = "\(settings.appFocusDebounceMs)"
        self.heartbeatIntervalMsText = "\(settings.heartbeatIntervalMs)"
        self.recorderIdleThresholdMsText = "\(settings.recorderIdleThresholdMs)"
        self.typingPauseQuietMsText = "\(settings.typingPauseQuietMs)"
        self.visualCheckIntervalMsText = "\(settings.visualCheckIntervalMs)"
        self.jpegQualityText = "\(settings.jpegQuality)"
        self.ocrLanguagesText = settings.ocrLanguages.joined(separator: ", ")
        self.ocrEveryNText = "\(settings.ocrEveryN)"
        self.sensitiveBundleIdsText = settings.sensitiveBundleIds.joined(separator: "\n")
        self.maxStorageMBText = "\(max(0, settings.snapshotMaxStorageBytes / (1024 * 1024)))"
        self.retentionDaysText = "\(settings.snapshotRetentionDays)"
        self.menuBarDisplayMode = settings.menuBarDisplayMode
        self.jevAutoTrackingEnabled = settings.jevAutoTrackingEnabled
        self.jevModelText = settings.jevModel
        self.jevSendOCRSnippet = settings.jevSendOCRSnippet
    }

    func buildSettings(fallback: DayHelmSettings) -> DayHelmSettings {
        let debounce = Int(appFocusDebounceMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.appFocusDebounceMs
        let heartbeat = Int(heartbeatIntervalMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.heartbeatIntervalMs
        let idle = Int(recorderIdleThresholdMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.recorderIdleThresholdMs
        let typingPause = Int(typingPauseQuietMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.typingPauseQuietMs
        let visualCheck = Int(visualCheckIntervalMsText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.visualCheckIntervalMs
        let jpegQ = Int(jpegQualityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.jpegQuality
        let ocrEvery = Int(ocrEveryNText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.ocrEveryN
        let retention = Int(retentionDaysText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? fallback.snapshotRetentionDays
        let maxMB = Int64(maxStorageMBText.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? (fallback.snapshotMaxStorageBytes / (1024 * 1024))

        let langs = ocrLanguagesText
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let bundles = sensitiveBundleIdsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let trimmedModel = jevModelText.trimmingCharacters(in: .whitespacesAndNewlines)

        return DayHelmSettings(
            activityRecorderEnabled: activityRecorderEnabled,
            deepRecordingEnabled: deepRecordingEnabled,
            visionOCREnabled: visionOCREnabled,
            inputMonitoringEnabled: inputMonitoringEnabled,
            appFocusDebounceMs: debounce,
            heartbeatIntervalMs: heartbeat,
            recorderIdleThresholdMs: idle,
            typingPauseQuietMs: typingPause,
            visualCheckIntervalMs: visualCheck,
            jpegQuality: jpegQ,
            ocrLanguages: langs.isEmpty ? DayHelmSettings.defaultOCRLanguages : langs,
            sensitiveBundleIds: bundles,
            snapshotRetentionDays: retention,
            snapshotMaxStorageBytes: max(0, maxMB) * 1024 * 1024,
            ocrEveryN: ocrEvery,
            menuBarDisplayMode: menuBarDisplayMode,
            jevAutoTrackingEnabled: jevAutoTrackingEnabled,
            jevModel: trimmedModel.isEmpty ? DayHelmSettings.defaultJevModel : trimmedModel,
            jevSendOCRSnippet: jevSendOCRSnippet
        )
    }
}

private enum TaskEditorSheetMode: Identifiable {
    case create
    case edit(TaskBudget)

    var id: String {
        switch self {
        case .create: return "create"
        case .edit(let budget): return "edit-\(budget.taskId)"
        }
    }
}

private struct ActivityRecorderSettingsTab: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    @Binding var selectedSection: ActivityRecorderSection
    let onOpenSession: (String) -> Void
    let onOpenAllHistory: () -> Void

    @State private var draft: RecorderDraftSettings
    @State private var justSavedFeedback: Bool = false
    @State private var taskEditorMode: TaskEditorSheetMode?
    @State private var pendingDeleteTask: TaskBudget?
    @State private var jevAPIKeyInput: String = ""
    @State private var isEditingJevKey: Bool = false
    @State private var isTestingJevConnection: Bool = false
    @State private var jevTestStatusMessage: String?
    @State private var jevTestStatusIsError: Bool = false
    @State private var jevLogFilter: JevLogFilter = .all

    private enum JevLogFilter: String, CaseIterable {
        case all = "全部"
        case switched = "已切换"
        case pendingOrIgnored = "观察/忽略"
        case errors = "异常"
    }

    init(
        coordinator: HybridActivityCoordinator,
        selectedSection: Binding<ActivityRecorderSection>,
        onOpenSession: @escaping (String) -> Void,
        onOpenAllHistory: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        _selectedSection = selectedSection
        self.onOpenSession = onOpenSession
        self.onOpenAllHistory = onOpenAllHistory
        _draft = State(initialValue: RecorderDraftSettings(from: coordinator.recorderSettings))
    }

    private var hasUnsavedChanges: Bool {
        draft != RecorderDraftSettings(from: coordinator.recorderSettings)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch selectedSection {
                    case .tasks:
                        tasksManagementSection
                    case .jev:
                        jevManagementSection
                    case .capture:
                        overviewCard
                        permissionsCard
                        captureTimingCard
                        ocrAndInputCard
                        recentSessionsCard
                    case .privacyStorage, .history:
                        sensitiveAppsCard
                        storageQuotaCard
                    }
                }
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }

            if (selectedSection != .tasks && selectedSection != .jev) || hasUnsavedChanges {
                Divider()
                saveFooterBar
            }
        }
        .sheet(item: $taskEditorMode) { mode in
            TaskBudgetEditorSheet(
                mode: mode,
                suggestedColorHex: nextSuggestedColorHex(),
                onSave: { displayName, shortName, description, colorHex, targetMinutes, capMinutes, keywords, appBundleIds, domains in
                    switch mode {
                    case .create:
                        coordinator.addTask(
                            displayName: displayName,
                            shortName: shortName,
                            description: description,
                            colorHex: colorHex,
                            targetMinutes: targetMinutes,
                            capMinutes: capMinutes,
                            keywords: keywords,
                            appBundleIds: appBundleIds,
                            domains: domains
                        )
                    case .edit(let existing):
                        coordinator.updateTask(
                            TaskBudget(
                                taskId: existing.taskId,
                                displayName: displayName,
                                shortName: shortName,
                                description: description,
                                colorHex: colorHex,
                                targetMinutes: targetMinutes,
                                capMinutes: capMinutes,
                                keywords: keywords,
                                appBundleIds: appBundleIds,
                                domains: domains
                            )
                        )
                    }
                    taskEditorMode = nil
                },
                onDelete: { budget in
                    taskEditorMode = nil
                    coordinator.deleteTask(taskId: budget.taskId)
                },
                onCancel: {
                    taskEditorMode = nil
                }
            )
        }
        .alert(
            "删除事项「\(pendingDeleteTask?.displayName ?? "")」？",
            isPresented: Binding(
                get: { pendingDeleteTask != nil },
                set: { if !$0 { pendingDeleteTask = nil } }
            ),
            presenting: pendingDeleteTask
        ) { budget in
            Button("删除", role: .destructive) {
                coordinator.deleteTask(taskId: budget.taskId)
                pendingDeleteTask = nil
            }
            Button("取消", role: .cancel) {
                pendingDeleteTask = nil
            }
        } message: { _ in
            Text("删除后将从今日事项配额与快捷切换列表移除，今日已记录的时间片段仍保留在本地日志中。")
        }
        .onChange(of: coordinator.recorderSettings) { _, newSettings in
            let incoming = RecorderDraftSettings(from: newSettings)
            if !hasUnsavedChanges {
                draft = incoming
            } else {
                draft.activityRecorderEnabled = newSettings.activityRecorderEnabled
                draft.deepRecordingEnabled = newSettings.deepRecordingEnabled
                draft.visionOCREnabled = newSettings.visionOCREnabled
                draft.inputMonitoringEnabled = newSettings.inputMonitoringEnabled
                draft.menuBarDisplayMode = newSettings.menuBarDisplayMode
                draft.jevAutoTrackingEnabled = newSettings.jevAutoTrackingEnabled
                draft.jevSendOCRSnippet = newSettings.jevSendOCRSnippet
            }
        }
    }

    private func menuBarModeDescription(_ mode: MenuBarDisplayMode) -> String {
        switch mode {
        case .standard:
            return "标准（推荐）：命中焦点项目时显示项目名与配额（如 电商运营 52/90m），未命中时显示活动大类（如 开发构建 18m、休息分心 6m）"
        case .compact:
            return "极简：专注中仅显示进度数字（如 52/90m），活动大类显示短标签，悬停查看详情"
        case .iconOnly:
            return "仅图标：始终只保留日舵图标与语义状态点，最省顶部空间，悬停查看当前任务"
        }
    }

    private func nextSuggestedColorHex() -> String {
        let idx = coordinator.taskProgressList.count % DayHelmColors.taskPalette.count
        return DayHelmColors.taskPalette[idx].hex
    }

    // MARK: 1. Overview Card

    private var overviewCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(DayHelmColors.primaryBlue)
                            Text("活动记录器")
                                .font(.system(size: 13.5, weight: .bold))
                        }
                        Text("静默截屏、OCR 识别并跟踪输入事件，让 DayHelm 与 Alma 回答「我刚才在干什么」。数据不会离开本机。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { draft.activityRecorderEnabled },
                        set: { newVal in
                            draft.activityRecorderEnabled = newVal
                            commitDraft()
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(DayHelmColors.primaryBlue)
                }

                HStack(spacing: 10) {
                    metricPill(
                        icon: "clock",
                        title: "会话数",
                        value: "\(coordinator.recorderStats.totalSessions)"
                    )
                    metricPill(
                        icon: "cylinder.split.1x2",
                        title: "快照体积",
                        value: RecorderFormatting.bytes(coordinator.recorderStats.usedSnapshotBytes),
                        subtitle: "\(coordinator.recorderStats.totalSnapshots) 张 · \(coordinator.recorderStats.totalOCRFrames) OCR"
                    )
                    metricPill(
                        icon: "bolt",
                        title: "当前会话",
                        value: coordinator.recorderStats.activeSessionId != nil ? "活跃" : "空闲",
                        valueColor: coordinator.recorderStats.activeSessionId != nil ? DayHelmColors.successEmerald : .primary
                    )
                    metricPill(
                        icon: "viewfinder",
                        title: "前台应用",
                        value: foregroundAppLabel
                    )
                }

                storageUsageBar
            }
        }
    }

    private var foregroundAppLabel: String {
        guard let sample = coordinator.latestSample else { return "—" }
        if sample.screenLocked { return "已锁屏" }
        return sample.redacted ? "\(sample.appName) (脱敏)" : sample.appName
    }

    private var storageUsageBar: some View {
        let used = coordinator.recorderStats.usedSnapshotBytes
        let maxBytes = coordinator.recorderSettings.snapshotMaxStorageBytes
        let ratio: Double = maxBytes > 0 ? min(1.0, Double(used) / Double(maxBytes)) : 0
        let pct = maxBytes > 0 ? Int((Double(used) / Double(maxBytes) * 100).rounded()) : 0
        let barColor = ratio >= 0.85 ? DayHelmColors.warningAmber : DayHelmColors.primaryBlue

        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                if maxBytes > 0 {
                    Text("已用存储: \(RecorderFormatting.bytes(used)) / \(RecorderFormatting.bytes(maxBytes)) (\(pct)%)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    Text("已用存储: \(RecorderFormatting.bytes(used)) / 不限制")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("超出上限的旧快照会自动删除")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(barColor)
                        .frame(width: max(used > 0 ? 4 : 0, geo.size.width * ratio))
                }
            }
            .frame(height: 6)
        }
        .padding(.top, 2)
    }

    private func metricPill(
        icon: String,
        title: String,
        value: String,
        subtitle: String? = nil,
        valueColor: Color = .primary
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 13.5, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.tail)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 9.5, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }

    // MARK: 2. macOS Permissions Card

    private var permissionsCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("macOS 权限", systemImage: "checkmark.shield")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Button {
                        coordinator.refreshPermissions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("重新检测系统权限")
                }

                permissionRow(
                    title: "屏幕录制",
                    granted: coordinator.screenCaptureTrusted,
                    actionTitle: "申请 / 前往设置",
                    onAction: {
                        _ = coordinator.requestScreenCapturePermission()
                    }
                )

                permissionRow(
                    title: "辅助功能（用于全局键鼠监听 & AX 标题）",
                    granted: coordinator.axTrusted,
                    actionTitle: "前往授权",
                    onAction: {
                        coordinator.openAccessibilitySettings()
                    }
                )
            }
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        actionTitle: String,
        onAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: granted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(granted ? DayHelmColors.successEmerald : DayHelmColors.warningAmber)

            Text(title)
                .font(.system(size: 11.5, weight: .medium))

            Text(granted ? "(已授权)" : "(未授权)")
                .font(.system(size: 11))
                .foregroundStyle(granted ? Color.secondary : DayHelmColors.warningAmber)

            Spacer()

            if !granted {
                Button(actionTitle) {
                    onAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: 3. Capture Timing Card

    private var captureTimingCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("采集", systemImage: "bolt")
                    .font(.system(size: 12.5, weight: .semibold))

                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        numericField(
                            title: "快照防抖（毫秒）",
                            text: $draft.appFocusDebounceMsText,
                            hint: "两次采集之间的最小间隔（默认 4000）"
                        )
                        numericField(
                            title: "心跳间隔（毫秒）",
                            text: $draft.heartbeatIntervalMsText,
                            hint: "即使空闲也按此间隔强制采集（默认 120000）"
                        )
                    }
                    GridRow {
                        numericField(
                            title: "空闲阈值（毫秒）",
                            text: $draft.recorderIdleThresholdMsText,
                            hint: "无输入达到该时长后关闭会话并回扣空闲（默认 180000 = 3 分钟）"
                        )
                        numericField(
                            title: "输入停顿（毫秒）",
                            text: $draft.typingPauseQuietMsText,
                            hint: "无按键 N 毫秒后触发采集（默认 2000）"
                        )
                    }
                    GridRow {
                        numericField(
                            title: "画面变化轮询（毫秒）",
                            text: $draft.visualCheckIntervalMsText,
                            hint: "无输入时检测动画/视频（0 = 关闭）"
                        )
                        numericField(
                            title: "JPEG 质量",
                            text: $draft.jpegQualityText,
                            hint: "1–100，越低文件越小（默认 55）"
                        )
                    }
                }
            }
        }
    }

    // MARK: 4. OCR & Input Card

    private var ocrAndInputCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("OCR 与输入", systemImage: "doc.text.viewfinder")
                    .font(.system(size: 12.5, weight: .semibold))

                toggleSettingRow(
                    title: "开启屏幕快照（去重截屏）",
                    subtitle: "关闭后仅记录应用切换、AX 窗口标题与输入次数，不保存画面截图。",
                    isOn: Binding(
                        get: { draft.deepRecordingEnabled },
                        set: { newVal in
                            draft.deepRecordingEnabled = newVal
                            commitDraft()
                        }
                    )
                )

                Divider()

                toggleSettingRow(
                    title: "对每张快照运行 Vision OCR",
                    subtitle: "仅 macOS。识别屏幕文字供关键词与会话检索使用。",
                    isOn: Binding(
                        get: { draft.visionOCREnabled },
                        set: { newVal in
                            draft.visionOCREnabled = newVal
                            commitDraft()
                        }
                    )
                )

                Divider()

                toggleSettingRow(
                    title: "全局键盘与鼠标监听",
                    subtitle: "仅记录点击/按键次数，绝不记录按键字符或坐标。需要辅助功能权限。",
                    isOn: Binding(
                        get: { draft.inputMonitoringEnabled },
                        set: { newVal in
                            draft.inputMonitoringEnabled = newVal
                            commitDraft()
                        }
                    )
                )

                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("OCR 语言（Vision 代码，逗号分隔）")
                                .font(.system(size: 11, weight: .medium))
                            TextField("en-US, zh-Hans, zh-Hant, ja", text: $draft.ocrLanguagesText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                                .onSubmit { commitDraft() }
                        }

                        numericField(
                            title: "每 N 张快照 OCR 一次",
                            text: $draft.ocrEveryNText,
                            hint: "1 = 每张都识别，3 = 每 3 张识别 1 张。长会话可降低数据库负载。"
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: 5. Sensitive Apps Card

    private var sensitiveAppsCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("敏感应用（永不采集）", systemImage: "exclamationmark.shield")
                    .font(.system(size: 12.5, weight: .semibold))

                Text("每行一个 bundle ID。这些应用在前台时不采集窗口标题、URL 与截屏。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextEditor(text: $draft.sensitiveBundleIdsText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 92)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
            }
        }
    }

    // MARK: 6. Storage Quota Card

    private var storageQuotaCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("存储配额", systemImage: "externaldrive")
                    .font(.system(size: 12.5, weight: .semibold))

                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 12) {
                    GridRow {
                        numericField(
                            title: "最大存储（MB）",
                            text: $draft.maxStorageMBText,
                            hint: "超过上限时自动删除最旧快照。10240 = 10 GB。"
                        )

                        numericField(
                            title: "快照保留天数（天）",
                            text: $draft.retentionDaysText,
                            hint: "超过保留期限的旧快照与数据将自动清理。"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("数据目录")
                        .font(.system(size: 11, weight: .medium))

                    HStack(spacing: 8) {
                        Text(coordinator.storeDirectoryURL.path)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Button("在 Finder 中打开") {
                            coordinator.openConfigDirectory()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                Text("快照随年龄降级重编码（warm ≈1280×720 q40，cold ≈640×360 q30），10 GB 能存数周而非数天的历史。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: 7. Recent Sessions Compact Preview Card

    private var recentSessionsCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("最近会话", systemImage: "clock")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()

                    Button("查看全部 →") {
                        onOpenAllHistory()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DayHelmColors.primaryBlue)

                    Button {
                        coordinator.refreshRecorderSessions()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("刷新最近会话")
                }

                if coordinator.recentSessions.isEmpty {
                    Text("暂无采集会话记录，启用活动记录器后会自动生成。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 14)
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(coordinator.recentSessions.prefix(5))) { session in
                            Button {
                                onOpenSession(session.id)
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(RecorderFormatting.sessionTitle(session))
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)

                                        HStack(spacing: 4) {
                                            Text(RecorderFormatting.relativeTime(ms: session.startedAt))
                                            Text("·")
                                            if session.endedAt == nil {
                                                Text("活跃")
                                                    .foregroundStyle(DayHelmColors.successEmerald)
                                                    .fontWeight(.semibold)
                                            } else {
                                                Text(RecorderFormatting.duration(session))
                                            }
                                            Text("·")
                                            Text("\(session.snapshotCount) 张快照")
                                            Text("·")
                                            Text("\(session.eventCount) 个事件")
                                        }
                                        .font(.system(size: 10, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Save Footer Bar & Reusable Inputs

    private var saveFooterBar: some View {
        HStack(spacing: 10) {
            if hasUnsavedChanges {
                HStack(spacing: 5) {
                    Circle()
                        .fill(DayHelmColors.warningAmber)
                        .frame(width: 6, height: 6)
                    Text("有未保存的文本或数值更改")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if justSavedFeedback {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DayHelmColors.successEmerald)
                    Text("配置已保存并即时生效")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DayHelmColors.successEmerald)
                }
            } else {
                Text("开关即时生效；数值与敏感应用列表可回车或点击保存")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("恢复默认") {
                draft = RecorderDraftSettings(from: .default)
                commitDraft()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

            if hasUnsavedChanges {
                Button("撤销更改") {
                    draft = RecorderDraftSettings(from: coordinator.recorderSettings)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("保存配置") {
                    commitDraft()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DayHelmColors.primaryBlue)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func numericField(
        title: String,
        text: Binding<String>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
                .monospacedDigit()
                .onChange(of: text.wrappedValue) { _, newValue in
                    let digits = newValue.filter(\.isNumber)
                    if digits != newValue {
                        text.wrappedValue = digits
                    }
                }
                .onSubmit {
                    commitDraft()
                }
            Text(hint)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func toggleSettingRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(DayHelmColors.primaryBlue)
        }
    }

    // MARK: 0. Tasks & Quota Management Section

    private var tasksManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            RecorderSectionCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Label("今日事项与配额", systemImage: "list.bullet.rectangle")
                                .font(.system(size: 13.5, weight: .bold))

                            if !coordinator.taskProgressList.isEmpty {
                                Text(tasksSummaryPillText)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.055), in: Capsule())
                            }
                        }

                        Text("管理每日专注事项、保底/上限配额与显示顺序；可选配置关键词、关联应用和域名用于跨应用同任务切换识别。修改立即生效。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        taskEditorMode = .create
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10.5, weight: .bold))
                            Text("新增事项")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(DayHelmColors.primaryBlue)
                }
            }

            RecorderSectionCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("菜单栏显示密度")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(menuBarModeDescription(draft.menuBarDisplayMode))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("菜单栏显示密度", selection: Binding(
                        get: { draft.menuBarDisplayMode },
                        set: { newMode in
                            draft.menuBarDisplayMode = newMode
                            commitDraft()
                        }
                    )) {
                        ForEach(MenuBarDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 210)
                }
            }

            if coordinator.taskProgressList.isEmpty {
                RecorderSectionCard {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 22))
                            .foregroundStyle(.tertiary)
                        Text("尚未配置任何今日事项")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("添加事项后，菜单栏悬浮窗将显示快捷切换按钮与实时配额进度。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button {
                            taskEditorMode = .create
                        } label: {
                            Label("新增第一项事项", systemImage: "plus")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .tint(DayHelmColors.primaryBlue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            } else {
                let items = coordinator.taskProgressList
                VStack(spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, progress in
                        TaskSettingsRowCard(
                            progress: progress,
                            isActive: activeTaskId == progress.budget.taskId,
                            canMoveUp: index > 0,
                            canMoveDown: index < items.count - 1,
                            onMoveUp: {
                                guard index > 0 else { return }
                                coordinator.moveTask(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                            },
                            onMoveDown: {
                                guard index < items.count - 1 else { return }
                                coordinator.moveTask(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                            },
                            onEdit: {
                                taskEditorMode = .edit(progress.budget)
                            },
                            onDelete: {
                                pendingDeleteTask = progress.budget
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: 0.5 Jev Semantic Recognition Section

    private var jevManagementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            jevAutoTrackingCard
            jevDecisionLogsCard
        }
    }

    private var jevAutoTrackingCard: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(DayHelmColors.primaryBlue)
                            Text("智能自动识别（Jev System One）")
                                .font(.system(size: 13.5, weight: .bold))

                            if draft.jevAutoTrackingEnabled {
                                if coordinator.jevAPIKeyConfigured {
                                    Text("已启用")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(DayHelmColors.successEmerald)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DayHelmColors.successEmerald.opacity(0.14), in: Capsule())
                                } else {
                                    Text("待配置 API Key")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundStyle(DayHelmColors.warningAmber)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(DayHelmColors.warningAmber.opacity(0.15), in: Capsule())
                                }
                            }
                        }
                        Text("即使不配置焦点事项，开启后也会自动识别 6 类活动大类（开发构建、内容创作、业务运营等）；配置事项后自动匹配并累计配额，实时展示在顶部菜单栏。")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { draft.jevAutoTrackingEnabled },
                        set: { newVal in
                            draft.jevAutoTrackingEnabled = newVal
                            commitDraft()
                            coordinator.refreshJevAPIKeyStatus()
                            if newVal && !coordinator.jevAPIKeyConfigured {
                                isEditingJevKey = true
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .tint(DayHelmColors.primaryBlue)
                }

                if draft.jevAutoTrackingEnabled {
                    Divider()

                    if !coordinator.jevAPIKeyConfigured || isEditingJevKey {
                        VStack(alignment: .leading, spacing: 8) {
                            if !coordinator.jevAPIKeyConfigured {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DayHelmColors.warningAmber)
                                    Text("已开启 Jev 自动识别，但尚未检测到 API Key。请粘贴你的 JEV_API_KEY（独立保存在本机 ~/.config/alma/dayhelm/jev.key，权限 0600）。")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(DayHelmColors.warningAmber)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 7)
                                .background(DayHelmColors.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }

                            HStack(spacing: 8) {
                                SecureField("粘贴 JEV_API_KEY（来自 typesafe.ai）", text: $jevAPIKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11.5, design: .monospaced))

                                Button("保存 Key") {
                                    let trimmed = jevAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !trimmed.isEmpty else { return }
                                    do {
                                        try coordinator.saveJevAPIKey(trimmed)
                                        jevAPIKeyInput = ""
                                        isEditingJevKey = false
                                        jevTestStatusMessage = "已安全保存至本机 jev.key（0600）"
                                        jevTestStatusIsError = false
                                    } catch {
                                        jevTestStatusMessage = "保存失败：\(error.localizedDescription)"
                                        jevTestStatusIsError = true
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(DayHelmColors.primaryBlue)
                                .disabled(jevAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                Button(isTestingJevConnection ? "测试中…" : "测试连接") {
                                    runJevConnectionTest(keyOverride: jevAPIKeyInput)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isTestingJevConnection || (jevAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !coordinator.jevAPIKeyConfigured))

                                if coordinator.jevAPIKeyConfigured && isEditingJevKey {
                                    Button("取消") {
                                        jevAPIKeyInput = ""
                                        isEditingJevKey = false
                                    }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(DayHelmColors.successEmerald)
                            Text("API Key 已配置（来源：\(coordinator.jevAPIKeySource?.displayName ?? "本机")）")
                                .font(.system(size: 11.5, weight: .medium))

                            Spacer()

                            Button(isTestingJevConnection ? "测试中…" : "测试连接") {
                                runJevConnectionTest(keyOverride: nil)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isTestingJevConnection)

                            Button("更换 Key") {
                                isEditingJevKey = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if coordinator.jevAPIKeySource == .localKeyFile {
                                Button("清除") {
                                    try? coordinator.clearJevAPIKey()
                                    jevTestStatusMessage = "已移除本地 jev.key"
                                    jevTestStatusIsError = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11))
                                .foregroundStyle(DayHelmColors.destructiveRed)
                            }
                        }
                    }

                    if let statusMsg = jevTestStatusMessage {
                        Text(statusMsg)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(jevTestStatusIsError ? DayHelmColors.destructiveRed : DayHelmColors.successEmerald)
                    } else if let lastErr = coordinator.jevLastError, !lastErr.isEmpty {
                        Text("最近一次识别异常：\(lastErr)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(DayHelmColors.warningAmber)
                    }

                    toggleSettingRow(
                        title: "允许发送脱敏后的本机 OCR 正文摘要（≤ 600 字，推荐）",
                        subtitle: "自动剔除菜单栏与浏览器标签栏噪声，提取 Hermes 看板、Discord、飞书、终端等页面正文；发送前自动清洗凭据与敏感参数，命中隐私应用或锁屏时绝不外发，永不上传截图。",
                        isOn: Binding(
                            get: { draft.jevSendOCRSnippet },
                            set: { newVal in
                                draft.jevSendOCRSnippet = newVal
                                commitDraft()
                            }
                        )
                    )
                }
            }
        }
    }

    private var filteredJevDecisionLogs: [JevDecisionLogEntry] {
        switch jevLogFilter {
        case .all:
            return coordinator.jevDecisionLogs
        case .switched:
            return coordinator.jevDecisionLogs.filter { $0.outcome == .committedSwitch || $0.outcome == .manualOverride }
        case .pendingOrIgnored:
            return coordinator.jevDecisionLogs.filter { $0.outcome == .pendingConfirmation || $0.outcome == .ignoredLowConfidence || $0.outcome == .manualPinned }
        case .errors:
            return coordinator.jevDecisionLogs.filter { $0.outcome == .error }
        }
    }

    private var jevDecisionLogsCard: some View {
        let allLogs = coordinator.jevDecisionLogs
        let entries = filteredJevDecisionLogs
        let switchedCount = allLogs.filter { $0.outcome == .committedSwitch }.count
        let latencies = allLogs.compactMap(\.latencyMs)
        let avgLatencyText = latencies.isEmpty ? "—" : "\(latencies.reduce(0, +) / latencies.count)ms"
        let totalTokens = allLogs.compactMap(\.inputTokens).reduce(0, +)
        let tokensText = totalTokens >= 1000
            ? String(format: "%.1fk", Double(totalTokens) / 1000.0)
            : "\(totalTokens)"

        return RecorderSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DayHelmColors.primaryBlue)
                    Text("Jev 判断记录")
                        .font(.system(size: 13, weight: .bold))

                    Text("今日 \(allLogs.count) 条")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.055), in: Capsule())

                    Spacer()

                    Picker("日志过滤", selection: $jevLogFilter) {
                        ForEach(JevLogFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 245)

                    if !allLogs.isEmpty {
                        Button("清空") {
                            coordinator.clearJevDecisionLogs()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if !allLogs.isEmpty {
                    HStack(spacing: 10) {
                        metricPill(
                            icon: "sparkles",
                            title: "今日判定",
                            value: "\(allLogs.count)"
                        )
                        metricPill(
                            icon: "arrow.triangle.swap",
                            title: "自动切换",
                            value: "\(switchedCount)",
                            valueColor: switchedCount > 0 ? DayHelmColors.successEmerald : .primary
                        )
                        metricPill(
                            icon: "timer",
                            title: "平均耗时",
                            value: avgLatencyText
                        )
                        metricPill(
                            icon: "text.word.spacing",
                            title: "输入 Token",
                            value: tokensText
                        )
                    }
                }

                if entries.isEmpty {
                    Text(allLogs.isEmpty
                         ? "暂无判断记录。切换窗口并停留 ≥ 3 秒后，Jev 的每次判定结果、活动大类、置信度与决策原因会实时显示在这里。"
                         : "当前筛选条件下暂无记录。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(entries) { entry in
                            jevDecisionLogRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func jevDecisionLogRow(_ entry: JevDecisionLogEntry) -> some View {
        let outcomeColor: Color = switch entry.outcome {
        case .committedSwitch: DayHelmColors.successEmerald
        case .maintained: .secondary
        case .pendingConfirmation: DayHelmColors.primaryBlue
        case .ignoredLowConfidence: DayHelmColors.warningAmber
        case .manualPinned, .manualOverride: DayHelmColors.violetAccent
        case .error: DayHelmColors.destructiveRed
        }

        let sourceTag: String = switch entry.source {
        case .jev: "Jev"
        case .cache: "防抖提交"
        case .localOverride: "手工"
        case .localRule: "本机规则"
        }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(Self.jevTimeFormatter.string(from: entry.timestamp))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(entry.outcome.displayName)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(outcomeColor)
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(outcomeColor.opacity(0.14), in: Capsule())

                if let mode = entry.activityMode, entry.outcome != .error {
                    Text(mode.displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(hex: mode.colorHex))
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Color(hex: mode.colorHex).opacity(0.14), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                if let focusName = entry.focusProjectDisplayName, !focusName.isEmpty {
                    Text("→ \(focusName)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                } else if entry.activityMode == nil || entry.outcome == .error {
                    Text(entry.predictedDisplayName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                if entry.outcome != .error {
                    Text("置信 \(Int((entry.confidence * 100).rounded()))%")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if let same = entry.sameTaskAsPrevious {
                        Text("· 同任务 \(Int((same * 100).rounded()))%")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if entry.isDistraction >= 0.45 {
                        Text("· 分心 \(Int((entry.isDistraction * 100).rounded()))%")
                            .font(.system(size: 10, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(DayHelmColors.destructiveRed)
                    }
                }

                Spacer(minLength: 4)

                Text(sourceTag)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)

                if let ms = entry.latencyMs {
                    Text("\(ms)ms")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }

                if let tok = entry.inputTokens, tok > 0 {
                    Text("\(tok) tok")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 6) {
                Text(entry.appName)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)

                if entry.redacted {
                    Text("隐私已脱敏（仅传应用名）")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else if let title = entry.windowTitle, !title.isEmpty {
                    Text("· \(title)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if let domain = entry.domain, !domain.isEmpty {
                    Text("· \(domain)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if entry.usedOCRSnippet {
                    Text("OCR")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DayHelmColors.primaryBlue)
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(DayHelmColors.primaryBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        .help(entry.ocrSnippetPreview ?? "本次判断附带了本机脱敏 OCR 摘要")
                }
            }

            if let err = entry.errorMessage, !err.isEmpty {
                Text(err)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(DayHelmColors.destructiveRed)
                    .lineLimit(2)
            } else if let preview = entry.ocrSnippetPreview, !preview.isEmpty {
                Text("OCR: \(preview)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7.5)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private static let jevTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func runJevConnectionTest(keyOverride: String?) {
        isTestingJevConnection = true
        jevTestStatusMessage = nil
        Task {
            let result = await coordinator.testJevConnection(apiKeyOverride: keyOverride)
            await MainActor.run {
                isTestingJevConnection = false
                switch result {
                case .success(let ping):
                    jevTestStatusMessage = "✓ 连接成功 · \(ping.model) · \(ping.latencyMs)ms"
                    jevTestStatusIsError = false
                case .failure(let error):
                    jevTestStatusMessage = "✗ 连接失败：\(error.localizedDescription)"
                    jevTestStatusIsError = true
                }
            }
        }
    }

    private var activeTaskId: String? {
        if case .focusing(let taskId, _) = coordinator.sessionState {
            return taskId
        }
        return nil
    }

    private var tasksSummaryPillText: String {
        let totalFocused = Int(coordinator.taskProgressList.reduce(0.0) { $0 + $1.focusedMinutes }.rounded())
        let targetTasks = coordinator.taskProgressList.filter { $0.budget.targetMinutes != nil }
        if !targetTasks.isEmpty {
            let metCount = targetTasks.filter {
                if case .targetMet = $0.status { return true }
                return false
            }.count
            return "共 \(coordinator.taskProgressList.count) 项 · 已投 \(totalFocused)m · 达标 \(metCount)/\(targetTasks.count)"
        }
        return "共 \(coordinator.taskProgressList.count) 项 · 已投 \(totalFocused)m"
    }

    private func commitDraft() {
        let updated = draft.buildSettings(fallback: coordinator.recorderSettings)
        coordinator.updateRecorderSettings(updated)
        draft = RecorderDraftSettings(from: coordinator.recorderSettings)
        justSavedFeedback = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !hasUnsavedChanges {
                justSavedFeedback = false
            }
        }
    }
}

private struct TaskSettingsRowCard: View {
    let progress: TaskProgress
    let isActive: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var taskColor: Color {
        Color(hex: progress.budget.colorHex)
    }

    private var focusedMinutesInt: Int {
        Int(progress.focusedMinutes.rounded())
    }

    private var progressRatio: Double {
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
        case .underTarget, .noBudget:
            return taskColor
        }
    }

    private var quotaSummaryText: String {
        var parts: [String] = []
        if let target = progress.budget.targetMinutes {
            parts.append("保底 \(target)m")
        }
        if let cap = progress.budget.capMinutes {
            parts.append("上限 \(cap)m")
        }
        if parts.isEmpty {
            parts.append("自由计时")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        RecorderSectionCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .center, spacing: 8) {
                    Circle()
                        .fill(taskColor)
                        .frame(width: 9, height: 9)

                    Text(progress.budget.displayName)
                        .font(.system(size: 13, weight: .semibold))

                    if isActive {
                        Text("专注中")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(taskColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(taskColor.opacity(0.14), in: Capsule())
                    }

                    Text(quotaSummaryText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05), in: Capsule())

                    Spacer()

                    Text("今日已投 \(focusedMinutesInt)m")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveUp)
                        .opacity(canMoveUp ? 1.0 : 0.35)
                        .help("上移")

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canMoveDown)
                        .opacity(canMoveDown ? 1.0 : 0.35)
                        .help("下移")

                        Button(action: onEdit) {
                            HStack(spacing: 3) {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 10, weight: .medium))
                                Text("编辑")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("编辑配额与匹配规则")

                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .font(.system(size: 10.5))
                                .foregroundStyle(DayHelmColors.destructiveRed)
                                .frame(width: 24, height: 24)
                                .background(DayHelmColors.destructiveRed.opacity(0.10), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("删除事项")
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor.opacity(0.12))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor)
                            .frame(width: max(progressRatio > 0 ? 4 : 0, geo.size.width * progressRatio))
                    }
                }
                .frame(height: 5)

                if let desc = progress.budget.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }

                if !progress.budget.keywords.isEmpty || !progress.budget.appBundleIds.isEmpty || !progress.budget.domains.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        if !progress.budget.keywords.isEmpty {
                            ruleMetadataLine(label: "关键词", values: progress.budget.keywords)
                        }
                        if !progress.budget.appBundleIds.isEmpty {
                            ruleMetadataLine(label: "应用", values: progress.budget.appBundleIds)
                        }
                        if !progress.budget.domains.isEmpty {
                            ruleMetadataLine(label: "域名", values: progress.budget.domains)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func ruleMetadataLine(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)

            Text(values.joined(separator: ", "))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct TaskBudgetEditorSheet: View {
    let mode: TaskEditorSheetMode
    let suggestedColorHex: String
    let onSave: (String, String?, String?, String, Int?, Int?, [String], [String], [String]) -> Void
    let onDelete: (TaskBudget) -> Void
    let onCancel: () -> Void

    @State private var displayName: String = ""
    @State private var shortName: String = ""
    @State private var descriptionText: String = ""
    @State private var selectedColorHex: String = "#3B82F6"
    @State private var keywordsText: String = ""
    @State private var appBundleIdsText: String = ""
    @State private var domainsText: String = ""
    @State private var showAdvancedRules: Bool = false
    @State private var hasTarget: Bool = true
    @State private var targetMinutes: Int = 60
    @State private var hasCap: Bool = false
    @State private var capMinutes: Int = 90

    private var isEditMode: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(isEditMode ? "编辑事项与配额" : "新增今日事项")
                    .font(.system(size: 14.5, weight: .bold))
                Spacer()
                Button("关闭") {
                    onCancel()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("事项名称")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("例如：电商做深 / 深度写作", text: $displayName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5))

                TextField("菜单栏短名（可选，如：电商，留空自动截断）", text: $shortName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("一句话说明（推荐，供 Jev 自动识别归属）")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：选品、商品开发、主图与详情页设计、营销转化优化", text: $descriptionText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                }
                .padding(.top, 2)

                HStack(spacing: 10) {
                    Text("标识颜色")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach(DayHelmColors.taskPalette, id: \.hex) { item in
                        let isSelected = selectedColorHex.caseInsensitiveCompare(item.hex) == .orderedSame
                        Button {
                            selectedColorHex = item.hex
                        } label: {
                            Circle()
                                .fill(Color(hex: item.hex))
                                .frame(width: 18, height: 18)
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

            HStack(spacing: 10) {
                QuotaDurationEditor(
                    title: "保底目标 (Target)",
                    accentColor: DayHelmColors.primaryBlue,
                    isEnabled: $hasTarget,
                    minutes: $targetMinutes
                )

                QuotaDurationEditor(
                    title: "封顶上限 (Cap)",
                    accentColor: DayHelmColors.warningAmber,
                    isEnabled: $hasCap,
                    minutes: $capMinutes
                )
            }

            DisclosureGroup("高级：离线关键词 / 应用 / 域名规则（可选）", isExpanded: $showAdvancedRules) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("匹配关键词（窗口标题 / URL / 实体）")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        TextField("如：抖店, 1688, 主图", text: $keywordsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("关联应用 Bundle ID")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        TextField("如：com.apple.dt.Xcode, com.todesktop.230313mzl4w4u92", text: $appBundleIdsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("关联域名 / Host")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        TextField("如：github.com, jinritemai.com", text: $domainsText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5, design: .monospaced))
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 10) {
                if case .edit(let existing) = mode {
                    Button(role: .destructive) {
                        onDelete(existing)
                    } label: {
                        Text("删除该事项")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(DayHelmColors.destructiveRed)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button("取消") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("保存") {
                    let trimmedShort = shortName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmedDesc = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(
                        trimmedName,
                        trimmedShort.isEmpty ? nil : trimmedShort,
                        trimmedDesc.isEmpty ? nil : trimmedDesc,
                        selectedColorHex,
                        hasTarget ? targetMinutes : nil,
                        hasCap ? capMinutes : nil,
                        parseCommaSeparated(keywordsText),
                        parseCommaSeparated(appBundleIdsText),
                        parseCommaSeparated(domainsText)
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DayHelmColors.primaryBlue)
                .disabled(trimmedName.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 500)
        .onAppear {
            switch mode {
            case .create:
                displayName = ""
                shortName = ""
                descriptionText = ""
                selectedColorHex = suggestedColorHex
                keywordsText = ""
                appBundleIdsText = ""
                domainsText = ""
                showAdvancedRules = false
                hasTarget = true
                targetMinutes = 60
                hasCap = false
                capMinutes = 90
            case .edit(let budget):
                displayName = budget.displayName
                shortName = budget.shortName ?? ""
                descriptionText = budget.description ?? ""
                selectedColorHex = budget.colorHex
                keywordsText = budget.keywords.joined(separator: ", ")
                appBundleIdsText = budget.appBundleIds.joined(separator: ", ")
                domainsText = budget.domains.joined(separator: ", ")
                showAdvancedRules = false
                hasTarget = budget.targetMinutes != nil
                targetMinutes = budget.targetMinutes ?? 60
                hasCap = budget.capMinutes != nil
                capMinutes = budget.capMinutes ?? 90
            }
        }
    }

    private func parseCommaSeparated(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "，", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
                            .frame(width: 54)
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
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
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

private struct RecorderSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
    }
}

// MARK: - History Tab

private enum SessionDetailSubTab: String, CaseIterable, Hashable {
    case events = "事件时间线"
    case snapshots = "快照与 OCR"
}

private struct ActivityRecorderHistoryTab: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    let showSidebar: Bool
    @Binding var selectedSessionId: String?
    @Binding var searchQuery: String
    @Binding var selectedDetail: RecordedSessionDetail?

    @State private var detailSubTab: SessionDetailSubTab = .events
    @State private var previewSnapshot: (snapshot: RecordedSnapshot, ocr: RecordedOCRFrame?)?

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                sessionListPane
                    .frame(width: 295)
                Divider()
            }
            sessionDetailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: Binding(
            get: { previewSnapshot != nil },
            set: { if !$0 { previewSnapshot = nil } }
        )) {
            if let preview = previewSnapshot {
                SnapshotPreviewSheet(
                    snapshot: preview.snapshot,
                    ocrFrame: preview.ocr,
                    onClose: { previewSnapshot = nil }
                )
            }
        }
    }

    // MARK: Left Session List

    private var sessionListPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    TextField("搜索标题、应用、URL 或 OCR...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .padding(10)
            .onChange(of: searchQuery) { _, newValue in
                coordinator.refreshRecorderSessions(searchQuery: newValue)
            }

            Divider()

            if coordinator.recentSessions.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 20))
                        .foregroundStyle(.tertiary)
                    Text(searchQuery.isEmpty ? "暂无历史会话" : "没有匹配的会话")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(coordinator.recentSessions) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func sessionRow(_ session: RecordedSessionSummary) -> some View {
        let isSelected = selectedSessionId == session.id
        let taskBudget = session.declaredTaskId.flatMap { taskId in
            coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId })?.budget
        }

        return Button {
            selectedSessionId = session.id
            selectedDetail = coordinator.loadSessionDetail(sessionId: session.id)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(RecorderFormatting.sessionTitle(session))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if session.endedAt == nil {
                        Text("活跃")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(DayHelmColors.successEmerald)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(DayHelmColors.successEmerald.opacity(0.14), in: Capsule())
                    }
                }

                if let taskBudget {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(hex: taskBudget.colorHex))
                            .frame(width: 5.5, height: 5.5)
                        Text(taskBudget.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 4) {
                    Text(RecorderFormatting.relativeTime(ms: session.startedAt))
                    Text("·")
                    Text(RecorderFormatting.duration(session))
                    Text("·")
                    Text("\(session.snapshotCount) 快照")
                    Text("·")
                    Text("\(session.eventCount) 事件")
                }
                .font(.system(size: 10, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? DayHelmColors.primaryBlue.opacity(0.12) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? DayHelmColors.primaryBlue.opacity(0.55) : Color.primary.opacity(0.06),
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Right Session Detail

    @ViewBuilder
    private var sessionDetailPane: some View {
        if let detail = selectedDetail {
            VStack(spacing: 0) {
                sessionDetailHeader(detail)
                Divider()

                Group {
                    switch detailSubTab {
                    case .events:
                        eventsTimelineView(detail.events)
                    case .snapshots:
                        snapshotsAndOCRView(snapshots: detail.snapshots, ocrFrames: detail.ocrFrames)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                Text("选择左侧采集会话，查看事件时间线、屏幕快照与 OCR 文本")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sessionDetailHeader(_ detail: RecordedSessionDetail) -> some View {
        let session = detail.session
        let taskBudget = session.declaredTaskId.flatMap { taskId in
            coordinator.taskProgressList.first(where: { $0.budget.taskId == taskId })?.budget
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(RecorderFormatting.sessionTitle(session))
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(2)

                        if session.endedAt == nil {
                            Text("活跃中")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(DayHelmColors.successEmerald)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DayHelmColors.successEmerald.opacity(0.14), in: Capsule())
                        }

                        if let taskBudget {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color(hex: taskBudget.colorHex))
                                    .frame(width: 6, height: 6)
                                Text(taskBudget.displayName)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: taskBudget.colorHex).opacity(0.14), in: Capsule())
                        }
                    }

                    if let desc = session.analysisDescription, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Picker("", selection: $detailSubTab) {
                    Text("事件时间线 (\(detail.events.count))").tag(SessionDetailSubTab.events)
                    Text("快照与 OCR (\(detail.snapshots.count))").tag(SessionDetailSubTab.snapshots)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }

            HStack(spacing: 12) {
                Label(RecorderFormatting.timeRange(startMs: session.startedAt, endMs: session.endedAt), systemImage: "calendar.badge.clock")
                Text("时长 \(RecorderFormatting.duration(session))")
                Text("点击 \(session.clickCount) · 按键 \(session.keypressCount) (\(String(format: "%.1f", session.inputEventsPerMinute))/m)")
                Text("\(RecorderFormatting.bytes(session.totalBytes)) · \(session.storageTier)")
            }
            .font(.system(size: 10.5, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(.secondary)

            if !session.appNames.isEmpty || !session.topics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(session.appNames, id: \.self) { app in
                            tagChip(app, tint: DayHelmColors.primaryBlue)
                        }
                        ForEach(session.topics, id: \.self) { topic in
                            tagChip("#\(topic)", tint: DayHelmColors.violetAccent)
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.02))
    }

    private func tagChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(tint.opacity(0.10), in: Capsule())
    }

    // MARK: Events Timeline

    private func eventsTimelineView(_ events: [RecordedActivityEvent]) -> some View {
        Group {
            if events.isEmpty {
                Text("该会话暂无记录事件")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(events) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Text(RecorderFormatting.clockTime(ms: event.timestamp))
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 60, alignment: .leading)

                                eventKindBadge(event.kind)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        if let app = event.appName, !app.isEmpty {
                                            Text(app)
                                                .font(.system(size: 11.5, weight: .semibold))
                                        }
                                        if let count = event.data["count"], !count.isEmpty {
                                            Text("×\(count)")
                                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                                .monospacedDigit()
                                                .foregroundStyle(DayHelmColors.primaryBlue)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(DayHelmColors.primaryBlue.opacity(0.10), in: Capsule())
                                        }
                                    }

                                    if let title = event.windowTitle, !title.isEmpty {
                                        Text(title)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary.opacity(0.88))
                                            .textSelection(.enabled)
                                    }

                                    if let urlStr = event.url, !urlStr.isEmpty {
                                        Text(urlStr)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(DayHelmColors.primaryBlue)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .textSelection(.enabled)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func eventKindBadge(_ kind: String) -> some View {
        let color: Color = {
            switch kind {
            case "app_focus": return DayHelmColors.primaryBlue
            case "browser_visit": return DayHelmColors.successEmerald
            case "click", "keypress": return DayHelmColors.violetAccent
            case "typing_pause": return DayHelmColors.warningAmber
            default: return .secondary
            }
        }()

        return Text(kind)
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .frame(width: 92, alignment: .leading)
    }

    // MARK: Snapshots & OCR

    private func snapshotsAndOCRView(
        snapshots: [RecordedSnapshot],
        ocrFrames: [RecordedOCRFrame]
    ) -> some View {
        let ocrBySnapshot = Dictionary(
            ocrFrames.map { ($0.snapshotId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return Group {
            if snapshots.isEmpty && ocrFrames.isEmpty {
                Text("该会话暂无屏幕快照或 OCR 文本")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(snapshots) { snapshot in
                            let ocr = ocrBySnapshot[snapshot.id]
                            snapshotRowCard(snapshot: snapshot, ocr: ocr)
                        }

                        let orphanOCR = ocrFrames.filter { frame in
                            !snapshots.contains(where: { $0.id == frame.snapshotId })
                        }
                        ForEach(orphanOCR) { frame in
                            RecorderSectionCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("OCR 文本 · \(RecorderFormatting.clockTime(ms: frame.createdAt))")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        Spacer()
                                        Text("\(frame.charCount) 字")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(frame.text)
                                        .font(.system(size: 11, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func snapshotRowCard(snapshot: RecordedSnapshot, ocr: RecordedOCRFrame?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                previewSnapshot = (snapshot, ocr)
            } label: {
                SnapshotThumbnailView(
                    filePath: snapshot.filePath,
                    storageTier: snapshot.storageTier,
                    resolutionText: "\(snapshot.width)×\(snapshot.height)"
                )
            }
            .buttonStyle(.plain)
            .help("点击查看大图与完整 OCR 文本")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(RecorderFormatting.clockTime(ms: snapshot.timestamp))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .monospacedDigit()

                    Text(snapshot.trigger)
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DayHelmColors.primaryBlue)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(DayHelmColors.primaryBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                    Text(snapshot.storageTier)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))

                    Spacer()

                    Text("\(snapshot.width)×\(snapshot.height) · \(RecorderFormatting.bytes(snapshot.sizeBytes))")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if let app = snapshot.appName, !app.isEmpty {
                    Text([app, snapshot.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }

                if let ocr, !ocr.text.isEmpty {
                    Text(ocr.text)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(7)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Text("无 OCR 文本")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

private struct SnapshotThumbnailView: View {
    let filePath: String
    let storageTier: String
    let resolutionText: String

    @State private var image: NSImage?
    @State private var didAttemptLoad: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 184, height: 112)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            } else {
                VStack(spacing: 4) {
                    Image(systemName: storageTier == "pruned" ? "scissors" : "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                    Text(storageTier == "pruned" ? "已清理 (pruned)" : (didAttemptLoad ? "文件不可用" : "加载中..."))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                    if !resolutionText.isEmpty && resolutionText != "0×0" {
                        Text(resolutionText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
        }
        .frame(width: 184, height: 112)
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .task(id: filePath) {
            image = nil
            didAttemptLoad = false
            guard storageTier != "pruned" else {
                didAttemptLoad = true
                return
            }
            let path = filePath
            let cgImage = await Task.detached(priority: .utility) {
                ScreenSnapshotCapturer.decodeThumbnailCGImage(at: URL(fileURLWithPath: path), maxPixelSize: 368)
            }.value
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            didAttemptLoad = true
        }
    }
}

private struct SnapshotPreviewSheet: View {
    let snapshot: RecordedSnapshot
    let ocrFrame: RecordedOCRFrame?
    let onClose: () -> Void

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text([snapshot.appName, snapshot.windowTitle].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " — "))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("\(RecorderFormatting.clockTime(ms: snapshot.timestamp)) · \(snapshot.width)×\(snapshot.height) · \(RecorderFormatting.bytes(snapshot.sizeBytes)) · \(snapshot.storageTier)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if FileManager.default.fileExists(atPath: snapshot.filePath) {
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: snapshot.filePath)])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button("关闭") {
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 740, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
                    )
            } else {
                Text(snapshot.storageTier == "pruned" ? "该快照已按保留策略清理，仅保留 OCR 与元数据。" : "快照文件不存在或无法读取：\(snapshot.filePath)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }

            if let ocrFrame, !ocrFrame.text.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vision OCR 文本（\(ocrFrame.charCount) 字）")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(ocrFrame.text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 120)
                    .padding(8)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .padding(16)
        .frame(width: 780)
        .task(id: snapshot.filePath) {
            guard snapshot.storageTier != "pruned" else { return }
            let path = snapshot.filePath
            let cgImage = await Task.detached(priority: .utility) {
                ScreenSnapshotCapturer.decodeThumbnailCGImage(at: URL(fileURLWithPath: path), maxPixelSize: 1600)
            }.value
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
        }
    }
}

// MARK: - Formatting Helpers

@MainActor
private enum RecorderFormatting {
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df
    }()

    static func sessionTitle(_ session: RecordedSessionSummary) -> String {
        if let title = session.analysisTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        if !session.appNames.isEmpty {
            return session.appNames.joined(separator: ", ")
        }
        return "未命名会话"
    }

    static func bytes(_ count: Int64) -> String {
        if count <= 0 { return "0 B" }
        let kb = 1024.0
        let mb = kb * 1024.0
        let gb = mb * 1024.0
        let value = Double(count)
        if value >= gb {
            return String(format: "%.2f GB", value / gb)
        }
        if value >= mb {
            return String(format: "%.1f MB", value / mb)
        }
        if value >= kb {
            return String(format: "%.0f KB", value / kb)
        }
        return "\(count) B"
    }

    static func relativeTime(ms: Int64) -> String {
        let deltaSec = max(0, Date().timeIntervalSince1970 - Double(ms) / 1000.0)
        if deltaSec < 60 { return "刚刚" }
        let mins = Int(deltaSec / 60)
        if mins < 60 { return "\(mins) 分钟前" }
        let hours = mins / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        return "\(days) 天前"
    }

    static func duration(_ session: RecordedSessionSummary) -> String {
        let ms: Int64
        if let explicit = session.durationMs {
            ms = explicit
        } else if let end = session.endedAt {
            ms = max(0, end - session.startedAt)
        } else {
            ms = max(0, Int64(Date().timeIntervalSince1970 * 1000) - session.startedAt)
        }
        let mins = max(0, Int((Double(ms) / 60_000.0).rounded()))
        if mins < 60 { return "\(mins)m" }
        let h = mins / 60
        let m = mins % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func clockTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        return timeFormatter.string(from: date)
    }

    static func timeRange(startMs: Int64, endMs: Int64?) -> String {
        let start = Date(timeIntervalSince1970: Double(startMs) / 1000.0)
        let startStr = dateTimeFormatter.string(from: start)
        if let endMs {
            let end = Date(timeIntervalSince1970: Double(endMs) / 1000.0)
            return "\(startStr) – \(timeFormatter.string(from: end))"
        }
        return "\(startStr) – 进行中"
    }
}
