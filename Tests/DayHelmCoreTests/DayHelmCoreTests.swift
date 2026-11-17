import Foundation
@testable import DayHelmCapture
@testable import DayHelmCore

#if canImport(XCTest)
import XCTest

final class DayHelmCoreTests: XCTestCase {

    private func baseDate() -> Date {
        DayHelmDateFormatting.parseISO8601("2026-11-17T09:00:00+08:00")!
    }

    private func sampleBudgets() -> [TaskBudget] {
        [
            TaskBudget(taskId: "ecommerce", displayName: "电商做深", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["example-shop", "product-listing", "ecommerce"]),
            TaskBudget(taskId: "ecommerce-ops", displayName: "电商日常运营", colorHex: "#F59E0B", targetMinutes: nil, capMinutes: 30, keywords: ["support-ticket", "order-refund"]),
            TaskBudget(taskId: "hermes", displayName: "Hermes 投研", colorHex: "#10B981", targetMinutes: 45, capMinutes: 60, keywords: ["hermes", "equity-research"]),
            TaskBudget(taskId: "infra-billing", displayName: "Infra 维护", colorHex: "#8B5CF6", targetMinutes: nil, capMinutes: 30, keywords: ["terraform", "cloud-billing"])
        ]
    }

    func testManualClockAdvancesDeterministically() {
        let t0 = baseDate()
        let clock = ManualClock(now: t0)
        XCTAssertEqual(clock.now(), t0)
        clock.advance(by: 125)
        XCTAssertEqual(clock.now(), t0.addingTimeInterval(125))
    }

    func testDateFormattingUTCPlus8AndISO8601() {
        let utcDate = DayHelmDateFormatting.parseISO8601("2026-11-16T16:30:00Z")!
        XCTAssertEqual(DayHelmDateFormatting.dayString(from: utcDate, timeZone: DayHelmDateFormatting.shanghaiTimeZone), "2026-11-17")
        XCTAssertEqual(DayHelmDateFormatting.iso8601String(from: utcDate, timeZone: DayHelmDateFormatting.shanghaiTimeZone), "2026-11-17T00:30:00+08:00")
    }

    func testPrivacyRedactorRedactsPasswordManagers() {
        let t0 = baseDate()
        let sample = ActivitySample(timestamp: t0, appName: "1Password", bundleId: "com.1password.1password", windowTitle: "Vault", url: "https://example.com", idleSeconds: 0, screenLocked: false, inputActive: true)
        let redacted = PrivacyRedactor.redact(sample)
        XCTAssertTrue(redacted.redacted)
        XCTAssertNil(redacted.windowTitle)
        XCTAssertNil(redacted.url)
        XCTAssertEqual(redacted.appName, "1Password")
        XCTAssertEqual(redacted.bundleId, "com.1password.1password")
    }

    func testPrivacyRedactorRedactsBankingAndMedicalKeywords() {
        let t0 = baseDate()
        let bankSample = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Portal", url: "https://checkout.stripe.com/session/123", idleSeconds: 0, screenLocked: false, inputActive: true)
        XCTAssertTrue(PrivacyRedactor.redact(bankSample).redacted)

        let medicalSample = ActivitySample(timestamp: t0, appName: "Preview", bundleId: "com.apple.Preview", windowTitle: "患者病历扫描.pdf", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        XCTAssertTrue(PrivacyRedactor.redact(medicalSample).redacted)

        let safePayload = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "JSON Payload Schema", url: "https://docs.example.com/payload", idleSeconds: 0, screenLocked: false, inputActive: true)
        XCTAssertFalse(PrivacyRedactor.redact(safePayload).redacted)
    }

