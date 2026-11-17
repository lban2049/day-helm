import CoreGraphics
import CoreText
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
#endif
