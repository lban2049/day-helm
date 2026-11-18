import Foundation

public struct ThrashingWindow: Sendable, Equatable {
    public let startedAt: Date
    public let endedAt: Date
    public let switchCount: Int
    public let distinctContextCount: Int

    public init(startedAt: Date, endedAt: Date, switchCount: Int, distinctContextCount: Int = 0) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.switchCount = switchCount
        self.distinctContextCount = distinctContextCount
    }
}

public enum SpectrumBuilder {
    public static let solidBlockMinimumMinutes: Double = 12.0
    public static let defaultIdleGapThresholdSeconds: TimeInterval = 60.0

    public static func detectThrashingWindows(
        spans: [EnrichedSpan],
        budgets: [TaskBudget] = [],
        windowSeconds: TimeInterval = 600.0,
        minSwitches: Int = 10,
        maxAverageDwellSeconds: TimeInterval = 45.0,
        minDistinctContexts: Int = 4,
        minInterruptSwitches: Int = 4,
        minEffectiveDwellSeconds: TimeInterval = SwitchClassifier.defaultMinEffectiveDwellSeconds
    ) -> [ThrashingWindow] {
        let prepared = SwitchClassifier.prepareSequence(
            spans: spans,
            minEffectiveDwellSeconds: minEffectiveDwellSeconds
        )
        return detectThrashingWindows(
            prepared: prepared,
            normalizedBudgets: budgets.map(SwitchClassifier.NormalizedBudget.init),
            windowSeconds: windowSeconds,
            minSwitches: minSwitches,
            maxAverageDwellSeconds: maxAverageDwellSeconds,
            minDistinctContexts: minDistinctContexts,
            minInterruptSwitches: minInterruptSwitches
        )
    }

    internal final class IncrementalCache: @unchecked Sendable {
        struct RawInterval: Sendable {
            var order: Int
            var startedAt: Date
            var endedAt: Date
            var kind: SpectrumSegmentKind
            var isTask: Bool
        }

        let budgetsVersion: Int
        let sequenceState = SwitchClassifier.IncrementalSequenceState()

        var thrashingStableCount: Int = 0
        var cachedTaskIds: [String??] = []
        var prefixDwell: [Double] = [0.0]
        var prefixSwitches: [Int] = []
        var prefixUnboundedSwitches: [Int] = []
        var prefixInterruptSwitches: [Int] = []
        var left: Int = 0
        var contextCounts: [String: Int] = Dictionary(minimumCapacity: 32)
        var rawWindows: [ThrashingWindow] = []

        var stableSpanCount: Int = 0
        var spanIntervalsPrefix: [RawInterval] = []
        var spanIntervalsLast: RawInterval?

        init(budgetsVersion: Int) {
            self.budgetsVersion = budgetsVersion
        }
    }

