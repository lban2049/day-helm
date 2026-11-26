import AppKit
import DayHelmCapture
import DayHelmCore
import SwiftUI

struct DailyStatsView: View {
    @ObservedObject var coordinator: HybridActivityCoordinator
    let refreshNonce: Int

    private enum TopRankingTab: String, CaseIterable {
        case apps = "Top 应用"
        case sites = "Top 站点"
    }

    @State private var selectedDate: String = ""
    @State private var availableDates: [String] = []
    @State private var report: DailyStatsReport?
    @State private var isLoadingReport: Bool = false
    @State private var loadTask: Task<Void, Never>?
    @State private var rankingTab: TopRankingTab = .apps
    @State private var promptPreset: AgentAnalysisPromptPreset = .dailyReview
    @State private var isPromptExpanded: Bool = false
    @State private var copiedFeedback: Bool = false
    @State private var hoveredHour: Int?
    @State private var hoveredSegmentId: String?

    var body: some View {
        VStack(spacing: 0) {
            dateNavigationBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let report {
                        if !report.hasData {
                            emptyStateCard(date: report.date)
                        } else {
                            coreTelemetryGrid(report: report)
                            spectrumSectionCard(report: report)
                            allocationDualCards(report: report)
                            hourlyRhythmCard(report: report)
                            habitsDualCards(report: report)
                        }
                        agentPromptCard(report: report)
                    } else if isLoadingReport || coordinator.isMaterializingHistoricalStats {
                        generatingPlaceholderCard
                    } else if availableDates.isEmpty {
                        noHistoryYetCard
                    } else {
                        generatingPlaceholderCard
                    }
                }
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .onAppear {
            loadDatesAndReport(resetToLatestIfNeeded: true)
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .onChange(of: refreshNonce) { _, _ in
            loadDatesAndReport(resetToLatestIfNeeded: false)
        }
        .onChange(of: coordinator.historicalStatsRevision) { _, _ in
            loadDatesAndReport(resetToLatestIfNeeded: selectedDate.isEmpty)
        }
        .onChange(of: selectedDate) { _, newDate in
            guard !newDate.isEmpty else {
                report = nil
                return
            }
            hoveredHour = nil
            hoveredSegmentId = nil
            loadReport(for: newDate, forceRebuild: false)
        }
    }

    // MARK: - 1. Date Navigation Bar

    private var dateNavigationBar: some View {
        let latestHistorical = availableDates.first
        let yesterdayString = yesterdayDateString

        return HStack(spacing: 10) {
            // Compact date stepper cluster — locked to single-line intrinsic width
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    Button {
                        stepDate(older: true)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStepOlder)
                    .opacity(canStepOlder ? 1.0 : 0.35)
                    .help("前一天")

                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(width: 1, height: 14)

                    Menu {
                        ForEach(availableDates, id: \.self) { date in
                            Button {
                                selectedDate = date
                            } label: {
                                HStack {
                                    Text(date == yesterdayString ? "\(date)（昨天）" : date)
                                    if date == selectedDate {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(DayHelmColors.primaryBlue)
                            Text(selectedDate.isEmpty ? "暂无历史报表" : selectedDate)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .lineLimit(1)
                            if !selectedDate.isEmpty && selectedDate == yesterdayString {
                                Text("昨天")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(DayHelmColors.primaryBlue)
                                    .lineLimit(1)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(DayHelmColors.primaryBlue.opacity(0.14), in: Capsule())
                            }
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(availableDates.isEmpty)

                    Rectangle()
                        .fill(Color.primary.opacity(0.09))
                        .frame(width: 1, height: 14)

                    Button {
                        stepDate(older: false)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10.5, weight: .semibold))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canStepNewer)
                    .opacity(canStepNewer ? 1.0 : 0.35)
                    .help("后一天")
                }
                .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
                )

                if let latestHistorical, !selectedDate.isEmpty, selectedDate != latestHistorical {
                    Button {
                        selectedDate = latestHistorical
                    } label: {
                        Text("最新")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DayHelmColors.primaryBlue)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(DayHelmColors.primaryBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("跳转到最新历史日期（\(latestHistorical)）")
                }

                if !selectedDate.isEmpty && !coordinator.isSyntheticDemo {
                    Button {
                        loadReport(for: selectedDate, forceRebuild: true)
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoadingReport)
                    .opacity(isLoadingReport ? 0.45 : 1.0)
                    .help("在后台重新计算并更新 \(selectedDate) 的持久化统计报表")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)

            if coordinator.isMaterializingHistoricalStats || isLoadingReport {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(coordinator.isMaterializingHistoricalStats ? "后台预计算中…" : "读取中…")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Color.primary.opacity(0.045), in: Capsule())
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(0)
            } else if let report, let first = report.firstActiveAt, let last = report.lastActiveAt {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("\(formatHHMM(first)) – \(formatHHMM(last)) · 跨度 \(formatDuration(minutes: report.spanMinutes))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .layoutPriority(0)
            }

            Spacer(minLength: 4)

            Button {
                if let report {
                    copyPromptToClipboard(report: report)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: copiedFeedback ? "checkmark.circle.fill" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                    Text(copiedFeedback ? "已复制提示词 ✓" : "复制 Agent 提示词")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(
                    copiedFeedback ? DayHelmColors.successEmerald : DayHelmColors.primaryBlue,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(2)
            .disabled(report == nil)
            .help("复制「\(promptPreset.title)」提示词到剪贴板，粘贴给本地 Claude Code / Codex / Hermes")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 2. Core Telemetry 4-Grid

    private func coreTelemetryGrid(report: DailyStatsReport) -> some View {
        let c = report.core
        let b = report.baseline7d
        let focusPct = c.sustainedFocusShare * 100.0
        let focusColor: Color = {
            if c.sustainedFocusShare >= 0.50 { return DayHelmColors.successEmerald }
            if c.sustainedFocusShare >= 0.30 { return DayHelmColors.primaryBlue }
            return DayHelmColors.warningAmber
        }()

        return HStack(alignment: .top, spacing: 10) {
            telemetryCard(
                icon: "clock.fill",
                iconColor: DayHelmColors.primaryBlue,
                title: "总活跃时长",
                primaryValue: formatDuration(minutes: c.activeMinutes),
                deltaText: b.flatMap { formatDelta(current: c.activeMinutes, baseline: $0.avgActiveMinutes, unit: "m", sampleDays: $0.sampleDays) },
                deltaPositiveIsGood: true,
                subtitle: spanSummaryText(report),
                helpText: "当日有效工作与活跃切换累计总时长（不含锁屏与空闲离开）。"
            )

            telemetryCard(
                icon: "target",
                iconColor: focusColor,
                title: "持续专注占比",
                primaryValue: String(format: "%.0f%%", focusPct),
                primaryColor: focusColor,
                deltaText: b.flatMap {
                    formatDelta(
                        current: focusPct,
                        baseline: $0.avgSustainedFocusShare * 100.0,
                        unit: "pp",
                        decimals: 0,
                        sampleDays: $0.sampleDays
                    )
                },
                deltaPositiveIsGood: true,
                subtitle: String(
                    format: "典型连续块 %.1fm\n最长 %.0fm · ≥12m %d 个",
                    c.weightedMedianBlockMinutes,
                    c.longestBlockMinutes,
                    c.solidBlocksCount
                ),
                helpText: "持续专注占比 = 连续 ≥3m 工作块累计时长 ÷ 总活跃时长（排除乱切与休息）；典型连续块为时长加权中位数（P50），表示有一半活跃工作时间处于 ≥ 该长度的连续块中，不会被大量瞬时切窗拉低至 0.1m。"
            )

            telemetryCard(
                icon: "arrow.triangle.branch",
                iconColor: c.thrashingSegmentCount > 0 ? DayHelmColors.destructiveRed : DayHelmColors.warningAmber,
                title: "跨任务切换与乱切",
                primaryValue: "\(c.crossTaskSwitchCount) 次",
                primaryColor: c.thrashingSegmentCount > 0 ? DayHelmColors.destructiveRed : .primary,
                deltaText: b.flatMap { formatDelta(current: c.switchesPerHour, baseline: $0.avgSwitchesPerHour, unit: "/h", decimals: 1, sampleDays: $0.sampleDays) },
                deltaPositiveIsGood: false,
                subtitle: String(format: "切换热度 %.1f/h\n乱切 %.0fm（%d 段）", c.switchesPerHour, c.thrashingMinutes, c.thrashingSegmentCount),
                helpText: "跨任务切换统计不同语义任务/站点间的有效切换次数（过滤同一任务内多应用协同与瞬时路过）；乱切指 10 分钟内 ≥10 次跨上下文切换且平均停留 <45s 的碎片时段。"
            )

            telemetryCard(
                icon: "keyboard",
                iconColor: DayHelmColors.violetAccent,
                title: "输入密度与采集",
                primaryValue: String(format: "%.1f/min", c.inputEventsPerMinute),
                deltaText: nil,
                deltaPositiveIsGood: true,
                subtitle: "点击 \(c.clickCount) · 敲击 \(c.keypressCount)\n会话 \(c.sessionCount)\(c.meetingCount > 0 ? "(会\(c.meetingCount))" : "") · OCR \(c.ocrFrameCount)",
                helpText: "仅记录键鼠计次频率与会话/屏幕 OCR 采集数量，不读取具体按键内容。"
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func telemetryCard(
        icon: String,
        iconColor: Color,
        title: String,
        primaryValue: String,
        primaryColor: Color = .primary,
        deltaText: (text: String, isHigher: Bool)?,
        deltaPositiveIsGood: Bool,
        subtitle: String,
        helpText: String
    ) -> some View {
        StatsSectionCard(fillHeight: true) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 16)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(primaryValue)
                        .font(.system(size: 19.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(primaryColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: true, vertical: false)

                    if let deltaText {
                        let isGood = deltaPositiveIsGood ? deltaText.isHigher : !deltaText.isHigher
                        Text(deltaText.text)
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(isGood ? DayHelmColors.successEmerald : DayHelmColors.warningAmber)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background((isGood ? DayHelmColors.successEmerald : DayHelmColors.warningAmber).opacity(0.12), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 26, alignment: .leading)

                Text(subtitle)
                    .font(.system(size: 10, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
        .help(helpText)
    }

    // MARK: - 3. Magnified Day Spectrum Ribbon

    private func spectrumSectionCard(report: DailyStatsReport) -> some View {
        let segments = report.spectrumSegments
        let totalMins = max(1.0, segments.reduce(0.0) { $0 + max(0.0, $1.durationMinutes) })

        return StatsSectionCard {
            VStack(alignment: .leading, spacing: 9) {
                statsCardHeader(
                    icon: "waveform.path",
                    iconColor: DayHelmColors.primaryBlue,
                    title: "日时间光谱"
                ) {
                    if let hoveredId = hoveredSegmentId,
                       let seg = segments.first(where: { $0.id == hoveredId }) {
                        Text(segmentSummaryLabel(seg))
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    } else if let first = segments.first, let last = segments.last {
                        Text("\(formatHHMM(first.startedAt)) – \(formatHHMM(last.endedAt)) · \(segments.count) 段（悬停查看分段详情）")
                            .font(.system(size: 10.5, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if segments.isEmpty {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.secondary.opacity(0.14))
                        .frame(height: 28)
                        .overlay(
                            Text("暂无光谱分段数据")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        )
                } else {
                    GeometryReader { geo in
                        let width = max(1.0, geo.size.width)
                        Canvas { context, size in
                            let totalWidth = max(1.0, size.width)
                            let gap: CGFloat = 1.0
                            var x: CGFloat = 0.0

                            for segment in segments {
                                let fraction = max(0.0, segment.durationMinutes) / totalMins
                                let segWidth = max(2.0, totalWidth * fraction - gap)
                                let rect = CGRect(x: x, y: 0, width: segWidth, height: size.height)

                                switch segment.kind {
                                case .task(_, _, let colorHex):
                                    context.fill(Path(rect), with: .color(Color(hex: colorHex)))
                                case .activityMode(let rawValue):
                                    let hex = ActivityMode(rawValue: rawValue)?.colorHex ?? "#64748B"
                                    context.fill(Path(rect), with: .color(Color(hex: hex)))
                                case .thrashing:
                                    context.fill(Path(rect), with: .color(DayHelmColors.destructiveRed.opacity(0.28)))
                                    context.drawLayer { layerCtx in
                                        layerCtx.clip(to: Path(rect))
                                        var hatch = Path()
                                        var hx = rect.minX - rect.height
                                        while hx < rect.maxX + rect.height {
                                            hatch.move(to: CGPoint(x: hx, y: rect.maxY))
                                            hatch.addLine(to: CGPoint(x: hx + rect.height, y: rect.minY))
                                            hx += 6.0
                                        }
                                        layerCtx.stroke(hatch, with: .color(DayHelmColors.destructiveRed.opacity(0.88)), lineWidth: 1.5)
                                    }
                                case .idle:
                                    context.fill(Path(rect), with: .color(Color.secondary.opacity(0.22)))
                                case .unassigned:
                                    context.fill(Path(rect), with: .color(Color.secondary.opacity(0.45)))
                                }

                                if hoveredSegmentId == segment.id {
                                    context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                                }
                                x += segWidth + gap
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoveredSegmentId = segmentId(atX: location.x, totalWidth: width, segments: segments, totalMinutes: totalMins)
                            case .ended:
                                hoveredSegmentId = nil
                            }
                        }
                    }
                    .frame(height: 28)

                    spectrumLegendRow(segments: segments)
                }
            }
        }
    }

    private func segmentId(atX targetX: CGFloat, totalWidth: CGFloat, segments: [SpectrumSegment], totalMinutes: Double) -> String? {
        let gap: CGFloat = 1.0
        var x: CGFloat = 0.0
        for seg in segments {
            let fraction = max(0.0, seg.durationMinutes) / totalMinutes
            let segWidth = max(2.0, totalWidth * fraction - gap)
            if targetX >= x && targetX <= x + segWidth + gap {
                return seg.id
            }
            x += segWidth + gap
        }
        return nil
    }

    private func spectrumLegendRow(segments: [SpectrumSegment]) -> some View {
        var taskItems: [(id: String, name: String, hex: String)] = []
        var seenTasks = Set<String>()
        var modeItems: Set<ActivityMode> = []
        var hasUnassigned = false

        for seg in segments {
            switch seg.kind {
            case .task(let taskId, let displayName, let colorHex):
                if seenTasks.insert(taskId).inserted {
                    taskItems.append((taskId, displayName, colorHex))
                }
            case .activityMode(let raw):
                if let mode = ActivityMode(rawValue: raw) {
                    modeItems.insert(mode)
                }
            case .unassigned:
                hasUnassigned = true
            case .thrashing, .idle:
                break
            }
        }

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(taskItems, id: \.id) { item in
                    legendDot(color: Color(hex: item.hex), label: item.name)
                }
                ForEach(ActivityMode.allCases.filter { modeItems.contains($0) }, id: \.rawValue) { mode in
                    legendDot(color: Color(hex: mode.colorHex), label: mode.compactLabel)
                }
                if hasUnassigned {
                    legendDot(color: Color.secondary.opacity(0.45), label: "未指定")
                }
                HStack(spacing: 4) {
                    ThrashingHatchView()
                        .frame(width: 9, height: 9)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("高频乱切")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                legendDot(color: Color.secondary.opacity(0.28), label: "空闲")
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6.5, height: 6.5)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - 4. Time Allocation Dual Cards (Equal Height)

    private func allocationDualCards(report: DailyStatsReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Left: Task Budgets + 6 Activity Modes
            StatsSectionCard(fillHeight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    statsCardHeader(
                        icon: "chart.pie.fill",
                        iconColor: DayHelmColors.primaryBlue,
                        title: report.budgets.isEmpty ? "6 大活动大类" : "事项配额与活动大类"
                    ) {
                        if report.budgets.isEmpty {
                            Text("时长 · 占比")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if !report.budgets.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("事项配额进度")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            ForEach(report.budgets, id: \.taskId) { budget in
                                budgetProgressRow(budget: budget)
                            }
                        }

                        Divider()

                        Text("6 大活动大类")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    let hasModeTime = report.activityModes.contains { $0.minutes >= 0.05 }
                    if !hasModeTime {
                        Text("当天未记录 Jev 活动大类分布（仅手动事项或未启用自动识别）")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 7) {
                            ForEach(report.activityModes.sorted { $0.minutes > $1.minutes }) { item in
                                distributionBarRow(
                                    label: item.displayName,
                                    color: Color(hex: item.colorHex),
                                    minutes: item.minutes,
                                    share: item.share,
                                    trailingNote: nil
                                )
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            // Right: Top Apps / Top Sites
            StatsSectionCard(fillHeight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    statsCardHeader(
                        icon: rankingTab == .apps ? "macwindow" : "globe",
                        iconColor: DayHelmColors.successEmerald,
                        title: rankingTab.rawValue
                    ) {
                        HStack(spacing: 2) {
                            ForEach(TopRankingTab.allCases, id: \.self) { tab in
                                let active = rankingTab == tab
                                Button {
                                    rankingTab = tab
                                } label: {
                                    Text(tab == .apps ? "应用" : "浏览器站点")
                                        .font(.system(size: 10, weight: active ? .semibold : .medium))
                                        .foregroundStyle(active ? .primary : .secondary)
                                        .lineLimit(1)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3.5)
                                        .background(
                                            active ? Color.primary.opacity(0.09) : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        )
                                }
                                .buttonStyle(.plain)
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                        .padding(2)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    if rankingTab == .apps {
                        if report.topApps.isEmpty {
                            Text("当日暂无应用使用记录")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            VStack(spacing: 7) {
                                ForEach(report.topApps.prefix(8)) { app in
                                    distributionBarRow(
                                        label: app.appName,
                                        color: DayHelmColors.primaryBlue,
                                        minutes: app.minutes,
                                        share: app.share,
                                        trailingNote: app.spanCount > 0 ? "\(app.spanCount)段" : nil
                                    )
                                }
                            }
                        }
                    } else {
                        if report.topSites.isEmpty {
                            Text("当日暂无浏览器 HTTP(S) 站点访问记录（已脱敏页面不入榜）")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            VStack(spacing: 7) {
                                ForEach(report.topSites.prefix(8)) { site in
                                    distributionBarRow(
                                        label: site.host,
                                        color: DayHelmColors.successEmerald,
                                        minutes: site.minutes,
                                        share: site.share,
                                        trailingNote: "\(site.visitCount)次"
                                    )
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func budgetProgressRow(budget: BudgetSnapshot) -> some View {
        let denom = Double(budget.capMinutes ?? budget.targetMinutes ?? 60)
        let ratio = denom > 0 ? min(1.0, max(0.0, budget.focusedMinutes / denom)) : 0
        let barColor: Color = {
            switch budget.status {
            case .capReached, .approachingCap: return DayHelmColors.warningAmber
            case .targetMet: return DayHelmColors.successEmerald
            case .underTarget, .noBudget: return DayHelmColors.primaryBlue
            }
        }()
        let statusTag: String = {
            switch budget.status {
            case .targetMet: return "✓ 已达标"
            case .capReached: return "已达上限"
            case .approachingCap: return "接近上限"
            case .underTarget:
                if let t = budget.targetMinutes {
                    return "差 \(max(1, Int((Double(t) - budget.focusedMinutes).rounded())))m"
                }
                return "推进中"
            case .noBudget: return "自由"
            }
        }()

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(barColor)
                    .frame(width: 6, height: 6)
                Text(budget.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Text(statusTag)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(barColor)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(String(format: "%.0fm", budget.focusedMinutes))
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 48, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.08))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(barColor)
                        .frame(width: max(budget.focusedMinutes > 0 ? 3 : 0, geo.size.width * ratio))
                }
            }
            .frame(height: 5)
        }
    }

    private func distributionBarRow(
        label: String,
        color: Color,
        minutes: Double,
        share: Double,
        trailingNote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let trailingNote {
                    Text(trailingNote)
                        .font(.system(size: 9.5, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .frame(width: 44, alignment: .trailing)
                }
                Text(String(format: "%.1fm", minutes))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 48, alignment: .trailing)
                Text(String(format: "%.0f%%", share * 100.0))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 32, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.primary.opacity(0.07))
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(color.opacity(0.85))
                        .frame(width: max(minutes > 0.05 ? 3 : 0, geo.size.width * min(1.0, max(0.0, share))))
                }
            }
            .frame(height: 4.5)
        }
    }

    // MARK: - 5. 24-Hour Rhythm Chart

    private func hourlyRhythmCard(report: DailyStatsReport) -> some View {
        let maxHourMins = max(15.0, report.hourlyRhythm.map(\.activeMinutes).max() ?? 15.0)
        let activeBucket = hoveredHour.flatMap { h in report.hourlyRhythm.first(where: { $0.hour == h }) }

        return StatsSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                statsCardHeader(
                    icon: "chart.bar.fill",
                    iconColor: DayHelmColors.primaryBlue,
                    title: "24 小时分时节律"
                ) {
                    if let b = activeBucket {
                        Text(String(
                            format: "%02d:00–%02d:59 · 活跃 %.1fm · 跨任务切换 %d 次 · 乱切 %.1fm",
                            b.hour, b.hour, b.activeMinutes, b.crossTaskSwitches, b.thrashingMinutes
                        ))
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    } else {
                        Text("蓝条=活跃分钟 · 红段=高频乱切 · 悬停查看单小时详情")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(report.hourlyRhythm) { bucket in
                        let isHovered = hoveredHour == bucket.hour
                        let activeRatio = min(1.0, max(0.0, bucket.activeMinutes / maxHourMins))
                        let thrashRatio = min(activeRatio, max(0.0, bucket.thrashingMinutes / maxHourMins))
                        let normalRatio = max(0.0, activeRatio - thrashRatio)

                        VStack(spacing: 4) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(isHovered ? Color.primary.opacity(0.09) : Color.primary.opacity(0.035))
                                    .frame(height: 82)

                                VStack(spacing: 0) {
                                    if thrashRatio > 0 {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(DayHelmColors.destructiveRed)
                                            .frame(height: max(2.0, 82.0 * thrashRatio))
                                    }
                                    if normalRatio > 0 {
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(isHovered ? DayHelmColors.primaryBlue : DayHelmColors.primaryBlue.opacity(0.82))
                                            .frame(height: max(2.0, 82.0 * normalRatio))
                                    }
                                }
                            }

                            Text(bucket.hour % 4 == 0 || bucket.hour == 23 ? String(format: "%02d", bucket.hour) : "")
                                .font(.system(size: 9, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(isHovered ? .primary : .tertiary)
                                .lineLimit(1)
                                .frame(height: 11)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                hoveredHour = bucket.hour
                            } else if hoveredHour == bucket.hour {
                                hoveredHour = nil
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 6. Behavioral Habits Dual Cards (Equal Height)

    private func habitsDualCards(report: DailyStatsReport) -> some View {
        let totalDwellCount = report.dwellBuckets.reduce(0) { $0 + $1.count }

        return HStack(alignment: .top, spacing: 12) {
            // Left: 5-tier Dwell Distribution
            StatsSectionCard(fillHeight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    statsCardHeader(
                        icon: "timer",
                        iconColor: DayHelmColors.violetAccent,
                        title: "连续停留时长分布（5 档）"
                    ) {
                        if totalDwellCount > 0 {
                            Text("共 \(totalDwellCount) 段")
                                .font(.system(size: 10, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if totalDwellCount == 0 {
                        Text("当日暂无连续停留片段")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 110)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(report.dwellBuckets) { bucket in
                                distributionBarRow(
                                    label: bucket.label,
                                    color: dwellBucketColor(id: bucket.id),
                                    minutes: bucket.minutes,
                                    share: bucket.share,
                                    trailingNote: "\(bucket.count)段"
                                )
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }

            // Right: Top Switch Transitions
            StatsSectionCard(fillHeight: true) {
                VStack(alignment: .leading, spacing: 10) {
                    statsCardHeader(
                        icon: "arrow.left.arrow.right",
                        iconColor: DayHelmColors.warningAmber,
                        title: "高频切换路径 Top \(max(1, report.topTransitions.count))"
                    ) {
                        if !report.topTransitions.isEmpty {
                            Text("频次 · 切入均停")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    if report.topTransitions.isEmpty {
                        Text("当日暂无高频跨任务切换路径")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, minHeight: 110)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(Array(report.topTransitions.enumerated()), id: \.element.id) { idx, t in
                                HStack(spacing: 6) {
                                    HStack(spacing: 4) {
                                        Text(t.fromLabel)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 8.5, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                            .fixedSize()
                                        Text(t.toLabel)
                                            .font(.system(size: 11, weight: .medium))
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text("\(t.count) 次")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(DayHelmColors.warningAmber)
                                        .lineLimit(1)
                                        .frame(width: 44, alignment: .center)
                                        .padding(.vertical, 2)
                                        .background(DayHelmColors.warningAmber.opacity(0.12), in: Capsule())
                                        .fixedSize(horizontal: true, vertical: false)

                                    Text(String(format: "均停 %.0fs", t.avgTargetDwellSeconds))
                                        .font(.system(size: 10, design: .monospaced))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 62, alignment: .trailing)
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                                .padding(.vertical, 2.5)

                                if idx + 1 < report.topTransitions.count {
                                    Divider().opacity(0.45)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 7. Local Agent Analysis Prompt Card

    private func agentPromptCard(report: DailyStatsReport) -> some View {
        let promptText = coordinator.buildAgentAnalysisPrompt(for: report, preset: promptPreset)

        return StatsSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal.fill")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(DayHelmColors.primaryBlue)
                            Text("本地 Agent 深度分析提示词")
                                .font(.system(size: 13, weight: .bold))
                                .lineLimit(1)
                        }
                        Text("纯本地只读下钻指令（无 API Key、不传网页端）：一键复制给本机 Claude Code / Codex / Hermes 自行查阅 dayhelm CLI 与只读 SQLite。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Button {
                        copyPromptToClipboard(report: report)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10.5, weight: .semibold))
                            Text(copiedFeedback ? "已复制 ✓" : "复制提示词")
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(
                            copiedFeedback ? DayHelmColors.successEmerald : DayHelmColors.primaryBlue,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                }

                HStack(alignment: .top, spacing: 10) {
                    ForEach(AgentAnalysisPromptPreset.allCases) { preset in
                        let selected = (promptPreset == preset)
                        Button {
                            promptPreset = preset
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.title)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(selected ? DayHelmColors.primaryBlue : .primary)
                                    .lineLimit(1)
                                Text(preset.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                selected ? DayHelmColors.primaryBlue.opacity(0.10) : Color.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        selected ? DayHelmColors.primaryBlue.opacity(0.55) : Color.primary.opacity(0.08),
                                        lineWidth: 0.75
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            isPromptExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isPromptExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9.5, weight: .semibold))
                            Text(isPromptExpanded ? "收起只读预览" : "展开只读预览")
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)

                    Spacer()

                    Text("\(promptText.count) 字符 · 含 \(report.date) 统计骨架与只读护栏")
                        .font(.system(size: 10, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if isPromptExpanded {
                    ScrollView {
                        Text(promptText)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(.primary.opacity(0.9))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 220)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    private func statsCardHeader<Trailing: View>(
        icon: String,
        iconColor: Color,
        title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 6)

            trailing()
        }
        .frame(minHeight: 22)
    }

    private var generatingPlaceholderCard: some View {
        StatsSectionCard {
            VStack(spacing: 10) {
                ProgressView()
                    .controlSize(.regular)
                Text(selectedDate.isEmpty ? "正在后台准备历史统计报表…" : "正在后台加载 / 生成 \(selectedDate) 统计报表…")
                    .font(.system(size: 13, weight: .semibold))
                Text("每日统计均在后台低优先级队列预计算并缓存到 stats/ 目录，不会阻塞界面操作。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private var noHistoryYetCard: some View {
        StatsSectionCard {
            VStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("暂无已生成的历史统计报表")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("「每日统计」仅查看昨天及更早的预计算历史报表（不在切换页面时实时计算当天）。系统会在次日跨天及启动时自动在后台生成前一天报表。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 36)
        }
    }

    private func emptyStateCard(date: String) -> some View {
        StatsSectionCard {
            VStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("\(date) 暂无可统计的活动数据")
                    .font(.system(size: 13, weight: .semibold))
                Text("切换到其他历史日期，或使用下方提示词让本地 Agent 检索历史 SQLite 记录。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        }
    }

    // MARK: - Helpers

    private var yesterdayDateString: String? {
        guard let todayStart = DayHelmDateFormatting.parseDayString(coordinator.todayDateString) else {
            return nil
        }
        return DayHelmDateFormatting.dayString(from: todayStart.addingTimeInterval(-86_400))
    }

    private var canStepOlder: Bool {
        guard let idx = availableDates.firstIndex(of: selectedDate) else { return false }
        return idx + 1 < availableDates.count
    }

    private var canStepNewer: Bool {
        guard let idx = availableDates.firstIndex(of: selectedDate) else { return false }
        return idx > 0
    }

    private func stepDate(older: Bool) {
        guard let idx = availableDates.firstIndex(of: selectedDate) else { return }
        let nextIdx = older ? idx + 1 : idx - 1
        guard nextIdx >= 0 && nextIdx < availableDates.count else { return }
        selectedDate = availableDates[nextIdx]
    }

    private func loadDatesAndReport(resetToLatestIfNeeded: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            let dates = await coordinator.refreshAvailableHistoricalDatesAsync()
            guard !Task.isCancelled else { return }
            availableDates = dates

            if dates.isEmpty {
                selectedDate = ""
                report = nil
                isLoadingReport = false
                return
            }

            let targetDate: String
            if resetToLatestIfNeeded || selectedDate.isEmpty || !dates.contains(selectedDate) {
                targetDate = dates[0]
            } else {
                targetDate = selectedDate
            }

            if selectedDate != targetDate {
                // Setting selectedDate triggers `.onChange(of: selectedDate)` which runs `loadReport`.
                selectedDate = targetDate
                return
            }

            await performLoadReport(for: targetDate, forceRebuild: false)
        }
    }

    private func loadReport(for dateString: String, forceRebuild: Bool) {
        loadTask?.cancel()
        loadTask = Task {
            await performLoadReport(for: dateString, forceRebuild: forceRebuild)
        }
    }

    @MainActor
    private func performLoadReport(for dateString: String, forceRebuild: Bool) async {
        guard !dateString.isEmpty else {
            report = nil
            isLoadingReport = false
            return
        }
        isLoadingReport = true
        if report?.date != dateString {
            report = nil
        }
        let loaded = await coordinator.loadHistoricalDailyStats(for: dateString, forceRebuild: forceRebuild)
        guard !Task.isCancelled, selectedDate == dateString else { return }
        report = loaded
        isLoadingReport = false
    }

    private func copyPromptToClipboard(report: DailyStatsReport) {
        let prompt = coordinator.buildAgentAnalysisPrompt(for: report, preset: promptPreset)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
        copiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            copiedFeedback = false
        }
    }

    private func dwellBucketColor(id: String) -> Color {
        switch id {
        case "<1m": return DayHelmColors.destructiveRed
        case "1-3m": return DayHelmColors.warningAmber
        case "3-10m": return DayHelmColors.primaryBlue
        case "10-25m": return DayHelmColors.successEmerald
        default: return DayHelmColors.violetAccent
        }
    }

    private func spanSummaryText(_ report: DailyStatsReport) -> String {
        if let first = report.firstActiveAt, let last = report.lastActiveAt {
            return "起止 \(formatHHMM(first))–\(formatHHMM(last))\n全天跨度 \(formatDuration(minutes: report.spanMinutes))"
        }
        return "历史归档日期\n后台预计算"
    }

    private func formatDelta(
        current: Double,
        baseline: Double,
        unit: String,
        decimals: Int = 0,
        sampleDays: Int
    ) -> (text: String, isHigher: Bool)? {
        guard baseline > 0 || current > 0 else { return nil }
        let diff = current - baseline
        let sign = diff >= 0 ? "+" : "-"
        let absDiff = abs(diff)
        let numStr = decimals == 0 ? String(format: "%.0f", absDiff) : String(format: "%.\(decimals)f", absDiff)
        return ("\(sign)\(numStr)\(unit) vs \(sampleDays)d", diff >= 0)
    }

    private func segmentSummaryLabel(_ segment: SpectrumSegment) -> String {
        let range = "\(formatHHMM(segment.startedAt))–\(formatHHMM(segment.endedAt))"
        let mins = String(format: "%.0fm", segment.durationMinutes)
        switch segment.kind {
        case .task(_, let displayName, _):
            return "\(displayName) · \(mins) (\(range))"
        case .activityMode(let rawValue):
            let label = ActivityMode(rawValue: rawValue)?.displayName ?? rawValue
            return "\(label) · \(mins) (\(range))"
        case .thrashing(let switchCount):
            return "高频乱切 (\(switchCount)次) · \(mins) (\(range))"
        case .idle:
            return "空闲/离开 · \(mins) (\(range))"
        case .unassigned:
            return "未指定专注 · \(mins) (\(range))"
        }
    }

    private static let hhmmFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        df.dateFormat = "HH:mm"
        return df
    }()

    private func formatHHMM(_ date: Date) -> String {
        Self.hhmmFormatter.string(from: date)
    }

    private func formatDuration(minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

private struct StatsSectionCard<Content: View>: View {
    var fillHeight: Bool = false
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
    }
}