    func testPrivacyRedactorRedactsPrivateChatAndSystemPrivacySettings() {
        let t0 = baseDate()
        let wechat = ActivitySample(timestamp: t0, appName: "WeChat", bundleId: "com.tencent.xinWeChat", windowTitle: "Chat", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        XCTAssertTrue(PrivacyRedactor.redact(wechat).redacted)
        XCTAssertFalse(PrivacyRedactor.redact(wechat, config: PrivacyRedactorConfig(redactWeChat: false, redactMessages: false)).redacted)

        let sysPrivacy = ActivitySample(timestamp: t0, appName: "System Settings", bundleId: "com.apple.systempreferences", windowTitle: "Privacy & Security", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        XCTAssertTrue(PrivacyRedactor.redact(sysPrivacy).redacted)

        let sysDisplays = ActivitySample(timestamp: t0, appName: "System Settings", bundleId: "com.apple.systempreferences", windowTitle: "Displays", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        XCTAssertFalse(PrivacyRedactor.redact(sysDisplays).redacted)
    }

    func testURLSanitizerStripsSensitiveQueryParameters() {
        let raw = "https://example.com/dashboard?tab=orders&token=secret123&key=abc&session=xyz&sig=999&secret=s&password=p&auth=bearer&page=2"
        XCTAssertEqual(PrivacyRedactor.sanitizeURL(raw), "https://example.com/dashboard?tab=orders&page=2")
        XCTAssertEqual(PrivacyRedactor.sanitizeURL("https://example.com/login?token=abc&sig=def"), "https://example.com/login")
    }

    func testEventMergerMergesWithinPulsetimeAndSplitsBeyondPulsetime() {
        let t0 = baseDate()
        let s1 = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
        let s2 = ActivitySample(timestamp: t0.addingTimeInterval(30), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
        let s3 = ActivitySample(timestamp: t0.addingTimeInterval(55), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
        let s4 = ActivitySample(timestamp: t0.addingTimeInterval(130), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)

        let spans = EventMerger.merge(samples: [s1, s2, s3, s4], declaredTaskId: "ecommerce", pulsetime: 60)
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].durationSeconds, 55, accuracy: 0.001)
    }

    func testSpectrumBuilderComputesMetricsAndDetectsThrashing() {
        let t0 = baseDate()
        let session1 = FocusSessionRecord(id: "s1", taskId: "ecommerce", startedAt: t0, endedAt: t0.addingTimeInterval(20 * 60), minutes: 20.0, note: nil)
        var spans: [EnrichedSpan] = [
            EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(20 * 60), appName: "Browser", bundleId: "com.example.browser", windowTitle: "Example Shop", url: nil, declaredTaskId: "ecommerce", redacted: false)
        ]
        let thrashStart = t0.addingTimeInterval(30 * 60)
        for i in 0..<12 {
            let start = thrashStart.addingTimeInterval(Double(i) * 30)
            spans.append(EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(25), appName: i % 2 == 0 ? "Browser" : "Terminal", bundleId: i % 2 == 0 ? "com.example.browser" : "com.apple.Terminal", windowTitle: "Switch \(i)", url: nil, declaredTaskId: nil, redacted: false))
        }
        let result = SpectrumBuilder.build(spans: spans, focusSessions: [session1], budgets: sampleBudgets(), now: thrashStart.addingTimeInterval(360))
        XCTAssertTrue(result.segments.contains { if case .thrashing = $0.kind { return true }; return false })
        XCTAssertTrue(result.segments.contains { if case .idle = $0.kind { return true }; return false })
        XCTAssertEqual(result.metrics.longestBlockMinutes, 20.0, accuracy: 0.5)
        XCTAssertEqual(result.metrics.solidBlocksCount, 1)
    }

    func testEngineAllowsCrossAppCollaborationDuringFocus() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", note: "Listing prep", at: t0)
        for (i, app) in [("Google Chrome", "com.google.Chrome"), ("Finder", "com.apple.finder"), ("Preview", "com.apple.Preview"), ("Terminal", "com.apple.Terminal")].enumerated() {
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(Double(i + 1) * 300), appName: app.0, bundleId: app.1, windowTitle: "Work \(i)", url: nil, idleSeconds: 2, screenLocked: false, inputActive: true))
        }
        XCTAssertEqual(engine.focusedMinutes(for: "ecommerce"), 20.0, accuracy: 0.001)
    }

    func testEnginePausesOnIdleOrScreenLockWithoutAccumulatingTime() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Shop", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        let idleTime = t0.addingTimeInterval(600)
        engine.ingest(ActivitySample(timestamp: idleTime, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Shop", url: nil, idleSeconds: 300, screenLocked: false, inputActive: false))
        XCTAssertEqual(engine.focusState, .paused(taskId: "ecommerce", pausedAt: idleTime))
        XCTAssertEqual(engine.focusedMinutes(for: "ecommerce"), 5.0, accuracy: 0.001)

        let resumeTime = t0.addingTimeInterval(900)
        engine.startFocus(taskId: "ecommerce", at: resumeTime)
        let lockTime = resumeTime.addingTimeInterval(120)
        engine.ingest(ActivitySample(timestamp: lockTime, appName: "loginwindow", bundleId: "com.apple.loginwindow", windowTitle: nil, url: nil, idleSeconds: 0, screenLocked: true, inputActive: false))
        XCTAssertEqual(engine.focusState, .paused(taskId: "ecommerce", pausedAt: lockTime))
        XCTAssertEqual(engine.focusedMinutes(for: "ecommerce"), 5.0, accuracy: 0.001)
    }

    func testEngineEmitsTargetMetAndCapReachedAndRespectsSnooze() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce-ops", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(26 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        XCTAssertEqual(engine.taskProgress().first { $0.budget.taskId == "ecommerce-ops" }?.status, .approachingCap(remainingMinutes: 4.0))

        let capAlerts = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(31 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        XCTAssertTrue(capAlerts.contains { if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = $0.kind { return true }; return false })

        engine.snoozeAlert(for: "ecommerce-ops", minutes: 15, at: t0.addingTimeInterval(31 * 60))
        let snoozed = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(40 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        XCTAssertFalse(snoozed.contains { if case .quotaCapReached = $0.kind { return true }; return false })

        let afterSnooze = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(47 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        XCTAssertTrue(afterSnooze.contains { if case .quotaCapReached = $0.kind { return true }; return false })

        let switchTime = t0.addingTimeInterval(50 * 60)
        engine.switchTask(to: "hermes", note: "Switched", at: switchTime)
        let targetAlerts = engine.ingest(ActivitySample(timestamp: switchTime.addingTimeInterval(46 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Research", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        XCTAssertTrue(targetAlerts.contains { if case .quotaTargetMet(taskId: "hermes", _, target: 45) = $0.kind { return true }; return false })
    }

    func testEngineDetectsDriftUnassignedAndHighFrequencySwitch() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.ingest(ActivitySample(timestamp: t0, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Docs", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let unassigned10 = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(10 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Docs", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        XCTAssertTrue(unassigned10.contains { if case .unassignedActivePrompt = $0.kind { return true }; return false })

        let focusStart = t0.addingTimeInterval(11 * 60)
        engine.startFocus(taskId: "ecommerce", at: focusStart)
        let driftStart = focusStart.addingTimeInterval(60)
        _ = engine.ingest(ActivitySample(timestamp: driftStart, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Equity Research", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let drift4m = engine.ingest(ActivitySample(timestamp: driftStart.addingTimeInterval(240), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Equity Research", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        XCTAssertTrue(drift4m.contains { if case .taskDrift(declaredTaskId: "ecommerce", detectedTaskId: "hermes", _) = $0.kind { return true }; return false })

        let thrashBase = driftStart.addingTimeInterval(300)
        var thrashAlerts: [SupervisorAlert] = []
        for i in 0..<12 {
            thrashAlerts.append(contentsOf: engine.ingest(ActivitySample(timestamp: thrashBase.addingTimeInterval(Double(i) * 20), appName: i % 2 == 0 ? "Chrome" : "Terminal", bundleId: i % 2 == 0 ? "com.google.Chrome" : "com.apple.Terminal", windowTitle: "Tab \(i)", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)))
        }
        XCTAssertTrue(thrashAlerts.contains { if case .highFrequencySwitch = $0.kind { return true }; return false })
    }

    func testTimeAuditConfigLoaderFallbackAndParsing() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let defaults = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: tmpDir.appendingPathComponent("missing.json"))
        XCTAssertEqual(defaults.count, 4)

        try #"{"projects":[{"name":"ecommerce","keywords":["synthetic-shop"]}]}"#.write(to: tmpDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try #"{"primary_focus":{"project_keys":["ecommerce"],"why":"ignored"}}"#.write(to: tmpDir.appendingPathComponent("focus.json"), atomically: true, encoding: .utf8)

        let loaded = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: nil)
        XCTAssertTrue(loaded.first { $0.taskId == "ecommerce" }?.keywords.contains("synthetic-shop") == true)
    }

    func testDayHelmStoreAtomicWriteRolloverAndPurge() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-store-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", note: "Synthetic note", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(600), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))

        let snapDay1 = engine.snapshot(at: t0.addingTimeInterval(600))
        try store.saveToday(snapDay1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("today.json.tmp").path))
        XCTAssertEqual(try store.loadToday()?.date, "2026-11-17")

        XCTAssertTrue(try store.rolloverIfNeeded(currentSnapshot: snapDay1, newDateString: "2026-11-18"))
        XCTAssertEqual(try store.loadDay(dateString: "2026-11-17")?.date, "2026-11-17")

        let oldSnap = DayHelmDaySnapshot(schemaVersion: 1, date: "2026-11-01", focusState: .unassigned, activeFocus: nil, budgets: [], focusSessions: [], enrichedSpans: [], metrics: DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0))
        try store.archiveDay(oldSnap)

        let partial = try store.purge(before: DayHelmDateFormatting.parseDayString("2026-11-10")!)
        XCTAssertEqual(partial.deletedFiles, 1)
        XCTAssertNotNil(try store.loadDay(dateString: "2026-11-17"))

        let full = try store.purge(before: nil)
        XCTAssertGreaterThanOrEqual(full.deletedFiles, 1)
        XCTAssertNil(try store.loadToday())
    }

    private final class MockAlmaTransport: AlmaHTTPTransport, @unchecked Sendable {
        let handler: @Sendable (URL) throws -> (Data, URLResponse)

        init(handler: @escaping @Sendable (URL) throws -> (Data, URLResponse)) {
            self.handler = handler
        }

        func data(from url: URL) async throws -> (Data, URLResponse) {
            try handler(url)
        }
    }

    private final class MockInspector: ActivityInspecting, @unchecked Sendable {
        var isAccessibilityTrusted: Bool = true
        let sample: ActivitySample
        init(sample: ActivitySample) { self.sample = sample }
        func inspectCurrent() -> ActivitySample { sample }
    }

    func testAlmaBrowserVisitURLTabSplitting() {
        let p1 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/shop/itemtabExample Shop Dashboard")
        XCTAssertEqual(p1.url, "https://example.com/shop/item")
        XCTAssertEqual(p1.tabTitle, "Example Shop Dashboard")

        let p2 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/dashboard?tab=orders&page=2")
        XCTAssertEqual(p2.url, "https://example.com/dashboard?tab=orders&page=2")
        XCTAssertNil(p2.tabTitle)
    }

    func testAlmaActivityClientMockParsingAndOfflineFallback() async {
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let sessionsJSON = """
        [{"id":"s1","startedAt":\(t0Ms),"endedAt":\(t0Ms + 60_000),"durationMs":60000,"appNames":["Chrome"]}]
        """.data(using: .utf8)!
        let detailJSON = """
        {"id":"s1","startedAt":\(t0Ms),"events":[
          {"id":"e1","timestamp":\(t0Ms),"kind":"browser_visit","appName":"Google Chrome","data":{"bundleId":"com.google.Chrome","url":"https://example.com/item?token=abc&v=1tabProduct Page"}}
        ]}
        """.data(using: .utf8)!

        let client = AlmaActivityClient(transport: MockAlmaTransport { url in
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return url.path.hasSuffix("/sessions/s1") ? (detailJSON, resp) : (sessionsJSON, resp)
        })
        let res = await client.fetchTodaySamples(dayStart: t0, dayEnd: t0.addingTimeInterval(3600))
        XCTAssertTrue(res.connected)
        XCTAssertEqual(res.samples.count, 1)
        XCTAssertEqual(res.samples[0].url, "https://example.com/item?v=1")
        XCTAssertEqual(res.samples[0].windowTitle, "Product Page")

        let offline = AlmaActivityClient(transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) })
        let offRes = await offline.fetchTodaySamples(dayStart: t0, dayEnd: t0.addingTimeInterval(3600))
        XCTAssertFalse(offRes.connected)
        XCTAssertTrue(offRes.samples.isEmpty)
    }

    @MainActor
    func testHybridActivityCoordinatorActions() {
        let t0 = baseDate()
        let clock = ManualClock(now: t0)
        let inspector = MockInspector(sample: ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let coord = HybridActivityCoordinator.makeSyntheticDemo(clock: clock, inspector: inspector)
        coord.selectTask("hermes", note: "Reading")
        if case .focusing(let taskId, _) = coord.sessionState {
            XCTAssertEqual(taskId, "hermes")
        } else {
            XCTFail("Expected focusing state")
        }
        coord.updateBudget(taskId: "hermes", targetMinutes: 50, capMinutes: 75)
        XCTAssertEqual(coord.taskProgressList.first { $0.budget.taskId == "hermes" }?.budget.targetMinutes, 50)
    }

    func testCLIStatusAndPurgeCommands() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-cli-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(300)))

        let status = DayHelmCLI.run(arguments: ["dayhelm", "status", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        XCTAssertEqual(status?.exitCode, 0)
        XCTAssertTrue(status?.stdout.contains("电商做深") == true)

        let purge = DayHelmCLI.run(arguments: ["dayhelm", "purge", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        XCTAssertEqual(purge?.exitCode, 0)
        XCTAssertNil(try store.loadToday())
    }

    func testEngineTaskCRUDAndDeleteWhileFocusing() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))

        let added = engine.addTask(
            displayName: "深度写作",
            colorHex: "#EC4899",
            targetMinutes: 50,
            capMinutes: 90,
            keywords: ["writing", "essay"]
        )
        XCTAssertFalse(added.taskId.isEmpty)
        XCTAssertEqual(engine.budgets.count, 5)

        let updated = TaskBudget(
            taskId: added.taskId,
            displayName: "深度写作 · 专栏",
            colorHex: "#06B6D4",
            targetMinutes: 60,
            capMinutes: 120,
            keywords: ["column"]
        )
        engine.updateTask(updated)
        XCTAssertEqual(engine.budgets.last?.displayName, "深度写作 · 专栏")
        XCTAssertEqual(engine.budgets.last?.colorHex, "#06B6D4")
        XCTAssertEqual(engine.budgets.last?.keywords, ["column"])

        engine.moveTask(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        XCTAssertEqual(engine.budgets.first?.taskId, added.taskId)

        engine.startFocus(taskId: added.taskId, at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Draft", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        engine.deleteTask(taskId: added.taskId)

        XCTAssertEqual(engine.budgets.count, 4)
        XCTAssertEqual(engine.focusState, .unassigned)
    }

    @MainActor
    func testConfigLoaderRespectsSavedConfigTruthWithCoordinatorCRUD() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-crud-\(UUID().uuidString)")
        let timeAuditDir = tmpDir.appendingPathComponent("time-audit", isDirectory: true)
        let storeDir = tmpDir.appendingPathComponent("dayhelm", isDirectory: true)
        try FileManager.default.createDirectory(at: timeAuditDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try #"{"primary_focus":{"project_keys":["ecommerce","legacy-ta-task"]}}"#.write(
            to: timeAuditDir.appendingPathComponent("focus.json"),
            atomically: true,
            encoding: .utf8
        )

        let store = DayHelmStore(directory: storeDir)
        let t0 = baseDate()
        let clock = ManualClock(now: t0)
        let inspector = MockInspector(sample: ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Work", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let initial = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: timeAuditDir, dayhelmConfigURL: store.configURL)
        let coord = HybridActivityCoordinator(engine: DayHelmEngine(budgets: initial, clock: clock), store: store, almaClient: nil, inspector: inspector, clock: clock, syntheticDemo: false)

        let created = coord.addTask(displayName: "独立开发", colorHex: "#10B981", targetMinutes: 90, capMinutes: 150, keywords: ["swift"])
        coord.deleteTask(taskId: "legacy-ta-task")
        coord.deleteTask(taskId: "ecommerce-ops")

        let reloaded = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: timeAuditDir, dayhelmConfigURL: store.configURL)
        XCTAssertFalse(reloaded.contains { $0.taskId == "legacy-ta-task" })
        XCTAssertFalse(reloaded.contains { $0.taskId == "ecommerce-ops" })
        XCTAssertEqual(reloaded.first { $0.taskId == created.taskId }?.displayName, "独立开发")
    }
}

