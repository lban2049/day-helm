import AppKit
import Combine
import DayHelmCore
import Foundation

public enum MenuBarVisualState: Equatable, Sendable {
    case standby
    case focusing
    case targetMet
    case capReached
    case otherWork
    case distraction
}

@MainActor
public final class MenuBarPillModel: ObservableObject {
    @Published public var text: String = ""
    @Published public var helpText: String = "DayHelm · 待命"
    @Published public var visualState: MenuBarVisualState = .standby
    public init() {}
}

@MainActor
public final class HybridActivityCoordinator: ObservableObject {
    public let pillModel = MenuBarPillModel()
    public private(set) var isPopoverVisible: Bool = false
    public private(set) var isRecorderWindowVisible: Bool = false
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
    @Published public private(set) var recorderSettings: DayHelmSettings = .default
    @Published public private(set) var recorderStats: RecorderStorageStats = RecorderStorageStats()
    @Published public private(set) var recentSessions: [RecordedSessionSummary] = []
    @Published public private(set) var screenCaptureTrusted: Bool = false
    @Published public private(set) var todaySnapshotCount: Int = 0
    @Published public private(set) var todayOCRCount: Int = 0
    @Published public private(set) var apiServerPort: UInt16?
    @Published public private(set) var apiServerPorts: [UInt16] = []

    // Jev semantic auto-tracking state
    @Published public private(set) var jevAPIKeyConfigured: Bool = false
    @Published public private(set) var jevAPIKeySource: JevAPIKeySource?
    @Published public private(set) var jevNeedsAPIKey: Bool = false
    @Published public private(set) var jevLastClassification: SemanticClassification?
    @Published public private(set) var jevLastError: String?
    @Published public private(set) var jevIsManualPinned: Bool = false
    @Published public private(set) var jevDecisionLogs: [JevDecisionLogEntry] = []
    @Published public private(set) var activeNonBudgetActivity: AutoNonBudgetActivity?
    @Published public private(set) var activeActivityMode: ActivityMode?
    @Published public private(set) var otherWorkMinutes: Double = 0.0
    @Published public private(set) var nonWorkMinutes: Double = 0.0
    @Published public private(set) var activityModeMinutes: [String: Double] = [:]
    @Published public private(set) var availableHistoricalStatsDates: [String] = []
    @Published public private(set) var isMaterializingHistoricalStats: Bool = false
    @Published public private(set) var historicalStatsRevision: Int = 0

    public let isSyntheticDemo: Bool
    public let storeDirectoryURL: URL

    private let engine: DayHelmEngine
    private let basePrivacyConfig: PrivacyRedactorConfig
    private let store: DayHelmStore?
    private let almaClient: AlmaActivityClient?
    private let inspector: any ActivityInspecting
    private let clock: any DayHelmClock
    private let database: ActivityDatabase?
    private let screenRecorder: NativeScreenRecorder?
    private let jevClient: JevActivityClient
    private let jevAPIKeyStore: JevAPIKeyStore
    private let semanticTracker = SemanticAutoTracker()
    private var httpServer: LocalActivityHTTPServer?
    private var eventMonitor: NativeEventMonitor?
    private var windowChangeObserver: AXWindowChangeObserver?
    private var settings: DayHelmSettings
    private var syntheticSessionDetails: [RecordedSessionDetail] = []
    private var syntheticHistorySnapshots: [String: DayHelmDaySnapshot] = [:]
    private var syntheticHistoryReports: [String: DailyStatsReport] = [:]

    public var enableLiveTimersForTesting: Bool = false

    private let runtimeStateBox = RuntimeStateBox()

    private var timerTask: Task<Void, Never>?
    private var almaSyncTask: Task<Void, Never>?
    private var statsMaterializationQueueTask: Task<Void, Never>?
    private var typingPauseTask: Task<Void, Never>?
    private var jevClassifyTask: Task<Void, Never>?
    private var jevDwellTask: Task<Void, Never>?
    private var jevDwellTargetContextKey: String?
    private var jevDwellScheduledAt: Date?
    private var jevDwellScheduledDelay: TimeInterval?
    private var jevPendingConfirmTask: Task<Void, Never>?
    private var jevContextOCRTask: Task<Void, Never>?
    private var jevContextOCRTargetKey: String?
    private var jevContextOCRCompletedForContextKey: String?
    private var lastAlmaEventMs: Int64?
    private var latestAlmaBrowserSample: ActivitySample?
    private var lastAlmaInputAt: Date?
    private var lastNativeInputAt: Date?
    private var lastRecordedSampleKey: String?
    private var lastRecordedHeartbeatAt: Date?
    private var lastRecordedAt: Date?
    private var lastRecordedAppName: String?
    private var lastRecordedURLKey: String?
    private var idleSessionClosed: Bool = false
    private var lastPersistedAt: Date?
    private var tickCount: Int = 0
    private var isStarted: Bool = false
    private var recorderCountRefreshInFlight: Bool = false

    private var observedContextKey: String?
    private var observedContextSince: Date?
    private var jevInFlightSignature: String?
    private var lastJevClassifiedSignature: String?
    private var lastJevErrorAt: Date?

    private let minTitleChangeInterval: TimeInterval = 5.0
    private let jevContextOCRDelaySeconds: TimeInterval = 0.35
    private var typingPauseQuietSeconds: TimeInterval = 2.0

    private var shouldScheduleEventTimers: Bool {
        isStarted || enableLiveTimersForTesting
    }

