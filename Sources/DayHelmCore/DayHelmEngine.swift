import Foundation

public struct DayHelmEngineConfig: Sendable, Equatable, Codable {
    public var idleThresholdSeconds: TimeInterval
    public var pulsetimeSeconds: TimeInterval
    public var maxTickGapSeconds: TimeInterval?
    public var driftWindowSeconds: TimeInterval
    public var unassignedPromptSeconds: TimeInterval
    public var thrashingWindowSeconds: TimeInterval
    public var thrashingMinSwitches: Int
    public var thrashingMaxAvgDwellSeconds: TimeInterval
    public var thrashingMinDistinctContexts: Int
    public var thrashingMinInterruptSwitches: Int
    public var thrashingMinEffectiveDwellSeconds: TimeInterval
    public var thrashingCooldownSeconds: TimeInterval
    public var privacyConfig: PrivacyRedactorConfig

    public static let `default` = DayHelmEngineConfig()

    public init(
        idleThresholdSeconds: TimeInterval = 180,
        pulsetimeSeconds: TimeInterval = 60,
        maxTickGapSeconds: TimeInterval? = nil,
        driftWindowSeconds: TimeInterval = 240,
        unassignedPromptSeconds: TimeInterval = 600,
        thrashingWindowSeconds: TimeInterval = 600,
        thrashingMinSwitches: Int = 10,
        thrashingMaxAvgDwellSeconds: TimeInterval = 45,
        thrashingMinDistinctContexts: Int = 4,
        thrashingMinInterruptSwitches: Int = 4,
        thrashingMinEffectiveDwellSeconds: TimeInterval = 4.0,
        thrashingCooldownSeconds: TimeInterval = 1800,
        privacyConfig: PrivacyRedactorConfig = .default
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.pulsetimeSeconds = pulsetimeSeconds
        self.maxTickGapSeconds = maxTickGapSeconds
        self.driftWindowSeconds = driftWindowSeconds
        self.unassignedPromptSeconds = unassignedPromptSeconds
        self.thrashingWindowSeconds = thrashingWindowSeconds
        self.thrashingMinSwitches = thrashingMinSwitches
        self.thrashingMaxAvgDwellSeconds = thrashingMaxAvgDwellSeconds
        self.thrashingMinDistinctContexts = thrashingMinDistinctContexts
        self.thrashingMinInterruptSwitches = thrashingMinInterruptSwitches
        self.thrashingMinEffectiveDwellSeconds = thrashingMinEffectiveDwellSeconds
        self.thrashingCooldownSeconds = thrashingCooldownSeconds
        self.privacyConfig = privacyConfig
    }
}

public final class DayHelmEngine: @unchecked Sendable {
    private struct DriftCandidate {
        let taskId: String
        let startedAt: Date
        var alertEmitted: Bool
    }

    private let lock = NSLock()
    private let clock: any DayHelmClock
    public let config: DayHelmEngineConfig
    private var _privacyConfig: PrivacyRedactorConfig

    private var _currentDateString: String
    private var _focusState: FocusSessionState = .unassigned
    private var _budgets: [TaskBudget]
    private var _focusSessions: [FocusSessionRecord] = []
    private var _enrichedSpans: [EnrichedSpan] = []
    private var _lastSample: ActivitySample?
    private var _pendingAlerts: [SupervisorAlert] = []

    private var activeSessionIndex: Int?
    private var lastProgressTimestamp: Date?
    private var sessionCounter: Int = 0
    private var alertCounter: Int = 0

    // Auto-tracking non-budget & Layer-1 ActivityMode state
    private var _autoTrackingActive: Bool = false
    private var _autoPausedByAbsence: Bool = false
    private var _activeNonBudgetActivity: AutoNonBudgetActivity?
    private var _activeActivityMode: ActivityMode?
    private var _nonBudgetLastTimestamp: Date?
    private var _nonBudgetSegmentStartedAt: Date?
    private var _nonBudgetSegmentMinutes: Double = 0.0
    private var _otherWorkMinutes: Double = 0.0
    private var _nonWorkMinutes: Double = 0.0
    private var _activityModeMinutes: [String: Double] = [:]
    private var _currentSemanticGroup: String?

    // Alert tracking / hysteresis state
    private var capAlertEmittedForTask: Set<String> = []
    private var targetAlertEmittedForTask: Set<String> = []
    private var snoozeUntilByTask: [String: Date] = [:]
    private var globalSnoozeUntil: Date?

    private var unassignedActiveStart: Date?
    private var unassignedPromptEmitted: Bool = false
    private var unassignedSnoozeUntil: Date?

    private var driftCandidate: DriftCandidate?
    private var lastThrashingAlertAt: Date?

    private var _normalizedBudgets: [SwitchClassifier.NormalizedBudget]
    private var _budgetsVersion: Int = 0
    private var _stateVersion: UInt64 = 0
    private var _cachedSpectrum: (version: UInt64, tsMs: Int64, segments: [SpectrumSegment], metrics: DayMetrics)?
    private var _incrementalSpectrumCache: SpectrumBuilder.IncrementalCache?

    public var effectivePrivacyConfig: PrivacyRedactorConfig {
        lock.lock(); defer { lock.unlock() }
        return _privacyConfig
    }

    public var currentDateString: String {
        lock.lock(); defer { lock.unlock() }
        return _currentDateString
    }

    public var focusState: FocusSessionState {
        lock.lock(); defer { lock.unlock() }
        return _focusState
    }

    public var budgets: [TaskBudget] {
        lock.lock(); defer { lock.unlock() }
        return _budgets
    }

    public var focusSessions: [FocusSessionRecord] {
        lock.lock(); defer { lock.unlock() }
        return _focusSessions
    }

    public var enrichedSpans: [EnrichedSpan] {
        lock.lock(); defer { lock.unlock() }
        return _enrichedSpans
    }

    public var lastSample: ActivitySample? {
        lock.lock(); defer { lock.unlock() }
        return _lastSample
    }

    public var pendingAlerts: [SupervisorAlert] {
        lock.lock(); defer { lock.unlock() }
        return _pendingAlerts
    }

    public var budgetsVersion: Int {
        lock.lock(); defer { lock.unlock() }
        return _budgetsVersion
    }

    public var autoTrackingActive: Bool {
        lock.lock(); defer { lock.unlock() }
        return _autoTrackingActive
    }

    public var activeNonBudgetActivity: AutoNonBudgetActivity? {
        lock.lock(); defer { lock.unlock() }
        return _activeNonBudgetActivity
    }

