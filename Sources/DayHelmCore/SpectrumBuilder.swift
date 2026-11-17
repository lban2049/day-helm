import Foundation

public struct ThrashingWindow: Sendable, Equatable {
    public let startedAt: Date
    public let endedAt: Date
    public let switchCount: Int

    public init(startedAt: Date, endedAt: Date, switchCount: Int) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.switchCount = switchCount
    }
}

public enum SpectrumBuilder {
    public static let solidBlockMinimumMinutes: Double = 12.0
    public static let defaultIdleGapThresholdSeconds: TimeInterval = 60.0

    public static func detectThrashingWindows(
        spans: [EnrichedSpan],
        windowSeconds: TimeInterval = 600.0,
        minSwitches: Int = 10,
        maxAverageDwellSeconds: TimeInterval = 45.0
    ) -> [ThrashingWindow] {
        let sorted = spans.sorted { $0.startedAt < $1.startedAt }
        guard sorted.count >= minSwitches + 1 else {
            return []
        }

        // Precompute switch flags between consecutive spans.
        var switchAtIndex = Array(repeating: false, count: sorted.count)
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let gap = curr.startedAt.timeIntervalSince(prev.endedAt)
            if gap <= windowSeconds && isSwitch(from: prev, to: curr) {
                switchAtIndex[i] = true
            }
        }

        var rawWindows: [ThrashingWindow] = []
        var left = 0
        for right in 0..<sorted.count {
            let windowEnd = max(sorted[right].endedAt, sorted[right].startedAt)
            while left < right && windowEnd.timeIntervalSince(sorted[left].startedAt) > windowSeconds {
                left += 1
            }

            let spanCount = right - left + 1
            guard spanCount >= minSwitches + 1 else { continue }

            var switches = 0
            for idx in (left + 1)...right where switchAtIndex[idx] {
                switches += 1
            }
            guard switches >= minSwitches else { continue }

            let totalDwell = sorted[left...right].reduce(0.0) { acc, span in
                acc + max(1.0, span.durationSeconds)
            }
            let avgDwell = totalDwell / Double(spanCount)
            if avgDwell < maxAverageDwellSeconds {
                rawWindows.append(
                    ThrashingWindow(
                        startedAt: sorted[left].startedAt,
                        endedAt: windowEnd,
                        switchCount: switches
                    )
                )
            }
        }

