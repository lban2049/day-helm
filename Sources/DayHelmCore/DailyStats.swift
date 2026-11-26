import Foundation

// MARK: - Daily Stats Models

public struct DailyStatsCoreMetrics: Sendable, Equatable, Codable {
    public let activeMinutes: Double
    public let medianBlockMinutes: Double
    public let longestBlockMinutes: Double
    public let solidBlocksCount: Int
    public let crossTaskSwitchCount: Int
    public let switchesPerHour: Double
    public let thrashingMinutes: Double
    public let thrashingSegmentCount: Int
    public let clickCount: Int
    public let keypressCount: Int
    public let inputEventsPerMinute: Double
    public let sessionCount: Int
    public let meetingCount: Int
    public let snapshotCount: Int
    public let ocrFrameCount: Int

    public init(
        activeMinutes: Double,
        medianBlockMinutes: Double,
        longestBlockMinutes: Double,
        solidBlocksCount: Int,
        crossTaskSwitchCount: Int,
        switchesPerHour: Double,
        thrashingMinutes: Double,
        thrashingSegmentCount: Int,
        clickCount: Int,
        keypressCount: Int,
        inputEventsPerMinute: Double,
        sessionCount: Int,
        meetingCount: Int,
        snapshotCount: Int,
        ocrFrameCount: Int
    ) {
        self.activeMinutes = activeMinutes
        self.medianBlockMinutes = medianBlockMinutes
        self.longestBlockMinutes = longestBlockMinutes
        self.solidBlocksCount = solidBlocksCount
        self.crossTaskSwitchCount = crossTaskSwitchCount
        self.switchesPerHour = switchesPerHour
        self.thrashingMinutes = thrashingMinutes
        self.thrashingSegmentCount = thrashingSegmentCount
        self.clickCount = clickCount
        self.keypressCount = keypressCount
        self.inputEventsPerMinute = inputEventsPerMinute
        self.sessionCount = sessionCount
        self.meetingCount = meetingCount
        self.snapshotCount = snapshotCount
        self.ocrFrameCount = ocrFrameCount
    }
}

public struct DailyStatsBaseline7d: Sendable, Equatable, Codable {
    public let sampleDays: Int
    public let avgActiveMinutes: Double
    public let avgMedianBlockMinutes: Double
    public let avgLongestBlockMinutes: Double
    public let avgSolidBlocksCount: Double
    public let avgCrossTaskSwitchCount: Double
    public let avgSwitchesPerHour: Double
    public let avgThrashingMinutes: Double

    public init(
        sampleDays: Int,
        avgActiveMinutes: Double,
        avgMedianBlockMinutes: Double,
        avgLongestBlockMinutes: Double,
        avgSolidBlocksCount: Double,
        avgCrossTaskSwitchCount: Double,
        avgSwitchesPerHour: Double,
        avgThrashingMinutes: Double
    ) {
        self.sampleDays = sampleDays
        self.avgActiveMinutes = avgActiveMinutes
        self.avgMedianBlockMinutes = avgMedianBlockMinutes
        self.avgLongestBlockMinutes = avgLongestBlockMinutes
        self.avgSolidBlocksCount = avgSolidBlocksCount
        self.avgCrossTaskSwitchCount = avgCrossTaskSwitchCount
        self.avgSwitchesPerHour = avgSwitchesPerHour
        self.avgThrashingMinutes = avgThrashingMinutes
    }
}

public struct DailyActivityModeStat: Sendable, Equatable, Codable, Identifiable {
    public var id: String { mode.rawValue }
    public let mode: ActivityMode
    public let displayName: String
    public let colorHex: String
    public let minutes: Double
    public let share: Double

    public init(
        mode: ActivityMode,
        displayName: String,
        colorHex: String,
        minutes: Double,
        share: Double
    ) {
        self.mode = mode
        self.displayName = displayName
        self.colorHex = colorHex
        self.minutes = minutes
        self.share = share
    }
}

public struct DailyAppStat: Sendable, Equatable, Codable, Identifiable {
    public var id: String { appName }
    public let appName: String
    public let bundleId: String?
    public let minutes: Double
    public let share: Double
    public let spanCount: Int

    public init(
        appName: String,
        bundleId: String? = nil,
        minutes: Double,
        share: Double,
        spanCount: Int
    ) {
        self.appName = appName
        self.bundleId = bundleId
        self.minutes = minutes
        self.share = share
        self.spanCount = spanCount
    }
}

public struct DailySiteStat: Sendable, Equatable, Codable, Identifiable {
    public var id: String { host }
    public let host: String
    public let minutes: Double
    public let share: Double
    public let visitCount: Int

    public init(
        host: String,
        minutes: Double,
        share: Double,
        visitCount: Int
    ) {
        self.host = host
        self.minutes = minutes
        self.share = share
        self.visitCount = visitCount
    }
}

public struct DailyHourBucket: Sendable, Equatable, Codable, Identifiable {
    public var id: Int { hour }
    public let hour: Int
    public let activeMinutes: Double
    public let crossTaskSwitches: Int
    public let thrashingMinutes: Double

    public init(
        hour: Int,
        activeMinutes: Double,
        crossTaskSwitches: Int,
        thrashingMinutes: Double
    ) {
        self.hour = hour
        self.activeMinutes = activeMinutes
        self.crossTaskSwitches = crossTaskSwitches
        self.thrashingMinutes = thrashingMinutes
    }
}

public struct DailyDwellBucket: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let label: String
    public let count: Int
    public let minutes: Double
    public let share: Double

    public init(
        id: String,
        label: String,
        count: Int,
        minutes: Double,
        share: Double
    ) {
        self.id = id
        self.label = label
        self.count = count
        self.minutes = minutes
        self.share = share
    }
}

public struct DailyTransitionStat: Sendable, Equatable, Codable, Identifiable {
    public var id: String { "\(fromLabel)->\(toLabel)" }
    public let fromLabel: String
    public let toLabel: String
    public let count: Int
    public let avgTargetDwellSeconds: Double

    public init(
        fromLabel: String,
        toLabel: String,
        count: Int,
        avgTargetDwellSeconds: Double
    ) {
        self.fromLabel = fromLabel
        self.toLabel = toLabel
        self.count = count
        self.avgTargetDwellSeconds = avgTargetDwellSeconds
    }
}

