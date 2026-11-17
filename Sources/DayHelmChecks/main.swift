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
            print("ALL DAYHELM CHECKS PASSED (18/18)")
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
    }
}
