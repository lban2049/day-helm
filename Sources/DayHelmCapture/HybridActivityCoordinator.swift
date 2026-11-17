import AppKit
import Combine
import DayHelmCore
import Foundation

@MainActor
public final class HybridActivityCoordinator: ObservableObject {
    @Published public private(set) var sessionState: FocusSessionState = .unassigned
    @Published public private(set) var taskProgressList: [TaskProgress] = []
    @Published public private(set) var spectrumSegments: [SpectrumSegment] = []
    @Published public private(set) var metrics: DayMetrics = DayMetrics(
        activeMinutes: 0,
        longestBlockMinutes: 0,
        solidBlocksCount: 0,
        recentSwitchesPerHour: 0
    )
    @Published public private(set) var latestSample: ActivitySample?
    @Published public private(set) var almaConnected: Bool = false
    @Published public private(set) var axTrusted: Bool = false
    @Published public private(set) var activeAlert: SupervisorAlert?
    @Published public private(set) var elapsedFocusSeconds: TimeInterval = 0
    @Published public private(set) var lastTaskNote: String?

    public let isSyntheticDemo: Bool
    public let storeDirectoryURL: URL

    private let engine: DayHelmEngine
    private let store: DayHelmStore?
    private let almaClient: AlmaActivityClient?
    private let inspector: any ActivityInspecting
    private let clock: any DayHelmClock

    private var timerTask: Task<Void, Never>?
    private var almaSyncTask: Task<Void, Never>?
    private var lastAlmaEventMs: Int64?
    private var latestAlmaBrowserSample: ActivitySample?
    private var lastAlmaInputAt: Date?
    private var tickCount: Int = 0
    private var isStarted: Bool = false

    public init(
        engine: DayHelmEngine,
        store: DayHelmStore?,
        almaClient: AlmaActivityClient?,
        inspector: any ActivityInspecting,
        clock: any DayHelmClock = SystemClock(),
        syntheticDemo: Bool = false
    ) {
        self.engine = engine
        self.store = store
        self.almaClient = almaClient
        self.inspector = inspector
        self.clock = clock
        self.isSyntheticDemo = syntheticDemo
        self.storeDirectoryURL = store?.directory ?? DayHelmStore.defaultDirectory
        self.axTrusted = inspector.isAccessibilityTrusted
        refreshPublishedState()
    }

    public static func makeLive(
        storeDirectory: URL = DayHelmStore.defaultDirectory,
        clock: any DayHelmClock = SystemClock()
    ) -> HybridActivityCoordinator {
        let store = DayHelmStore(directory: storeDirectory)
        let budgets = TimeAuditConfigLoader.loadBudgets(dayhelmConfigURL: store.configURL)
        let todayStr = DayHelmDateFormatting.dayString(from: clock.now())

        let engine: DayHelmEngine
        if let existing = try? store.loadToday() {
            if existing.date == todayStr {
                engine = DayHelmEngine(snapshot: existing, budgets: budgets, clock: clock)
            } else {
                _ = try? store.rolloverIfNeeded(currentSnapshot: existing, newDateString: todayStr)
                engine = DayHelmEngine(budgets: budgets, clock: clock)
            }
        } else {
            engine = DayHelmEngine(budgets: budgets, clock: clock)
        }

        let inspector = AXWindowInspector(clock: clock, privacyConfig: engine.config.privacyConfig)
        let almaClient = AlmaActivityClient()

        return HybridActivityCoordinator(
            engine: engine,
            store: store,
            almaClient: almaClient,
            inspector: inspector,
            clock: clock,
            syntheticDemo: false
        )
    }