    public var activeActivityMode: ActivityMode? {
        lock.lock(); defer { lock.unlock() }
        return _activeActivityMode
    }

    public var otherWorkMinutes: Double {
        lock.lock(); defer { lock.unlock() }
        return _otherWorkMinutes
    }

    public var nonWorkMinutes: Double {
        lock.lock(); defer { lock.unlock() }
        return _nonWorkMinutes
    }

    public var activityModeMinutes: [String: Double] {
        lock.lock(); defer { lock.unlock() }
        return _activityModeMinutes
    }

    public func minutes(for mode: ActivityMode) -> Double {
        lock.lock(); defer { lock.unlock() }
        return _activityModeMinutes[mode.rawValue, default: 0.0]
    }

    public func setAutoTrackingActive(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _autoTrackingActive = enabled
        if !enabled {
            _activeNonBudgetActivity = nil
            _activeActivityMode = nil
            _nonBudgetLastTimestamp = nil
            _currentSemanticGroup = nil
        }
    }

    /// Stamps recent spans matching `contextKey` with a semanticGroup (used by SwitchClassifier).
    public func stampSemanticGroup(_ semanticGroup: String, forContextKey contextKey: String, withinSeconds: TimeInterval = 60.0, at now: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = now ?? clock.now()
        _currentSemanticGroup = semanticGroup
        var changed = false
        for i in stride(from: _enrichedSpans.count - 1, through: 0, by: -1) {
            if ts.timeIntervalSince(_enrichedSpans[i].endedAt) > withinSeconds {
                break
            }
            if SwitchClassifier.canonicalContextKey(for: _enrichedSpans[i]) == contextKey {
                if _enrichedSpans[i].semanticGroup != semanticGroup {
                    _enrichedSpans[i].semanticGroup = semanticGroup
                    changed = true
                }
            }
        }
        if changed {
            _incrementalSpectrumCache = nil
            _cachedSpectrum = nil
            _stateVersion &+= 1
        }
    }

    public func applyAutoCategory(_ categoryId: String, activityMode: ActivityMode? = nil, at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        _autoPausedByAbsence = false
        if categoryId == AutoActivityIds.otherWork {
            closeActiveSessionLocked(at: ts, closingNote: nil)
            _focusState = .unassigned
            _activeNonBudgetActivity = .otherWork
            _activeActivityMode = activityMode ?? .commsAdmin
            _nonBudgetLastTimestamp = ts
            _nonBudgetSegmentStartedAt = ts
            _nonBudgetSegmentMinutes = 0.0
            _currentSemanticGroup = "mode:\((_activeActivityMode ?? .commsAdmin).rawValue)"
            driftCandidate = nil
            unassignedActiveStart = nil
            unassignedPromptEmitted = false
            _stateVersion &+= 1
            return
        }
        if categoryId == AutoActivityIds.nonWork {
            closeActiveSessionLocked(at: ts, closingNote: nil)
            _focusState = .unassigned
            _activeNonBudgetActivity = .nonWork
            _activeActivityMode = .breakTime
            _nonBudgetLastTimestamp = ts
            _nonBudgetSegmentStartedAt = ts
            _nonBudgetSegmentMinutes = 0.0
            _currentSemanticGroup = "break"
            driftCandidate = nil
            unassignedActiveStart = nil
            unassignedPromptEmitted = false
            _stateVersion &+= 1
            return
        }
        if let mode = AutoActivityIds.activityMode(from: categoryId) {
            closeActiveSessionLocked(at: ts, closingNote: nil)
            _focusState = .unassigned
            _activeActivityMode = mode
            _activeNonBudgetActivity = mode.isDistraction ? .nonWork : .otherWork
            _nonBudgetLastTimestamp = ts
            _nonBudgetSegmentStartedAt = ts
            _nonBudgetSegmentMinutes = 0.0
            _currentSemanticGroup = mode.isDistraction ? "break" : "mode:\(mode.rawValue)"
            driftCandidate = nil
            unassignedActiveStart = nil
            unassignedPromptEmitted = false
            _stateVersion &+= 1
            return
        }
        guard _budgets.contains(where: { $0.taskId == categoryId }) else {
            return
        }
        _activeNonBudgetActivity = nil
        _activeActivityMode = activityMode
        _nonBudgetLastTimestamp = nil
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        _currentSemanticGroup = (activityMode == .breakTime) ? "break" : "proj:\(categoryId)"
        if case .focusing(let currentTaskId, _) = _focusState, currentTaskId == categoryId {
            return
        }
        closeActiveSessionLocked(at: ts, closingNote: nil)
        openNewSessionLocked(taskId: categoryId, note: nil, at: ts)
    }

    public init(
        budgets: [TaskBudget] = TimeAuditConfigLoader.defaultBudgets,
        clock: any DayHelmClock = SystemClock(),
        config: DayHelmEngineConfig = .default
    ) {
        self.clock = clock
        self.config = config
        self._privacyConfig = config.privacyConfig
        self._budgets = budgets
        self._normalizedBudgets = budgets.map(SwitchClassifier.NormalizedBudget.init)
        self._currentDateString = DayHelmDateFormatting.dayString(from: clock.now())
    }

    public convenience init(
        snapshot: DayHelmDaySnapshot,
        budgets: [TaskBudget],
        clock: any DayHelmClock = SystemClock(),
        config: DayHelmEngineConfig = .default
    ) {
        self.init(budgets: budgets, clock: clock, config: config)
        lock.lock()
        defer { lock.unlock() }
        self._currentDateString = snapshot.date
        self._focusSessions = snapshot.focusSessions
        self._enrichedSpans = snapshot.enrichedSpans
        self.sessionCounter = snapshot.focusSessions.count
        self._otherWorkMinutes = max(0, snapshot.otherWorkMinutes ?? 0)
        self._nonWorkMinutes = max(0, snapshot.nonWorkMinutes ?? 0)
        self._activityModeMinutes = snapshot.activityModeMinutes ?? [:]
        // Startup grace period (120s) after restoring from today.json so restarting the app
        // does not immediately fire a stale high-frequency switch alert from historical spans.
        let startupGraceSeconds: TimeInterval = 120.0
        if config.thrashingCooldownSeconds > startupGraceSeconds {
            self.lastThrashingAlertAt = clock.now().addingTimeInterval(-(config.thrashingCooldownSeconds - startupGraceSeconds))
        }

        if let restoredState = snapshot.focusState {
            self._focusState = restoredState
        } else if let active = snapshot.activeFocus {
            self._focusState = .focusing(taskId: active.taskId, startedAt: active.startedAt)
        } else {
            self._focusState = .unassigned
        }

        if case .focusing(let taskId, _) = self._focusState {
            if let openIdx = self._focusSessions.lastIndex(where: { $0.taskId == taskId && $0.endedAt == nil }) {
                self.activeSessionIndex = openIdx
                self.lastProgressTimestamp = self._focusSessions[openIdx].startedAt.addingTimeInterval(self._focusSessions[openIdx].minutes * 60.0)
            }
        }
        self._incrementalSpectrumCache = nil
        self._cachedSpectrum = nil
        self._budgetsVersion &+= 1
        self._stateVersion &+= 1
    }