#elseif canImport(Testing)
import Testing

@Suite("DayHelmCore Tests")
struct DayHelmCoreTests {

    private func baseDate() -> Date {
        DayHelmDateFormatting.parseISO8601("2026-11-17T09:00:00+08:00")!
    }

    private func sampleBudgets() -> [TaskBudget] {
        [
            TaskBudget(taskId: "ecommerce", displayName: "电商做深", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["example-shop", "product-listing", "ecommerce"]),
            TaskBudget(taskId: "ecommerce-ops", displayName: "电商日常运营", colorHex: "#F59E0B", targetMinutes: nil, capMinutes: 30, keywords: ["support-ticket", "order-refund"]),
            TaskBudget(taskId: "hermes", displayName: "Hermes 投研", colorHex: "#10B981", targetMinutes: 45, capMinutes: 60, keywords: ["hermes", "equity-research"]),
            TaskBudget(taskId: "infra-billing", displayName: "Infra 维护", colorHex: "#8B5CF6", targetMinutes: nil, capMinutes: 30, keywords: ["terraform", "cloud-billing"])
        ]
    }

    @Test("ManualClock advances deterministically")
    func manualClockAdvancesDeterministically() {
        let t0 = baseDate()
        let clock = ManualClock(now: t0)
        #expect(clock.now() == t0)
        clock.advance(by: 125)
        #expect(clock.now() == t0.addingTimeInterval(125))
    }