public struct DailyStatsReport: Sendable, Equatable, Codable {
    public let schemaVersion: Int
    public let date: String
    public let isToday: Bool
    public let hasData: Bool
    public let firstActiveAt: Date?
    public let lastActiveAt: Date?
    public let spanMinutes: Double
    public let core: DailyStatsCoreMetrics
    public let baseline7d: DailyStatsBaseline7d?
    public let spectrumSegments: [SpectrumSegment]
    public let budgets: [BudgetSnapshot]
    public let activityModes: [DailyActivityModeStat]
    public let topApps: [DailyAppStat]
    public let topSites: [DailySiteStat]
    public let hourlyRhythm: [DailyHourBucket]
    public let dwellBuckets: [DailyDwellBucket]
    public let topTransitions: [DailyTransitionStat]

    public init(
        schemaVersion: Int = 1,
        date: String,
        isToday: Bool,
        hasData: Bool,
        firstActiveAt: Date?,
        lastActiveAt: Date?,
        spanMinutes: Double,
        core: DailyStatsCoreMetrics,
        baseline7d: DailyStatsBaseline7d?,
        spectrumSegments: [SpectrumSegment],
        budgets: [BudgetSnapshot],
        activityModes: [DailyActivityModeStat],
        topApps: [DailyAppStat],
        topSites: [DailySiteStat],
        hourlyRhythm: [DailyHourBucket],
        dwellBuckets: [DailyDwellBucket],
        topTransitions: [DailyTransitionStat]
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.isToday = isToday
        self.hasData = hasData
        self.firstActiveAt = firstActiveAt
        self.lastActiveAt = lastActiveAt
        self.spanMinutes = spanMinutes
        self.core = core
        self.baseline7d = baseline7d
        self.spectrumSegments = spectrumSegments
        self.budgets = budgets
        self.activityModes = activityModes
        self.topApps = topApps
        self.topSites = topSites
        self.hourlyRhythm = hourlyRhythm
        self.dwellBuckets = dwellBuckets
        self.topTransitions = topTransitions
    }
}

public enum AgentAnalysisPromptPreset: String, Sendable, Equatable, Codable, CaseIterable, Identifiable {
    case dailyReview = "daily_review"
    case workOutputDraft = "work_output_draft"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dailyReview:
            return "每日复盘与习惯诊断"
        case .workOutputDraft:
            return "工作产出与日报草稿"
        }
    }

    public var subtitle: String {
        switch self {
        case .dailyReview:
            return "聚焦注意力连续度、高频切换诱因与明日节奏校准"
        case .workOutputDraft:
            return "按会话/标题/OCR 下钻梳理实际完成事项并生成日报草稿"
        }
    }
}

// MARK: - Aggregator

public enum DailyStatsAggregator {
    public struct SyntheticRecorderTotals: Sendable, Equatable {
        public let sessions: Int
        public let meetings: Int
        public let clicks: Int
        public let keypresses: Int
        public let snapshots: Int
        public let ocrFrames: Int
        public let activeSessionMs: Int64

        public init(
            sessions: Int,
            meetings: Int,
            clicks: Int,
            keypresses: Int,
            snapshots: Int,
            ocrFrames: Int,
            activeSessionMs: Int64
        ) {
            self.sessions = sessions
            self.meetings = meetings
            self.clicks = clicks
            self.keypresses = keypresses
            self.snapshots = snapshots
            self.ocrFrames = ocrFrames
            self.activeSessionMs = activeSessionMs
        }
    }