    public func updateBudgets(_ newBudgets: [TaskBudget]) {
        lock.lock()
        defer { lock.unlock() }
        _budgets = newBudgets
        _normalizedBudgets = newBudgets.map(SwitchClassifier.NormalizedBudget.init)
        _budgetsVersion &+= 1
        _incrementalSpectrumCache = nil
        _stateVersion &+= 1
    }

    public func updatePrivacyConfig(_ newPrivacyConfig: PrivacyRedactorConfig) {
        lock.lock()
        defer { lock.unlock() }
        _privacyConfig = newPrivacyConfig
    }

    @discardableResult
    public func addTask(
        taskId: String? = nil,
        displayName: String,
        shortName: String? = nil,
        description: String? = nil,
        colorHex: String,
        targetMinutes: Int?,
        capMinutes: Int?,
        keywords: [String],
        appBundleIds: [String] = [],
        domains: [String] = []
    ) -> TaskBudget {
        lock.lock()
        defer { lock.unlock() }

        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "未命名事项" : trimmedName
        let trimmedColor = colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalColor = trimmedColor.isEmpty ? "#3B82F6" : trimmedColor
        let cleanedKeywords = Self.cleanKeywords(keywords)
        let cleanedBundleIds = Self.cleanKeywords(appBundleIds)
        let cleanedDomains = Self.cleanKeywords(domains)

        let existingIds = Set(_budgets.map(\.taskId))
        let finalId = Self.makeUniqueTaskId(preferredId: taskId, displayName: finalName, existingIds: existingIds)

        let created = TaskBudget(
            taskId: finalId,
            displayName: finalName,
            shortName: shortName,
            description: description,
            colorHex: finalColor,
            targetMinutes: targetMinutes,
            capMinutes: capMinutes,
            keywords: cleanedKeywords,
            appBundleIds: cleanedBundleIds,
            domains: cleanedDomains
        )
        _budgets.append(created)
        _normalizedBudgets.append(SwitchClassifier.NormalizedBudget(budget: created))
        _budgetsVersion &+= 1
        _incrementalSpectrumCache = nil
        _stateVersion &+= 1
        return created
    }

    @discardableResult
    public func updateTask(_ updatedBudget: TaskBudget) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let idx = _budgets.firstIndex(where: { $0.taskId == updatedBudget.taskId }) else {
            return false
        }
        let trimmedName = updatedBudget.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? _budgets[idx].displayName : trimmedName
        let trimmedColor = updatedBudget.colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalColor = trimmedColor.isEmpty ? _budgets[idx].colorHex : trimmedColor
        let cleanedKeywords = Self.cleanKeywords(updatedBudget.keywords)

        let normalized = TaskBudget(
            taskId: updatedBudget.taskId,
            displayName: finalName,
            shortName: updatedBudget.shortName,
            description: updatedBudget.description,
            colorHex: finalColor,
            targetMinutes: updatedBudget.targetMinutes,
            capMinutes: updatedBudget.capMinutes,
            keywords: cleanedKeywords,
            appBundleIds: Self.cleanKeywords(updatedBudget.appBundleIds),
            domains: Self.cleanKeywords(updatedBudget.domains)
        )
        _budgets[idx] = normalized
        _normalizedBudgets[idx] = SwitchClassifier.NormalizedBudget(budget: normalized)
        _budgetsVersion &+= 1
        _incrementalSpectrumCache = nil
        _stateVersion &+= 1