    private static func detectThrashingWindowsIncremental(
        stablePrepared: [PreparedActivitySpan],
        tailPrepared: [PreparedActivitySpan],
        normalizedBudgets: [SwitchClassifier.NormalizedBudget],
        windowSeconds: TimeInterval,
        minSwitches: Int,
        maxAverageDwellSeconds: TimeInterval,
        minDistinctContexts: Int,
        minInterruptSwitches: Int,
        cache: IncrementalCache
    ) -> [ThrashingWindow] {
        let stableCount = stablePrepared.count
        let totalCount = stableCount + tailPrepared.count
        guard totalCount > 0 else {
            return []
        }

        @inline(__always)
        func preparedAt(_ idx: Int) -> PreparedActivitySpan {
            idx < stableCount ? stablePrepared[idx] : tailPrepared[idx - stableCount]
        }

        let prevStableCount = min(cache.thrashingStableCount, stableCount)
        if prevStableCount < cache.thrashingStableCount {
            cache.thrashingStableCount = 0
            cache.cachedTaskIds.removeAll(keepingCapacity: true)
            cache.prefixDwell = [0.0]
            cache.prefixSwitches.removeAll(keepingCapacity: true)
            cache.prefixUnboundedSwitches.removeAll(keepingCapacity: true)
            cache.prefixInterruptSwitches.removeAll(keepingCapacity: true)
            cache.left = 0
            cache.contextCounts.removeAll(keepingCapacity: true)
            cache.rawWindows.removeAll(keepingCapacity: true)
        }

        // Advance cache in-place for newly finalized stable items [prevStableCount ..< stableCount].
        if stableCount > prevStableCount {
            cache.cachedTaskIds.append(contentsOf: repeatElement(nil, count: stableCount - prevStableCount))
            cache.prefixSwitches.append(contentsOf: repeatElement(0, count: stableCount - prevStableCount))
            cache.prefixUnboundedSwitches.append(contentsOf: repeatElement(0, count: stableCount - prevStableCount))
            cache.prefixInterruptSwitches.append(contentsOf: repeatElement(0, count: stableCount - prevStableCount))
            cache.prefixDwell.reserveCapacity(stableCount + 1)

            @inline(__always)
            func stableTaskId(at idx: Int) -> String? {
                if let existing = cache.cachedTaskIds[idx] { return existing }
                let computed = SwitchClassifier.inferredTaskId(for: stablePrepared[idx], normalizedBudgets: normalizedBudgets)
                cache.cachedTaskIds[idx] = .some(computed)
                return computed
            }

            for i in prevStableCount..<stableCount {
                cache.prefixDwell.append(cache.prefixDwell[i] + max(1.0, stablePrepared[i].effectiveDwellSeconds))
            }

            let tStart = max(1, prevStableCount)
            if tStart < stableCount {
                for i in tStart..<stableCount {
                    var isSwitch = false
                    var isUnboundedSwitch = false
                    var isInterrupt = false
                    let prev = stablePrepared[i - 1]
                    let curr = stablePrepared[i]
                    if SwitchClassifier.isCrossTaskSwitch(
                        from: prev,
                        to: curr,
                        normalizedBudgets: normalizedBudgets,
                        lhsTokens: { prev.projectTokens },
                        rhsTokens: { curr.projectTokens },
                        lhsTaskId: { stableTaskId(at: i - 1) },
                        rhsTaskId: { stableTaskId(at: i) }
                    ) {
                        isUnboundedSwitch = true
                        let gap = curr.span.startedAt.timeIntervalSince(prev.span.endedAt)
                        if gap <= windowSeconds {
                            isSwitch = true
                            if SwitchClassifier.isInterruptTransition(from: prev, to: curr) {
                                isInterrupt = true
                            }
                        }
                    }
                    cache.prefixSwitches[i] = cache.prefixSwitches[i - 1] + (isSwitch ? 1 : 0)
                    cache.prefixUnboundedSwitches[i] = cache.prefixUnboundedSwitches[i - 1] + (isUnboundedSwitch ? 1 : 0)
                    cache.prefixInterruptSwitches[i] = cache.prefixInterruptSwitches[i - 1] + (isInterrupt ? 1 : 0)
                }
            }

            for right in prevStableCount..<stableCount {
                let rightKey = stablePrepared[right].contextKey
                cache.contextCounts[rightKey, default: 0] += 1

                let windowEnd = max(stablePrepared[right].span.endedAt, stablePrepared[right].span.startedAt)
                while cache.left < right && windowEnd.timeIntervalSince(stablePrepared[cache.left].span.startedAt) > windowSeconds {
                    let leftKey = stablePrepared[cache.left].contextKey
                    if let existing = cache.contextCounts[leftKey] {
                        if existing <= 1 {
                            cache.contextCounts.removeValue(forKey: leftKey)
                        } else {
                            cache.contextCounts[leftKey] = existing - 1
                        }
                    }
                    cache.left += 1
                }

                let spanCount = right - cache.left + 1
                if spanCount >= minSwitches + 1 {
                    let switches = cache.prefixSwitches[right] - cache.prefixSwitches[cache.left]
                    if switches >= minSwitches {
                        let interruptSwitches = cache.prefixInterruptSwitches[right] - cache.prefixInterruptSwitches[cache.left]
                        let distinctContextCount = cache.contextCounts.count
                        if distinctContextCount >= minDistinctContexts || interruptSwitches >= minInterruptSwitches {
                            let totalDwell = cache.prefixDwell[right + 1] - cache.prefixDwell[cache.left]
                            let avgDwell = totalDwell / Double(spanCount)
                            if avgDwell < maxAverageDwellSeconds {
                                cache.rawWindows.append(
                                    ThrashingWindow(
                                        startedAt: stablePrepared[cache.left].span.startedAt,
                                        endedAt: windowEnd,
                                        switchCount: switches,
                                        distinctContextCount: distinctContextCount
                                    )
                                )
                            }
                        }
                    }
                }
            }
            cache.thrashingStableCount = stableCount
        }

        // Now evaluate only the mutable tail [stableCount ..< totalCount] using local state.
        var allRawWindows = cache.rawWindows
        if !tailPrepared.isEmpty {
            var tailTaskIds = Array<String??>(repeating: nil, count: tailPrepared.count)
            @inline(__always)
            func anyTaskId(at idx: Int) -> String? {
                if idx < stableCount {
                    if let existing = cache.cachedTaskIds[idx] { return existing }
                    let computed = SwitchClassifier.inferredTaskId(for: stablePrepared[idx], normalizedBudgets: normalizedBudgets)
                    cache.cachedTaskIds[idx] = .some(computed)
                    return computed
                }
                let localIdx = idx - stableCount
                if let existing = tailTaskIds[localIdx] { return existing }
                let computed = SwitchClassifier.inferredTaskId(for: tailPrepared[localIdx], normalizedBudgets: normalizedBudgets)
                tailTaskIds[localIdx] = .some(computed)
                return computed
            }

            var tailDwell = Array(repeating: 0.0, count: tailPrepared.count + 1)
            tailDwell[0] = cache.prefixDwell[stableCount]
            var tailSwitches = Array(repeating: 0, count: tailPrepared.count)
            var tailInterrupts = Array(repeating: 0, count: tailPrepared.count)

            for k in 0..<tailPrepared.count {
                let i = stableCount + k
                tailDwell[k + 1] = tailDwell[k] + max(1.0, tailPrepared[k].effectiveDwellSeconds)
                if i > 0 {
                    let prevSwitches = (k == 0) ? cache.prefixSwitches[i - 1] : tailSwitches[k - 1]
                    let prevInterrupts = (k == 0) ? cache.prefixInterruptSwitches[i - 1] : tailInterrupts[k - 1]
                    var isSwitch = false
                    var isInterrupt = false
                    let prev = preparedAt(i - 1)
                    let curr = tailPrepared[k]
                    let gap = curr.span.startedAt.timeIntervalSince(prev.span.endedAt)
                    if gap <= windowSeconds && SwitchClassifier.isCrossTaskSwitch(
                        from: prev,
                        to: curr,
                        normalizedBudgets: normalizedBudgets,
                        lhsTokens: { prev.projectTokens },
                        rhsTokens: { curr.projectTokens },
                        lhsTaskId: { anyTaskId(at: i - 1) },
                        rhsTaskId: { anyTaskId(at: i) }
                    ) {
                        isSwitch = true
                        if SwitchClassifier.isInterruptTransition(from: prev, to: curr) {
                            isInterrupt = true
                        }
                    }
                    tailSwitches[k] = prevSwitches + (isSwitch ? 1 : 0)
                    tailInterrupts[k] = prevInterrupts + (isInterrupt ? 1 : 0)
                }
            }

            var localLeft = cache.left
            var localContextCounts = cache.contextCounts
            for k in 0..<tailPrepared.count {
                let right = stableCount + k
                let rightSpan = tailPrepared[k]
                let rightKey = rightSpan.contextKey
                localContextCounts[rightKey, default: 0] += 1

                let windowEnd = max(rightSpan.span.endedAt, rightSpan.span.startedAt)
                while localLeft < right && windowEnd.timeIntervalSince(preparedAt(localLeft).span.startedAt) > windowSeconds {
                    let leftKey = preparedAt(localLeft).contextKey
                    if let existing = localContextCounts[leftKey] {
                        if existing <= 1 {
                            localContextCounts.removeValue(forKey: leftKey)
                        } else {
                            localContextCounts[leftKey] = existing - 1
                        }
                    }
                    localLeft += 1
                }

                let spanCount = right - localLeft + 1
                guard spanCount >= minSwitches + 1 else { continue }

                let leftSwitches = localLeft < stableCount ? cache.prefixSwitches[localLeft] : tailSwitches[localLeft - stableCount]
                let switches = tailSwitches[k] - leftSwitches
                guard switches >= minSwitches else { continue }

                let leftInterrupts = localLeft < stableCount ? cache.prefixInterruptSwitches[localLeft] : tailInterrupts[localLeft - stableCount]
                let interruptSwitches = tailInterrupts[k] - leftInterrupts
                let distinctContextCount = localContextCounts.count
                guard distinctContextCount >= minDistinctContexts || interruptSwitches >= minInterruptSwitches else {
                    continue
                }

                let leftDwell = localLeft <= stableCount ? cache.prefixDwell[localLeft] : tailDwell[localLeft - stableCount]
                let totalDwell = tailDwell[k + 1] - leftDwell
                let avgDwell = totalDwell / Double(spanCount)
                if avgDwell < maxAverageDwellSeconds {
                    allRawWindows.append(
                        ThrashingWindow(
                            startedAt: preparedAt(localLeft).span.startedAt,
                            endedAt: windowEnd,
                            switchCount: switches,
                            distinctContextCount: distinctContextCount
                        )
                    )
                }
            }
        }

        guard totalCount >= minSwitches + 1, !allRawWindows.isEmpty else {
            return []
        }

        // Merge overlapping thrashing windows.
        let sortedWindows = allRawWindows.sorted { $0.startedAt < $1.startedAt }
        var merged: [ThrashingWindow] = [sortedWindows[0]]
        for win in sortedWindows.dropFirst() {
            let last = merged[merged.count - 1]
            if win.startedAt <= last.endedAt {
                merged[merged.count - 1] = ThrashingWindow(
                    startedAt: last.startedAt,
                    endedAt: max(last.endedAt, win.endedAt),
                    switchCount: max(last.switchCount, win.switchCount),
                    distinctContextCount: max(last.distinctContextCount, win.distinctContextCount)
                )
            } else {
                merged.append(win)
            }
        }
        return merged
    }