    /// Computes a deterministic single-day report.
    /// Time allocation, spectrum, block continuity, and cross-task switches use `DayHelmDaySnapshot` as the single source of truth;
    /// SQLite enriches input counts, sessions/meetings, snapshots, and OCR frames.
    public static func aggregate(
        dateString: String,
        liveSnapshot: DayHelmDaySnapshot? = nil,
        budgets: [TaskBudget]? = nil,
        store: DayHelmStore? = nil,
        database: ActivityDatabase? = nil,
        clock: any DayHelmClock = SystemClock(),
        includeBaseline: Bool = true,
        syntheticTotals: SyntheticRecorderTotals? = nil,
        archivedSnapshots: [String: DayHelmDaySnapshot]? = nil
    ) -> DailyStatsReport {
        let now = clock.now()
        let todayStr = DayHelmDateFormatting.dayString(from: now)
        let isToday = (dateString == todayStr)

        let resolvedSnapshot: DayHelmDaySnapshot? = {
            if let liveSnapshot, liveSnapshot.date == dateString {
                return liveSnapshot
            }
            if isToday, let todaySnap = try? store?.loadToday(), todaySnap.date == dateString {
                return todaySnap
            }
            if let overrideSnap = archivedSnapshots?[dateString] {
                return overrideSnap
            }
            return try? store?.loadDay(dateString: dateString)
        }()

        let effectiveBudgets = resolveBudgets(explicit: budgets, snapshot: resolvedSnapshot, store: store)
        let dbStats = loadSQLiteStats(
            dateString: dateString,
            database: database,
            syntheticTotals: syntheticTotals
        )

        let baseline7d: DailyStatsBaseline7d? = includeBaseline
            ? computeBaseline7d(
                before: dateString,
                store: store,
                budgets: effectiveBudgets,
                clock: clock,
                archivedSnapshots: archivedSnapshots
            )
            : nil

        guard let snapshot = resolvedSnapshot else {
            return makeFallbackReport(
                dateString: dateString,
                isToday: isToday,
                dbStats: dbStats,
                baseline7d: baseline7d
            )
        }

        let spectrumNow = resolveSpectrumReferenceTime(
            snapshot: snapshot,
            isToday: isToday,
            clockNow: now
        )

        let built = SpectrumBuilder.build(
            spans: snapshot.enrichedSpans,
            focusSessions: snapshot.focusSessions,
            budgets: effectiveBudgets,
            now: spectrumNow
        )

        let primaryMetrics = snapshot.metrics.activeMinutes > 0 ? snapshot.metrics : built.metrics
        let segments = built.segments

        // Work block durations for median block (consistent with SpectrumBuilder longestBlock/solidBlocks).
        let workBlockDurations = segments.compactMap { seg -> Double? in
            switch seg.kind {
            case .task, .unassigned:
                return seg.durationMinutes > 0 ? seg.durationMinutes : nil
            case .activityMode(let raw):
                guard raw != ActivityMode.breakTime.rawValue else { return nil }
                return seg.durationMinutes > 0 ? seg.durationMinutes : nil
            case .thrashing, .idle:
                return nil
            }
        }
        let medianBlockMinutes = median(of: workBlockDurations)

        // Thrashing aggregates
        var thrashingMinutes = 0.0
        var thrashingSegmentCount = 0
        for seg in segments {
            if case .thrashing = seg.kind {
                thrashingMinutes += max(0, seg.durationMinutes)
                thrashingSegmentCount += 1
            }
        }

        // First / last active timestamps & span
        let activeBounds = computeActiveTimeBounds(spans: snapshot.enrichedSpans, focusSessions: snapshot.focusSessions, segments: segments)
        let spanMinutes: Double
        if let first = activeBounds.first, let last = activeBounds.last, last >= first {
            spanMinutes = last.timeIntervalSince(first) / 60.0
        } else {
            spanMinutes = 0.0
        }

        // Switch, transition & dwell analysis via SwitchClassifier
        let prepared = SwitchClassifier.prepareSequence(spans: snapshot.enrichedSpans)
        let normalizedBudgets = effectiveBudgets.map(SwitchClassifier.NormalizedBudget.init)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone

        var hourlyActive = [Double](repeating: 0.0, count: 24)
        var hourlyThrashing = [Double](repeating: 0.0, count: 24)
        var hourlySwitches = [Int](repeating: 0, count: 24)

        if let dayStart = DayHelmDateFormatting.parseDayString(dateString) {
            distributeSegmentsByHour(
                segments: segments,
                dayStart: dayStart,
                hourlyActive: &hourlyActive,
                hourlyThrashing: &hourlyThrashing
            )
        }

        var crossTaskSwitchCount = 0
        var transitionMap: [TransitionKey: (count: Int, totalTargetDwellSeconds: Double)] = [:]

        if prepared.count >= 2 {
            for i in 1..<prepared.count {
                let prev = prepared[i - 1]
                let curr = prepared[i]
                guard SwitchClassifier.isCrossTaskSwitch(from: prev, to: curr, normalizedBudgets: normalizedBudgets) else {
                    continue
                }
                crossTaskSwitchCount += 1
                let hour = cal.component(.hour, from: curr.span.startedAt)
                if hour >= 0 && hour < 24 && DayHelmDateFormatting.dayString(from: curr.span.startedAt) == dateString {
                    hourlySwitches[hour] += 1
                }
                let fromLabel = transitionLabel(for: prev.span)
                let toLabel = transitionLabel(for: curr.span)
                if fromLabel != toLabel {
                    let dwell = dwellDurationSeconds(for: curr)
                    let key = TransitionKey(fromLabel: fromLabel, toLabel: toLabel)
                    var existing = transitionMap[key] ?? (0, 0.0)
                    existing.count += 1
                    existing.totalTargetDwellSeconds += dwell
                    transitionMap[key] = existing
                }
            }
        }

        let switchesPerHour: Double
        if primaryMetrics.activeMinutes > 0 && crossTaskSwitchCount > 0 {
            let observedSeconds = max(600.0, primaryMetrics.activeMinutes * 60.0)
            switchesPerHour = Double(crossTaskSwitchCount) / (observedSeconds / 3600.0)
        } else {
            switchesPerHour = 0.0
        }

        let topTransitions = transitionMap
            .map { key, stats in
                DailyTransitionStat(
                    fromLabel: key.fromLabel,
                    toLabel: key.toLabel,
                    count: stats.count,
                    avgTargetDwellSeconds: stats.totalTargetDwellSeconds / Double(max(1, stats.count))
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                let lhsTotal = lhs.avgTargetDwellSeconds * Double(lhs.count)
                let rhsTotal = rhs.avgTargetDwellSeconds * Double(rhs.count)
                if abs(lhsTotal - rhsTotal) > 0.01 { return lhsTotal > rhsTotal }
                if lhs.fromLabel != rhs.fromLabel { return lhs.fromLabel < rhs.fromLabel }
                return lhs.toLabel < rhs.toLabel
            }
            .prefix(8)
            .map { $0 }

        let dwellBuckets = computeDwellBuckets(prepared: prepared, fallbackSpans: snapshot.enrichedSpans)
        let activityModes = computeActivityModes(snapshot: snapshot)
        let topApps = computeTopApps(spans: snapshot.enrichedSpans)
        let topSites = computeTopSites(spans: snapshot.enrichedSpans)

        let hourlyRhythm = (0..<24).map { hour in
            DailyHourBucket(
                hour: hour,
                activeMinutes: hourlyActive[hour],
                crossTaskSwitches: hourlySwitches[hour],
                thrashingMinutes: hourlyThrashing[hour]
            )
        }

        let effectiveDensity: Double
        if dbStats.inputEventsPerMinute > 0 {
            effectiveDensity = dbStats.inputEventsPerMinute
        } else if (dbStats.clickCount + dbStats.keypressCount) > 0, primaryMetrics.activeMinutes > 0 {
            effectiveDensity = Double(dbStats.clickCount + dbStats.keypressCount) / primaryMetrics.activeMinutes
        } else {
            effectiveDensity = 0.0
        }

        let core = DailyStatsCoreMetrics(
            activeMinutes: primaryMetrics.activeMinutes,
            medianBlockMinutes: medianBlockMinutes,
            longestBlockMinutes: primaryMetrics.longestBlockMinutes,
            solidBlocksCount: primaryMetrics.solidBlocksCount,
            crossTaskSwitchCount: crossTaskSwitchCount,
            switchesPerHour: switchesPerHour,
            thrashingMinutes: thrashingMinutes,
            thrashingSegmentCount: thrashingSegmentCount,
            clickCount: dbStats.clickCount,
            keypressCount: dbStats.keypressCount,
            inputEventsPerMinute: effectiveDensity,
            sessionCount: dbStats.sessionCount,
            meetingCount: dbStats.meetingCount,
            snapshotCount: dbStats.snapshotCount,
            ocrFrameCount: dbStats.ocrFrameCount
        )

        let hasData = primaryMetrics.activeMinutes > 0
            || !snapshot.enrichedSpans.isEmpty
            || !snapshot.focusSessions.isEmpty
            || dbStats.sessionCount > 0

        return DailyStatsReport(
            schemaVersion: 1,
            date: dateString,
            isToday: isToday,
            hasData: hasData,
            firstActiveAt: activeBounds.first,
            lastActiveAt: activeBounds.last,
            spanMinutes: spanMinutes,
            core: core,
            baseline7d: baseline7d,
            spectrumSegments: segments,
            budgets: snapshot.budgets,
            activityModes: activityModes,
            topApps: topApps,
            topSites: topSites,
            hourlyRhythm: hourlyRhythm,
            dwellBuckets: dwellBuckets,
            topTransitions: topTransitions
        )
    }

    /// Parses an `http(s)` URL into a normalized display host: lowercased, leading `www.` stripped,
    /// default ports (`80` for http, `443` for https) removed, and non-default ports preserved.
    public static func extractSiteHost(from rawURL: String?) -> String? {
        guard let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }

        if host.hasPrefix("www."), host.count > 4 {
            host = String(host.dropFirst(4))
        }

        if let port = components.port {
            let isDefaultPort = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
            if !isDefaultPort {
                return "\(host):\(port)"
            }
        }
        return host
    }

