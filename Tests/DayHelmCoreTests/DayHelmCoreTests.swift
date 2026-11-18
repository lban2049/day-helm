import CoreGraphics
import CoreText
import Foundation
import SQLite3
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

    func testActivityClassifierDistinguishesBrowserVisitsFromFileDocuments() {
        XCTAssertEqual(ActivityClassifier.eventKind(appName: "Google Chrome", bundleId: "com.google.Chrome", url: "https://example.com", redacted: false), "browser_visit")
        XCTAssertEqual(ActivityClassifier.eventKind(appName: "Preview", bundleId: "com.apple.Preview", url: "file:///tmp/a.pdf", redacted: false), "app_focus")
        XCTAssertEqual(ActivityClassifier.eventKind(appName: "Google Chrome", bundleId: "com.google.Chrome", url: "https://example.com", redacted: true), "app_focus")
        XCTAssertEqual(ActivityClassifier.normalizedURLKey("https://Example.com/a#x"), "https://example.com/a")
    }

    func testActivityTextNormalizerIgnoresVolatileTitleJitter() {
        XCTAssertEqual(ActivityTextNormalizer.normalizedTitleKey("Inbox (3) — Gmail"), ActivityTextNormalizer.normalizedTitleKey("Inbox (9) — Gmail"))
        XCTAssertEqual(ActivityTextNormalizer.normalizedTitleKey("Standup 14:52"), ActivityTextNormalizer.normalizedTitleKey("Standup 09:03"))
        XCTAssertEqual(ActivityTextNormalizer.normalizedTitleKey("Uploading… 45%"), ActivityTextNormalizer.normalizedTitleKey("Uploading… 87%"))
        XCTAssertNotEqual(ActivityTextNormalizer.normalizedTitleKey("Alpha Spec"), ActivityTextNormalizer.normalizedTitleKey("Beta Spec"))
        XCTAssertTrue(ActivityTextNormalizer.isVolatileOnlyChange(previous: "Inbox (3)", current: "Inbox (9)"))
    }

    func testPrivacyRedactorMasksCredentialsInFreeFormMetadata() {
        let masked = PrivacyRedactor.redactSecrets(in: "token: abcdef123456 password=hunter2")
        XCTAssertFalse(masked.contains("abcdef123456"))
        XCTAssertFalse(masked.contains("hunter2"))
        XCTAssertEqual(PrivacyRedactor.sanitizeMetadataValue("https://example.com/a?token=abc&page=2"), "https://example.com/a?page=2")
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
        var isAccessibilityTrusted: Bool
        var currentSample: ActivitySample
        init(sample: ActivitySample, isAccessibilityTrusted: Bool = true) {
            self.isAccessibilityTrusted = isAccessibilityTrusted
            self.currentSample = sample
        }
        func inspectCurrent() -> ActivitySample { currentSample }
    }

    private final class MockScreenCapturer: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var currentImage: CGImage
        let isScreenCaptureTrusted: Bool

        init(image: CGImage, isScreenCaptureTrusted: Bool = true) {
            self.currentImage = image
            self.isScreenCaptureTrusted = isScreenCaptureTrusted
        }

        func setImage(_ image: CGImage) {
            lock.withLock {
                currentImage = image
            }
        }

        private func readCurrentImage() -> CGImage {
            lock.withLock {
                currentImage
            }
        }

        func requestScreenCapturePermission() -> Bool {
            isScreenCaptureTrusted
        }

        func captureMainDisplayImage() async throws -> CGImage {
            readCurrentImage()
        }
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

    func testActivityDatabaseSessionLifecycleAndAlmaCompatibility() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let e1 = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Dashboard",
            url: "https://shop.example.com/orders?token=secret123&page=2",
            data: ["bundleId": "com.google.Chrome"],
            declaredTaskId: "ecommerce",
            project: "ecommerce"
        )
        XCTAssertEqual(e1.url, "https://shop.example.com/orders?page=2")
        XCTAssertEqual(e1.windowTitle, "Example Shop Dashboard")

        let snap1 = try db.insertSnapshot(
            sessionId: e1.sessionId,
            timestampMs: t0Ms + 15_000,
            filePath: tmpDir.appendingPathComponent("snapshots/2026-11-17/snap1.jpg").path,
            width: 1280,
            height: 720,
            sizeBytes: 24_576,
            trigger: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Dashboard",
            hashHex: "0123456789abcdef",
            histogram: Array(repeating: 1.0 / 32.0, count: 32),
            diffPct: 1.0,
            declaredTaskId: "ecommerce"
        )
        _ = try db.insertOCRFrame(snapshotId: snap1.id, sessionId: e1.sessionId, text: "Order fulfillment metrics and SKU inventory review", createdAtMs: t0Ms + 15_000)

        _ = try db.insertEvent(timestampMs: t0Ms + 45_000, kind: "lock", appName: "loginwindow")
        let e3 = try db.insertEvent(timestampMs: t0Ms + 200_000, kind: "app_focus", appName: "Terminal", windowTitle: "swift test", declaredTaskId: "infra-billing")
        XCTAssertNotEqual(e3.sessionId, e1.sessionId)

        let sessions = try db.listSessions(sinceMs: t0Ms - 1000, untilMs: t0Ms + 300_000, limit: 10)
        XCTAssertEqual(sessions.count, 2)

        let detail = try db.getSessionDetail(sessionId: e1.sessionId)
        XCTAssertNotNil(detail)
        XCTAssertEqual(detail?.session.declaredTaskId, "ecommerce")
        XCTAssertEqual(detail?.session.eventCount, 2)
        XCTAssertEqual(detail?.session.snapshotCount, 1)
        XCTAssertEqual(detail?.ocrFrames.count, 1)

        let enc = DayHelmDateFormatting.makeEncoder()
        let dec = DayHelmDateFormatting.makeDecoder()
        let almaSess = try dec.decode(AlmaSession.self, from: enc.encode(detail!.session))
        XCTAssertEqual(almaSess.id, e1.sessionId)
        let almaEvt = try dec.decode(AlmaEvent.self, from: enc.encode(e1))
        XCTAssertEqual(almaEvt.kind, "app_focus")
    }

    func testActivityDatabaseSearchAndAgentContext() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let ev = try db.insertEvent(timestampMs: t0Ms, kind: "browser_visit", appName: "Google Chrome", windowTitle: "Hermes Semiconductor Note", url: "https://research.example.com/semiconductor-q4", declaredTaskId: "hermes")
        let snap = try db.insertSnapshot(sessionId: ev.sessionId, timestampMs: t0Ms + 5_000, filePath: tmpDir.appendingPathComponent("snap.jpg").path, width: 800, height: 600, sizeBytes: 10_000, appName: "Google Chrome", windowTitle: "Hermes Semiconductor Note")
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Quarterly wafer fab utilization reached 92% in Q4.", createdAtMs: t0Ms + 5_000)

        XCTAssertTrue(try db.search(keyword: "wafer fab", limit: 10).contains { $0.sourceKind == "ocr" })
        XCTAssertTrue(try db.search(keyword: "semiconductor-q4", limit: 10).contains { $0.sourceKind == "event" })

        let ctx = try db.queryAgentContext(sinceMs: t0Ms - 1000, untilMs: t0Ms + 60_000, maxOCRChars: 500)
        XCTAssertEqual(ctx.sessionCount, 1)
        XCTAssertEqual(ctx.ocrFrameCount, 1)
        XCTAssertTrue(ctx.recentWindows.contains { $0.windowTitle == "Hermes Semiconductor Note" })
        XCTAssertTrue(ctx.ocrHighlights.contains { $0.text.contains("wafer fab") })
    }

    func testImageHistogramAndVisionOCR() async throws {
        let whiteImg = try makeSyntheticTextImage(text: "DayHelm OCR 2026", backgroundWhite: true)
        let sameImg = try makeSyntheticTextImage(text: "DayHelm OCR 2026", backgroundWhite: true)
        let darkImg = try makeSyntheticTextImage(text: "Completely Different Screen", backgroundWhite: false)

        let h1 = ImageHistogram.computeHistogram(from: whiteImg, bins: 32)
        let h2 = ImageHistogram.computeHistogram(from: sameImg, bins: 32)
        let hDark = ImageHistogram.computeHistogram(from: darkImg, bins: 32)

        XCTAssertEqual(h1.count, 32)
        XCTAssertEqual(ImageHistogram.histogramDistance(from: h1, to: h2), 0.0, accuracy: 0.001)
        XCTAssertGreaterThan(ImageHistogram.histogramDistance(from: h1, to: hDark), 0.5)
        XCTAssertEqual(ImageHistogram.computePerceptualHashHex(from: whiteImg), ImageHistogram.computePerceptualHashHex(from: sameImg))

        let ocr = try await VisionOCRService.recognizeText(from: whiteImg)
        XCTAssertTrue(ocr.text.contains("DayHelm") || ocr.text.contains("2026"))
        XCTAssertGreaterThan(ocr.charCount, 0)
    }

    func testCLIQuerySearchAndSessionsCommands() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-clihub-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Catalog Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(300)))

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let ev = try db.insertEvent(timestampMs: t0Ms + 60_000, kind: "app_focus", appName: "Editor", windowTitle: "Catalog Spec", url: "https://docs.example.com/catalog", declaredTaskId: "ecommerce")
        let snap = try db.insertSnapshot(sessionId: ev.sessionId, timestampMs: t0Ms + 65_000, filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/s1.jpg").path, width: 640, height: 360, sizeBytes: 4096, appName: "Editor", windowTitle: "Catalog Spec")
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Spring SKU pricing matrix", createdAtMs: t0Ms + 65_000)

        let queryJSON = DayHelmCLI.run(arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0.addingTimeInterval(300)))
        XCTAssertEqual(queryJSON?.exitCode, 0)
        XCTAssertTrue(queryJSON?.stdout.contains("Spring SKU pricing matrix") == true)

        let searchRes = DayHelmCLI.run(arguments: ["dayhelm", "search", "SKU pricing", "--limit", "5", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        XCTAssertEqual(searchRes?.exitCode, 0)
        XCTAssertTrue(searchRes?.stdout.contains("Spring SKU pricing matrix") == true)

        let detailRes = DayHelmCLI.run(arguments: ["dayhelm", "sessions", "--id", ev.sessionId, "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        XCTAssertEqual(detailRes?.exitCode, 0)
        XCTAssertTrue(detailRes?.stdout.contains("https://docs.example.com/catalog") == true)
    }

    func testLocalActivityHTTPServerEndpoints() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-http-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "hermes", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(120), appName: "Preview", bundleId: "com.apple.Preview", windowTitle: "Earnings Call.pdf", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let daySnap = engine.snapshot(at: t0.addingTimeInterval(120))
        try store.saveToday(daySnap)

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let ev = try db.insertEvent(timestampMs: t0Ms + 10_000, kind: "app_focus", appName: "Preview", windowTitle: "Earnings Call.pdf", declaredTaskId: "hermes")
        let snap = try db.insertSnapshot(sessionId: ev.sessionId, timestampMs: t0Ms + 12_000, filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/p1.jpg").path, width: 1024, height: 768, sizeBytes: 8192, appName: "Preview", windowTitle: "Earnings Call.pdf")
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Revenue guidance raised by 14%", createdAtMs: t0Ms + 12_000)

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(120)),
            stateProvider: { LocalActivityHTTPServer.RuntimeState(axTrusted: true, screenCaptureTrusted: true, deepRecordingEnabled: true, daySnapshot: daySnap) }
        )
        XCTAssertEqual(LocalActivityHTTPServer.defaultPrimaryPort, 24001)
        XCTAssertFalse(LocalActivityHTTPServer.defaultPortCandidates.contains(23001))
        XCTAssertTrue(LocalActivityHTTPServer.defaultPortCandidates.allSatisfy { (24001...24009).contains($0) })

        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try XCTUnwrap(ports.first)

        let session = URLSession(configuration: .ephemeral)
        let dec = DayHelmDateFormatting.makeDecoder()

        let (statusData, statusResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/status")!)
        XCTAssertEqual((statusResp as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try dec.decode(LocalRecorderStatusSnapshot.self, from: statusData).source, "dayhelm")

        let (detailData, detailResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/\(ev.sessionId)")!)
        XCTAssertEqual((detailResp as? HTTPURLResponse)?.statusCode, 200)
        let detail = try dec.decode(RecordedSessionDetail.self, from: detailData)
        XCTAssertEqual(detail.session.declaredTaskId, "hermes")
        XCTAssertEqual(detail.events.first?.windowTitle, "Earnings Call.pdf")

        let (_, missingResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/missing")!)
        XCTAssertEqual((missingResp as? HTTPURLResponse)?.statusCode, 404)

        let (ctxData, ctxResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!)
        XCTAssertEqual((ctxResp as? HTTPURLResponse)?.statusCode, 200)
        let ctx = try dec.decode(DayHelmContextAPIResponse.self, from: ctxData)
        XCTAssertEqual(ctx.activeFocus?.taskId, "hermes")
        XCTAssertTrue(ctx.activity.ocrHighlights.contains { $0.text.contains("Revenue guidance") })
    }

    func testNativeScreenRecorderPrivacyDedupAndRetentionPrune() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-rec-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: store.snapshotsDirectory, clock: ManualClock(now: t0))

        let imgA = try makeSyntheticTextImage(text: "Product Spec Alpha 2026", backgroundWhite: true)
        let imgB = try makeSyntheticTextImage(text: "Night Console View", backgroundWhite: false)

        let redacted = PrivacyRedactor.redact(ActivitySample(timestamp: t0, appName: "1Password", bundleId: "com.1password.1password", windowTitle: "Vault", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let savedRedacted = try await recorder.processCapturedImage(imgA, sample: redacted, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
        XCTAssertFalse(savedRedacted)

        let locked = ActivitySample(timestamp: t0.addingTimeInterval(5), appName: "loginwindow", bundleId: "com.apple.loginwindow", windowTitle: nil, url: nil, idleSeconds: 0, screenLocked: true, inputActive: false)
        let savedLocked = try await recorder.processCapturedImage(imgA, sample: locked, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
        XCTAssertFalse(savedLocked)

        let s1 = ActivitySample(timestamp: t0.addingTimeInterval(10), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved1 = try await recorder.processCapturedImage(imgA, sample: s1, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
        XCTAssertTrue(saved1)
        let s2 = ActivitySample(timestamp: t0.addingTimeInterval(25), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved2 = try await recorder.processCapturedImage(imgA, sample: s2, trigger: "visual_change", declaredTaskId: "ecommerce", runOCR: true)
        XCTAssertFalse(saved2)
        let s3 = ActivitySample(timestamp: t0.addingTimeInterval(40), appName: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "Console", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved3 = try await recorder.processCapturedImage(imgB, sample: s3, trigger: "visual_change", declaredTaskId: "infra-billing", runOCR: true)
        XCTAssertTrue(saved3)

        try store.saveBudgets(sampleBudgets())
        try store.saveSettings(DayHelmSettings(deepRecordingEnabled: false, snapshotRetentionDays: 14))
        XCTAssertFalse(store.loadSettings().deepRecordingEnabled)
        XCTAssertEqual(TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: store.configURL).count, 4)

        let oldDir = store.snapshotsDirectory.appendingPathComponent("2026-10-01", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        let oldJPEG = oldDir.appendingPathComponent("old.jpg")
        try Data("fake".utf8).write(to: oldJPEG)
        let pruned = try db.pruneOldSnapshots(olderThanDays: 7, snapshotsRootDir: store.snapshotsDirectory, now: t0)
        XCTAssertEqual(pruned.deletedFiles, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldJPEG.path))
    }

    func testFullDayE2ECoordinatorPipelineMorningToRollover() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-e2e-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate() // 2026-11-17T09:00:00+08:00
        let clock = ManualClock(now: t0)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let imgXcode1 = try makeSyntheticTextImage(text: "Xcode DayHelmEngine Pipeline", backgroundWhite: true)
        let imgTerminal = try makeSyntheticTextImage(text: "Terminal Swift Test Runner", backgroundWhite: false)
        let imgChrome = try makeSyntheticTextImage(text: "Swift Concurrency Documentation", backgroundWhite: true)
        let imgXcode2 = try makeSyntheticTextImage(text: "DayHelmChecks Main Verification", backgroundWhite: false)

        let capturer = MockScreenCapturer(image: imgXcode1, isScreenCaptureTrusted: true)
        let recorder = NativeScreenRecorder(
            database: db,
            snapshotsRootDir: store.snapshotsDirectory,
            capturer: capturer,
            clock: clock
        )
        let inspector = MockInspector(
            sample: ActivitySample(
                timestamp: t0,
                appName: "Xcode",
                bundleId: "com.apple.dt.Xcode",
                windowTitle: "DayHelmEngine.swift — focus-guard",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ),
            isAccessibilityTrusted: true
        )
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
        let coordinator = await MainActor.run {
            HybridActivityCoordinator(
                engine: engine,
                store: store,
                almaClient: nil,
                inspector: inspector,
                clock: clock,
                syntheticDemo: false,
                database: db,
                screenRecorder: recorder,
                httpServer: nil
            )
        }

        let httpServer = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: clock,
            stateProvider: { coordinator.currentRuntimeState() }
        )
        let ports = await httpServer.start(primaryPort: 0, fallbackPort: nil)
        defer { httpServer.stop() }
        let port = try XCTUnwrap(ports.first)

        // 09:00: User adds custom task "独立开发 · DayHelm" (target 60m, cap 90m) and starts focus
        let customTask = await MainActor.run { () -> TaskBudget in
            let created = coordinator.addTask(
                displayName: "独立开发 · DayHelm",
                colorHex: "#3B82F6",
                targetMinutes: 60,
                capMinutes: 90,
                keywords: ["xcode", "dayhelm", "swift"]
            )
            coordinator.selectTask(created.taskId, note: "Full-day E2E pipeline")
            return created
        }

        // 09:00: Xcode sample + snapshot #1 + OCR #1
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #1 + OCR #1 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 1 && coordinator.todayOCRCount >= 1 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // 09:15: Terminal sample + snapshot #2 + OCR #2
        clock.advance(by: 15 * 60)
        capturer.setImage(imgTerminal)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "swift test — focus-guard",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #2 + OCR #2 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 2 && coordinator.todayOCRCount >= 2 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // 09:30: Sensitive 1Password sample -> MUST redact and produce 0 snapshots/OCR
        clock.advance(by: 15 * 60)
        capturer.setImage(imgChrome)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "1Password",
            bundleId: "com.1password.1password",
            windowTitle: "Vault Master Password",
            url: "https://vault.1password.com/item?secret=topsecret",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await Task.sleep(nanoseconds: 80_000_000)
        let after1Pass = await MainActor.run { (coordinator.latestSample, coordinator.todaySnapshotCount) }
        XCTAssertEqual(after1Pass.0?.redacted, true)
        XCTAssertNil(after1Pass.0?.windowTitle)
        XCTAssertNil(after1Pass.0?.url)
        XCTAssertEqual(after1Pass.1, 2)

        // 09:45: Chrome sample + snapshot #3 + OCR #3
        clock.advance(by: 15 * 60)
        capturer.setImage(imgChrome)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Swift Concurrency Docs",
            url: "https://docs.swift.org/concurrency?token=secret123&page=1",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #3 + OCR #3 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 3 && coordinator.todayOCRCount >= 3 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // 10:00: Xcode sample -> reaches 60m -> targetMet alert fires + snapshot #4 + OCR #4
        clock.advance(by: 15 * 60)
        capturer.setImage(imgXcode2)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitle: "DayHelmChecks — main.swift",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #4 + OCR #4 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 4 && coordinator.todayOCRCount >= 4 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let alert1000 = await MainActor.run { coordinator.activeAlert }
        if case .quotaTargetMet(taskId: let alertedTask, _, target: 60) = alert1000?.kind {
            XCTAssertEqual(alertedTask, customTask.taskId)
        } else {
            XCTFail("Expected quotaTargetMet alert at 60m, got \(String(describing: alert1000))")
        }

        // 10:05: Terminal sample -> 65m cross-app total
        clock.advance(by: 5 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "git status — focus-guard",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let customProgress = await MainActor.run {
            coordinator.taskProgressList.first { $0.budget.taskId == customTask.taskId }
        }
        XCTAssertEqual(customProgress?.focusedMinutes ?? 0, 65.0, accuracy: 0.01)

        // 10:05 -> 10:35: Switch to "电商日常运营" (cap 30m)
        await MainActor.run {
            coordinator.selectTask("ecommerce-ops", note: "Daily support queue")
        }
        clock.advance(by: 30 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #301",
            url: "https://ops.example.com/tickets/301",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let capAlert = await MainActor.run { coordinator.activeAlert }
        if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = capAlert?.kind {
            // OK
        } else {
            XCTFail("Expected quotaCapReached for ecommerce-ops at 10:35, got \(String(describing: capAlert))")
        }

        // User snoozes 15m via coordinator.handleAlertAction
        await MainActor.run {
            coordinator.handleAlertAction(.snooze(minutes: 15, label: "+15m 收尾"))
        }
        let clearedAlert = await MainActor.run { coordinator.activeAlert }
        XCTAssertNil(clearedAlert)

        // 10:40 (+5m): Alert stays suppressed
        clock.advance(by: 5 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #302",
            url: "https://ops.example.com/tickets/302",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let suppressedAlert = await MainActor.run { coordinator.activeAlert }
        XCTAssertNil(suppressedAlert)

        // 10:51 (+11m, total 16m past snooze): Alert re-arms
        clock.advance(by: 11 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #303",
            url: "https://ops.example.com/tickets/303",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let rearmedAlert = await MainActor.run { coordinator.activeAlert }
        if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = rearmedAlert?.kind {
            // OK
        } else {
            XCTFail("Expected quotaCapReached to re-arm after 15m snooze")
        }

        // 11:00 (+9m): Verify HTTP server + CLI return exact accumulated task minutes, sessions, window titles & OCR
        clock.advance(by: 9 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #304",
            url: "https://ops.example.com/tickets/304",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await Task.sleep(nanoseconds: 120_000_000)

        let urlSession = URLSession(configuration: .ephemeral)
        let dec = DayHelmDateFormatting.makeDecoder()

        let (ctxData, ctxResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!)
        XCTAssertEqual((ctxResp as? HTTPURLResponse)?.statusCode, 200)
        let ctx = try dec.decode(DayHelmContextAPIResponse.self, from: ctxData)
        XCTAssertEqual(ctx.budgets.first { $0.taskId == customTask.taskId }?.focusedMinutes ?? 0, 65.0, accuracy: 0.01)
        XCTAssertEqual(ctx.budgets.first { $0.taskId == "ecommerce-ops" }?.focusedMinutes ?? 0, 55.0, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(ctx.activity.sessionCount, 1)
        XCTAssertTrue(ctx.activity.recentWindows.contains { $0.windowTitle == "DayHelmEngine.swift — focus-guard" })
        XCTAssertTrue(ctx.activity.recentWindows.contains { $0.windowTitle == "Swift Concurrency Docs" })
        XCTAssertFalse(ctx.activity.recentWindows.contains { ($0.windowTitle ?? "").contains("Vault Master Password") })
        XCTAssertTrue(ctx.activity.ocrHighlights.contains { $0.text.contains("Terminal") || $0.text.contains("Xcode") || $0.text.contains("Concurrency") })

        let (sessData, sessResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions")!)
        XCTAssertEqual((sessResp as? HTTPURLResponse)?.statusCode, 200)
        let sessJSON = String(data: sessData, encoding: .utf8) ?? ""
        XCTAssertTrue(sessJSON.contains(ctx.activity.sessions[0].id))

        let cliResult = DayHelmCLI.run(
            arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path],
            clock: clock
        )
        XCTAssertEqual(cliResult?.exitCode, 0)
        let cliOut = cliResult?.stdout ?? ""
        XCTAssertTrue(cliOut.contains(customTask.taskId))
        XCTAssertTrue(cliOut.contains("DayHelmEngine.swift — focus-guard"))
        XCTAssertTrue(cliOut.contains("Swift Concurrency Docs"))
        XCTAssertFalse(cliOut.contains("Vault Master Password"))
        XCTAssertTrue(cliOut.contains("Concurrency") || cliOut.contains("Terminal") || cliOut.contains("DayHelmEngine"))

        let cliJSONObj = try JSONSerialization.jsonObject(with: Data(cliOut.utf8)) as? [String: Any]
        let cliBudgets = cliJSONObj?["budgets"] as? [[String: Any]] ?? []
        let cliCustomMinutes = cliBudgets.first { ($0["taskId"] as? String) == customTask.taskId }?["focusedMinutes"] as? Double
        XCTAssertEqual(cliCustomMinutes ?? 0, 65.0, accuracy: 0.01)

        // 00:05 next day (2026-11-18): Rollover archives 2026-11-17.json and resets counters to 0
        let nextDay = DayHelmDateFormatting.parseISO8601("2026-11-18T00:05:00+08:00")!
        clock.advance(by: nextDay.timeIntervalSince(clock.now()))
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Finder",
            bundleId: "com.apple.finder",
            windowTitle: "Desktop",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }

        let archivedURL = store.daysDirectory.appendingPathComponent("2026-11-17.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archivedURL.path))
        let archivedSnap = try store.loadDay(dateString: "2026-11-17")
        XCTAssertEqual(archivedSnap?.budgets.first { $0.taskId == customTask.taskId }?.focusedMinutes ?? 0, 65.0, accuracy: 0.01)

        let nextDayProgress = await MainActor.run { coordinator.taskProgressList }
        XCTAssertTrue(nextDayProgress.allSatisfy { $0.focusedMinutes == 0 })
        let nextSessionState = await MainActor.run { coordinator.sessionState }
        XCTAssertEqual(nextSessionState, .unassigned)
        XCTAssertEqual((try store.loadToday())?.date, "2026-11-18")
    }

    func testAlmaTimeAuditContractCompatibilityE2E() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-alma-contract-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let e1 = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Orders",
            url: "https://shop.example.com/orders",
            data: ["bundleId": "com.google.Chrome", "appName": "Google Chrome"],
            declaredTaskId: "ecommerce",
            project: "ecommerce"
        )
        let snap1 = try db.insertSnapshot(
            sessionId: e1.sessionId,
            timestampMs: t0Ms + 15_000,
            filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/c1.jpg").path,
            width: 1440,
            height: 900,
            sizeBytes: 12_345,
            trigger: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Orders",
            declaredTaskId: "ecommerce",
            project: "ecommerce"
        )
        _ = try db.insertOCRFrame(
            snapshotId: snap1.id,
            sessionId: e1.sessionId,
            text: "Order #9921 Shipped",
            createdAtMs: t0Ms + 15_000
        )
        try db.closeSession(sessionId: e1.sessionId, endedAtMs: t0Ms + 120_000)

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(120)),
            stateProvider: { LocalActivityHTTPServer.RuntimeState(axTrusted: true, screenCaptureTrusted: true, deepRecordingEnabled: true) }
        )
        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try XCTUnwrap(ports.first)

        let urlSession = URLSession(configuration: .ephemeral)

        let (statusData, statusResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/status")!)
        XCTAssertEqual((statusResp as? HTTPURLResponse)?.statusCode, 200)
        let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
        XCTAssertTrue(isJSONBoolean(statusJSON?["running"]))
        XCTAssertEqual(statusJSON?["running"] as? Bool, true)

        let sinceMs = t0Ms - 60_000
        let untilMs = t0Ms + 300_000
        let listURL = URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions?limit=2000&since=\(sinceMs)&until=\(untilMs)")!
        let (listData, listResp) = try await urlSession.data(from: listURL)
        XCTAssertEqual((listResp as? HTTPURLResponse)?.statusCode, 200)
        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        let sessions = try XCTUnwrap(listJSON?["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 1)
        let s0 = sessions[0]
        XCTAssertTrue(s0["id"] is String)
        XCTAssertTrue(isJSONInteger(s0["startedAt"]))
        XCTAssertTrue(isJSONInteger(s0["endedAt"]))
        XCTAssertTrue(isJSONInteger(s0["durationMs"]))
        XCTAssertTrue(s0["appNames"] is [String])
        XCTAssertTrue(s0["analysisStatus"] is String)
        XCTAssertTrue(s0["analysisTitle"] is String)
        XCTAssertTrue(s0["analysisDescription"] is String)
        XCTAssertTrue(s0["project"] is String)
        XCTAssertTrue(s0["highlights"] is [String])

        let detailURL = URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/\(e1.sessionId)")!
        let (detailData, detailResp) = try await urlSession.data(from: detailURL)
        XCTAssertEqual((detailResp as? HTTPURLResponse)?.statusCode, 200)
        let detailJSON = try JSONSerialization.jsonObject(with: detailData) as? [String: Any]
        let events = try XCTUnwrap(detailJSON?["events"] as? [[String: Any]])
        XCTAssertEqual(events.count, 1)
        XCTAssertTrue(events[0]["kind"] is String)
        XCTAssertTrue(isJSONInteger(events[0]["timestamp"]))
        XCTAssertTrue(events[0]["appName"] is String)
        XCTAssertTrue(events[0]["data"] is [String: Any])

        let snapshots = try XCTUnwrap(detailJSON?["snapshots"] as? [[String: Any]])
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertTrue(snapshots[0]["trigger"] is String)
        XCTAssertTrue(snapshots[0]["appName"] is String)
        XCTAssertTrue(snapshots[0]["windowTitle"] is String)
    }

    func testSubprocessBinaryCLIAndExitCodesE2E() throws {
        let appBinary = try resolveDayHelmAppExecutableURL()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-proc-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: now))
        engine.startFocus(taskId: "ecommerce", note: "Subprocess CLI E2E", at: now.addingTimeInterval(-300))
        engine.ingest(ActivitySample(
            timestamp: now,
            appName: "Editor",
            bundleId: "com.example.editor",
            windowTitle: "Subprocess keyword window",
            url: "https://docs.example.com/keyword",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        ))
        try store.saveToday(engine.snapshot(at: now))

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let ev = try db.insertEvent(
            timestampMs: nowMs - 60_000,
            kind: "app_focus",
            appName: "Editor",
            windowTitle: "Subprocess keyword window",
            url: "https://docs.example.com/keyword",
            declaredTaskId: "ecommerce"
        )
        let snap = try db.insertSnapshot(
            sessionId: ev.sessionId,
            timestampMs: nowMs - 30_000,
            filePath: store.snapshotsDirectory.appendingPathComponent("snap.jpg").path,
            width: 800,
            height: 600,
            sizeBytes: 2048,
            appName: "Editor",
            windowTitle: "Subprocess keyword window"
        )
        _ = try db.insertOCRFrame(
            snapshotId: snap.id,
            sessionId: ev.sessionId,
            text: "DayHelm subprocess keyword OCR verification",
            createdAtMs: nowMs - 30_000
        )

        let helpProc = try runProcess(executableURL: appBinary, arguments: ["--help"])
        XCTAssertEqual(helpProc.exitCode, 0)
        XCTAssertTrue(helpProc.stdout.contains("Usage:") && helpProc.stdout.contains("dayhelm"))

        let statusProc = try runProcess(executableURL: appBinary, arguments: ["status", "--store-dir", tmpDir.path])
        XCTAssertEqual(statusProc.exitCode, 0)
        XCTAssertTrue(statusProc.stdout.contains("DayHelm Status") && statusProc.stdout.contains("电商做深"))

        let queryProc = try runProcess(executableURL: appBinary, arguments: ["query", "--today", "--format", "md", "--store-dir", tmpDir.path])
        XCTAssertEqual(queryProc.exitCode, 0)
        XCTAssertTrue(queryProc.stdout.contains("# DayHelm Activity Context") && queryProc.stdout.contains("keyword"))

        let searchProc = try runProcess(executableURL: appBinary, arguments: ["search", "keyword", "--store-dir", tmpDir.path])
        XCTAssertEqual(searchProc.exitCode, 0)
        XCTAssertTrue(searchProc.stdout.contains("# DayHelm Search") && searchProc.stdout.contains("keyword"))

        let purgeProc = try runProcess(executableURL: appBinary, arguments: ["purge", "--store-dir", tmpDir.path])
        XCTAssertEqual(purgeProc.exitCode, 0)
        XCTAssertTrue(purgeProc.stdout.contains("DayHelm purge completed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.todayURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.databaseURL.path))

        let unknownProc = try runProcess(executableURL: appBinary, arguments: ["unknown-flag"])
        XCTAssertNotEqual(unknownProc.exitCode, 0)
        XCTAssertFalse(unknownProc.stderr.isEmpty)
    }

    func testConcurrentSQLiteReaderWriterStressWALModeE2E() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-xct-stress-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        let daySnap = engine.snapshot(at: t0.addingTimeInterval(600))
        try store.saveToday(daySnap)

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        XCTAssertEqual(try db.journalMode().lowercased(), "wal")

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(600)),
            stateProvider: {
                LocalActivityHTTPServer.RuntimeState(
                    axTrusted: true,
                    screenCaptureTrusted: true,
                    deepRecordingEnabled: true,
                    daySnapshot: daySnap
                )
            }
        )
        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try XCTUnwrap(ports.first)

        let contextURL = URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!
        let urlSession = URLSession(configuration: .ephemeral)
        let dec = DayHelmDateFormatting.makeDecoder()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<50 {
                    _ = try db.insertEvent(
                        timestampMs: t0Ms + Int64(i * 2000),
                        kind: i % 5 == 0 ? "browser_visit" : "app_focus",
                        appName: i % 2 == 0 ? "Xcode" : "Terminal",
                        windowTitle: "StressWindow-\(i)",
                        url: i % 5 == 0 ? "https://example.com/stress/\(i)" : nil,
                        declaredTaskId: "ecommerce"
                    )
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
            }

            group.addTask {
                for i in 0..<25 {
                    let snap = try db.insertSnapshot(
                        timestampMs: t0Ms + Int64(i * 4000) + 500,
                        filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/stress-\(i).jpg").path,
                        width: 1280,
                        height: 720,
                        sizeBytes: 4096,
                        trigger: "visual_change",
                        appName: "Xcode",
                        windowTitle: "StressWindow-\(i)",
                        declaredTaskId: "ecommerce"
                    )
                    _ = try db.insertOCRFrame(
                        snapshotId: snap.id,
                        sessionId: snap.sessionId,
                        text: "StressOCR frame payload \(i)",
                        createdAtMs: t0Ms + Int64(i * 4000) + 500
                    )
                    try await Task.sleep(nanoseconds: 3_000_000)
                }
            }

            group.addTask {
                for _ in 0..<25 {
                    let (data, resp) = try await urlSession.data(from: contextURL)
                    XCTAssertEqual((resp as? HTTPURLResponse)?.statusCode, 200)
                    _ = try dec.decode(DayHelmContextAPIResponse.self, from: data)
                    try await Task.sleep(nanoseconds: 3_000_000)
                }
            }

            group.addTask {
                for _ in 0..<15 {
                    let res = DayHelmCLI.run(
                        arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path],
                        clock: ManualClock(now: t0.addingTimeInterval(600))
                    )
                    XCTAssertEqual(res?.exitCode, 0)
                    try await Task.sleep(nanoseconds: 4_000_000)
                }
            }

            try await group.waitForAll()
        }

        let counts = try db.todayCounts(dayStartMs: t0Ms - 1000, dayEndMs: t0Ms + 86_400_000)
        XCTAssertEqual(counts.events, 50)
        XCTAssertEqual(counts.snapshots, 25)
        XCTAssertEqual(counts.ocrFrames, 25)
        XCTAssertEqual(try db.integrityCheck().lowercased(), "ok")
        XCTAssertEqual((try db.search(keyword: "StressOCR", limit: 50)).count, 25)
    }

    private func waitUntil(
        _ description: String,
        timeoutSeconds: TimeInterval = 8.0,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw NSError(domain: "DayHelmCoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for: \(description)"])
    }

    private func isJSONBoolean(_ value: Any?) -> Bool {
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) == CFBooleanGetTypeID()
    }

    private func isJSONInteger(_ value: Any?) -> Bool {
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) != CFBooleanGetTypeID()
    }

    private func resolveDayHelmAppExecutableURL() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []

        for bundle in Bundle.allBundles {
            candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("DayHelmApp"))
        }
        if let mainExecDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(mainExecDir.appendingPathComponent("DayHelmApp"))
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        var repoRoot = sourceURL.deletingLastPathComponent()
        while repoRoot.path != "/" {
            if fm.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path) {
                break
            }
            repoRoot = repoRoot.deletingLastPathComponent()
        }

        candidates.append(repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/DayHelmApp"))
        candidates.append(repoRoot.appendingPathComponent(".build/debug/DayHelmApp"))
        candidates.append(repoRoot.appendingPathComponent(".build/release/DayHelmApp"))

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }

        let buildProc = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build", "--product", "DayHelmApp"],
            currentDirectoryURL: repoRoot,
            timeoutSeconds: 60.0
        )
        guard buildProc.exitCode == 0 else {
            throw NSError(domain: "DayHelmCoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to build DayHelmApp: \(buildProc.stderr)"])
        }

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        throw NSError(domain: "DayHelmCoreTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to locate compiled DayHelmApp executable"])
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeoutSeconds: TimeInterval = 15.0
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let doneSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            doneSemaphore.signal()
        }

        try process.run()
        let waitResult = doneSemaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            throw NSError(domain: "DayHelmCoreTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Process timed out"])
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private func makeSyntheticTextImage(text: String, backgroundWhite: Bool, width: Int = 960, height: Int = 240) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        ctx.setFillColor(red: backgroundWhite ? 1 : 0.08, green: backgroundWhite ? 1 : 0.09, blue: backgroundWhite ? 1 : 0.12, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let fgColor = backgroundWhite ? CGColor(red: 0, green: 0, blue: 0, alpha: 1) : CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 1)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: fgColor]
        let attrString = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        ctx.textPosition = CGPoint(x: 40, y: 95)
        CTLineDraw(line, ctx)
        return try XCTUnwrap(ctx.makeImage())
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

    @Test("ActivityClassifier keeps file documents as app_focus and web URLs as browser_visit")
    func activityClassifierDistinguishesBrowserVisitsFromFileDocuments() {
        #expect(ActivityClassifier.eventKind(appName: "Google Chrome", bundleId: "com.google.Chrome", url: "https://example.com", redacted: false) == "browser_visit")
        #expect(ActivityClassifier.eventKind(appName: "Preview", bundleId: "com.apple.Preview", url: "file:///tmp/a.pdf", redacted: false) == "app_focus")
        #expect(ActivityClassifier.eventKind(appName: "Google Chrome", bundleId: "com.google.Chrome", url: "https://example.com", redacted: true) == "app_focus")
        #expect(ActivityClassifier.normalizedURLKey("https://Example.com/a#x") == "https://example.com/a")
    }

    @Test("ActivityTextNormalizer ignores volatile counters, clocks, and percentages")
    func activityTextNormalizerIgnoresVolatileTitleJitter() {
        #expect(ActivityTextNormalizer.normalizedTitleKey("Inbox (3) — Gmail") == ActivityTextNormalizer.normalizedTitleKey("Inbox (9) — Gmail"))
        #expect(ActivityTextNormalizer.normalizedTitleKey("Standup 14:52") == ActivityTextNormalizer.normalizedTitleKey("Standup 09:03"))
        #expect(ActivityTextNormalizer.normalizedTitleKey("Uploading… 45%") == ActivityTextNormalizer.normalizedTitleKey("Uploading… 87%"))
        #expect(ActivityTextNormalizer.normalizedTitleKey("Alpha Spec") != ActivityTextNormalizer.normalizedTitleKey("Beta Spec"))
        #expect(ActivityTextNormalizer.isVolatileOnlyChange(previous: "Inbox (3)", current: "Inbox (9)"))
    }

    @Test("PrivacyRedactor masks credentials in free-form metadata")
    func privacyRedactorMasksCredentialsInFreeFormMetadata() {
        let masked = PrivacyRedactor.redactSecrets(in: "token: abcdef123456 password=hunter2")
        #expect(!masked.contains("abcdef123456"))
        #expect(!masked.contains("hunter2"))
        #expect(PrivacyRedactor.sanitizeMetadataValue("https://example.com/a?token=abc&page=2") == "https://example.com/a?page=2")
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
        var isAccessibilityTrusted: Bool
        var currentSample: ActivitySample
        init(sample: ActivitySample, isAccessibilityTrusted: Bool = true) {
            self.isAccessibilityTrusted = isAccessibilityTrusted
            self.currentSample = sample
        }
        func inspectCurrent() -> ActivitySample { currentSample }
    }

    private final class MockScreenCapturer: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var currentImage: CGImage
        let isScreenCaptureTrusted: Bool

        init(image: CGImage, isScreenCaptureTrusted: Bool = true) {
            self.currentImage = image
            self.isScreenCaptureTrusted = isScreenCaptureTrusted
        }

        func setImage(_ image: CGImage) {
            lock.withLock {
                currentImage = image
            }
        }

        private func readCurrentImage() -> CGImage {
            lock.withLock {
                currentImage
            }
        }

        func requestScreenCapturePermission() -> Bool {
            isScreenCaptureTrusted
        }

        func captureMainDisplayImage() async throws -> CGImage {
            readCurrentImage()
        }
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

    @Test("ActivityDatabase stores sessions, events, snapshots, OCR frames and Alma-compatible detail")
    func activityDatabaseSessionLifecycleAndAlmaCompatibility() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let e1 = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Dashboard",
            url: "https://shop.example.com/orders?token=secret123&page=2",
            data: ["bundleId": "com.google.Chrome"],
            declaredTaskId: "ecommerce",
            project: "ecommerce"
        )
        #expect(e1.url == "https://shop.example.com/orders?page=2")
        #expect(e1.windowTitle == "Example Shop Dashboard")

        let snap1 = try db.insertSnapshot(
            sessionId: e1.sessionId,
            timestampMs: t0Ms + 15_000,
            filePath: tmpDir.appendingPathComponent("snapshots/2026-11-17/snap1.jpg").path,
            width: 1280,
            height: 720,
            sizeBytes: 24_576,
            trigger: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Dashboard",
            hashHex: "0123456789abcdef",
            histogram: Array(repeating: 1.0 / 32.0, count: 32),
            diffPct: 1.0,
            declaredTaskId: "ecommerce"
        )
        _ = try db.insertOCRFrame(snapshotId: snap1.id, sessionId: e1.sessionId, text: "Order fulfillment metrics and SKU inventory review", createdAtMs: t0Ms + 15_000)

        _ = try db.insertEvent(timestampMs: t0Ms + 45_000, kind: "lock", appName: "loginwindow")
        let e3 = try db.insertEvent(timestampMs: t0Ms + 200_000, kind: "app_focus", appName: "Terminal", windowTitle: "swift test", declaredTaskId: "infra-billing")
        #expect(e3.sessionId != e1.sessionId)

        let sessions = try db.listSessions(sinceMs: t0Ms - 1000, untilMs: t0Ms + 300_000, limit: 10)
        #expect(sessions.count == 2)

        let detail = try db.getSessionDetail(sessionId: e1.sessionId)
        #expect(detail != nil)
        #expect(detail?.session.declaredTaskId == "ecommerce")
        #expect(detail?.session.eventCount == 2)
        #expect(detail?.session.snapshotCount == 1)
        #expect(detail?.ocrFrames.count == 1)

        let enc = DayHelmDateFormatting.makeEncoder()
        let dec = DayHelmDateFormatting.makeDecoder()
        let almaSess = try dec.decode(AlmaSession.self, from: enc.encode(detail!.session))
        #expect(almaSess.id == e1.sessionId)
        let almaEvt = try dec.decode(AlmaEvent.self, from: enc.encode(e1))
        #expect(almaEvt.kind == "app_focus")
    }

    @Test("ActivityDatabase searches across titles, URLs, and OCR frames and builds AgentActivityContext")
    func activityDatabaseSearchAndAgentContext() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-search-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let ev = try db.insertEvent(timestampMs: t0Ms, kind: "browser_visit", appName: "Google Chrome", windowTitle: "Hermes Semiconductor Note", url: "https://research.example.com/semiconductor-q4", declaredTaskId: "hermes")
        let snap = try db.insertSnapshot(sessionId: ev.sessionId, timestampMs: t0Ms + 5_000, filePath: tmpDir.appendingPathComponent("snap.jpg").path, width: 800, height: 600, sizeBytes: 10_000, appName: "Google Chrome", windowTitle: "Hermes Semiconductor Note")
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Quarterly wafer fab utilization reached 92% in Q4.", createdAtMs: t0Ms + 5_000)

        #expect(try db.search(keyword: "wafer fab", limit: 10).contains { $0.sourceKind == "ocr" })
        #expect(try db.search(keyword: "semiconductor-q4", limit: 10).contains { $0.sourceKind == "event" })

        let ctx = try db.queryAgentContext(sinceMs: t0Ms - 1000, untilMs: t0Ms + 60_000, maxOCRChars: 500)
        #expect(ctx.sessionCount == 1)
        #expect(ctx.ocrFrameCount == 1)
        #expect(ctx.recentWindows.contains { $0.windowTitle == "Hermes Semiconductor Note" })
        #expect(ctx.ocrHighlights.contains { $0.text.contains("wafer fab") })
    }

    @Test("ImageHistogram deduplicates identical frames and VisionOCRService recognizes CoreText CGImage text")
    func imageHistogramAndVisionOCR() async throws {
        let whiteImg = try makeSyntheticTextImage(text: "DayHelm OCR 2026", backgroundWhite: true)
        let sameImg = try makeSyntheticTextImage(text: "DayHelm OCR 2026", backgroundWhite: true)
        let darkImg = try makeSyntheticTextImage(text: "Completely Different Screen", backgroundWhite: false)

        let h1 = ImageHistogram.computeHistogram(from: whiteImg, bins: 32)
        let h2 = ImageHistogram.computeHistogram(from: sameImg, bins: 32)
        let hDark = ImageHistogram.computeHistogram(from: darkImg, bins: 32)

        #expect(h1.count == 32)
        #expect(abs(ImageHistogram.histogramDistance(from: h1, to: h2)) < 0.001)
        #expect(ImageHistogram.histogramDistance(from: h1, to: hDark) > 0.5)
        #expect(ImageHistogram.computePerceptualHashHex(from: whiteImg) == ImageHistogram.computePerceptualHashHex(from: sameImg))

        let ocr = try await VisionOCRService.recognizeText(from: whiteImg)
        #expect(ocr.text.contains("DayHelm") || ocr.text.contains("2026"))
        #expect(ocr.charCount > 0)
    }

    @Test("DayHelmCLI supports query, search, and sessions subcommands")
    func cliQuerySearchAndSessionsCommands() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-clihub-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Catalog Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(300)))

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let ev = try db.insertEvent(timestampMs: t0Ms + 60_000, kind: "app_focus", appName: "Editor", windowTitle: "Catalog Spec", url: "https://docs.example.com/catalog", declaredTaskId: "ecommerce")
        let snap = try db.insertSnapshot(sessionId: ev.sessionId, timestampMs: t0Ms + 65_000, filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/s1.jpg").path, width: 640, height: 360, sizeBytes: 4096, appName: "Editor", windowTitle: "Catalog Spec")
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Spring SKU pricing matrix", createdAtMs: t0Ms + 65_000)

        let queryJSON = DayHelmCLI.run(arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0.addingTimeInterval(300)))
        #expect(queryJSON?.exitCode == 0)
        #expect(queryJSON?.stdout.contains("Spring SKU pricing matrix") == true)

        let searchRes = DayHelmCLI.run(arguments: ["dayhelm", "search", "SKU pricing", "--limit", "5", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        #expect(searchRes?.exitCode == 0)
        #expect(searchRes?.stdout.contains("Spring SKU pricing matrix") == true)

        let detailRes = DayHelmCLI.run(arguments: ["dayhelm", "sessions", "--id", ev.sessionId, "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
        #expect(detailRes?.exitCode == 0)
        #expect(detailRes?.stdout.contains("https://docs.example.com/catalog") == true)
    }

    @Test("LocalActivityHTTPServer serves status, sessions, detail, 404, and context on 127.0.0.1")
    func localActivityHTTPServerEndpoints() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-http-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "hermes", at: t0)
        engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(120), appName: "Preview", bundleId: "com.apple.Preview", windowTitle: "Earnings Call.pdf", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let daySnap = engine.snapshot(at: t0.addingTimeInterval(120))
        try store.saveToday(daySnap)

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let ev = try db.insertEvent(timestampMs: t0Ms + 10_000, kind: "app_focus", appName: "Preview", windowTitle: "Earnings Call.pdf", declaredTaskId: "hermes")
        let snap = try db.insertSnapshot(sessionId: ev.sessionId, timestampMs: t0Ms + 12_000, filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/p1.jpg").path, width: 1024, height: 768, sizeBytes: 8192, appName: "Preview", windowTitle: "Earnings Call.pdf")
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Revenue guidance raised by 14%", createdAtMs: t0Ms + 12_000)

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(120)),
            stateProvider: { LocalActivityHTTPServer.RuntimeState(axTrusted: true, screenCaptureTrusted: true, deepRecordingEnabled: true, daySnapshot: daySnap) }
        )
        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try #require(ports.first)

        let session = URLSession(configuration: .ephemeral)
        let dec = DayHelmDateFormatting.makeDecoder()

        let (statusData, statusResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/status")!)
        #expect((statusResp as? HTTPURLResponse)?.statusCode == 200)
        #expect((try dec.decode(LocalRecorderStatusSnapshot.self, from: statusData)).source == "dayhelm")

        let (detailData, detailResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/\(ev.sessionId)")!)
        #expect((detailResp as? HTTPURLResponse)?.statusCode == 200)
        let detail = try dec.decode(RecordedSessionDetail.self, from: detailData)
        #expect(detail.session.declaredTaskId == "hermes")
        #expect(detail.events.first?.windowTitle == "Earnings Call.pdf")

        let (_, missingResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/missing")!)
        #expect((missingResp as? HTTPURLResponse)?.statusCode == 404)

        let (ctxData, ctxResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!)
        #expect((ctxResp as? HTTPURLResponse)?.statusCode == 200)
        let ctx = try dec.decode(DayHelmContextAPIResponse.self, from: ctxData)
        #expect(ctx.activeFocus?.taskId == "hermes")
        #expect(ctx.activity.ocrHighlights.contains { $0.text.contains("Revenue guidance") })
    }

    @Test("NativeScreenRecorder enforces privacy guard, deduplication, settings, and snapshot retention pruning")
    func nativeScreenRecorderPrivacyDedupAndRetentionPrune() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-rec-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: store.snapshotsDirectory, clock: ManualClock(now: t0))

        let imgA = try makeSyntheticTextImage(text: "Product Spec Alpha 2026", backgroundWhite: true)
        let imgB = try makeSyntheticTextImage(text: "Night Console View", backgroundWhite: false)

        let redacted = PrivacyRedactor.redact(ActivitySample(timestamp: t0, appName: "1Password", bundleId: "com.1password.1password", windowTitle: "Vault", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
        let savedRedacted = try await recorder.processCapturedImage(imgA, sample: redacted, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
        #expect(savedRedacted == false)

        let locked = ActivitySample(timestamp: t0.addingTimeInterval(5), appName: "loginwindow", bundleId: "com.apple.loginwindow", windowTitle: nil, url: nil, idleSeconds: 0, screenLocked: true, inputActive: false)
        let savedLocked = try await recorder.processCapturedImage(imgA, sample: locked, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
        #expect(savedLocked == false)

        let s1 = ActivitySample(timestamp: t0.addingTimeInterval(10), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved1 = try await recorder.processCapturedImage(imgA, sample: s1, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
        #expect(saved1 == true)
        let s2 = ActivitySample(timestamp: t0.addingTimeInterval(25), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved2 = try await recorder.processCapturedImage(imgA, sample: s2, trigger: "visual_change", declaredTaskId: "ecommerce", runOCR: true)
        #expect(saved2 == false)
        let s3 = ActivitySample(timestamp: t0.addingTimeInterval(40), appName: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "Console", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved3 = try await recorder.processCapturedImage(imgB, sample: s3, trigger: "visual_change", declaredTaskId: "infra-billing", runOCR: true)
        #expect(saved3 == true)

        try store.saveBudgets(sampleBudgets())
        try store.saveSettings(DayHelmSettings(deepRecordingEnabled: false, snapshotRetentionDays: 14))
        #expect(store.loadSettings().deepRecordingEnabled == false)
        #expect(TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: store.configURL).count == 4)

        let oldDir = store.snapshotsDirectory.appendingPathComponent("2026-10-01", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        let oldJPEG = oldDir.appendingPathComponent("old.jpg")
        try Data("fake".utf8).write(to: oldJPEG)
        let pruned = try db.pruneOldSnapshots(olderThanDays: 7, snapshotsRootDir: store.snapshotsDirectory, now: t0)
        #expect(pruned.deletedFiles == 1)
        #expect(!FileManager.default.fileExists(atPath: oldJPEG.path))
    }

    @Test("Full-day E2E coordinator pipeline covers focus, redaction, OCR, snooze, HTTP/CLI, and rollover")
    func fullDayE2ECoordinatorPipelineMorningToRollover() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-e2e-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate() // 2026-11-17T09:00:00+08:00
        let clock = ManualClock(now: t0)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let imgXcode1 = try makeSyntheticTextImage(text: "Xcode DayHelmEngine Pipeline", backgroundWhite: true)
        let imgTerminal = try makeSyntheticTextImage(text: "Terminal Swift Test Runner", backgroundWhite: false)
        let imgChrome = try makeSyntheticTextImage(text: "Swift Concurrency Documentation", backgroundWhite: true)
        let imgXcode2 = try makeSyntheticTextImage(text: "DayHelmChecks Main Verification", backgroundWhite: false)

        let capturer = MockScreenCapturer(image: imgXcode1, isScreenCaptureTrusted: true)
        let recorder = NativeScreenRecorder(
            database: db,
            snapshotsRootDir: store.snapshotsDirectory,
            capturer: capturer,
            clock: clock
        )
        let inspector = MockInspector(
            sample: ActivitySample(
                timestamp: t0,
                appName: "Xcode",
                bundleId: "com.apple.dt.Xcode",
                windowTitle: "DayHelmEngine.swift — focus-guard",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ),
            isAccessibilityTrusted: true
        )
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
        let coordinator = await MainActor.run {
            HybridActivityCoordinator(
                engine: engine,
                store: store,
                almaClient: nil,
                inspector: inspector,
                clock: clock,
                syntheticDemo: false,
                database: db,
                screenRecorder: recorder,
                httpServer: nil
            )
        }

        let httpServer = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: clock,
            stateProvider: { coordinator.currentRuntimeState() }
        )
        let ports = await httpServer.start(primaryPort: 0, fallbackPort: nil)
        defer { httpServer.stop() }
        let port = try #require(ports.first)

        // 09:00: User adds custom task "独立开发 · DayHelm" (target 60m, cap 90m) and starts focus
        let customTask = await MainActor.run { () -> TaskBudget in
            let created = coordinator.addTask(
                displayName: "独立开发 · DayHelm",
                colorHex: "#3B82F6",
                targetMinutes: 60,
                capMinutes: 90,
                keywords: ["xcode", "dayhelm", "swift"]
            )
            coordinator.selectTask(created.taskId, note: "Full-day E2E pipeline")
            return created
        }

        // 09:00: Xcode sample + snapshot #1 + OCR #1
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #1 + OCR #1 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 1 && coordinator.todayOCRCount >= 1 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // 09:15: Terminal sample + snapshot #2 + OCR #2
        clock.advance(by: 15 * 60)
        capturer.setImage(imgTerminal)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "swift test — focus-guard",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #2 + OCR #2 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 2 && coordinator.todayOCRCount >= 2 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // 09:30: Sensitive 1Password sample -> MUST redact and produce 0 snapshots/OCR
        clock.advance(by: 15 * 60)
        capturer.setImage(imgChrome)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "1Password",
            bundleId: "com.1password.1password",
            windowTitle: "Vault Master Password",
            url: "https://vault.1password.com/item?secret=topsecret",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await Task.sleep(nanoseconds: 80_000_000)
        let after1Pass = await MainActor.run { (coordinator.latestSample, coordinator.todaySnapshotCount) }
        #expect(after1Pass.0?.redacted == true)
        #expect(after1Pass.0?.windowTitle == nil)
        #expect(after1Pass.0?.url == nil)
        #expect(after1Pass.1 == 2)

        // 09:45: Chrome sample + snapshot #3 + OCR #3
        clock.advance(by: 15 * 60)
        capturer.setImage(imgChrome)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Swift Concurrency Docs",
            url: "https://docs.swift.org/concurrency?token=secret123&page=1",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #3 + OCR #3 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 3 && coordinator.todayOCRCount >= 3 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)

        // 10:00: Xcode sample -> reaches 60m -> targetMet alert fires + snapshot #4 + OCR #4
        clock.advance(by: 15 * 60)
        capturer.setImage(imgXcode2)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitle: "DayHelmChecks — main.swift",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await waitUntil("Snapshot #4 + OCR #4 recorded") {
            await MainActor.run { coordinator.todaySnapshotCount >= 4 && coordinator.todayOCRCount >= 4 }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        let alert1000 = await MainActor.run { coordinator.activeAlert }
        if case .quotaTargetMet(taskId: let alertedTask, _, target: 60) = alert1000?.kind {
            #expect(alertedTask == customTask.taskId)
        } else {
            Issue.record("Expected quotaTargetMet alert at 60m, got \(String(describing: alert1000))")
        }

        // 10:05: Terminal sample -> 65m cross-app total
        clock.advance(by: 5 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "git status — focus-guard",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let customProgress = await MainActor.run {
            coordinator.taskProgressList.first { $0.budget.taskId == customTask.taskId }
        }
        #expect(abs((customProgress?.focusedMinutes ?? 0) - 65.0) < 0.01)

        // 10:05 -> 10:35: Switch to "电商日常运营" (cap 30m)
        await MainActor.run {
            coordinator.selectTask("ecommerce-ops", note: "Daily support queue")
        }
        clock.advance(by: 30 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #301",
            url: "https://ops.example.com/tickets/301",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let capAlert = await MainActor.run { coordinator.activeAlert }
        if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = capAlert?.kind {
            // OK
        } else {
            Issue.record("Expected quotaCapReached for ecommerce-ops at 10:35, got \(String(describing: capAlert))")
        }

        // User snoozes 15m via coordinator.handleAlertAction
        await MainActor.run {
            coordinator.handleAlertAction(.snooze(minutes: 15, label: "+15m 收尾"))
        }
        let clearedAlert = await MainActor.run { coordinator.activeAlert }
        #expect(clearedAlert == nil)

        // 10:40 (+5m): Alert stays suppressed
        clock.advance(by: 5 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #302",
            url: "https://ops.example.com/tickets/302",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let suppressedAlert = await MainActor.run { coordinator.activeAlert }
        #expect(suppressedAlert == nil)

        // 10:51 (+11m, total 16m past snooze): Alert re-arms
        clock.advance(by: 11 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #303",
            url: "https://ops.example.com/tickets/303",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        let rearmedAlert = await MainActor.run { coordinator.activeAlert }
        if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = rearmedAlert?.kind {
            // OK
        } else {
            Issue.record("Expected quotaCapReached to re-arm after 15m snooze")
        }

        // 11:00 (+9m): Verify HTTP server + CLI return exact accumulated task minutes, sessions, window titles & OCR
        clock.advance(by: 9 * 60)
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #304",
            url: "https://ops.example.com/tickets/304",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }
        try await Task.sleep(nanoseconds: 120_000_000)

        let urlSession = URLSession(configuration: .ephemeral)
        let dec = DayHelmDateFormatting.makeDecoder()

        let (ctxData, ctxResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!)
        #expect((ctxResp as? HTTPURLResponse)?.statusCode == 200)
        let ctx = try dec.decode(DayHelmContextAPIResponse.self, from: ctxData)
        #expect(abs((ctx.budgets.first { $0.taskId == customTask.taskId }?.focusedMinutes ?? 0) - 65.0) < 0.01)
        #expect(abs((ctx.budgets.first { $0.taskId == "ecommerce-ops" }?.focusedMinutes ?? 0) - 55.0) < 0.01)
        #expect(ctx.activity.sessionCount >= 1)
        #expect(ctx.activity.recentWindows.contains { $0.windowTitle == "DayHelmEngine.swift — focus-guard" })
        #expect(ctx.activity.recentWindows.contains { $0.windowTitle == "Swift Concurrency Docs" })
        #expect(!ctx.activity.recentWindows.contains { ($0.windowTitle ?? "").contains("Vault Master Password") })
        #expect(ctx.activity.ocrHighlights.contains { $0.text.contains("Terminal") || $0.text.contains("Xcode") || $0.text.contains("Concurrency") })

        let (sessData, sessResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions")!)
        #expect((sessResp as? HTTPURLResponse)?.statusCode == 200)
        let sessJSON = String(data: sessData, encoding: .utf8) ?? ""
        #expect(sessJSON.contains(ctx.activity.sessions[0].id))

        let cliResult = DayHelmCLI.run(
            arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path],
            clock: clock
        )
        #expect(cliResult?.exitCode == 0)
        let cliOut = cliResult?.stdout ?? ""
        #expect(cliOut.contains(customTask.taskId))
        #expect(cliOut.contains("DayHelmEngine.swift — focus-guard"))
        #expect(cliOut.contains("Swift Concurrency Docs"))
        #expect(!cliOut.contains("Vault Master Password"))
        #expect(cliOut.contains("Concurrency") || cliOut.contains("Terminal") || cliOut.contains("DayHelmEngine"))

        let cliJSONObj = try JSONSerialization.jsonObject(with: Data(cliOut.utf8)) as? [String: Any]
        let cliBudgets = cliJSONObj?["budgets"] as? [[String: Any]] ?? []
        let cliCustomMinutes = cliBudgets.first { ($0["taskId"] as? String) == customTask.taskId }?["focusedMinutes"] as? Double
        #expect(abs((cliCustomMinutes ?? 0) - 65.0) < 0.01)

        // 00:05 next day (2026-11-18): Rollover archives 2026-11-17.json and resets counters to 0
        let nextDay = DayHelmDateFormatting.parseISO8601("2026-11-18T00:05:00+08:00")!
        clock.advance(by: nextDay.timeIntervalSince(clock.now()))
        inspector.currentSample = ActivitySample(
            timestamp: clock.now(),
            appName: "Finder",
            bundleId: "com.apple.finder",
            windowTitle: "Desktop",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        await MainActor.run { coordinator.pollOnce() }

        let archivedURL = store.daysDirectory.appendingPathComponent("2026-11-17.json")
        #expect(FileManager.default.fileExists(atPath: archivedURL.path))
        let archivedSnap = try store.loadDay(dateString: "2026-11-17")
        #expect(abs((archivedSnap?.budgets.first { $0.taskId == customTask.taskId }?.focusedMinutes ?? 0) - 65.0) < 0.01)

        let nextDayProgress = await MainActor.run { coordinator.taskProgressList }
        #expect(nextDayProgress.allSatisfy { $0.focusedMinutes == 0 })
        let nextSessionState = await MainActor.run { coordinator.sessionState }
        #expect(nextSessionState == .unassigned)
        #expect((try store.loadToday())?.date == "2026-11-18")
    }

    @Test("LocalActivityHTTPServer matches exact alma-time-audit JSON key and type contract")
    func almaTimeAuditContractCompatibilityE2E() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-alma-contract-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let e1 = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Orders",
            url: "https://shop.example.com/orders",
            data: ["bundleId": "com.google.Chrome", "appName": "Google Chrome"],
            declaredTaskId: "ecommerce",
            project: "ecommerce"
        )
        let snap1 = try db.insertSnapshot(
            sessionId: e1.sessionId,
            timestampMs: t0Ms + 15_000,
            filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/c1.jpg").path,
            width: 1440,
            height: 900,
            sizeBytes: 12_345,
            trigger: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Example Shop Orders",
            declaredTaskId: "ecommerce",
            project: "ecommerce"
        )
        _ = try db.insertOCRFrame(
            snapshotId: snap1.id,
            sessionId: e1.sessionId,
            text: "Order #9921 Shipped",
            createdAtMs: t0Ms + 15_000
        )
        try db.closeSession(sessionId: e1.sessionId, endedAtMs: t0Ms + 120_000)

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(120)),
            stateProvider: { LocalActivityHTTPServer.RuntimeState(axTrusted: true, screenCaptureTrusted: true, deepRecordingEnabled: true) }
        )
        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try #require(ports.first)

        let urlSession = URLSession(configuration: .ephemeral)

        let (statusData, statusResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/status")!)
        #expect((statusResp as? HTTPURLResponse)?.statusCode == 200)
        let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
        #expect(isJSONBoolean(statusJSON?["running"]))
        #expect(statusJSON?["running"] as? Bool == true)

        let sinceMs = t0Ms - 60_000
        let untilMs = t0Ms + 300_000
        let listURL = URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions?limit=2000&since=\(sinceMs)&until=\(untilMs)")!
        let (listData, listResp) = try await urlSession.data(from: listURL)
        #expect((listResp as? HTTPURLResponse)?.statusCode == 200)
        let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
        let sessions = try #require(listJSON?["sessions"] as? [[String: Any]])
        #expect(sessions.count == 1)
        let s0 = sessions[0]
        #expect(s0["id"] is String)
        #expect(isJSONInteger(s0["startedAt"]))
        #expect(isJSONInteger(s0["endedAt"]))
        #expect(isJSONInteger(s0["durationMs"]))
        #expect(s0["appNames"] is [String])
        #expect(s0["analysisStatus"] is String)
        #expect(s0["analysisTitle"] is String)
        #expect(s0["analysisDescription"] is String)
        #expect(s0["project"] is String)
        #expect(s0["highlights"] is [String])

        let detailURL = URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/\(e1.sessionId)")!
        let (detailData, detailResp) = try await urlSession.data(from: detailURL)
        #expect((detailResp as? HTTPURLResponse)?.statusCode == 200)
        let detailJSON = try JSONSerialization.jsonObject(with: detailData) as? [String: Any]
        let events = try #require(detailJSON?["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events[0]["kind"] is String)
        #expect(isJSONInteger(events[0]["timestamp"]))
        #expect(events[0]["appName"] is String)
        #expect(events[0]["data"] is [String: Any])

        let snapshots = try #require(detailJSON?["snapshots"] as? [[String: Any]])
        #expect(snapshots.count == 1)
        #expect(snapshots[0]["trigger"] is String)
        #expect(snapshots[0]["appName"] is String)
        #expect(snapshots[0]["windowTitle"] is String)
    }

    @Test("Compiled DayHelmApp binary executes CLI subcommands and returns expected exit codes")
    func subprocessBinaryCLIAndExitCodesE2E() throws {
        let appBinary = try resolveDayHelmAppExecutableURL()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-proc-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let now = Date()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: now))
        engine.startFocus(taskId: "ecommerce", note: "Subprocess CLI E2E", at: now.addingTimeInterval(-300))
        engine.ingest(ActivitySample(
            timestamp: now,
            appName: "Editor",
            bundleId: "com.example.editor",
            windowTitle: "Subprocess keyword window",
            url: "https://docs.example.com/keyword",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        ))
        try store.saveToday(engine.snapshot(at: now))

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let ev = try db.insertEvent(
            timestampMs: nowMs - 60_000,
            kind: "app_focus",
            appName: "Editor",
            windowTitle: "Subprocess keyword window",
            url: "https://docs.example.com/keyword",
            declaredTaskId: "ecommerce"
        )
        let snap = try db.insertSnapshot(
            sessionId: ev.sessionId,
            timestampMs: nowMs - 30_000,
            filePath: store.snapshotsDirectory.appendingPathComponent("snap.jpg").path,
            width: 800,
            height: 600,
            sizeBytes: 2048,
            appName: "Editor",
            windowTitle: "Subprocess keyword window"
        )
        _ = try db.insertOCRFrame(
            snapshotId: snap.id,
            sessionId: ev.sessionId,
            text: "DayHelm subprocess keyword OCR verification",
            createdAtMs: nowMs - 30_000
        )

        let helpProc = try runProcess(executableURL: appBinary, arguments: ["--help"])
        #expect(helpProc.exitCode == 0)
        #expect(helpProc.stdout.contains("Usage:") && helpProc.stdout.contains("dayhelm"))

        let statusProc = try runProcess(executableURL: appBinary, arguments: ["status", "--store-dir", tmpDir.path])
        #expect(statusProc.exitCode == 0)
        #expect(statusProc.stdout.contains("DayHelm Status") && statusProc.stdout.contains("电商做深"))

        let queryProc = try runProcess(executableURL: appBinary, arguments: ["query", "--today", "--format", "md", "--store-dir", tmpDir.path])
        #expect(queryProc.exitCode == 0)
        #expect(queryProc.stdout.contains("# DayHelm Activity Context") && queryProc.stdout.contains("keyword"))

        let searchProc = try runProcess(executableURL: appBinary, arguments: ["search", "keyword", "--store-dir", tmpDir.path])
        #expect(searchProc.exitCode == 0)
        #expect(searchProc.stdout.contains("# DayHelm Search") && searchProc.stdout.contains("keyword"))

        let purgeProc = try runProcess(executableURL: appBinary, arguments: ["purge", "--store-dir", tmpDir.path])
        #expect(purgeProc.exitCode == 0)
        #expect(purgeProc.stdout.contains("DayHelm purge completed"))
        #expect(!FileManager.default.fileExists(atPath: store.todayURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.databaseURL.path))

        let unknownProc = try runProcess(executableURL: appBinary, arguments: ["unknown-flag"])
        #expect(unknownProc.exitCode != 0)
        #expect(!unknownProc.stderr.isEmpty)
    }

    @Test("ActivityDatabase handles concurrent writers and HTTP/CLI readers in WAL mode without SQLITE_BUSY")
    func concurrentSQLiteReaderWriterStressWALModeE2E() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-stress-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        let daySnap = engine.snapshot(at: t0.addingTimeInterval(600))
        try store.saveToday(daySnap)

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        #expect(try db.journalMode().lowercased() == "wal")

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(600)),
            stateProvider: {
                LocalActivityHTTPServer.RuntimeState(
                    axTrusted: true,
                    screenCaptureTrusted: true,
                    deepRecordingEnabled: true,
                    daySnapshot: daySnap
                )
            }
        )
        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try #require(ports.first)

        let contextURL = URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!
        let urlSession = URLSession(configuration: .ephemeral)
        let dec = DayHelmDateFormatting.makeDecoder()

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<50 {
                    _ = try db.insertEvent(
                        timestampMs: t0Ms + Int64(i * 2000),
                        kind: i % 5 == 0 ? "browser_visit" : "app_focus",
                        appName: i % 2 == 0 ? "Xcode" : "Terminal",
                        windowTitle: "StressWindow-\(i)",
                        url: i % 5 == 0 ? "https://example.com/stress/\(i)" : nil,
                        declaredTaskId: "ecommerce"
                    )
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
            }

            group.addTask {
                for i in 0..<25 {
                    let snap = try db.insertSnapshot(
                        timestampMs: t0Ms + Int64(i * 4000) + 500,
                        filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/stress-\(i).jpg").path,
                        width: 1280,
                        height: 720,
                        sizeBytes: 4096,
                        trigger: "visual_change",
                        appName: "Xcode",
                        windowTitle: "StressWindow-\(i)",
                        declaredTaskId: "ecommerce"
                    )
                    _ = try db.insertOCRFrame(
                        snapshotId: snap.id,
                        sessionId: snap.sessionId,
                        text: "StressOCR frame payload \(i)",
                        createdAtMs: t0Ms + Int64(i * 4000) + 500
                    )
                    try await Task.sleep(nanoseconds: 3_000_000)
                }
            }

            group.addTask {
                for _ in 0..<25 {
                    let (data, resp) = try await urlSession.data(from: contextURL)
                    #expect((resp as? HTTPURLResponse)?.statusCode == 200)
                    _ = try dec.decode(DayHelmContextAPIResponse.self, from: data)
                    try await Task.sleep(nanoseconds: 3_000_000)
                }
            }

            group.addTask {
                for _ in 0..<15 {
                    let res = DayHelmCLI.run(
                        arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path],
                        clock: ManualClock(now: t0.addingTimeInterval(600))
                    )
                    #expect(res?.exitCode == 0)
                    try await Task.sleep(nanoseconds: 4_000_000)
                }
            }

            try await group.waitForAll()
        }

        let counts = try db.todayCounts(dayStartMs: t0Ms - 1000, dayEndMs: t0Ms + 86_400_000)
        #expect(counts.events == 50)
        #expect(counts.snapshots == 25)
        #expect(counts.ocrFrames == 25)
        #expect(try db.integrityCheck().lowercased() == "ok")
        #expect((try db.search(keyword: "StressOCR", limit: 50)).count == 25)
    }

    private func waitUntil(
        _ description: String,
        timeoutSeconds: TimeInterval = 8.0,
        condition: @escaping @Sendable () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        throw NSError(domain: "DayHelmCoreTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for: \(description)"])
    }

    private func isJSONBoolean(_ value: Any?) -> Bool {
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) == CFBooleanGetTypeID()
    }

    private func isJSONInteger(_ value: Any?) -> Bool {
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) != CFBooleanGetTypeID()
    }

    private func resolveDayHelmAppExecutableURL() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []

        for bundle in Bundle.allBundles {
            candidates.append(bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("DayHelmApp"))
        }
        if let mainExecDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(mainExecDir.appendingPathComponent("DayHelmApp"))
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
        var repoRoot = sourceURL.deletingLastPathComponent()
        while repoRoot.path != "/" {
            if fm.fileExists(atPath: repoRoot.appendingPathComponent("Package.swift").path) {
                break
            }
            repoRoot = repoRoot.deletingLastPathComponent()
        }

        candidates.append(repoRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/DayHelmApp"))
        candidates.append(repoRoot.appendingPathComponent(".build/debug/DayHelmApp"))
        candidates.append(repoRoot.appendingPathComponent(".build/release/DayHelmApp"))

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }

        let buildProc = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build", "--product", "DayHelmApp"],
            currentDirectoryURL: repoRoot,
            timeoutSeconds: 60.0
        )
        guard buildProc.exitCode == 0 else {
            throw NSError(domain: "DayHelmCoreTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to build DayHelmApp: \(buildProc.stderr)"])
        }

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        throw NSError(domain: "DayHelmCoreTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to locate compiled DayHelmApp executable"])
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil,
        timeoutSeconds: TimeInterval = 15.0
    ) throws -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let doneSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            doneSemaphore.signal()
        }

        try process.run()
        let waitResult = doneSemaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            throw NSError(domain: "DayHelmCoreTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Process timed out"])
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private func makeSyntheticTextImage(text: String, backgroundWhite: Bool, width: Int = 960, height: Int = 240) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        ctx.setFillColor(red: backgroundWhite ? 1 : 0.08, green: backgroundWhite ? 1 : 0.09, blue: backgroundWhite ? 1 : 0.12, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let fgColor = backgroundWhite ? CGColor(red: 0, green: 0, blue: 0, alpha: 1) : CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 1)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: fgColor]
        let attrString = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        ctx.textPosition = CGPoint(x: 40, y: 95)
        CTLineDraw(line, ctx)
        return try #require(ctx.makeImage())
    }
}