    private static func detectThrashingWindows(
        prepared: [PreparedActivitySpan],
        normalizedBudgets: [SwitchClassifier.NormalizedBudget],
        windowSeconds: TimeInterval,
        minSwitches: Int,
        maxAverageDwellSeconds: TimeInterval,
        minDistinctContexts: Int,
        minInterruptSwitches: Int
    ) -> [ThrashingWindow] {
        detectThrashingWindowsIncremental(
            stablePrepared: prepared,
            tailPrepared: [],
            normalizedBudgets: normalizedBudgets,
            windowSeconds: windowSeconds,
            minSwitches: minSwitches,
            maxAverageDwellSeconds: maxAverageDwellSeconds,
            minDistinctContexts: minDistinctContexts,
            minInterruptSwitches: minInterruptSwitches,
            cache: IncrementalCache(budgetsVersion: 0)
        )
    }

    public static func recentSwitchStats(
        spans: [EnrichedSpan],
        now: Date,
        budgets: [TaskBudget] = [],
        windowSeconds: TimeInterval = 3600.0,
        minEffectiveDwellSeconds: TimeInterval = SwitchClassifier.defaultMinEffectiveDwellSeconds
    ) -> (switches: Int, switchesPerHour: Double) {
        recentSwitchStats(
            sortedSpans: sortedByStart(spans),
            now: now,
            normalizedBudgets: budgets.map(SwitchClassifier.NormalizedBudget.init),
            windowSeconds: windowSeconds,
            minEffectiveDwellSeconds: minEffectiveDwellSeconds
        )
    }