    public init(
        engine: DayHelmEngine,
        store: DayHelmStore?,
        almaClient: AlmaActivityClient?,
        inspector: any ActivityInspecting,
        clock: any DayHelmClock = SystemClock(),
        syntheticDemo: Bool = false,
        database: ActivityDatabase? = nil,
        screenRecorder: NativeScreenRecorder? = nil,
        httpServer: LocalActivityHTTPServer? = nil,
        jevClient: JevActivityClient = JevActivityClient(),
        jevAPIKeyStore: JevAPIKeyStore? = nil
    ) {
        self.engine = engine
        self.basePrivacyConfig = engine.config.privacyConfig
        self.store = store
        self.almaClient = almaClient
        self.inspector = inspector
        self.clock = clock
        self.isSyntheticDemo = syntheticDemo
        self.database = database
        self.screenRecorder = screenRecorder
        self.httpServer = httpServer
        self.jevClient = jevClient
        let storeDir = store?.directory ?? DayHelmStore.defaultDirectory
        self.jevAPIKeyStore = jevAPIKeyStore ?? JevAPIKeyStore(directory: storeDir)

        let loadedSettings = store?.loadSettings() ?? .default
        self.settings = loadedSettings
        self.recorderSettings = loadedSettings
        self.deepRecordingEnabled = loadedSettings.deepRecordingEnabled
        self.typingPauseQuietSeconds = TimeInterval(max(200, loadedSettings.typingPauseQuietMs)) / 1000.0
        self.storeDirectoryURL = storeDir
        self.axTrusted = inspector.isAccessibilityTrusted
        self.screenCaptureTrusted = screenRecorder?.isScreenCaptureTrusted ?? false

        let effectivePrivacy = loadedSettings.makePrivacyRedactorConfig(base: basePrivacyConfig)
        engine.updatePrivacyConfig(effectivePrivacy)
        inspector.updatePrivacyConfig(effectivePrivacy)
        screenRecorder?.applySettings(loadedSettings)

        if !syntheticDemo, let store {
            self.jevDecisionLogs = store.loadJevDecisionLogs(forDate: engine.currentDateString)
            let todayStr = engine.currentDateString
            var initialDates = Set<String>(store.listMaterializedStatsDayStrings().filter { $0 < todayStr })
            for archived in store.listArchivedDayStrings() where archived < todayStr {
                initialDates.insert(archived)
            }
            self.availableHistoricalStatsDates = initialDates.sorted(by: >)
        }

        refreshJevAPIKeyStatus()
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

        let liveConfig = DayHelmEngineConfig(maxTickGapSeconds: 60.0)
        let engine: DayHelmEngine
        if let existing = try? store.loadToday() {
            if existing.date == todayStr {
                engine = DayHelmEngine(snapshot: existing, budgets: budgets, clock: clock, config: liveConfig)
            } else {
                _ = try? store.rolloverIfNeeded(currentSnapshot: existing, newDateString: todayStr)
                engine = DayHelmEngine(budgets: budgets, clock: clock, config: liveConfig)
            }
        } else {
            engine = DayHelmEngine(budgets: budgets, clock: clock, config: liveConfig)
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

        let demoDetails = Self.makeSyntheticSessionDetails(now: now)
        coordinator.syntheticSessionDetails = demoDetails
        let historySnapshots = Self.makeSyntheticHistorySnapshots(now: now, budgets: budgets)
        coordinator.syntheticHistorySnapshots = historySnapshots
        coordinator.syntheticHistoryReports = Self.makeSyntheticHistoryReports(
            snapshots: historySnapshots,
            budgets: budgets,
            clock: clock
        )
        coordinator.availableHistoricalStatsDates = coordinator.availableStatsDates()
        coordinator.recentSessions = demoDetails.map(\.session)
        coordinator.recorderStats = RecorderStorageStats(
            totalSessions: demoDetails.count,
            totalEvents: demoDetails.reduce(0) { $0 + $1.events.count },
            totalSnapshots: demoDetails.reduce(0) { $0 + $1.snapshots.count },
            totalOCRFrames: demoDetails.reduce(0) { $0 + $1.ocrFrames.count },
            usedSnapshotBytes: 42_600_000,
            activeSessionId: demoDetails.first?.session.id,
            activeSessionStartedAt: demoDetails.first?.session.startedAt
        )
        coordinator.refreshPublishedState()
        return coordinator
    }

    private static func makeSyntheticSessionDetails(now: Date) -> [RecordedSessionDetail] {
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let s1Start = nowMs - 17 * 60_000
        let s2Start = nowMs - 70 * 60_000
        let s2End = s2Start + 26 * 60_000
        let s3Start = nowMs - 210 * 60_000
        let s3End = s3Start + 35 * 60_000

        let d1 = RecordedSessionDetail(
            session: RecordedSessionSummary(
                id: "demo_sess_1",
                startedAt: s1Start,
                endedAt: nil,
                durationMs: nil,
                triggerKind: "app_focus",
                appNames: ["Example Browser", "Terminal"],
                eventCount: 4,
                snapshotCount: 2,
                totalBytes: 184_000,
                analysisStatus: "analyzed",
                analysisTitle: "Example Shop 商品详情页与脚本联调",
                analysisDescription: "优化主图卖点文案并验证本地导出脚本输出。",
                storageTier: "hot",
                entities: ["domain": ["shop.example.com"], "repo": ["focus-guard"]],
                topics: ["主图优化", "详情页预览"],
                project: "ecommerce",
                declaredTaskId: "ecommerce",
                createdAt: s1Start,
                updatedAt: nowMs - 10_000,
                clickCount: 32,
                keypressCount: 218
            ),
            events: [
                RecordedActivityEvent(
                    id: "demo_evt_1",
                    sessionId: "demo_sess_1",
                    timestamp: s1Start,
                    kind: "app_focus",
                    appName: "Example Browser",
                    windowTitle: "Example Shop — 商品详情页预览",
                    url: "https://shop.example.com/product/102",
                    createdAt: s1Start
                ),
                RecordedActivityEvent(
                    id: "demo_evt_2",
                    sessionId: "demo_sess_1",
                    timestamp: s1Start + 5 * 60_000,
                    kind: "keypress",
                    appName: "Terminal",
                    windowTitle: "swift test — focus-guard",
                    data: ["count": "120"],
                    createdAt: s1Start + 5 * 60_000
                )
            ],
            snapshots: [
                RecordedSnapshot(
                    id: "demo_snap_1",
                    sessionId: "demo_sess_1",
                    timestamp: s1Start + 60_000,
                    filePath: "/tmp/demo_snap_1.jpg",
                    width: 1440,
                    height: 900,
                    sizeBytes: 92_000,
                    trigger: "app_focus",
                    appName: "Example Browser",
                    windowTitle: "Example Shop — 商品详情页预览",
                    storageTier: "hot",
                    createdAt: s1Start + 60_000
                )
            ],
            ocrFrames: [
                RecordedOCRFrame(
                    id: "demo_ocr_1",
                    snapshotId: "demo_snap_1",
                    sessionId: "demo_sess_1",
                    text: "Example Shop · 商品详情页主图卖点检查\nSKU: EX-102 · 状态: 待上线",
                    charCount: 38,
                    tokenCount: 16,
                    createdAt: s1Start + 60_000
                )
            ]
        )

        let d2 = RecordedSessionDetail(
            session: RecordedSessionSummary(
                id: "demo_sess_2",
                startedAt: s2Start,
                endedAt: s2End,
                durationMs: s2End - s2Start,
                triggerKind: "app_focus",
                appNames: ["Example Browser"],
                eventCount: 6,
                snapshotCount: 3,
                totalBytes: 248_000,
                analysisStatus: "analyzed",
                analysisTitle: "Support Ticket #1042 退换货工单处理",
                analysisDescription: "核对订单物流状态并完成工单回复。",
                storageTier: "hot",
                entities: ["domain": ["ops.example.com"]],
                topics: ["工单处理"],
                project: "ecommerce-ops",
                declaredTaskId: "ecommerce-ops",
                createdAt: s2Start,
                updatedAt: s2End,
                clickCount: 45,
                keypressCount: 164
            ),
            events: [
                RecordedActivityEvent(
                    id: "demo_evt_3",
                    sessionId: "demo_sess_2",
                    timestamp: s2Start,
                    kind: "browser_visit",
                    appName: "Example Browser",
                    windowTitle: "Support Ticket #1042 — 订单处理",
                    url: "https://ops.example.com/tickets/1042",
                    createdAt: s2Start
                )
            ],
            snapshots: [],
            ocrFrames: []
        )

        let d3 = RecordedSessionDetail(
            session: RecordedSessionSummary(
                id: "demo_sess_3",
                startedAt: s3Start,
                endedAt: s3End,
                durationMs: s3End - s3Start,
                triggerKind: "app_focus",
                appNames: ["Example Notes", "Example Browser"],
                eventCount: 9,
                snapshotCount: 4,
                totalBytes: 312_000,
                analysisStatus: "analyzed",
                analysisTitle: "Hermes Q4 行业研报摘录整理",
                analysisDescription: "整理宏观数据摘要并归档关键结论。",
                isMeeting: false,
                storageTier: "warm",
                entities: ["domain": ["docs.example.com"]],
                topics: ["Q4 研报", "行业分析"],
                project: "hermes",
                declaredTaskId: "hermes",
                createdAt: s3Start,
                updatedAt: s3End,
                clickCount: 28,
                keypressCount: 342
            ),
            events: [
                RecordedActivityEvent(
                    id: "demo_evt_4",
                    sessionId: "demo_sess_3",
                    timestamp: s3Start,
                    kind: "app_focus",
                    appName: "Example Notes",
                    windowTitle: "Hermes Equity Research — 行业周报",
                    createdAt: s3Start
                )
            ],
            snapshots: [],
            ocrFrames: []
        )

        return [d1, d2, d3]
    }

    // MARK: - Daily Stats & Local Agent Prompt

    public var todayDateString: String {
        engine.currentDateString
    }

    public func availableStatsDates() -> [String] {
        let todayStr = todayDateString
        if isSyntheticDemo {
            return syntheticHistoryReports.keys
                .filter { $0 < todayStr }
                .sorted(by: >)
        }
        var dates = Set<String>(availableHistoricalStatsDates.filter { $0 < todayStr })
        if let store {
            for key in store.listMaterializedStatsDayStrings() where key < todayStr {
                dates.insert(key)
            }
            for key in store.listArchivedDayStrings() where key < todayStr {
                dates.insert(key)
            }
        }
        return dates.sorted(by: >)
    }

    public func refreshAvailableHistoricalDatesAsync() async -> [String] {
        let todayStr = todayDateString
        if isSyntheticDemo {
            let demoDates = syntheticHistoryReports.keys.filter { $0 < todayStr }.sorted(by: >)
            if availableHistoricalStatsDates != demoDates {
                availableHistoricalStatsDates = demoDates
            }
            return demoDates
        }
        guard let store else { return [] }
        let db = database
        let discovered = await Task.detached(priority: .utility) {
            DailyStatsMaterializer.discoverHistoricalCandidateDates(
                store: store,
                database: db,
                todayDateString: todayStr
            )
        }.value
        if availableHistoricalStatsDates != discovered {
            availableHistoricalStatsDates = discovered
        }
        return discovered
    }

    /// Asynchronously loads a precomputed historical report (`< todayDateString`) off the main thread.
    /// Never computes or returns today's live report so tab/date switching stays instantaneous.
    public func loadHistoricalDailyStats(
        for dateString: String,
        forceRebuild: Bool = false
    ) async -> DailyStatsReport? {
        let todayStr = todayDateString
        guard dateString < todayStr else { return nil }

        if isSyntheticDemo {
            return syntheticHistoryReports[dateString]
        }

        guard let store else { return nil }
        let db = database
        let budgets = engine.budgets
        let clock = self.clock

        let result = await Task.detached(priority: .utility) {
            DailyStatsMaterializer.loadOrMaterializeHistoricalStats(
                dateString: dateString,
                store: store,
                database: db,
                budgets: budgets,
                clock: clock,
                forceRebuild: forceRebuild
            )
        }.value

        if let result, !result.loadedFromCache {
            _ = await refreshAvailableHistoricalDatesAsync()
        }
        return result?.report
    }

    public func scheduleHistoricalStatsMaterialization(forceRebuildDate: String? = nil) {
        guard !isSyntheticDemo, let store else { return }
        let db = database
        let budgets = engine.budgets
        let clock = self.clock
        let previousTask = statsMaterializationQueueTask
        isMaterializingHistoricalStats = true

        let task = Task.detached(priority: .utility) { [weak self] in
            _ = await previousTask?.value
            guard !Task.isCancelled else { return }

            if let forceRebuildDate {
                _ = DailyStatsMaterializer.loadOrMaterializeHistoricalStats(
                    dateString: forceRebuildDate,
                    store: store,
                    database: db,
                    budgets: budgets,
                    clock: clock,
                    forceRebuild: true
                )
            } else {
                _ = DailyStatsMaterializer.materializeMissingHistoricalStats(
                    store: store,
                    database: db,
                    budgets: budgets,
                    clock: clock,
                    forceRebuild: false
                )
            }

            guard !Task.isCancelled else { return }
            let todayStr = DayHelmDateFormatting.dayString(from: clock.now())
            let updatedDates = DailyStatsMaterializer.discoverHistoricalCandidateDates(
                store: store,
                database: db,
                todayDateString: todayStr
            )

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.availableHistoricalStatsDates = updatedDates
                self.historicalStatsRevision &+= 1
                self.isMaterializingHistoricalStats = false
            }
        }
        statsMaterializationQueueTask = task
    }

    public func buildAgentAnalysisPrompt(
        for report: DailyStatsReport,
        preset: AgentAnalysisPromptPreset
    ) -> String {
        AgentAnalysisPromptBuilder.build(
            report: report,
            preset: preset,
            storeDirectory: storeDirectoryURL
        )
    }

    private static func makeSyntheticHistoryReports(
        snapshots: [String: DayHelmDaySnapshot],
        budgets: [TaskBudget],
        clock: any DayHelmClock
    ) -> [String: DailyStatsReport] {
        var reports: [String: DailyStatsReport] = [:]
        let sortedDays = snapshots.keys.sorted()
        for (idx, dayStr) in sortedDays.enumerated() {
            let syntheticTotals = DailyStatsAggregator.SyntheticRecorderTotals(
                sessions: 3 + idx,
                meetings: idx % 2,
                clicks: 120 + idx * 35,
                keypresses: 860 + idx * 190,
                snapshots: 14 + idx * 4,
                ocrFrames: 11 + idx * 3,
                activeSessionMs: Int64((115 + idx * 20) * 60_000)
            )
            reports[dayStr] = DailyStatsAggregator.aggregate(
                dateString: dayStr,
                liveSnapshot: nil,
                budgets: budgets,
                store: nil,
                database: nil,
                clock: clock,
                includeBaseline: true,
                syntheticTotals: syntheticTotals,
                archivedSnapshots: snapshots
            )
        }
        return reports
    }

    private static func makeSyntheticHistorySnapshots(
        now: Date,
        budgets: [TaskBudget]
    ) -> [String: DayHelmDaySnapshot] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        let todayStart = cal.startOfDay(for: now)
        var result: [String: DayHelmDaySnapshot] = [:]

