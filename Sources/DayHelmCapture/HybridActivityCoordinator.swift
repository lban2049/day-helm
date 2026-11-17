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

    @Published public var deepRecordingEnabled: Bool = true
    @Published public private(set) var screenCaptureTrusted: Bool = false
    @Published public private(set) var todaySnapshotCount: Int = 0
    @Published public private(set) var todayOCRCount: Int = 0
    @Published public private(set) var apiServerPort: UInt16?
    @Published public private(set) var apiServerPorts: [UInt16] = []

    public let isSyntheticDemo: Bool
    public let storeDirectoryURL: URL

    private let engine: DayHelmEngine
    private let store: DayHelmStore?
    private let almaClient: AlmaActivityClient?
    private let inspector: any ActivityInspecting
    private let clock: any DayHelmClock
    private let database: ActivityDatabase?
    private let screenRecorder: NativeScreenRecorder?
    private var httpServer: LocalActivityHTTPServer?
    private var eventMonitor: NativeEventMonitor?
    private var settings: DayHelmSettings

    private let runtimeStateBox = RuntimeStateBox()

    private var timerTask: Task<Void, Never>?
    private var almaSyncTask: Task<Void, Never>?
    private var lastAlmaEventMs: Int64?
    private var latestAlmaBrowserSample: ActivitySample?
    private var lastAlmaInputAt: Date?
    private var lastNativeInputAt: Date?
    private var lastRecordedSampleKey: String?
    private var lastRecordedHeartbeatAt: Date?
    private var lastRecordedAt: Date?
    private var lastRecordedAppName: String?
    private var lastRecordedURLKey: String?
    private var pendingTypingPauseAt: Date?
    private var idleSessionClosed: Bool = false
    private var lastPersistedAt: Date?
    private var tickCount: Int = 0
    private var isStarted: Bool = false

    private let minTitleChangeInterval: TimeInterval = 5.0
    private let typingPauseQuietSeconds: TimeInterval = 2.0

    public init(
        engine: DayHelmEngine,
        store: DayHelmStore?,
        almaClient: AlmaActivityClient?,
        inspector: any ActivityInspecting,
        clock: any DayHelmClock = SystemClock(),
        syntheticDemo: Bool = false,
        database: ActivityDatabase? = nil,
        screenRecorder: NativeScreenRecorder? = nil,
        httpServer: LocalActivityHTTPServer? = nil
    ) {
        self.engine = engine
        self.store = store
        self.almaClient = almaClient
        self.inspector = inspector
        self.clock = clock
        self.isSyntheticDemo = syntheticDemo
        self.database = database
        self.screenRecorder = screenRecorder
        self.httpServer = httpServer

        let loadedSettings = store?.loadSettings() ?? .default
        self.settings = loadedSettings
        self.deepRecordingEnabled = loadedSettings.deepRecordingEnabled
        self.storeDirectoryURL = store?.directory ?? DayHelmStore.defaultDirectory
        self.axTrusted = inspector.isAccessibilityTrusted
        self.screenCaptureTrusted = screenRecorder?.isScreenCaptureTrusted ?? false

        refreshPublishedState()
        refreshRecorderCounts()
        syncCachedRuntimeState()
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
        let database = try? ActivityDatabase(databaseURL: store.databaseURL)
        let recorder = database.map {
            NativeScreenRecorder(
                database: $0,
                snapshotsRootDir: store.snapshotsDirectory,
                clock: clock
            )
        }

        let coordinator = HybridActivityCoordinator(
            engine: engine,
            store: store,
            almaClient: almaClient,
            inspector: inspector,
            clock: clock,
            syntheticDemo: false,
            database: database,
            screenRecorder: recorder,
            httpServer: nil
        )

        if let database {
            coordinator.httpServer = LocalActivityHTTPServer(
                database: database,
                store: store,
                clock: clock,
                stateProvider: { [weak coordinator] in
                    coordinator?.readCachedRuntimeState() ?? LocalActivityHTTPServer.RuntimeState()
                }
            )
        }

        return coordinator
    }

    public static func makeSyntheticDemo(
        clock: any DayHelmClock = SystemClock(),
        inspector: (any ActivityInspecting)? = nil
    ) -> HybridActivityCoordinator {
        let now = clock.now()
        let budgets = TimeAuditConfigLoader.defaultBudgets
        let engine = DayHelmEngine(budgets: budgets, clock: clock)

        let morningStart = now.addingTimeInterval(-3.5 * 3600)

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
        coordinator.screenCaptureTrusted = true
        coordinator.todaySnapshotCount = 18
        coordinator.todayOCRCount = 18
        coordinator.apiServerPort = LocalActivityHTTPServer.defaultPrimaryPort
        coordinator.apiServerPorts = [LocalActivityHTTPServer.defaultPrimaryPort]
        coordinator.refreshPublishedState()
        return coordinator
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        if !isSyntheticDemo {
            if !inspector.isAccessibilityTrusted {
                axTrusted = inspector.requestAccessibilityPrompt()
            } else {
                axTrusted = true
            }
            screenCaptureTrusted = screenRecorder?.isScreenCaptureTrusted ?? false
            refreshRecorderCounts()
            syncCachedRuntimeState()

            if let server = httpServer {
                Task { [weak self] in
                    let ports = await server.start(
                        primaryPort: LocalActivityHTTPServer.defaultPrimaryPort,
                        fallbackPort: nil
                    )
                    await MainActor.run {
                        self?.apiServerPorts = ports
                        self?.apiServerPort = ports.first
                    }
                    await self?.syncFromAlma(isInitialBackfill: true)
                }
            } else {
                Task { [weak self] in
                    await self?.syncFromAlma(isInitialBackfill: true)
                }
            }

            if eventMonitor == nil {
                let monitor = NativeEventMonitor(clock: clock) { [weak self] event in
                    Task { @MainActor [weak self] in
                        self?.handleNativeMonitorEvent(event)
                    }
                }
                monitor.start()
                eventMonitor = monitor
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
        eventMonitor?.stop()
        eventMonitor = nil
        httpServer?.stop()
        apiServerPort = nil
        apiServerPorts = []
        let endMs = Int64(clock.now().timeIntervalSince1970 * 1000)
        try? database?.closeActiveSessionIfNeeded(endedAtMs: endMs)
        persistTodayIfNeeded()
    }

    // MARK: - User Actions

    public func setDeepRecordingEnabled(_ enabled: Bool) {
        deepRecordingEnabled = enabled
        settings.deepRecordingEnabled = enabled
        if !isSyntheticDemo, let store {
            try? store.saveSettings(settings)
        }
        syncCachedRuntimeState()
    }

    @discardableResult
    public func requestScreenCapturePermission() -> Bool {
        let granted = screenRecorder?.requestScreenCapturePermission() ?? CGRequestScreenCaptureAccess()
        screenCaptureTrusted = granted
        if !granted {
            openScreenRecordingSettings()
        }
        syncCachedRuntimeState()
        return granted
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

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
        axTrusted = inspector.requestAccessibilityPrompt()
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
        if let screenRecorder {
            screenCaptureTrusted = screenRecorder.isScreenCaptureTrusted
        }

        var sample = PrivacyRedactor.redact(inspector.inspectCurrent(), config: engine.config.privacyConfig)

        if !sample.screenLocked {
            var patchedTitle = sample.windowTitle
            var patchedURL = sample.url
            var patchedInputActive = sample.inputActive
            var patchedIdle = sample.idleSeconds

            if let recentNative = lastNativeInputAt, now.timeIntervalSince(recentNative) <= 3.0 {
                patchedInputActive = true
                patchedIdle = min(patchedIdle, now.timeIntervalSince(recentNative))
            }
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

        // Idle / locked: close the open session at its last activity and stop screenshots.
        let isAbsent = sample.screenLocked || sample.idleSeconds >= engine.config.idleThresholdSeconds
        if isAbsent {
            pendingTypingPauseAt = nil
            if !idleSessionClosed, !isSyntheticDemo, let database {
                try? database.closeActiveSessionAtLastActivity()
                idleSessionClosed = true
            }
        } else {
            idleSessionClosed = false
            if let pending = pendingTypingPauseAt,
               sample.timestamp.timeIntervalSince(pending) >= typingPauseQuietSeconds {
                pendingTypingPauseAt = nil
                screenRecorder?.triggerTypingPauseCaptureIfNeeded(
                    sample: sample,
                    deepRecordingEnabled: deepRecordingEnabled,
                    declaredTaskId: currentDeclaredTaskId(),
                    idleThresholdSeconds: engine.config.idleThresholdSeconds
                ) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.refreshRecorderCounts()
                    }
                }
            }
        }

        recordSampleToDatabaseIfNeeded(sample)
        if !isAbsent {
            screenRecorder?.evaluatePeriodicCaptureIfNeeded(
                sample: sample,
                deepRecordingEnabled: deepRecordingEnabled,
                declaredTaskId: currentDeclaredTaskId(),
                idleThresholdSeconds: engine.config.idleThresholdSeconds,
                retentionDays: settings.snapshotRetentionDays
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.refreshRecorderCounts()
                }
            }
        }
        screenRecorder?.runRetentionMaintenanceIfNeeded(
            retentionDays: settings.snapshotRetentionDays,
            now: now
        )

        refreshPublishedState()
        if lastPersistedAt == nil || now.timeIntervalSince(lastPersistedAt!) >= 10.0 {
            persistTodayIfNeeded()
        }
        syncCachedRuntimeState()
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
                refreshRecorderCounts()
            }
        }
    }

    private func handleNativeMonitorEvent(_ event: NativeMonitorEvent) {
        guard !isSyntheticDemo else { return }
        let tsMs = Int64(event.timestamp.timeIntervalSince1970 * 1000)
        let taskId = currentDeclaredTaskId()

        switch event.kind {
        case "app_focus":
            let sample = PrivacyRedactor.redact(inspector.inspectCurrent(), config: engine.config.privacyConfig)
            let alerts = engine.ingest(sample)
            if let newest = alerts.last {
                activeAlert = newest
            }
            if !sample.screenLocked {
                recordSampleToDatabaseIfNeeded(sample)
                screenRecorder?.triggerAppFocusCaptureIfNeeded(
                    sample: sample,
                    deepRecordingEnabled: deepRecordingEnabled,
                    declaredTaskId: taskId,
                    idleThresholdSeconds: engine.config.idleThresholdSeconds
                ) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.refreshRecorderCounts()
                    }
                }
            }
            refreshPublishedState()
            syncCachedRuntimeState()

        case "lock":
            _ = try? database?.insertEvent(
                timestampMs: tsMs,
                kind: "lock",
                appName: "loginwindow",
                declaredTaskId: taskId,
                project: taskId
            )
            pollOnce()

        case "unlock":
            _ = try? database?.insertEvent(
                timestampMs: tsMs,
                kind: "unlock",
                appName: "loginwindow",
                declaredTaskId: taskId,
                project: taskId
            )
            pollOnce()

        case "click", "keypress":
            lastNativeInputAt = event.timestamp
            if event.kind == "keypress" {
                pendingTypingPauseAt = event.timestamp
            }
            if latestSample?.screenLocked != true {
                _ = try? database?.insertEvent(
                    timestampMs: tsMs,
                    kind: event.kind,
                    appName: latestSample?.appName,
                    windowTitle: latestSample?.redacted == true ? nil : latestSample?.windowTitle,
                    url: latestSample?.redacted == true ? nil : latestSample?.url,
                    data: [:],
                    declaredTaskId: taskId,
                    project: taskId
                )
            }
            if event.kind == "click", let sample = latestSample, !sample.screenLocked {
                let clickSample = ActivitySample(
                    timestamp: event.timestamp,
                    appName: sample.appName,
                    bundleId: sample.bundleId,
                    windowTitle: sample.windowTitle,
                    url: sample.url,
                    idleSeconds: sample.idleSeconds,
                    screenLocked: sample.screenLocked,
                    inputActive: true,
                    redacted: sample.redacted
                )
                screenRecorder?.triggerClickCaptureIfNeeded(
                    sample: clickSample,
                    deepRecordingEnabled: deepRecordingEnabled,
                    declaredTaskId: taskId,
                    idleThresholdSeconds: engine.config.idleThresholdSeconds
                ) { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.refreshRecorderCounts()
                    }
                }
            }

        default:
            break
        }
    }

    private func recordSampleToDatabaseIfNeeded(_ sample: ActivitySample) {
        guard !isSyntheticDemo, let database else { return }
        guard !sample.screenLocked, sample.idleSeconds < engine.config.idleThresholdSeconds else {
            return
        }

        let key = ActivityTextNormalizer.normalizedChangeKey(
            appName: sample.appName,
            bundleId: sample.bundleId,
            title: sample.windowTitle,
            url: sample.url
        )
        let appChanged = (sample.appName != lastRecordedAppName)
        let keyChanged = (key != lastRecordedSampleKey)
        let heartbeatDue = lastRecordedHeartbeatAt.map { sample.timestamp.timeIntervalSince($0) >= 30.0 } ?? true
        // Title-only jitter is throttled; app switches are always recorded immediately.
        let withinTitleThrottle: Bool = {
            guard !appChanged, let last = lastRecordedAt else { return false }
            return sample.timestamp.timeIntervalSince(last) < minTitleChangeInterval
        }()

        guard heartbeatDue || (keyChanged && !withinTitleThrottle) else { return }

        let tsMs = Int64(sample.timestamp.timeIntervalSince1970 * 1000)
        let taskId = currentDeclaredTaskId()
        let urlKey = ActivityClassifier.normalizedURLKey(sample.url)
        let urlChanged = (urlKey != nil && urlKey != lastRecordedURLKey)

        var eventData: [String: String] = [:]
        if let bundleId = sample.bundleId { eventData["bundleId"] = bundleId }
        eventData["appName"] = sample.appName
        if !sample.redacted {
            if let title = sample.windowTitle { eventData["windowTitle"] = title }
            if let url = sample.url { eventData["url"] = url }
        } else {
            eventData["redacted"] = "true"
        }

        // Browser visits require a real web URL in a browser AND an actual URL change;
        // title-only changes stay as app_focus to avoid jitter masquerading as new pages.
        let classified = ActivityClassifier.eventKind(
            appName: sample.appName,
            bundleId: sample.bundleId,
            url: sample.url,
            redacted: sample.redacted
        )
        let kind = (classified == ActivityEventKind.browserVisit.rawValue && !urlChanged)
            ? ActivityEventKind.appFocus.rawValue
            : classified

        _ = try? database.insertEvent(
            timestampMs: tsMs,
            kind: kind,
            appName: sample.appName,
            windowTitle: sample.redacted ? nil : sample.windowTitle,
            url: sample.redacted ? nil : sample.url,
            data: eventData,
            declaredTaskId: taskId,
            project: taskId
        )

        lastRecordedSampleKey = key
        lastRecordedAppName = sample.appName
        lastRecordedAt = sample.timestamp
        lastRecordedHeartbeatAt = sample.timestamp
        if kind == ActivityEventKind.browserVisit.rawValue {
            lastRecordedURLKey = urlKey
        }
    }

    private func syncFromAlma(isInitialBackfill: Bool) async {
        guard let almaClient else { return }
        guard httpServer?.isServingPort(LocalActivityHTTPServer.almaReservedPort) != true else {
            almaConnected = false
            return
        }

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
                    for alert in engine.pendingAlerts {
                        engine.dismissAlert(id: alert.id)
                    }
                } else {
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
        let endMs = Int64(now.timeIntervalSince1970 * 1000)
        try? database?.closeActiveSessionIfNeeded(endedAtMs: endMs)
        if !isSyntheticDemo, let store {
            let prevSnapshot = engine.snapshot(at: now)
            _ = try? store.rolloverIfNeeded(currentSnapshot: prevSnapshot, newDateString: currentDay)
        }
        engine.rolloverToNewDay(currentDay)
        lastAlmaEventMs = nil
        latestAlmaBrowserSample = nil
        lastRecordedSampleKey = nil
        lastRecordedHeartbeatAt = nil
        activeAlert = nil
        refreshPublishedState()
        refreshRecorderCounts()
        syncCachedRuntimeState()
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
        syncCachedRuntimeState()
    }

    private func refreshRecorderCounts() {
        guard !isSyntheticDemo, let database else { return }
        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let dayEndMs = dayStartMs + 86_400_000 - 1
        if let counts = try? database.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs) {
            todaySnapshotCount = counts.snapshots
            todayOCRCount = counts.ocrFrames
        }
    }

    private func syncCachedRuntimeState() {
        let snap = engine.snapshot(at: clock.now())
        let state = LocalActivityHTTPServer.RuntimeState(
            axTrusted: axTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            deepRecordingEnabled: deepRecordingEnabled,
            daySnapshot: snap
        )
        runtimeStateBox.update(state)
    }

    public nonisolated func currentRuntimeState() -> LocalActivityHTTPServer.RuntimeState {
        runtimeStateBox.read()
    }

    private nonisolated func readCachedRuntimeState() -> LocalActivityHTTPServer.RuntimeState {
        runtimeStateBox.read()
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
        let now = clock.now()
        let snap = engine.snapshot(at: now)
        try? store.saveToday(snap)
        lastPersistedAt = now
    }

    private func currentDeclaredTaskId() -> String? {
        if case .focusing(let taskId, _) = engine.focusState {
            return taskId
        }
        return nil
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

private final class RuntimeStateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var state = LocalActivityHTTPServer.RuntimeState()

    func update(_ newState: LocalActivityHTTPServer.RuntimeState) {
        lock.lock()
        state = newState
        lock.unlock()
    }

    func read() -> LocalActivityHTTPServer.RuntimeState {
        lock.lock()
        defer { lock.unlock() }
        return state
    }
}