    // MARK: - Private Helpers

    private struct TransitionKey: Hashable {
        let fromLabel: String
        let toLabel: String
    }

    private struct SQLiteDayStats {
        let clickCount: Int
        let keypressCount: Int
        let inputEventsPerMinute: Double
        let sessionCount: Int
        let meetingCount: Int
        let snapshotCount: Int
        let ocrFrameCount: Int
        let fallbackSummary: ActivityDailySummaryStats?
    }

    private static func loadSQLiteStats(
        dateString: String,
        database: ActivityDatabase?,
        syntheticTotals: SyntheticRecorderTotals?
    ) -> SQLiteDayStats {
        if let syntheticTotals {
            let density = DayInputTotals.density(
                clickCount: syntheticTotals.clicks,
                keypressCount: syntheticTotals.keypresses,
                durationMs: syntheticTotals.activeSessionMs
            )
            return SQLiteDayStats(
                clickCount: syntheticTotals.clicks,
                keypressCount: syntheticTotals.keypresses,
                inputEventsPerMinute: density,
                sessionCount: syntheticTotals.sessions,
                meetingCount: syntheticTotals.meetings,
                snapshotCount: syntheticTotals.snapshots,
                ocrFrameCount: syntheticTotals.ocrFrames,
                fallbackSummary: nil
            )
        }

        guard let database,
              let dayStart = DayHelmDateFormatting.parseDayString(dateString) else {
            return SQLiteDayStats(
                clickCount: 0,
                keypressCount: 0,
                inputEventsPerMinute: 0,
                sessionCount: 0,
                meetingCount: 0,
                snapshotCount: 0,
                ocrFrameCount: 0,
                fallbackSummary: nil
            )
        }

        let startMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let endMs = startMs + 86_400_000 - 1
        let counts: (sessions: Int, events: Int, snapshots: Int, ocrFrames: Int) = (try? database.todayCounts(dayStartMs: startMs, dayEndMs: endMs)) ?? (0, 0, 0, 0)
        let inputTotals = (try? database.dayInputTotals(dayStartMs: startMs, dayEndMs: endMs))
            ?? DayInputTotals(clickCount: 0, keypressCount: 0, totalSessionDurationMs: 0, inputEventsPerMinute: 0)
        let meetings = (try? database.countMeetingSessions(dayStartMs: startMs, dayEndMs: endMs)) ?? 0
        let summary = counts.sessions > 0 ? (try? database.dailySummaryStats(dateKey: dateString)) : nil

        return SQLiteDayStats(
            clickCount: inputTotals.clickCount,
            keypressCount: inputTotals.keypressCount,
            inputEventsPerMinute: inputTotals.inputEventsPerMinute,
            sessionCount: counts.sessions,
            meetingCount: meetings,
            snapshotCount: counts.snapshots,
            ocrFrameCount: counts.ocrFrames,
            fallbackSummary: summary
        )
    }

    private static func resolveBudgets(
        explicit: [TaskBudget]?,
        snapshot: DayHelmDaySnapshot?,
        store: DayHelmStore?
    ) -> [TaskBudget] {
        if let explicit {
            return explicit
        }
        if let store {
            return TimeAuditConfigLoader.loadBudgets(
                timeAuditDirectory: store.directory.appendingPathComponent("__none__", isDirectory: true),
                dayhelmConfigURL: store.configURL
            )
        }
        if let snapshot, !snapshot.budgets.isEmpty {
            return snapshot.budgets.map {
                TaskBudget(
                    taskId: $0.taskId,
                    displayName: $0.displayName,
                    colorHex: "#3B82F6",
                    targetMinutes: $0.targetMinutes,
                    capMinutes: $0.capMinutes
                )
            }
        }
        return []
    }

    private static func resolveSpectrumReferenceTime(
        snapshot: DayHelmDaySnapshot,
        isToday: Bool,
        clockNow: Date
    ) -> Date {
        var latest = snapshot.enrichedSpans.map(\.endedAt).max()
        let sessionEndMax = snapshot.focusSessions.compactMap { $0.endedAt ?? $0.startedAt }.max()
        if let sessionEndMax {
            latest = max(latest ?? sessionEndMax, sessionEndMax)
        }
        if isToday {
            return max(clockNow, latest ?? clockNow)
        }
        if let latest {
            return latest
        }
        return DayHelmDateFormatting.parseDayString(snapshot.date)?.addingTimeInterval(86_399) ?? clockNow
    }

    private static func computeActiveTimeBounds(
        spans: [EnrichedSpan],
        focusSessions: [FocusSessionRecord],
        segments: [SpectrumSegment]
    ) -> (first: Date?, last: Date?) {
        var dates: [Date] = []
        dates.reserveCapacity(spans.count * 2 + focusSessions.count * 2)
        for span in spans {
            dates.append(span.startedAt)
            dates.append(max(span.startedAt, span.endedAt))
        }
        for session in focusSessions {
            dates.append(session.startedAt)
            if let ended = session.endedAt {
                dates.append(max(session.startedAt, ended))
            }
        }
        for seg in segments {
            dates.append(seg.startedAt)
            dates.append(seg.endedAt)
        }
        return (dates.min(), dates.max())
    }

    private static func distributeSegmentsByHour(
        segments: [SpectrumSegment],
        dayStart: Date,
        hourlyActive: inout [Double],
        hourlyThrashing: inout [Double]
    ) {
        let dayEnd = dayStart.addingTimeInterval(86_400)
        for seg in segments {
            let isThrash: Bool
            let isActive: Bool
            switch seg.kind {
            case .task, .unassigned:
                isActive = true
                isThrash = false
            case .activityMode(let raw):
                isActive = (raw != ActivityMode.breakTime.rawValue)
                isThrash = false
            case .thrashing:
                isActive = true
                isThrash = true
            case .idle:
                isActive = false
                isThrash = false
            }
            guard isActive else { continue }

            let clampedStart = max(dayStart, seg.startedAt)
            let clampedEnd = min(dayEnd, seg.endedAt)
            guard clampedEnd > clampedStart else { continue }

            for hour in 0..<24 {
                let hourStart = dayStart.addingTimeInterval(Double(hour) * 3600.0)
                let hourEnd = hourStart.addingTimeInterval(3600.0)
                let overlapStart = max(clampedStart, hourStart)
                let overlapEnd = min(clampedEnd, hourEnd)
                if overlapEnd > overlapStart {
                    let mins = overlapEnd.timeIntervalSince(overlapStart) / 60.0
                    hourlyActive[hour] += mins
                    if isThrash {
                        hourlyThrashing[hour] += mins
                    }
                }
            }
        }
    }