        let focused = focusedMinutesLocked(for: normalized.taskId)
        if let cap = normalized.capMinutes, focused < Double(cap) {
            capAlertEmittedForTask.remove(normalized.taskId)
        }
        if let target = normalized.targetMinutes, focused < Double(target) {
            targetAlertEmittedForTask.remove(normalized.taskId)
        }
        return true
    }

    @discardableResult
    public func deleteTask(taskId: String, at date: Date? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let originalCount = _budgets.count
        _budgets.removeAll { $0.taskId == taskId }
        guard _budgets.count != originalCount else {
            return false
        }
        _normalizedBudgets.removeAll { $0.taskId == taskId }
        _budgetsVersion &+= 1
        _incrementalSpectrumCache = nil
        _stateVersion &+= 1

        let ts = date ?? clock.now()
        switch _focusState {
        case .focusing(let activeId, _) where activeId == taskId:
            closeActiveSessionLocked(at: ts, closingNote: nil)
            _focusState = .unassigned
            driftCandidate = nil
            unassignedActiveStart = nil
            unassignedPromptEmitted = false
        case .paused(let pausedId, _) where pausedId == taskId:
            _focusState = .unassigned
            driftCandidate = nil
            unassignedActiveStart = nil
            unassignedPromptEmitted = false
        default:
            break
        }

        if driftCandidate?.taskId == taskId {
            driftCandidate = nil
        }

        capAlertEmittedForTask.remove(taskId)
        targetAlertEmittedForTask.remove(taskId)
        snoozeUntilByTask.removeValue(forKey: taskId)

        _pendingAlerts.removeAll { alert in
            switch alert.kind {
            case .quotaCapReached(let id, _, _), .quotaTargetMet(let id, _, _):
                return id == taskId
            case .taskDrift(_, let detectedId, _):
                return detectedId == taskId
            case .highFrequencySwitch, .unassignedActivePrompt:
                return false
            }
        }
        return true
    }

    public func moveTask(fromOffsets: IndexSet, toOffset: Int) {
        lock.lock()
        defer { lock.unlock() }

        let validOffsets = fromOffsets.filter { $0 >= 0 && $0 < _budgets.count }.sorted()
        guard !validOffsets.isEmpty else { return }

        let moving = validOffsets.map { _budgets[$0] }
        for index in validOffsets.reversed() {
            _budgets.remove(at: index)
        }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let destination = min(max(0, toOffset - removedBeforeDestination), _budgets.count)
        _budgets.insert(contentsOf: moving, at: destination)
        _normalizedBudgets = _budgets.map(SwitchClassifier.NormalizedBudget.init)
        _budgetsVersion &+= 1
        _incrementalSpectrumCache = nil
        _stateVersion &+= 1
    }

    public func startFocus(taskId: String, note: String? = nil, at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        _autoPausedByAbsence = false
        _activeNonBudgetActivity = nil
        _nonBudgetLastTimestamp = nil
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        closeActiveSessionLocked(at: ts, closingNote: nil)
        openNewSessionLocked(taskId: taskId, note: note, at: ts)
    }

    public func switchTask(to taskId: String, note: String? = nil, closingNote: String? = nil, at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        _autoPausedByAbsence = false
        _activeNonBudgetActivity = nil
        _nonBudgetLastTimestamp = nil
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        if case .focusing(let currentTaskId, _) = _focusState, currentTaskId == taskId {
            if let idx = activeSessionIndex, let note {
                _focusSessions[idx].note = note
                _stateVersion &+= 1
            }
            return
        }
        closeActiveSessionLocked(at: ts, closingNote: closingNote)
        openNewSessionLocked(taskId: taskId, note: note, at: ts)
    }

    public func pauseFocus(note: String? = nil, at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        // Explicit manual pause: never auto-resume when user returns/continues typing.
        _autoPausedByAbsence = false
        _activeNonBudgetActivity = nil
        _nonBudgetLastTimestamp = nil
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        guard case .focusing(let taskId, _) = _focusState else {
            return
        }
        closeActiveSessionLocked(at: ts, closingNote: note)
        _focusState = .paused(taskId: taskId, pausedAt: ts)
        _stateVersion &+= 1
        driftCandidate = nil
    }

    public func stopFocus(note: String? = nil, at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        _autoPausedByAbsence = false
        _activeNonBudgetActivity = nil
        _nonBudgetLastTimestamp = nil
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        closeActiveSessionLocked(at: ts, closingNote: note)
        _focusState = .unassigned
        _stateVersion &+= 1
        driftCandidate = nil
        unassignedActiveStart = nil
        unassignedPromptEmitted = false
    }

    /// Seals active timing baselines immediately before macOS enters system sleep so wake-up
    /// never attributes sleep duration to any focus task or activity mode.
    public func handleSystemSleep(at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        if case .focusing(let taskId, _) = _focusState {
            let sessionStart = activeSessionIndex.flatMap { idx in
                idx < _focusSessions.count ? _focusSessions[idx].startedAt : nil
            } ?? ts
            let endTimestamp = lastProgressTimestamp ?? ts
            closeActiveSessionLocked(at: max(endTimestamp, sessionStart), closingNote: nil)
            _focusState = .paused(taskId: taskId, pausedAt: ts)
            _autoPausedByAbsence = true
            _stateVersion &+= 1
        }
        lastProgressTimestamp = nil
        _nonBudgetLastTimestamp = nil
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        unassignedActiveStart = nil
        driftCandidate = nil
    }

    public func snoozeAlert(for taskId: String?, minutes: Int, at date: Date? = nil) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        let until = ts.addingTimeInterval(TimeInterval(max(1, minutes)) * 60.0)
        if let taskId {
            snoozeUntilByTask[taskId] = until
            capAlertEmittedForTask.remove(taskId)
        } else {
            globalSnoozeUntil = until
            unassignedSnoozeUntil = until
            unassignedPromptEmitted = false
        }
        _pendingAlerts.removeAll { alert in
            switch alert.kind {
            case .quotaCapReached(let id, _, _), .quotaTargetMet(let id, _, _):
                return taskId == nil || id == taskId
            case .taskDrift(_, let detectedId, _):
                return taskId == nil || detectedId == taskId
            case .unassignedActivePrompt, .highFrequencySwitch:
                return taskId == nil
            }
        }
    }

    public func dismissAlert(id: String) {
        lock.lock()
        defer { lock.unlock() }
        _pendingAlerts.removeAll { $0.id == id }
    }

    @discardableResult
    public func ingest(_ sample: ActivitySample) -> [SupervisorAlert] {
        lock.lock()
        defer { lock.unlock() }
        let cleanSample = PrivacyRedactor.redact(sample, config: _privacyConfig)
        return ingestRedactedLocked(cleanSample)
    }

    @discardableResult
    public func ingestAlreadyRedacted(_ cleanSample: ActivitySample) -> [SupervisorAlert] {
        lock.lock()
        defer { lock.unlock() }
        return ingestRedactedLocked(cleanSample)
    }

    private func ingestRedactedLocked(_ cleanSample: ActivitySample) -> [SupervisorAlert] {
        _lastSample = cleanSample

        let isIdleTrigger = !cleanSample.screenLocked && cleanSample.idleSeconds >= config.idleThresholdSeconds
        let isAbsent = cleanSample.screenLocked || isIdleTrigger
        if isAbsent {
            let lastActiveAt = cleanSample.timestamp.addingTimeInterval(-max(0, cleanSample.idleSeconds))
            if case .focusing(let taskId, _) = _focusState {
                var endTimestamp = lastProgressTimestamp ?? cleanSample.timestamp
                if let idx = activeSessionIndex, idx < _focusSessions.count {
                    let sessionStart = _focusSessions[idx].startedAt
                    let trackedUpTo = lastProgressTimestamp ?? sessionStart
                    if isIdleTrigger {
                        let clampedLastActive = max(lastActiveAt, sessionStart)
                        let overcountedSec = max(0, trackedUpTo.timeIntervalSince(clampedLastActive))
                        let deductMin = min(_focusSessions[idx].minutes, overcountedSec / 60.0)
                        if deductMin > 0 {
                            _focusSessions[idx].minutes = max(0, _focusSessions[idx].minutes - deductMin)
                            if let mode = _activeActivityMode {
                                _activityModeMinutes[mode.rawValue] = max(0, (_activityModeMinutes[mode.rawValue] ?? 0.0) - deductMin)
                            }
                        }
                        endTimestamp = clampedLastActive
                    } else {
                        endTimestamp = max(trackedUpTo, sessionStart)
                    }
                }
                closeActiveSessionLocked(at: endTimestamp, closingNote: nil)
                _focusState = .paused(taskId: taskId, pausedAt: cleanSample.timestamp)
                _autoPausedByAbsence = true
                _stateVersion &+= 1
            } else if _activeNonBudgetActivity != nil || _activeActivityMode != nil {
                if isIdleTrigger, let trackedUpTo = _nonBudgetLastTimestamp {
                    let segStart = _nonBudgetSegmentStartedAt ?? trackedUpTo
                    let clampedLastActive = max(lastActiveAt, segStart)
                    let overcountedSec = max(0, trackedUpTo.timeIntervalSince(clampedLastActive))
                    let deductMin = min(_nonBudgetSegmentMinutes, overcountedSec / 60.0)
                    if deductMin > 0 {
                        if let mode = _activeActivityMode {
                            _activityModeMinutes[mode.rawValue] = max(0, (_activityModeMinutes[mode.rawValue] ?? 0.0) - deductMin)
                        }
                        if let nonBudget = _activeNonBudgetActivity {
                            switch nonBudget {
                            case .otherWork:
                                _otherWorkMinutes = max(0, _otherWorkMinutes - deductMin)
                            case .nonWork:
                                _nonWorkMinutes = max(0, _nonWorkMinutes - deductMin)
                            }
                        }
                        _stateVersion &+= 1
                    }
                }
            }
            _nonBudgetLastTimestamp = nil
            _nonBudgetSegmentStartedAt = nil
            _nonBudgetSegmentMinutes = 0.0
            unassignedActiveStart = nil
            driftCandidate = nil
            return []
        }

        var emitted: [SupervisorAlert] = []
        let ts = cleanSample.timestamp

        // 0. Auto-resume focus if previously auto-paused by idle/lock/sleep (manual pause stays paused).
        if _autoPausedByAbsence, case .paused(let pausedTaskId, _) = _focusState {
            _autoPausedByAbsence = false
            if _budgets.contains(where: { $0.taskId == pausedTaskId }) {
                openNewSessionLocked(taskId: pausedTaskId, note: nil, at: ts)
            }
        }

        // 1. Accumulate focus time if currently focusing, and Layer-1 activityMode / non-budget time
        var activeTaskId: String?
        if case .focusing(let taskId, let startedAt) = _focusState {
            activeTaskId = taskId
            let baseline = lastProgressTimestamp ?? startedAt
            let deltaSeconds = max(0, ts.timeIntervalSince(baseline))
            if let maxGap = config.maxTickGapSeconds, deltaSeconds > maxGap {
                // Wall-clock jump (sleep / freeze): reset baseline without attributing ghost time.
                lastProgressTimestamp = ts
            } else if deltaSeconds > 0, let idx = activeSessionIndex {
                let deltaMin = deltaSeconds / 60.0
                _focusSessions[idx].minutes += deltaMin
                if let mode = _activeActivityMode {
                    _activityModeMinutes[mode.rawValue, default: 0.0] += deltaMin
                }
                lastProgressTimestamp = ts
            } else if lastProgressTimestamp == nil {
                lastProgressTimestamp = ts
            }
        } else if _activeNonBudgetActivity != nil || _activeActivityMode != nil {
            if let lastTs = _nonBudgetLastTimestamp {
                let deltaSeconds = max(0, ts.timeIntervalSince(lastTs))
                if let maxGap = config.maxTickGapSeconds, deltaSeconds > maxGap {
                    _nonBudgetSegmentStartedAt = ts
                    _nonBudgetSegmentMinutes = 0.0
                } else if deltaSeconds > 0 {
                    let deltaMin = deltaSeconds / 60.0
                    _nonBudgetSegmentMinutes += deltaMin
                    if let mode = _activeActivityMode {
                        _activityModeMinutes[mode.rawValue, default: 0.0] += deltaMin
                    }
                    if let nonBudget = _activeNonBudgetActivity {
                        switch nonBudget {
                        case .otherWork:
                            _otherWorkMinutes += deltaMin
                        case .nonWork:
                            _nonWorkMinutes += deltaMin
                        }
                    }
                }
            } else {
                _nonBudgetSegmentStartedAt = ts
                _nonBudgetSegmentMinutes = 0.0
            }
            _nonBudgetLastTimestamp = ts
        }

        // 2. Append to enriched spans
        EventMerger.append(
            sample: cleanSample,
            declaredTaskId: activeTaskId,
            semanticGroup: _currentSemanticGroup,
            to: &_enrichedSpans,
            pulsetime: config.pulsetimeSeconds
        )
        _stateVersion &+= 1

        // 3. Quota checks for active focused task
        if let taskId = activeTaskId, let budget = _budgets.first(where: { $0.taskId == taskId }) {
            let focused = focusedMinutesLocked(for: taskId)

            if let cap = budget.capMinutes, focused >= Double(cap) {
                let snoozed = (snoozeUntilByTask[taskId].map { ts < $0 } ?? false)
                    || (globalSnoozeUntil.map { ts < $0 } ?? false)
                if !snoozed && !capAlertEmittedForTask.contains(taskId) {
                    capAlertEmittedForTask.insert(taskId)
                    let alert = makeCapAlertLocked(budget: budget, focusedMinutes: focused, cap: cap, at: ts)
                    emitted.append(alert)
                }
            }

            if let target = budget.targetMinutes, focused >= Double(target) {
                if !targetAlertEmittedForTask.contains(taskId) {
                    targetAlertEmittedForTask.insert(taskId)
                    let alert = makeTargetAlertLocked(budget: budget, focusedMinutes: focused, target: target, at: ts)
                    emitted.append(alert)
                }
            }

            // 4. Task drift check (in manual mode; in auto-tracking mode Jev handles automatic switching)
            if !_autoTrackingActive, !cleanSample.redacted, let driftAlert = evaluateDriftLocked(declaredTaskId: taskId, sample: cleanSample) {
                emitted.append(driftAlert)
            }
        } else if _focusState == .unassigned && !_autoTrackingActive {
            // 5. Unassigned continuous activity check (only when manual mode is active)
            if unassignedActiveStart == nil {
                unassignedActiveStart = ts
            }
            if let start = unassignedActiveStart {
                let activeSeconds = ts.timeIntervalSince(start)
                let snoozed = (unassignedSnoozeUntil.map { ts < $0 } ?? false)
                    || (globalSnoozeUntil.map { ts < $0 } ?? false)
                if activeSeconds >= config.unassignedPromptSeconds && !snoozed && !unassignedPromptEmitted {
                    unassignedPromptEmitted = true
                    emitted.append(makeUnassignedPromptAlertLocked(activeMinutes: activeSeconds / 60.0, at: ts))
                }
            }
        }

        // 6. High-frequency switch check
        if let switchAlert = evaluateHighFrequencySwitchLocked(at: ts) {
            emitted.append(switchAlert)
        }

        if !emitted.isEmpty {
            _pendingAlerts.append(contentsOf: emitted)
        }
        return emitted
    }

    public func focusedMinutes(for taskId: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        return focusedMinutesLocked(for: taskId)
    }

    public func lastNote(for taskId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return _focusSessions.last(where: { $0.taskId == taskId && ($0.note?.isEmpty == false) })?.note
    }

    public func taskProgress() -> [TaskProgress] {
        lock.lock()
        defer { lock.unlock() }
        let minutesByTask = focusedMinutesByTaskLocked()
        return _budgets.map { budget in
            let minutes = minutesByTask[budget.taskId, default: 0.0]
            let status = BudgetStatus.compute(
                focusedMinutes: minutes,
                targetMinutes: budget.targetMinutes,
                capMinutes: budget.capMinutes
            )
            return TaskProgress(budget: budget, focusedMinutes: minutes, status: status)
        }
    }

    public func currentSpectrumAndMetrics(at date: Date? = nil) -> (segments: [SpectrumSegment], metrics: DayMetrics) {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        let tsMs = Int64((ts.timeIntervalSince1970 * 1000.0).rounded())
        let version = _stateVersion
        if let cached = _cachedSpectrum, cached.version == version, cached.tsMs == tsMs {
            return (cached.segments, cached.metrics)
        }
        let built = SpectrumBuilder.buildIncremental(
            spans: _enrichedSpans,
            focusSessions: _focusSessions,
            budgets: _budgets,
            budgetsVersion: _budgetsVersion,
            now: ts,
            cache: _incrementalSpectrumCache,
            thrashingWindowSeconds: config.thrashingWindowSeconds,
            thrashingMinSwitches: config.thrashingMinSwitches,
            thrashingMaxAvgDwellSeconds: config.thrashingMaxAvgDwellSeconds,
            thrashingMinDistinctContexts: config.thrashingMinDistinctContexts,
            thrashingMinInterruptSwitches: config.thrashingMinInterruptSwitches,
            thrashingMinEffectiveDwellSeconds: config.thrashingMinEffectiveDwellSeconds
        )
        _cachedSpectrum = (version: version, tsMs: tsMs, segments: built.segments, metrics: built.metrics)
        _incrementalSpectrumCache = built.nextCache
        return (built.segments, built.metrics)
    }

    public func snapshot(at date: Date? = nil, precomputedMetrics: DayMetrics? = nil) -> DayHelmDaySnapshot {
        lock.lock()
        defer { lock.unlock() }
        let ts = date ?? clock.now()
        let tsMs = Int64((ts.timeIntervalSince1970 * 1000.0).rounded())
        let version = _stateVersion

        let activeFocus: ActiveFocusSnapshot?
        if case .focusing(let taskId, let startedAt) = _focusState {
            activeFocus = ActiveFocusSnapshot(taskId: taskId, startedAt: startedAt)
        } else {
            activeFocus = nil
        }

        let minutesByTask = focusedMinutesByTaskLocked()
        let budgetSnapshots = _budgets.map { budget in
            let minutes = minutesByTask[budget.taskId, default: 0.0]
            let status = BudgetStatus.compute(
                focusedMinutes: minutes,
                targetMinutes: budget.targetMinutes,
                capMinutes: budget.capMinutes
            )
            return BudgetSnapshot(
                taskId: budget.taskId,
                displayName: budget.displayName,
                focusedMinutes: minutes,
                targetMinutes: budget.targetMinutes,
                capMinutes: budget.capMinutes,
                status: BudgetStatusCode(from: status)
            )
        }

        let metrics: DayMetrics
        if let precomputedMetrics {
            metrics = precomputedMetrics
        } else if let cached = _cachedSpectrum, cached.version == version, cached.tsMs == tsMs {
            metrics = cached.metrics
        } else {
            let built = SpectrumBuilder.buildIncremental(
                spans: _enrichedSpans,
                focusSessions: _focusSessions,
                budgets: _budgets,
                budgetsVersion: _budgetsVersion,
                now: ts,
                cache: _incrementalSpectrumCache,
                thrashingWindowSeconds: config.thrashingWindowSeconds,
                thrashingMinSwitches: config.thrashingMinSwitches,
                thrashingMaxAvgDwellSeconds: config.thrashingMaxAvgDwellSeconds,
                thrashingMinDistinctContexts: config.thrashingMinDistinctContexts,
                thrashingMinInterruptSwitches: config.thrashingMinInterruptSwitches,
                thrashingMinEffectiveDwellSeconds: config.thrashingMinEffectiveDwellSeconds
            )
            _cachedSpectrum = (version: version, tsMs: tsMs, segments: built.segments, metrics: built.metrics)
            _incrementalSpectrumCache = built.nextCache
            metrics = built.metrics
        }

        return DayHelmDaySnapshot(
            schemaVersion: 1,
            date: _currentDateString,
            focusState: _focusState,
            activeFocus: activeFocus,
            budgets: budgetSnapshots,
            focusSessions: _focusSessions,
            enrichedSpans: _enrichedSpans,
            metrics: metrics,
            otherWorkMinutes: _otherWorkMinutes > 0 ? _otherWorkMinutes : nil,
            nonWorkMinutes: _nonWorkMinutes > 0 ? _nonWorkMinutes : nil,
            activityModeMinutes: _activityModeMinutes.isEmpty ? nil : _activityModeMinutes
        )
    }

    public func rolloverToNewDay(_ newDateString: String) {
        lock.lock()
        defer { lock.unlock() }
        let ts = clock.now()
        closeActiveSessionLocked(at: ts, closingNote: nil)
        _currentDateString = newDateString
        _focusState = .unassigned
        _focusSessions = []
        _enrichedSpans = []
        _pendingAlerts = []
        activeSessionIndex = nil
        lastProgressTimestamp = nil
        _activeNonBudgetActivity = nil
        _activeActivityMode = nil
        _nonBudgetLastTimestamp = nil
        _autoPausedByAbsence = false
        _nonBudgetSegmentStartedAt = nil
        _nonBudgetSegmentMinutes = 0.0
        _otherWorkMinutes = 0.0
        _nonWorkMinutes = 0.0
        _activityModeMinutes = [:]
        _currentSemanticGroup = nil
        capAlertEmittedForTask.removeAll()
        targetAlertEmittedForTask.removeAll()
        snoozeUntilByTask.removeAll()
        globalSnoozeUntil = nil
        unassignedActiveStart = nil
        unassignedPromptEmitted = false
        unassignedSnoozeUntil = nil
        driftCandidate = nil
        lastThrashingAlertAt = nil
        _cachedSpectrum = nil
        _incrementalSpectrumCache = nil
        _stateVersion &+= 1
    }

    // MARK: - Private Helpers (must hold lock)

    private func focusedMinutesLocked(for taskId: String) -> Double {
        var total = 0.0
        for session in _focusSessions where session.taskId == taskId {
            total += session.minutes
        }
        return total
    }

    private func focusedMinutesByTaskLocked() -> [String: Double] {
        var totals: [String: Double] = [:]
        totals.reserveCapacity(_budgets.count)
        for session in _focusSessions {
            totals[session.taskId, default: 0.0] += session.minutes
        }
        return totals
    }

    private func openNewSessionLocked(taskId: String, note: String?, at ts: Date) {
        sessionCounter += 1
        let id = String(format: "sess_focus_%02d", sessionCounter)
        let record = FocusSessionRecord(
            id: id,
            taskId: taskId,
            startedAt: ts,
            endedAt: nil,
            minutes: 0,
            note: note
        )
        _focusSessions.append(record)
        activeSessionIndex = _focusSessions.count - 1
        lastProgressTimestamp = ts
        _focusState = .focusing(taskId: taskId, startedAt: ts)
        _stateVersion &+= 1
        driftCandidate = nil
        unassignedActiveStart = nil
        unassignedPromptEmitted = false
    }

    private func closeActiveSessionLocked(at ts: Date, closingNote: String?) {
        guard let idx = activeSessionIndex, idx < _focusSessions.count else {
            activeSessionIndex = nil
            lastProgressTimestamp = nil
            return
        }
        if _focusSessions[idx].endedAt == nil {
            _focusSessions[idx].endedAt = max(_focusSessions[idx].startedAt, ts)
        }
        if let closingNote, !closingNote.isEmpty {
            _focusSessions[idx].note = closingNote
        }
        activeSessionIndex = nil
        lastProgressTimestamp = nil
        _stateVersion &+= 1
    }

    private func evaluateDriftLocked(declaredTaskId: String, sample: ActivitySample) -> SupervisorAlert? {
        let declaredBudget = _budgets.first { $0.taskId == declaredTaskId }
        if let declaredNorm = _normalizedBudgets.first(where: { $0.taskId == declaredTaskId }),
           SwitchClassifier.matchesBudget(
               appName: sample.appName,
               bundleId: sample.bundleId,
               windowTitle: sample.windowTitle,
               url: sample.url,
               redacted: sample.redacted,
               normalizedBudget: declaredNorm
           ) {
            driftCandidate = nil
            return nil
        }

        let matchedOtherIndex = _normalizedBudgets.firstIndex {
            $0.taskId != declaredTaskId && SwitchClassifier.matchesBudget(
                appName: sample.appName,
                bundleId: sample.bundleId,
                windowTitle: sample.windowTitle,
                url: sample.url,
                redacted: sample.redacted,
                normalizedBudget: $0
            )
        }
        guard let matchedOtherIndex, matchedOtherIndex < _budgets.count else {
            // Neutral auxiliary tool (Finder, Preview, generic editor, etc.)
            driftCandidate = nil
            return nil
        }
        let matchedOther = _budgets[matchedOtherIndex]

        if let current = driftCandidate, current.taskId == matchedOther.taskId {
            let elapsed = sample.timestamp.timeIntervalSince(current.startedAt)
            let snoozed = (snoozeUntilByTask[matchedOther.taskId].map { sample.timestamp < $0 } ?? false)
                || (globalSnoozeUntil.map { sample.timestamp < $0 } ?? false)
            if elapsed >= config.driftWindowSeconds && !current.alertEmitted && !snoozed {
                driftCandidate?.alertEmitted = true
                let declaredName = declaredBudget?.displayName ?? declaredTaskId
                return makeDriftAlertLocked(
                    declaredTaskId: declaredTaskId,
                    declaredName: declaredName,
                    detectedBudget: matchedOther,
                    minutes: elapsed / 60.0,
                    at: sample.timestamp
                )
            }
        } else {
            driftCandidate = DriftCandidate(taskId: matchedOther.taskId, startedAt: sample.timestamp, alertEmitted: false)
        }

        return nil
    }

    private func evaluateHighFrequencySwitchLocked(at ts: Date) -> SupervisorAlert? {
        if let lastAlert = lastThrashingAlertAt, ts.timeIntervalSince(lastAlert) < config.thrashingCooldownSeconds {
            return nil
        }
        if let globalSnoozeUntil, ts < globalSnoozeUntil {
            return nil
        }

        let recentWindowStart = ts.addingTimeInterval(-config.thrashingWindowSeconds)
        var tailStart = _enrichedSpans.count
        for i in stride(from: _enrichedSpans.count - 1, through: 0, by: -1) {
            if _enrichedSpans[i].endedAt < recentWindowStart {
                break
            }
            tailStart = i
        }
        var recentSpans: [EnrichedSpan] = []
        if tailStart < _enrichedSpans.count {
            recentSpans.reserveCapacity(_enrichedSpans.count - tailStart)
            for i in tailStart..<_enrichedSpans.count {
                let span = _enrichedSpans[i]
                if span.endedAt >= recentWindowStart && span.startedAt <= ts {
                    recentSpans.append(span)
                }
            }
        }
        let windows = SpectrumBuilder.detectThrashingWindows(
            spans: recentSpans,
            budgets: _budgets,
            windowSeconds: config.thrashingWindowSeconds,
            minSwitches: config.thrashingMinSwitches,
            maxAverageDwellSeconds: config.thrashingMaxAvgDwellSeconds,
            minDistinctContexts: config.thrashingMinDistinctContexts,
            minInterruptSwitches: config.thrashingMinInterruptSwitches,
            minEffectiveDwellSeconds: config.thrashingMinEffectiveDwellSeconds
        )
        guard let latest = windows.last else {
            return nil
        }

        lastThrashingAlertAt = ts
        alertCounter += 1
        let windowMins = max(1, Int(config.thrashingWindowSeconds / 60.0))
        let message: String
        if latest.distinctContextCount > 0 {
            message = "过去 \(windowMins) 分钟内在 \(latest.distinctContextCount) 个不同上下文间频繁切换，连续专注被打散，建议稳住当前任务或先休息 3 分钟。"
        } else {
            message = "过去 \(windowMins) 分钟内应用切换频繁，连续专注被打散，建议稳住当前任务或先休息 3 分钟。"
        }
        return SupervisorAlert(
            id: "alert_\(alertCounter)",
            timestamp: ts,
            kind: .highFrequencySwitch(switchesInWindow: latest.switchCount, windowMinutes: windowMins),
            title: "检测到高频切换（\(latest.switchCount) 次 / \(windowMins)m）",
            message: message,
            actions: [
                .snooze(minutes: 15, label: "15m 后再说"),
                .dismiss(label: "知道了")
            ]
        )
    }

    private func makeCapAlertLocked(budget: TaskBudget, focusedMinutes: Double, cap: Int, at ts: Date) -> SupervisorAlert {
        alertCounter += 1
        var actions: [SupervisorAction] = []
        if let nextTask = _budgets.first(where: { other in
            guard other.taskId != budget.taskId, let target = other.targetMinutes else { return false }
            return focusedMinutesLocked(for: other.taskId) < Double(target)
        }) {
            let remaining = max(1, Int(Double(nextTask.targetMinutes ?? 0) - focusedMinutesLocked(for: nextTask.taskId)))
            actions.append(.switchTask(taskId: nextTask.taskId, label: "切到「\(nextTask.displayName)」"))
            let message = "今日「\(nextTask.displayName)」还差 \(remaining) 分钟达标，建议现在换挡。"
            actions.append(.snooze(minutes: 15, label: "+15m 收尾"))
            actions.append(.pauseFocus(label: "转入休息"))
            return SupervisorAlert(
                id: "alert_\(alertCounter)",
                timestamp: ts,
                kind: .quotaCapReached(taskId: budget.taskId, minutes: focusedMinutes, cap: cap),
                title: "【\(budget.displayName)】已达到今日 \(cap)m 上限",
                message: message,
                actions: actions
            )
        }

        actions.append(.snooze(minutes: 15, label: "+15m 收尾"))
        actions.append(.pauseFocus(label: "转入休息"))
        return SupervisorAlert(
            id: "alert_\(alertCounter)",
            timestamp: ts,
            kind: .quotaCapReached(taskId: budget.taskId, minutes: focusedMinutes, cap: cap),
            title: "【\(budget.displayName)】已达到今日 \(cap)m 上限",
            message: "已累计 \(Int(focusedMinutes.rounded())) 分钟，建议收尾或切换其他事项。",
            actions: actions
        )
    }

    private func makeTargetAlertLocked(budget: TaskBudget, focusedMinutes: Double, target: Int, at ts: Date) -> SupervisorAlert {
        alertCounter += 1
        return SupervisorAlert(
            id: "alert_\(alertCounter)",
            timestamp: ts,
            kind: .quotaTargetMet(taskId: budget.taskId, minutes: focusedMinutes, target: target),
            title: "【\(budget.displayName)】今日 \(target)m 保底已达标",
            message: "已累计 \(Int(focusedMinutes.rounded())) 分钟，可继续推进或切换下一事项。",
            actions: [
                .dismiss(label: "继续推进"),
                .pauseFocus(label: "休息一下")
            ]
        )
    }

    private func makeDriftAlertLocked(
        declaredTaskId: String,
        declaredName: String,
        detectedBudget: TaskBudget,
        minutes: Double,
        at ts: Date
    ) -> SupervisorAlert {
        alertCounter += 1
        return SupervisorAlert(
            id: "alert_\(alertCounter)",
            timestamp: ts,
            kind: .taskDrift(declaredTaskId: declaredTaskId, detectedTaskId: detectedBudget.taskId, minutes: minutes),
            title: "疑似从「\(declaredName)」飘到「\(detectedBudget.displayName)」",
            message: "已连续 \(Int(minutes.rounded())) 分钟停留在「\(detectedBudget.displayName)」相关内容。",
            actions: [
                .switchTask(taskId: detectedBudget.taskId, label: "改计入「\(detectedBudget.displayName)」"),
                .snooze(minutes: 10, label: "顺手处理 (10m)"),
                .dismiss(label: "回到「\(declaredName)」")
            ]
        )
    }

    private func makeUnassignedPromptAlertLocked(activeMinutes: Double, at ts: Date) -> SupervisorAlert {
        alertCounter += 1
        var actions: [SupervisorAction] = _budgets.prefix(2).map {
            .switchTask(taskId: $0.taskId, label: "开始「\($0.displayName)」")
        }
        actions.append(.snooze(minutes: 10, label: "10m 后再说"))
        actions.append(.dismiss(label: "暂不指定"))
        return SupervisorAlert(
            id: "alert_\(alertCounter)",
            timestamp: ts,
            kind: .unassignedActivePrompt(activeMinutes: activeMinutes),
            title: "已连续活跃 \(Int(activeMinutes.rounded())) 分钟，尚未指定专注事项",
            message: "选一个当前主攻事项，让时长准确计入今日配额。",
            actions: actions
        )
    }

    private static func cleanKeywords(_ keywords: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for kw in keywords {
            let trimmed = kw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let lower = trimmed.lowercased()
            if seen.insert(lower).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    private static func makeUniqueTaskId(preferredId: String?, displayName: String, existingIds: Set<String>) -> String {
        let baseSlug: String = {
            if let preferredId {
                let cleaned = preferredId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !cleaned.isEmpty {
                    return cleaned
                }
            }
            let asciiLower = displayName
                .lowercased()
                .map { ch -> Character in
                    if ch.isASCII && (ch.isLetter || ch.isNumber) {
                        return ch
                    }
                    return "-"
                }
            let collapsed = String(asciiLower)
                .split(separator: "-", omittingEmptySubsequences: true)
                .joined(separator: "-")
            if !collapsed.isEmpty {
                return collapsed
            }
            return "task-\(UUID().uuidString.prefix(8).lowercased())"
        }()

        if !existingIds.contains(baseSlug) {
            return baseSlug
        }
        var suffix = 2
        while existingIds.contains("\(baseSlug)-\(suffix)") {
            suffix += 1
        }
        return "\(baseSlug)-\(suffix)"
    }
}