    @Test("Date formatting respects UTC+8 day rollover and ISO8601")
    func dateFormattingUTCPlus8AndISO8601() {
        let utcDate = DayHelmDateFormatting.parseISO8601("2026-11-16T16:30:00Z")!
        #expect(DayHelmDateFormatting.dayString(from: utcDate, timeZone: DayHelmDateFormatting.shanghaiTimeZone) == "2026-11-17")
        #expect(DayHelmDateFormatting.iso8601String(from: utcDate, timeZone: DayHelmDateFormatting.shanghaiTimeZone) == "2026-11-17T00:30:00+08:00")
    }

    @Test("PrivacyRedactor redacts password managers while preserving appName and bundleId")
    func privacyRedactorRedactsPasswordManagers() {
        let t0 = baseDate()
        let sample = ActivitySample(timestamp: t0, appName: "1Password", bundleId: "com.1password.1password", windowTitle: "Vault", url: "https://example.com", idleSeconds: 0, screenLocked: false, inputActive: true)
        let redacted = PrivacyRedactor.redact(sample)
        #expect(redacted.redacted == true)
        #expect(redacted.windowTitle == nil)
        #expect(redacted.url == nil)
        #expect(redacted.appName == "1Password")
        #expect(redacted.bundleId == "com.1password.1password")
    }