    private static func transitionLabel(for span: EnrichedSpan) -> String {
        if span.redacted {
            return span.appName
        }
        if ActivityClassifier.isWebURL(span.url), let host = extractSiteHost(from: span.url) {
            return host
        }
        let app = span.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.isEmpty ? "Unknown" : app
    }

    private static func dwellDurationSeconds(for item: PreparedActivitySpan) -> Double {
        let raw = item.span.durationSeconds
        return raw > 0 ? raw : max(1.0, item.effectiveDwellSeconds)
    }

    private static func computeDwellBuckets(
        prepared: [PreparedActivitySpan],
        fallbackSpans: [EnrichedSpan]
    ) -> [DailyDwellBucket] {
        struct BucketDef {
            let id: String
            let label: String
        }
        let defs = [
            BucketDef(id: "<1m", label: "<1m"),
            BucketDef(id: "1-3m", label: "1–3m"),
            BucketDef(id: "3-10m", label: "3–10m"),
            BucketDef(id: "10-25m", label: "10–25m"),
            BucketDef(id: ">=25m", label: "≥25m")
        ]

        var counts = [Int](repeating: 0, count: 5)
        var seconds = [Double](repeating: 0.0, count: 5)

        let durationsSec: [Double]
        if !prepared.isEmpty {
            durationsSec = prepared.map { dwellDurationSeconds(for: $0) }
        } else {
            durationsSec = fallbackSpans.compactMap { span in
                let d = span.durationSeconds
                return d > 0 ? d : nil
            }
        }

        for sec in durationsSec {
            let idx: Int
            if sec < 60.0 {
                idx = 0
            } else if sec < 180.0 {
                idx = 1
            } else if sec < 600.0 {
                idx = 2
            } else if sec < 1500.0 {
                idx = 3
            } else {
                idx = 4
            }
            counts[idx] += 1
            seconds[idx] += sec
        }

        let totalMinutes = seconds.reduce(0.0, +) / 60.0
        return (0..<5).map { idx in
            let mins = seconds[idx] / 60.0
            return DailyDwellBucket(
                id: defs[idx].id,
                label: defs[idx].label,
                count: counts[idx],
                minutes: mins,
                share: totalMinutes > 0 ? mins / totalMinutes : 0.0
            )
        }
    }

    private static func computeActivityModes(snapshot: DayHelmDaySnapshot) -> [DailyActivityModeStat] {
        var minutesByMode: [ActivityMode: Double] = [:]
        if let recorded = snapshot.activityModeMinutes, !recorded.isEmpty {
            for mode in ActivityMode.allCases {
                minutesByMode[mode] = max(0.0, recorded[mode.rawValue] ?? 0.0)
            }
        } else {
            for span in snapshot.enrichedSpans {
                guard let group = span.semanticGroup, !group.isEmpty else { continue }
                let mins = span.durationSeconds / 60.0
                guard mins > 0 else { continue }
                if group == "break" {
                    minutesByMode[.breakTime, default: 0.0] += mins
                } else if group.hasPrefix("mode:"),
                          let mode = ActivityMode(rawValue: String(group.dropFirst(5))) {
                    minutesByMode[mode, default: 0.0] += mins
                }
            }
        }

        let total = minutesByMode.values.reduce(0.0, +)
        return ActivityMode.allCases.map { mode in
            let mins = minutesByMode[mode] ?? 0.0
            return DailyActivityModeStat(
                mode: mode,
                displayName: mode.displayName,
                colorHex: mode.colorHex,
                minutes: mins,
                share: total > 0 ? mins / total : 0.0
            )
        }
    }

    private static func computeTopApps(spans: [EnrichedSpan]) -> [DailyAppStat] {
        var grouped: [String: (bundleId: String?, seconds: Double, count: Int)] = [:]
        var totalSeconds = 0.0

        for span in spans {
            let dur = span.durationSeconds
            guard dur > 0 else { continue }
            let trimmed = span.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let app = trimmed.isEmpty ? "Unknown" : trimmed
            var entry = grouped[app] ?? (span.bundleId, 0.0, 0)
            if entry.bundleId == nil, let b = span.bundleId, !b.isEmpty {
                entry.bundleId = b
            }
            entry.seconds += dur
            entry.count += 1
            grouped[app] = entry
            totalSeconds += dur
        }

        return grouped
            .map { app, entry in
                DailyAppStat(
                    appName: app,
                    bundleId: entry.bundleId,
                    minutes: entry.seconds / 60.0,
                    share: totalSeconds > 0 ? entry.seconds / totalSeconds : 0.0,
                    spanCount: entry.count
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.minutes - rhs.minutes) > 0.001 { return lhs.minutes > rhs.minutes }
                if lhs.spanCount != rhs.spanCount { return lhs.spanCount > rhs.spanCount }
                return lhs.appName < rhs.appName
            }
            .prefix(10)
            .map { $0 }
    }

    private static func computeTopSites(spans: [EnrichedSpan]) -> [DailySiteStat] {
        var grouped: [String: (seconds: Double, count: Int)] = [:]
        var totalSeconds = 0.0

        for span in spans {
            // Hard privacy gate: redacted spans must never contribute to topSites.
            guard !span.redacted else { continue }
            guard let host = extractSiteHost(from: span.url) else { continue }
            let dur = span.durationSeconds
            guard dur > 0 else { continue }
            var entry = grouped[host] ?? (0.0, 0)
            entry.seconds += dur
            entry.count += 1
            grouped[host] = entry
            totalSeconds += dur
        }

        return grouped
            .map { host, entry in
                DailySiteStat(
                    host: host,
                    minutes: entry.seconds / 60.0,
                    share: totalSeconds > 0 ? entry.seconds / totalSeconds : 0.0,
                    visitCount: entry.count
                )
            }
            .sorted { lhs, rhs in
                if abs(lhs.minutes - rhs.minutes) > 0.001 { return lhs.minutes > rhs.minutes }
                if lhs.visitCount != rhs.visitCount { return lhs.visitCount > rhs.visitCount }
                return lhs.host < rhs.host
            }
            .prefix(10)
            .map { $0 }
    }