    private static func recentSwitchStats(
        sortedSpans: [EnrichedSpan],
        now: Date,
        normalizedBudgets: [SwitchClassifier.NormalizedBudget],
        windowSeconds: TimeInterval = 3600.0,
        minEffectiveDwellSeconds: TimeInterval = SwitchClassifier.defaultMinEffectiveDwellSeconds
    ) -> (switches: Int, switchesPerHour: Double) {
        let windowStart = now.addingTimeInterval(-windowSeconds)
        var tailSlice: [EnrichedSpan] = []
        tailSlice.reserveCapacity(min(sortedSpans.count, 256))
        for i in stride(from: sortedSpans.count - 1, through: 0, by: -1) {
            let span = sortedSpans[i]
            if span.endedAt < windowStart {
                break
            }
            if span.startedAt <= now {
                tailSlice.append(span)
            }
        }
        let recent = Array(tailSlice.reversed())

        let prepared = SwitchClassifier.prepareSequence(
            spans: recent,
            minEffectiveDwellSeconds: minEffectiveDwellSeconds
        )
        guard prepared.count >= 2 else {
            return (0, 0.0)
        }

        var cachedTaskIds = Array<String??>(repeating: nil, count: prepared.count)

        func taskId(at idx: Int) -> String? {
            if let existing = cachedTaskIds[idx] { return existing }
            let computed = SwitchClassifier.inferredTaskId(for: prepared[idx], normalizedBudgets: normalizedBudgets)
            cachedTaskIds[idx] = .some(computed)
            return computed
        }

        var switches = 0
        for i in 1..<prepared.count {
            let prev = prepared[i - 1]
            let curr = prepared[i]
            if SwitchClassifier.isCrossTaskSwitch(
                from: prev,
                to: curr,
                normalizedBudgets: normalizedBudgets,
                lhsTokens: { prev.projectTokens },
                rhsTokens: { curr.projectTokens },
                lhsTaskId: { taskId(at: i - 1) },
                rhsTaskId: { taskId(at: i) }
            ) {
                switches += 1
            }
        }
        guard switches > 0 else {
            return (0, 0.0)
        }

        let firstTime = max(windowStart, prepared.first!.span.startedAt)
        let lastTime = min(now, prepared.last!.span.endedAt)
        let observedSeconds = max(600.0, min(windowSeconds, lastTime.timeIntervalSince(firstTime)))
        let rate = Double(switches) / (observedSeconds / 3600.0)
        return (switches, rate)
    }