        for offset in 1...3 {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let dayStr = DayHelmDateFormatting.dayString(from: dayStart)
            let workStart = dayStart.addingTimeInterval(9.5 * 3600)
            let dur1 = TimeInterval((75 + offset * 15) * 60)
            let dur2 = TimeInterval((30 + offset * 5) * 60)

            let spans = [
                EnrichedSpan(
                    startedAt: workStart,
                    endedAt: workStart.addingTimeInterval(dur1),
                    appName: "Example Browser",
                    bundleId: "com.example.browser",
                    windowTitle: "Example Shop — 商品企划",
                    url: "https://shop.example.com/product/100",
                    declaredTaskId: "ecommerce",
                    redacted: false,
                    semanticGroup: "proj:ecommerce"
                ),
                EnrichedSpan(
                    startedAt: workStart.addingTimeInterval(dur1 + 600),
                    endedAt: workStart.addingTimeInterval(dur1 + 600 + dur2),
                    appName: "Example Notes",
                    bundleId: "com.example.notes",
                    windowTitle: "Hermes Research Notes",
                    url: nil,
                    declaredTaskId: "hermes",
                    redacted: false,
                    semanticGroup: "proj:hermes"
                )
            ]
            let sessions = [
                FocusSessionRecord(id: "hist_s1_\(offset)", taskId: "ecommerce", startedAt: workStart, endedAt: workStart.addingTimeInterval(dur1), minutes: dur1 / 60.0),
                FocusSessionRecord(id: "hist_s2_\(offset)", taskId: "hermes", startedAt: workStart.addingTimeInterval(dur1 + 600), endedAt: workStart.addingTimeInterval(dur1 + 600 + dur2), minutes: dur2 / 60.0)
            ]
            let built = SpectrumBuilder.build(
                spans: spans,
                focusSessions: sessions,
                budgets: budgets,
                now: workStart.addingTimeInterval(dur1 + 600 + dur2)
            )
            let budgetSnapshots = budgets.map { b in
                let mins: Double
                if b.taskId == "ecommerce" { mins = dur1 / 60.0 }
                else if b.taskId == "hermes" { mins = dur2 / 60.0 }
                else { mins = 0 }
                return BudgetSnapshot(
                    taskId: b.taskId,
                    displayName: b.displayName,
                    focusedMinutes: mins,
                    targetMinutes: b.targetMinutes,
                    capMinutes: b.capMinutes,
                    status: BudgetStatusCode(from: BudgetStatus.compute(focusedMinutes: mins, targetMinutes: b.targetMinutes, capMinutes: b.capMinutes))
                )
            }
            result[dayStr] = DayHelmDaySnapshot(
                date: dayStr,
                budgets: budgetSnapshots,
                focusSessions: sessions,
                enrichedSpans: spans,
                metrics: built.metrics
            )
        }
        return result
    }

    // MARK: - Lifecycle

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        if !isSyntheticDemo {
            _ = try? database?.finalizeStaleOpenSessionsOnStartup()

            if !inspector.isAccessibilityTrusted {
                axTrusted = inspector.requestAccessibilityPrompt()
            } else {
                axTrusted = true
            }
            screenCaptureTrusted = screenRecorder?.isScreenCaptureTrusted ?? false
            refreshRecorderCounts()
            refreshRecorderSessions()
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
                let monitor = NativeEventMonitor(
                    clock: clock,
                    inputMonitoringEnabled: settings.inputMonitoringEnabled,
                    onRawInput: { [weak self] isKeypress, at in
                        Task { @MainActor [weak self] in
                            self?.handleRawInput(isKeypress: isKeypress, at: at)
                        }
                    },
                    onEvent: { [weak self] event in
                        Task { @MainActor [weak self] in
                            self?.handleNativeMonitorEvent(event)
                        }
                    }
                )
                monitor.start()
                eventMonitor = monitor
                syncCachedRuntimeState()
            }

            if windowChangeObserver == nil {
                let observer = AXWindowChangeObserver(coalesceSeconds: 0.06) { [weak self] in
                    self?.handleWindowContextChanged()
                }
                if let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                    observer.attach(pid: frontPID)
                }
                windowChangeObserver = observer
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
            scheduleHistoricalStatsMaterialization()
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
        statsMaterializationQueueTask?.cancel()
        statsMaterializationQueueTask = nil
        isMaterializingHistoricalStats = false
        typingPauseTask?.cancel()
        typingPauseTask = nil
        jevClassifyTask?.cancel()
        jevClassifyTask = nil
        jevInFlightSignature = nil
        cancelJevScheduledTimers()
        windowChangeObserver?.stop()
        windowChangeObserver = nil
        eventMonitor?.stop()
        eventMonitor = nil
        httpServer?.stop()
        apiServerPort = nil
        apiServerPorts = []
        let endMs = Int64(clock.now().timeIntervalSince1970 * 1000)
        try? database?.closeActiveSessionIfNeeded(endedAtMs: endMs)
        VisionOCRService.shutdownWorker()
        persistTodayIfNeeded()
    }

    // MARK: - User Actions

    public func setDeepRecordingEnabled(_ enabled: Bool) {
        var next = settings
        next.deepRecordingEnabled = enabled
        updateRecorderSettings(next)
    }

    public func updateRecorderSettings(_ newSettings: DayHelmSettings) {
        let normalized = DayHelmSettings(
            activityRecorderEnabled: newSettings.activityRecorderEnabled,
            deepRecordingEnabled: newSettings.deepRecordingEnabled,
            visionOCREnabled: newSettings.visionOCREnabled,
            inputMonitoringEnabled: newSettings.inputMonitoringEnabled,
            appFocusDebounceMs: newSettings.appFocusDebounceMs,
            heartbeatIntervalMs: newSettings.heartbeatIntervalMs,
            recorderIdleThresholdMs: newSettings.recorderIdleThresholdMs,
            typingPauseQuietMs: newSettings.typingPauseQuietMs,
            visualCheckIntervalMs: newSettings.visualCheckIntervalMs,
            jpegQuality: newSettings.jpegQuality,
            ocrLanguages: newSettings.ocrLanguages,
            sensitiveBundleIds: newSettings.sensitiveBundleIds,
            snapshotRetentionDays: newSettings.snapshotRetentionDays,
            snapshotMaxStorageBytes: newSettings.snapshotMaxStorageBytes,
            ocrEveryN: newSettings.ocrEveryN,
            menuBarDisplayMode: newSettings.menuBarDisplayMode,
            jevAutoTrackingEnabled: newSettings.jevAutoTrackingEnabled,
            jevModel: newSettings.jevModel,
            jevSendOCRSnippet: newSettings.jevSendOCRSnippet
        )

        let wasRecorderEnabled = settings.activityRecorderEnabled
        let wasJevEnabled = settings.jevAutoTrackingEnabled
        settings = normalized
        recorderSettings = normalized
        deepRecordingEnabled = normalized.deepRecordingEnabled
        typingPauseQuietSeconds = TimeInterval(max(200, normalized.typingPauseQuietMs)) / 1000.0

        if !isSyntheticDemo, let store {
            try? store.saveSettings(normalized)
        }

        let effectivePrivacy = normalized.makePrivacyRedactorConfig(base: basePrivacyConfig)
        engine.updatePrivacyConfig(effectivePrivacy)
        inspector.updatePrivacyConfig(effectivePrivacy)
        screenRecorder?.applySettings(normalized)
        eventMonitor?.setInputMonitoringEnabled(normalized.inputMonitoringEnabled)

        if wasJevEnabled && !normalized.jevAutoTrackingEnabled {
            jevClassifyTask?.cancel()
            jevClassifyTask = nil
            jevInFlightSignature = nil
            cancelJevScheduledTimers()
            jevLastError = nil
        }
        refreshJevAPIKeyStatus()

        if wasRecorderEnabled && !normalized.activityRecorderEnabled {
            typingPauseTask?.cancel()
            typingPauseTask = nil
            if !isSyntheticDemo, let database {
                let endMs = Int64(clock.now().timeIntervalSince1970 * 1000)
                try? database.closeActiveSessionIfNeeded(endedAtMs: endMs)
            }
            idleSessionClosed = true
        } else if !wasRecorderEnabled && normalized.activityRecorderEnabled {
            idleSessionClosed = false
        }

        refreshRecorderCounts()
        refreshRecorderSessions()
        _ = refreshPublishedState(now: clock.now(), forceUI: false)
        syncCachedRuntimeState()
    }

    public func refreshPermissions() {
        axTrusted = inspector.isAccessibilityTrusted
        if let screenRecorder {
            screenCaptureTrusted = screenRecorder.isScreenCaptureTrusted
        }
        syncCachedRuntimeState()
    }

    public func refreshRecorderSessions(searchQuery: String? = nil, limit: Int = 50) {
        let trimmedQuery = searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isSyntheticDemo {
            if trimmedQuery.isEmpty {
                recentSessions = Array(syntheticSessionDetails.map(\.session).prefix(max(1, limit)))
            } else {
                let lower = trimmedQuery.lowercased()
                recentSessions = syntheticSessionDetails
                    .filter { detail in
                        let s = detail.session
                        if (s.analysisTitle?.lowercased().contains(lower) ?? false)
                            || (s.analysisDescription?.lowercased().contains(lower) ?? false)
                            || s.appNames.contains(where: { $0.lowercased().contains(lower) })
                            || (s.project?.lowercased().contains(lower) ?? false) {
                            return true
                        }
                        if detail.events.contains(where: {
                            ($0.appName?.lowercased().contains(lower) ?? false)
                                || ($0.windowTitle?.lowercased().contains(lower) ?? false)
                                || ($0.url?.lowercased().contains(lower) ?? false)
                        }) {
                            return true
                        }
                        return detail.ocrFrames.contains(where: { $0.text.lowercased().contains(lower) })
                    }
                    .map(\.session)
                    .prefix(max(1, limit))
                    .map { $0 }
            }
            return
        }

        guard let database else {
            recentSessions = []
            return
        }

        if trimmedQuery.isEmpty {
            recentSessions = (try? database.listSessions(limit: max(1, limit))) ?? []
        } else {
            recentSessions = (try? database.searchSessions(keyword: trimmedQuery, limit: max(1, limit))) ?? []
        }
    }

    public func loadSessionDetail(sessionId: String) -> RecordedSessionDetail? {
        if isSyntheticDemo {
            return syntheticSessionDetails.first(where: { $0.session.id == sessionId })
        }
        return try? database?.getSessionDetail(sessionId: sessionId)
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

    public func refreshJevAPIKeyStatus() {
        let resolved = jevAPIKeyStore.resolveKey()
        let configured = (resolved != nil)
        if jevAPIKeyConfigured != configured {
            jevAPIKeyConfigured = configured
        }
        if jevAPIKeySource != resolved?.source {
            jevAPIKeySource = resolved?.source
        }
        let needsKey = settings.jevAutoTrackingEnabled && !configured
        if jevNeedsAPIKey != needsKey {
            jevNeedsAPIKey = needsKey
        }
        engine.setAutoTrackingActive(settings.jevAutoTrackingEnabled && configured)
    }

    public func saveJevAPIKey(_ rawKey: String) throws {
        try jevAPIKeyStore.saveKey(rawKey)
        jevLastError = nil
        lastJevErrorAt = nil
        lastJevClassifiedSignature = nil
        refreshJevAPIKeyStatus()
        _ = refreshPublishedState(now: clock.now(), forceUI: false)
    }

    public func clearJevAPIKey() throws {
        try jevAPIKeyStore.deleteKey()
        jevClassifyTask?.cancel()
        jevClassifyTask = nil
        jevInFlightSignature = nil
        cancelJevScheduledTimers()
        refreshJevAPIKeyStatus()
        _ = refreshPublishedState(now: clock.now(), forceUI: false)
    }

    public func testJevConnection(apiKeyOverride: String? = nil) async -> Result<JevPingResult, Error> {
        let key: String?
        if let override = apiKeyOverride?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            key = override
        } else {
            key = jevAPIKeyStore.resolveKey()?.key
        }
        guard let key, !key.isEmpty else {
            return .failure(JevClientError.missingAPIKey)
        }
        do {
            let result = try await jevClient.testConnection(apiKey: key, model: settings.jevModel)
            jevLastError = nil
            return .success(result)
        } catch {
            jevLastError = error.localizedDescription
            return .failure(error)
        }
    }

    public func resumeAutoTracking() {
        semanticTracker.clearManualPin()
        jevIsManualPinned = false
        lastJevClassifiedSignature = nil
        _ = refreshPublishedState(now: clock.now(), forceUI: false)
    }

    public func clearJevDecisionLogs() {
        jevDecisionLogs = []
        if !isSyntheticDemo, let store {
            try? store.saveJevDecisionLogs([], forDate: engine.currentDateString)
        }
    }

    private func categoryDisplayName(for categoryId: String) -> String {
        if let reserved = AutoActivityIds.displayName(for: categoryId) {
            return reserved
        }
        return engine.budgets.first(where: { $0.taskId == categoryId })?.displayName ?? categoryId
    }

    private func appendJevDecisionLog(_ entry: JevDecisionLogEntry) {
        jevDecisionLogs.insert(entry, at: 0)
        if jevDecisionLogs.count > 100 {
            jevDecisionLogs.removeLast(jevDecisionLogs.count - 100)
        }
        if !isSyntheticDemo, let store {
            try? store.saveJevDecisionLogs(jevDecisionLogs, forDate: engine.currentDateString)
        }
    }

    public func selectTask(_ taskId: String, note: String? = nil) {
        let now = clock.now()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        engine.switchTask(to: taskId, note: effectiveNote, at: now)
        if settings.jevAutoTrackingEnabled {
            semanticTracker.recordManualSelection(categoryId: taskId, contextKey: observedContextKey, at: now)
            if let ctxKey = observedContextKey {
                engine.stampSemanticGroup("proj:\(taskId)", forContextKey: ctxKey, at: now)
            }
            jevIsManualPinned = semanticTracker.isManualPinActive
            if let sample = engine.lastSample {
                appendJevDecisionLog(
                    JevDecisionLogEntry(
                        timestamp: now,
                        appName: sample.appName,
                        windowTitle: sample.redacted ? nil : sample.windowTitle,
                        domain: sample.redacted ? nil : SwitchClassifier.registrableDomain(from: sample.url),
                        redacted: sample.redacted,
                        usedOCRSnippet: false,
                        predictedCategoryId: taskId,
                        predictedDisplayName: categoryDisplayName(for: taskId),
                        confidence: 1.0,
                        sameTaskAsPrevious: nil,
                        isDistraction: 0.0,
                        source: .localOverride,
                        outcome: .manualOverride
                    )
                )
            }
        }
        if let alert = activeAlert {
            engine.dismissAlert(id: alert.id)
            activeAlert = nil
        }
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
    }

    public func pauseFocus(note: String? = nil) {
        let now = clock.now()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        engine.pauseFocus(note: effectiveNote, at: now)
        if settings.jevAutoTrackingEnabled {
            semanticTracker.recordManualSelection(categoryId: nil, contextKey: nil, at: now)
            jevIsManualPinned = false
        }
        if let alert = activeAlert {
            engine.dismissAlert(id: alert.id)
            activeAlert = nil
        }
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
    }

    public func stopToStandby(note: String? = nil) {
        let now = clock.now()
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveNote = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        engine.stopFocus(note: effectiveNote, at: now)
        if settings.jevAutoTrackingEnabled {
            semanticTracker.recordManualSelection(categoryId: nil, contextKey: nil, at: now)
            jevIsManualPinned = false
        }
        if let alert = activeAlert {
            engine.dismissAlert(id: alert.id)
            activeAlert = nil
        }
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
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
        let nextAlert = engine.pendingAlerts.last
        if activeAlert != nextAlert {
            activeAlert = nextAlert
        }
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
    }

    public func updateBudget(taskId: String, targetMinutes: Int?, capMinutes: Int?) {
        let updated = engine.budgets.map { budget in
            guard budget.taskId == taskId else { return budget }
            return TaskBudget(
                taskId: budget.taskId,
                displayName: budget.displayName,
                shortName: budget.shortName,
                description: budget.description,
                colorHex: budget.colorHex,
                targetMinutes: targetMinutes,
                capMinutes: capMinutes,
                keywords: budget.keywords,
                appBundleIds: budget.appBundleIds,
                domains: budget.domains
            )
        }
        engine.updateBudgets(updated)
        saveBudgetsIfNeeded()
        let now = clock.now()
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
    }

    @discardableResult
    public func addTask(
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
        let created = engine.addTask(
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
        saveBudgetsIfNeeded()
        let now = clock.now()
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
        return created
    }

    public func updateTask(_ updatedBudget: TaskBudget) {
        _ = engine.updateTask(updatedBudget)
        saveBudgetsIfNeeded()
        let now = clock.now()
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
    }

    public func deleteTask(taskId: String) {
        let now = clock.now()
        _ = engine.deleteTask(taskId: taskId, at: now)
        let nextAlert = engine.pendingAlerts.last
        if activeAlert != nextAlert {
            activeAlert = nextAlert
        }
        saveBudgetsIfNeeded()
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
    }

    public func moveTask(fromOffsets: IndexSet, toOffset: Int) {
        engine.moveTask(fromOffsets: fromOffsets, toOffset: toOffset)
        saveBudgetsIfNeeded()
        let now = clock.now()
        let metrics = refreshPublishedState(now: now)
        persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
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

    private var recorderIdleThresholdSeconds: TimeInterval {
        TimeInterval(max(5000, settings.recorderIdleThresholdMs)) / 1000.0
    }

    private func inspectPatchedSample(now: Date) -> ActivitySample {
        let privacy = engine.effectivePrivacyConfig
        let rawSample = inspector.inspectCurrent()
        var sample = (inspector is AXWindowInspector) ? rawSample : PrivacyRedactor.redact(rawSample, config: privacy)

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

            if patchedTitle != sample.windowTitle || patchedURL != sample.url {
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
                    config: privacy
                )
            } else if patchedInputActive != sample.inputActive || patchedIdle != sample.idleSeconds {
                sample = ActivitySample(
                    timestamp: sample.timestamp,
                    appName: sample.appName,
                    bundleId: sample.bundleId,
                    windowTitle: sample.windowTitle,
                    url: sample.url,
                    idleSeconds: patchedIdle,
                    screenLocked: sample.screenLocked,
                    inputActive: patchedInputActive,
                    redacted: sample.redacted
                )
            }
        }
        return sample
    }

    public func pollOnce() {
        let now = clock.now()
        checkDayRolloverIfNeeded(now: now)

        let nextAxTrusted = inspector.isAccessibilityTrusted
        if axTrusted != nextAxTrusted {
            axTrusted = nextAxTrusted
        }
        if isStarted, nextAxTrusted,
           let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
           windowChangeObserver?.attachedPID != frontPID {
            windowChangeObserver?.attach(pid: frontPID)
        }
        if let screenRecorder {
            let nextScreenCaptureTrusted = screenRecorder.isScreenCaptureTrusted
            if screenCaptureTrusted != nextScreenCaptureTrusted {
                screenCaptureTrusted = nextScreenCaptureTrusted
            }
        }

        let sample = inspectPatchedSample(now: now)

        let alerts = engine.ingestAlreadyRedacted(sample)
        if let newest = alerts.last, activeAlert != newest {
            activeAlert = newest
        }

        evaluateJevAutoTrackingIfNeeded(sample: sample, now: now)

        var didRecordSample = false
        let wasFirstRecord = (lastRecordedAt == nil)
        if settings.activityRecorderEnabled {
            // Idle / locked: close the open session at its last activity and stop screenshots.
            let idleThreshold = recorderIdleThresholdSeconds
            let isAbsent = sample.screenLocked || sample.idleSeconds >= idleThreshold
            if isAbsent {
                typingPauseTask?.cancel()
                typingPauseTask = nil
                if !idleSessionClosed, !isSyntheticDemo, let database {
                    try? database.closeActiveSessionAtLastActivity()
                    idleSessionClosed = true
                }
            } else {
                idleSessionClosed = false
            }

            didRecordSample = recordSampleToDatabaseIfNeeded(sample)
            if !isAbsent {
                screenRecorder?.evaluatePeriodicCaptureIfNeeded(
                    sample: sample,
                    deepRecordingEnabled: deepRecordingEnabled,
                    declaredTaskId: currentDeclaredTaskId(),
                    idleThresholdSeconds: idleThreshold,
                    retentionDays: settings.snapshotRetentionDays,
                    maxStorageBytes: settings.snapshotMaxStorageBytes,
                    ocrEveryN: settings.ocrEveryN
                ) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, !self.shouldGateBackgroundUI else { return }
                        self.refreshRecorderCountsAsync()
                    }
                }
            }
        } else {
            typingPauseTask?.cancel()
            typingPauseTask = nil
        }

        screenRecorder?.runRetentionMaintenanceIfNeeded(
            retentionDays: settings.snapshotRetentionDays,
            maxStorageBytes: settings.snapshotMaxStorageBytes,
            now: now
        )

        let precomputedMetrics = refreshPublishedState(now: now)
        if didRecordSample && !shouldGateBackgroundUI {
            if wasFirstRecord {
                refreshRecorderCounts()
            } else {
                refreshRecorderCountsAsync()
            }
        }
        if lastPersistedAt == nil || now.timeIntervalSince(lastPersistedAt!) >= 30.0 {
            persistTodayIfNeeded(now: now, precomputedMetrics: precomputedMetrics)
        }
    }

    private var shouldGateBackgroundUI: Bool {
        isStarted && !isPopoverVisible && !isRecorderWindowVisible
    }

    public func setPopoverVisible(_ visible: Bool) {
        isPopoverVisible = visible
        if visible {
            refreshPublishedState(now: clock.now(), forceUI: true)
            refreshRecorderCountsAsync()
        }
    }

    public func setRecorderWindowVisible(_ visible: Bool) {
        isRecorderWindowVisible = visible
        if visible {
            refreshPublishedState(now: clock.now(), forceUI: true)
            refreshRecorderCountsAsync()
        }
    }

    public func releaseHistoryWindowCaches() {
        if !isSyntheticDemo {
            recentSessions = []
        }
    }

    private func onOneSecondTick() {
        tickCount += 1
        if isPopoverVisible {
            updateElapsedFocusSeconds()
        }

        if !isSyntheticDemo {
            if tickCount % 2 == 0 {
                pollOnce()
            }
            if tickCount % 10 == 0 && !shouldGateBackgroundUI {
                refreshRecorderCountsAsync()
            }
        }
    }

    public func handleMonitorEventForTesting(_ event: NativeMonitorEvent) {
        handleNativeMonitorEvent(event)
    }

    public func handleWindowContextChangedForTesting() {
        handleWindowContextChanged()
    }

    private func handleWindowContextChanged() {
        guard !isSyntheticDemo else { return }
        let now = clock.now()
        checkDayRolloverIfNeeded(now: now)
        let sample = inspectPatchedSample(now: now)
        guard !sample.screenLocked else { return }

        let prevContextKey = observedContextKey
        let nextContextKey = SemanticPayloadSanitizer.semanticContextKey(for: sample)
        let contextChanged = (nextContextKey != prevContextKey)

        if contextChanged {
            let alerts = engine.ingestAlreadyRedacted(sample)
            if let newest = alerts.last, activeAlert != newest {
                activeAlert = newest
            }
            if settings.activityRecorderEnabled, sample.idleSeconds < recorderIdleThresholdSeconds {
                _ = recordSampleToDatabaseIfNeeded(sample)
            }
        }

        evaluateJevAutoTrackingIfNeeded(sample: sample, now: now)
        _ = refreshPublishedState(now: now)
    }

    private func handleRawInput(isKeypress: Bool, at timestamp: Date) {
        guard !isSyntheticDemo, settings.activityRecorderEnabled, settings.inputMonitoringEnabled else { return }
        lastNativeInputAt = timestamp
        guard isKeypress else { return }

        typingPauseTask?.cancel()
        let quietNanos = UInt64(typingPauseQuietSeconds * 1_000_000_000)
        typingPauseTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: quietNanos)
            guard !Task.isCancelled, let self else { return }
            self.triggerTypingPauseCaptureAfterQuietWindow()
        }
    }

    private func triggerTypingPauseCaptureAfterQuietWindow() {
        guard !isSyntheticDemo, settings.activityRecorderEnabled else { return }
        let sample = PrivacyRedactor.redact(inspector.inspectCurrent(), config: engine.effectivePrivacyConfig)
        let idleThreshold = recorderIdleThresholdSeconds
        guard !sample.screenLocked,
              !sample.redacted,
              sample.idleSeconds < idleThreshold else {
            return
        }
        screenRecorder?.triggerTypingPauseCaptureIfNeeded(
            sample: sample,
            deepRecordingEnabled: deepRecordingEnabled,
            declaredTaskId: currentDeclaredTaskId(),
            idleThresholdSeconds: idleThreshold,
            ocrEveryN: settings.ocrEveryN
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.shouldGateBackgroundUI else { return }
                self.refreshRecorderCountsAsync()
            }
        }
    }

    private func resolveSampleForInputEvent(at timestamp: Date) -> ActivitySample {
        if let existing = latestSample, abs(timestamp.timeIntervalSince(existing.timestamp)) <= 1.5 {
            return existing
        }
        let fresh = PrivacyRedactor.redact(inspector.inspectCurrent(), config: engine.effectivePrivacyConfig)
        return fresh
    }

    private func handleNativeMonitorEvent(_ event: NativeMonitorEvent) {
        guard !isSyntheticDemo else { return }
        let tsMs = Int64(event.timestamp.timeIntervalSince1970 * 1000)
        let taskId = currentDeclaredTaskId()
        let idleThreshold = recorderIdleThresholdSeconds

        switch event.kind {
        case "app_focus":
            if isStarted, let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                windowChangeObserver?.attach(pid: frontPID)
            }
            let now = clock.now()
            let sample = inspectPatchedSample(now: now)
            let alerts = engine.ingestAlreadyRedacted(sample)
            if let newest = alerts.last, activeAlert != newest {
                activeAlert = newest
            }
            evaluateJevAutoTrackingIfNeeded(sample: sample, now: now)
            let expectedContextKey = observedContextKey
            if settings.activityRecorderEnabled, !sample.screenLocked {
                _ = recordSampleToDatabaseIfNeeded(sample)
                screenRecorder?.triggerAppFocusCaptureIfNeeded(
                    sample: sample,
                    deepRecordingEnabled: deepRecordingEnabled,
                    declaredTaskId: taskId,
                    idleThresholdSeconds: idleThreshold,
                    ocrEveryN: settings.ocrEveryN
                ) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if !self.shouldGateBackgroundUI {
                            self.refreshRecorderCountsAsync()
                        }
                        if let expectedContextKey {
                            self.handleJevOCRReady(expectedContextKey: expectedContextKey)
                        }
                    }
                }
            }
            refreshPublishedState(now: now)
            if !shouldGateBackgroundUI {
                refreshRecorderCountsAsync()
            }

        case "will_sleep":
            typingPauseTask?.cancel()
            typingPauseTask = nil
            VisionOCRService.shutdownWorker()
            engine.handleSystemSleep(at: event.timestamp)
            if !idleSessionClosed, let database {
                try? database.closeActiveSessionAtLastActivity()
                idleSessionClosed = true
            }
            let metrics = refreshPublishedState(now: event.timestamp)
            persistTodayIfNeeded(now: event.timestamp, precomputedMetrics: metrics)

        case "did_wake":
            screenRecorder?.resetDeduplicationBaseline()
            let current = inspector.inspectCurrent()
            if !current.screenLocked {
                idleSessionClosed = false
            }

        case "lock":
            typingPauseTask?.cancel()
            typingPauseTask = nil
            VisionOCRService.shutdownWorker()
            engine.handleSystemSleep(at: event.timestamp)
            if settings.activityRecorderEnabled {
                _ = try? database?.insertEvent(
                    timestampMs: tsMs,
                    kind: "lock",
                    appName: "loginwindow",
                    declaredTaskId: taskId,
                    project: taskId
                )
            }
            pollOnce()

        case "unlock":
            screenRecorder?.resetDeduplicationBaseline()
            idleSessionClosed = false
            if settings.activityRecorderEnabled {
                _ = try? database?.insertEvent(
                    timestampMs: tsMs,
                    kind: "unlock",
                    appName: "loginwindow",
                    declaredTaskId: taskId,
                    project: taskId
                )
            }
            pollOnce()

        case "click", "keypress":
            guard settings.activityRecorderEnabled, settings.inputMonitoringEnabled else { return }
            lastNativeInputAt = event.timestamp
            let activeSample = resolveSampleForInputEvent(at: event.timestamp)
            if !activeSample.screenLocked {
                _ = try? database?.insertEvent(
                    timestampMs: tsMs,
                    kind: event.kind,
                    appName: activeSample.appName,
                    windowTitle: activeSample.redacted ? nil : activeSample.windowTitle,
                    url: activeSample.redacted ? nil : activeSample.url,
                    data: ["count": String(max(1, event.count))],
                    declaredTaskId: taskId,
                    project: taskId
                )
            }
            if event.kind == "click", !activeSample.screenLocked {
                let clickSample = ActivitySample(
                    timestamp: event.timestamp,
                    appName: activeSample.appName,
                    bundleId: activeSample.bundleId,
                    windowTitle: activeSample.windowTitle,
                    url: activeSample.url,
                    idleSeconds: 0,
                    screenLocked: activeSample.screenLocked,
                    inputActive: true,
                    redacted: activeSample.redacted
                )
                screenRecorder?.triggerClickCaptureIfNeeded(
                    sample: clickSample,
                    deepRecordingEnabled: deepRecordingEnabled,
                    declaredTaskId: taskId,
                    idleThresholdSeconds: idleThreshold,
                    ocrEveryN: settings.ocrEveryN
                ) { [weak self] in
                    Task { @MainActor [weak self] in
                        guard let self, !self.shouldGateBackgroundUI else { return }
                        self.refreshRecorderCountsAsync()
                    }
                }
            }

        default:
            break
        }
    }

    @discardableResult
    private func recordSampleToDatabaseIfNeeded(_ sample: ActivitySample) -> Bool {
        guard !isSyntheticDemo, settings.activityRecorderEnabled, let database else { return false }
        guard !sample.screenLocked, sample.idleSeconds < recorderIdleThresholdSeconds else {
            return false
        }

        let key = ActivityTextNormalizer.normalizedChangeKey(
            appName: sample.appName,
            bundleId: sample.bundleId,
            title: sample.windowTitle,
            url: sample.url
        )
        let appChanged = (sample.appName != lastRecordedAppName)
        let keyChanged = (key != lastRecordedSampleKey)
        let heartbeatDue = (sample.idleSeconds < 30.0)
            && (lastRecordedHeartbeatAt.map { sample.timestamp.timeIntervalSince($0) >= 30.0 } ?? true)
        // Title-only jitter is throttled; app switches are always recorded immediately.
        let withinTitleThrottle: Bool = {
            guard !appChanged, let last = lastRecordedAt else { return false }
            return sample.timestamp.timeIntervalSince(last) < minTitleChangeInterval
        }()

        guard heartbeatDue || (keyChanged && !withinTitleThrottle) else { return false }

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
        return true
    }

    private func syncFromAlma(isInitialBackfill: Bool) async {
        guard let almaClient else { return }
        guard httpServer?.isServingPort(LocalActivityHTTPServer.almaReservedPort) != true else {
            if almaConnected {
                almaConnected = false
            }
            return
        }

        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let sinceMs = isInitialBackfill ? nil : lastAlmaEventMs

        let result = await almaClient.fetchTodaySamples(
            dayStart: dayStart,
            dayEnd: now.addingTimeInterval(60),
            sinceEventMs: sinceMs,
            privacyConfig: engine.effectivePrivacyConfig
        )

        if almaConnected != result.connected {
            almaConnected = result.connected
        }
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
                let metrics = refreshPublishedState(now: now)
                persistTodayIfNeeded(now: now, precomputedMetrics: metrics)
            }
        }
    }

    // MARK: - Jev Semantic Auto-Tracking

    private func cancelJevScheduledTimers() {
        jevDwellTask?.cancel()
        jevDwellTask = nil
        jevDwellTargetContextKey = nil
        jevDwellScheduledAt = nil
        jevDwellScheduledDelay = nil
        jevPendingConfirmTask?.cancel()
        jevPendingConfirmTask = nil
        jevContextOCRTask?.cancel()
        jevContextOCRTask = nil
        jevContextOCRTargetKey = nil
        jevContextOCRCompletedForContextKey = nil
    }

    private func scheduleJevDwellTimerIfNeeded(for contextKey: String, after delaySeconds: TimeInterval, now: Date) {
        guard shouldScheduleEventTimers, !isSyntheticDemo, settings.jevAutoTrackingEnabled else { return }
        let clampedDelay = max(0.02, delaySeconds)
        let targetFireAt = now.addingTimeInterval(clampedDelay)
        if jevDwellTargetContextKey == contextKey,
           jevDwellTask != nil,
           let scheduledAt = jevDwellScheduledAt,
           let scheduledDelay = jevDwellScheduledDelay {
            let existingFireAt = scheduledAt.addingTimeInterval(scheduledDelay)
            if existingFireAt <= targetFireAt.addingTimeInterval(0.05) {
                return
            }
        }
        jevDwellTask?.cancel()
        jevDwellTargetContextKey = contextKey
        jevDwellScheduledAt = now
        jevDwellScheduledDelay = clampedDelay
        let sleepNanos = UInt64(clampedDelay * 1_000_000_000) + 15_000_000
        jevDwellTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: sleepNanos)
            guard !Task.isCancelled, let self else { return }
            guard self.jevDwellTargetContextKey == contextKey else { return }
            self.jevDwellTask = nil
            self.jevDwellTargetContextKey = nil
            self.jevDwellScheduledAt = nil
            self.jevDwellScheduledDelay = nil
            guard self.observedContextKey == contextKey else { return }
            let fireNow = self.clock.now()
            let sample = self.inspectPatchedSample(now: fireNow)
            self.evaluateJevAutoTrackingIfNeeded(sample: sample, now: fireNow)
            _ = self.refreshPublishedState(now: fireNow)
        }
    }

    private func scheduleJevPendingConfirmTimerIfNeeded(for contextKey: String, now: Date) {
        guard shouldScheduleEventTimers, !isSyntheticDemo, settings.jevAutoTrackingEnabled else { return }
        guard let remaining = semanticTracker.remainingConfirmSeconds(for: contextKey, at: now) else {
            jevPendingConfirmTask?.cancel()
            jevPendingConfirmTask = nil
            return
        }
        jevPendingConfirmTask?.cancel()
        let sleepNanos = UInt64(max(0.02, remaining) * 1_000_000_000) + 20_000_000
        jevPendingConfirmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: sleepNanos)
            guard !Task.isCancelled, let self else { return }
            self.jevPendingConfirmTask = nil
            guard self.observedContextKey == contextKey else { return }
            let ts = self.clock.now()
            let sample = self.inspectPatchedSample(now: ts)
            self.evaluateJevAutoTrackingIfNeeded(sample: sample, now: ts)
            _ = self.refreshPublishedState(now: ts)
        }
    }

    private func scheduleContextOCRCaptureIfNeeded(sample: ActivitySample, contextKey: String) {
        guard shouldScheduleEventTimers,
              !isSyntheticDemo,
              settings.jevAutoTrackingEnabled,
              settings.jevSendOCRSnippet,
              settings.activityRecorderEnabled,
              deepRecordingEnabled,
              settings.visionOCREnabled,
              screenRecorder != nil,
              !sample.redacted,
              !sample.screenLocked else {
            return
        }
        guard jevContextOCRTargetKey != contextKey else { return }
        jevContextOCRTask?.cancel()
        jevContextOCRTargetKey = contextKey
        let sleepNanos = UInt64(jevContextOCRDelaySeconds * 1_000_000_000)
        jevContextOCRTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: sleepNanos)
            guard !Task.isCancelled, let self else { return }
            self.jevContextOCRTask = nil
            guard self.observedContextKey == contextKey,
                  self.settings.jevAutoTrackingEnabled,
                  self.settings.activityRecorderEnabled,
                  self.deepRecordingEnabled else {
                return
            }
            let ts = self.clock.now()
            let fresh = self.inspectPatchedSample(now: ts)
            guard !fresh.screenLocked,
                  !fresh.redacted,
                  fresh.idleSeconds < self.recorderIdleThresholdSeconds,
                  SemanticPayloadSanitizer.semanticContextKey(for: fresh) == contextKey else {
                return
            }
            self.screenRecorder?.triggerWindowContextCaptureIfNeeded(
                sample: fresh,
                deepRecordingEnabled: self.deepRecordingEnabled,
                declaredTaskId: self.currentDeclaredTaskId(),
                idleThresholdSeconds: self.recorderIdleThresholdSeconds,
                ocrEveryN: self.settings.ocrEveryN
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if !self.shouldGateBackgroundUI {
                        self.refreshRecorderCountsAsync()
                    }
                    self.handleJevOCRReady(expectedContextKey: contextKey)
                }
            }
        }
    }

    private func handleJevOCRReady(expectedContextKey: String) {
        guard !isSyntheticDemo,
              settings.jevAutoTrackingEnabled,
              settings.jevSendOCRSnippet,
              observedContextKey == expectedContextKey else {
            return
        }
        jevContextOCRCompletedForContextKey = expectedContextKey
        let now = clock.now()
        let sample = inspectPatchedSample(now: now)
        guard !sample.screenLocked, !sample.redacted else { return }
        evaluateJevAutoTrackingIfNeeded(sample: sample, now: now)
        _ = refreshPublishedState(now: now)
    }

    private func evaluateJevAutoTrackingIfNeeded(sample: ActivitySample, now: Date) {
        guard !isSyntheticDemo else { return }
        guard !sample.screenLocked, sample.idleSeconds < engine.config.idleThresholdSeconds else {
            return
        }

        // Ignore DayHelm's own windows, transient auxiliary overlays (Xnip/Spotlight/Stats),
        // and blank browser New Tab transitions so they never hijack the active task or emit low-confidence noise.
        let selfBundle = Bundle.main.bundleIdentifier?.lowercased()
        let sampleBundle = sample.bundleId?.lowercased()
        if (selfBundle != nil && sampleBundle == selfBundle)
            || SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: sample) {
            return
        }

        let contextKey = SemanticPayloadSanitizer.semanticContextKey(for: sample)

        if observedContextKey != contextKey {
            observedContextKey = contextKey
            observedContextSince = now
            jevDwellTask?.cancel()
            jevDwellTask = nil
            jevDwellTargetContextKey = nil
            jevDwellScheduledAt = nil
            jevDwellScheduledDelay = nil
            jevPendingConfirmTask?.cancel()
            jevPendingConfirmTask = nil
            jevContextOCRTask?.cancel()
            jevContextOCRTask = nil
            jevContextOCRTargetKey = nil
            jevContextOCRCompletedForContextKey = nil
        } else if observedContextSince == nil {
            observedContextSince = now
        }

        guard settings.jevAutoTrackingEnabled else { return }

        let resolvedKey = jevAPIKeyStore.resolveKey()
        let hasKey = (resolvedKey != nil)
        if jevAPIKeyConfigured != hasKey {
            jevAPIKeyConfigured = hasKey
        }
        if jevAPIKeySource != resolvedKey?.source {
            jevAPIKeySource = resolvedKey?.source
        }
        let needsKey = !hasKey
        if jevNeedsAPIKey != needsKey {
            jevNeedsAPIKey = needsKey
        }
        engine.setAutoTrackingActive(hasKey)

        guard let apiKey = resolvedKey?.key, !apiKey.isEmpty else {
            return
        }

        // 1. Advance anti-flicker dwell on any pending candidate.
        let dwellDecision = semanticTracker.tickDwell(activeContextKey: contextKey, at: now)
        if dwellDecision.didSwitch, let committed = dwellDecision.committedCategoryId {
            jevPendingConfirmTask?.cancel()
            jevPendingConfirmTask = nil
            let committedCls = dwellDecision.committedClassification ?? semanticTracker.latestClassification
            engine.applyAutoCategory(committed, activityMode: committedCls?.activityMode, at: now)
            if let semGroup = committedCls?.semanticGroupKey {
                engine.stampSemanticGroup(semGroup, forContextKey: contextKey, at: now)
            }
            let focusProjName = committedCls?.focusProjectId.map { categoryDisplayName(for: $0) }
            appendJevDecisionLog(
                JevDecisionLogEntry(
                    timestamp: now,
                    appName: sample.appName,
                    windowTitle: sample.redacted ? nil : sample.windowTitle,
                    domain: sample.redacted ? nil : SwitchClassifier.registrableDomain(from: sample.url),
                    redacted: sample.redacted,
                    usedOCRSnippet: false,
                    predictedCategoryId: committed,
                    predictedDisplayName: categoryDisplayName(for: committed),
                    activityMode: committedCls?.activityMode,
                    focusProjectDisplayName: focusProjName,
                    confidence: committedCls?.confidence ?? 1.0,
                    sameTaskAsPrevious: committedCls?.sameTaskAsPrevious,
                    isDistraction: committedCls?.isDistraction ?? 0.0,
                    source: committedCls?.source ?? .cache,
                    outcome: .committedSwitch
                )
            )
        } else if dwellDecision.pendingCategoryId != nil {
            scheduleJevPendingConfirmTimerIfNeeded(for: contextKey, now: now)
        }
        let pinActive = semanticTracker.isManualPinActive
        if jevIsManualPinned != pinActive {
            jevIsManualPinned = pinActive
        }

        let budgetsVersion = engine.budgetsVersion

        // 2. Day-scoped manual override short-circuits outbound calls.
        if let overrideId = semanticTracker.manualOverride(for: contextKey) {
            let overrideCls = SemanticClassification(
                categoryId: overrideId,
                confidence: 1.0,
                probabilities: [overrideId: 1.0],
                sameTaskAsPrevious: nil,
                isDistraction: 0.0,
                source: .localOverride,
                classifiedAt: now
            )
            let wasPinned = semanticTracker.isManualPinActive
            let previousCategory = semanticTracker.currentCategoryId
            let decision = semanticTracker.apply(
                classification: overrideCls,
                contextKey: contextKey,
                budgetsVersion: budgetsVersion,
                at: now
            )
            applySemanticWriteBackIfAdopted(
                classification: overrideCls,
                decision: decision,
                previousCategory: previousCategory,
                wasPinned: wasPinned,
                contextKey: contextKey,
                at: now
            )
            return
        }

        // Check whether fresh same-window OCR is available (used both for cache upgrade and payload).
        let needsOCR = settings.jevSendOCRSnippet
            && !sample.redacted
            && SemanticPayloadSanitizer.shouldAttachOCR(appName: sample.appName, windowTitle: sample.windowTitle, url: sample.url)
        let ocrText: String?
        if needsOCR, let database {
            let nowMs = Int64(now.timeIntervalSince1970 * 1000)
            ocrText = database.latestOCRText(
                withinSeconds: 180,
                appName: sample.appName,
                windowTitle: sample.windowTitle,
                nowMs: nowMs
            )
        } else {
            ocrText = nil
        }

        let dwellSeconds = max(0, now.timeIntervalSince(observedContextSince ?? now))

        // 3. Local 5-minute context cache short-circuits redundant API calls.
        // If previously classified without OCR and fresh OCR for this exact window has now landed, bypass once to upgrade.
        if let cached = semanticTracker.cachedClassification(
            for: contextKey,
            budgetsVersion: budgetsVersion,
            hasFreshOCR: ocrText != nil,
            at: now
        ) {
            let isColdStart = (semanticTracker.currentCategoryId == nil)
            let isSameCategory = (semanticTracker.currentCategoryId == cached.categoryId)
            if !isColdStart && !isSameCategory && dwellSeconds < semanticTracker.config.cacheSwitchDwellSeconds {
                scheduleJevDwellTimerIfNeeded(
                    for: contextKey,
                    after: semanticTracker.config.cacheSwitchDwellSeconds - dwellSeconds,
                    now: now
                )
                return
            }
            let wasPinned = semanticTracker.isManualPinActive
            let previousCategory = semanticTracker.currentCategoryId
            let decision = semanticTracker.apply(
                classification: cached,
                contextKey: contextKey,
                budgetsVersion: budgetsVersion,
                at: now
            )
            applySemanticWriteBackIfAdopted(
                classification: cached,
                decision: decision,
                previousCategory: previousCategory,
                wasPinned: wasPinned,
                contextKey: contextKey,
                at: now
            )
            if !decision.didSwitch && decision.pendingCategoryId != nil {
                scheduleJevPendingConfirmTimerIfNeeded(for: contextKey, now: now)
            }
            return
        }

        // For weak-title / multi-purpose / self-hosted web pages without recent OCR, trigger an on-demand capture+OCR
        // after 0.35s paint settle and defer the first Jev request up to onDemandOCRWaitSeconds (1.4s) so OCR
        // lands before dispatch, eliminating 1s noOCR -> OCR double-fires. If OCR times out or produces no text,
        // fallback cleanly to noOCR.
        let canCaptureOnDemandOCR = needsOCR
            && ocrText == nil
            && settings.activityRecorderEnabled
            && deepRecordingEnabled
            && settings.visionOCREnabled
            && (screenRecorder?.isScreenCaptureTrusted ?? false)
            && database != nil
        if canCaptureOnDemandOCR {
            scheduleContextOCRCaptureIfNeeded(sample: sample, contextKey: contextKey)
        }

        let awaitingOnDemandOCR = canCaptureOnDemandOCR
            && jevContextOCRCompletedForContextKey != contextKey
        let requiredDwellSeconds = awaitingOnDemandOCR
            ? max(semanticTracker.config.minDwellBeforeClassifySeconds, semanticTracker.config.onDemandOCRWaitSeconds)
            : semanticTracker.config.minDwellBeforeClassifySeconds

        // 4. Enforce precision dwell gate before calling Jev.
        guard dwellSeconds >= requiredDwellSeconds else {
            scheduleJevDwellTimerIfNeeded(
                for: contextKey,
                after: requiredDwellSeconds - dwellSeconds,
                now: now
            )
            return
        }
        jevDwellTask?.cancel()
        jevDwellTask = nil
        jevDwellTargetContextKey = nil
        jevDwellScheduledAt = nil
        jevDwellScheduledDelay = nil

        // Error backoff (15s) to avoid hammering on offline/invalid-key states.
        if let lastErr = lastJevErrorAt, now.timeIntervalSince(lastErr) < 15.0 {
            return
        }

        let ocrSig = ocrText.map { String($0.prefix(48)) } ?? ""
        let requestSignature = "\(budgetsVersion)|\(contextKey)|\(ocrSig)"
        if jevInFlightSignature == requestSignature || lastJevClassifiedSignature == requestSignature {
            return
        }

        guard let sanitizedInput = SemanticPayloadSanitizer.buildInput(
            sample: sample,
            ocrText: ocrText,
            recentSpans: engine.enrichedSpans,
            budgets: engine.budgets,
            sendOCRSnippet: settings.jevSendOCRSnippet,
            privacyConfig: engine.effectivePrivacyConfig
        ) else {
            return
        }

        let usedOCR = (sanitizedInput.ocrSnippet != nil)
        let model = settings.jevModel
        let client = jevClient
        jevInFlightSignature = requestSignature
        jevClassifyTask?.cancel()
        jevClassifyTask = Task { [weak self] in
            do {
                let classification = try await client.classify(
                    input: sanitizedInput,
                    apiKey: apiKey,
                    model: model
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.jevInFlightSignature == requestSignature {
                        self.jevInFlightSignature = nil
                    }
                    self.lastJevClassifiedSignature = requestSignature
                    self.lastJevErrorAt = nil
                    self.jevLastError = nil

                    let ts = self.clock.now()

                    // Guard against late-response flicker & write-back privilege escalation if the user already moved to another context while in flight.
                    if self.observedContextKey != contextKey {
                        self.semanticTracker.storeCache(
                            classification,
                            for: contextKey,
                            budgetsVersion: budgetsVersion,
                            usedOCR: usedOCR,
                            at: ts
                        )
                        return
                    }

                    self.jevLastClassification = classification
                    let previousCategory = self.semanticTracker.currentCategoryId
                    let wasPinned = self.semanticTracker.isManualPinActive
                    let decision = self.semanticTracker.apply(
                        classification: classification,
                        contextKey: contextKey,
                        budgetsVersion: budgetsVersion,
                        usedOCR: usedOCR,
                        at: ts
                    )
                    self.applySemanticWriteBackIfAdopted(
                        classification: classification,
                        decision: decision,
                        previousCategory: previousCategory,
                        wasPinned: wasPinned,
                        contextKey: contextKey,
                        at: ts
                    )
                    if !decision.didSwitch && decision.pendingCategoryId != nil {
                        self.scheduleJevPendingConfirmTimerIfNeeded(for: contextKey, now: ts)
                    }

                    let outcome: JevDecisionOutcome
                    if decision.didSwitch {
                        outcome = .committedSwitch
                    } else if wasPinned && self.semanticTracker.isManualPinActive {
                        outcome = .manualPinned
                    } else if decision.pendingCategoryId == classification.categoryId {
                        outcome = .pendingConfirmation
                    } else if previousCategory == classification.categoryId {
                        outcome = .maintained
                    } else {
                        outcome = .ignoredLowConfidence
                    }

                    let ocrPreview = sanitizedInput.ocrSnippet.map { snippet in
                        snippet.count > 80 ? String(snippet.prefix(80)) + "…" : snippet
                    }
                    let focusProjDisplay = classification.focusProjectId.map { self.categoryDisplayName(for: $0) }
                    self.appendJevDecisionLog(
                        JevDecisionLogEntry(
                            timestamp: ts,
                            appName: sanitizedInput.appName,
                            windowTitle: sanitizedInput.windowTitle,
                            domain: SwitchClassifier.registrableDomain(from: sanitizedInput.url),
                            redacted: sanitizedInput.redacted,
                            usedOCRSnippet: sanitizedInput.ocrSnippet != nil,
                            ocrSnippetPreview: ocrPreview,
                            predictedCategoryId: classification.categoryId,
                            predictedDisplayName: self.categoryDisplayName(for: classification.categoryId),
                            activityMode: classification.activityMode,
                            focusProjectDisplayName: focusProjDisplay,
                            confidence: classification.confidence,
                            sameTaskAsPrevious: classification.sameTaskAsPrevious,
                            isDistraction: classification.isDistraction,
                            source: classification.source,
                            outcome: outcome,
                            latencyMs: classification.latencyMs,
                            inputTokens: classification.inputTokens
                        )
                    )

                    let metrics = self.refreshPublishedState(now: ts)
                    if decision.didSwitch {
                        self.persistTodayIfNeeded(now: ts, precomputedMetrics: metrics)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.jevInFlightSignature == requestSignature {
                        self.jevInFlightSignature = nil
                    }
                    let ts = self.clock.now()
                    self.lastJevErrorAt = ts
                    self.jevLastError = error.localizedDescription
                    self.appendJevDecisionLog(
                        JevDecisionLogEntry(
                            timestamp: ts,
                            appName: sanitizedInput.appName,
                            windowTitle: sanitizedInput.windowTitle,
                            domain: SwitchClassifier.registrableDomain(from: sanitizedInput.url),
                            redacted: sanitizedInput.redacted,
                            usedOCRSnippet: sanitizedInput.ocrSnippet != nil,
                            predictedCategoryId: "",
                            predictedDisplayName: "识别失败",
                            confidence: 0.0,
                            source: .jev,
                            outcome: .error,
                            errorMessage: error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    /// Applies engine category switching and fine-grained span semanticGroup stamping
    /// ONLY when `SemanticAutoTracker` genuinely commits or maintains the classification
    /// (never on `ignored_low_confidence`, `pending_confirmation`, or `manualPin` interception).
    private func applySemanticWriteBackIfAdopted(
        classification: SemanticClassification,
        decision: SemanticTrackerDecision,
        previousCategory: String?,
        wasPinned: Bool,
        contextKey: String,
        at timestamp: Date
    ) {
        if decision.didSwitch, let committed = decision.committedCategoryId {
            jevPendingConfirmTask?.cancel()
            jevPendingConfirmTask = nil
            engine.applyAutoCategory(committed, activityMode: classification.activityMode, at: timestamp)
            engine.stampSemanticGroup(classification.semanticGroupKey, forContextKey: contextKey, at: timestamp)
            return
        }
        let blockedByPin = wasPinned && semanticTracker.isManualPinActive
        guard !blockedByPin,
              decision.pendingCategoryId == nil,
              previousCategory == classification.categoryId,
              decision.committedCategoryId == classification.categoryId,
              classification.confidence >= semanticTracker.config.coldStartConfidence else {
            return
        }
        engine.stampSemanticGroup(classification.semanticGroupKey, forContextKey: contextKey, at: timestamp)
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
        semanticTracker.resetForNewDay()
        observedContextKey = nil
        observedContextSince = nil
        jevInFlightSignature = nil
        lastJevClassifiedSignature = nil
        cancelJevScheduledTimers()
        jevLastClassification = nil
        jevIsManualPinned = false
        clearJevDecisionLogs()
        lastAlmaEventMs = nil
        latestAlmaBrowserSample = nil
        lastRecordedSampleKey = nil
        lastRecordedHeartbeatAt = nil
        if activeAlert != nil {
            activeAlert = nil
        }
        refreshPublishedState(now: now)
        refreshRecorderCounts()
        scheduleHistoricalStatsMaterialization()
    }

    @discardableResult
    private func refreshPublishedState(now: Date? = nil, forceUI: Bool = false) -> DayMetrics? {
        let ts = now ?? clock.now()
        let nextSessionState = engine.focusState
        if sessionState != nextSessionState {
            sessionState = nextSessionState
        }
        let nextNonBudget = engine.activeNonBudgetActivity
        if activeNonBudgetActivity != nextNonBudget {
            activeNonBudgetActivity = nextNonBudget
        }
        let nextMode = engine.activeActivityMode
        if activeActivityMode != nextMode {
            activeActivityMode = nextMode
        }
        let nextOtherMin = engine.otherWorkMinutes
        if abs(otherWorkMinutes - nextOtherMin) >= 0.01 {
            otherWorkMinutes = nextOtherMin
        }
        let nextNonWorkMin = engine.nonWorkMinutes
        if abs(nonWorkMinutes - nextNonWorkMin) >= 0.01 {
            nonWorkMinutes = nextNonWorkMin
        }
        let nextModeMinutes = engine.activityModeMinutes
        if activityModeMinutes != nextModeMinutes {
            activityModeMinutes = nextModeMinutes
        }
        let nextPinActive = semanticTracker.isManualPinActive
        if jevIsManualPinned != nextPinActive {
            jevIsManualPinned = nextPinActive
        }

        let nextProgress = engine.taskProgress()
        let nextPill = Self.formatPillText(
            sessionState: nextSessionState,
            progressList: nextProgress,
            activeActivityMode: nextMode,
            activityModeMinutes: nextModeMinutes,
            nonBudgetActivity: nextNonBudget,
            otherWorkMinutes: nextOtherMin,
            nonWorkMinutes: nextNonWorkMin,
            mode: settings.menuBarDisplayMode
        )
        if pillModel.text != nextPill {
            pillModel.text = nextPill
        }
        let nextHelp = Self.formatPillHelpText(
            sessionState: nextSessionState,
            progressList: nextProgress,
            activeActivityMode: nextMode,
            activityModeMinutes: nextModeMinutes,
            nonBudgetActivity: nextNonBudget,
            otherWorkMinutes: nextOtherMin,
            nonWorkMinutes: nextNonWorkMin
        )
        if pillModel.helpText != nextHelp {
            pillModel.helpText = nextHelp
        }
        let nextVisualState = Self.formatPillVisualState(
            sessionState: nextSessionState,
            progressList: nextProgress,
            activeActivityMode: nextMode,
            nonBudgetActivity: nextNonBudget
        )
        if pillModel.visualState != nextVisualState {
            pillModel.visualState = nextVisualState
        }

        if shouldGateBackgroundUI && !forceUI {
            syncCachedRuntimeState()
            return nil
        }

        if taskProgressList != nextProgress {
            taskProgressList = nextProgress
        }
        let spectrum = engine.currentSpectrumAndMetrics(at: ts)
        if spectrumSegments != spectrum.segments {
            spectrumSegments = spectrum.segments
        }
        if metrics != spectrum.metrics {
            metrics = spectrum.metrics
        }
        let nextSample = engine.lastSample
        if latestSample != nextSample {
            latestSample = nextSample
        }
        if isPopoverVisible {
            updateElapsedFocusSeconds(now: ts)
        } else if case .focusing = nextSessionState {
            // Keep elapsedFocusSeconds paused while popover is hidden to avoid 1Hz SwiftUI invalidation.
        } else if elapsedFocusSeconds != 0 {
            elapsedFocusSeconds = 0
        }

        let nextNote: String?
        if case .focusing(let taskId, _) = nextSessionState {
            nextNote = engine.lastNote(for: taskId)
        } else if case .paused(let taskId, _) = nextSessionState {
            nextNote = engine.lastNote(for: taskId)
        } else {
            nextNote = nil
        }
        if lastTaskNote != nextNote {
            lastTaskNote = nextNote
        }
        syncCachedRuntimeState()
        return spectrum.metrics
    }

    private static func shortTaskLabel(for budget: TaskBudget) -> String {
        if let customShort = budget.shortName?.trimmingCharacters(in: .whitespacesAndNewlines), !customShort.isEmpty {
            return customShort
        }
        let rawName = budget.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Visual width budget: CJK/wide scalars count as 2, ASCII/narrow count as 1.
        // 16 units comfortably fits "Infra 维护" (10), "Hermes 投研" (11), "电商日常运营" (12) without ellipsis.
        let maxVisualUnits = 16
        var units = 0
        var prefix = ""
        for ch in rawName {
            let w = ch.unicodeScalars.contains(where: { $0.value > 0x7F }) ? 2 : 1
            if units + w > maxVisualUnits {
                return prefix.trimmingCharacters(in: .whitespaces) + "…"
            }
            units += w
            prefix.append(ch)
        }
        return rawName
    }

    private static func formatPillText(
        sessionState: FocusSessionState,
        progressList: [TaskProgress],
        activeActivityMode: ActivityMode?,
        activityModeMinutes: [String: Double],
        nonBudgetActivity: AutoNonBudgetActivity?,
        otherWorkMinutes: Double,
        nonWorkMinutes: Double,
        mode: MenuBarDisplayMode
    ) -> String {
        if mode == .iconOnly {
            return ""
        }

        // Priority 1: Matched Focus Project (user-configured TaskBudget)
        if case .focusing(let taskId, _) = sessionState,
           let progress = progressList.first(where: { $0.budget.taskId == taskId }) {
            let focused = Int(progress.focusedMinutes.rounded())
            let isCapReached: Bool
            if case .capReached = progress.status {
                isCapReached = true
            } else {
                isCapReached = false
            }

            let metricText: String
            if isCapReached, let cap = progress.budget.capMinutes {
                metricText = mode == .compact ? "\(focused)/\(cap)m!" : "\(focused)/\(cap)m▲"
            } else if let target = progress.budget.targetMinutes {
                metricText = "\(focused)/\(target)m"
            } else if let cap = progress.budget.capMinutes {
                metricText = "\(focused)/\(cap)m"
            } else {
                metricText = "\(focused)m"
            }

            switch mode {
            case .iconOnly:
                return ""
            case .compact:
                return metricText
            case .standard:
                let shortName = shortTaskLabel(for: progress.budget)
                return "\(shortName) \(metricText)"
            }
        }

        // Priority 2: Layer-1 ActivityMode (zero-project mode or unmatched project)
        if let actMode = activeActivityMode {
            let mins = Int((activityModeMinutes[actMode.rawValue] ?? (actMode.isDistraction ? nonWorkMinutes : otherWorkMinutes)).rounded())
            // Keep legacy label parity if explicitly set via legacy __other_work__/__non_work__ without a richer mode
            if let nonBudgetActivity, actMode == .commsAdmin, nonBudgetActivity == .otherWork, activityModeMinutes[actMode.rawValue] == nil {
                let label = AutoActivityIds.menuBarLabel(for: AutoActivityIds.otherWork, compact: mode == .compact) ?? "其他事务"
                return "\(label) \(Int(otherWorkMinutes.rounded()))m"
            }
            let label = (mode == .compact) ? actMode.compactLabel : actMode.displayName
            return "\(label) \(mins)m"
        }

        if let nonBudgetActivity {
            switch nonBudgetActivity {
            case .otherWork:
                let mins = Int(otherWorkMinutes.rounded())
                let label = AutoActivityIds.menuBarLabel(for: AutoActivityIds.otherWork, compact: mode == .compact) ?? "其他事务"
                return "\(label) \(mins)m"
            case .nonWork:
                let mins = Int(nonWorkMinutes.rounded())
                let label = AutoActivityIds.menuBarLabel(for: AutoActivityIds.nonWork, compact: mode == .compact) ?? "分心中"
                return "\(label) \(mins)m"
            }
        }

        return mode == .standard ? "待命" : ""
    }

    private static func formatPillHelpText(
        sessionState: FocusSessionState,
        progressList: [TaskProgress],
        activeActivityMode: ActivityMode?,
        activityModeMinutes: [String: Double],
        nonBudgetActivity: AutoNonBudgetActivity?,
        otherWorkMinutes: Double,
        nonWorkMinutes: Double
    ) -> String {
        if case .focusing(let taskId, _) = sessionState,
           let progress = progressList.first(where: { $0.budget.taskId == taskId }) {
            let focused = Int(progress.focusedMinutes.rounded())
            let modeSuffix = activeActivityMode.map { " · \($0.displayName)" } ?? ""
            if case .capReached = progress.status, let cap = progress.budget.capMinutes {
                return "DayHelm · \(progress.budget.displayName)\(modeSuffix) \(focused)/\(cap)m (已达上限)"
            }
            if let target = progress.budget.targetMinutes {
                return "DayHelm · \(progress.budget.displayName)\(modeSuffix) \(focused)/\(target)m"
            }
            if let cap = progress.budget.capMinutes {
                return "DayHelm · \(progress.budget.displayName)\(modeSuffix) \(focused)/\(cap)m"
            }
            return "DayHelm · \(progress.budget.displayName)\(modeSuffix) \(focused)m"
        }

        if let actMode = activeActivityMode {
            let mins = Int((activityModeMinutes[actMode.rawValue] ?? (actMode.isDistraction ? nonWorkMinutes : otherWorkMinutes)).rounded())
            return "DayHelm · \(actMode.displayName)（自动识别）今日累计 \(mins)m"
        }

        if let nonBudgetActivity {
            switch nonBudgetActivity {
            case .otherWork:
                return "DayHelm · 其他事务（自动识别）今日累计 \(Int(otherWorkMinutes.rounded()))m"
            case .nonWork:
                return "DayHelm · 分心/休息（自动识别）今日累计 \(Int(nonWorkMinutes.rounded()))m"
            }
        }
        return "DayHelm · 待命"
    }

    private static func formatPillVisualState(
        sessionState: FocusSessionState,
        progressList: [TaskProgress],
        activeActivityMode: ActivityMode?,
        nonBudgetActivity: AutoNonBudgetActivity?
    ) -> MenuBarVisualState {
        if case .focusing(let taskId, _) = sessionState,
           let progress = progressList.first(where: { $0.budget.taskId == taskId }) {
            switch progress.status {
            case .capReached:
                return .capReached
            case .targetMet:
                return .targetMet
            case .underTarget, .approachingCap, .noBudget:
                return .focusing
            }
        }
        if let actMode = activeActivityMode {
            switch actMode {
            case .breakTime:
                return .distraction
            case .commsAdmin:
                return .otherWork
            case .build, .create, .operate, .research:
                return .focusing
            }
        }
        if let nonBudgetActivity {
            switch nonBudgetActivity {
            case .otherWork:
                return .otherWork
            case .nonWork:
                return .distraction
            }
        }
        return .standby
    }

    public func refreshRecorderCounts() {
        guard !isSyntheticDemo, let database else { return }
        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let dayEndMs = dayStartMs + 86_400_000 - 1
        if let counts = try? database.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs) {
            if todaySnapshotCount != counts.snapshots {
                todaySnapshotCount = counts.snapshots
            }
            if todayOCRCount != counts.ocrFrames {
                todayOCRCount = counts.ocrFrames
            }
        }
        if let stats = try? database.recorderStorageStats(), recorderStats != stats {
            recorderStats = stats
        }
    }

    public func refreshRecorderCountsAsync() {
        guard !isSyntheticDemo, let database, !recorderCountRefreshInFlight else { return }
        recorderCountRefreshInFlight = true
        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let dayEndMs = dayStartMs + 86_400_000 - 1

        Task.detached(priority: .utility) { [weak self, database] in
            let counts = try? database.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs)
            let stats = try? database.recorderStorageStats()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.recorderCountRefreshInFlight = false
                if let counts {
                    if self.todaySnapshotCount != counts.snapshots {
                        self.todaySnapshotCount = counts.snapshots
                    }
                    if self.todayOCRCount != counts.ocrFrames {
                        self.todayOCRCount = counts.ocrFrames
                    }
                }
                if let stats, self.recorderStats != stats {
                    self.recorderStats = stats
                }
            }
        }
    }

    private func syncCachedRuntimeState() {
        let keypressEffective = eventMonitor?.isKeypressMonitoringEffective ?? inspector.isAccessibilityTrusted
        let state = LocalActivityHTTPServer.RuntimeState(
            axTrusted: axTrusted,
            screenCaptureTrusted: screenCaptureTrusted,
            keypressMonitoringEffective: keypressEffective,
            activityRecorderEnabled: settings.activityRecorderEnabled,
            deepRecordingEnabled: deepRecordingEnabled,
            daySnapshot: nil,
            settings: settings
        )
        runtimeStateBox.update(state)
    }

    public nonisolated func currentRuntimeState() -> LocalActivityHTTPServer.RuntimeState {
        var state = runtimeStateBox.read()
        state.daySnapshot = engine.snapshot(at: clock.now())
        return state
    }

    private nonisolated func readCachedRuntimeState() -> LocalActivityHTTPServer.RuntimeState {
        runtimeStateBox.read()
    }

    private func updateElapsedFocusSeconds(now: Date? = nil) {
        let nextElapsed: TimeInterval
        if case .focusing(let taskId, _) = engine.focusState {
            if let openSession = engine.focusSessions.last(where: { $0.taskId == taskId && $0.endedAt == nil }) {
                let baseSeconds = openSession.minutes * 60.0
                let ts = now ?? clock.now()
                let extra = max(0, ts.timeIntervalSince(openSession.startedAt.addingTimeInterval(baseSeconds)))
                nextElapsed = max(baseSeconds, baseSeconds + extra)
            } else {
                nextElapsed = engine.focusedMinutes(for: taskId) * 60.0
            }
        } else {
            nextElapsed = 0
        }
        if elapsedFocusSeconds != nextElapsed {
            elapsedFocusSeconds = nextElapsed
        }
    }

    private func persistTodayIfNeeded(now: Date? = nil, precomputedMetrics: DayMetrics? = nil) {
        guard !isSyntheticDemo, let store else { return }
        let ts = now ?? clock.now()
        let snap = engine.snapshot(at: ts, precomputedMetrics: precomputedMetrics)
        try? store.saveToday(snap)
        lastPersistedAt = ts
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