    private static func computeBaseline7d(
        before dateString: String,
        store: DayHelmStore?,
        budgets: [TaskBudget],
        clock: any DayHelmClock,
        archivedSnapshots: [String: DayHelmDaySnapshot]?
    ) -> DailyStatsBaseline7d? {
        let snapshotMap: [String: DayHelmDaySnapshot] = archivedSnapshots ?? [:]
        var candidateDates: [String] = []

        if let store {
            candidateDates.append(contentsOf: store.listArchivedDayStrings().filter { $0 < dateString })
        }
        if let archivedSnapshots {
            for key in archivedSnapshots.keys where key < dateString && !candidateDates.contains(key) {
                candidateDates.append(key)
            }
        }
        candidateDates = Array(candidateDates.sorted(by: >).prefix(7))
        guard !candidateDates.isEmpty else { return nil }

        var sumActive = 0.0
        var sumMedian = 0.0
        var sumLongest = 0.0
        var sumSolid = 0.0
        var sumSwitches = 0.0
        var sumSwitchesPerHour = 0.0
        var sumThrash = 0.0
        var count = 0

        for day in candidateDates {
            let archSnap = snapshotMap[day] ?? (try? store?.loadDay(dateString: day))
            guard let archSnap else { continue }
            let report = aggregate(
                dateString: day,
                liveSnapshot: archSnap,
                budgets: budgets,
                store: nil,
                database: nil,
                clock: clock,
                includeBaseline: false
            )
            sumActive += report.core.activeMinutes
            sumMedian += report.core.medianBlockMinutes
            sumLongest += report.core.longestBlockMinutes
            sumSolid += Double(report.core.solidBlocksCount)
            sumSwitches += Double(report.core.crossTaskSwitchCount)
            sumSwitchesPerHour += report.core.switchesPerHour
            sumThrash += report.core.thrashingMinutes
            count += 1
        }

        guard count > 0 else { return nil }
        let d = Double(count)
        return DailyStatsBaseline7d(
            sampleDays: count,
            avgActiveMinutes: sumActive / d,
            avgMedianBlockMinutes: sumMedian / d,
            avgLongestBlockMinutes: sumLongest / d,
            avgSolidBlocksCount: sumSolid / d,
            avgCrossTaskSwitchCount: sumSwitches / d,
            avgSwitchesPerHour: sumSwitchesPerHour / d,
            avgThrashingMinutes: sumThrash / d
        )
    }

    private static func makeFallbackReport(
        dateString: String,
        isToday: Bool,
        dbStats: SQLiteDayStats,
        baseline7d: DailyStatsBaseline7d?
    ) -> DailyStatsReport {
        let summary = dbStats.fallbackSummary
        let activeMinutes = summary.map { Double($0.totalActiveMs) / 60_000.0 } ?? 0.0
        let totalAppMs = summary?.apps.reduce(Int64(0)) { $0 + $1.durationMs } ?? 0
        let topApps: [DailyAppStat] = (summary?.apps ?? []).map { entry in
            let mins = Double(entry.durationMs) / 60_000.0
            let share = totalAppMs > 0 ? Double(entry.durationMs) / Double(totalAppMs) : 0.0
            return DailyAppStat(appName: entry.app, bundleId: nil, minutes: mins, share: share, spanCount: 0)
        }
        let hourly = (0..<24).map {
            DailyHourBucket(hour: $0, activeMinutes: 0, crossTaskSwitches: 0, thrashingMinutes: 0)
        }
        let dwell = computeDwellBuckets(prepared: [], fallbackSpans: [])
        let modes = ActivityMode.allCases.map {
            DailyActivityModeStat(mode: $0, displayName: $0.displayName, colorHex: $0.colorHex, minutes: 0, share: 0)
        }
        let hasData = dbStats.sessionCount > 0 || activeMinutes > 0
        let core = DailyStatsCoreMetrics(
            activeMinutes: activeMinutes,
            medianBlockMinutes: 0,
            longestBlockMinutes: 0,
            solidBlocksCount: 0,
            crossTaskSwitchCount: 0,
            switchesPerHour: 0,
            thrashingMinutes: 0,
            thrashingSegmentCount: 0,
            clickCount: dbStats.clickCount,
            keypressCount: dbStats.keypressCount,
            inputEventsPerMinute: dbStats.inputEventsPerMinute,
            sessionCount: dbStats.sessionCount,
            meetingCount: dbStats.meetingCount,
            snapshotCount: dbStats.snapshotCount,
            ocrFrameCount: dbStats.ocrFrameCount
        )

        return DailyStatsReport(
            schemaVersion: 1,
            date: dateString,
            isToday: isToday,
            hasData: hasData,
            firstActiveAt: nil,
            lastActiveAt: nil,
            spanMinutes: 0,
            core: core,
            baseline7d: baseline7d,
            spectrumSegments: [],
            budgets: [],
            activityModes: modes,
            topApps: topApps,
            topSites: [],
            hourlyRhythm: hourly,
            dwellBuckets: dwell,
            topTransitions: []
        )
    }

    private static func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return (sorted[mid - 1] + sorted[mid]) / 2.0
    }
}

// MARK: - Markdown Renderer