    private static func recentSwitchStatsFromPrepared(
        stablePrepared: [PreparedActivitySpan],
        tailPrepared: [PreparedActivitySpan],
        now: Date,
        normalizedBudgets: [SwitchClassifier.NormalizedBudget],
        cache: IncrementalCache,
        windowSeconds: TimeInterval = 3600.0
    ) -> (switches: Int, switchesPerHour: Double) {
        let totalCount = stablePrepared.count + tailPrepared.count
        guard totalCount >= 2 else { return (0, 0.0) }

        let windowStart = now.addingTimeInterval(-windowSeconds)
        @inline(__always)
        func preparedAt(_ idx: Int) -> PreparedActivitySpan {
            idx < stablePrepared.count ? stablePrepared[idx] : tailPrepared[idx - stablePrepared.count]
        }

        var startIdx = totalCount
        var endIdx = -1
        for i in stride(from: totalCount - 1, through: 0, by: -1) {
            let item = preparedAt(i)
            if item.span.endedAt < windowStart {
                break
            }
            if item.span.startedAt <= now {
                if endIdx == -1 { endIdx = i }
                startIdx = i
            }
        }
        guard endIdx >= startIdx + 1 else { return (0, 0.0) }

        var switches = 0
        let stableCount = stablePrepared.count
        if startIdx < stableCount && cache.prefixUnboundedSwitches.count == stableCount {
            let stableEnd = min(endIdx, stableCount - 1)
            if stableEnd > startIdx {
                switches += cache.prefixUnboundedSwitches[stableEnd] - cache.prefixUnboundedSwitches[startIdx]
            }
        }

        let tailLoopStart = max(startIdx + 1, (cache.prefixUnboundedSwitches.count == stableCount) ? stableCount : startIdx + 1)
        if tailLoopStart <= endIdx {
            for i in tailLoopStart...endIdx {
                let prev = preparedAt(i - 1)
                let curr = preparedAt(i)
                if SwitchClassifier.isCrossTaskSwitch(
                    from: prev,
                    to: curr,
                    normalizedBudgets: normalizedBudgets,
                    lhsTokens: { prev.projectTokens },
                    rhsTokens: { curr.projectTokens },
                    lhsTaskId: { SwitchClassifier.inferredTaskId(for: prev, normalizedBudgets: normalizedBudgets) },
                    rhsTaskId: { SwitchClassifier.inferredTaskId(for: curr, normalizedBudgets: normalizedBudgets) }
                ) {
                    switches += 1
                }
            }
        }
        guard switches > 0 else { return (0, 0.0) }

        let firstTime = max(windowStart, preparedAt(startIdx).span.startedAt)
        let lastTime = min(now, preparedAt(endIdx).span.endedAt)
        let observedSeconds = max(600.0, min(windowSeconds, lastTime.timeIntervalSince(firstTime)))
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
        thrashingMaxAvgDwellSeconds: TimeInterval = 45.0,
        thrashingMinDistinctContexts: Int = 4,
        thrashingMinInterruptSwitches: Int = 4,
        thrashingMinEffectiveDwellSeconds: TimeInterval = SwitchClassifier.defaultMinEffectiveDwellSeconds
    ) -> (segments: [SpectrumSegment], metrics: DayMetrics) {
        let result = buildIncremental(
            spans: spans,
            focusSessions: focusSessions,
            budgets: budgets,
            budgetsVersion: 0,
            now: now,
            cache: nil,
            thrashingWindowSeconds: thrashingWindowSeconds,
            thrashingMinSwitches: thrashingMinSwitches,
            thrashingMaxAvgDwellSeconds: thrashingMaxAvgDwellSeconds,
            thrashingMinDistinctContexts: thrashingMinDistinctContexts,
            thrashingMinInterruptSwitches: thrashingMinInterruptSwitches,
            thrashingMinEffectiveDwellSeconds: thrashingMinEffectiveDwellSeconds
        )
        return (result.segments, result.metrics)
    }