        // Merge overlapping thrashing windows.
        guard !rawWindows.isEmpty else { return [] }
        let sortedWindows = rawWindows.sorted { $0.startedAt < $1.startedAt }
        var merged: [ThrashingWindow] = [sortedWindows[0]]
        for win in sortedWindows.dropFirst() {
            let last = merged[merged.count - 1]
            if win.startedAt <= last.endedAt {
                merged[merged.count - 1] = ThrashingWindow(
                    startedAt: last.startedAt,
                    endedAt: max(last.endedAt, win.endedAt),
                    switchCount: max(last.switchCount, win.switchCount)
                )
            } else {
                merged.append(win)
            }
        }
        return merged
    }

    public static func recentSwitchStats(
        spans: [EnrichedSpan],
        now: Date,
        windowSeconds: TimeInterval = 3600.0
    ) -> (switches: Int, switchesPerHour: Double) {
        let windowStart = now.addingTimeInterval(-windowSeconds)
        let recent = spans
            .filter { $0.endedAt >= windowStart && $0.startedAt <= now }
            .sorted { $0.startedAt < $1.startedAt }

        guard recent.count >= 2 else {
            return (0, 0.0)
        }

        var switches = 0
        for i in 1..<recent.count {
            if isSwitch(from: recent[i - 1], to: recent[i]) {
                switches += 1
            }
        }
        guard switches > 0 else {
            return (0, 0.0)
        }

        let firstTime = max(windowStart, recent.first!.startedAt)
        let lastTime = min(now, recent.last!.endedAt)
        let observedSeconds = max(300.0, min(windowSeconds, lastTime.timeIntervalSince(firstTime)))
        let rate = Double(switches) / (observedSeconds / 3600.0)
        return (switches, rate)
    }

    public static func build(
        spans: [EnrichedSpan],
        focusSessions: [FocusSessionRecord],
        budgets: [TaskBudget],
        now: Date,
        thrashingWindowSeconds: TimeInterval = 600.0,
        thrashingMinSwitches: Int = 10,
        thrashingMaxAvgDwellSeconds: TimeInterval = 45.0
    ) -> (segments: [SpectrumSegment], metrics: DayMetrics) {
        let budgetMap = Dictionary(uniqueKeysWithValues: budgets.map { ($0.taskId, $0) })

        struct RawInterval {
            var startedAt: Date
            var endedAt: Date
            var kind: SpectrumSegmentKind
        }

        var baseIntervals: [RawInterval] = []

        // 1. Add focus sessions as task intervals.
        for session in focusSessions {
            let end = max(session.startedAt, session.endedAt ?? now)
            guard end > session.startedAt else { continue }
            let kind = taskKind(for: session.taskId, budgetMap: budgetMap)
            baseIntervals.append(RawInterval(startedAt: session.startedAt, endedAt: end, kind: kind))
        }

        // 2. Add spans that have duration > 0 (or non-empty intervals).
        let sortedSpans = spans.sorted { $0.startedAt < $1.startedAt }
        for span in sortedSpans {
            let end = max(span.startedAt, span.endedAt)
            guard end > span.startedAt else { continue }
            let kind: SpectrumSegmentKind = span.declaredTaskId.map {
                taskKind(for: $0, budgetMap: budgetMap)
            } ?? .unassigned
            // Add span interval; focus sessions take priority over unassigned spans in overlap resolution.
            baseIntervals.append(RawInterval(startedAt: span.startedAt, endedAt: end, kind: kind))
        }

        guard !baseIntervals.isEmpty else {
            let (_, rate) = recentSwitchStats(spans: sortedSpans, now: now)
            return ([], DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: rate))
        }

        // 3. Detect thrashing windows from spans.
        let thrashingWindows = detectThrashingWindows(
            spans: sortedSpans,
            windowSeconds: thrashingWindowSeconds,
            minSwitches: thrashingMinSwitches,
            maxAverageDwellSeconds: thrashingMaxAvgDwellSeconds
        )

        // 4. Sweep-line partition across all interval boundaries so segments never overlap.
        var boundaries = Set<Date>()
        for interval in baseIntervals {
            boundaries.insert(interval.startedAt)
            boundaries.insert(interval.endedAt)
        }
        for tw in thrashingWindows {
            boundaries.insert(tw.startedAt)
            boundaries.insert(tw.endedAt)
        }
        let sortedPoints = boundaries.sorted()

        var rawSegments: [RawInterval] = []
        for i in 0..<(sortedPoints.count - 1) {
            let sliceStart = sortedPoints[i]
            let sliceEnd = sortedPoints[i + 1]
            guard sliceEnd > sliceStart else { continue }

            // Thrashing takes highest precedence for visual warning overlay.
            if let tw = thrashingWindows.first(where: { $0.startedAt <= sliceStart && $0.endedAt >= sliceEnd }) {
                rawSegments.append(RawInterval(startedAt: sliceStart, endedAt: sliceEnd, kind: .thrashing(switchCount: tw.switchCount)))
                continue
            }

            // Otherwise, task focus takes precedence over unassigned spans.
            let covering = baseIntervals.filter { $0.startedAt <= sliceStart && $0.endedAt >= sliceEnd }
            if let taskInterval = covering.first(where: { if case .task = $0.kind { return true }; return false }) {
                rawSegments.append(RawInterval(startedAt: sliceStart, endedAt: sliceEnd, kind: taskInterval.kind))
            } else if let other = covering.first {
                rawSegments.append(RawInterval(startedAt: sliceStart, endedAt: sliceEnd, kind: other.kind))
            } else {
                rawSegments.append(RawInterval(startedAt: sliceStart, endedAt: sliceEnd, kind: .idle))
            }
        }

        // 5. Coalesce adjacent segments with identical kinds (and bridge tiny gaps <= 60s if same kind, else keep idle).
        var coalesced: [RawInterval] = []
        for seg in rawSegments {
            if let last = coalesced.last, last.kind == seg.kind, abs(seg.startedAt.timeIntervalSince(last.endedAt)) < 0.001 {
                coalesced[coalesced.count - 1].endedAt = seg.endedAt
            } else {
                coalesced.append(seg)
            }
        }

        let segments: [SpectrumSegment] = coalesced.enumerated().map { idx, item in
            let minutes = item.endedAt.timeIntervalSince(item.startedAt) / 60.0
            return SpectrumSegment(
                id: "seg_\(idx)",
                startedAt: item.startedAt,
                endedAt: item.endedAt,
                kind: item.kind,
                durationMinutes: minutes
            )
        }

        // 6. Compute DayMetrics.
        var activeMinutes = 0.0
        var longestBlockMinutes = 0.0
        var solidBlocksCount = 0

        for seg in segments {
            switch seg.kind {
            case .task, .unassigned:
                activeMinutes += seg.durationMinutes
                if seg.durationMinutes > longestBlockMinutes {
                    longestBlockMinutes = seg.durationMinutes
                }
                if seg.durationMinutes >= solidBlockMinimumMinutes {
                    solidBlocksCount += 1
                }
            case .thrashing(let switchCount):
                _ = switchCount
                activeMinutes += seg.durationMinutes
            case .idle:
                break
            }
        }

        let (_, recentRate) = recentSwitchStats(spans: sortedSpans, now: now)
        let metrics = DayMetrics(
            activeMinutes: activeMinutes,
            longestBlockMinutes: longestBlockMinutes,
            solidBlocksCount: solidBlocksCount,
            recentSwitchesPerHour: recentRate
        )

        return (segments, metrics)
    }

    private static func taskKind(for taskId: String, budgetMap: [String: TaskBudget]) -> SpectrumSegmentKind {
        if let budget = budgetMap[taskId] {
            return .task(taskId: budget.taskId, displayName: budget.displayName, colorHex: budget.colorHex)
        }
        return .task(taskId: taskId, displayName: taskId, colorHex: "#3B82F6")
    }

    private static func isSwitch(from lhs: EnrichedSpan, to rhs: EnrichedSpan) -> Bool {
        lhs.appName != rhs.appName
            || lhs.bundleId != rhs.bundleId
            || lhs.windowTitle != rhs.windowTitle
    }
}
