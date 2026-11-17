import CoreGraphics
import CoreText
import ImageIO
import DayHelmCapture
import DayHelmCore
import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private func check(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw CheckFailure(description: message)
    }
}

private func checkEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) throws {
    if lhs != rhs {
        throw CheckFailure(description: "\(message) (got \(lhs), expected \(rhs))")
    }
}

private func checkApprox(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.001, _ message: String) throws {
    if abs(lhs - rhs) > tolerance {
        throw CheckFailure(description: "\(message) (got \(lhs), expected \(rhs) ± \(tolerance))")
    }
}

@main
struct DayHelmChecksMain {
    static func main() async {
        do {
            try await runAllChecks()
            print("ALL DAYHELM CHECKS PASSED (41/41)")
            exit(0)
        } catch {
            fputs("DAYHELM CHECK FAILED: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func baseDate() -> Date {
        DayHelmDateFormatting.parseISO8601("2026-11-17T09:00:00+08:00")!
    }

    private static func sampleBudgets() -> [TaskBudget] {
        [
            TaskBudget(taskId: "ecommerce", displayName: "电商做深", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["example-shop", "product-listing", "ecommerce"]),
            TaskBudget(taskId: "ecommerce-ops", displayName: "电商日常运营", colorHex: "#F59E0B", targetMinutes: nil, capMinutes: 30, keywords: ["support-ticket", "order-refund"]),
            TaskBudget(taskId: "hermes", displayName: "Hermes 投研", colorHex: "#10B981", targetMinutes: 45, capMinutes: 60, keywords: ["hermes", "equity-research"]),
            TaskBudget(taskId: "infra-billing", displayName: "Infra 维护", colorHex: "#8B5CF6", targetMinutes: nil, capMinutes: 30, keywords: ["terraform", "cloud-billing"])
        ]
    }

    private static func runCheck(_ name: String, _ block: () async throws -> Void) async throws {
        try await block()
        print("  [PASS] \(name)")
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

        init(isAccessibilityTrusted: Bool = true, currentSample: ActivitySample) {
            self.isAccessibilityTrusted = isAccessibilityTrusted
            self.currentSample = currentSample
        }

        func inspectCurrent() -> ActivitySample {
            currentSample
        }
    }

    private final class MockScreenCapturer: ScreenCapturing, @unchecked Sendable {
        private let lock = NSLock()
        private var currentImage: CGImage
        private var captureCount = 0
        let isScreenCaptureTrusted: Bool

        init(image: CGImage, isScreenCaptureTrusted: Bool = true) {
            self.currentImage = image
            self.isScreenCaptureTrusted = isScreenCaptureTrusted
        }

        var captures: Int {
            lock.withLock { captureCount }
        }

        func setImage(_ image: CGImage) {
            lock.withLock {
                currentImage = image
            }
        }

        func requestScreenCapturePermission() -> Bool {
            isScreenCaptureTrusted
        }

        func captureMainDisplayImage() async throws -> CGImage {
            lock.withLock {
                captureCount += 1
                return currentImage
            }
        }
    }

    private static func runAllChecks() async throws {
        try await runCheck("1. ManualClock deterministic advancement") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            try checkEqual(clock.now(), t0, "Initial clock time")
            clock.advance(by: 125)
            try checkEqual(clock.now(), t0.addingTimeInterval(125), "Clock advance")
        }

        try await runCheck("2. UTC+8 day formatting and ISO8601 round-trip") {
            let utcDate = DayHelmDateFormatting.parseISO8601("2026-11-16T16:30:00Z")!
            let day = DayHelmDateFormatting.dayString(from: utcDate, timeZone: DayHelmDateFormatting.shanghaiTimeZone)
            try checkEqual(day, "2026-11-17", "UTC+8 day rollover")
            let iso = DayHelmDateFormatting.iso8601String(from: utcDate, timeZone: DayHelmDateFormatting.shanghaiTimeZone)
            try checkEqual(iso, "2026-11-17T00:30:00+08:00", "ISO8601 +08:00 format")
        }

        try await runCheck("3. PrivacyRedactor password manager redaction") {
            let t0 = baseDate()
            for bundle in ["com.1password.1password", "com.bitwarden.desktop", "com.agilebits.onepassword7"] {
                let sample = ActivitySample(timestamp: t0, appName: "PwdApp", bundleId: bundle, windowTitle: "Secret", url: "https://example.com", idleSeconds: 0, screenLocked: false, inputActive: true)
                let out = PrivacyRedactor.redact(sample)
                try check(out.redacted && out.windowTitle == nil && out.url == nil, "Must redact \(bundle)")
                try checkEqual(out.appName, "PwdApp", "Must preserve appName")
                try checkEqual(out.bundleId, bundle, "Must preserve bundleId")
            }
        }

        try await runCheck("4. PrivacyRedactor banking/payment & medical/ID keywords") {
            let t0 = baseDate()
            let bank = ActivitySample(timestamp: t0, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Portal", url: "https://checkout.stripe.com/s/1", idleSeconds: 0, screenLocked: false, inputActive: true)
            try check(PrivacyRedactor.redact(bank).redacted, "Checkout/Stripe URL must redact")

            let med = ActivitySample(timestamp: t0, appName: "Preview", bundleId: "com.apple.Preview", windowTitle: "患者病历.pdf", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            try check(PrivacyRedactor.redact(med).redacted, "Medical title must redact")

            let safe = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "JSON Payload Schema", url: "https://docs.example.com/payload", idleSeconds: 0, screenLocked: false, inputActive: true)
            try check(!PrivacyRedactor.redact(safe).redacted, "Word 'payload' must not falsely trigger 'pay'")
        }

        try await runCheck("5. PrivacyRedactor private chat & system privacy settings") {
            let t0 = baseDate()
            let wechat = ActivitySample(timestamp: t0, appName: "WeChat", bundleId: "com.tencent.xinWeChat", windowTitle: "Chat", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            try check(PrivacyRedactor.redact(wechat).redacted, "WeChat redacted by default")
            let allowCfg = PrivacyRedactorConfig(redactWeChat: false, redactMessages: false)
            try check(!PrivacyRedactor.redact(wechat, config: allowCfg).redacted, "WeChat respects config toggle")

            let sysPrivacy = ActivitySample(timestamp: t0, appName: "System Settings", bundleId: "com.apple.systempreferences", windowTitle: "Privacy & Security", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            try check(PrivacyRedactor.redact(sysPrivacy).redacted, "Privacy settings must redact")

            let sysDisplays = ActivitySample(timestamp: t0, appName: "System Settings", bundleId: "com.apple.systempreferences", windowTitle: "Displays", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            try check(!PrivacyRedactor.redact(sysDisplays).redacted, "Displays settings should not redact")
        }

        try await runCheck("6. URL query parameter sanitizer") {
            let raw = "https://example.com/dashboard?tab=orders&token=1&key=2&session=3&sig=4&secret=5&password=6&auth=7&page=2"
            try checkEqual(PrivacyRedactor.sanitizeURL(raw), "https://example.com/dashboard?tab=orders&page=2", "Strip sensitive query params")
            try checkEqual(PrivacyRedactor.sanitizeURL("https://example.com/login?token=abc"), "https://example.com/login", "Drop empty query string")
        }

        try await runCheck("7. EventMerger pulsetime merging and splitting") {
            let t0 = baseDate()
            let s1 = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
            let s2 = ActivitySample(timestamp: t0.addingTimeInterval(30), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
            let s3 = ActivitySample(timestamp: t0.addingTimeInterval(55), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
            let s4 = ActivitySample(timestamp: t0.addingTimeInterval(130), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true)
            let spans = EventMerger.merge(samples: [s1, s2, s3, s4], declaredTaskId: "ecommerce", pulsetime: 60)
            try checkEqual(spans.count, 2, "Gap > 60s must split")
            try checkApprox(spans[0].durationSeconds, 55.0, "Merged span duration")
        }

        try await runCheck("8. SpectrumBuilder metrics and thrashing detection") {
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
            try check(result.segments.contains { if case .thrashing = $0.kind { return true }; return false }, "Must detect thrashing segment")
            try check(result.segments.contains { if case .idle = $0.kind { return true }; return false }, "Must detect idle segment")
            try checkEqual(result.metrics.solidBlocksCount, 1, "20m block counts as 1 solid block")
            try checkApprox(result.metrics.longestBlockMinutes, 20.0, tolerance: 0.5, "Longest block minutes")
        }

        try await runCheck("9. DayHelmEngine cross-app collaboration tolerance") {
            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce", note: "Listing prep", at: t0)
            for (i, app) in [("Chrome", "com.google.Chrome"), ("Finder", "com.apple.finder"), ("Preview", "com.apple.Preview"), ("Terminal", "com.apple.Terminal")].enumerated() {
                engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(Double(i + 1) * 300), appName: app.0, bundleId: app.1, windowTitle: "Work \(i)", url: nil, idleSeconds: 2, screenLocked: false, inputActive: true))
            }
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 20.0, "Cross-app active time accumulates")
        }

        try await runCheck("10. DayHelmEngine idle and screen lock auto-pause") {
            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce", at: t0)
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
            let idleTime = t0.addingTimeInterval(600)
            engine.ingest(ActivitySample(timestamp: idleTime, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: nil, idleSeconds: 300, screenLocked: false, inputActive: false))
            try checkEqual(engine.focusState, .paused(taskId: "ecommerce", pausedAt: idleTime), "Idle >= 300s pauses focus")
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 5.0, "Idle does not add time")

            let resume = t0.addingTimeInterval(900)
            engine.startFocus(taskId: "ecommerce", at: resume)
            let lockTime = resume.addingTimeInterval(120)
            engine.ingest(ActivitySample(timestamp: lockTime, appName: "loginwindow", bundleId: "com.apple.loginwindow", windowTitle: nil, url: nil, idleSeconds: 0, screenLocked: true, inputActive: false))
            try checkEqual(engine.focusState, .paused(taskId: "ecommerce", pausedAt: lockTime), "Screen lock pauses focus")
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 5.0, "Locked sample does not add time")
        }

        try await runCheck("11. DayHelmEngine quota target/cap & snooze") {
            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce-ops", at: t0)
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(26 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
            let progress26 = engine.taskProgress().first { $0.budget.taskId == "ecommerce-ops" }!
            try checkEqual(progress26.status, .approachingCap(remainingMinutes: 4.0), "85% cap warning")

            let capAlerts = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(31 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
            try check(capAlerts.contains { if case .quotaCapReached(taskId: "ecommerce-ops", _, cap: 30) = $0.kind { return true }; return false }, "Cap reached alert")

            engine.snoozeAlert(for: "ecommerce-ops", minutes: 15, at: t0.addingTimeInterval(31 * 60))
            let snoozed = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(40 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
            try check(!snoozed.contains { if case .quotaCapReached = $0.kind { return true }; return false }, "Snooze suppresses cap alert")

            let afterSnooze = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(47 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Support Ticket", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
            try check(afterSnooze.contains { if case .quotaCapReached = $0.kind { return true }; return false }, "Cap alert re-fires after snooze")

            let switchTime = t0.addingTimeInterval(50 * 60)
            engine.switchTask(to: "hermes", note: "Switched", at: switchTime)
            let targetAlerts = engine.ingest(ActivitySample(timestamp: switchTime.addingTimeInterval(46 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Research", url: nil, idleSeconds: 1, screenLocked: false, inputActive: true))
            try check(targetAlerts.contains { if case .quotaTargetMet(taskId: "hermes", _, target: 45) = $0.kind { return true }; return false }, "Target met alert")
        }

        try await runCheck("12. DayHelmEngine drift, unassigned prompt & high-frequency switch") {
            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.ingest(ActivitySample(timestamp: t0, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Docs", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            let unassigned10 = engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(10 * 60), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Docs", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            try check(unassigned10.contains { if case .unassignedActivePrompt = $0.kind { return true }; return false }, "Unassigned active >= 10m prompt")

            let focusStart = t0.addingTimeInterval(11 * 60)
            engine.startFocus(taskId: "ecommerce", at: focusStart)
            let driftStart = focusStart.addingTimeInterval(60)
            _ = engine.ingest(ActivitySample(timestamp: driftStart, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Equity Research", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            let drift4m = engine.ingest(ActivitySample(timestamp: driftStart.addingTimeInterval(240), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Equity Research", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            try check(drift4m.contains { if case .taskDrift(declaredTaskId: "ecommerce", detectedTaskId: "hermes", _) = $0.kind { return true }; return false }, "4m continuous drift alert")

            let thrashBase = driftStart.addingTimeInterval(300)
            var thrashAlerts: [SupervisorAlert] = []
            for i in 0..<12 {
                thrashAlerts.append(contentsOf: engine.ingest(ActivitySample(timestamp: thrashBase.addingTimeInterval(Double(i) * 20), appName: i % 2 == 0 ? "Chrome" : "Terminal", bundleId: i % 2 == 0 ? "com.google.Chrome" : "com.apple.Terminal", windowTitle: "Tab \(i)", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)))
            }
            try check(thrashAlerts.contains { if case .highFrequencySwitch = $0.kind { return true }; return false }, "High-frequency switch alert")
        }

        try await runCheck("13. TimeAuditConfigLoader fallback and synthetic parsing") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-cfg-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let defaults = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: tmpDir.appendingPathComponent("missing.json"))
            try checkEqual(defaults.count, 4, "Default budget count")

            let configJSON = #"{"projects":[{"name":"ecommerce","keywords":["synthetic-shop"]}]}"#
            let focusJSON = #"{"primary_focus":{"project_keys":["ecommerce"],"why":"ignored"}}"#
            try configJSON.write(to: tmpDir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
            try focusJSON.write(to: tmpDir.appendingPathComponent("focus.json"), atomically: true, encoding: .utf8)

            let loaded = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: nil)
            let ecom = loaded.first { $0.taskId == "ecommerce" }!
            try check(ecom.keywords.contains("synthetic-shop"), "Merged project keywords")
        }

        try await runCheck("14. DayHelmStore atomic write, rollover, and purge") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-store-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce", note: "Synthetic note", at: t0)
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(600), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            let snap = engine.snapshot(at: t0.addingTimeInterval(600))

            try store.saveToday(snap)
            try check(!FileManager.default.fileExists(atPath: tmpDir.appendingPathComponent("today.json.tmp").path), "No leftover tmp file")
            try checkEqual((try store.loadToday())?.date, "2026-11-17", "Reload today.json")

            let rolled = try store.rolloverIfNeeded(currentSnapshot: snap, newDateString: "2026-11-18")
            try check(rolled, "Rollover must archive previous day")
            try checkEqual((try store.loadDay(dateString: "2026-11-17"))?.date, "2026-11-17", "Archived day loadable")

            let oldSnap = DayHelmDaySnapshot(schemaVersion: 1, date: "2026-11-01", focusState: .unassigned, activeFocus: nil, budgets: [], focusSessions: [], enrichedSpans: [], metrics: DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0))
            try store.archiveDay(oldSnap)

            let partial = try store.purge(before: DayHelmDateFormatting.parseDayString("2026-11-10")!)
            try checkEqual(partial.deletedFiles, 1, "Purge before cutoff deletes only older day")
            try check((try store.loadDay(dateString: "2026-11-17")) != nil, "Newer day preserved")

            let full = try store.purge(before: nil)
            try check(full.deletedFiles >= 1 && full.deletedBytes > 0, "Full purge deletes remaining files")
            try check((try store.loadDay(dateString: "2026-11-17")) == nil, "All days deleted")
        }

        try await runCheck("15. AlmaActivityClient browser_visit tab URL splitting") {
            let parsed1 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/shop/itemtabExample Shop Dashboard")
            try checkEqual(parsed1.url, "https://example.com/shop/item", "Must strip concatenated tab title")
            try checkEqual(parsed1.tabTitle, "Example Shop Dashboard", "Must extract tab title")

            let parsed2 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/page\ntabLowercase Title")
            try checkEqual(parsed2.url, "https://example.com/page", "Must split on newline+tab")
            try checkEqual(parsed2.tabTitle, "Lowercase Title", "Must extract title after newline+tab")

            let parsed3 = AlmaActivityClient.parseBrowserVisitURL("https://example.com/dashboard?tab=orders&page=2")
            try checkEqual(parsed3.url, "https://example.com/dashboard?tab=orders&page=2", "Must preserve ?tab= query param")
            try check(parsed3.tabTitle == nil, "Must not falsely extract ?tab= query param")

            let parsed4 = AlmaActivityClient.parseBrowserVisitURL("https://tabs.example.com/table/view")
            try checkEqual(parsed4.url, "https://tabs.example.com/table/view", "Must preserve /table path")
            try check(parsed4.tabTitle == nil, "Must not falsely split /table path")
        }

        try await runCheck("16. AlmaActivityClient JSON parsing, sample reconstruction, and offline degradation") {
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
            let sessionsJSON = """
            [
              {
                "id": "sess_1",
                "startedAt": \(t0Ms),
                "endedAt": \(t0Ms + 180_000),
                "durationMs": 180000,
                "appNames": ["Editor", "Google Chrome"]
              }
            ]
            """.data(using: .utf8)!

            let detailJSON = """
            {
              "id": "sess_1",
              "startedAt": \(t0Ms),
              "endedAt": \(t0Ms + 180_000),
              "events": [
                {
                  "id": "ev_1",
                  "timestamp": \(t0Ms),
                  "kind": "app_focus",
                  "appName": "Editor",
                  "data": { "bundleId": "com.example.editor" }
                },
                {
                  "id": "ev_2",
                  "timestamp": \(t0Ms + 60_000),
                  "kind": "browser_visit",
                  "appName": "Google Chrome",
                  "data": {
                    "bundleId": "com.google.Chrome",
                    "url": "https://example.com/research?token=secret&q=1tabHermes Research Tab"
                  }
                },
                {
                  "id": "ev_3",
                  "timestamp": \(t0Ms + 120_000),
                  "kind": "keypress",
                  "appName": "Google Chrome",
                  "data": {}
                }
              ]
            }
            """.data(using: .utf8)!

            let mockTransport = MockAlmaTransport { url in
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                if url.path.hasSuffix("/sessions/sess_1") {
                    return (detailJSON, response)
                }
                if url.path.hasSuffix("/sessions") {
                    return (sessionsJSON, response)
                }
                throw URLError(.badURL)
            }

            let client = AlmaActivityClient(transport: mockTransport)
            let result = await client.fetchTodaySamples(dayStart: t0, dayEnd: t0.addingTimeInterval(3600))
            try check(result.connected, "Mock Alma client must report connected")
            try checkEqual(result.samples.count, 3, "Must reconstruct 3 chronological ActivitySamples")
            try checkEqual(result.samples[0].appName, "Editor", "First sample appName")
            try checkEqual(result.samples[1].url, "https://example.com/research?q=1", "Browser visit URL cleaned and sanitized")
            try checkEqual(result.samples[1].windowTitle, "Hermes Research Tab", "Browser visit tab title extracted")
            try checkEqual(result.samples[2].inputActive, true, "Keypress event marks inputActive")

            let offlineTransport = MockAlmaTransport { _ in
                throw URLError(.cannotConnectToHost)
            }
            let offlineClient = AlmaActivityClient(transport: offlineTransport)
            let offlineResult = await offlineClient.fetchTodaySamples(dayStart: t0, dayEnd: t0.addingTimeInterval(3600))
            try check(!offlineResult.connected, "Offline Alma client must report disconnected")
            try checkEqual(offlineResult.samples.count, 0, "Offline Alma client returns empty samples")
        }

        try await runCheck("17. HybridActivityCoordinator synthetic mode and user actions") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let sample = ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            let inspector = MockInspector(isAccessibilityTrusted: true, currentSample: sample)
            let coordinator = await MainActor.run {
                HybridActivityCoordinator.makeSyntheticDemo(clock: clock, inspector: inspector)
            }

            await MainActor.run {
                coordinator.selectTask("ecommerce", note: "Working on listing")
            }
            let state1 = await MainActor.run { coordinator.sessionState }
            if case .focusing(let taskId, _) = state1 {
                try checkEqual(taskId, "ecommerce", "selectTask switches to ecommerce")
            } else {
                throw CheckFailure(description: "Expected focusing state after selectTask")
            }

            await MainActor.run {
                coordinator.updateBudget(taskId: "ecommerce", targetMinutes: 100, capMinutes: 140)
            }
            let updatedBudget = await MainActor.run {
                coordinator.taskProgressList.first { $0.budget.taskId == "ecommerce" }?.budget
            }
            try checkEqual(updatedBudget?.targetMinutes, 100, "updateBudget updates targetMinutes")
            try checkEqual(updatedBudget?.capMinutes, 140, "updateBudget updates capMinutes")

            await MainActor.run {
                coordinator.triggerDemoAlert()
            }
            let hasAlert = await MainActor.run { coordinator.activeAlert != nil }
            try check(hasAlert, "triggerDemoAlert exposes activeAlert")

            await MainActor.run {
                coordinator.handleAlertAction(.pauseFocus(label: "休息"))
            }
            let state2 = await MainActor.run { coordinator.sessionState }
            if case .paused = state2 {
                // OK
            } else {
                throw CheckFailure(description: "Expected paused state after pauseFocus alert action")
            }
        }

        try await runCheck("18. DayHelmCLI status and purge commands") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-cli-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce", note: "Synthetic CLI check", at: t0)
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(600), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Example Doc", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(600)))

            let oldSnap = DayHelmDaySnapshot(schemaVersion: 1, date: "2026-10-15", focusState: .unassigned, activeFocus: nil, budgets: [], focusSessions: [], enrichedSpans: [], metrics: DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0))
            try store.archiveDay(oldSnap)

            let statusRes = DayHelmCLI.run(arguments: ["dayhelm", "status", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
            try check(statusRes != nil, "status subcommand handled")
            try checkEqual(statusRes?.exitCode, 0, "status exits 0")
            try check(statusRes?.stdout.contains("电商做深") == true, "status output includes task displayName")

            let purgePartial = DayHelmCLI.run(arguments: ["dayhelm", "purge", "--before", "2026-11-01", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
            try checkEqual(purgePartial?.exitCode, 0, "partial purge exits 0")
            try check(purgePartial?.stdout.contains("1") == true, "partial purge reports 1 deleted file")
            try check((try store.loadToday()) != nil, "partial purge keeps today.json")

            let purgeAll = DayHelmCLI.run(arguments: ["dayhelm", "purge", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
            try checkEqual(purgeAll?.exitCode, 0, "full purge exits 0")
            try check((try store.loadToday()) == nil, "full purge removes today.json")
        }

        try await runCheck("19. DayHelmEngine Task CRUD & delete active focused task") {
            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))

            // Add custom task
            let added = engine.addTask(
                displayName: "深度写作",
                colorHex: "#EC4899",
                targetMinutes: 50,
                capMinutes: 90,
                keywords: ["writing", "essay"]
            )
            try check(!added.taskId.isEmpty, "Generated taskId must not be empty")
            try checkEqual(engine.budgets.count, 5, "addTask appends new task")
            try checkEqual(engine.budgets.last?.displayName, "深度写作", "Added task displayName matches")

            // Update task
            let edited = TaskBudget(
                taskId: added.taskId,
                displayName: "深度写作 · 专栏",
                colorHex: "#06B6D4",
                targetMinutes: 60,
                capMinutes: 120,
                keywords: ["column", "draft"]
            )
            engine.updateTask(edited)
            let fetched = engine.budgets.first { $0.taskId == added.taskId }
            try checkEqual(fetched?.displayName, "深度写作 · 专栏", "updateTask updates displayName")
            try checkEqual(fetched?.colorHex, "#06B6D4", "updateTask updates colorHex")
            try checkEqual(fetched?.targetMinutes, 60, "updateTask updates targetMinutes")
            try checkEqual(fetched?.capMinutes, 120, "updateTask updates capMinutes")
            try checkEqual(fetched?.keywords, ["column", "draft"], "updateTask updates keywords")

            // Reorder task (move last item index 4 to index 0)
            engine.moveTask(fromOffsets: IndexSet(integer: 4), toOffset: 0)
            try checkEqual(engine.budgets.first?.taskId, added.taskId, "moveTask reorders budgets")

            // Focus on the added task, advance 10m, then delete while focusing
            engine.startFocus(taskId: added.taskId, at: t0)
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(600), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Draft", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            engine.deleteTask(taskId: added.taskId)
            try checkEqual(engine.budgets.count, 4, "deleteTask removes task")
            try check(!engine.budgets.contains { $0.taskId == added.taskId }, "Deleted task absent from budgets")
            try checkEqual(engine.focusState, .unassigned, "Deleting active focused task stops focus to unassigned")

            // Delete while paused
            engine.startFocus(taskId: "hermes", at: t0.addingTimeInterval(700))
            engine.pauseFocus(at: t0.addingTimeInterval(800))
            engine.deleteTask(taskId: "hermes")
            try checkEqual(engine.focusState, .unassigned, "Deleting paused task resets focusState to unassigned")
        }

        try await runCheck("20. TimeAuditConfigLoader respects config.json truth & HybridActivityCoordinator CRUD persistence") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-crud-\(UUID().uuidString)")
            let timeAuditDir = tmpDir.appendingPathComponent("time-audit", isDirectory: true)
            let storeDir = tmpDir.appendingPathComponent("dayhelm", isDirectory: true)
            try FileManager.default.createDirectory(at: timeAuditDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            // Seed time-audit config with project keys that user will delete/not include
            try #"{"projects":[{"name":"ecommerce","keywords":["from-ta"]}]}"#.write(
                to: timeAuditDir.appendingPathComponent("config.json"),
                atomically: true,
                encoding: .utf8
            )
            try #"{"primary_focus":{"project_keys":["ecommerce","legacy-ta-task"]}}"#.write(
                to: timeAuditDir.appendingPathComponent("focus.json"),
                atomically: true,
                encoding: .utf8
            )

            let store = DayHelmStore(directory: storeDir)
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let inspector = MockInspector(isAccessibilityTrusted: true, currentSample: ActivitySample(timestamp: t0, appName: "Editor", bundleId: "com.example.editor", windowTitle: "Work", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))

            let coordinator = await MainActor.run { () -> HybridActivityCoordinator in
                let initialBudgets = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: timeAuditDir, dayhelmConfigURL: store.configURL)
                let engine = DayHelmEngine(budgets: initialBudgets, clock: clock)
                return HybridActivityCoordinator(engine: engine, store: store, almaClient: nil, inspector: inspector, clock: clock, syntheticDemo: false)
            }

            let created = await MainActor.run { () -> TaskBudget in
                let added = coordinator.addTask(
                    displayName: "独立开发",
                    colorHex: "#10B981",
                    targetMinutes: 90,
                    capMinutes: 150,
                    keywords: ["xcode", "swift"]
                )
                coordinator.deleteTask(taskId: "legacy-ta-task")
                coordinator.deleteTask(taskId: "ecommerce-ops")
                coordinator.updateTask(TaskBudget(
                    taskId: added.taskId,
                    displayName: "独立开发 · Swift",
                    colorHex: "#3B82F6",
                    targetMinutes: 120,
                    capMinutes: 180,
                    keywords: ["swiftpm"]
                ))
                return added
            }

            // Reload from DayHelm config.json + same time-audit dir: must preserve exact user-customized list
            let reloaded = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: timeAuditDir, dayhelmConfigURL: store.configURL)
            try check(!reloaded.contains { $0.taskId == "legacy-ta-task" }, "Deleted time-audit task must NOT come back once config.json exists")
            try check(!reloaded.contains { $0.taskId == "ecommerce-ops" }, "Deleted default task must NOT come back once config.json exists")
            let custom = reloaded.first { $0.taskId == created.taskId }
            try checkEqual(custom?.displayName, "独立开发 · Swift", "Reloaded custom task displayName matches")
            try checkEqual(custom?.colorHex, "#3B82F6", "Reloaded custom task colorHex matches")
            try checkEqual(custom?.targetMinutes, 120, "Reloaded custom task targetMinutes matches")
            try checkEqual(custom?.capMinutes, 180, "Reloaded custom task capMinutes matches")
            try checkEqual(custom?.keywords, ["swiftpm"], "Reloaded custom task keywords matches")

            let ecommerceReloaded = reloaded.first { $0.taskId == "ecommerce" }
            try check(ecommerceReloaded?.keywords.contains("from-ta") == true, "Initial seed still carries keywords before edits")
        }

        try await runCheck("21. ActivityDatabase SQLite schema, session lifecycle, auto-summary & Alma-compatible detail") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-db-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let dbURL = tmpDir.appendingPathComponent("activity.sqlite")
            let db = try ActivityDatabase(databaseURL: dbURL)
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
            try checkEqual(e1.url, "https://shop.example.com/orders?page=2", "insertEvent sanitizes sensitive URL query params")
            try checkEqual(e1.windowTitle, "Example Shop Dashboard", "insertEvent populates windowTitle")

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
            _ = try db.insertOCRFrame(
                snapshotId: snap1.id,
                sessionId: e1.sessionId,
                text: "Order fulfillment metrics and SKU inventory review",
                createdAtMs: t0Ms + 15_000
            )

            // Lock event closes current session; later event beyond idle gap starts a new session
            _ = try db.insertEvent(timestampMs: t0Ms + 45_000, kind: "lock", appName: "loginwindow")
            let e3 = try db.insertEvent(
                timestampMs: t0Ms + 200_000,
                kind: "app_focus",
                appName: "Terminal",
                windowTitle: "swift test — focus-guard",
                declaredTaskId: "infra-billing"
            )
            try check(e3.sessionId != e1.sessionId, "Session splits after lock / idle gap")

            let sessions = try db.listSessions(sinceMs: t0Ms - 1000, untilMs: t0Ms + 300_000, limit: 10)
            try checkEqual(sessions.count, 2, "listSessions returns both sessions")

            let detail = try db.getSessionDetail(sessionId: e1.sessionId)
            try check(detail != nil, "getSessionDetail returns populated detail")
            try checkEqual(detail?.session.declaredTaskId, "ecommerce", "Session carries declaredTaskId")
            try checkEqual(detail?.session.eventCount, 2, "Session counts events accurately")
            try checkEqual(detail?.session.snapshotCount, 1, "Session counts snapshots accurately")
            try check(detail?.session.analysisTitle?.contains("Google Chrome") == true, "Session synthesizes analysisTitle")
            try checkEqual(detail?.ocrFrames.count, 1, "Session detail includes OCR frames")

            // Verify Alma-compatible JSON keys decode into AlmaSession / AlmaEvent
            let enc = DayHelmDateFormatting.makeEncoder()
            let dec = DayHelmDateFormatting.makeDecoder()
            let sessData = try enc.encode(detail!.session)
            let almaSess = try dec.decode(AlmaSession.self, from: sessData)
            try checkEqual(almaSess.id, e1.sessionId, "AlmaSession decodes RecordedSessionSummary JSON")
            let evtData = try enc.encode(e1)
            let almaEvt = try dec.decode(AlmaEvent.self, from: evtData)
            try checkEqual(almaEvt.kind, "app_focus", "AlmaEvent decodes RecordedActivityEvent JSON")
        }

        try await runCheck("22. ActivityDatabase search & queryAgentContext across titles, URLs & OCR") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-search-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

            let ev = try db.insertEvent(
                timestampMs: t0Ms,
                kind: "browser_visit",
                appName: "Google Chrome",
                windowTitle: "Hermes Semiconductor Note",
                url: "https://research.example.com/semiconductor-q4",
                declaredTaskId: "hermes"
            )
            let snap = try db.insertSnapshot(
                sessionId: ev.sessionId,
                timestampMs: t0Ms + 5_000,
                filePath: tmpDir.appendingPathComponent("snap.jpg").path,
                width: 800,
                height: 600,
                sizeBytes: 10_000,
                appName: "Google Chrome",
                windowTitle: "Hermes Semiconductor Note"
            )
            _ = try db.insertOCRFrame(
                snapshotId: snap.id,
                sessionId: ev.sessionId,
                text: "Quarterly wafer fab utilization reached 92% in Q4.",
                createdAtMs: t0Ms + 5_000
            )

            let ocrHits = try db.search(keyword: "wafer fab", limit: 10)
            try check(ocrHits.contains { $0.sourceKind == "ocr" && $0.sessionId == ev.sessionId }, "search finds OCR frame hit")

            let urlHits = try db.search(keyword: "semiconductor-q4", limit: 10)
            try check(urlHits.contains { $0.sourceKind == "event" && $0.url?.contains("semiconductor-q4") == true }, "search finds URL event hit")

            let ctx = try db.queryAgentContext(sinceMs: t0Ms - 1000, untilMs: t0Ms + 60_000, maxOCRChars: 500)
            try checkEqual(ctx.sessionCount, 1, "queryAgentContext counts sessions")
            try checkEqual(ctx.ocrFrameCount, 1, "queryAgentContext counts OCR frames")
            try check(ctx.recentWindows.contains { $0.windowTitle == "Hermes Semiconductor Note" }, "queryAgentContext includes recent windows")
            try check(ctx.ocrHighlights.contains { $0.text.contains("wafer fab") }, "queryAgentContext includes OCR highlights")
        }

        try await runCheck("23. ImageHistogram, perceptual hash & VisionOCRService on synthetic CoreText CGImage") {
            let whiteImg = try makeSyntheticTextImage(text: "DayHelm OCR 2026", backgroundWhite: true)
            let sameImg = try makeSyntheticTextImage(text: "DayHelm OCR 2026", backgroundWhite: true)
            let darkImg = try makeSyntheticTextImage(text: "Completely Different Screen", backgroundWhite: false)

            let h1 = ImageHistogram.computeHistogram(from: whiteImg, bins: 32)
            let h2 = ImageHistogram.computeHistogram(from: sameImg, bins: 32)
            let hDark = ImageHistogram.computeHistogram(from: darkImg, bins: 32)

            try checkEqual(h1.count, 32, "Histogram has 32 bins")
            try checkApprox(ImageHistogram.histogramDistance(from: h1, to: h2), 0.0, tolerance: 0.001, "Identical images have 0 histogram distance")
            try check(ImageHistogram.histogramDistance(from: h1, to: hDark) > 0.5, "Light vs dark images have large histogram distance")

            let hash1 = ImageHistogram.computePerceptualHashHex(from: whiteImg)
            let hash2 = ImageHistogram.computePerceptualHashHex(from: sameImg)
            try checkEqual(hash1.count, 16, "Perceptual hash is 16 hex chars")
            try checkEqual(hash1, hash2, "Identical images yield identical perceptual hash")

            let ocr = try await VisionOCRService.recognizeText(from: whiteImg)
            try check(ocr.text.contains("DayHelm") || ocr.text.contains("2026"), "Vision OCR extracts text from synthetic CGImage (got: '\(ocr.text)')")
            try check(ocr.charCount > 0 && ocr.tokenCount > 0, "OCR reports positive charCount and tokenCount")
        }

        try await runCheck("24. DayHelmCLI query, search, sessions & partial purge with SQLite + JSON") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-cli-hub-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce", at: t0)
            engine.ingest(ActivitySample(timestamp: t0.addingTimeInterval(300), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Catalog Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            try store.saveToday(engine.snapshot(at: t0.addingTimeInterval(300)))

            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            let ev = try db.insertEvent(
                timestampMs: t0Ms + 60_000,
                kind: "app_focus",
                appName: "Editor",
                windowTitle: "Catalog Spec",
                url: "https://docs.example.com/catalog",
                declaredTaskId: "ecommerce"
            )
            let snap = try db.insertSnapshot(
                sessionId: ev.sessionId,
                timestampMs: t0Ms + 65_000,
                filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/s1.jpg").path,
                width: 640,
                height: 360,
                sizeBytes: 4096,
                appName: "Editor",
                windowTitle: "Catalog Spec"
            )
            _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Spring SKU pricing matrix", createdAtMs: t0Ms + 65_000)

            let queryJSON = DayHelmCLI.run(arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0.addingTimeInterval(300)))
            try checkEqual(queryJSON?.exitCode, 0, "query --format json exits 0")
            try check(queryJSON?.stdout.contains("Spring SKU pricing matrix") == true, "query json includes OCR highlights")
            try check(queryJSON?.stdout.contains("Catalog Spec") == true, "query json includes recent window titles")

            let queryMD = DayHelmCLI.run(arguments: ["dayhelm", "query", "--since", "2h", "--format", "md", "--store-dir", tmpDir.path], clock: ManualClock(now: t0.addingTimeInterval(300)))
            try checkEqual(queryMD?.exitCode, 0, "query --since 2h --format md exits 0")
            try check(queryMD?.stdout.contains("电商做深") == true, "query md includes active focus task displayName")

            let searchRes = DayHelmCLI.run(arguments: ["dayhelm", "search", "SKU pricing", "--limit", "5", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
            try checkEqual(searchRes?.exitCode, 0, "search exits 0")
            try check(searchRes?.stdout.contains("Spring SKU pricing matrix") == true, "search json returns matching OCR snippet")

            let sessionsRes = DayHelmCLI.run(arguments: ["dayhelm", "sessions", "--date", "2026-11-17", "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
            try checkEqual(sessionsRes?.exitCode, 0, "sessions --date exits 0")
            try check(sessionsRes?.stdout.contains(ev.sessionId) == true, "sessions lists recorded session ID")

            let sessionDetailRes = DayHelmCLI.run(arguments: ["dayhelm", "sessions", "--id", ev.sessionId, "--format", "json", "--store-dir", tmpDir.path], clock: ManualClock(now: t0))
            try checkEqual(sessionDetailRes?.exitCode, 0, "sessions --id exits 0")
            try check(sessionDetailRes?.stdout.contains("https://docs.example.com/catalog") == true, "sessions --id returns session events")
        }

        try await runCheck("25. LocalActivityHTTPServer TCP loopback endpoints (/status, /sessions, /context)") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-http-\(UUID().uuidString)")
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
            let ev = try db.insertEvent(
                timestampMs: t0Ms + 10_000,
                kind: "app_focus",
                appName: "Preview",
                windowTitle: "Earnings Call.pdf",
                declaredTaskId: "hermes"
            )
            let snap = try db.insertSnapshot(
                sessionId: ev.sessionId,
                timestampMs: t0Ms + 12_000,
                filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/p1.jpg").path,
                width: 1024,
                height: 768,
                sizeBytes: 8192,
                appName: "Preview",
                windowTitle: "Earnings Call.pdf"
            )
            _ = try db.insertOCRFrame(snapshotId: snap.id, sessionId: ev.sessionId, text: "Revenue guidance raised by 14%", createdAtMs: t0Ms + 12_000)

            let server = LocalActivityHTTPServer(
                database: db,
                store: store,
                clock: ManualClock(now: t0.addingTimeInterval(120)),
                stateProvider: {
                    LocalActivityHTTPServer.RuntimeState(
                        axTrusted: true,
                        screenCaptureTrusted: true,
                        deepRecordingEnabled: true,
                        daySnapshot: daySnap
                    )
                }
            )
            try checkEqual(LocalActivityHTTPServer.defaultPrimaryPort, 24001, "Default primary port is 24001 (in 2400x range)")
            try check(!LocalActivityHTTPServer.defaultPortCandidates.contains(23001), "Port candidates never include Alma's 23001 port")
            try check(LocalActivityHTTPServer.defaultPortCandidates.allSatisfy { (24001...24009).contains($0) }, "Port candidates stay within 24001...24009")

            let ports = await server.start(primaryPort: 0, fallbackPort: nil)
            defer { server.stop() }
            guard let port = ports.first else {
                throw CheckFailure(description: "LocalActivityHTTPServer failed to bind ephemeral loopback port")
            }

            let session = URLSession(configuration: .ephemeral)
            let dec = DayHelmDateFormatting.makeDecoder()

            // 1. /api/activity-recorder/status
            let (statusData, statusResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/status")!)
            try checkEqual((statusResp as? HTTPURLResponse)?.statusCode, 200, "GET /status returns HTTP 200")
            let statusObj = try dec.decode(LocalRecorderStatusSnapshot.self, from: statusData)
            try checkEqual(statusObj.source, "dayhelm", "Status source is dayhelm")
            try checkEqual(statusObj.todayOCRFrames, 1, "Status reports todayOCRFrames")

            // 2. /api/activity-recorder/sessions
            let (listData, listResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions?limit=10")!)
            try checkEqual((listResp as? HTTPURLResponse)?.statusCode, 200, "GET /sessions returns HTTP 200")
            let listText = String(data: listData, encoding: .utf8) ?? ""
            try check(listText.contains(ev.sessionId), "GET /sessions includes recorded session")

            // 3. /api/activity-recorder/sessions/<id>
            let (detailData, detailResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/\(ev.sessionId)")!)
            try checkEqual((detailResp as? HTTPURLResponse)?.statusCode, 200, "GET /sessions/<id> returns HTTP 200")
            let detailObj = try dec.decode(RecordedSessionDetail.self, from: detailData)
            try checkEqual(detailObj.session.declaredTaskId, "hermes", "HTTP detail preserves declaredTaskId")
            try checkEqual(detailObj.events.first?.windowTitle, "Earnings Call.pdf", "HTTP detail preserves windowTitle")
            try checkEqual(detailObj.ocrFrames.count, 1, "HTTP detail preserves ocrFrames")

            // 4. Missing session -> 404
            let (_, missingResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/nonexistent-id")!)
            try checkEqual((missingResp as? HTTPURLResponse)?.statusCode, 404, "Missing session returns HTTP 404")

            // 5. /api/dayhelm/context
            let (ctxData, ctxResp) = try await session.data(from: URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!)
            try checkEqual((ctxResp as? HTTPURLResponse)?.statusCode, 200, "GET /api/dayhelm/context returns HTTP 200")
            let ctxObj = try dec.decode(DayHelmContextAPIResponse.self, from: ctxData)
            try checkEqual(ctxObj.activeFocus?.taskId, "hermes", "Context includes activeFocus taskId")
            try check(ctxObj.activity.ocrHighlights.contains { $0.text.contains("Revenue guidance") }, "Context includes OCR highlights")
        }

        try await runCheck("26. NativeScreenRecorder privacy guard, visual deduplication, settings & snapshot retention prune") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-rec-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let t0 = baseDate()
            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            let recorder = NativeScreenRecorder(
                database: db,
                snapshotsRootDir: store.snapshotsDirectory,
                clock: ManualClock(now: t0)
            )

            let imgA = try makeSyntheticTextImage(text: "Product Spec Alpha 2026", backgroundWhite: true)
            let imgB = try makeSyntheticTextImage(text: "Night Console View", backgroundWhite: false)

            // 1. Privacy guard: redacted sample NEVER captures or saves OCR/JPEG
            let redactedSample = PrivacyRedactor.redact(ActivitySample(
                timestamp: t0,
                appName: "1Password",
                bundleId: "com.1password.1password",
                windowTitle: "Vault Secrets",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
            let savedRedacted = try await recorder.processCapturedImage(imgA, sample: redactedSample, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
            try checkEqual(savedRedacted, false, "Redacted sample NEVER saves snapshot or runs OCR")

            // 2. Screen locked sample NEVER captures
            let lockedSample = ActivitySample(timestamp: t0.addingTimeInterval(5), appName: "loginwindow", bundleId: "com.apple.loginwindow", windowTitle: nil, url: nil, idleSeconds: 0, screenLocked: true, inputActive: false)
            let savedLocked = try await recorder.processCapturedImage(imgA, sample: lockedSample, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
            try checkEqual(savedLocked, false, "Locked sample NEVER saves snapshot or runs OCR")

            // 3. Normal sample saves JPEG + OCR
            let normal1 = ActivitySample(timestamp: t0.addingTimeInterval(10), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Product Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            let saved1 = try await recorder.processCapturedImage(imgA, sample: normal1, trigger: "heartbeat", declaredTaskId: "ecommerce", runOCR: true)
            try checkEqual(saved1, true, "Normal sample saves first snapshot + OCR")

            // 4. Visual deduplication skips identical image within heartbeat interval
            let normal2 = ActivitySample(timestamp: t0.addingTimeInterval(25), appName: "Editor", bundleId: "com.example.editor", windowTitle: "Product Spec", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            let saved2 = try await recorder.processCapturedImage(imgA, sample: normal2, trigger: "visual_change", declaredTaskId: "ecommerce", runOCR: true)
            try checkEqual(saved2, false, "Visual deduplication skips identical frame (<4% diff)")

            // 5. Visual change (>=4% diff) saves new JPEG
            let normal3 = ActivitySample(timestamp: t0.addingTimeInterval(40), appName: "Terminal", bundleId: "com.apple.Terminal", windowTitle: "Console", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            let saved3 = try await recorder.processCapturedImage(imgB, sample: normal3, trigger: "visual_change", declaredTaskId: "infra-billing", runOCR: true)
            try checkEqual(saved3, true, "Significant visual change saves new snapshot")

            let dayStartMs = Int64(t0.addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
            let counts = try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayStartMs + 86_400_000)
            try checkEqual(counts.snapshots, 2, "Only 2 non-deduplicated snapshots recorded in SQLite")
            try check(counts.ocrFrames >= 1, "OCR frame recorded in SQLite for normal capture")

            // 6. DayHelmSettings persistence alongside budgets
            try store.saveBudgets(sampleBudgets())
            try store.saveSettings(DayHelmSettings(deepRecordingEnabled: false, snapshotRetentionDays: 14))
            let loadedSettings = store.loadSettings()
            try checkEqual(loadedSettings.deepRecordingEnabled, false, "Settings persist deepRecordingEnabled")
            try checkEqual(loadedSettings.snapshotRetentionDays, 14, "Settings persist snapshotRetentionDays")
            let loadedBudgets = TimeAuditConfigLoader.loadBudgets(timeAuditDirectory: tmpDir, dayhelmConfigURL: store.configURL)
            try checkEqual(loadedBudgets.count, 4, "Saving settings preserves budgets in config.json")

            // 7. Old snapshot JPEG retention pruning removes JPEG files older than N days while keeping SQLite OCR searchable
            let oldSnapDir = store.snapshotsDirectory.appendingPathComponent("2026-10-01", isDirectory: true)
            try FileManager.default.createDirectory(at: oldSnapDir, withIntermediateDirectories: true)
            let oldJPEG = oldSnapDir.appendingPathComponent("old.jpg")
            try Data("fake-jpeg".utf8).write(to: oldJPEG)
            let pruned = try db.pruneOldSnapshots(olderThanDays: 7, snapshotsRootDir: store.snapshotsDirectory, now: t0)
            try checkEqual(pruned.deletedFiles, 1, "pruneOldSnapshots deletes old snapshot day directory JPEGs")
            try check(!FileManager.default.fileExists(atPath: oldJPEG.path), "Old JPEG removed from disk")
            let ocrStillSearchable = try db.search(keyword: "Product Spec", limit: 10)
            try check(!ocrStillSearchable.isEmpty, "OCR & metadata remain searchable after pruning")
        }

        try await runCheck("27. Full-day E2E coordinator pipeline (morning to midnight rollover)") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-e2e-\(UUID().uuidString)")
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
                isAccessibilityTrusted: true,
                currentSample: ActivitySample(
                    timestamp: t0,
                    appName: "Xcode",
                    bundleId: "com.apple.dt.Xcode",
                    windowTitle: "DayHelmEngine.swift — focus-guard",
                    url: nil,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
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
            guard let port = ports.first else {
                throw CheckFailure(description: "Failed to bind ephemeral port for E2E HTTP server")
            }

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
            try check(after1Pass.0?.redacted == true, "1Password sample must be redacted")
            try check(after1Pass.0?.windowTitle == nil && after1Pass.0?.url == nil, "1Password title and url must be stripped")
            try checkEqual(after1Pass.1, 2, "1Password must trigger 0 new snapshots")

            // 09:45: Chrome sample + snapshot #3 + OCR #3 (with sensitive query param sanitized)
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
                try checkEqual(alertedTask, customTask.taskId, "targetMet fires for custom task at 60m")
            } else {
                throw CheckFailure(description: "Expected quotaTargetMet alert at 60m, got \(String(describing: alert1000))")
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
            try checkApprox(customProgress?.focusedMinutes ?? 0, 65.0, "Custom task accumulates 65m across Xcode/Terminal/Chrome")

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
                throw CheckFailure(description: "Expected quotaCapReached for ecommerce-ops at 10:35, got \(String(describing: capAlert))")
            }

            // User snoozes 15m via coordinator.handleAlertAction
            await MainActor.run {
                coordinator.handleAlertAction(.snooze(minutes: 15, label: "+15m 收尾"))
            }
            try check(await MainActor.run { coordinator.activeAlert == nil }, "Alert clears immediately after snooze action")

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
            try check(await MainActor.run { coordinator.activeAlert == nil }, "Alert remains suppressed during 15m snooze")

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
                throw CheckFailure(description: "Expected quotaCapReached to re-arm after 15m snooze")
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
            try checkEqual((ctxResp as? HTTPURLResponse)?.statusCode, 200, "HTTP /api/dayhelm/context returns 200")
            let ctx = try dec.decode(DayHelmContextAPIResponse.self, from: ctxData)
            let httpCustomBudget = ctx.budgets.first { $0.taskId == customTask.taskId }
            let httpOpsBudget = ctx.budgets.first { $0.taskId == "ecommerce-ops" }
            try checkApprox(httpCustomBudget?.focusedMinutes ?? 0, 65.0, "HTTP context returns exact 65m for custom task")
            try checkApprox(httpOpsBudget?.focusedMinutes ?? 0, 55.0, "HTTP context returns exact 55m for ecommerce-ops")
            try check(ctx.activity.sessionCount >= 1, "HTTP context includes recorded sessions")
            try check(ctx.activity.recentWindows.contains { $0.windowTitle == "DayHelmEngine.swift — focus-guard" }, "HTTP context includes Xcode window title")
            try check(ctx.activity.recentWindows.contains { $0.windowTitle == "Swift Concurrency Docs" }, "HTTP context includes Chrome window title")
            try check(!ctx.activity.recentWindows.contains { ($0.windowTitle ?? "").contains("Vault Master Password") }, "HTTP context excludes redacted 1Password title")
            try check(ctx.activity.ocrHighlights.contains { $0.text.contains("Terminal") || $0.text.contains("Xcode") || $0.text.contains("Concurrency") }, "HTTP context includes Vision OCR highlights")

            let (sessData, sessResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions")!)
            try checkEqual((sessResp as? HTTPURLResponse)?.statusCode, 200, "HTTP /api/activity-recorder/sessions returns 200")
            let sessJSON = String(data: sessData, encoding: .utf8) ?? ""
            try check(sessJSON.contains(ctx.activity.sessions[0].id), "HTTP /sessions lists recorded session id")

            let cliResult = DayHelmCLI.run(
                arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path],
                clock: clock
            )
            try checkEqual(cliResult?.exitCode, 0, "CLI query --today --format json exits 0")
            let cliOut = cliResult?.stdout ?? ""
            try check(cliOut.contains(customTask.taskId), "CLI query includes custom taskId")
            try check(cliOut.contains("DayHelmEngine.swift — focus-guard"), "CLI query includes Xcode window title")
            try check(cliOut.contains("Swift Concurrency Docs"), "CLI query includes Chrome window title")
            try check(!cliOut.contains("Vault Master Password"), "CLI query excludes redacted 1Password title")
            try check(cliOut.contains("Concurrency") || cliOut.contains("Terminal") || cliOut.contains("DayHelmEngine"), "CLI query includes OCR text")

            let cliJSONObj = try JSONSerialization.jsonObject(with: Data(cliOut.utf8)) as? [String: Any]
            let cliBudgets = cliJSONObj?["budgets"] as? [[String: Any]] ?? []
            let cliCustomMinutes = cliBudgets.first { ($0["taskId"] as? String) == customTask.taskId }?["focusedMinutes"] as? Double
            try checkApprox(cliCustomMinutes ?? 0, 65.0, "CLI query JSON has exact 65m for custom task")

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
            try check(FileManager.default.fileExists(atPath: archivedURL.path), "Rollover archives days/2026-11-17.json on disk")
            let archivedSnap = try store.loadDay(dateString: "2026-11-17")
            try checkApprox(archivedSnap?.budgets.first { $0.taskId == customTask.taskId }?.focusedMinutes ?? 0, 65.0, "Archived day preserves 65m custom task time")

            let nextDayProgress = await MainActor.run { coordinator.taskProgressList }
            try check(nextDayProgress.allSatisfy { $0.focusedMinutes == 0 }, "All task counters reset to 0 on 2026-11-18")
            try checkEqual(await MainActor.run { coordinator.sessionState }, .unassigned, "Focus state resets to unassigned after rollover")
            try checkEqual((try store.loadToday())?.date, "2026-11-18", "today.json reflects 2026-11-18 after rollover")
        }

        try await runCheck("28. alma-time-audit contract compatibility E2E test") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-alma-contract-\(UUID().uuidString)")
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
            guard let port = ports.first else {
                throw CheckFailure(description: "Failed to bind ephemeral port for Alma contract check")
            }

            let urlSession = URLSession(configuration: .ephemeral)

            // 1. /api/activity-recorder/status
            let (statusData, statusResp) = try await urlSession.data(from: URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/status")!)
            try checkEqual((statusResp as? HTTPURLResponse)?.statusCode, 200, "Contract status returns 200")
            let statusJSON = try JSONSerialization.jsonObject(with: statusData) as? [String: Any]
            try check(isJSONBoolean(statusJSON?["running"]), "status.running must be Bool")
            try checkEqual(statusJSON?["running"] as? Bool, true, "status.running must be true")

            // 2. /api/activity-recorder/sessions?limit=2000&since=...&until=...
            let sinceMs = t0Ms - 60_000
            let untilMs = t0Ms + 300_000
            let listURL = URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions?limit=2000&since=\(sinceMs)&until=\(untilMs)")!
            let (listData, listResp) = try await urlSession.data(from: listURL)
            try checkEqual((listResp as? HTTPURLResponse)?.statusCode, 200, "Contract sessions list returns 200")
            let listJSON = try JSONSerialization.jsonObject(with: listData) as? [String: Any]
            let sessions = listJSON?["sessions"] as? [[String: Any]]
            try checkEqual(sessions?.count, 1, "Contract sessions list returns 1 session")
            let s0 = sessions![0]
            try check(s0["id"] is String, "sessions[].id must be String")
            try check(isJSONInteger(s0["startedAt"]), "sessions[].startedAt must be Int64")
            try check(isJSONInteger(s0["endedAt"]), "sessions[].endedAt must be Int64")
            try check(isJSONInteger(s0["durationMs"]), "sessions[].durationMs must be Int64")
            try check(s0["appNames"] is [String], "sessions[].appNames must be [String]")
            try check(s0["analysisStatus"] is String, "sessions[].analysisStatus must be String")
            try check(s0["analysisTitle"] is String, "sessions[].analysisTitle must be String")
            try check(s0["analysisDescription"] is String, "sessions[].analysisDescription must be String")
            try check(s0["project"] is String, "sessions[].project must be String")
            try check(s0["highlights"] is [String], "sessions[].highlights must be [String]")

            // 3. /api/activity-recorder/sessions/<id>
            let detailURL = URL(string: "http://127.0.0.1:\(port)/api/activity-recorder/sessions/\(e1.sessionId)")!
            let (detailData, detailResp) = try await urlSession.data(from: detailURL)
            try checkEqual((detailResp as? HTTPURLResponse)?.statusCode, 200, "Contract session detail returns 200")
            let detailJSON = try JSONSerialization.jsonObject(with: detailData) as? [String: Any]
            let events = detailJSON?["events"] as? [[String: Any]]
            try checkEqual(events?.count, 1, "Detail returns 1 event")
            let ev0 = events![0]
            try check(ev0["kind"] is String, "events[].kind must be String")
            try check(isJSONInteger(ev0["timestamp"]), "events[].timestamp must be Int64")
            try check(ev0["appName"] is String, "events[].appName must be String")
            try check(ev0["data"] is [String: Any], "events[].data must be JSON object")

            let snapshots = detailJSON?["snapshots"] as? [[String: Any]]
            try checkEqual(snapshots?.count, 1, "Detail returns 1 snapshot")
            let snap0 = snapshots![0]
            try check(snap0["trigger"] is String, "snapshots[].trigger must be String")
            try check(snap0["appName"] is String, "snapshots[].appName must be String")
            try check(snap0["windowTitle"] is String, "snapshots[].windowTitle must be String")
        }

        try await runCheck("29. Subprocess binary E2E test (DayHelmApp CLI & exit codes)") {
            let appBinary = try resolveDayHelmAppExecutableURL()
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-proc-\(UUID().uuidString)")
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

            // 1. --help
            let helpProc = try runProcess(executableURL: appBinary, arguments: ["--help"])
            try checkEqual(helpProc.exitCode, 0, "DayHelmApp --help exits 0")
            try check(helpProc.stdout.contains("Usage:") && helpProc.stdout.contains("dayhelm"), "--help prints usage output")

            // 2. status --store-dir
            let statusProc = try runProcess(executableURL: appBinary, arguments: ["status", "--store-dir", tmpDir.path])
            try checkEqual(statusProc.exitCode, 0, "DayHelmApp status exits 0")
            try check(statusProc.stdout.contains("DayHelm Status") && statusProc.stdout.contains("Daily Budgets:") && statusProc.stdout.contains("电商做深"), "status prints formatted budget summary")

            // 3. query --today --format md --store-dir
            let queryProc = try runProcess(executableURL: appBinary, arguments: ["query", "--today", "--format", "md", "--store-dir", tmpDir.path])
            try checkEqual(queryProc.exitCode, 0, "DayHelmApp query --today --format md exits 0")
            try check(queryProc.stdout.contains("# DayHelm Activity Context") && queryProc.stdout.contains("keyword"), "query md includes activity context and keyword")

            // 4. search "keyword" --store-dir
            let searchProc = try runProcess(executableURL: appBinary, arguments: ["search", "keyword", "--store-dir", tmpDir.path])
            try checkEqual(searchProc.exitCode, 0, "DayHelmApp search exits 0")
            try check(searchProc.stdout.contains("# DayHelm Search") && searchProc.stdout.contains("keyword"), "search prints matching hits")

            // 5. purge --store-dir
            let purgeProc = try runProcess(executableURL: appBinary, arguments: ["purge", "--store-dir", tmpDir.path])
            try checkEqual(purgeProc.exitCode, 0, "DayHelmApp purge exits 0")
            try check(purgeProc.stdout.contains("DayHelm purge completed"), "purge prints completion summary")
            try check(!FileManager.default.fileExists(atPath: store.todayURL.path), "purge deletes today.json")
            try check(!FileManager.default.fileExists(atPath: store.databaseURL.path), "purge deletes activity.sqlite")

            // 6. unknown-flag -> non-zero exit code
            let unknownProc = try runProcess(executableURL: appBinary, arguments: ["unknown-flag"])
            try check(unknownProc.exitCode != 0, "DayHelmApp unknown-flag exits non-zero")
            try check(!unknownProc.stderr.isEmpty, "DayHelmApp unknown-flag writes error to stderr")
        }

        try await runCheck("30. Concurrent SQLite reader/writer stress E2E test (WAL mode)") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-stress-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)

            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            engine.startFocus(taskId: "ecommerce", at: t0)
            let daySnap = engine.snapshot(at: t0.addingTimeInterval(600))
            try store.saveToday(daySnap)

            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            try checkEqual(try db.journalMode().lowercased(), "wal", "ActivityDatabase must run in WAL journal mode")

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
            guard let port = ports.first else {
                throw CheckFailure(description: "Failed to bind ephemeral port for SQLite stress check")
            }

            let contextURL = URL(string: "http://127.0.0.1:\(port)/api/dayhelm/context")!
            let urlSession = URLSession(configuration: .ephemeral)
            let dec = DayHelmDateFormatting.makeDecoder()

            try await withThrowingTaskGroup(of: Void.self) { group in
                // Writer 1: 50 rapid AX event writes
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

                // Writer 2: 25 background snapshot + OCR frame writes
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

                // Reader 1: 25 concurrent HTTP /api/dayhelm/context reads
                group.addTask {
                    for _ in 0..<25 {
                        let (data, resp) = try await urlSession.data(from: contextURL)
                        try checkEqual((resp as? HTTPURLResponse)?.statusCode, 200, "Concurrent HTTP context read returns 200")
                        _ = try dec.decode(DayHelmContextAPIResponse.self, from: data)
                        try await Task.sleep(nanoseconds: 3_000_000)
                    }
                }

                // Reader 2: 15 concurrent DayHelmCLI queries (opening separate SQLite connections)
                group.addTask {
                    for _ in 0..<15 {
                        let res = DayHelmCLI.run(
                            arguments: ["dayhelm", "query", "--today", "--format", "json", "--store-dir", tmpDir.path],
                            clock: ManualClock(now: t0.addingTimeInterval(600))
                        )
                        try checkEqual(res?.exitCode, 0, "Concurrent CLI query exits 0 without SQLITE_BUSY")
                        try await Task.sleep(nanoseconds: 4_000_000)
                    }
                }

                try await group.waitForAll()
            }

            let counts = try db.todayCounts(dayStartMs: t0Ms - 1000, dayEndMs: t0Ms + 86_400_000)
            try checkEqual(counts.events, 50, "All 50 concurrent events persisted without loss")
            try checkEqual(counts.snapshots, 25, "All 25 concurrent snapshots persisted without loss")
            try checkEqual(counts.ocrFrames, 25, "All 25 concurrent OCR frames persisted without loss")
            try checkEqual(try db.integrityCheck().lowercased(), "ok", "SQLite PRAGMA integrity_check reports ok")
            try checkEqual((try db.search(keyword: "StressOCR", limit: 50)).count, 25, "All 25 OCR frames remain searchable")
        }

        try await runCheck("31. ActivityClassifier distinguishes browser_visit from file:// app_focus") {
            try checkEqual(
                ActivityClassifier.eventKind(appName: "Google Chrome", bundleId: "com.google.Chrome", url: "https://shop.example.com/orders", redacted: false),
                "browser_visit",
                "Chrome + https => browser_visit"
            )
            try checkEqual(
                ActivityClassifier.eventKind(appName: "Preview", bundleId: "com.apple.Preview", url: "file:///Users/me/Earnings%20Call.pdf", redacted: false),
                "app_focus",
                "Preview + file:// => app_focus (not browser_visit)"
            )
            try checkEqual(
                ActivityClassifier.eventKind(appName: "Xcode", bundleId: "com.apple.dt.Xcode", url: "file:///Users/me/project.xcodeproj", redacted: false),
                "app_focus",
                "Xcode + file:// => app_focus"
            )
            try checkEqual(
                ActivityClassifier.eventKind(appName: "Google Chrome", bundleId: "com.google.Chrome", url: "https://secret.example.com", redacted: true),
                "app_focus",
                "Redacted samples never become browser_visit"
            )
            try checkEqual(
                ActivityClassifier.eventKind(appName: "Terminal", bundleId: "com.apple.Terminal", url: nil, redacted: false),
                "app_focus",
                "No URL => app_focus"
            )
            try checkEqual(
                ActivityClassifier.normalizedURLKey("https://Shop.Example.com/a?b=1#frag"),
                "https://shop.example.com/a?b=1",
                "URL change key drops fragment and lowercases scheme/host"
            )
        }

        try await runCheck("32. ActivityTextNormalizer suppresses title jitter but keeps semantic changes") {
            let inboxA = "Inbox (3) — Gmail"
            let inboxB = "Inbox (12) — Gmail"
            try checkEqual(
                ActivityTextNormalizer.normalizedTitleKey(inboxA),
                ActivityTextNormalizer.normalizedTitleKey(inboxB),
                "Unread counters normalize to the same key"
            )
            try check(ActivityTextNormalizer.isVolatileOnlyChange(previous: inboxA, current: inboxB), "Unread counter change is volatile-only")

            let progressA = "Uploading… 45%"
            let progressB = "Uploading… 87%"
            try checkEqual(
                ActivityTextNormalizer.normalizedTitleKey(progressA),
                ActivityTextNormalizer.normalizedTitleKey(progressB),
                "Progress percentage / ellipsis normalize to the same key"
            )

            let clockA = "Standup 14:52"
            let clockB = "Standup 09:03"
            try checkEqual(
                ActivityTextNormalizer.normalizedTitleKey(clockA),
                ActivityTextNormalizer.normalizedTitleKey(clockB),
                "Clocks normalize to the same key"
            )

            let alpha = "Product Spec Alpha"
            let beta = "Product Spec Beta"
            try check(
                ActivityTextNormalizer.normalizedTitleKey(alpha) != ActivityTextNormalizer.normalizedTitleKey(beta),
                "Word changes must produce different keys"
            )
            try check(!ActivityTextNormalizer.isVolatileOnlyChange(previous: alpha, current: beta), "Word change is not volatile-only")
        }

        try await runCheck("33. Credential redaction for metadata, URLs and OCR text") {
            let rawKeyText = "export API_KEY=sk-abcdefghijklmnop1234567890"
            let maskedKey = PrivacyRedactor.redactSecrets(in: rawKeyText)
            try check(!maskedKey.contains("sk-abcdefghijklmnop1234567890"), "sk- token must be masked (got: \(maskedKey))")
            try check(maskedKey.contains("***"), "Masked key keeps a *** marker")

            let rawJWT = "Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
            let maskedJWT = PrivacyRedactor.redactSecrets(in: rawJWT)
            try check(!maskedJWT.contains("eyJhbGciOiJIUzI1NiJ9"), "JWT payload must be masked")

            let rawPassword = "password=hunter2 token: abcdef123456"
            let maskedPassword = PrivacyRedactor.redactSecrets(in: rawPassword)
            try check(!maskedPassword.contains("hunter2"), "password value must be masked")
            try check(!maskedPassword.contains("abcdef123456"), "token value must be masked")

            try checkEqual(
                PrivacyRedactor.sanitizeMetadataValue("https://shop.example.com/orders?token=secret123&page=2"),
                "https://shop.example.com/orders?page=2",
                "Metadata URL values drop credential query params"
            )

            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-secret-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
            let t0Ms = Int64(baseDate().timeIntervalSince1970 * 1000)
            let ev = try db.insertEvent(
                timestampMs: t0Ms,
                kind: "app_focus",
                appName: "Terminal",
                windowTitle: "session token: abcdef123456",
                data: ["note": "Authorization: Bearer abcdefghijklmnop", "url": "https://api.example.com/v1?token=secret123"]
            )
            try checkEqual(ev.windowTitle?.contains("abcdef123456"), false, "insertEvent redacts windowTitle tokens")
            try checkEqual(ev.data["url"], "https://api.example.com/v1", "insertEvent sanitizes data URL params")
            try checkEqual(ev.data["note"]?.contains("abcdefghijklmnop"), false, "insertEvent redacts data credentials")

            let snap = try db.insertSnapshot(
                sessionId: ev.sessionId,
                timestampMs: t0Ms + 1_000,
                filePath: tmpDir.appendingPathComponent("s.jpg").path,
                width: 10,
                height: 10,
                sizeBytes: 1,
                appName: "Terminal",
                windowTitle: "token: abcdef123456"
            )
            let ocr = try db.insertOCRFrame(
                snapshotId: snap.id,
                sessionId: ev.sessionId,
                text: "password=hunter2 and token: abcdef123456",
                createdAtMs: t0Ms + 1_000
            )
            try check(!ocr.text.contains("hunter2"), "insertOCRFrame masks password value")
            try check(!ocr.text.contains("abcdef123456"), "insertOCRFrame masks token value")
        }

        try await runCheck("34. Idle closes sessions at last activity and structured tags are populated") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-idle-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
            let db = try ActivityDatabase(databaseURL: store.databaseURL)

            let ev = try db.insertEvent(
                timestampMs: t0Ms,
                kind: "browser_visit",
                appName: "Google Chrome",
                windowTitle: "Shop Orders",
                url: "https://shop.example.com/orders?page=2",
                declaredTaskId: "ecommerce",
                project: "ecommerce"
            )
            _ = try db.insertEvent(
                timestampMs: t0Ms + 3_000,
                kind: "app_focus",
                appName: "Google Chrome",
                windowTitle: "Shop Orders",
                url: "https://shop.example.com/orders?page=2",
                declaredTaskId: "ecommerce"
            )

            try check(try db.currentOpenSessionId() != nil, "Session is open while active")
            try db.closeActiveSessionAtLastActivity()
            try check(try db.currentOpenSessionId() == nil, "closeActiveSessionAtLastActivity closes the open session")

            guard let detail = try db.getSessionDetail(sessionId: ev.sessionId) else {
                throw CheckFailure(description: "Missing session detail after idle close")
            }
            try checkEqual(detail.session.endedAt, t0Ms + 3_000, "ended_at uses last observed activity, not idle time")
            try checkEqual(detail.session.durationMs, 3_000, "duration excludes idle tail")
            try check(detail.session.topics.contains("ecommerce"), "topics include declared task")
            try check(detail.session.topics.contains("Google Chrome"), "topics include frequent app")
            try check(detail.session.topics.contains("shop.example.com"), "topics include web domain")
            try checkEqual(detail.session.entities["domain"], ["shop.example.com"], "entities.domain groups web domains")
            try checkEqual(detail.session.entities["app"], ["Google Chrome"], "entities.app groups apps")
            try check(detail.session.entities["task"] == ["ecommerce"], "entities.task carries declared task")
            try check(!detail.session.highlights.isEmpty, "highlights contain headline windows")
        }

        try await runCheck("35. AlmaActivityClient consumes local /api/activity-recorder API end-to-end") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-alma-api-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
            let db = try ActivityDatabase(databaseURL: store.databaseURL)

            let ev = try db.insertEvent(
                timestampMs: t0Ms,
                kind: "browser_visit",
                appName: "Google Chrome",
                windowTitle: "Q4 Research Note",
                url: "https://research.example.com/q4",
                data: ["bundleId": "com.google.Chrome"],
                declaredTaskId: "hermes"
            )
            let server = LocalActivityHTTPServer(database: db, store: store, clock: ManualClock(now: t0))
            let ports = await server.start(primaryPort: 0, fallbackPort: nil)
            defer { server.stop() }
            guard let port = ports.first else {
                throw CheckFailure(description: "Failed to bind HTTP port for Alma compatibility check")
            }

            let client = AlmaActivityClient(
                baseURL: URL(string: "http://127.0.0.1:\(port)")!,
                transport: URLSessionAlmaTransport(timeoutInterval: 3.0)
            )
            let sessions = try await client.fetchSessions(sinceMs: t0Ms - 1_000, untilMs: t0Ms + 60_000)
            try checkEqual(sessions.count, 1, "Alma client decodes exactly one session from local API")
            try checkEqual(sessions.first?.id, ev.sessionId, "Alma client session id matches")
            try checkEqual(sessions.first?.appNames ?? [], ["Google Chrome"], "Alma client decodes appNames")

            let events = try await client.fetchSessionEvents(sessionId: ev.sessionId)
            try checkEqual(events.count, 1, "Alma client decodes embedded session events")
            try checkEqual(events.first?.kind, "browser_visit", "Alma client decodes event kind")

            let eventsRoute = server.handleRawHTTPRequestLineAndRoute(
                target: "/api/activity-recorder/sessions/\(ev.sessionId)/events"
            )
            try checkEqual(eventsRoute.statusCode, 200, "GET /sessions/<id>/events returns 200")
            let eventsJSON = String(data: eventsRoute.body, encoding: .utf8) ?? ""
            try check(eventsJSON.contains("\"events\"") && eventsJSON.contains("\"total\""), "Events endpoint returns {events,total}")
        }

        try await runCheck("36. app_focus / click / typing_pause all de-duplicate and idle never captures") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-triggers-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            let imgA = try makeSyntheticTextImage(text: "Alpha Screen 2026", backgroundWhite: true)
            let imgB = try makeSyntheticTextImage(text: "Beta Screen 2026", backgroundWhite: false)
            let capturer = MockScreenCapturer(image: imgA, isScreenCaptureTrusted: true)
            let recorder = NativeScreenRecorder(
                database: db,
                snapshotsRootDir: store.snapshotsDirectory,
                capturer: capturer,
                clock: ManualClock(now: t0)
            )

            func sample(_ offset: TimeInterval, idle: TimeInterval = 0) -> ActivitySample {
                ActivitySample(
                    timestamp: t0.addingTimeInterval(offset),
                    appName: "Editor",
                    bundleId: "com.example.editor",
                    windowTitle: "Doc",
                    url: nil,
                    idleSeconds: idle,
                    screenLocked: false,
                    inputActive: idle < 300
                )
            }

            let first = try await recorder.processCapturedImage(imgA, sample: sample(0), trigger: "app_focus", declaredTaskId: nil, runOCR: false)
            try check(first, "First app_focus frame is saved")
            let dupFocus = try await recorder.processCapturedImage(imgA, sample: sample(5), trigger: "app_focus", declaredTaskId: nil, runOCR: false)
            try check(!dupFocus, "app_focus with identical pixels is de-duplicated")
            let dupClick = try await recorder.processCapturedImage(imgA, sample: sample(10), trigger: "click", declaredTaskId: nil, runOCR: false)
            try check(!dupClick, "click with identical pixels is de-duplicated")
            let changedClick = try await recorder.processCapturedImage(imgB, sample: sample(20), trigger: "click", declaredTaskId: nil, runOCR: false)
            try check(changedClick, "click with a visual change is saved")
            let dupTyping = try await recorder.processCapturedImage(imgB, sample: sample(30), trigger: "typing_pause", declaredTaskId: nil, runOCR: false)
            try check(!dupTyping, "typing_pause with identical pixels is de-duplicated")

            let before = capturer.captures
            recorder.triggerAppFocusCaptureIfNeeded(sample: sample(40, idle: 400), deepRecordingEnabled: true, declaredTaskId: nil, idleThresholdSeconds: 300)
            recorder.triggerClickCaptureIfNeeded(sample: sample(40, idle: 400), deepRecordingEnabled: true, declaredTaskId: nil, idleThresholdSeconds: 300)
            recorder.triggerTypingPauseCaptureIfNeeded(sample: sample(40, idle: 400), deepRecordingEnabled: true, declaredTaskId: nil, idleThresholdSeconds: 300)
            recorder.evaluatePeriodicCaptureIfNeeded(sample: sample(40, idle: 400), deepRecordingEnabled: true, declaredTaskId: nil, idleThresholdSeconds: 300, retentionDays: 7)
            try await Task.sleep(nanoseconds: 80_000_000)
            try checkEqual(capturer.captures, before, "Idle samples must never capture screenshots")
        }

        try await runCheck("37. Old snapshots are downsampled before final retention pruning") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-downsample-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            let img = try makeSyntheticTextImage(text: "Downsample Target 2026", backgroundWhite: true, width: 960, height: 240)
            let recorder = NativeScreenRecorder(
                database: db,
                snapshotsRootDir: store.snapshotsDirectory,
                clock: ManualClock(now: t0)
            )
            let sample = ActivitySample(
                timestamp: t0,
                appName: "Editor",
                bundleId: "com.example.editor",
                windowTitle: "Doc",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            )
            let saved = try await recorder.processCapturedImage(img, sample: sample, trigger: "app_focus", declaredTaskId: "ecommerce", runOCR: false)
            try check(saved, "Initial snapshot is saved before downsampling")
            guard let sessionId = try db.currentOpenSessionId(),
                  let beforeDetail = try db.getSessionDetail(sessionId: sessionId),
                  let snapBefore = beforeDetail.snapshots.first else {
                throw CheckFailure(description: "Missing snapshot before downsampling")
            }
            try checkEqual(snapBefore.width, 960, "Original snapshot keeps full width")
            try checkEqual(snapBefore.storageTier, "hot", "Fresh snapshot is hot tier")

            let result = await recorder.downsampleOldSnapshots(
                olderThanDays: 1,
                retentionDays: 7,
                maxWidth: 480,
                quality: 0.4,
                now: t0.addingTimeInterval(3 * 86_400)
            )
            try checkEqual(result.downsampled, 1, "Exactly one old snapshot is downsampled")

            guard let afterDetail = try db.getSessionDetail(sessionId: sessionId),
                  let snapAfter = afterDetail.snapshots.first else {
                throw CheckFailure(description: "Missing snapshot after downsampling")
            }
            try check(snapAfter.width <= 480, "Downsampled snapshot width <= 480 (got \(snapAfter.width))")
            try checkEqual(snapAfter.storageTier, "downsampled", "Downsampled snapshot tier is recorded")
            try check(snapAfter.sizeBytes < snapBefore.sizeBytes, "Downsampling reduces stored bytes")
            try check(FileManager.default.fileExists(atPath: snapAfter.filePath), "Downsampled JPEG still exists on disk")

            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: snapAfter.filePath) as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = props[kCGImagePropertyPixelWidth] as? Int else {
                throw CheckFailure(description: "Unable to read downsampled JPEG properties")
            }
            try check(width <= 480, "JPEG on disk is actually <= 480px wide (got \(width))")
        }

        try await runCheck("38. Session and day summaries expose click/keypress input density") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-density-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
            let db = try ActivityDatabase(databaseURL: store.databaseURL)

            let focus = try db.insertEvent(
                timestampMs: t0Ms,
                kind: "app_focus",
                appName: "Google Chrome",
                windowTitle: "Orders",
                declaredTaskId: "ecommerce"
            )
            for i in 0..<3 {
                _ = try db.insertEvent(timestampMs: t0Ms + Int64(i) * 5_000 + 1_000, kind: "click", appName: "Google Chrome")
            }
            for i in 0..<2 {
                _ = try db.insertEvent(timestampMs: t0Ms + 30_000 + Int64(i) * 2_000, kind: "keypress", appName: "Google Chrome")
            }
            try db.closeSession(sessionId: focus.sessionId, endedAtMs: t0Ms + 60_000)

            let summary = try db.getSessionDetail(sessionId: focus.sessionId)?.session
            try checkEqual(summary?.clickCount ?? -1, 3, "Session clickCount aggregates click events")
            try checkEqual(summary?.keypressCount ?? -1, 2, "Session keypressCount aggregates keypress events")
            try checkApprox(summary?.inputEventsPerMinute ?? -1, 5.0, tolerance: 0.001, "Session input density = 5 events/min")

            let totals = try db.dayInputTotals(dayStartMs: t0Ms, dayEndMs: t0Ms + 86_400_000 - 1)
            try checkEqual(totals.clickCount, 3, "Day input totals aggregate clicks")
            try checkEqual(totals.keypressCount, 2, "Day input totals aggregate keypresses")
            try checkApprox(totals.inputEventsPerMinute, 5.0, tolerance: 0.001, "Day input density = 5 events/min")

            let daily = try db.dailySummaryStats(dateKey: "2026-11-17")
            try checkEqual(daily.sessionCount, 1, "Daily summary counts the session")
            try checkEqual(daily.clickCount, 3, "Daily summary carries click density metadata")
            try checkEqual(daily.hours.count, 24, "Daily summary exposes 24 hour buckets")
        }

        try await runCheck("39. HTTP keyword search, ocr alias, and DayHelm rich search") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-searchapi-\(UUID().uuidString)")
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
                declaredTaskId: "hermes"
            )
            let snap = try db.insertSnapshot(
                sessionId: event.sessionId,
                timestampMs: t0Ms + 1_000,
                filePath: store.snapshotsDirectory.appendingPathComponent("2026-11-17/wafer.jpg").path,
                width: 100,
                height: 60,
                sizeBytes: 4_096,
                trigger: "app_focus",
                appName: "Google Chrome",
                windowTitle: "Wafer Fab Report"
            )
            _ = try db.insertOCRFrame(
                snapshotId: snap.id,
                sessionId: event.sessionId,
                text: "Wafer fab utilization reached 92% in Q4",
                createdAtMs: t0Ms + 1_000
            )

            let server = LocalActivityHTTPServer(database: db, store: store, clock: ManualClock(now: t0))

            let detail = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/sessions/\(event.sessionId)")
            let detailJSON = try JSONSerialization.jsonObject(with: detail.body) as? [String: Any]
            let ocrAlias = detailJSON?["ocr"] as? [[String: Any]]
            let ocrFrames = detailJSON?["ocrFrames"] as? [[String: Any]]
            try checkEqual(ocrAlias?.count, 1, "Session detail exposes Alma-compatible ocr key")
            try checkEqual(ocrFrames?.count, 1, "Session detail still exposes ocrFrames")

            let keyword = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/search/keyword?q=wafer&limit=10")
            try checkEqual(keyword.statusCode, 200, "Keyword search returns 200")
            let keywordJSON = try JSONSerialization.jsonObject(with: keyword.body) as? [String: Any]
            let results = keywordJSON?["results"] as? [[String: Any]]
            try checkEqual(results?.count, 1, "Keyword search returns one OCR hit")
            try checkEqual(results?.first?["snapshotId"] as? String, snap.id, "Keyword hit carries snapshotId")

            let empty = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/search/keyword?q=")
            let emptyJSON = try JSONSerialization.jsonObject(with: empty.body) as? [String: Any]
            try checkEqual((emptyJSON?["results"] as? [[String: Any]])?.count, 0, "Empty keyword returns empty results")

            let rich = server.handleRawHTTPRequestLineAndRoute(target: "/api/dayhelm/search?q=wafer&limit=10")
            let richJSON = try JSONSerialization.jsonObject(with: rich.body) as? [String: Any]
            let hits = richJSON?["hits"] as? [[String: Any]] ?? []
            try check(hits.contains { $0["sourceKind"] as? String == "ocr" }, "Rich search includes OCR hits")
            try check(hits.contains { $0["sourceKind"] as? String == "event" }, "Rich search includes event hits")
        }

        try await runCheck("40. HTTP daily and weekly summaries follow the Alma activity_summaries contract") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-summaryapi-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
            let db = try ActivityDatabase(databaseURL: store.databaseURL)

            let event = try db.insertEvent(timestampMs: t0Ms, kind: "app_focus", appName: "Google Chrome", windowTitle: "Orders", declaredTaskId: "ecommerce")
            _ = try db.insertEvent(timestampMs: t0Ms + 10_000, kind: "click", appName: "Google Chrome")
            try db.closeSession(sessionId: event.sessionId, endedAtMs: t0Ms + 120_000)

            let server = LocalActivityHTTPServer(database: db, store: store, clock: ManualClock(now: t0.addingTimeInterval(600)))

            let daily = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/summary/daily/2026-11-17")
            try checkEqual(daily.statusCode, 200, "Daily summary returns 200")
            let dailyJSON = try JSONSerialization.jsonObject(with: daily.body) as? [String: Any]
            try checkEqual(dailyJSON?["kind"] as? String, "daily", "Daily summary kind is daily")
            try check(dailyJSON?["summary"] is NSNull, "Daily summary row keeps summary null (no LLM)")
            try check(dailyJSON?["isPartial"] as? Bool == true, "Today's daily summary is partial")
            let stats = dailyJSON?["stats"] as? [String: Any]
            try checkEqual(stats?["sessionCount"] as? Int, 1, "Daily stats sessionCount")
            try checkEqual(stats?["totalActiveMs"] as? Int, 120_000, "Daily stats totalActiveMs")
            try checkEqual(stats?["clickCount"] as? Int, 1, "Daily stats carry click density")
            try check((stats?["apps"] as? [[String: Any]])?.isEmpty == false, "Daily stats list per-app durations")

            let weekly = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/summary/weekly/2026-11-17")
            try checkEqual(weekly.statusCode, 200, "Weekly summary returns 200")
            let weeklyJSON = try JSONSerialization.jsonObject(with: weekly.body) as? [String: Any]
            let weeklyStats = weeklyJSON?["stats"] as? [String: Any]
            try checkEqual(weeklyStats?["weekKey"] as? String, "2026-W47", "Weekly summary resolves ISO week key")
            try checkEqual(weeklyStats?["startDate"] as? String, "2026-11-16", "Weekly summary start date is Monday")
            try checkEqual(weeklyStats?["endDate"] as? String, "2026-11-22", "Weekly summary end date is Sunday")
            try checkEqual((weeklyStats?["daily"] as? [[String: Any]])?.count, 7, "Weekly summary has seven daily slices")

            let invalid = server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/summary/weekly/not-a-week")
            try checkEqual(invalid.statusCode, 400, "Invalid week key returns 400")
        }

        try await runCheck("41. HTTP snapshot-file containment and CLI status --json density") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-snapfile-\(UUID().uuidString)")
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

            let event = try db.insertEvent(timestampMs: t0Ms, kind: "app_focus", appName: "Google Chrome")
            let snap = try db.insertSnapshot(
                sessionId: event.sessionId,
                timestampMs: t0Ms + 1_000,
                filePath: storedFile.path,
                width: 4,
                height: 4,
                sizeBytes: Int64(jpegBytes.count),
                trigger: "app_focus",
                appName: "Google Chrome"
            )
            _ = try db.insertEvent(sessionId: event.sessionId, timestampMs: t0Ms + 5_000, kind: "click", appName: "Google Chrome")
            _ = try db.insertEvent(sessionId: event.sessionId, timestampMs: t0Ms + 9_000, kind: "keypress", appName: "Google Chrome")

            let server = LocalActivityHTTPServer(database: db, store: store, clock: ManualClock(now: t0))
            let ports = await server.start(primaryPort: 0, fallbackPort: nil)
            defer { server.stop() }
            guard let port = ports.first else {
                throw CheckFailure(description: "Failed to bind HTTP port for snapshot-file check")
            }
            let urlSession = URLSession(configuration: .ephemeral)

            func fetchSnapshot(_ query: String) async throws -> (Data, HTTPURLResponse) {
                var components = URLComponents(string: "http://127.0.0.1:\(port)/api/activity-recorder/snapshot-file")!
                components.query = query.isEmpty ? nil : query
                let (data, response) = try await urlSession.data(from: components.url!)
                guard let http = response as? HTTPURLResponse else {
                    throw CheckFailure(description: "Missing HTTP response for snapshot-file")
                }
                return (data, http)
            }

            let byPath = try await fetchSnapshot("path=\(storedFile.path)")
            try checkEqual(byPath.1.statusCode, 200, "snapshot-file by path returns 200")
            try check(byPath.1.value(forHTTPHeaderField: "Content-Type")?.contains("image/jpeg") == true, "snapshot-file sends image/jpeg")
            try check(byPath.0 == jpegBytes, "snapshot-file returns raw JPEG bytes")

            let byId = try await fetchSnapshot("id=\(snap.id)")
            try checkEqual(byId.1.statusCode, 200, "snapshot-file by id returns 200")

            let forbidden = try await fetchSnapshot("path=\(outsideFile.path)")
            try checkEqual(forbidden.1.statusCode, 403, "snapshot-file rejects paths outside snapshots dir")

            let missing = try await fetchSnapshot("path=\(snapshotDir.appendingPathComponent("missing.jpg").path)")
            try checkEqual(missing.1.statusCode, 404, "snapshot-file reports missing file as 404")

            let statusResult = DayHelmCLI.run(
                arguments: ["dayhelm", "status", "--format", "json", "--store-dir", tmpDir.path],
                clock: ManualClock(now: t0)
            )
            guard let result = statusResult, result.exitCode == 0 else {
                throw CheckFailure(description: "dayhelm status --format json must exit 0")
            }
            let payload = try JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any]
            let recorder = payload?["recorder"] as? [String: Any]
            try checkEqual(recorder?["clickCount"] as? Int, 1, "CLI status json reports clickCount")
            try checkEqual(recorder?["keypressCount"] as? Int, 1, "CLI status json reports keypressCount")
        }
    }

    private static func waitUntil(
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
        throw CheckFailure(description: "Timed out waiting for: \(description)")
    }

    private static func isJSONBoolean(_ value: Any?) -> Bool {
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) == CFBooleanGetTypeID()
    }

    private static func isJSONInteger(_ value: Any?) -> Bool {
        guard let num = value as? NSNumber else { return false }
        return CFGetTypeID(num) != CFBooleanGetTypeID()
    }

    private static func resolveDayHelmAppExecutableURL() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []

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

        // Build DayHelmApp on demand if invoked without prior `swift build`
        let buildProc = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/swift"),
            arguments: ["build", "--product", "DayHelmApp"],
            currentDirectoryURL: repoRoot,
            timeoutSeconds: 60.0
        )
        guard buildProc.exitCode == 0 else {
            throw CheckFailure(description: "Failed to build DayHelmApp: \(buildProc.stderr)")
        }

        for url in candidates where fm.isExecutableFile(atPath: url.path) {
            return url
        }
        throw CheckFailure(description: "Unable to locate compiled DayHelmApp executable")
    }

    private static func runProcess(
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
            throw CheckFailure(description: "Process timed out after \(timeoutSeconds)s: \(executableURL.lastPathComponent) \(arguments.joined(separator: " "))")
        }

        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private static func makeSyntheticTextImage(text: String, backgroundWhite: Bool, width: Int = 960, height: Int = 240) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CheckFailure(description: "Failed to create CGContext for synthetic OCR image")
        }

        if backgroundWhite {
            ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        } else {
            ctx.setFillColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1)
        }
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 48, nil)
        let fgColor = backgroundWhite
            ? CGColor(red: 0, green: 0, blue: 0, alpha: 1)
            : CGColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: fgColor
        ]
        let attrString = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)
        ctx.textPosition = CGPoint(x: 40, y: 95)
        CTLineDraw(line, ctx)

        guard let cgImage = ctx.makeImage() else {
            throw CheckFailure(description: "Failed to finalize synthetic CGImage")
        }
        return cgImage
    }
}