@Suite("DayHelm Alma compatibility surface (ADR 007)")
struct DayHelmAlmaCompatTests {

    private func baseDate() -> Date {
        DayHelmDateFormatting.parseISO8601("2026-11-17T09:00:00+08:00")!
    }

    private func sampleBudgets() -> [TaskBudget] {
        [
            TaskBudget(taskId: "ecommerce", displayName: "电商做深", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["example-shop"]),
            TaskBudget(taskId: "hermes", displayName: "Hermes 投研", colorHex: "#10B981", targetMinutes: 45, capMinutes: 60, keywords: ["hermes"])
        ]
    }

    @Test("Session summaries expose click/keypress counts and derived input density")
    func sessionSummaryExposesInputDensity() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-density-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        let focus = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Orders",
            declaredTaskId: "ecommerce"
        )
        for i in 0..<3 {
            _ = try db.insertEvent(timestampMs: t0Ms + Int64(i * 5_000) + 1_000, kind: "click", appName: "Google Chrome")
        }
        for i in 0..<2 {
            _ = try db.insertEvent(timestampMs: t0Ms + 30_000 + Int64(i * 2_000), kind: "keypress", appName: "Google Chrome")
        }
        try db.closeSession(sessionId: focus.sessionId, endedAtMs: t0Ms + 60_000)

        let summary = try #require(try db.getSessionDetail(sessionId: focus.sessionId)?.session)
        #expect(summary.clickCount == 3)
        #expect(summary.keypressCount == 2)
        #expect(summary.eventCount == 6)
        #expect(abs(summary.inputEventsPerMinute - 5.0) < 0.0001)

        let listed = try #require(try db.listSessions(sinceMs: t0Ms - 1_000, untilMs: t0Ms + 120_000, limit: 5).first)
        #expect(listed.clickCount == 3)
        #expect(listed.keypressCount == 2)

        let dayTotals = try db.dayInputTotals(dayStartMs: t0Ms, dayEndMs: t0Ms + 86_400_000 - 1)
        #expect(dayTotals.clickCount == 3)
        #expect(dayTotals.keypressCount == 2)
        #expect(abs(dayTotals.inputEventsPerMinute - 5.0) < 0.0001)
    }

    @Test("Opening an older activity.sqlite adds click/keypress columns without losing sessions")
    func oldDatabaseMigratesInputDensityColumns() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let databaseURL = tmpDir.appendingPathComponent("activity.sqlite")

        let legacySchema = """
        CREATE TABLE activity_sessions (
            id TEXT PRIMARY KEY,
            started_at INTEGER NOT NULL,
            ended_at INTEGER,
            duration_ms INTEGER,
            trigger_kind TEXT NOT NULL DEFAULT 'idle',
            app_names TEXT NOT NULL DEFAULT '[]',
            event_count INTEGER NOT NULL DEFAULT 0,
            snapshot_count INTEGER NOT NULL DEFAULT 0,
            total_bytes INTEGER NOT NULL DEFAULT 0,
            analysis_status TEXT NOT NULL DEFAULT 'pending',
            analysis_title TEXT,
            analysis_description TEXT,
            analysis_model TEXT,
            analysis_error TEXT,
            analyzed_at INTEGER,
            worth_memory INTEGER NOT NULL DEFAULT 0,
            worth_knowledge INTEGER NOT NULL DEFAULT 0,
            is_meeting INTEGER NOT NULL DEFAULT 0,
            storage_tier TEXT NOT NULL DEFAULT 'hot',
            entities TEXT NOT NULL DEFAULT '{}',
            topics TEXT NOT NULL DEFAULT '[]',
            project TEXT,
            highlights TEXT NOT NULL DEFAULT '[]',
            declared_task_id TEXT,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
        INSERT INTO activity_sessions (id, started_at, duration_ms, app_names, event_count, created_at, updated_at)
        VALUES ('sess_legacy', 1763337600000, 60000, '["Editor"]', 1, 1763337600000, 1763337660000);
        """
        try execRawSQL(legacySchema, at: databaseURL)

        let db = try ActivityDatabase(databaseURL: databaseURL)
        let legacy = try #require(try db.getSessionDetail(sessionId: "sess_legacy")?.session)
        #expect(legacy.clickCount == 0)
        #expect(legacy.keypressCount == 0)

        let t0Ms: Int64 = 1_763_337_660_000
        _ = try db.insertEvent(sessionId: "sess_legacy", timestampMs: t0Ms, kind: "click", appName: "Editor")
        _ = try db.insertEvent(sessionId: "sess_legacy", timestampMs: t0Ms + 1_000, kind: "keypress", appName: "Editor")
        let migrated = try #require(try db.getSessionDetail(sessionId: "sess_legacy")?.session)
        #expect(migrated.clickCount == 1)
        #expect(migrated.keypressCount == 1)
        #expect(migrated.eventCount == 2)
    }

    @Test("HTTP snapshot-file serves only files inside the snapshots directory")
    func httpSnapshotFileServesOnlyStoredSnapshots() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-snapfile-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let snapshotDir = store.snapshotsDirectory.appendingPathComponent("2026-11-17", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotDir, withIntermediateDirectories: true)
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0xFF, 0xD9])
        let storedFile = snapshotDir.appendingPathComponent("frame-1.jpg")
        try jpegBytes.write(to: storedFile)
        let outsideFile = tmpDir.appendingPathComponent("outside.jpg")
        try jpegBytes.write(to: outsideFile)

        let event = try db.insertEvent(timestampMs: t0Ms, kind: "app_focus", appName: "Google Chrome", windowTitle: "Orders")
        let snap = try db.insertSnapshot(
            sessionId: event.sessionId,
            timestampMs: t0Ms + 1_000,
            filePath: storedFile.path,
            width: 4,
            height: 4,
            sizeBytes: Int64(jpegBytes.count),
            trigger: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Orders"
        )

        let server = LocalActivityHTTPServer(database: db, store: store, clock: ManualClock(now: t0))
        let ports = await server.start(primaryPort: 0, fallbackPort: nil)
        defer { server.stop() }
        let port = try #require(ports.first)
        let urlSession = URLSession(configuration: .ephemeral)

        func get(_ query: String) async throws -> (Data, HTTPURLResponse) {
            var components = URLComponents(string: "http://127.0.0.1:\(port)/api/activity-recorder/snapshot-file")!
            components.query = query.isEmpty ? nil : query
            let (data, response) = try await urlSession.data(from: components.url!)
            return (data, try #require(response as? HTTPURLResponse))
        }

        let byPath = try await get("path=\(storedFile.path)")
        #expect(byPath.1.statusCode == 200)
        #expect(byPath.1.value(forHTTPHeaderField: "Content-Type")?.contains("image/jpeg") == true)
        #expect(byPath.0 == jpegBytes)

        let byId = try await get("id=\(snap.id)")
        #expect(byId.1.statusCode == 200)
        #expect(byId.0 == jpegBytes)

        let escaped = try await get("path=\(outsideFile.path)")
        #expect(escaped.1.statusCode == 403)

        let missing = try await get("path=\(snapshotDir.appendingPathComponent("missing.jpg").path)")
        #expect(missing.1.statusCode == 404)

        let noParam = try await get("")
        #expect(noParam.1.statusCode == 400)
    }

    @Test("HTTP OCR keyword search, ocr alias, and daily/weekly summaries match the Alma contract")
    func httpAlmaSearchOCRAndSummaryContract() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-almasum-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let event = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "browser_visit",
            appName: "Google Chrome",
            windowTitle: "Wafer Fab Report",
            url: "https://research.example.com/wafer",
            declaredTaskId: "hermes",
            project: "hermes"
        )
        _ = try db.insertEvent(timestampMs: t0Ms + 20_000, kind: "click", appName: "Google Chrome")
        _ = try db.insertEvent(timestampMs: t0Ms + 25_000, kind: "keypress", appName: "Google Chrome")
        let snap = try db.insertSnapshot(
            sessionId: event.sessionId,
            timestampMs: t0Ms + 5_000,
            filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/wafer.jpg").path,
            width: 100,
            height: 60,
            sizeBytes: 4_096,
            trigger: "browser_visit",
            appName: "Google Chrome",
            windowTitle: "Wafer Fab Report"
        )
        _ = try db.insertOCRFrame(
            snapshotId: snap.id,
            sessionId: event.sessionId,
            text: "Wafer fab utilization reached 92% in Q4",
            createdAtMs: t0Ms + 5_000
        )
        try db.closeSession(sessionId: event.sessionId, endedAtMs: t0Ms + 120_000)

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(600))
        )

        let detail = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/sessions/\(event.sessionId)")
        #expect(detail.statusCode == 200)
        let detailJSON = try #require(try JSONSerialization.jsonObject(with: detail.body) as? [String: Any])
        let ocrAlias = try #require(detailJSON["ocr"] as? [[String: Any]])
        let ocrFrames = try #require(detailJSON["ocrFrames"] as? [[String: Any]])
        #expect(ocrAlias.count == 1)
        #expect(ocrFrames.count == 1)
        #expect(ocrAlias[0]["snapshotId"] as? String == snap.id)
        #expect(ocrAlias[0]["hasEmbedding"] as? Bool == false)
        let sessionJSON = try #require(detailJSON["session"] as? [String: Any])
        #expect(sessionJSON["clickCount"] as? Int == 1)
        #expect(sessionJSON["keypressCount"] as? Int == 1)

        let search = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/search/keyword?q=wafer&limit=10")
        #expect(search.statusCode == 200)
        let searchJSON = try #require(try JSONSerialization.jsonObject(with: search.body) as? [String: Any])
        let results = try #require(searchJSON["results"] as? [[String: Any]])
        #expect(results.count == 1)
        #expect(results[0]["snapshotId"] as? String == snap.id)
        #expect((results[0]["text"] as? String)?.contains("Wafer fab") == true)

        let emptySearch = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/search/keyword?q=")
        let emptyJSON = try #require(try JSONSerialization.jsonObject(with: emptySearch.body) as? [String: Any])
        #expect((emptyJSON["results"] as? [[String: Any]])?.isEmpty == true)

        let richSearch = server.handleRawHTTPRequestLineAndRoute(target: "/api/dayhelm/search?q=wafer&limit=10")
        #expect(richSearch.statusCode == 200)
        let richJSON = try #require(try JSONSerialization.jsonObject(with: richSearch.body) as? [String: Any])
        let hits = try #require(richJSON["hits"] as? [[String: Any]])
        #expect(hits.contains { $0["sourceKind"] as? String == "ocr" })
        #expect(hits.contains { $0["sourceKind"] as? String == "event" })

        let daily = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/summary/daily/2026-11-17")
        #expect(daily.statusCode == 200)
        let dailyJSON = try #require(try JSONSerialization.jsonObject(with: daily.body) as? [String: Any])
        #expect(dailyJSON["kind"] as? String == "daily")
        #expect(dailyJSON["dateKey"] as? String == "2026-11-17")
        #expect(dailyJSON["summary"] is NSNull)
        #expect(dailyJSON["isPartial"] as? Bool == true)
        let dailyStats = try #require(dailyJSON["stats"] as? [String: Any])
        #expect(dailyStats["sessionCount"] as? Int == 1)
        #expect(dailyStats["totalActiveMs"] as? Int == 120_000)
        #expect(dailyStats["clickCount"] as? Int == 1)
        #expect(dailyStats["keypressCount"] as? Int == 1)
        let apps = try #require(dailyStats["apps"] as? [[String: Any]])
        #expect(apps.contains { $0["app"] as? String == "Google Chrome" })
        #expect((dailyStats["hours"] as? [[String: Any]])?.count == 24)
        let keyMoments = try #require(dailyStats["keyMoments"] as? [[String: Any]])
        #expect(keyMoments.first?["sessionId"] as? String == event.sessionId)

        let weekly = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/summary/weekly/2026-11-17")
        #expect(weekly.statusCode == 200)
        let weeklyJSON = try #require(try JSONSerialization.jsonObject(with: weekly.body) as? [String: Any])
        #expect(weeklyJSON["kind"] as? String == "weekly")
        let weeklyStats = try #require(weeklyJSON["stats"] as? [String: Any])
        #expect(weeklyStats["weekKey"] as? String == "2026-W47")
        #expect(weeklyStats["startDate"] as? String == "2026-11-16")
        #expect(weeklyStats["endDate"] as? String == "2026-11-22")
        #expect((weeklyStats["daily"] as? [[String: Any]])?.count == 7)

        let invalidWeek = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/summary/weekly/not-a-week")
        #expect(invalidWeek.statusCode == 400)
    }

    @Test("DayHelmCLI status --format json emits recorder density counters")
    func cliStatusJSONIncludesRecorderDensity() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-st-statusjson-\(UUID().uuidString)")
        let store = DayHelmStore(directory: tmpDir)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
        engine.startFocus(taskId: "ecommerce", at: t0)
        try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(600)))

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let event = try db.insertEvent(timestampMs: t0Ms, kind: "app_focus", appName: "Google Chrome", declaredTaskId: "ecommerce")
        _ = try db.insertEvent(sessionId: event.sessionId, timestampMs: t0Ms + 10_000, kind: "click", appName: "Google Chrome")
        _ = try db.insertEvent(sessionId: event.sessionId, timestampMs: t0Ms + 20_000, kind: "click", appName: "Google Chrome")
        _ = try db.insertEvent(sessionId: event.sessionId, timestampMs: t0Ms + 30_000, kind: "keypress", appName: "Google Chrome")
        try db.closeSession(sessionId: event.sessionId, endedAtMs: t0Ms + 60_000)

        let clock = ManualClock(now: t0.addingTimeInterval(600))
        let jsonResult = DayHelmCLI.run(arguments: ["dayhelm", "status", "--format", "json", "--store-dir", tmpDir.path], clock: clock)
        let result = try #require(jsonResult)
        #expect(result.exitCode == 0)
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        #expect(payload["schemaVersion"] as? Int == 1)
        #expect(payload["date"] as? String == "2026-11-17")
        #expect(payload["activeTaskId"] as? String == "ecommerce")
        #expect((payload["budgets"] as? [[String: Any]])?.count == sampleBudgets().count)
        let recorder = try #require(payload["recorder"] as? [String: Any])
        #expect(recorder["clickCount"] as? Int == 2)
        #expect(recorder["keypressCount"] as? Int == 1)
        #expect(recorder["events"] as? Int == 4)

        let aliasResult = DayHelmCLI.run(arguments: ["dayhelm", "status", "--json", "--store-dir", tmpDir.path], clock: clock)
        #expect(aliasResult?.exitCode == 0)
        #expect(aliasResult?.stdout.contains("\"recorder\"") == true)

        let mdResult = DayHelmCLI.run(arguments: ["dayhelm", "status", "--store-dir", tmpDir.path], clock: clock)
        #expect(mdResult?.exitCode == 0)
        #expect(mdResult?.stdout.contains("DayHelm Status") == true)
    }

    private func execRawSQL(_ sql: String, at url: URL) throws {
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw NSError(domain: "DayHelmAlmaCompatTests", code: 9, userInfo: [NSLocalizedDescriptionKey: "Failed to open sqlite file"])
        }
        defer { sqlite3_close(handle) }
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &errMsg) != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? "unknown sqlite error"
            if let errMsg { sqlite3_free(errMsg) }
            throw NSError(domain: "DayHelmAlmaCompatTests", code: 10, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

@Suite("DayHelm Alma Parity & Capture Upgrades (ADR 008)")
struct DayHelmAlmaParityTests {

    private func baseDate() -> Date {
        DayHelmDateFormatting.parseISO8601("2026-11-17T09:00:00+08:00")!
    }

    @Test("ActivityClassifier supports Dia & Safari Technology Preview without Obsidian false-positive")
    func browserClassificationExtendedAndExactDia() {
        #expect(ActivityClassifier.isBrowser(appName: "Dia", bundleId: "company.thebrowser.dia"))
        #expect(ActivityClassifier.isBrowser(appName: "Dia", bundleId: "com.thebrowser.dia"))
        #expect(ActivityClassifier.isBrowser(appName: "Dia", bundleId: nil))
        #expect(ActivityClassifier.isBrowser(appName: "Safari Technology Preview", bundleId: "com.apple.safaritechnologypreview"))
        #expect(!ActivityClassifier.isBrowser(appName: "Obsidian", bundleId: "md.obsidian"))
        #expect(!ActivityClassifier.isBrowser(appName: "Diagram", bundleId: nil))
    }

    @Test("Browser AppleScript fallback respects PrivacyRedactor, builds valid scripts, and circuit-breaks errors")
    func browserAppleScriptFallbackAndCircuitBreaker() {
        let chromeScript = BrowserTabScriptRouter.appleScriptSource(appName: "Google Chrome", bundleId: "com.google.Chrome")
        #expect(chromeScript?.contains("URL of active tab of front window") == true)
        #expect(chromeScript?.contains("with timeout of 1 seconds") == true)

        let safariScript = BrowserTabScriptRouter.appleScriptSource(appName: "Safari Technology Preview", bundleId: "com.apple.safaritechnologypreview")
        #expect(safariScript?.contains("URL of front document") == true)
        #expect(BrowserTabScriptRouter.appleScriptSource(appName: "Terminal", bundleId: "com.apple.Terminal") == nil)

        let parsed = BrowserTabScriptRouter.parseScriptOutput("https://github.com/acme/dayhelm\nAcme Pull Request")
        #expect(parsed?.url == "https://github.com/acme/dayhelm")
        #expect(parsed?.title == "Acme Pull Request")

        // Privacy guard must block AppleScript call completely when sample is already sensitive or locked
        var scriptInvoked = 0
        let blocked = AXWindowInspector.resolveBrowserFallbackIfNeeded(
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            existingTitle: "Acme Bank Account",
            existingURL: nil,
            screenLocked: false,
            privacyConfig: .default
        ) { _, _ in
            scriptInvoked += 1
            return ("https://bank.example.com", "Secret")
        }
        #expect(scriptInvoked == 0)
        #expect(blocked.url == nil)

        let filled = AXWindowInspector.resolveBrowserFallbackIfNeeded(
            appName: "Dia",
            bundleId: "company.thebrowser.dia",
            existingTitle: nil,
            existingURL: nil,
            screenLocked: false,
            privacyConfig: .default
        ) { _, _ in
            scriptInvoked += 1
            return ("https://example.com/docs", "Docs Home")
        }
        #expect(scriptInvoked == 1)
        #expect(filled.url == "https://example.com/docs")
        #expect(filled.title == "Docs Home")

        // Circuit breaker: -1743 immediately opens 300s cooldown; 3 generic failures open cooldown
        let clock = ManualClock(now: baseDate())
        let breaker = BrowserAppleScriptCircuitBreaker(clock: clock, cooldownSeconds: 300, maxConsecutiveFailures: 3)
        #expect(breaker.shouldAllow(key: "com.google.Chrome"))
        breaker.recordFailure(key: "com.google.Chrome", errorCode: -1743)
        #expect(!breaker.shouldAllow(key: "com.google.Chrome"))
        clock.advance(by: 301)
        #expect(breaker.shouldAllow(key: "com.google.Chrome"))

        breaker.recordFailure(key: "company.thebrowser.dia", errorCode: -1)
        breaker.recordFailure(key: "company.thebrowser.dia", errorCode: -1)
        #expect(breaker.shouldAllow(key: "company.thebrowser.dia"))
        breaker.recordFailure(key: "company.thebrowser.dia", errorCode: -1)
        #expect(!breaker.shouldAllow(key: "company.thebrowser.dia"))
        clock.advance(by: 301)
        breaker.recordSuccess(key: "company.thebrowser.dia")
        #expect(breaker.shouldAllow(key: "company.thebrowser.dia"))
    }

    @Test("NativeEventMonitor aggregates input counts without drops and ActivityDatabase sums data.count")
    func inputEventAggregationAndDatabaseCount() throws {
        final class EventCollector: @unchecked Sendable {
            private let lock = NSLock()
            private var events: [NativeMonitorEvent] = []
            func append(_ event: NativeMonitorEvent) {
                lock.withLock { events.append(event) }
            }
            func drain() -> [NativeMonitorEvent] {
                lock.withLock {
                    let copy = events
                    events.removeAll()
                    return copy
                }
            }
        }
        let clock = ManualClock(now: baseDate())
        let collector = EventCollector()

        let monitor = NativeEventMonitor(clock: clock) { event in
            collector.append(event)
        }
        for _ in 0..<10 { monitor.recordMouseClick(at: clock.now()) }
        for _ in 0..<5 { monitor.recordKeyPress(at: clock.now()) }
        monitor.flushPendingInput(at: clock.now())

        let firstBatch = collector.drain()

        let clicks = firstBatch.filter { $0.kind == "click" }
        let keypresses = firstBatch.filter { $0.kind == "keypress" }
        #expect(clicks.reduce(0) { $0 + $1.count } == 10)
        #expect(keypresses.reduce(0) { $0 + $1.count } == 5)

        // Batch threshold at 40 triggers automatic flush
        for _ in 0..<40 { monitor.recordKeyPress(at: clock.now()) }
        let autoFlushed = collector.drain()
        #expect(autoFlushed.contains { $0.kind == "keypress" && $0.count == 40 })

        // Database aggregates data.count and defaults legacy empty data to 1
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-agg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0Ms = Int64(baseDate().timeIntervalSince1970 * 1000)

        let e1 = try db.insertEvent(timestampMs: t0Ms, kind: "click", appName: "Xcode", data: ["count": "12"])
        _ = try db.insertEvent(sessionId: e1.sessionId, timestampMs: t0Ms + 2_000, kind: "click", appName: "Xcode")
        _ = try db.insertEvent(sessionId: e1.sessionId, timestampMs: t0Ms + 5_000, kind: "keypress", appName: "Xcode", data: ["count": "25"])
        try db.closeSession(sessionId: e1.sessionId, endedAtMs: t0Ms + 60_000)

        let summary = try #require(try db.getSessionDetail(sessionId: e1.sessionId)?.session)
        #expect(summary.clickCount == 13)
        #expect(summary.keypressCount == 25)
        #expect(summary.eventCount == 3)

        let totals = try db.dayInputTotals(dayStartMs: t0Ms, dayEndMs: t0Ms + 86_400_000 - 1)
        #expect(totals.clickCount == 13)
        #expect(totals.keypressCount == 25)
    }

    @Test("Idle >= 30s suppresses keepalive heartbeat events and startup finalizes stale open sessions")
    @MainActor
    func idleHeartbeatNonPollutionAndStartupCleanup() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-idle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let store = DayHelmStore(directory: tmpDir)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        // Simulate leftover open session from a prior crash
        let stale = try db.insertEvent(timestampMs: t0Ms - 600_000, kind: "app_focus", appName: "Terminal", windowTitle: "Old Run")
        #expect(try db.currentOpenSessionId() == stale.sessionId)
        let closedCount = try db.finalizeStaleOpenSessionsOnStartup()
        #expect(closedCount == 1)
        #expect(try db.currentOpenSessionId() == nil)
        let staleClosed = try #require(try db.getSessionDetail(sessionId: stale.sessionId)?.session)
        #expect(staleClosed.endedAt == t0Ms - 600_000)

        // Now verify coordinator does NOT emit 30s keepalive heartbeat while idle >= 30s
        final class ScriptedInspector: ActivityInspecting, @unchecked Sendable {
            private let lock = NSLock()
            private var currentSample: ActivitySample
            init(sample: ActivitySample) { self.currentSample = sample }
            var isAccessibilityTrusted: Bool { true }
            func set(_ s: ActivitySample) { lock.lock(); currentSample = s; lock.unlock() }
            func inspectCurrent() -> ActivitySample { lock.lock(); defer { lock.unlock() }; return currentSample }
        }

        let clock = ManualClock(now: t0)
        let inspector = ScriptedInspector(sample: ActivitySample(
            timestamp: t0, appName: "Xcode", bundleId: "com.apple.dt.Xcode",
            windowTitle: "Editor", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true
        ))
        let engine = DayHelmEngine(budgets: [], clock: clock)
        let coord = HybridActivityCoordinator(
            engine: engine, store: store, almaClient: nil, inspector: inspector,
            clock: clock, syntheticDemo: false, database: db
        )

        coord.pollOnce() // active at t0
        let activeSessionId = try #require(try db.currentOpenSessionId())

        clock.advance(by: 45)
        inspector.set(ActivitySample(
            timestamp: clock.now(), appName: "Xcode", bundleId: "com.apple.dt.Xcode",
            windowTitle: "Editor", url: nil, idleSeconds: 45, screenLocked: false, inputActive: false
        ))
        coord.pollOnce() // idle=45s (>=30s), same window: must NOT emit heartbeat!

        clock.advance(by: 260) // total 305s
        inspector.set(ActivitySample(
            timestamp: clock.now(), appName: "Xcode", bundleId: "com.apple.dt.Xcode",
            windowTitle: "Editor", url: nil, idleSeconds: 305, screenLocked: false, inputActive: false
        ))
        coord.pollOnce()

        let closed = try #require(try db.getSessionDetail(sessionId: activeSessionId))
        #expect(closed.events.count == 1)
        #expect(closed.session.endedAt == t0Ms)
        #expect(closed.session.durationMs == 0)

        // Verify will_sleep closes open session
        clock.advance(by: 600)
        inspector.set(ActivitySample(
            timestamp: clock.now(), appName: "Notes", bundleId: "com.apple.Notes",
            windowTitle: "Draft", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true
        ))
        coord.pollOnce()
        #expect(try db.currentOpenSessionId() != nil)
        coord.handleMonitorEventForTesting(NativeMonitorEvent(timestamp: clock.now().addingTimeInterval(5), kind: "will_sleep"))
        #expect(try db.currentOpenSessionId() == nil)
    }

    @Test("ActivityDatabase updates counters incrementally in O(1) and throttles summary synthesis to 30s")
    func incrementalCountersAndThrottledSummary() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-o1-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0Ms = Int64(baseDate().timeIntervalSince1970 * 1000)

        let first = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "app_focus",
            appName: "Xcode",
            windowTitle: "First File",
            declaredTaskId: "alma"
        )
        let firstDetail = try #require(try db.getSessionDetail(sessionId: first.sessionId))
        let initialAnalyzedAt = firstDetail.session.analyzedAt

        // Next 20 events within < 30s should update counters in O(1) and NOT re-run summary synthesis
        for i in 1...20 {
            let kind = (i % 2 == 0) ? "click" : "keypress"
            _ = try db.insertEvent(
                sessionId: first.sessionId,
                timestampMs: t0Ms + Int64(i * 1_000),
                kind: kind,
                appName: i == 10 ? "Terminal" : "Xcode",
                data: ["count": "2"]
            )
        }
        #expect(db.fullCounterResyncCount == 0)

        let midDetail = try #require(try db.getSessionDetail(sessionId: first.sessionId))
        #expect(midDetail.session.eventCount == 21)
        #expect(midDetail.session.clickCount == 20)
        #expect(midDetail.session.keypressCount == 20)
        #expect(midDetail.session.appNames == ["Xcode", "Terminal"])
        #expect(midDetail.session.analyzedAt == initialAnalyzedAt)

        // Event >= 30s later triggers summary synthesis refresh
        _ = try db.insertEvent(
            sessionId: first.sessionId,
            timestampMs: t0Ms + 35_000,
            kind: "app_focus",
            appName: "Terminal",
            windowTitle: "Build Log"
        )
        let refreshed = try #require(try db.getSessionDetail(sessionId: first.sessionId))
        #expect(refreshed.session.analyzedAt == t0Ms + 35_000)
        #expect(db.fullCounterResyncCount == 0)
    }

    @Test("Pixel diff catches same-histogram shifts, probe skips full capture when unchanged, and priority queue drains")
    func pixelDiffProbeQueueAndDisplayGeometry() async throws {
        // Two 50% white / 50% black checkerboard images with opposite halves -> same 32-bin histogram, 100% pixel diff!
        func halfSplitImage(leftWhite: Bool) throws -> CGImage {
            let w = 160, h = 90
            guard let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw ScreenCaptureError.noDisplayAvailable
            }
            ctx.setFillColor(red: leftWhite ? 1 : 0, green: leftWhite ? 1 : 0, blue: leftWhite ? 1 : 0, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w / 2, height: h))
            ctx.setFillColor(red: leftWhite ? 0 : 1, green: leftWhite ? 0 : 1, blue: leftWhite ? 0 : 1, alpha: 1)
            ctx.fill(CGRect(x: w / 2, y: 0, width: w / 2, height: h))
            guard let img = ctx.makeImage() else {
                throw ScreenCaptureError.noDisplayAvailable
            }
            return img
        }

        let imgLeft = try halfSplitImage(leftWhite: true)
        let imgRight = try halfSplitImage(leftWhite: false)
        let hLeft = ImageHistogram.computeHistogram(from: imgLeft)
        let hRight = ImageHistogram.computeHistogram(from: imgRight)
        #expect(ImageHistogram.histogramDistance(from: hLeft, to: hRight) < 0.001)

        let thumbL = ImageHistogram.computeThumbnailRGB(from: imgLeft)
        let thumbR = ImageHistogram.computeThumbnailRGB(from: imgRight)
        #expect(ImageHistogram.pixelDiffPercentage(from: thumbL, to: thumbR) > 0.9)

        // Display geometry picks secondary display with larger intersection
        let displays = [
            DisplayGeometry.DisplayInfo(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117)),
            DisplayGeometry.DisplayInfo(displayID: 2, frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440))
        ]
        #expect(DisplayGeometry.selectDisplayID(windowFrame: CGRect(x: 1800, y: 100, width: 1200, height: 800), displays: displays, mainDisplayID: 1) == 2)
        #expect(DisplayGeometry.selectDisplayID(windowFrame: nil, displays: displays, mainDisplayID: 1) == 1)

        // Dual-stage probe + pending queue
        final class MockDualStageCapturer: ScreenCapturing, @unchecked Sendable {
            private let lock = NSLock()
            var probeImage: CGImage
            var fullImage: CGImage
            var probeCalls = 0
            var fullCalls = 0

            init(probe: CGImage, full: CGImage) {
                self.probeImage = probe
                self.fullImage = full
            }
            var isScreenCaptureTrusted: Bool { true }
            func requestScreenCapturePermission() -> Bool { true }
            func captureMainDisplayImage() async throws -> CGImage {
                lock.withLock {
                    fullCalls += 1
                    return fullImage
                }
            }
            func captureActiveDisplayImage() async throws -> CGImage {
                try await captureMainDisplayImage()
            }
            func captureProbeImage() async throws -> CGImage {
                lock.withLock {
                    probeCalls += 1
                    return probeImage
                }
            }
        }

        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let capturer = MockDualStageCapturer(probe: imgLeft, full: imgLeft)
        let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: tmpDir.appendingPathComponent("snapshots"), capturer: capturer, clock: ManualClock(now: t0))

        let s0 = ActivitySample(timestamp: t0, appName: "Code", bundleId: "com.microsoft.VSCode", windowTitle: "A", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(try await recorder.processCapturedImage(imgLeft, sample: s0, trigger: "app_focus", runOCR: false))
        // Now save imgRight (identical histogram, different pixels) -> saved via pixelDiff!
        let s1 = ActivitySample(timestamp: t0.addingTimeInterval(3), appName: "Code", bundleId: "com.microsoft.VSCode", windowTitle: "B", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(try await recorder.processCapturedImage(imgRight, sample: s1, trigger: "app_focus", runOCR: false))

        // Unchanged visual_change probe should NOT trigger full capture
        capturer.probeImage = imgRight
        capturer.fullImage = imgRight
        let beforeFull = capturer.fullCalls
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let s2 = ActivitySample(timestamp: t0.addingTimeInterval(20), appName: "Code", bundleId: "com.microsoft.VSCode", windowTitle: "B", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            recorder.evaluatePeriodicCaptureIfNeeded(sample: s2, deepRecordingEnabled: true, declaredTaskId: nil) {
                done.resume()
            }
        }
        #expect(capturer.probeCalls == 1)
        #expect(capturer.fullCalls == beforeFull)

        // Reset baseline allows saving same image again immediately
        recorder.resetDeduplicationBaseline()
        let s3 = ActivitySample(timestamp: t0.addingTimeInterval(25), appName: "Code", bundleId: "com.microsoft.VSCode", windowTitle: "B", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        #expect(try await recorder.processCapturedImage(imgRight, sample: s3, trigger: "unlock", runOCR: false))
    }

    @Test("Multi-tier downsampling marks missing files pruned, enforces 10GB cap pattern, and preserves DayHelmSettings compat")
    func retentionTiersMissingFileFixAndStorageCap() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-cap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let store = DayHelmStore(directory: tmpDir)

        // Backward compatible config.json decode
        try Data("{\"deepRecordingEnabled\":false,\"snapshotRetentionDays\":14}".utf8).write(to: store.configURL)
        let loaded = store.loadSettings()
        #expect(loaded.deepRecordingEnabled == false)
        #expect(loaded.snapshotRetentionDays == 14)
        #expect(loaded.ocrEveryN == 1)
        #expect(loaded.snapshotMaxStorageBytes == 10 * 1024 * 1024 * 1024)

        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        // Insert missing-file snapshot older than 2 days
        let missingSnap = try db.insertSnapshot(
            timestampMs: t0Ms - 3 * 86_400_000,
            filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-14/missing.jpg").path,
            width: 1920, height: 1080, sizeBytes: 123_456, trigger: "app_focus", storageTier: "hot"
        )

        let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: store.snapshotsDirectory, clock: ManualClock(now: t0))
        _ = await recorder.downsampleOldSnapshots(olderThanDays: 1, retentionDays: 7, now: t0)
        let afterMissing = try #require(try db.snapshot(id: missingSnap.id))
        #expect(afterMissing.storageTier == "pruned")
        #expect(afterMissing.sizeBytes == 0)

        // Storage cap eviction: create 3 real files of 1000 bytes each, cap at 2500 -> target 1500 deletes oldest 2
        let dayDir = store.snapshotsDirectory.appendingPathComponent("2026-11-17", isDirectory: true)
        try FileManager.default.createDirectory(at: dayDir, withIntermediateDirectories: true)
        var createdIds: [String] = []
        for i in 0..<3 {
            let file = dayDir.appendingPathComponent("f\(i).jpg")
            try Data(repeating: 0xAB, count: 1000).write(to: file)
            let snap = try db.insertSnapshot(
                timestampMs: t0Ms + Int64(i * 10_000),
                filePath: file.path, width: 100, height: 100, sizeBytes: 1000, trigger: "heartbeat", storageTier: "hot"
            )
            createdIds.append(snap.id)
        }
        let evicted = try db.enforceSnapshotStorageCap(maxTotalBytes: 2500, targetBytes: 1500, snapshotsRootDir: store.snapshotsDirectory)
        #expect(evicted.deletedFiles == 2)
        #expect(try db.snapshot(id: createdIds[0])?.storageTier == "pruned")
        #expect(try db.snapshot(id: createdIds[1])?.storageTier == "pruned")
        #expect(try db.snapshot(id: createdIds[2])?.storageTier == "hot")
    }

    @Test("FTS5 trigram OCR search, ocrEveryN, consecutive OCR dedup, is_meeting, and regex entities")
    func fts5OCRSearchMeetingsAndEntities() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-fts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

        // Meeting session + GitHub PR + localhost port
        let meetEvt = try db.insertEvent(
            timestampMs: t0Ms,
            kind: "browser_visit",
            appName: "Google Chrome",
            windowTitle: "Fix capture #42 · acme/dayhelm",
            url: "https://github.com/acme/dayhelm/pull/42"
        )
        _ = try db.insertEvent(
            sessionId: meetEvt.sessionId,
            timestampMs: t0Ms + 5_000,
            kind: "browser_visit",
            appName: "Google Chrome",
            windowTitle: "Google Meet - Architecture Sync",
            url: "https://meet.google.com/abc-defg-hij"
        )
        _ = try db.insertEvent(
            sessionId: meetEvt.sessionId,
            timestampMs: t0Ms + 10_000,
            kind: "app_focus",
            appName: "Google Chrome",
            windowTitle: "Dashboard http://localhost:3000/status",
            url: "http://localhost:3000/status"
        )
        let snap1 = try db.insertSnapshot(
            sessionId: meetEvt.sessionId,
            timestampMs: t0Ms + 12_000,
            filePath: tmpDir.appendingPathComponent("s1.jpg").path,
            width: 100, height: 100, sizeBytes: 500, trigger: "app_focus"
        )
        _ = try db.insertOCRFrame(
            snapshotId: snap1.id,
            sessionId: meetEvt.sessionId,
            text: "2026年晶圆厂 Wafer Fab Q4 产能报告 \"quoted\"",
            createdAtMs: t0Ms + 12_000
        )
        try db.closeSession(sessionId: meetEvt.sessionId, endedAtMs: t0Ms + 60_000)

        let summary = try #require(try db.getSessionDetail(sessionId: meetEvt.sessionId)?.session)
        #expect(summary.isMeeting == true)
        #expect(summary.entities["repo"] == ["acme/dayhelm"])
        #expect(summary.entities["pr"] == ["#42"])
        #expect(summary.entities["local_port"] == ["localhost:3000"])

        // FTS5 trigram CJK (>=3) & English (>=3) & LIKE fallback (<3) & special char safety
        #expect(try db.searchOCR(keyword: "晶圆厂").count == 1)
        #expect(try db.searchOCR(keyword: "wafer").count == 1)
        #expect(try db.searchOCR(keyword: "Q4").count == 1)
        #expect(try db.searchOCR(keyword: "\"quoted\"").count == 1)
        #expect(try db.search(keyword: "晶圆厂").contains { $0.sourceKind == "ocr" })

        // ocrEveryN & consecutive OCR dedup helper
        #expect(NativeScreenRecorder.shouldRunOCR(savedCount: 1, trigger: "heartbeat", ocrEveryN: 3))
        #expect(!NativeScreenRecorder.shouldRunOCR(savedCount: 2, trigger: "heartbeat", ocrEveryN: 3))
        #expect(!NativeScreenRecorder.shouldRunOCR(savedCount: 3, trigger: "heartbeat", ocrEveryN: 3))
        #expect(NativeScreenRecorder.shouldRunOCR(savedCount: 4, trigger: "heartbeat", ocrEveryN: 3))
        #expect(NativeScreenRecorder.shouldRunOCR(savedCount: 2, trigger: "app_focus", ocrEveryN: 3))
    }

    @Test("PrivacyRedactor masks PEM keys, Google AIza keys, SSNs, and Luhn-valid credit cards")
    func extendedCredentialRedaction() {
        let pem = "-----BEGIN " + "RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA1234567890abcdef\n-----END RSA PRIVATE KEY-----"
        let googleKey = "AIza" + "SyD-1234567890ABCDEFGHIJKLMNOPQRS"
        let text = "key=\(googleKey) ssn=123-45-6789 card=4532 0151 1283 0366 order=1234567890123457 \(pem)"
        let redacted = PrivacyRedactor.redactSecrets(in: text)

        #expect(!redacted.contains("AIzaSyD-1234567890"))
        #expect(redacted.contains("AIza***"))
        #expect(!redacted.contains("123-45-6789"))
        #expect(redacted.contains("***-**-****"))
        #expect(!redacted.contains("4532 0151 1283 0366"))
        #expect(redacted.contains("0366"))
        #expect(redacted.contains("1234567890123457")) // non-Luhn order ID preserved
        #expect(!redacted.contains("MIIEowIBAAKCAQEA"))
    }

    @Test("HTTP compatibility endpoints expose pagination, prefix IDs, permissions, config, digest, and markdown report")
    func httpExtendedCompatibilityEndpoints() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-httpext-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let store = DayHelmStore(directory: tmpDir)
        let settings = DayHelmSettings(
            deepRecordingEnabled: true,
            snapshotRetentionDays: 14,
            snapshotMaxStorageBytes: 5_000_000_000,
            ocrEveryN: 2
        )
        try store.saveSettings(settings)

        let t0 = baseDate()
        let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)

        let s1 = try db.startSession(id: "abc12345-1111-2222-3333-444455556666", startedAtMs: t0Ms, triggerKind: "app_focus")
        _ = try db.insertEvent(sessionId: s1.id, timestampMs: t0Ms + 1_000, kind: "browser_visit", appName: "Google Chrome", windowTitle: "PR Review", url: "https://github.com/acme/dayhelm/pull/42")
        try db.closeSession(sessionId: s1.id, endedAtMs: t0Ms + 60_000)

        let s2 = try db.startSession(id: "def67890-1111-2222-3333-444455556666", startedAtMs: t0Ms + 120_000, triggerKind: "app_focus")
        _ = try db.insertEvent(sessionId: s2.id, timestampMs: t0Ms + 121_000, kind: "app_focus", appName: "Xcode", windowTitle: "Code")
        try db.closeSession(sessionId: s2.id, endedAtMs: t0Ms + 180_000)

        let server = LocalActivityHTTPServer(
            database: db,
            store: store,
            clock: ManualClock(now: t0.addingTimeInterval(600)),
            stateProvider: {
                LocalActivityHTTPServer.RuntimeState(
                    axTrusted: true,
                    screenCaptureTrusted: false,
                    keypressMonitoringEffective: true,
                    deepRecordingEnabled: true,
                    settings: settings
                )
            }
        )

        // offset + limit + total
        let paged = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/sessions?limit=1&offset=1&analysisStatus=completed")
        #expect(paged.statusCode == 200)
        let pagedJSON = try #require(try JSONSerialization.jsonObject(with: paged.body) as? [String: Any])
        #expect(pagedJSON["total"] as? Int == 2)
        let pagedSessions = try #require(pagedJSON["sessions"] as? [[String: Any]])
        #expect(pagedSessions.count == 1)
        #expect(pagedSessions[0]["id"] as? String == s1.id)

        // 6-char prefix lookup
        let prefixDetail = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/sessions/abc12345")
        #expect(prefixDetail.statusCode == 200)
        let prefixEvents = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/sessions/abc12345/events")
        #expect(prefixEvents.statusCode == 200)

        // /permissions & /config
        let perms = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/permissions")
        #expect(perms.statusCode == 200)
        let permsJSON = try #require(try JSONSerialization.jsonObject(with: perms.body) as? [String: Any])
        #expect(permsJSON["axTrusted"] as? Bool == true)
        #expect(permsJSON["keypressMonitoringEffective"] as? Bool == true)

        let cfg = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/config")
        #expect(cfg.statusCode == 200)
        let cfgJSON = try #require(try JSONSerialization.jsonObject(with: cfg.body) as? [String: Any])
        #expect(cfgJSON["snapshotRetentionDays"] as? Int == 14)
        #expect(cfgJSON["ocrEveryN"] as? Int == 2)

        // /digest & /report/<dateKey>
        let digest = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/digest?hours=24")
        #expect(digest.statusCode == 200)
        let digestJSON = try #require(try JSONSerialization.jsonObject(with: digest.body) as? [String: Any])
        #expect(digestJSON["sessionCount"] as? Int == 2)

        let report = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/report/2026-11-17")
        #expect(report.statusCode == 200)
        let reportJSON = try #require(try JSONSerialization.jsonObject(with: report.body) as? [String: Any])
        #expect(reportJSON["skeletonOnly"] as? Bool == true)
        #expect((reportJSON["markdown"] as? String)?.contains("2026-11-17") == true)

        let badReport = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/report/bad-date")
        #expect(badReport.statusCode == 400)
    }

    @Test("Extended DayHelmSettings persists all recorder parameters, clamps bounds, and loads legacy JSON")
    func extendedSettingsPersistenceAndCompatibility() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-extcfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let store = DayHelmStore(directory: tmpDir)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // Legacy config.json without new keys must load cleanly with defaults
        try Data("{\"deepRecordingEnabled\":false,\"snapshotRetentionDays\":5}".utf8).write(to: store.configURL)
        let legacy = store.loadSettings()
        #expect(legacy.deepRecordingEnabled == false)
        #expect(legacy.snapshotRetentionDays == 5)
        #expect(legacy.activityRecorderEnabled == true)
        #expect(legacy.visionOCREnabled == true)
        #expect(legacy.inputMonitoringEnabled == true)
        #expect(legacy.appFocusDebounceMs == 4000)
        #expect(legacy.heartbeatIntervalMs == 120_000)
        #expect(legacy.recorderIdleThresholdMs == 300_000)
        #expect(legacy.typingPauseQuietMs == 2000)
        #expect(legacy.visualCheckIntervalMs == 12_000)
        #expect(legacy.jpegQuality == 55)
        #expect(legacy.ocrLanguages == ["zh-Hans", "zh-Hant", "en-US", "ja"])
        #expect(legacy.sensitiveBundleIds.contains("com.apple.keychainaccess"))

        let custom = DayHelmSettings(
            activityRecorderEnabled: true,
            deepRecordingEnabled: true,
            visionOCREnabled: false,
            inputMonitoringEnabled: false,
            appFocusDebounceMs: 2500,
            heartbeatIntervalMs: 60_000,
            recorderIdleThresholdMs: 45_000,
            typingPauseQuietMs: 1200,
            visualCheckIntervalMs: 0,
            jpegQuality: 150, // clamped to 100
            ocrLanguages: ["en-US", "zh-Hans"],
            sensitiveBundleIds: ["com.example.secret"],
            snapshotRetentionDays: 14,
            snapshotMaxStorageBytes: 2 * 1024 * 1024 * 1024,
            ocrEveryN: 3
        )
        #expect(custom.jpegQuality == 100)
        try store.saveSettings(custom)

        let reloaded = store.loadSettings()
        #expect(reloaded.visionOCREnabled == false)
        #expect(reloaded.inputMonitoringEnabled == false)
        #expect(reloaded.appFocusDebounceMs == 2500)
        #expect(reloaded.heartbeatIntervalMs == 60_000)
        #expect(reloaded.recorderIdleThresholdMs == 45_000)
        #expect(reloaded.typingPauseQuietMs == 1200)
        #expect(reloaded.visualCheckIntervalMs == 0)
        #expect(reloaded.jpegQuality == 100)
        #expect(reloaded.ocrLanguages == ["en-US", "zh-Hans"])
        #expect(reloaded.sensitiveBundleIds == ["com.example.secret"])
        #expect(reloaded.ocrEveryN == 3)
    }

    @Test("ActivityDatabase.recorderStorageStats aggregates sessions, events, snapshots, OCR, and non-pruned bytes")
    func recorderStorageStatsAggregation() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-stats-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0Ms = Int64(baseDate().timeIntervalSince1970 * 1000)

        let s1 = try db.startSession(startedAtMs: t0Ms, triggerKind: "app_focus", appNames: ["Xcode"])
        _ = try db.insertEvent(sessionId: s1.id, timestampMs: t0Ms + 1000, kind: "app_focus", appName: "Xcode", windowTitle: "Main.swift")
        let snap1 = try db.insertSnapshot(sessionId: s1.id, timestampMs: t0Ms + 2000, filePath: "/tmp/a.jpg", width: 1280, height: 720, sizeBytes: 2048, storageTier: "hot")
        _ = try db.insertOCRFrame(snapshotId: snap1.id, sessionId: s1.id, text: "Hello DayHelm", createdAtMs: t0Ms + 2000)
        try db.closeSession(sessionId: s1.id, endedAtMs: t0Ms + 30_000)

        let s2 = try db.startSession(startedAtMs: t0Ms + 60_000, triggerKind: "app_focus", appNames: ["Terminal"])
        _ = try db.insertSnapshot(sessionId: s2.id, timestampMs: t0Ms + 61_000, filePath: "/tmp/b.jpg", width: 1280, height: 720, sizeBytes: 4096, storageTier: "pruned")

        let stats = try db.recorderStorageStats()
        #expect(stats.totalSessions == 2)
        #expect(stats.totalEvents == 1)
        #expect(stats.totalSnapshots == 2)
        #expect(stats.totalOCRFrames == 1)
        #expect(stats.usedSnapshotBytes == 2048)
        #expect(stats.activeSessionId == s2.id)
    }

    @Test("NativeScreenRecorder applies runtime timing, disables visual_change when 0, and respects visionOCREnabled == false")
    func recorderAppliesRuntimeSettings() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-recset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let store = DayHelmStore(directory: tmpDir)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let clock = ManualClock(now: baseDate())

        func makeTextImage(_ text: String) throws -> CGImage {
            let w = 640, h = 240
            guard let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else {
                throw NSError(domain: "Test", code: 1)
            }
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let attr = NSAttributedString(string: text, attributes: [
                .font: CTFontCreateWithName("Helvetica" as CFString, 40, nil),
                .foregroundColor: CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            ])
            let line = CTLineCreateWithAttributedString(attr)
            ctx.textPosition = CGPoint(x: 40, y: 100)
            CTLineDraw(line, ctx)
            return ctx.makeImage()!
        }

        final class CountingCapturer: ScreenCapturing, @unchecked Sendable {
            private let lock = NSLock()
            var image: CGImage
            var fullCount = 0
            var probeCount = 0
            init(image: CGImage) { self.image = image }
            var isScreenCaptureTrusted: Bool { true }
            func requestScreenCapturePermission() -> Bool { true }
            private func takeFull() -> CGImage {
                lock.lock(); defer { lock.unlock() }; fullCount += 1; return image
            }
            private func takeProbe() -> CGImage {
                lock.lock(); defer { lock.unlock() }; probeCount += 1; return image
            }
            func captureMainDisplayImage() async throws -> CGImage { takeFull() }
            func captureActiveDisplayImage() async throws -> CGImage { takeFull() }
            func captureProbeImage() async throws -> CGImage { takeProbe() }
        }

        let capturer = CountingCapturer(image: try makeTextImage("DayHelm OCR Toggle 2026"))
        let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: store.snapshotsDirectory, capturer: capturer, clock: clock)

        let customSettings = DayHelmSettings(
            activityRecorderEnabled: true,
            deepRecordingEnabled: true,
            visionOCREnabled: false,
            inputMonitoringEnabled: true,
            appFocusDebounceMs: 1000,
            heartbeatIntervalMs: 60_000,
            recorderIdleThresholdMs: 300_000,
            typingPauseQuietMs: 1200,
            visualCheckIntervalMs: 0,
            jpegQuality: 30
        )
        recorder.applySettings(customSettings)

        let sample0 = ActivitySample(timestamp: clock.now(), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Doc A", idleSeconds: 0, screenLocked: false, inputActive: true)
        let saved = try await recorder.processCapturedImage(
            try makeTextImage("DayHelm OCR Off Test"),
            sample: sample0,
            trigger: "heartbeat",
            runOCR: customSettings.visionOCREnabled,
            ocrEveryN: customSettings.ocrEveryN,
            ocrLanguages: customSettings.ocrLanguages
        )
        #expect(saved == true)
        let stats1 = try db.recorderStorageStats()
        #expect(stats1.totalSnapshots == 1)
        #expect(stats1.totalOCRFrames == 0)

        // Advance 20s: visualCheckIntervalMs == 0 must skip periodic visual_change capture
        clock.advance(by: 20)
        let sample20 = ActivitySample(timestamp: clock.now(), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Doc A", idleSeconds: 0, screenLocked: false, inputActive: true)
        recorder.evaluatePeriodicCaptureIfNeeded(
            sample: sample20,
            deepRecordingEnabled: true,
            declaredTaskId: nil,
            idleThresholdSeconds: 300,
            retentionDays: 7,
            maxStorageBytes: DayHelmSettings.defaultMaxStorageBytes,
            ocrEveryN: 1
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(capturer.probeCount == 0)
        #expect(capturer.fullCount == 0)

        // Advance to 65s (> heartbeatIntervalMs 60_000): heartbeat must fire
        clock.advance(by: 45)
        let sample65 = ActivitySample(timestamp: clock.now(), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Doc A", idleSeconds: 0, screenLocked: false, inputActive: true)
        recorder.evaluatePeriodicCaptureIfNeeded(
            sample: sample65,
            deepRecordingEnabled: true,
            declaredTaskId: nil,
            idleThresholdSeconds: 300,
            retentionDays: 7,
            maxStorageBytes: DayHelmSettings.defaultMaxStorageBytes,
            ocrEveryN: 1
        )
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(capturer.fullCount == 1)
    }

    @MainActor
    @Test("HybridActivityCoordinator syncs sensitiveBundleIds, toggles recording, and provides session history")
    func coordinatorRecorderSettingsAndSessionHistory() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-t-coordset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let store = DayHelmStore(directory: tmpDir)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let clock = ManualClock(now: baseDate())

        final class MutableInspector: ActivityInspecting, @unchecked Sendable {
            private let lock = NSLock()
            var sample: ActivitySample
            var latestPrivacyConfig: PrivacyRedactorConfig = .default
            init(sample: ActivitySample) { self.sample = sample }
            var isAccessibilityTrusted: Bool { true }
            func updatePrivacyConfig(_ config: PrivacyRedactorConfig) {
                lock.lock(); latestPrivacyConfig = config; lock.unlock()
            }
            func inspectCurrent() -> ActivitySample {
                lock.lock(); defer { lock.unlock() }; return sample
            }
        }

        let inspector = MutableInspector(sample: ActivitySample(
            timestamp: clock.now(),
            appName: "Example Browser",
            bundleId: "com.example.browser",
            windowTitle: "Example Docs",
            url: "https://docs.example.com",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        ))
        let engine = DayHelmEngine(budgets: [], clock: clock)
        let coord = HybridActivityCoordinator(
            engine: engine,
            store: store,
            almaClient: nil,
            inspector: inspector,
            clock: clock,
            syntheticDemo: false,
            database: db
        )

        coord.pollOnce()
        coord.refreshRecorderSessions()
        #expect(coord.recorderStats.totalSessions == 1)
        #expect(coord.recentSessions.count == 1)

        let sessionId = coord.recentSessions[0].id
        let detail = coord.loadSessionDetail(sessionId: sessionId)
        #expect(detail?.events.count == 1)

        // Add custom sensitive bundle ID and verify PrivacyRedactor + inspector update
        var updated = coord.recorderSettings
        updated.sensitiveBundleIds = ["com.example.secretvault"]
        coord.updateRecorderSettings(updated)

        #expect(inspector.latestPrivacyConfig.additionalSensitiveBundlePrefixes.contains("com.example.secretvault"))

        clock.advance(by: 10)
        inspector.sample = ActivitySample(
            timestamp: clock.now(),
            appName: "SecretVault",
            bundleId: "com.example.secretvault",
            windowTitle: "Master Password",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        coord.pollOnce()
        #expect(coord.latestSample?.redacted == true)
        #expect(coord.latestSample?.windowTitle == nil)

        // Disable activityRecorderEnabled and verify active session closes & new samples don't create sessions
        updated.activityRecorderEnabled = false
        coord.updateRecorderSettings(updated)
        #expect(try db.currentOpenSessionId() == nil)

        clock.advance(by: 400)
        inspector.sample = ActivitySample(
            timestamp: clock.now(),
            appName: "Terminal",
            bundleId: "com.apple.Terminal",
            windowTitle: "zsh",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        coord.pollOnce()
        #expect(try db.recorderStorageStats().totalSessions == 1)
    }

    @Test("SwitchClassifier debounces jitter, bridges auxiliary tools, and exempts same-task cross-app collaboration")
    func switchClassifierAndThrashingGate() {
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T08:30:00+08:00")!
        let budgets = [
            TaskBudget(
                taskId: "ecommerce",
                displayName: "电商做深",
                colorHex: "#3B82F6",
                targetMinutes: 90,
                capMinutes: 120,
                keywords: ["抖店", "1688", "主图"],
                appBundleIds: ["com.figma.Desktop"],
                domains: ["jinritemai.com"]
            )
        ]

        // 1. Auxiliary tools (Finder + Preview) bridged with ecommerce domain do not count as switches
        let auxSequence: [EnrichedSpan] = (0..<14).map { i in
            let start = t0.addingTimeInterval(Double(i) * 15)
            switch i % 3 {
            case 0:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "商品主图管理", url: "https://fxg.jinritemai.com/product/1", declaredTaskId: nil, redacted: false)
            case 1:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "Finder", bundleId: "com.apple.finder", windowTitle: "产品素材", url: nil, declaredTaskId: nil, redacted: false)
            default:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "Preview", bundleId: "com.apple.Preview", windowTitle: "banner.png", url: nil, declaredTaskId: nil, redacted: false)
            }
        }
        #expect(SpectrumBuilder.detectThrashingWindows(spans: auxSequence, budgets: budgets).isEmpty)

        // 2. Shared project token across engineering apps (T3 Code <-> Terminal <-> Chrome GitHub) does not thrash
        let devEngine = DayHelmEngine(budgets: budgets, clock: ManualClock(now: t0))
        let devSteps: [(String, String, String, String?)] = [
            ("T3 Code", "com.t3code.app", "T3 Code (Beta) - focus-guard", nil),
            ("Terminal", "com.apple.Terminal", "focus-guard — zsh", nil),
            ("Google Chrome", "com.google.Chrome", "focus-guard PR #9", "https://github.com/lban/focus-guard/pull/9")
        ]
        for i in 0..<15 {
            let s = devSteps[i % devSteps.count]
            let alerts = devEngine.ingest(ActivitySample(
                timestamp: t0.addingTimeInterval(Double(i) * 15),
                appName: s.0,
                bundleId: s.1,
                windowTitle: s.2,
                url: s.3,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
            #expect(!alerts.contains { if case .highFrequencySwitch = $0.kind { return true }; return false })
        }

        // 3. Interrupt apps (WeChat, Bilibili, Slack, Weibo) DO trigger thrashing & smooth rate uses >= 600s denominator
        let distractSpans: [EnrichedSpan] = (0..<14).map { i in
            let start = t0.addingTimeInterval(Double(i) * 15)
            switch i % 4 {
            case 0:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "WeChat", bundleId: "com.tencent.xinWeChat", windowTitle: "Chat", url: nil, declaredTaskId: nil, redacted: false)
            case 1:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Video", url: "https://www.bilibili.com/video/1", declaredTaskId: nil, redacted: false)
            case 2:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "Slack", bundleId: "com.tinyspeck.slackmacgap", windowTitle: "random", url: nil, declaredTaskId: nil, redacted: false)
            default:
                return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(12), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Feed", url: "https://weibo.com/u/1", declaredTaskId: nil, redacted: false)
            }
        }
        let thrashWindows = SpectrumBuilder.detectThrashingWindows(spans: distractSpans, budgets: budgets)
        #expect(!thrashWindows.isEmpty)
        #expect(thrashWindows[0].distinctContextCount >= 4)

        let rateStats = SpectrumBuilder.recentSwitchStats(spans: distractSpans, now: t0.addingTimeInterval(210), budgets: budgets)
        // 13 switches over <= 600s observed window => 13 * 6 = 78/h (smoothed by 600s floor instead of 300s)
        #expect(abs(rateStats.switchesPerHour - 78.0) < 0.01)
    }

    @Test("SpectrumBuilder sweep-line preserves precedence, coalesces segments, and scales on dense inputs")
    func spectrumSweepLinePrecedenceAndDensePerformance() {
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T09:00:00+08:00")!
        let budgets = [
            TaskBudget(
                taskId: "dev",
                displayName: "开发",
                colorHex: "#3B82F6",
                targetMinutes: 60,
                capMinutes: 120,
                keywords: ["xcode"],
                appBundleIds: ["com.apple.dt.Xcode"],
                domains: []
            ),
            TaskBudget(
                taskId: "ops",
                displayName: "运营",
                colorHex: "#F59E0B",
                targetMinutes: nil,
                capMinutes: 30,
                keywords: ["support"],
                appBundleIds: [],
                domains: []
            )
        ]

        // 09:00-09:10: Explicit focus session on "dev"
        // 09:02-09:05: Interrupt thrashing burst during focus session (thrashing MUST win precedence over focus session)
        // 09:10-09:15: Gap (300s -> idle)
        // 09:15-09:17: Unassigned span (declaredTaskId: nil -> .unassigned)
        // 09:17-09:20: Declared "ops" span without focus session (declaredTaskId: "ops" -> .task("ops"))
        var spans: [EnrichedSpan] = [
            EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(120), appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "App.swift", url: nil, declaredTaskId: "dev", redacted: false)
        ]
        for i in 0..<12 {
            let s = t0.addingTimeInterval(120 + Double(i) * 15)
            let app: (String, String, String?) = switch i % 4 {
            case 0: ("WeChat", "com.tencent.xinWeChat", nil)
            case 1: ("Google Chrome", "com.google.Chrome", "https://www.bilibili.com/video/1")
            case 2: ("Slack", "com.tinyspeck.slackmacgap", nil)
            default: ("Google Chrome", "com.google.Chrome", "https://weibo.com/u/1")
            }
            spans.append(EnrichedSpan(
                startedAt: s,
                endedAt: s.addingTimeInterval(12),
                appName: app.0,
                bundleId: app.1,
                windowTitle: "Noise \(i)",
                url: app.2,
                declaredTaskId: "dev",
                redacted: false
            ))
        }
        spans.append(EnrichedSpan(
            startedAt: t0.addingTimeInterval(300),
            endedAt: t0.addingTimeInterval(600),
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitle: "Engine.swift",
            url: nil,
            declaredTaskId: "dev",
            redacted: false
        ))
        spans.append(EnrichedSpan(
            startedAt: t0.addingTimeInterval(900),
            endedAt: t0.addingTimeInterval(1020),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Random Browsing",
            url: nil,
            declaredTaskId: nil,
            redacted: false
        ))
        spans.append(EnrichedSpan(
            startedAt: t0.addingTimeInterval(1020),
            endedAt: t0.addingTimeInterval(1200),
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            windowTitle: "Support Ticket #1",
            url: nil,
            declaredTaskId: "ops",
            redacted: false
        ))

        let sessions = [
            FocusSessionRecord(
                id: "s1",
                taskId: "dev",
                startedAt: t0,
                endedAt: t0.addingTimeInterval(600),
                minutes: 10.0,
                note: nil
            )
        ]

        let built = SpectrumBuilder.build(
            spans: spans,
            focusSessions: sessions,
            budgets: budgets,
            now: t0.addingTimeInterval(1200)
        )

        #expect(built.segments.contains { if case .thrashing = $0.kind { return true }; return false })
        #expect(built.segments.contains { if case .idle = $0.kind { return true }; return false })
        #expect(built.segments.contains { if case .unassigned = $0.kind { return true }; return false })
        #expect(built.segments.contains { if case .task(let id, _, _) = $0.kind { return id == "ops" }; return false })
        // Adjacent identical kinds must coalesce
        for i in 1..<built.segments.count {
            #expect(built.segments[i - 1].kind != built.segments[i].kind)
        }

        // Stress test: 1,500 overlapping spans across 50 sessions
        var denseSpans: [EnrichedSpan] = []
        denseSpans.reserveCapacity(1500)
        for i in 0..<1500 {
            let s = t0.addingTimeInterval(Double(i) * 18)
            denseSpans.append(EnrichedSpan(
                startedAt: s,
                endedAt: s.addingTimeInterval(25),
                appName: i % 2 == 0 ? "Xcode" : "Terminal",
                bundleId: i % 2 == 0 ? "com.apple.dt.Xcode" : "com.apple.Terminal",
                windowTitle: "focus-guard file \(i)",
                url: nil,
                declaredTaskId: i % 5 == 0 ? "dev" : nil,
                redacted: false
            ))
        }
        let denseSessions = (0..<50).map { idx in
            FocusSessionRecord(
                id: "ds_\(idx)",
                taskId: idx % 2 == 0 ? "dev" : "ops",
                startedAt: t0.addingTimeInterval(Double(idx) * 500),
                endedAt: t0.addingTimeInterval(Double(idx) * 500 + 300),
                minutes: 5.0
            )
        }
        let benchStart = Date()
        let denseBuilt = SpectrumBuilder.build(
            spans: denseSpans,
            focusSessions: denseSessions,
            budgets: budgets,
            now: t0.addingTimeInterval(27000)
        )
        let elapsed = Date().timeIntervalSince(benchStart)
        #expect(!denseBuilt.segments.isEmpty)
        #expect(elapsed < 1.0)
    }

    @Test("DayHelmEngine caches spectrum per stateVersion/timestamp and invalidates on mutations")
    func engineSpectrumCacheInvalidationAndSnapshotPrecomputedMetrics() {
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T10:00:00+08:00")!
        let clock = ManualClock(now: t0)
        let budgets = [
            TaskBudget(taskId: "dev", displayName: "开发", colorHex: "#3B82F6", targetMinutes: 60, capMinutes: nil, keywords: ["xcode"]),
            TaskBudget(taskId: "ops", displayName: "运营", colorHex: "#F59E0B", targetMinutes: nil, capMinutes: 30, keywords: ["ticket"])
        ]
        let engine = DayHelmEngine(budgets: budgets, clock: clock)

        let s1 = engine.currentSpectrumAndMetrics(at: t0)
        let s1Repeat = engine.currentSpectrumAndMetrics(at: t0)
        #expect(s1.segments == s1Repeat.segments)
        #expect(s1.metrics == s1Repeat.metrics)

        engine.startFocus(taskId: "dev", at: t0)
        clock.advance(by: 15 * 60)
        engine.ingest(ActivitySample(
            timestamp: clock.now(),
            appName: "Xcode",
            bundleId: "com.apple.dt.Xcode",
            windowTitle: "DayHelmEngine.swift",
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        ))

        let s2 = engine.currentSpectrumAndMetrics(at: clock.now())
        #expect(s2.metrics.activeMinutes >= 14.9)
        #expect(s2.metrics.solidBlocksCount >= 1)

        let snapDirect = engine.snapshot(at: clock.now())
        let snapPrecomputed = engine.snapshot(at: clock.now(), precomputedMetrics: s2.metrics)
        #expect(snapDirect.metrics == s2.metrics)
        #expect(snapPrecomputed.metrics == s2.metrics)

        // Mutate task displayName and ensure cached segment displayName updates immediately
        _ = engine.updateTask(TaskBudget(taskId: "dev", displayName: "核心研发", colorHex: "#3B82F6", targetMinutes: 60, capMinutes: nil, keywords: ["xcode"]))
        let s3 = engine.currentSpectrumAndMetrics(at: clock.now())
        let hasUpdatedName = s3.segments.contains {
            if case .task(let id, let name, _) = $0.kind {
                return id == "dev" && name == "核心研发"
            }
            return false
        }
        #expect(hasUpdatedName)

        engine.rolloverToNewDay("2026-11-19")
        let s4 = engine.currentSpectrumAndMetrics(at: clock.now())
        #expect(s4.segments.isEmpty)
        #expect(s4.metrics.activeMinutes == 0)
    }

    @Test("ActivityDatabase hot queries use indexes without plain full table scans")
    func sqliteHotQueriesUseIndexes() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-idx-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let dbURL = tmpDir.appendingPathComponent("activity.sqlite")
        let db = try ActivityDatabase(databaseURL: dbURL)
        let nowMs: Int64 = 1_763_430_000_000
        let session = try db.startSession(startedAtMs: nowMs, triggerKind: "manual", declaredTaskId: "dev")
        let snap = try db.insertSnapshot(
            timestampMs: nowMs + 1_000,
            filePath: "2026-11-18/test.jpg",
            width: 1280,
            height: 720,
            sizeBytes: 42_000,
            trigger: "app_focus",
            appName: "Xcode",
            windowTitle: "Main.swift",
            hashHex: "abcd",
            histogram: Array(repeating: 0.03125, count: 32),
            diffPct: 0.1
        )
        _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: session.id, text: "Example OCR", createdAtMs: nowMs + 1_500)

        var rawDB: OpaquePointer?
        #expect(sqlite3_open_v2(dbURL.path, &rawDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
        defer { sqlite3_close(rawDB) }

        let queries = [
            "SELECT id FROM activity_sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;",
            "SELECT COUNT(*) FROM activity_snapshots WHERE timestamp >= 0 AND timestamp <= 9999999999999;",
            "SELECT COUNT(*) FROM activity_ocr_frames WHERE created_at >= 0 AND created_at <= 9999999999999;",
            "SELECT COALESCE(SUM(size_bytes), 0) FROM activity_snapshots WHERE storage_tier != 'pruned';"
        ]
        for sql in queries {
            var stmt: OpaquePointer?
            #expect(sqlite3_prepare_v2(rawDB, "EXPLAIN QUERY PLAN " + sql, -1, &stmt, nil) == SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(stmt, 3) {
                    let detail = String(cString: cStr)
                    let isPlainScan = detail.contains("SCAN ") && !detail.contains("INDEX")
                    #expect(!isPlainScan, "Plain table scan for [\(sql)]: \(detail)")
                }
            }
        }
    }

    @Test("SwitchClassifier memoization, eviction, and 1500-span 50-tick SpectrumBuilder performance")
    func switchClassifierMemoizationAndLargeDayPerf() {
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T09:00:00+08:00")!
        let clock = ManualClock(now: t0)
        let budgets = [
            TaskBudget(taskId: "ecommerce", displayName: "电商做深", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["example-shop", "product-listing"]),
            TaskBudget(taskId: "hermes", displayName: "Hermes 投研", colorHex: "#10B981", targetMinutes: 45, capMinutes: 60, keywords: ["hermes"])
        ]
        let engine = DayHelmEngine(budgets: budgets, clock: clock)
        engine.startFocus(taskId: "ecommerce", at: t0)

        let apps: [(String, String, String, String?)] = [
            ("Google Chrome", "com.google.Chrome", "example-shop Admin - (2) Orders 45%", "https://example-shop.local/orders"),
            ("Terminal", "com.apple.Terminal", "zsh — swift build 12:01:02", nil),
            ("Preview", "com.apple.Preview", "product-listing.png", nil),
            ("WeChat", "com.tencent.xinWeChat", "WeChat (5)", nil),
            ("Xcode", "com.apple.dt.Xcode", "hermes-core.swift", nil)
        ]
        for i in 0..<1500 {
            let item = apps[i % apps.count]
            clock.advance(by: 10)
            engine.ingest(ActivitySample(
                timestamp: clock.now(),
                appName: item.0,
                bundleId: item.1,
                windowTitle: "\(item.2) #\(i % 12)",
                url: item.3,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
        }

        let start = CFAbsoluteTimeGetCurrent()
        var last = engine.currentSpectrumAndMetrics(at: clock.now())
        for tick in 0..<50 {
            clock.advance(by: 2)
            let item = apps[tick % apps.count]
            engine.ingest(ActivitySample(
                timestamp: clock.now(),
                appName: item.0,
                bundleId: item.1,
                windowTitle: item.2,
                url: item.3,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
            last = engine.currentSpectrumAndMetrics(at: clock.now())
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(!last.segments.isEmpty)
        #expect(last.metrics.activeMinutes > 0)
        #expect(elapsed < 0.25)

        for k in 0..<4500 {
            let span = EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(10), appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "File-\(k).swift", url: nil, declaredTaskId: nil, redacted: false)
            _ = SwitchClassifier.role(for: span)
            _ = SwitchClassifier.canonicalContextKey(for: span)
            _ = SwitchClassifier.projectTokens(for: span)
        }
        let wechatSpan = EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(15), appName: "WeChat", bundleId: "com.tencent.xinWeChat", windowTitle: "Chat", url: nil, declaredTaskId: nil, redacted: false)
        #expect(SwitchClassifier.role(for: wechatSpan) == .interrupt)
    }

    @Test("ActivityDatabase grouped session summary synthesis matches expected metadata and entities")
    func groupedSessionSummarySynthesisParity() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-sum-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let t0Ms: Int64 = 1_763_430_000_000
        let session = try db.startSession(startedAtMs: t0Ms, triggerKind: "manual", declaredTaskId: "dev")
        for i in 0..<500 {
            let ts = t0Ms + Int64(i * 100)
            switch i % 4 {
            case 0:
                try db.insertEvent(timestampMs: ts, kind: "browser_visit", appName: "Google Chrome", windowTitle: "Fix perf PR #42", url: "https://github.com/acme/dayhelm/pull/42", data: [:])
            case 1:
                try db.insertEvent(timestampMs: ts, kind: "browser_visit", appName: "Google Chrome", windowTitle: "Local Preview", url: "http://localhost:3000/dashboard", data: [:])
            case 2:
                try db.insertEvent(timestampMs: ts, kind: "keypress", appName: "Zoom", windowTitle: "Zoom Meeting", url: "https://zoom.us/j/12345", data: ["count": "2"])
            default:
                try db.insertEvent(timestampMs: ts, kind: "click", appName: "Xcode", windowTitle: "DayHelmEngine.swift", url: nil, data: ["count": "3"])
            }
        }
        try db.closeSession(sessionId: session.id, endedAtMs: t0Ms + 60_000)
        let detail = try db.getSessionDetail(sessionId: session.id)!
        #expect(detail.session.clickCount == 375)
        #expect(detail.session.keypressCount == 250)
        #expect(detail.session.isMeeting == true)
        #expect(detail.session.analysisTitle?.isEmpty == false)
        #expect(detail.session.analysisDescription?.isEmpty == false)
        #expect(!detail.session.topics.isEmpty)
        let entityTypes = Set(detail.session.entities.keys)
        for expected in ["repo", "pr", "local_port", "domain", "app", "task"] {
            #expect(entityTypes.contains(expected))
        }
    }

    @Test("ActivityTextNormalizer and PrivacyRedactor precompiled regex and fast-path parity")
    func normalizerAndRedactorFastPathParity() {
        #expect(ActivityTextNormalizer.normalizedTitleKey("(3) Inbox - 45% 12:34:56 Loading...") == "inbox - loading")
        #expect(ActivityTextNormalizer.normalizedTitleKey("v2 Release Q4") == "v2 release q4")

        let now = DayHelmDateFormatting.parseISO8601("2026-11-18T09:00:00+08:00")!
        #expect(PrivacyRedactor.shouldRedact(ActivitySample(timestamp: now, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Invoice Payment Portal", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)))
        #expect(!PrivacyRedactor.shouldRedact(ActivitySample(timestamp: now, appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "payload.json", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)))
        #expect(!PrivacyRedactor.shouldRedact(ActivitySample(timestamp: now, appName: "System Settings", bundleId: "com.apple.systemsettings", windowTitle: "Display Settings", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)))

        let secrets = [
            "-----BEGIN " + "RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----",
            "token=sk-" + "1234567890abcdefghijklmnop",
            "ghp_" + "1234567890abcdefghijklmnopqrstuvwxyz",
            "xoxb-" + "123456789012-1234567890123-abcdefghijklmnopqrstuvwx",
            "AKIA" + "IOSFODNN7EXAMPLE",
            "AIza" + "SyDaGmWKa4JsXZ-HjGw7ISLn_3namBGewQe",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U",
            "ssn: 123-45-6789",
            "Authorization: Bearer super_secret_token_value_12345",
            "Authorization: Basic dXNlcjpwYXNzMTIzNDU=",
            "api_key=my_super_secret_value_999",
            "card: 4111 1111 1111 1111"
        ]
        for raw in secrets {
            let out = PrivacyRedactor.redactSecrets(in: raw)
            #expect(out != raw && out.contains("***"))
        }

        let cleanOCR = String(repeating: "SwiftPM DayHelmCore ActivityDatabase SQLite WAL benchmark line 12345.\n", count: 80)
        #expect(PrivacyRedactor.redactSecrets(in: cleanOCR) == cleanOCR)
    }

    @Test("Incremental SpectrumBuilder matches stateless SpectrumBuilder.build across mixed ticks")
    func incrementalSpectrumMatchesStatelessBuild() {
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T09:00:00+08:00")!
        let clock = ManualClock(now: t0)
        let budgets = [
            TaskBudget(taskId: "dev", displayName: "Dev", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 180, keywords: ["xcode", "dayhelm"]),
            TaskBudget(taskId: "ops", displayName: "Ops", colorHex: "#10B981", targetMinutes: 30, capMinutes: 60, keywords: ["shop"])
        ]
        let engine = DayHelmEngine(budgets: budgets, clock: clock)
        let samples: [(String, String, String, String?, String?)] = [
            ("Xcode", "com.apple.dt.Xcode", "DayHelmEngine.swift", nil, "dev"),
            ("Google Chrome", "com.google.Chrome", "Shop Admin", "https://shop.local/orders", nil),
            ("WeChat", "com.tencent.xinWeChat", "Chat", nil, nil),
            ("Finder", "com.apple.finder", "Downloads", nil, nil),
            ("Terminal", "com.apple.Terminal", "zsh", nil, "dev")
        ]
        for i in 0..<60 {
            let item = samples[i % samples.count]
            if i == 10 { engine.startFocus(taskId: "dev", at: clock.now()) }
            if i == 35 { engine.pauseFocus(at: clock.now()) }
            clock.advance(by: (i % 7 == 0) ? 15 : 3)
            engine.ingest(ActivitySample(
                timestamp: clock.now(),
                appName: item.0,
                bundleId: item.1,
                windowTitle: "\(item.2) #\(i)",
                url: item.3,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
            let incremental = engine.currentSpectrumAndMetrics(at: clock.now())
            let snap = engine.snapshot(at: clock.now())
            let stateless = SpectrumBuilder.build(
                spans: snap.enrichedSpans,
                focusSessions: snap.focusSessions,
                budgets: budgets,
                now: clock.now()
            )
            #expect(incremental.segments == stateless.segments)
            #expect(incremental.metrics == stateless.metrics)
        }
    }

    @Test("VisionOCRService downscales >1600px images and ImageHistogram computes single-pass visual signature")
    func ocrDownscalingAndVisualSignature() async throws {
        let largeImg = try makeSyntheticTextImage(text: "DAYHELM_OCR_2560", backgroundWhite: true, width: 2560, height: 1600)
        let scaled = VisionOCRService.prepareOCRImage(from: largeImg, maxDimension: 1600)
        #expect(scaled.width == 1600)
        #expect(scaled.height == 1000)

        let smallImg = try makeSyntheticTextImage(text: "SMALL_960", backgroundWhite: true, width: 960, height: 240)
        let untouched = VisionOCRService.prepareOCRImage(from: smallImg, maxDimension: 1600)
        #expect(untouched.width == 960)
        #expect(untouched.height == 240)

        let ocrResult = try await VisionOCRService.recognizeText(from: scaled)
        #expect(ocrResult.text.uppercased().contains("DAYHELM"))

        let sig = ImageHistogram.computeVisualSignature(from: largeImg, bins: 32)
        #expect(sig.histogram.count == 32)
        #expect(sig.thumbnailRGB.count == 160 * 90 * 3)
        #expect(sig.hashHex.count == 16)
    }

    @Test("NativeScreenRecorder caps OCR session dedup cache at 4 and resets on baseline clear")
    func boundedOCRSessionDedupCache() async throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-ocr-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T10:00:00+08:00")!
        let clock = ManualClock(now: t0)
        let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
        let capturer = MockScreenCapturer(image: try makeSyntheticTextImage(text: "OCR_INIT", backgroundWhite: true))
        let recorder = NativeScreenRecorder(
            database: db,
            snapshotsRootDir: tmpDir.appendingPathComponent("snapshots"),
            capturer: capturer,
            clock: clock
        )
        for i in 0..<20 {
            let session = try db.startSession(startedAtMs: Int64(clock.now().timeIntervalSince1970 * 1000), triggerKind: "manual")
            let img = try makeSyntheticTextImage(text: "SESSION_OCR_\(i)", backgroundWhite: (i % 2 == 0))
            let sample = ActivitySample(
                timestamp: clock.now(),
                appName: "Xcode",
                bundleId: "com.apple.dt.Xcode",
                windowTitle: "File\(i).swift",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            )
            _ = try await recorder.processCapturedImage(
                img,
                sample: sample,
                sessionId: session.id,
                trigger: "app_focus"
            )
            try db.closeSession(sessionId: session.id, endedAtMs: Int64(clock.now().timeIntervalSince1970 * 1000) + 1000)
            clock.advance(by: 2)
        }
        #expect(recorder.cachedOCRSessionCount <= 4)
        recorder.resetDeduplicationBaseline()
        #expect(recorder.cachedOCRSessionCount == 0)
    }

    @Test("AXWindowInspector caches browser tab AppleScript result for 15s when title is unchanged")
    func axWindowInspectorBrowserTTLCache() {
        final class CounterBox: @unchecked Sendable {
            private let lock = NSLock()
            private var _value = 0
            var value: Int { lock.withLock { _value } }
            func increment() { lock.withLock { _value += 1 } }
        }
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T10:00:00+08:00")!
        let clock = ManualClock(now: t0)
        let counter = CounterBox()
        let inspector = AXWindowInspector(
            clock: clock,
            observeScreenLock: false,
            browserCacheTTLSeconds: 15.0,
            browserTabProvider: { appName, _ in
                counter.increment()
                return (url: "https://example.com/\(appName)/\(counter.value)", title: "Page \(counter.value)")
            }
        )
        for _ in 0..<7 {
            let res = inspector.resolveBrowserFallbackWithCache(
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                existingTitle: "Same Tab Title",
                existingURL: nil,
                screenLocked: false
            )
            #expect(res.url == "https://example.com/Google Chrome/1")
            clock.advance(by: 2)
        }
        #expect(counter.value == 1)

        clock.advance(by: 2)
        let refreshed = inspector.resolveBrowserFallbackWithCache(
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            existingTitle: "Same Tab Title",
            existingURL: nil,
            screenLocked: false
        )
        #expect(counter.value == 2)
        #expect(refreshed.url == "https://example.com/Google Chrome/2")

        clock.advance(by: 2)
        _ = inspector.resolveBrowserFallbackWithCache(
            appName: "Google Chrome",
            bundleId: "com.google.Chrome",
            existingTitle: "Changed Title",
            existingURL: nil,
            screenLocked: false
        )
        #expect(counter.value == 3)

        clock.advance(by: 2)
        _ = inspector.resolveBrowserFallbackWithCache(
            appName: "Safari",
            bundleId: "com.apple.Safari",
            existingTitle: "Changed Title",
            existingURL: nil,
            screenLocked: false
        )
        #expect(counter.value == 4)
    }

    @Test("Coordinator lazily builds RuntimeState.daySnapshot, gates closed-popover timer, and decouples MenuBarPillModel")
    @MainActor
    func coordinatorLazySnapshotPopoverGatingAndPillModel() throws {
        let t0 = DayHelmDateFormatting.parseISO8601("2026-11-18T10:00:00+08:00")!
        let clock = ManualClock(now: t0)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-coord-stage2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = DayHelmStore(directory: tmpDir)
        let budgets = [
            TaskBudget(taskId: "dev", displayName: "Dev", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["xcode"])
        ]
        let engine = DayHelmEngine(budgets: budgets, clock: clock)
        let coordinator = HybridActivityCoordinator(
            engine: engine,
            store: store,
            almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
            inspector: MockInspector(sample: ActivitySample(
                timestamp: t0,
                appName: "Xcode",
                bundleId: "com.apple.dt.Xcode",
                windowTitle: "Main.swift",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            )),
            clock: clock
        )
        #expect(coordinator.pillModel.text == "○ DayHelm · 待命")
        coordinator.selectTask("dev")
        #expect(coordinator.pillModel.text.contains("Dev"))
        let initialPill = coordinator.pillModel.text

        #expect(coordinator.isPopoverVisible == false)
        let beforeElapsed = coordinator.elapsedFocusSeconds
        clock.advance(by: 2)
        coordinator.pollOnce()
        #expect(coordinator.elapsedFocusSeconds == beforeElapsed)
        #expect(coordinator.pillModel.text == initialPill)

        coordinator.setPopoverVisible(true)
        #expect(coordinator.elapsedFocusSeconds >= 2.0)

        let runtimeSnap = coordinator.currentRuntimeState().daySnapshot
        #expect(runtimeSnap != nil)
        #expect(runtimeSnap?.activeFocus?.taskId == "dev")
    }

    @Test("ScreenSnapshotCapturer.decodeThumbnailCGImage downsamples 2560x1440 JPEG to max 368px")
    func thumbnailDownsampledDecoding() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let large = try makeSyntheticTextImage(text: "THUMB_368", backgroundWhite: false, width: 2560, height: 1440)
        let jpgURL = tmpDir.appendingPathComponent("frame.jpg")
        _ = try ScreenSnapshotCapturer.encodeJPEG(image: large, to: jpgURL, quality: 0.6)

        let thumb = ScreenSnapshotCapturer.decodeThumbnailCGImage(at: jpgURL, maxPixelSize: 368)
        #expect(thumb != nil)
        if let thumb {
            #expect(max(thumb.width, thumb.height) == 368)
        }
    }

    @Test("VisionOCRWorker.processRequestJSONData decodes JPEG, recognizes text, and handles missing files")
    func visionOCRWorkerJSONRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-ocr-worker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let img = try makeSyntheticTextImage(text: "WORKER_OCR_2026", backgroundWhite: true, width: 1280, height: 720)
        let jpgURL = tmpDir.appendingPathComponent("sample.jpg")
        _ = try ScreenSnapshotCapturer.encodeJPEG(image: img, to: jpgURL, quality: 0.8)

        let reqObj: [String: Any] = [
            "imagePath": jpgURL.path,
            "maxDimension": 1280,
            "languages": ["en-US"]
        ]
        let reqData = try JSONSerialization.data(withJSONObject: reqObj)
        let respData = VisionOCRWorker.processRequestJSONData(reqData)
        let resp = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
        #expect(resp?["ok"] as? Bool == true)
        let text = resp?["text"] as? String ?? ""
        #expect(text.uppercased().contains("WORKER"))
        #expect((resp?["charCount"] as? Int ?? 0) > 0)

        let missingReq = try JSONSerialization.data(withJSONObject: [
            "imagePath": tmpDir.appendingPathComponent("missing.jpg").path,
            "maxDimension": 1280,
            "languages": ["en-US"]
        ])
        let missingRespData = VisionOCRWorker.processRequestJSONData(missingReq)
        let missingResp = try JSONSerialization.jsonObject(with: missingRespData) as? [String: Any]
        #expect(missingResp?["ok"] as? Bool == false)
    }

    @Test("NativeScreenRecorder skips rapid secondary OCR within minNonFocusOCRIntervalSeconds while running app_focus immediately")
    func nativeScreenRecorderNonFocusOCRCooldown() async throws {
        let t0 = Date(timeIntervalSince1970: 1_760_300_000)
        let clock = ManualClock(now: t0)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-ocr-cooldown-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = DayHelmStore(directory: tmpDir)
        let db = try ActivityDatabase(databaseURL: store.databaseURL)
        let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: store.snapshotsDirectory, clock: clock)
        recorder.minNonFocusOCRIntervalSeconds = 25.0

        let sample = ActivitySample(
            timestamp: t0,
            appName: "Notes",
            bundleId: "com.apple.Notes",
            windowTitle: "Doc 1",
            url: nil,
            idleSeconds: 0,
            screenLocked: false,
            inputActive: true
        )
        let dayStartMs = Int64(t0.timeIntervalSince1970 * 1000) - 1000
        let dayEndMs = dayStartMs + 86_400_000
        let img1 = try makeSyntheticTextImage(text: "COOLDOWN_ONE", backgroundWhite: true, width: 1280, height: 720)
        let saved1 = try await recorder.processCapturedImage(img1, sample: sample, trigger: ActivityEventKind.appFocus.rawValue, runOCR: true)
        #expect(saved1)
        #expect(try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs).ocrFrames == 1)

        clock.advance(by: 5)
        let sample2 = ActivitySample(timestamp: clock.now(), appName: "Notes", bundleId: "com.apple.Notes", windowTitle: "Doc 1", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let img2 = try makeSyntheticTextImage(text: "COOLDOWN_TWO_VISUAL", backgroundWhite: false, width: 1280, height: 720)
        let saved2 = try await recorder.processCapturedImage(img2, sample: sample2, trigger: "visual_change", runOCR: true)
        #expect(saved2)
        #expect(try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs).ocrFrames == 1)

        clock.advance(by: 5)
        let sample3 = ActivitySample(timestamp: clock.now(), appName: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "zsh", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
        let img3 = try makeSyntheticTextImage(text: "COOLDOWN_FOCUS_IMMEDIATE", backgroundWhite: true, width: 1280, height: 720)
        let saved3 = try await recorder.processCapturedImage(img3, sample: sample3, trigger: ActivityEventKind.appFocus.rawValue, runOCR: true)
        #expect(saved3)
        #expect(try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs).ocrFrames == 2)
    }

    @Test("HybridActivityCoordinator gates UI @Published updates when started and hidden, and hydrates on window/popover open")
    @MainActor
    func coordinatorBackgroundUIGatingAndHydration() throws {
        let t0 = Date(timeIntervalSince1970: 1_760_301_000)
        let clock = ManualClock(now: t0)
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-test-ui-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let store = DayHelmStore(directory: tmpDir)
        let budgets = [TaskBudget(taskId: "dev", displayName: "Dev", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["xcode"])]
        let engine = DayHelmEngine(budgets: budgets, clock: clock)
        let inspector = MockInspector(sample: ActivitySample(
            timestamp: t0, appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "Initial.swift", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true
        ))
        let coordinator = HybridActivityCoordinator(
            engine: engine,
            store: store,
            almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
            inspector: inspector,
            clock: clock
        )
        coordinator.start()
        defer { coordinator.stop() }

        #expect(coordinator.isPopoverVisible == false)
        #expect(coordinator.isRecorderWindowVisible == false)

        inspector.currentSample = ActivitySample(
            timestamp: t0.addingTimeInterval(4), appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "UpdatedHidden.swift", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true
        )
        clock.advance(by: 4)
        coordinator.pollOnce()
        #expect(coordinator.latestSample?.windowTitle != "UpdatedHidden.swift")

        coordinator.setRecorderWindowVisible(true)
        #expect(coordinator.isRecorderWindowVisible == true)
        #expect(coordinator.latestSample?.windowTitle == "UpdatedHidden.swift")
        coordinator.setRecorderWindowVisible(false)
        #expect(coordinator.isRecorderWindowVisible == false)
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
        var isAccessibilityTrusted: Bool
        var currentSample: ActivitySample
        init(sample: ActivitySample, isAccessibilityTrusted: Bool = true) {
            self.isAccessibilityTrusted = isAccessibilityTrusted
            self.currentSample = sample
        }
        func inspectCurrent() -> ActivitySample { currentSample }
    }

    private final class MockScreenCapturer: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var currentImage: CGImage
        let isScreenCaptureTrusted: Bool

        init(image: CGImage, isScreenCaptureTrusted: Bool = true) {
            self.currentImage = image
            self.isScreenCaptureTrusted = isScreenCaptureTrusted
        }

        func requestScreenCapturePermission() -> Bool {
            isScreenCaptureTrusted
        }

        func captureMainDisplayImage() async throws -> CGImage {
            lock.withLock { currentImage }
        }
    }

    private func makeSyntheticTextImage(text: String, backgroundWhite: Bool, width: Int = 960, height: Int = 240) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        ctx.setFillColor(red: backgroundWhite ? 1 : 0.08, green: backgroundWhite ? 1 : 0.09, blue: backgroundWhite ? 1 : 0.12, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let fgColor = backgroundWhite ? CGColor(red: 0, green: 0, blue: 0, alpha: 1) : CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 1)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: fgColor]
        let attrString = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        ctx.textPosition = CGPoint(x: 40, y: 95)
        CTLineDraw(line, ctx)
        return try #require(ctx.makeImage())
    }
}
#endif