    internal static func buildIncremental(
        spans: [EnrichedSpan],
        focusSessions: [FocusSessionRecord],
        budgets: [TaskBudget],
        budgetsVersion: Int,
        now: Date,
        cache: IncrementalCache?,
        thrashingWindowSeconds: TimeInterval = 600.0,
        thrashingMinSwitches: Int = 10,
        thrashingMaxAvgDwellSeconds: TimeInterval = 45.0,
        thrashingMinDistinctContexts: Int = 4,
        thrashingMinInterruptSwitches: Int = 4,
        thrashingMinEffectiveDwellSeconds: TimeInterval = SwitchClassifier.defaultMinEffectiveDwellSeconds
    ) -> (segments: [SpectrumSegment], metrics: DayMetrics, nextCache: IncrementalCache?) {
        let budgetMap = Dictionary(uniqueKeysWithValues: budgets.map { ($0.taskId, $0) })
        let normalizedBudgets = budgets.map(SwitchClassifier.NormalizedBudget.init)

        typealias RawInterval = IncrementalCache.RawInterval

        var baseIntervals: [RawInterval] = []
        baseIntervals.reserveCapacity(focusSessions.count + 16)

        // 1. Add focus sessions as task intervals.
        for session in focusSessions {
            let end = max(session.startedAt, session.endedAt ?? now)
            guard end > session.startedAt else { continue }
            let kind = taskKind(for: session.taskId, budgetMap: budgetMap)
            baseIntervals.append(
                RawInterval(
                    order: baseIntervals.count,
                    startedAt: session.startedAt,
                    endedAt: end,
                    kind: kind,
                    isTask: true
                )
            )
        }

        // 2. Add spans that have duration > 0 (coalescing adjacent same-kind spans to shrink sweep-line points).
        let sortedSpans = sortedByStart(spans)
        let focusIntervalCount = baseIntervals.count

        let activeCache: IncrementalCache
        if let cache, cache.budgetsVersion == budgetsVersion, sortedSpans.count >= cache.stableSpanCount {
            activeCache = cache
        } else {
            activeCache = IncrementalCache(budgetsVersion: budgetsVersion)
        }

        let spanStartIdx = activeCache.stableSpanCount
        var tailSpanIntervals: [RawInterval] = []
        if let last = activeCache.spanIntervalsLast {
            tailSpanIntervals.append(last)
        }

        let nextStableSpanCount = max(0, sortedSpans.count - 1)
        var didAdvanceSpanPrefix = false

        func advanceSpanPrefixIfNeeded(at idx: Int) {
            guard !didAdvanceSpanPrefix,
                  nextStableSpanCount > 0,
                  nextStableSpanCount > activeCache.stableSpanCount,
                  idx == nextStableSpanCount else { return }
            didAdvanceSpanPrefix = true
            if tailSpanIntervals.count > 1 {
                activeCache.spanIntervalsPrefix.append(contentsOf: tailSpanIntervals.dropLast())
                tailSpanIntervals = [tailSpanIntervals.last!]
            }
            activeCache.spanIntervalsLast = tailSpanIntervals.last
            activeCache.stableSpanCount = nextStableSpanCount
        }

        for idx in spanStartIdx..<sortedSpans.count {
            advanceSpanPrefixIfNeeded(at: idx)
            let span = sortedSpans[idx]
            let end = max(span.startedAt, span.endedAt)
            guard end > span.startedAt else { continue }
            let kind: SpectrumSegmentKind = span.declaredTaskId.map {
                taskKind(for: $0, budgetMap: budgetMap)
            } ?? .unassigned
            let isTask: Bool
            if case .task = kind { isTask = true } else { isTask = false }
            if let last = tailSpanIntervals.last,
               last.kind == kind,
               span.startedAt.timeIntervalSince(last.endedAt) <= 0.001 {
                if end > last.endedAt {
                    tailSpanIntervals[tailSpanIntervals.count - 1].endedAt = end
                }
                continue
            }
            let nextOrder = activeCache.spanIntervalsPrefix.count + tailSpanIntervals.count
            tailSpanIntervals.append(
                RawInterval(
                    order: nextOrder,
                    startedAt: span.startedAt,
                    endedAt: end,
                    kind: kind,
                    isTask: isTask
                )
            )
        }
        advanceSpanPrefixIfNeeded(at: sortedSpans.count)

        baseIntervals.reserveCapacity(focusIntervalCount + activeCache.spanIntervalsPrefix.count + tailSpanIntervals.count)
        for item in activeCache.spanIntervalsPrefix {
            baseIntervals.append(
                RawInterval(
                    order: focusIntervalCount + item.order,
                    startedAt: item.startedAt,
                    endedAt: item.endedAt,
                    kind: item.kind,
                    isTask: item.isTask
                )
            )
        }
        for item in tailSpanIntervals {
            baseIntervals.append(
                RawInterval(
                    order: focusIntervalCount + item.order,
                    startedAt: item.startedAt,
                    endedAt: item.endedAt,
                    kind: item.kind,
                    isTask: item.isTask
                )
            )
        }

        guard !baseIntervals.isEmpty else {
            let (_, rate) = recentSwitchStats(
                sortedSpans: sortedSpans,
                now: now,
                normalizedBudgets: normalizedBudgets,
                minEffectiveDwellSeconds: thrashingMinEffectiveDwellSeconds
            )
            return ([], DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: rate), nil)
        }