    public static func makeSyntheticDemo(
        clock: any DayHelmClock = SystemClock(),
        inspector: (any ActivityInspecting)? = nil
    ) -> HybridActivityCoordinator {
        let now = clock.now()
        let budgets = TimeAuditConfigLoader.defaultBudgets
        let engine = DayHelmEngine(budgets: budgets, clock: clock)

        // Seed synthetic morning timeline ending near `now`
        let morningStart = now.addingTimeInterval(-3.5 * 3600)

        // 1. Morning ecommerce deep block (35m)
        engine.startFocus(taskId: "ecommerce", note: "完成示例商品 A 主图初稿", at: morningStart)
        engine.ingest(ActivitySample(
            timestamp: morningStart.addingTimeInterval(35 * 60),
            appName: "Example Browser",
            bundleId: "com.example.browser",
            windowTitle: "Example Shop — 商品主图编辑器",
            url: "https://shop.example.com/product/101",
            idleSeconds: 1,
            screenLocked: false,
            inputActive: true
        ))

        // 2. Brief thrashing segment (12 rapid switches in 5m)
        engine.stopFocus(at: morningStart.addingTimeInterval(40 * 60))
        let thrashBase = morningStart.addingTimeInterval(42 * 60)
        for i in 0..<12 {
            let t = thrashBase.addingTimeInterval(Double(i) * 22)
            engine.ingest(ActivitySample(
                timestamp: t,
                appName: i % 2 == 0 ? "Example Browser" : "Terminal",
                bundleId: i % 2 == 0 ? "com.example.browser" : "com.apple.Terminal",
                windowTitle: "Synthetic Tab \(i)",
                url: nil,
                idleSeconds: 1,
                screenLocked: false,
                inputActive: true
            ))
        }

        // 3. Ecommerce ops block (26m)
        let opsStart = morningStart.addingTimeInterval(65 * 60)
        engine.startFocus(taskId: "ecommerce-ops", note: "处理当日退换货工单", at: opsStart)
        engine.ingest(ActivitySample(
            timestamp: opsStart.addingTimeInterval(26 * 60),
            appName: "Example Browser",
            bundleId: "com.example.browser",
            windowTitle: "Support Ticket #1042 — 订单处理",
            url: "https://ops.example.com/tickets/1042",
            idleSeconds: 1,
            screenLocked: false,
            inputActive: true
        ))

        // 4. Hermes block (20m)
        let hermesStart = morningStart.addingTimeInterval(100 * 60)
        engine.startFocus(taskId: "hermes", note: "整理 Q4 行业研报摘录", at: hermesStart)
        engine.ingest(ActivitySample(
            timestamp: hermesStart.addingTimeInterval(20 * 60),
            appName: "Example Notes",
            bundleId: "com.example.notes",
            windowTitle: "Hermes Equity Research — 行业周报",
            url: nil,
            idleSeconds: 1,
            screenLocked: false,
            inputActive: true
        ))

        // 5. Current active ecommerce focus (17m so far -> 52m total)
        let activeStart = now.addingTimeInterval(-17 * 60)
        engine.startFocus(taskId: "ecommerce", note: "优化主图卖点文案", at: activeStart)
        engine.ingest(ActivitySample(
            timestamp: now.addingTimeInterval(-2),
            appName: "Example Browser",
            bundleId: "com.example.browser",
            windowTitle: "Example Shop — 商品详情页预览",
            url: "https://shop.example.com/product/102",
            idleSeconds: 1,
            screenLocked: false,
            inputActive: true
        ))

        let demoInspector = inspector ?? StaticSyntheticInspector(clock: clock)
        let coordinator = HybridActivityCoordinator(
            engine: engine,
            store: nil,
            almaClient: nil,
            inspector: demoInspector,
            clock: clock,
            syntheticDemo: true
        )
        coordinator.almaConnected = true
        coordinator.axTrusted = true
        coordinator.refreshPublishedState()
        return coordinator
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        if !isSyntheticDemo {
            Task { [weak self] in
                await self?.syncFromAlma(isInitialBackfill: true)
            }
        }

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                self?.onOneSecondTick()
            }
        }

        if !isSyntheticDemo {
            almaSyncTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    guard !Task.isCancelled else { break }
                    await self?.syncFromAlma(isInitialBackfill: false)
                }
            }
        }
    }

    public func stop() {
        isStarted = false
        timerTask?.cancel()
        timerTask = nil
        almaSyncTask?.cancel()
        almaSyncTask = nil
        persistTodayIfNeeded()
    }

    // MARK: - User Actions

    public func selectTask(_ taskId: String, note: String? = nil) {
        let now = clock.now()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        engine.switchTask(to: taskId, note: effectiveNote, at: now)
        if let alert = activeAlert {
            engine.dismissAlert(id: alert.id)
            activeAlert = nil
        }
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    public func pauseFocus(note: String? = nil) {
        let now = clock.now()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        engine.pauseFocus(note: effectiveNote, at: now)
        if let alert = activeAlert {
            engine.dismissAlert(id: alert.id)
            activeAlert = nil
        }
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    public func stopToStandby(note: String? = nil) {
        let now = clock.now()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        engine.stopFocus(note: effectiveNote, at: now)
        if let alert = activeAlert {
            engine.dismissAlert(id: alert.id)
            activeAlert = nil
        }
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    public func handleAlertAction(_ action: SupervisorAction) {
        let now = clock.now()
        let currentAlert = activeAlert
        let alertTaskId: String? = {
            guard let alert = currentAlert else { return nil }
            switch alert.kind {
            case .quotaCapReached(let taskId, _, _),
                 .quotaTargetMet(let taskId, _, _):
                return taskId
            case .taskDrift(_, let detectedTaskId, _):
                return detectedTaskId
            case .highFrequencySwitch, .unassignedActivePrompt:
                return nil
            }
        }()

        switch action {
        case .switchTask(let taskId, _):
            engine.switchTask(to: taskId, at: now)
        case .snooze(let minutes, _):
            engine.snoozeAlert(for: alertTaskId, minutes: minutes, at: now)
        case .pauseFocus:
            engine.pauseFocus(at: now)
        case .dismiss:
            if let currentAlert {
                engine.dismissAlert(id: currentAlert.id)
            }
        }

        if let currentAlert {
            engine.dismissAlert(id: currentAlert.id)
        }
        activeAlert = engine.pendingAlerts.last
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    public func updateBudget(taskId: String, targetMinutes: Int?, capMinutes: Int?) {
        let updated = engine.budgets.map { budget in
            guard budget.taskId == taskId else { return budget }
            return TaskBudget(
                taskId: budget.taskId,
                displayName: budget.displayName,
                colorHex: budget.colorHex,
                targetMinutes: targetMinutes,
                capMinutes: capMinutes,
                keywords: budget.keywords
            )
        }
        engine.updateBudgets(updated)
        saveBudgetsIfNeeded()
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    @discardableResult
    public func addTask(
        displayName: String,
        colorHex: String,
        targetMinutes: Int?,
        capMinutes: Int?,
        keywords: [String]
    ) -> TaskBudget {
        let created = engine.addTask(
            displayName: displayName,
            colorHex: colorHex,
            targetMinutes: targetMinutes,
            capMinutes: capMinutes,
            keywords: keywords
        )
        saveBudgetsIfNeeded()
        refreshPublishedState()
        persistTodayIfNeeded()
        return created
    }

    public func updateTask(_ updatedBudget: TaskBudget) {
        _ = engine.updateTask(updatedBudget)
        saveBudgetsIfNeeded()
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    public func deleteTask(taskId: String) {
        let now = clock.now()
        _ = engine.deleteTask(taskId: taskId, at: now)
        activeAlert = engine.pendingAlerts.last
        saveBudgetsIfNeeded()
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    public func moveTask(fromOffsets: IndexSet, toOffset: Int) {
        engine.moveTask(fromOffsets: fromOffsets, toOffset: toOffset)
        saveBudgetsIfNeeded()
        refreshPublishedState()
        persistTodayIfNeeded()
    }

    private func saveBudgetsIfNeeded() {
        guard !isSyntheticDemo, let store else { return }
        try? store.saveBudgets(engine.budgets)
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openConfigDirectory() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: storeDirectoryURL.path) {
            try? fm.createDirectory(at: storeDirectoryURL, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(storeDirectoryURL)
    }

    public func triggerDemoAlert() {
        let now = clock.now()
        let sampleBudget = engine.budgets.first(where: { $0.capMinutes != nil }) ?? engine.budgets.first
        let nextTarget = engine.budgets.first(where: { $0.taskId != sampleBudget?.taskId && $0.targetMinutes != nil })

        let taskName = sampleBudget?.displayName ?? "电商日常运营"
        let cap = sampleBudget?.capMinutes ?? 30

        var actions: [SupervisorAction] = []
        if let nextTarget {
            actions.append(.switchTask(taskId: nextTarget.taskId, label: "切到「\(nextTarget.displayName)」"))
        }
        actions.append(.snooze(minutes: 15, label: "+15m 收尾"))
        actions.append(.pauseFocus(label: "转入休息"))

        let message: String
        if let nextTarget, let target = nextTarget.targetMinutes {
            let focused = Int(engine.focusedMinutes(for: nextTarget.taskId).rounded())
            let rem = max(1, target - focused)
            message = "今日「\(nextTarget.displayName)」还差 \(rem) 分钟达标，建议现在换挡。"
        } else {
            message = "已达到设定上限，建议收尾或切换核心推进事项。"
        }

        activeAlert = SupervisorAlert(
            id: "demo_alert_\(Int(now.timeIntervalSince1970))",
            timestamp: now,
            kind: .quotaCapReached(taskId: sampleBudget?.taskId ?? "ecommerce-ops", minutes: Double(cap), cap: cap),
            title: "【\(taskName)】已达到今日 \(cap)m 上限",
            message: message,
            actions: actions
        )
    }

    // MARK: - Polling & Sync

    public func pollOnce() {
        let now = clock.now()
        checkDayRolloverIfNeeded(now: now)

        axTrusted = inspector.isAccessibilityTrusted
        var sample = inspector.inspectCurrent()

        // Fuse recent Alma browser URL/title or input activity when AX cannot provide it
        if !sample.screenLocked {
            var patchedTitle = sample.windowTitle
            var patchedURL = sample.url
            var patchedInputActive = sample.inputActive
            var patchedIdle = sample.idleSeconds

            if let recentInput = lastAlmaInputAt, now.timeIntervalSince(recentInput) <= 3.0 {
                patchedInputActive = true
                patchedIdle = min(patchedIdle, now.timeIntervalSince(recentInput))
            }
            if patchedTitle == nil || patchedURL == nil,
               let almaBrowser = latestAlmaBrowserSample,
               now.timeIntervalSince(almaBrowser.timestamp) <= 5.0,
               almaBrowser.appName == sample.appName || almaBrowser.bundleId == sample.bundleId {
                patchedTitle = patchedTitle ?? almaBrowser.windowTitle
                patchedURL = patchedURL ?? almaBrowser.url
            }

            if patchedTitle != sample.windowTitle
                || patchedURL != sample.url
                || patchedInputActive != sample.inputActive
                || patchedIdle != sample.idleSeconds {
                sample = PrivacyRedactor.redact(
                    ActivitySample(
                        timestamp: sample.timestamp,
                        appName: sample.appName,
                        bundleId: sample.bundleId,
                        windowTitle: patchedTitle,
                        url: patchedURL,
                        idleSeconds: patchedIdle,
                        screenLocked: sample.screenLocked,
                        inputActive: patchedInputActive,
                        redacted: sample.redacted
                    ),
                    config: engine.config.privacyConfig
                )
            }
        }

        let alerts = engine.ingest(sample)
        if let newest = alerts.last {
            activeAlert = newest
        }
        refreshPublishedState()
    }

    private func onOneSecondTick() {
        tickCount += 1
        updateElapsedFocusSeconds()

        if !isSyntheticDemo {
            if tickCount % 2 == 0 {
                pollOnce()
            }
            if tickCount % 10 == 0 {
                persistTodayIfNeeded()
            }
        }
    }

    private func syncFromAlma(isInitialBackfill: Bool) async {
        guard let almaClient else { return }
        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let sinceMs = isInitialBackfill ? nil : lastAlmaEventMs

        let result = await almaClient.fetchTodaySamples(
            dayStart: dayStart,
            dayEnd: now.addingTimeInterval(60),
            sinceEventMs: sinceMs,
            privacyConfig: engine.config.privacyConfig
        )

        almaConnected = result.connected
        if let latestMs = result.latestEventTimestampMs {
            lastAlmaEventMs = max(lastAlmaEventMs ?? 0, latestMs)
        }

        guard result.connected, !result.samples.isEmpty else { return }

        if let lastSample = result.samples.last {
            if lastSample.inputActive {
                lastAlmaInputAt = lastSample.timestamp
            }
            if lastSample.url != nil || lastSample.windowTitle != nil {
                latestAlmaBrowserSample = lastSample
            }
        }

        if isInitialBackfill {
            let existingCutoff = engine.enrichedSpans.map(\.endedAt).max()
            let newSamples = result.samples.filter { sample in
                guard let existingCutoff else { return true }
                return sample.timestamp > existingCutoff
            }
            if !newSamples.isEmpty {
                let savedState = engine.focusState
                if case .unassigned = savedState {
                    for sample in newSamples {
                        _ = engine.ingest(sample)
                    }
                    // Suppress stale alerts from historical backfill
                    for alert in engine.pendingAlerts {
                        engine.dismissAlert(id: alert.id)
                    }
                } else {
                    // Only append historical spans before active focus without disturbing active timer
                    for sample in newSamples where sample.timestamp >= (engine.enrichedSpans.last?.endedAt ?? .distantPast) {
                        _ = engine.ingest(sample)
                    }
                }
                refreshPublishedState()
                persistTodayIfNeeded()
            }
        }
    }

    // MARK: - Helpers

    private func checkDayRolloverIfNeeded(now: Date) {
        let currentDay = DayHelmDateFormatting.dayString(from: now)
        guard currentDay != engine.currentDateString else { return }
        if !isSyntheticDemo, let store {
            let prevSnapshot = engine.snapshot(at: now)
            _ = try? store.rolloverIfNeeded(currentSnapshot: prevSnapshot, newDateString: currentDay)
        }
        engine.rolloverToNewDay(currentDay)
        lastAlmaEventMs = nil
        latestAlmaBrowserSample = nil
        activeAlert = nil
        refreshPublishedState()
    }

    private func refreshPublishedState() {
        let now = clock.now()
        sessionState = engine.focusState
        taskProgressList = engine.taskProgress()
        let spectrum = engine.currentSpectrumAndMetrics(at: now)
        spectrumSegments = spectrum.segments
        metrics = spectrum.metrics
        latestSample = engine.lastSample
        updateElapsedFocusSeconds()

        if case .focusing(let taskId, _) = sessionState {
            lastTaskNote = engine.lastNote(for: taskId)
        } else if case .paused(let taskId, _) = sessionState {
            lastTaskNote = engine.lastNote(for: taskId)
        } else {
            lastTaskNote = nil
        }
    }

    private func updateElapsedFocusSeconds() {
        if case .focusing(let taskId, _) = engine.focusState {
            if let openSession = engine.focusSessions.last(where: { $0.taskId == taskId && $0.endedAt == nil }) {
                let baseSeconds = openSession.minutes * 60.0
                let extra = max(0, clock.now().timeIntervalSince(openSession.startedAt.addingTimeInterval(baseSeconds)))
                elapsedFocusSeconds = max(baseSeconds, baseSeconds + extra)
                return
            }
            elapsedFocusSeconds = engine.focusedMinutes(for: taskId) * 60.0
        } else {
            elapsedFocusSeconds = 0
        }
    }

    private func persistTodayIfNeeded() {
        guard !isSyntheticDemo, let store else { return }
        let snap = engine.snapshot(at: clock.now())
        try? store.saveToday(snap)
    }

    private func startOfDay(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        return cal.startOfDay(for: date)
    }
}

private final class StaticSyntheticInspector: ActivityInspecting, @unchecked Sendable {
    private let clock: any DayHelmClock

    init(clock: any DayHelmClock) {
        self.clock = clock
    }

    var isAccessibilityTrusted: Bool { true }

    func inspectCurrent() -> ActivitySample {
        ActivitySample(
            timestamp: clock.now(),
            appName: "Example Browser",
            bundleId: "com.example.browser",
            windowTitle: "Example Shop — 商品详情页预览",
            url: "https://shop.example.com/product/102",
            idleSeconds: 1,
            screenLocked: false,
            inputActive: true
        )
    }
}