    @Test("PrivacyRedactor redacts banking/payment and medical keywords without false positives")
    func privacyRedactorRedactsBankingAndMedicalKeywords() {
        let t0 = baseDate()
        let bankSample = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Portal", url: "https://checkout.stripe.com/session/123", idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(PrivacyRedactor.redact(bankSample).redacted == true)

        let medicalSample = ActivitySample(timestamp: t0, appName: "Preview", bundleId: "com.apple.Preview", windowTitle: "患者病历扫描.pdf", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(PrivacyRedactor.redact(medicalSample).redacted == true)

        let safePayload = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "JSON Payload Schema", url: "https://docs.example.com/payload", idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(PrivacyRedactor.redact(safePayload).redacted == false)
    }

    @Test("PrivacyRedactor handles private chat toggles and system privacy settings")
    func privacyRedactorRedactsPrivateChatAndSystemPrivacySettings() {
        let t0 = baseDate()
        let wechat = ActivitySample(timestamp: t0, appName: "WeChat", bundleId: "com.tencent.xinWeChat", windowTitle: "Chat", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(PrivacyRedactor.redact(wechat).redacted == true)
        #expect(PrivacyRedactor.redact(wechat, config: PrivacyRedactorConfig(redactWeChat: false, redactMessages: false)).redacted == false)

        let sysPrivacy = ActivitySample(timestamp: t0, appName: "System Settings", bundleId: "com.apple.systempreferences", windowTitle: "Privacy & Security", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(PrivacyRedactor.redact(sysPrivacy).redacted == true)

        let sysDisplays = ActivitySample(timestamp: t0, appName: "System Settings", bundleId: "com.apple.systempreferences", windowTitle: "Displays", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(PrivacyRedactor.redact(sysDisplays).redacted == false)
    }

    @Test("URL sanitizer strips sensitive query parameters")
    func urlSanitizerStripsSensitiveQueryParameters() {
        let raw = "https://example.com/dashboard?tab=orders&token=secret123&key=abc&session=xyz&sig=999&secret=s&password=p&auth=bearer&page=2"
        #expect(PrivacyRedactor.sanitizeURL(raw) == "https://example.com/dashboard?tab=orders&page=2")
        #expect(PrivacyRedactor.sanitizeURL("https://example.com/login?token=abc&sig=def") == "https://example.com/login")
    }

    @Test("EventMerger merges within pulsetime and splits beyond pulsetime")
    func eventMergerMergesWithinPulsetimeAndSplitsBeyondPulsetime() {
        let t0 = baseDate()
        let s1 = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
        let s2 = ActivitySample(timestamp: t0.addingTimeInterval(30), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
        let s3 = ActivitySample(timestamp: t0.addingTimeInterval(55), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
        let s4 = ActivitySample(timestamp: t0.addingTimeInterval(130), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)

        let spans = EventMerger.merge(samples: [s1, s2, s3, s4], declaredTaskId: "ecommerce", pulsetime: 60)
        #expect(spans.count == 2)
        #expect(abs(spans[0].durationSeconds - 55.0) < 0.001)
    }

    @Test("SpectrumBuilder computes metrics and detects thrashing")
    func spectrumBuilderComputesMetricsAndDetectsThrashing() {
        let t0 = baseDate()
        let session1 = FocusSessionRecord(id: "s1", taskId: "ecommerce", startedAt: t0, endedAt: t0.addingTimeInterval(20 * 60), minutes: 20.0, note: nil)
        var spans: [EnrichedSpan] = [
            EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(20 * 60), appName: "Browser", bundleId: "com.example.browser", windowTitle: "Example Shop", url: nil, declaredTaskId: "ecommerce", redacted: false)
        ]
        let thrashStart = t0.addingTimeInterval(30 * 60)
        for i in 0..<12 {
            let start = thrashStart.addingTimeInterval(Double(i) * 30)
            spans.append(EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(25), appName: i % 2 == 0 ? "Browser" : "Terminal", bundleId: i % 2 == 0 ? "com.example.browser" : "com.apple.Terminal", windowTitle: "Switch \(i)", url: nil, declaredTaskId: nil, redacted: false))
        }
        let result = SpectrumBuilder.build(spans: spans, focusSessions: [session1], budgets: sampleBudgets(), now: thrashStart.addingTimeInterval(360))
        #expect(result.segments.contains { if case .thrashing = $0.kind { return true }; return false })
        #expect(result.segments.contains { if case .idle = $0.kind { return true }; return false })
        #expect(abs(result.metrics.longestBlockMinutes - 20.0) < 0.5)
        #expect(result.metrics.solidBlocksCount == 1)
    }

    @Test("Engine allows cross-app collaboration during focus")
    func engineAllowsCrossAppCollaborationDuringFocus() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", note: "Listing prep", at: t0)
        for (i, app) in [("Google Chrome", "com.google.Chrome"), ("Finder", "com.apple.finder"), ("Preview", "com.apple.Preview"), ("Terminal", "com.apple.Terminal")].enumerated() {
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(Double(i + 1) * 300), appName: app.0, bundleId: app.1, windowTitle: "Work \(i)", url: nil, idleSeconds: 2, screenLocked: false, inputActive: true))
        }
        #expect(abs(engine.focusedMinutes(for: "ecommerce") - 20.0) < 0.001)
    }

    @Test("Engine pauses on idle or screen lock without accumulating time")
    func enginePausesOnIdleOrScreenLockWithoutAccumulatingTime() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Shop", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        let idleTime = t0.addingTimeInterval(600)
        engine.ingest(ActivitySample(timestamp: idleTime, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Shop", url: nil, idleSeconds: 300, screenLocked: false, inputActive: false))
        #expect(engine.focusState == .paused(taskId: "ecommerce", pausedAt: idleTime))
        #expect(abs(engine.focusedMinutes(for: "ecommerce") - 5.0) < 0.001)

        let resumeTime = t0.addingTimeInterval(900)
        engine.startFocus(taskId: "ecommerce", at: resumeTime)
        let lockTime = resumeTime.addingTimeInterval(120)
        engine.ingest(ActivitySample(timestamp: lockTime, appName: "loginwindow", bundleId: "com.apple.loginwindow", windowTitle: nil, url: nil, idleSeconds: 0, screenLocked: true, inputActive: false))
        #expect(engine.focusState == .paused(taskId: "ecommerce", pausedAt: lockTime))
        #expect(abs(engine.focusedMinutes(for: "ecommerce") - 5.0) < 0.001)
    }

    @Test("Engine emits targetMet and capReached and respects snooze")
    func engineEmitsTargetMetAndCapReachedAndRespectsSnooze() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce-ops", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(26 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        #expect(engine.taskProgress().first { $0.budget.taskId == "ecommerce-ops" }?.status == .approachingCap(remainingMinutes: 4.0))

        let capAlerts = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(31 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        #expect(capAlerts.contains { if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = $0.kind { return true }; return false })

        engine.snoozeAlert(for: "ecommerce-ops", minutes: 15, at: t0.addingTimeInterval(31 * 60))
        let snoozed = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(40 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        #expect(!snoozed.contains { if case .quotaCapReached = $0.kind { return true }; return false })

        let afterSnooze = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(47 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        #expect(afterSnooze.contains { if case .quotaCapReached = $0.kind { return true }; return false })

        let switchTime = t0.addingTimeInterval(50 * 60)
        engine.switchTask(to: "hermes", note: "Switched", at: switchTime)
        let targetAlerts = engine.ingest(ActivitySample(timestamp: switchTime.addingTimeInterval(46 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Research", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
        #expect(targetAlerts.contains { if case .quotaTargetMet(taskId: "hermes", _, target: 45) = $0.kind { return true }; return false })
    }

    @Test("Engine detects task drift, unassigned prompt, and high-frequency switch")
    func engineDetectsDriftUnassignedAndHighFrequencySwitch() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.ingest(ActivitySample(timestamp: t0, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Docs", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let unassigned10 = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(10 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Docs", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        #expect(unassigned10.contains { if case .unassignedActivePrompt = $0.kind { return true }; return false })

        let focusStart = t0.addingTimeInterval(11 * 60)
        engine.startFocus(taskId: "ecommerce", at: focusStart)
        let driftStart = focusStart.addingTimeInterval(60)
        _ = engine.ingest(ActivitySample(timestamp: driftStart, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Equity Research", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let drift4m = engine.ingest(ActivitySample(timestamp: driftStart.addingTimeInterval(240), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Equity Research", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        #expect(drift4m.contains { if case .taskDrift(declaredTaskId: "ecommerce", detectedTaskId: "hermes", _) = $0.kind { return true }; return false })

        let thrashBase = driftStart.addingTimeInterval(300)
        var thrashAlerts: [SupervisorAlert] = []
        for i in 0..<12 {
            thrashAlerts.append(contentsOf: engine.ingest(ActivitySample(timestamp: thrashBase.addingTimeInterval(Double(i) * 20), appName: i % 2 == 0 ? "Chrome" : "Terminal", bundleId: i % 2 == 0 ? "com.google.Chrome" : "com.apple.Terminal", windowTitle: "Tab \(i)", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)))
        }
        #expect(thrashAlerts.contains { if case .highFrequencySwitch = $0.kind { return true }; return false })
    }

    @Test("TimeAuditConfigLoader falls back gracefully and merges project keywords")
    func timeAuditConfigLoaderFallbackAndParsing() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-cfg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let defaults = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: tmpDir.appendingPathComponent("missing.json"))
        #expect(defaults.count == 4)

        try #"{"projects":[{"name":"ecommerce","keywords":["synthetic-shop"]}]}"#.write(to: tmpDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        try #"{"primary_focus":{"project_keys":["ecommerce"],"why":"ignored"}}"#.write(to: tmpDir.appendingPathComponent("focus.json"), atomically: true, encoding: .utf8)

        let loaded = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: nil)
        #expect(loaded.first { $0.taskId == "ecommerce" }?.keywords.contains("synthetic-shop") == true)
    }

    @Test("DayHelmStore performs atomic write, rollover, and purge")
    func dayHelmStoreAtomicWriteRolloverAndPurge() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-store-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", note: "Synthetic note", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(600), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))

        let snapDay1 = engine.snapshot(at: t0.addingTimeInterval(600))
        try store.saveToday(snapDay1)
        #expect(!FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("today.json.tmp").path))
        #expect((try store.loadToday())?.date == "2026-11-17")

        #expect(try store.rolloverIfNeeded(currentSnapshot: snapDay1, newDateString: "2026-11-18") == true)
        #expect((try store.loadDay(dateString: "2026-11-17"))?.date == "2026-11-17")

        let oldSnap = DayHelmDaySnapshot(schemaVersion: 1, date: "2026-11-01", focusState: .unassigned, activeFocus: nil, budgets: [], focusSessions: [], enrichedSpans: [], metrics: DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0))
        try store.archiveDay(oldSnap)

        let partial = try store.purge(before: DayHelmDateFormatting.parseDayString("2026-11-10")!)
        #expect(partial.deletedFiles == 1)
        #expect((try store.loadDay(dateString: "2026-11-17")) != nil)

        let full = try store.purge(before: nil)
        #expect(full.deletedFiles >= 1)
        #expect((try store.loadToday()) == nil)
    }

    private final class MockAlmaTransport: AlmaHTTPTransport, @unchecked Sendable {
        let handler: @Sendable (URL) throws -> (Data, URLResponse)

        init(handler: @escaping @Sendable (URL) throws -> (Data, URLResponse)) {
            self.handler = handler
        }

        func data(from url: URL) async throws -> (Data, URLResponse) {
            try handler(url)
        }
    }

    private final class MockInspector: ActivityInspecting, @unchecked Sendable {
        var isAccessibilityTrusted: Bool = true
        let sample: ActivitySample
        init(sample: ActivitySample) { self.sample = sample }
        func inspectCurrent() -> ActivitySample { sample }
    }

    @Test("AlmaActivityClient splits concatenated tab URLs without false positives")
    func almaBrowserVisitURLTabSplitting() {
        let p1 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/shop/itemtabExample Shop Dashboard")
        #expect(p1.url == "https://example.com/shop/item")
        #expect(p1.tabTitle == "Example Shop Dashboard")

        let p2 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/dashboard?tab=orders&page=2")
        #expect(p2.url == "https://example.com/dashboard?tab=orders&page=2")
        #expect(p2.tabTitle == nil)
    }

    @Test("AlmaActivityClient parses mocked JSON and degrades gracefully offline")
    func almaActivityClientMockParsingAndOfflineFallback() async {
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let sessionsJSON = """
        [{"id":"s1","startedAt":\(t0Ms),"endedAt":\(t0Ms + 60_000),"durationMs":60000,"appNames":["Chrome"]}]
        """.data(using: .utf8)!
        let detailJSON = """
        {"id":"s1","startedAt":\(t0Ms),"events":[
          {"id":"e1","timestamp":\(t0Ms),"kind":"browser_visit","appName":"Google Chrome","data":{"bundleId":"com.google.Chrome","url":"https://example.com/item?token=abc&v=1tabProduct Page"}}
        ]}
        """.data(using: .utf8)!

        let client = AlmaActivityClient(transport: MockAlmaTransport { url in
            let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return url.path.hasSuffix("/sessions/s1") ? (detailJSON, resp) : (sessionsJSON, resp)
        })
        let res = await client.fetchTodaySamples(dayStart: t0, dayEnd: t0.addingTimeInterval(3600))
        #expect(res.connected == true)
        #expect(res.samples.count == 1)
        #expect(res.samples[0].url == "https://example.com/item?v=1")
        #expect(res.samples[0].windowTitle == "Product Page")

        let offline = AlmaActivityClient(transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) })
        let offRes = await offline.fetchTodaySamples(dayStart: t0, dayEnd: t0.addingTimeInterval(3600))
        #expect(offRes.connected == false)
        #expect(offRes.samples.isEmpty)
    }

    @Test("HybridActivityCoordinator updates tasks and budgets in synthetic demo mode")
    @MainActor
    func hybridActivityCoordinatorActions() {
        let t0 = baseDate()
        let clock = ManualClock(now: t0)
        let inspector = MockInspector(sample: ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let coord = HybridActivityCoordinator.makeSyntheticDemo(clock: clock, inspector: inspector)
        coord.selectTask("hermes", note: "Reading")
        if case .focusing(let taskId, _) = coord.sessionState {
            #expect(taskId == "hermes")
        } else {
            Issue.record("Expected focusing state")
        }
        coord.updateBudget(taskId: "hermes", targetMinutes: 50, capMinutes: 75)
        #expect(coord.taskProgressList.first { $0.budget.taskId == "hermes" }?.budget.targetMinutes == 50)
    }

    @Test("DayHelmCLI runs status and purge commands cleanly")
    func cliStatusAndPurgeCommands() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-cli-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(300)))

        let status = DayHelmCLI.run(arguments: ["dayhelm", "status", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        #expect(status?.exitCode == 0)
        #expect(status?.stdout.contains("电商做深") == true)

        let purge = DayHelmCLI.run(arguments: ["dayhelm", "purge", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        #expect(purge?.exitCode == 0)
        #expect((try store.loadToday()) == nil)
    }

    @Test("Engine supports full task CRUD and resets focus to unassigned when deleting active task")
    func engineTaskCRUDAndDeleteWhileFocusing() {
        let t0 = baseDate()
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))

        let added = engine.addTask(
            displayName: "深度写作",
            colorHex: "#EC4899",
            targetMinutes: 50,
            capMinutes: 90,
            keywords: ["writing", "essay"]
        )
        #expect(!added.taskId.isEmpty)
        #expect(engine.budgets.count == 5)

        let updated = TaskBudget(
            taskId: added.taskId,
            displayName: "深度写作 · 专栏",
            colorHex: "#06B6D4",
            targetMinutes: 60,
            capMinutes: 120,
            keywords: ["column"]
        )
        engine.updateTask(updated)
        #expect(engine.budgets.last?.displayName == "深度写作 · 专栏")
        #expect(engine.budgets.last?.colorHex == "#06B6D4")
        #expect(engine.budgets.last?.keywords == ["column"])

        engine.moveTask(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        #expect(engine.budgets.first?.taskId == added.taskId)

        engine.startFocus(taskId: added.taskId, at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Draft", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        engine.deleteTask(taskId: added.taskId)

        #expect(engine.budgets.count == 4)
        #expect(engine.focusState == .unassigned)
    }

    @Test("TimeAuditConfigLoader uses config.json as primary truth once saved")
    @MainActor
    func configLoaderRespectsSavedConfigTruthWithCoordinatorCRUD() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-crud-\(UUID().uuidString)")
        let timeAuditDir = tmpDir.appendingPathComponent("time-audit", isDirectory: true)
        let storeDir = tmpDir.appendingPathComponent("dayhelm", isDirectory: true)
        try FileManager.default.createDirectory(at: timeAuditDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try #"{"primary_focus":{"project_keys":["ecommerce","legacy-ta-task"]}}"#.write(
            to: timeAuditDir.appendingPathComponent("focus.json"),
            atomically: true,
            encoding: .utf8
        )

        let store = DayHelmStore(directory: storeDir)
        let t0 = baseDate()
        let clock = ManualClock(now: t0)
        let inspector = MockInspector(sample: ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Work", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let initial = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: timeAuditDir, dayhelmConfigURL: store.configURL)
        let coord = HybridActivityCoordinator(engine: DayHelmEngine(budgets: initial, clock: clock), store: store, almaClient: nil, inspector: inspector, clock: clock, syntheticDemo: false)

        let created = coord.addTask(displayName: "独立开发", colorHex: "#10B981", targetMinutes: 90, capMinutes: 150, keywords: ["swift"])
        coord.deleteTask(taskId: "legacy-ta-task")
        coord.deleteTask(taskId: "ecommerce-ops")

        let reloaded = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: timeAuditDir, dayhelmConfigURL: store.configURL)
        #expect(!reloaded.contains { $0.taskId == "legacy-ta-task" })
        #expect(!reloaded.contains { $0.taskId == "ecommerce-ops" })
        #expect(reloaded.first { $0.taskId == created.taskId }?.displayName == "独立开发")
    }
}
#endif