        // 3. Prepare sequence once and detect thrashing windows from spans.
        let tailPrepared = SwitchClassifier.prepareSequenceIncremental(
            sortedSpans: sortedSpans,
            state: activeCache.sequenceState,
            minEffectiveDwellSeconds: thrashingMinEffectiveDwellSeconds
        )
        let thrashingWindows = detectThrashingWindowsIncremental(
            stablePrepared: activeCache.sequenceState.coalescedStable,
            tailPrepared: tailPrepared,
            normalizedBudgets: normalizedBudgets,
            windowSeconds: thrashingWindowSeconds,
            minSwitches: thrashingMinSwitches,
            maxAverageDwellSeconds: thrashingMaxAvgDwellSeconds,
            minDistinctContexts: thrashingMinDistinctContexts,
            minInterruptSwitches: thrashingMinInterruptSwitches,
            cache: activeCache
        )

        let nextCache: IncrementalCache? = (nextStableSpanCount > 0) ? activeCache : nil

        // 4. O(N log N) sweep-line partition across all interval boundaries so segments never overlap.
        var boundaries = Set<Date>(minimumCapacity: (baseIntervals.count + thrashingWindows.count) * 2)
        for interval in baseIntervals {
            boundaries.insert(interval.startedAt)
            boundaries.insert(interval.endedAt)
        }
        for tw in thrashingWindows {
            boundaries.insert(tw.startedAt)
            boundaries.insert(tw.endedAt)
        }
        let sortedPoints = boundaries.sorted()