public enum DailyStatsMarkdownRenderer {
    public static func render(_ report: DailyStatsReport) -> String {
        var lines: [String] = []
        let tag = report.isToday ? "（今日实时）" : ""
        lines.append("# DayHelm 每日统计 · \(report.date)\(tag)")
        lines.append("")

        if !report.hasData {
            lines.append("当日暂无活动记录。")
            return lines.joined(separator: "\n") + "\n"
        }

        lines.append("## 核心遥测")
        let spanText: String
        if let first = report.firstActiveAt, let last = report.lastActiveAt {
            spanText = "（起止 \(formatHHMM(first))–\(formatHHMM(last))，跨度 \(formatDuration(minutes: report.spanMinutes))）"
        } else {
            spanText = ""
        }
        lines.append("- 总活跃时长：\(formatDuration(minutes: report.core.activeMinutes))\(spanText)")
        lines.append(String(
            format: "- 连续度：中位连续块 %.1fm · 最长连续块 %.0fm · ≥12m 有效块 %d 个",
            report.core.medianBlockMinutes,
            report.core.longestBlockMinutes,
            report.core.solidBlocksCount
        ))
        lines.append(String(
            format: "- 切换与乱切：有效跨任务切换 %d 次（%.1f/h）· 高频乱切 %.1fm（%d 段）",
            report.core.crossTaskSwitchCount,
            report.core.switchesPerHour,
            report.core.thrashingMinutes,
            report.core.thrashingSegmentCount
        ))
        lines.append(String(
            format: "- 输入与采集：点击 %d · 敲击 %d（%.1f/min）· 会话 %d（含会议 %d）· 快照 %d · OCR %d",
            report.core.clickCount,
            report.core.keypressCount,
            report.core.inputEventsPerMinute,
            report.core.sessionCount,
            report.core.meetingCount,
            report.core.snapshotCount,
            report.core.ocrFrameCount
        ))

        if let b = report.baseline7d {
            lines.append(String(
                format: "- 近 %d 日均值基线：活跃 %.0fm · 中位块 %.1fm · 最长块 %.0fm · 有效块 %.1f 个 · 切换 %.1f/h · 乱切 %.1fm",
                b.sampleDays,
                b.avgActiveMinutes,
                b.avgMedianBlockMinutes,
                b.avgLongestBlockMinutes,
                b.avgSolidBlocksCount,
                b.avgSwitchesPerHour,
                b.avgThrashingMinutes
            ))
        }

        if !report.budgets.isEmpty {
            lines.append("")
            lines.append("## 事项配额")
            for b in report.budgets {
                let quota: String
                if let target = b.targetMinutes, let cap = b.capMinutes {
                    quota = "保底 \(target)m / 封顶 \(cap)m"
                } else if let target = b.targetMinutes {
                    quota = "保底 \(target)m"
                } else if let cap = b.capMinutes {
                    quota = "封顶 \(cap)m"
                } else {
                    quota = "自由计时"
                }
                lines.append(String(format: "- **%@** [`%@`]: %.0fm（%@, `%@`）", b.displayName, b.taskId, b.focusedMinutes, quota, b.status.rawValue))
            }
        }

        let nonZeroModes = report.activityModes.filter { $0.minutes >= 0.05 }
        if !nonZeroModes.isEmpty {
            lines.append("")
            lines.append("## 活动大类分布")
            for m in nonZeroModes.sorted(by: { $0.minutes > $1.minutes }) {
                lines.append(String(format: "- %@: %.1fm (%.0f%%)", m.displayName, m.minutes, m.share * 100.0))
            }
        }

        if !report.topApps.isEmpty {
            lines.append("")
            lines.append("## Top 应用")
            for app in report.topApps.prefix(8) {
                lines.append(String(format: "- %@: %.1fm (%.0f%%, %d 段)", app.appName, app.minutes, app.share * 100.0, app.spanCount))
            }
        }

        if !report.topSites.isEmpty {
            lines.append("")
            lines.append("## Top 浏览器站点")
            for site in report.topSites.prefix(8) {
                lines.append(String(format: "- %@: %.1fm (%.0f%%, %d 次)", site.host, site.minutes, site.share * 100.0, site.visitCount))
            }
        }

        let activeHours = report.hourlyRhythm.filter { $0.activeMinutes >= 0.5 || $0.crossTaskSwitches > 0 }
        if !activeHours.isEmpty {
            lines.append("")
            lines.append("## 24 小时分时节律（活跃时段）")
            for h in activeHours {
                lines.append(String(
                    format: "- %02d:00–%02d:59: 活跃 %.0fm · 切换 %d 次 · 乱切 %.0fm",
                    h.hour, h.hour, h.activeMinutes, h.crossTaskSwitches, h.thrashingMinutes
                ))
            }
        }

        let totalDwellCount = report.dwellBuckets.reduce(0) { $0 + $1.count }
        if totalDwellCount > 0 {
            lines.append("")
            lines.append("## 连续停留时长分布")
            for bucket in report.dwellBuckets {
                lines.append(String(format: "- %@: %d 段 (%.1fm, %.0f%%)", bucket.label, bucket.count, bucket.minutes, bucket.share * 100.0))
            }
        }

        if !report.topTransitions.isEmpty {
            lines.append("")
            lines.append("## 高频切换路径 Top \(report.topTransitions.count)")
            for t in report.topTransitions {
                lines.append(String(format: "- %@ → %@: %d 次（切入后均停 %.0fs）", t.fromLabel, t.toLabel, t.count, t.avgTargetDwellSeconds))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    public static func renderCompactSkeleton(_ report: DailyStatsReport) -> String {
        var lines: [String] = []
        lines.append("- 日期：\(report.date)\(report.isToday ? "（今日实时）" : "")")
        if let first = report.firstActiveAt, let last = report.lastActiveAt {
            lines.append("- 起止跨度：\(formatHHMM(first))–\(formatHHMM(last))（\(formatDuration(minutes: report.spanMinutes))）")
        }
        lines.append(String(
            format: "- 活跃与连续度：总活跃 %.0fm · 中位块 %.1fm · 最长块 %.0fm · ≥12m 有效块 %d 个",
            report.core.activeMinutes,
            report.core.medianBlockMinutes,
            report.core.longestBlockMinutes,
            report.core.solidBlocksCount
        ))
        lines.append(String(
            format: "- 切换与乱切：有效跨任务切换 %d 次（%.1f/h）· 乱切 %.1fm（%d 段）",
            report.core.crossTaskSwitchCount,
            report.core.switchesPerHour,
            report.core.thrashingMinutes,
            report.core.thrashingSegmentCount
        ))
        lines.append(String(
            format: "- 采集概览：会话 %d（会议 %d）· 点击 %d / 敲击 %d（%.1f/min）· 快照 %d · OCR %d",
            report.core.sessionCount,
            report.core.meetingCount,
            report.core.clickCount,
            report.core.keypressCount,
            report.core.inputEventsPerMinute,
            report.core.snapshotCount,
            report.core.ocrFrameCount
        ))
        if let b = report.baseline7d {
            lines.append(String(
                format: "- 近 %d 日均值：活跃 %.0fm · 中位块 %.1fm · 最长块 %.0fm · 切换 %.1f/h · 乱切 %.1fm",
                b.sampleDays,
                b.avgActiveMinutes,
                b.avgMedianBlockMinutes,
                b.avgLongestBlockMinutes,
                b.avgSwitchesPerHour,
                b.avgThrashingMinutes
            ))
        }
        if !report.budgets.isEmpty {
            let budgetStr = report.budgets.map { "\($0.displayName) \(Int($0.focusedMinutes.rounded()))m" }.joined(separator: " / ")
            lines.append("- 事项配额：\(budgetStr)")
        }
        let nonZeroModes = report.activityModes.filter { $0.minutes >= 0.5 }.sorted { $0.minutes > $1.minutes }
        if !nonZeroModes.isEmpty {
            let modeStr = nonZeroModes.map { String(format: "%@ %.0fm", $0.displayName, $0.minutes) }.joined(separator: " / ")
            lines.append("- 活动大类：\(modeStr)")
        }
        if !report.topApps.isEmpty {
            let appStr = report.topApps.prefix(5).map { String(format: "%@ %.0fm", $0.appName, $0.minutes) }.joined(separator: " · ")
            lines.append("- Top 应用：\(appStr)")
        }
        if !report.topSites.isEmpty {
            let siteStr = report.topSites.prefix(5).map { String(format: "%@ %.0fm", $0.host, $0.minutes) }.joined(separator: " · ")
            lines.append("- Top 站点：\(siteStr)")
        }
        if !report.topTransitions.isEmpty {
            let pathStr = report.topTransitions.prefix(5).map { "\($0.fromLabel)→\($0.toLabel)(\($0.count)次/\(Int($0.avgTargetDwellSeconds.rounded()))s)" }.joined(separator: " · ")
            lines.append("- 高频切换：\(pathStr)")
        }
        return lines.joined(separator: "\n")
    }

    private static let hhmmFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        df.dateFormat = "HH:mm"
        return df
    }()

    private static func formatHHMM(_ date: Date) -> String {
        hhmmFormatter.string(from: date)
    }

    private static func formatDuration(minutes: Double) -> String {
        let total = max(0, Int(minutes.rounded()))
        if total < 60 {
            return "\(total)m"
        }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Local Agent Analysis Prompt Builder

public enum AgentAnalysisPromptBuilder {
    public static func build(
        report: DailyStatsReport,
        preset: AgentAnalysisPromptPreset,
        storeDirectory: URL = DayHelmStore.defaultDirectory
    ) -> String {
        let storePath = storeDirectory.path
        let snapshotRelative = report.isToday ? "today.json" : "days/\(report.date).json"
        let snapshotFullPath = storeDirectory.appendingPathComponent(snapshotRelative).path
        let sqlitePath = storeDirectory.appendingPathComponent("activity.sqlite").path
        let storeFlag = storeDirectory.standardizedFileURL == DayHelmStore.defaultDirectory.standardizedFileURL
            ? ""
            : " --store-dir \"\(storePath)\""

        let skeleton = DailyStatsMarkdownRenderer.renderCompactSkeleton(report)

        let goalSection: String
        switch preset {
        case .dailyReview:
            goalSection = """
            ## 分析任务：\(preset.title)（\(report.date)）
            请结合下方客观统计骨架，通过本地 `dayhelm` CLI 与只读 SQLite 查询下钻当天会话、事件与（如有）OCR 上下文，完成以下复盘：
            1. **专注结构与连续度诊断**：对比当日中位/最长连续块、5 档停留时长分布与近 7 日均值，指出真正进入深度推进的时段，以及碎片化高发的时段与诱因。
            2. **高频切换路径解剖**：针对高频切换路径（`A → B`）与乱切时段，结合该时段前后 `activity_events` 窗口标题/URL 区分「同一任务的合理多应用协同」与「无意识跑偏/打断」。
            3. **双向配额执行检查**：评估保底目标是否完成、封顶事务是否及时换挡（若无焦点项目，则基于 6 大活动大类比例分析）。
            4. **明日可执行的 2–3 条微调建议**：必须具体到时间段、事项边界或切换触发器，避免空泛说教；**不要输出主观“生产力评分”**。
            """
        case .workOutputDraft:
            goalSection = """
            ## 分析任务：\(preset.title)（\(report.date)）
            请结合下方客观统计骨架，使用本地 `dayhelm` CLI 与只读 SQLite 查询下钻当天的会话摘要、窗口标题、URL 与（如有）OCR 片段，还原实际工作产出并输出一份可直接微调使用的**工作日报草稿**：
            1. **按项目 / 事项聚合当日产出**：优先依据 `declared_task_id`、会话摘要（`analysis_title` / `entities` / `topics`）与关键窗口记录，梳理每个工作主线完成了什么（附客观投入时长）。
            2. **沟通、会议与杂务归档**：列出当日会议（`is_meeting = 1`）与跨沟通/运营处理的关键事务。
            3. **未竟事项 / 断点恢复线索**：根据当天最后停留的窗口/会话与备注（`focusSessions.note`），提炼下次接续工作的起点。
            4. **输出格式**：先给出一份精炼可复制的 Markdown 日报草稿，再附上需要我人工核对/补充的 1–3 个事实细节（严禁编造未在本地数据中出现的产出）。
            """
        }

        return """
        你现在作为我的本地个人工作分析助手，基于本机 DayHelm（日舵）采集的客观活动数据进行\(preset.title)。

        \(goalSection)

        ## 本地数据源与只读下钻方式
        - **数据目录**：`\(storePath)`
        - **当日快照文件**（只读）：`\(snapshotFullPath)`（包含 `budgets`、`focusSessions`、`enrichedSpans`、`metrics`）
        - **本地 SQLite 数据库**（只读）：`\(sqlitePath)`

        推荐先运行以下 CLI 命令获取结构化上下文：
        ```bash
        dayhelm stats --date \(report.date) --format json\(storeFlag)
        dayhelm sessions --date \(report.date) --format md\(storeFlag)
        dayhelm search <关键词> --limit 20 --format md\(storeFlag)
        ```

        如需进一步下钻具体事件或 OCR 片段，请**仅使用只读方式**查询 SQLite（例如）：
        ```bash
        sqlite3 -readonly "\(sqlitePath)" "SELECT id, datetime(started_at/1000,'unixepoch','localtime'), duration_ms/60000 AS mins, app_names, analysis_title, declared_task_id, is_meeting FROM activity_sessions WHERE date(started_at/1000,'unixepoch','localtime') = '\(report.date)' ORDER BY started_at ASC;"
        ```

        ## 只读与隐私脱敏护栏（必须遵守）
        1. **严格只读**：严禁修改、覆盖或删除 `\(storePath)` 下的任何文件（包括 `activity.sqlite`、`today.json`、`days/*.json`、`config.json`、`jev.key`）；查询 SQLite 必须使用 `-readonly` 且只执行 `SELECT`。
        2. **隐私边界**：命中脱敏规则（`redacted = true`）的记录仅保留应用名，绝不尝试猜测、反推或索要被脱敏的标题、URL 或密码/私密对话内容；若在数据中遇到掩码凭据（`***`），直接忽略并保持脱敏。
        3. **客观陈述**：所有时长、切换与产出结论必须严格引用观测到的会话/事件事实，不得虚构工作成果或给出主观“生产力打分”。

        ## 当日客观统计骨架（\(report.date)）
        \(skeleton)
        """
    }
}