        let sortedIntervals = baseIntervals.sorted {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.order < $1.order
        }
        var intervalCursor = 0
        var activeIntervals: [RawInterval] = []
        var twCursor = 0

        struct CoalescedInterval {
            var startedAt: Date
            var endedAt: Date
            var kind: SpectrumSegmentKind
        }

        var coalesced: [CoalescedInterval] = []
        coalesced.reserveCapacity(sortedPoints.count)

        for i in 0..<(sortedPoints.count - 1) {
            let sliceStart = sortedPoints[i]
            let sliceEnd = sortedPoints[i + 1]
            guard sliceEnd > sliceStart else { continue }

            while twCursor < thrashingWindows.count && thrashingWindows[twCursor].endedAt <= sliceStart {
                twCursor += 1
            }

            if !activeIntervals.isEmpty {
                activeIntervals.removeAll { $0.endedAt <= sliceStart }
            }
            while intervalCursor < sortedIntervals.count && sortedIntervals[intervalCursor].startedAt <= sliceStart {
                let candidate = sortedIntervals[intervalCursor]
                intervalCursor += 1
                if candidate.endedAt > sliceStart {
                    activeIntervals.append(candidate)
                }
            }

            // Thrashing takes highest precedence for visual warning overlay.
            let sliceKind: SpectrumSegmentKind
            if twCursor < thrashingWindows.count,
               thrashingWindows[twCursor].startedAt <= sliceStart,
               thrashingWindows[twCursor].endedAt >= sliceEnd {
                sliceKind = .thrashing(switchCount: thrashingWindows[twCursor].switchCount)
            } else {
                var bestTask: RawInterval?
                var bestOther: RawInterval?
                for active in activeIntervals where active.startedAt <= sliceStart && active.endedAt >= sliceEnd {
                    if active.isTask {
                        if bestTask == nil || active.order < bestTask!.order {
                            bestTask = active
                        }
                    } else if bestOther == nil || active.order < bestOther!.order {
                        bestOther = active
                    }
                }
                if let bestTask {
                    sliceKind = bestTask.kind
                } else if let bestOther {
                    sliceKind = bestOther.kind
                } else {
                    sliceKind = .idle
                }
            }

            // 5. Coalesce adjacent segments with identical kinds inline.
            if let last = coalesced.last, last.kind == sliceKind, abs(sliceStart.timeIntervalSince(last.endedAt)) < 0.001 {
                coalesced[coalesced.count - 1].endedAt = sliceEnd
            } else {
                coalesced.append(CoalescedInterval(startedAt: sliceStart, endedAt: sliceEnd, kind: sliceKind))
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

        let (_, recentRate) = recentSwitchStatsFromPrepared(
            stablePrepared: activeCache.sequenceState.coalescedStable,
            tailPrepared: tailPrepared,
            now: now,
            normalizedBudgets: normalizedBudgets,
            cache: activeCache
        )
        let metrics = DayMetrics(
            activeMinutes: activeMinutes,
            longestBlockMinutes: longestBlockMinutes,
            solidBlocksCount: solidBlocksCount,
            recentSwitchesPerHour: recentRate
        )

        return (segments, metrics, nextCache)
    }

    private static func sortedByStart(_ spans: [EnrichedSpan]) -> [EnrichedSpan] {
        guard spans.count > 1 else { return spans }
        for i in 1..<spans.count where spans[i].startedAt < spans[i - 1].startedAt {
            return spans.sorted { $0.startedAt < $1.startedAt }
        }
        return spans
    }

    private static func taskKind(for taskId: String, budgetMap: [String: TaskBudget]) -> SpectrumSegmentKind {
        if let budget = budgetMap[taskId] {
            return .task(taskId: budget.taskId, displayName: budget.displayName, colorHex: budget.colorHex)
        }
        return .task(taskId: taskId, displayName: taskId, colorHex: "#3B82F6")
    }
}
