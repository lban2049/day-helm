import CoreGraphics
import CoreText
import ImageIO
import DayHelmCapture
import DayHelmCore
import Foundation
import SQLite3

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
            print("ALL DAYHELM CHECKS PASSED (71/71)")
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

    private final class MockJevTransport: JevHTTPTransport, @unchecked Sendable {
        let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

        init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
            self.handler = handler
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            try await handler(request)
        }
    }

    private final class LockedBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T

        init(_ value: T) {
            self.value = value
        }

        func get() -> T {
            lock.withLock { value }
        }

        func set(_ newValue: T) {
            lock.withLock { value = newValue }
        }

        func modify(_ block: (inout T) -> Void) {
            lock.withLock { block(&value) }
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

        try await runCheck("8b. Spectrum falls back to Jev activity modes without concrete tasks") {
            let t0 = baseDate()
            let budgets = [TaskBudget(taskId: "dev", displayName: "开发事项", colorHex: "#3B82F6")]
            let spans: [EnrichedSpan] = [
                EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(600), appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "App.swift", url: nil, declaredTaskId: nil, redacted: false, semanticGroup: "mode:build"),
                EnrichedSpan(startedAt: t0.addingTimeInterval(600), endedAt: t0.addingTimeInterval(1200), appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Ops Board", url: nil, declaredTaskId: nil, redacted: false, semanticGroup: "mode:operate"),
                EnrichedSpan(startedAt: t0.addingTimeInterval(1200), endedAt: t0.addingTimeInterval(1800), appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "Engine.swift", url: nil, declaredTaskId: "dev", redacted: false, semanticGroup: "mode:build")
            ]
            let result = SpectrumBuilder.build(spans: spans, focusSessions: [], budgets: budgets, now: t0.addingTimeInterval(1800))
            try check(result.segments.contains { if case .activityMode(let raw) = $0.kind { return raw == ActivityMode.build.rawValue }; return false }, "Build mode segment")
            try check(result.segments.contains { if case .activityMode(let raw) = $0.kind { return raw == ActivityMode.operate.rawValue }; return false }, "Operate mode segment")
            try check(result.segments.contains { if case .task(let id, _, _) = $0.kind { return id == "dev" }; return false }, "Concrete task still wins")
            try check(!result.segments.contains { if case .unassigned = $0.kind { return true }; return false }, "Matched modes must not fall back to unassigned")
            try checkApprox(result.metrics.longestBlockMinutes, 10.0, tolerance: 0.001, "Mode blocks count toward longest block")
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
            let thrashAlert = thrashAlerts.first { if case .highFrequencySwitch = $0.kind { return true }; return false }
            try check(thrashAlert != nil, "High-frequency switch alert")
            try check(thrashAlert?.title.contains("切换偏碎") == true, "High-frequency switch title explains choppy switching")
            try check(thrashAlert?.message.contains("固定一个任务 10 分钟") == true, "High-frequency switch message gives an action")
        }

        try await runCheck("12b. High-frequency switch alert explains semantic activity types") {
            let t0 = baseDate()
            let engine = DayHelmEngine(budgets: [], clock: ManualClock(now: t0))
            let modes: [ActivityMode] = [.build, .commsAdmin, .operate, .research, .create]
            var alerts: [SupervisorAlert] = []
            for i in 0..<12 {
                let mode = modes[i % modes.count]
                let ts = t0.addingTimeInterval(Double(i) * 20)
                engine.applyAutoCategory(mode.categoryId, activityMode: mode, at: ts)
                alerts.append(contentsOf: engine.ingest(
                    ActivitySample(
                        timestamp: ts,
                        appName: mode == .commsAdmin ? "微信" : "SyntheticApp\(i)",
                        bundleId: "com.synthetic.app\(i)",
                        windowTitle: "Synthetic \(mode.rawValue) \(i)",
                        url: nil,
                        idleSeconds: 0,
                        screenLocked: false,
                        inputActive: true
                    )
                ))
            }
            let alert = alerts.first { if case .highFrequencySwitch = $0.kind { return true }; return false }
            try check(alert != nil, "Semantic-mode thrashing alert")
            try check(alert?.title.contains("跨了 5 类活动") == true, "Alert title names the activity category count")
            for label in ["开发构建", "沟通杂务", "业务运营", "研究规划", "内容创作"] {
                try check(alert?.message.contains(label) == true, "Alert message includes \(label)")
            }
            try check(alert?.message.contains("固定一个活动 10 分钟") == true, "Alert message gives a concrete next step")
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

        try await runCheck("42. Browser parity: Dia/SafariTP, AppleScript router, circuit breaker & privacy guard") {
            try check(ActivityClassifier.isBrowser(appName: "Dia", bundleId: "company.thebrowser.dia"), "Dia bundle is browser")
            try check(ActivityClassifier.isBrowser(appName: "Safari Technology Preview", bundleId: "com.apple.safaritechnologypreview"), "SafariTP bundle is browser")
            try check(!ActivityClassifier.isBrowser(appName: "Obsidian", bundleId: "md.obsidian"), "Obsidian must not false-match dia")
            try check(BrowserTabScriptRouter.appleScriptSource(appName: "Arc", bundleId: "company.thebrowser.browser") != nil, "Arc produces AppleScript")
            var called = 0
            _ = AXWindowInspector.resolveBrowserFallbackIfNeeded(
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                existingTitle: "Bank Login",
                existingURL: nil,
                screenLocked: false,
                privacyConfig: .default
            ) { _, _ in
                called += 1
                return ("https://bank.example.com", "Bank")
            }
            try checkEqual(called, 0, "Redacted browser title must block AppleScript fallback")
        }

        try await runCheck("43. Aggregated input events & O(1) incremental database session counters") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-agg-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
            let t0Ms = Int64(baseDate().timeIntervalSince1970 * 1000)

            let e1 = try db.insertEvent(timestampMs: t0Ms, kind: "click", appName: "Xcode", data: ["count": "15"])
            _ = try db.insertEvent(sessionId: e1.sessionId, timestampMs: t0Ms + 2_000, kind: "keypress", appName: "Xcode", data: ["count": "30"])
            try db.closeSession(sessionId: e1.sessionId, endedAtMs: t0Ms + 60_000)
            let detail = try db.getSessionDetail(sessionId: e1.sessionId)
            try checkEqual(detail?.session.clickCount, 15, "Session clickCount sums data.count")
            try checkEqual(detail?.session.keypressCount, 30, "Session keypressCount sums data.count")
            try checkEqual(db.fullCounterResyncCount, 0, "New sessions update counters in O(1) without resync")
        }

        try await runCheck("44. Pixel diff, DisplayGeometry, FTS5 trigram, is_meeting, regex entities & extended redaction") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-fts-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
            let t0Ms = Int64(baseDate().timeIntervalSince1970 * 1000)
            let e = try db.insertEvent(
                timestampMs: t0Ms,
                kind: "browser_visit",
                appName: "Google Chrome",
                windowTitle: "Tencent Meeting · github.com/acme/dayhelm/pull/9",
                url: "https://github.com/acme/dayhelm/pull/9"
            )
            let s = try db.insertSnapshot(sessionId: e.sessionId, timestampMs: t0Ms + 1_000, filePath: tmpDir.appendingPathComponent("a.jpg").path, width: 100, height: 100, sizeBytes: 100)
            _ = try db.insertOCRFrame(snapshotId: s.id, sessionId: e.sessionId, text: "晶圆厂良率分析 " + "AIza" + "SyD-1234567890ABCDEFGHIJKLMNOPQRS", createdAtMs: t0Ms + 1_000)
            try db.closeSession(sessionId: e.sessionId, endedAtMs: t0Ms + 60_000)
            let summary = try db.getSessionDetail(sessionId: e.sessionId)?.session
            try checkEqual(summary?.isMeeting, true, "Meeting session sets isMeeting")
            try checkEqual(summary?.entities["repo"], ["acme/dayhelm"], "Extracts GitHub repo entity")
            try checkEqual(summary?.entities["pr"], ["#9"], "Extracts PR entity")
            let hits = try db.searchOCR(keyword: "晶圆厂")
            try checkEqual(hits.count, 1, "FTS5 trigram matches CJK OCR query")
            try check(hits.first?.text.contains("AIza***") == true, "Google API key masked on OCR write")
        }

        try await runCheck("45. Extended HTTP API routes: permissions, config, digest, report, pagination & prefix") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-chk-httpext-\(UUID().uuidString)")
            let store = DayHelmStore(directory: tmpDir)
            defer { try? FileManager.default.removeItem(at: tmpDir) }
            let t0 = baseDate()
            let t0Ms = Int64(t0.timeIntervalSince1970 * 1000)
            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            let sess = try db.startSession(id: "feed1234-0000-0000-0000-000000000001", startedAtMs: t0Ms)
            _ = try db.insertEvent(sessionId: sess.id, timestampMs: t0Ms + 1_000, kind: "app_focus", appName: "Terminal")
            try db.closeSession(sessionId: sess.id, endedAtMs: t0Ms + 60_000)
            let server = LocalActivityHTTPServer(database: db, store: store, clock: ManualClock(now: t0))

            try checkEqual(server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/permissions").statusCode, 200, "/permissions returns 200")
            try checkEqual(server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/config").statusCode, 200, "/config returns 200")
            try checkEqual(server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/digest?hours=24").statusCode, 200, "/digest returns 200")
            try checkEqual(server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/report/2026-11-17").statusCode, 200, "/report/<dateKey> returns 200")
            try checkEqual(server.handleRawHTTPRequestLineAndRoute(target: "/api/activity-recorder/sessions/feed1234").statusCode, 200, "6+ char session prefix resolves")
        }

        try await runCheck("46. SwitchClassifier: jitter merge, transient dwell, same-task cross-app affinity & working-set gate") {
            let t0 = baseDate()

            // A. Volatile title jitter merges in EventMerger and does not inflate switches
            var jitterSpans: [EnrichedSpan] = []
            for i in 0..<12 {
                let s = ActivitySample(
                    timestamp: t0.addingTimeInterval(Double(i) * 10),
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "Inbox (\(i + 1)) — Mail",
                    url: "https://mail.example.com/inbox",
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
                EventMerger.append(sample: s, declaredTaskId: nil, to: &jitterSpans, pulsetime: 60)
            }
            try checkEqual(jitterSpans.count, 1, "Volatile counter jitter merges into 1 span")

            // B. Transient <4s pass-through spans (e.g. Spotlight flash) are debounced and coalesce surrounding context
            let transientSpans: [EnrichedSpan] = [
                EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(20), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Quarterly Report", url: nil, declaredTaskId: nil, redacted: false),
                EnrichedSpan(startedAt: t0.addingTimeInterval(21), endedAt: t0.addingTimeInterval(22), appName: "Notes", bundleId: "com.apple.Notes", windowTitle: "Quick Glance", url: nil, declaredTaskId: nil, redacted: false),
                EnrichedSpan(startedAt: t0.addingTimeInterval(23), endedAt: t0.addingTimeInterval(50), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Quarterly Report", url: nil, declaredTaskId: nil, redacted: false)
            ]
            let preparedTransient = SwitchClassifier.prepareSequence(spans: transientSpans)
            try checkEqual(preparedTransient.count, 1, "Transient <4s middle span drops and coalesces identical surrounding context")

            // C. Cross-app collaboration sharing project token / workflow cluster / auxiliary tools does NOT trigger thrashing
            let collabEngine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            let collabSamples: [(String, String, String, String?)] = [
                ("T3 Code", "com.t3code.app", "T3 Code (Beta) - focus-guard", nil),
                ("Terminal", "com.apple.Terminal", "focus-guard — zsh", nil),
                ("Google Chrome", "com.google.Chrome", "Pull Request #12 — focus-guard", "https://github.com/org/focus-guard/pull/12"),
                ("Finder", "com.apple.finder", "focus-guard", nil),
                ("Google Chrome", "com.google.Chrome", "Local Preview", "http://localhost:3000/dashboard")
            ]
            for i in 0..<15 {
                let item = collabSamples[i % collabSamples.count]
                let alerts = collabEngine.ingest(ActivitySample(
                    timestamp: t0.addingTimeInterval(Double(i) * 18),
                    appName: item.0,
                    bundleId: item.1,
                    windowTitle: item.2,
                    url: item.3,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                ))
                try check(!alerts.contains { if case .highFrequencySwitch = $0.kind { return true }; return false }, "Same-project engineering workflow must not trigger thrashing")
            }

            // D. Unconfigured 3-context closed-loop ping-pong (Numbers <-> Mail <-> internal ERP) stays exempt
            let loopSpans: [EnrichedSpan] = (0..<14).map { i in
                let start = t0.addingTimeInterval(Double(i) * 20)
                switch i % 3 {
                case 0:
                    return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(18), appName: "Numbers", bundleId: "com.apple.iWork.Numbers", windowTitle: "Budget.numbers", url: nil, declaredTaskId: nil, redacted: false)
                case 1:
                    return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(18), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Vendor Invoice", url: nil, declaredTaskId: nil, redacted: false)
                default:
                    return EnrichedSpan(startedAt: start, endedAt: start.addingTimeInterval(18), appName: "Safari", bundleId: "com.apple.Safari", windowTitle: "ERP Orders", url: "https://erp.internal.example/orders", declaredTaskId: nil, redacted: false)
                }
            }
            let loopWindows = SpectrumBuilder.detectThrashingWindows(spans: loopSpans, budgets: sampleBudgets())
            try check(loopWindows.isEmpty, "Closed-loop <=3 non-interrupt contexts must not trigger thrashing")

            // E. Real distraction involving interrupt apps / 4+ unrelated contexts DOES trigger thrashing
            let distractEngine = DayHelmEngine(budgets: sampleBudgets(), clock: ManualClock(now: t0))
            let distractSamples: [(String, String, String, String?)] = [
                ("WeChat", "com.tencent.xinWeChat", "Chat", nil),
                ("Google Chrome", "com.google.Chrome", "Bilibili Video", "https://www.bilibili.com/video/BV1xx"),
                ("Slack", "com.tinyspeck.slackmacgap", "general", nil),
                ("Google Chrome", "com.google.Chrome", "Weibo Hot", "https://weibo.com/hot")
            ]
            var fired = false
            for i in 0..<14 {
                let item = distractSamples[i % distractSamples.count]
                let alerts = distractEngine.ingest(ActivitySample(
                    timestamp: t0.addingTimeInterval(Double(i) * 18),
                    appName: item.0,
                    bundleId: item.1,
                    windowTitle: item.2,
                    url: item.3,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                ))
                if alerts.contains(where: { if case .highFrequencySwitch = $0.kind { return true }; return false }) {
                    fired = true
                }
            }
            try check(fired, "Distracted switching across interrupt apps and 4+ contexts must trigger thrashing")

            // F. TaskBudget appBundleIds / domains matching + smoothed recentSwitchStats floor (600s)
            let customBudget = TaskBudget(taskId: "design", displayName: "Design", colorHex: "#EC4899", appBundleIds: ["com.figma.Desktop"], domains: ["figma.com"])
            let figmaSpan = EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(30), appName: "Figma", bundleId: "com.figma.Desktop", windowTitle: "Untitled", url: nil, declaredTaskId: nil, redacted: false)
            try checkEqual(SwitchClassifier.inferredTaskId(for: figmaSpan, budgets: [customBudget]), "design", "appBundleIds matches TaskBudget")
        }

        try await runCheck("47. SQLite hot queries use indexes without plain table scans") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-47-\(UUID().uuidString)")
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
            guard sqlite3_open_v2(dbURL.path, &rawDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let rawDB else {
                throw CheckFailure(description: "Failed to open SQLite DB for EXPLAIN QUERY PLAN")
            }
            defer { sqlite3_close(rawDB) }

            let queries = [
                "SELECT id FROM activity_sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;",
                "SELECT COUNT(*) FROM activity_snapshots WHERE timestamp >= 0 AND timestamp <= 9999999999999;",
                "SELECT COUNT(*) FROM activity_ocr_frames WHERE created_at >= 0 AND created_at <= 9999999999999;",
                "SELECT COALESCE(SUM(size_bytes), 0) FROM activity_snapshots WHERE storage_tier != 'pruned';"
            ]
            for sql in queries {
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(rawDB, "EXPLAIN QUERY PLAN " + sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                    throw CheckFailure(description: "Failed to prepare EXPLAIN QUERY PLAN for: \(sql)")
                }
                defer { sqlite3_finalize(stmt) }
                var details: [String] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let cStr = sqlite3_column_text(stmt, 3) {
                        details.append(String(cString: cStr))
                    }
                }
                for detail in details {
                    if detail.contains("SCAN ") && !detail.contains("INDEX") {
                        throw CheckFailure(description: "Plain table scan detected for query [\(sql)]: \(detail)")
                    }
                }
            }
        }

        try await runCheck("48. SwitchClassifier memoization, eviction & 1500-span SpectrumBuilder 50-tick perf") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let budgets = sampleBudgets()
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

            let perfStart = CFAbsoluteTimeGetCurrent()
            var lastSpectrum = engine.currentSpectrumAndMetrics(at: clock.now())
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
                lastSpectrum = engine.currentSpectrumAndMetrics(at: clock.now())
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - perfStart
            try check(!lastSpectrum.segments.isEmpty, "Spectrum segments should not be empty")
            try check(lastSpectrum.metrics.activeMinutes > 0, "Active minutes should be positive")
            try check(elapsed < 0.25, "50 heartbeat ticks on 1500 spans took \(String(format: "%.3f", elapsed))s (expected < 0.25s)")

            // Verify SwitchClassifier bounded cache handles > 4096 distinct keys cleanly
            for k in 0..<4500 {
                let span = EnrichedSpan(
                    startedAt: t0,
                    endedAt: t0.addingTimeInterval(10),
                    appName: "Xcode",
                    bundleId: "com.apple.dt.Xcode",
                    windowTitle: "File-\(k).swift",
                    url: nil,
                    declaredTaskId: nil,
                    redacted: false
                )
                _ = SwitchClassifier.role(for: span)
                _ = SwitchClassifier.canonicalContextKey(for: span)
                _ = SwitchClassifier.projectTokens(for: span)
            }
            let wechatSpan = EnrichedSpan(startedAt: t0, endedAt: t0.addingTimeInterval(15), appName: "WeChat", bundleId: "com.tencent.xinWeChat", windowTitle: "Chat", url: nil, declaredTaskId: nil, redacted: false)
            try checkEqual(SwitchClassifier.role(for: wechatSpan), .interrupt, "SwitchClassifier role remains accurate after >4096 cache insertions")
        }

        try await runCheck("49. ActivityDatabase grouped session summary synthesis parity") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-49-\(UUID().uuidString)")
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
            try checkEqual(detail.session.clickCount, 125 * 3, "Grouped summary clickCount parity")
            try checkEqual(detail.session.keypressCount, 125 * 2, "Grouped summary keypressCount parity")
            try checkEqual(detail.session.isMeeting, true, "Grouped summary detects meeting signal")
            try check(detail.session.analysisTitle != nil && !(detail.session.analysisTitle?.isEmpty ?? true), "analysisTitle populated")
            try check(detail.session.analysisDescription != nil && !(detail.session.analysisDescription?.isEmpty ?? true), "analysisDescription populated")
            try check(!detail.session.topics.isEmpty, "topics populated")
            let entityTypes = Set(detail.session.entities.keys)
            for expected in ["repo", "pr", "local_port", "domain", "app", "task"] {
                try check(entityTypes.contains(expected), "entities missing expected type '\(expected)'")
            }
        }

        try await runCheck("50. ActivityTextNormalizer & PrivacyRedactor precompiled regex and fast-path parity") {
            try checkEqual(ActivityTextNormalizer.normalizedTitleKey("(3) Inbox - 45% 12:34:56 Loading..."), "inbox - loading", "Normalizer strips volatile counters, pct, clock, ellipsis")
            try checkEqual(ActivityTextNormalizer.normalizedTitleKey("v2 Release Q4"), "v2 release q4", "Normalizer preserves alphanumeric tokens")

            let now = baseDate()
            try check(PrivacyRedactor.shouldRedact(ActivitySample(timestamp: now, appName: "Chrome", bundleId: "com.google.Chrome", windowTitle: "Invoice Payment Portal", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)), "Payment boundary redacts")
            try check(!PrivacyRedactor.shouldRedact(ActivitySample(timestamp: now, appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "payload.json", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)), "payload does not false-positive")
            try check(!PrivacyRedactor.shouldRedact(ActivitySample(timestamp: now, appName: "System Settings", bundleId: "com.apple.systemsettings", windowTitle: "Display Settings", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)), "display does not false-positive")

            let secretInputs: [(String, String)] = [
                ("-----BEGIN " + "RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEA\n-----END RSA PRIVATE KEY-----", "PEM"),
                ("token=sk-" + "1234567890abcdefghijklmnop", "sk-"),
                ("ghp_" + "1234567890abcdefghijklmnopqrstuvwxyz", "ghp_"),
                ("xoxb-" + "123456789012-1234567890123-abcdefghijklmnopqrstuvwx", "xoxb-"),
                ("AKIA" + "IOSFODNN7EXAMPLE", "AKIA"),
                ("AIza" + "SyDaGmWKa4JsXZ-HjGw7ISLn_3namBGewQe", "AIza"),
                ("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U", "JWT"),
                ("ssn: 123-45-6789", "SSN"),
                ("Authorization: Bearer super_secret_token_value_12345", "Bearer"),
                ("Authorization: Basic dXNlcjpwYXNzMTIzNDU=", "Basic"),
                ("api_key=my_super_secret_value_999", "api_key"),
                ("card: 4111 1111 1111 1111", "Luhn card")
            ]
            for (raw, label) in secretInputs {
                let redacted = PrivacyRedactor.redactSecrets(in: raw)
                try check(redacted != raw && redacted.contains("***"), "Secret redaction failed for \(label)")
            }

            let cleanOCR = String(repeating: "SwiftPM DayHelmCore ActivityDatabase SQLite WAL benchmark line 12345.\n", count: 80)
            try checkEqual(PrivacyRedactor.redactSecrets(in: cleanOCR), cleanOCR, "Clean multi-KB OCR text remains untouched")
        }

        try await runCheck("51. VisionOCRService 1600px downscaling & ImageHistogram visual signature") {
            let largeImg = try makeSyntheticTextImage(text: "DAYHELM_OCR_2560", backgroundWhite: true, width: 2560, height: 1600)
            let scaled = VisionOCRService.prepareOCRImage(from: largeImg, maxDimension: 1600)
            try checkEqual(scaled.width, 1600, "2560x1600 should scale width to 1600")
            try checkEqual(scaled.height, 1000, "2560x1600 should scale height proportionally to 1000")

            let smallImg = try makeSyntheticTextImage(text: "SMALL_960", backgroundWhite: true, width: 960, height: 240)
            let untouched = VisionOCRService.prepareOCRImage(from: smallImg, maxDimension: 1600)
            try checkEqual(untouched.width, 960, "960x240 should remain 960px wide")
            try checkEqual(untouched.height, 240, "960x240 should remain 240px tall")

            let ocrResult = try await VisionOCRService.recognizeText(from: scaled)
            try check(ocrResult.text.uppercased().contains("DAYHELM"), "OCR should still recognize text after 1600px downscale, got: \(ocrResult.text)")

            let sig = ImageHistogram.computeVisualSignature(from: largeImg, bins: 32)
            try checkEqual(sig.histogram.count, 32, "Visual signature histogram should have 32 bins")
            try checkEqual(sig.thumbnailRGB.count, 160 * 90 * 3, "Visual signature thumbnailRGB should be 160x90x3")
            try checkEqual(sig.hashHex.count, 16, "Visual signature hashHex should be 16 hex chars")
        }

        try await runCheck("52. NativeScreenRecorder bounded OCR session dedup cache (<= 4)") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-52-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let db = try ActivityDatabase(databaseURL: tmpDir.appendingPathComponent("activity.sqlite"))
            let capturer = MockScreenCapturer(image: try makeSyntheticTextImage(text: "BOUNDED_OCR_TEST", backgroundWhite: true))
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
            try check(recorder.cachedOCRSessionCount <= 4, "cachedOCRSessionCount should be capped <= 4, got \(recorder.cachedOCRSessionCount)")
            recorder.resetDeduplicationBaseline()
            try checkEqual(recorder.cachedOCRSessionCount, 0, "resetDeduplicationBaseline should clear cachedOCRSessionCount")
        }

        try await runCheck("53. AXWindowInspector 15s unchanged-title browser TTL cache & invalidation") {
            final class CounterBox: @unchecked Sendable {
                private let lock = NSLock()
                private var _value = 0
                var value: Int { lock.withLock { _value } }
                func increment() { lock.withLock { _value += 1 } }
            }
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let callCounter = CounterBox()
            let inspector = AXWindowInspector(
                clock: clock,
                observeScreenLock: false,
                browserCacheTTLSeconds: 15.0,
                browserTabProvider: { appName, _ in
                    callCounter.increment()
                    return (url: "https://example.com/\(appName)/\(callCounter.value)", title: "Page \(callCounter.value)")
                }
            )
            // Poll every 2s for 14s on same (app, title): should invoke provider only once.
            for step in 0..<7 {
                let res = inspector.resolveBrowserFallbackWithCache(
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    existingTitle: "Same Tab Title",
                    existingURL: nil,
                    screenLocked: false
                )
                try checkEqual(res.url, "https://example.com/Google Chrome/1", "Step \(step) should reuse cached URL")
                clock.advance(by: 2)
            }
            try checkEqual(callCounter.value, 1, "Provider should be called once within 15s TTL")

            // Advance past 15s (>= 15s total elapsed): should re-query.
            clock.advance(by: 2)
            let refreshed = inspector.resolveBrowserFallbackWithCache(
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                existingTitle: "Same Tab Title",
                existingURL: nil,
                screenLocked: false
            )
            try checkEqual(callCounter.value, 2, "Provider should be called again once >= 15s elapsed")
            try checkEqual(refreshed.url, "https://example.com/Google Chrome/2", "Refreshed URL should reflect 2nd call")

            // Title change within TTL: should invalidate immediately.
            clock.advance(by: 2)
            _ = inspector.resolveBrowserFallbackWithCache(
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                existingTitle: "New Tab Title",
                existingURL: nil,
                screenLocked: false
            )
            try checkEqual(callCounter.value, 3, "Title change should invoke provider immediately")

            // App change within TTL: should invalidate immediately.
            clock.advance(by: 2)
            _ = inspector.resolveBrowserFallbackWithCache(
                appName: "Safari",
                bundleId: "com.apple.Safari",
                existingTitle: "New Tab Title",
                existingURL: nil,
                screenLocked: false
            )
            try checkEqual(callCounter.value, 4, "App change should invoke provider immediately")
        }

        try await runCheck("54. Coordinator lazy daySnapshot, popover timer gating & MenuBarPillModel") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-54-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: MockInspector(currentSample: ActivitySample(
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
            }
            try await MainActor.run {
                try checkEqual(coordinator.pillModel.text, "待命", "Initial standard standby pill text should show 待命")
                try checkEqual(coordinator.pillModel.visualState, .standby, "Initial pill visualState should be standby")
                try check(coordinator.pillModel.helpText.contains("待命"), "Standby helpText should describe standby state")
                coordinator.selectTask("ecommerce")
                try checkEqual(coordinator.pillModel.text, "电商做深 0/90m", "Standard focusing pill text should show task label + focused/target")
                try checkEqual(coordinator.pillModel.visualState, .focusing, "Focusing pill visualState should be focusing")
                try check(coordinator.pillModel.helpText.contains("电商"), "HelpText should reflect focused task")
                let initialPill = coordinator.pillModel.text

                // Popover closed: elapsedFocusSeconds should not advance on pollOnce/tick.
                try checkEqual(coordinator.isPopoverVisible, false, "Popover should start hidden")
                let beforeElapsed = coordinator.elapsedFocusSeconds
                clock.advance(by: 2)
                coordinator.pollOnce()
                try checkEqual(coordinator.elapsedFocusSeconds, beforeElapsed, "Closed popover should suppress elapsedFocusSeconds updates")
                try checkEqual(coordinator.pillModel.text, initialPill, "Same rounded minute should not mutate pillModel.text")

                coordinator.setPopoverVisible(true)
                try check(coordinator.elapsedFocusSeconds >= 2.0, "Opening popover should immediately update elapsedFocusSeconds")
            }

            let runtimeSnapshot = coordinator.currentRuntimeState().daySnapshot
            try check(runtimeSnapshot != nil, "currentRuntimeState().daySnapshot should be populated lazily on demand")
            try checkEqual(runtimeSnapshot?.activeFocus?.taskId, "ecommerce", "Lazy daySnapshot should reflect active focus")
        }

        try await runCheck("55. ScreenSnapshotCapturer.decodeThumbnailCGImage downsamples 2560x1440 to 368px") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-55-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let large = try makeSyntheticTextImage(text: "THUMB_TEST", backgroundWhite: false, width: 2560, height: 1440)
            let jpgURL = tmpDir.appendingPathComponent("frame.jpg")
            _ = try ScreenSnapshotCapturer.encodeJPEG(image: large, to: jpgURL, quality: 0.6)

            let thumb = ScreenSnapshotCapturer.decodeThumbnailCGImage(at: jpgURL, maxPixelSize: 368)
            try check(thumb != nil, "decodeThumbnailCGImage should return a CGImage")
            if let thumb {
                try checkEqual(max(thumb.width, thumb.height), 368, "Thumbnail longest side should be 368px, got \(thumb.width)x\(thumb.height)")
            }
        }

        try await runCheck("56. VisionOCRWorker JSON round-trip and missing file error") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-56-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let img = try makeSyntheticTextImage(text: "CHECK56_OCR", backgroundWhite: true, width: 1280, height: 720)
            let jpgURL = tmpDir.appendingPathComponent("sample.jpg")
            _ = try ScreenSnapshotCapturer.encodeJPEG(image: img, to: jpgURL, quality: 0.8)

            let reqData = try JSONSerialization.data(withJSONObject: [
                "imagePath": jpgURL.path,
                "maxDimension": 1280,
                "languages": ["en-US"]
            ])
            let respData = VisionOCRWorker.processRequestJSONData(reqData)
            let resp = try JSONSerialization.jsonObject(with: respData) as? [String: Any]
            try checkEqual(resp?["ok"] as? Bool, true, "VisionOCRWorker should return ok: true")
            let text = (resp?["text"] as? String ?? "").uppercased()
            try check(text.contains("CHECK56"), "VisionOCRWorker should recognize CHECK56, got '\(text)'")

            let missingReq = try JSONSerialization.data(withJSONObject: [
                "imagePath": tmpDir.appendingPathComponent("nope.jpg").path,
                "maxDimension": 1280,
                "languages": ["en-US"]
            ])
            let missingResp = try JSONSerialization.jsonObject(with: VisionOCRWorker.processRequestJSONData(missingReq)) as? [String: Any]
            try checkEqual(missingResp?["ok"] as? Bool, false, "Missing file should return ok: false")
        }

        try await runCheck("57. NativeScreenRecorder non-focus OCR cooldown (25s)") {
            let t0 = Date(timeIntervalSince1970: 1_760_300_000)
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-57-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let db = try ActivityDatabase(databaseURL: store.databaseURL)
            let recorder = NativeScreenRecorder(database: db, snapshotsRootDir: store.snapshotsDirectory, clock: clock)

            let dayStartMs = Int64(t0.timeIntervalSince1970 * 1000) - 1000
            let dayEndMs = dayStartMs + 86_400_000
            let sample1 = ActivitySample(timestamp: t0, appName: "Notes", bundleId: "com.apple.Notes", windowTitle: "Note", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            let s1 = try await recorder.processCapturedImage(
                try makeSyntheticTextImage(text: "FOCUS_FIRST", backgroundWhite: true, width: 1280, height: 720),
                sample: sample1,
                trigger: ActivityEventKind.appFocus.rawValue,
                runOCR: true
            )
            try check(s1, "First app_focus snapshot should be saved")
            try checkEqual(try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs).ocrFrames, 1, "First app_focus should run OCR")

            clock.advance(by: 6)
            let sample2 = ActivitySample(timestamp: clock.now(), appName: "Notes", bundleId: "com.apple.Notes", windowTitle: "Note", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
            let s2 = try await recorder.processCapturedImage(
                try makeSyntheticTextImage(text: "SECONDARY_SKIPPED", backgroundWhite: false, width: 1280, height: 720),
                sample: sample2,
                trigger: "visual_change",
                runOCR: true
            )
            try check(s2, "Visual change snapshot should still be saved")
            try checkEqual(try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs).ocrFrames, 1, "Secondary OCR within 25s on SAME window should be skipped")

            // Switching to a different tab/window title after >= 4s should run OCR without waiting 25s
            clock.advance(by: 5)
            let sample3 = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Hermes Agent - Dashboard", url: "http://127.0.0.1:9119/", idleSeconds: 0, screenLocked: false, inputActive: true)
            let s3 = try await recorder.processCapturedImage(
                try makeSyntheticTextImage(text: "DIFFERENT_TAB_OCR", backgroundWhite: true, width: 1280, height: 720),
                sample: sample3,
                trigger: ActivityEventKind.click.rawValue,
                runOCR: true
            )
            try check(s3, "Different browser tab click snapshot should be saved")
            try checkEqual(try db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs).ocrFrames, 2, "Switching to a different window/tab title after >= 4s should run OCR immediately")
        }

        try await runCheck("58. HybridActivityCoordinator background UI gating and window hydration") {
            let t0 = Date(timeIntervalSince1970: 1_760_301_000)
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-58-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let engine = DayHelmEngine(budgets: [TaskBudget(taskId: "dev", displayName: "Dev", colorHex: "#3B82F6", targetMinutes: 90, capMinutes: 120, keywords: ["xcode"])], clock: clock)
            let inspector = MockInspector(currentSample: ActivitySample(timestamp: t0, appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "A.swift", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true))
            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspector,
                    clock: clock
                )
            }
            try await MainActor.run {
                coordinator.start()
                defer { coordinator.stop() }
                try checkEqual(coordinator.isRecorderWindowVisible, false, "Recorder window should start hidden")
                inspector.currentSample = ActivitySample(timestamp: t0.addingTimeInterval(4), appName: "Xcode", bundleId: "com.apple.dt.Xcode", windowTitle: "B.swift", url: nil, idleSeconds: 0, screenLocked: false, inputActive: true)
                clock.advance(by: 4)
                coordinator.pollOnce()
                try check(coordinator.latestSample?.windowTitle != "B.swift", "Hidden started coordinator should gate latestSample")
                coordinator.setRecorderWindowVisible(true)
                try checkEqual(coordinator.latestSample?.windowTitle, "B.swift", "Opening recorder window should hydrate latestSample")
            }
        }

        try await runCheck("59. MenuBarDisplayMode formatting, TaskBudget shortName & settings compatibility") {
            let legacyJSON = Data(#"{"activityRecorderEnabled":true}"#.utf8)
            let decodedLegacy = try JSONDecoder().decode(DayHelmSettings.self, from: legacyJSON)
            try checkEqual(decodedLegacy.menuBarDisplayMode, .standard, "Legacy settings JSON should default menuBarDisplayMode to .standard")

            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-59-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let customBudgets = [
                TaskBudget(
                    taskId: "ops",
                    displayName: "电商日常运营",
                    shortName: "运营",
                    colorHex: "#F59E0B",
                    targetMinutes: nil,
                    capMinutes: 30
                ),
                TaskBudget(
                    taskId: "infra",
                    displayName: "Infra 维护",
                    colorHex: "#8B5CF6",
                    targetMinutes: nil,
                    capMinutes: 30
                ),
                TaskBudget(
                    taskId: "long",
                    displayName: "超长核心研发任务规划专项",
                    colorHex: "#3B82F6",
                    targetMinutes: 90,
                    capMinutes: nil
                )
            ]
            let engine = DayHelmEngine(budgets: customBudgets, clock: clock)
            let inspector = MockInspector(currentSample: ActivitySample(
                timestamp: t0,
                appName: "Xcode",
                bundleId: "com.apple.dt.Xcode",
                windowTitle: "Main.swift",
                url: nil,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspector,
                    clock: clock
                )
            }

            try await MainActor.run {
                // Standard mode: standby shows short "待命", focusing uses shortName or 4-char truncation
                var standardSettings = coordinator.recorderSettings
                standardSettings.menuBarDisplayMode = .standard
                coordinator.updateRecorderSettings(standardSettings)
                try checkEqual(coordinator.pillModel.text, "待命", "Standard standby should omit brand prefix")

                coordinator.selectTask("infra")
                try checkEqual(coordinator.pillModel.text, "Infra 维护 0/30m", "Standard mode must NOT truncate mixed ASCII+CJK labels like 'Infra 维护'")

                coordinator.selectTask("long")
                try checkEqual(coordinator.pillModel.text, "超长核心研发任务… 0/90m", "Standard mode should only truncate ultra-long names exceeding 16 visual units")

                coordinator.selectTask("ops")
                try checkEqual(coordinator.pillModel.text, "运营 0/30m", "Standard mode should prefer TaskBudget.shortName")

                // Simulate 31 minutes of focus on ops to hit cap (30m)
                for step in 1...31 {
                    let nextTs = t0.addingTimeInterval(TimeInterval(step * 60))
                    clock.advance(by: 60)
                    inspector.currentSample = ActivitySample(
                        timestamp: nextTs,
                        appName: "Xcode",
                        bundleId: "com.apple.dt.Xcode",
                        windowTitle: "Main.swift",
                        url: nil,
                        idleSeconds: 0,
                        screenLocked: false,
                        inputActive: true
                    )
                    coordinator.pollOnce()
                }
                try checkEqual(coordinator.pillModel.text, "运营 31/30m▲", "Standard capReached should show compact ▲ suffix")

                // Switch to compact mode: should immediately drop task name and show 31/30m!
                var compactSettings = coordinator.recorderSettings
                compactSettings.menuBarDisplayMode = .compact
                coordinator.updateRecorderSettings(compactSettings)
                try checkEqual(coordinator.pillModel.text, "31/30m!", "Compact capReached should show 31/30m!")

                // Switch to iconOnly mode: text should be empty, but visualState should still distinguish capReached vs standby
                var iconSettings = coordinator.recorderSettings
                iconSettings.menuBarDisplayMode = .iconOnly
                coordinator.updateRecorderSettings(iconSettings)
                try checkEqual(coordinator.pillModel.text, "", "IconOnly mode should render empty pill text")
                try checkEqual(coordinator.pillModel.visualState, .capReached, "IconOnly mode should still expose capReached visualState")
                try check(coordinator.pillModel.helpText.contains("电商日常运营"), "IconOnly helpText should still contain full task name")

                coordinator.pauseFocus()
                try checkEqual(coordinator.pillModel.visualState, .standby, "Pausing focus should return iconOnly visualState to standby")
            }
        }

        try await runCheck("60. TaskBudget description, Jev settings persistence & JevAPIKeyStore isolation") {
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-60-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let budget = TaskBudget(
                taskId: "ecom",
                displayName: "电商做深",
                shortName: "电商",
                description: "选品、主图与详情页优化",
                colorHex: "#3B82F6",
                targetMinutes: 90,
                capMinutes: 120
            )
            try store.saveBudgets([budget])
            let loadedBudgets = TimeAuditConfigLoader.loadBudgets(dayhelmConfigURL: store.configURL)
            try checkEqual(loadedBudgets.first?.description, "选品、主图与详情页优化", "TaskBudget.description should persist in config.json")

            var settings = DayHelmSettings.default
            try checkEqual(settings.jevAutoTrackingEnabled, false, "Jev auto-tracking should be opt-in (false by default)")
            try checkEqual(settings.jevSendOCRSnippet, true, "jevSendOCRSnippet should default to true")
            settings.jevAutoTrackingEnabled = true
            settings.jevModel = "jev-1.14.0"
            settings.jevSendOCRSnippet = false
            settings.menuBarDisplayMode = .compact
            try store.saveSettings(settings)

            let reloaded = store.loadSettings()
            try checkEqual(reloaded.jevAutoTrackingEnabled, true, "jevAutoTrackingEnabled should persist")
            try checkEqual(reloaded.jevModel, "jev-1.14.0", "jevModel should persist")
            try checkEqual(reloaded.jevSendOCRSnippet, false, "jevSendOCRSnippet should persist")
            try checkEqual(reloaded.menuBarDisplayMode, .compact, "menuBarDisplayMode should persist in config.json")

            // API key stored in jev.key (NOT config.json) with 0600 permissions
            let keyStore = JevAPIKeyStore(directory: tmpDir, environment: [:], dotEnvSearchPaths: [])
            try checkEqual(keyStore.resolveKey(), nil, "Empty JevAPIKeyStore should resolve nil")
            try keyStore.saveKey("test_synthetic_jev_key_12345")
            let resolved = keyStore.resolveKey()
            try checkEqual(resolved?.key, "test_synthetic_jev_key_12345", "Saved key should resolve from local file")
            try checkEqual(resolved?.source, .localKeyFile, "Saved key source should be .localKeyFile")

            let configText = try String(contentsOf: store.configURL, encoding: .utf8)
            try check(!configText.contains("test_synthetic_jev_key_12345"), "API key must never be written into config.json")

            let envStore = JevAPIKeyStore(directory: tmpDir, environment: ["JEV_API_KEY": "env_key_999"], dotEnvSearchPaths: [])
            try keyStore.deleteKey()
            try checkEqual(envStore.resolveKey()?.key, "env_key_999", "Environment JEV_API_KEY should act as fallback")
            try checkEqual(envStore.resolveKey()?.source, .environment, "Fallback source should be .environment")
        }

        try await runCheck("61. SemanticPayloadSanitizer hard privacy gates & OCR truncation") {
            let t0 = baseDate()
            let budgets = sampleBudgets()

            // Locked screen -> nil (never classify)
            let locked = ActivitySample(timestamp: t0, appName: "loginwindow", windowTitle: "Lock", idleSeconds: 0, screenLocked: true, inputActive: false)
            try checkEqual(
                SemanticPayloadSanitizer.buildInput(
                    sample: locked,
                    ocrText: "secret screen text",
                    recentSpans: [],
                    budgets: budgets,
                    sendOCRSnippet: true,
                    privacyConfig: .default
                ),
                nil,
                "Locked screen must never build an outbound classification input"
            )

            // Redacted app (1Password) -> strips title, url, ocr completely
            let pwSample = ActivitySample(
                timestamp: t0,
                appName: "1Password",
                bundleId: "com.1password.1password",
                windowTitle: "Vault - Bank Password",
                url: "https://bank.example.com?token=secret123",
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            )
            let redactedInput = SemanticPayloadSanitizer.buildInput(
                sample: pwSample,
                ocrText: "master password 123456",
                recentSpans: [],
                budgets: budgets,
                sendOCRSnippet: true,
                privacyConfig: .default
            )
            try check(redactedInput != nil, "Redacted non-locked sample should produce app-only sanitized input")
            try checkEqual(redactedInput?.redacted, true, "Redacted sample must preserve redacted=true")
            try checkEqual(redactedInput?.windowTitle, nil, "Redacted sample must strip windowTitle")
            try checkEqual(redactedInput?.url, nil, "Redacted sample must strip url")
            try checkEqual(redactedInput?.ocrSnippet, nil, "Redacted sample must strip OCR snippet")

            // Normal sample -> strips URL tokens, masks secrets, caps OCR at 320 chars
            let longOCR = "Header Bearer supersecrettoken999999 sk-abcdefghij1234567890 " + String(repeating: "主图优化", count: 120)
            let normalSample = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Example Shop api_key=rawsecret123",
                url: "https://shop.example.com/item?id=42&token=mysecret&session=abc",
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            )
            let normalInput = SemanticPayloadSanitizer.buildInput(
                sample: normalSample,
                ocrText: longOCR,
                recentSpans: [],
                budgets: budgets,
                sendOCRSnippet: true,
                privacyConfig: .default
            )
            try check(normalInput != nil, "Normal sample should build classification input")
            try check(!(normalInput?.windowTitle?.contains("rawsecret123") ?? true), "Title secrets must be masked")
            try check(!(normalInput?.url?.contains("mysecret") ?? true), "URL sensitive query params must be stripped")
            try check(!(normalInput?.ocrSnippet?.contains("supersecrettoken999999") ?? true), "OCR bearer token must be masked")
            try check(!(normalInput?.ocrSnippet?.contains("sk-abcdefghij1234567890") ?? true), "OCR sk- key must be masked")
            try check((normalInput?.ocrSnippet?.count ?? 999) <= SemanticPayloadSanitizer.maxOCRSnippetChars, "OCR snippet must be capped to <= 320 chars")
        }

        try await runCheck("62. SemanticAutoTracker deterministic hysteresis, caching & manual override") {
            let t0 = baseDate()
            let tracker = SemanticAutoTracker()

            // 0. Calibrated sub-2s defaults (0.65s dwell ensures cold-TLS ~1.1s RTT stays <= 2.0s)
            try checkApprox(tracker.config.minDwellBeforeClassifySeconds, 0.65, "Default pre-classify dwell should be 0.65s")
            try checkApprox(tracker.config.onDemandOCRWaitSeconds, 1.4, "Default on-demand OCR wait deadline should be 1.4s")
            try checkApprox(tracker.config.cacheSwitchDwellSeconds, 0.45, "Default cached-switch anti-flicker dwell should be 0.45s")
            try checkApprox(tracker.config.immediateSwitchConfidence, 0.80, "Default immediate switch confidence should be 0.80")
            try checkApprox(tracker.config.fastSwitchConfirmSeconds, 1.2, "Default fast anti-flicker confirm should be 1.2s")
            try checkApprox(tracker.config.minSwitchConfirmSeconds, 2.5, "Default standard anti-flicker confirm should be 2.5s")

            // 1. Cold start commits immediately when confidence >= 0.55
            let c1 = SemanticClassification(
                categoryId: "ecommerce",
                confidence: 0.88,
                probabilities: ["ecommerce": 0.90],
                sameTaskAsPrevious: nil,
                isDistraction: 0.05,
                source: .jev,
                classifiedAt: t0
            )
            let d1 = tracker.apply(classification: c1, contextKey: "browser|chrome|shop.example.com", at: t0)
            try checkEqual(d1.committedCategoryId, "ecommerce", "Cold start with high confidence should commit immediately")

            // 2. Low-confidence noise while focusing does not switch
            let cNoise = SemanticClassification(
                categoryId: AutoActivityIds.otherWork,
                confidence: 0.38,
                probabilities: [AutoActivityIds.otherWork: 0.45],
                sameTaskAsPrevious: 0.40,
                isDistraction: 0.15,
                source: .jev,
                classifiedAt: t0.addingTimeInterval(30)
            )
            let dNoise = tracker.apply(classification: cNoise, contextKey: "app|finder|desktop", at: t0.addingTimeInterval(30))
            try checkEqual(dNoise.committedCategoryId, "ecommerce", "Low-confidence classification must not switch active project")

            // 3. Moderate-confidence switch (0.78 / same=0.30) enters fast anti-flicker dwell (1.2s) and reports exact remainingConfirmSeconds
            let cSwitch = SemanticClassification(
                categoryId: "hermes",
                confidence: 0.78,
                probabilities: ["hermes": 0.80],
                sameTaskAsPrevious: 0.30,
                isDistraction: 0.05,
                source: .jev,
                classifiedAt: t0.addingTimeInterval(60)
            )
            let dPending = tracker.apply(classification: cSwitch, contextKey: "app|obsidian|hermes-q4", at: t0.addingTimeInterval(60))
            try checkEqual(dPending.committedCategoryId, "ecommerce", "Moderate-confidence candidate should enter brief anti-flicker dwell")
            try checkEqual(dPending.pendingCategoryId, "hermes", "Moderate-confidence candidate should set pendingCategoryId")
            try checkApprox(tracker.remainingConfirmSeconds(for: "app|obsidian|hermes-q4", at: t0.addingTimeInterval(60.5)) ?? -1, 0.7, tolerance: 0.05, "remainingConfirmSeconds should compute exact remaining fast confirm dwell")

            let dBefore = tracker.tickDwell(activeContextKey: "app|obsidian|hermes-q4", at: t0.addingTimeInterval(60.8))
            try checkEqual(dBefore.committedCategoryId, "ecommerce", "At 0.8s (< 1.2s) fast anti-flicker switch should still observe")

            let dAfter = tracker.tickDwell(activeContextKey: "app|obsidian|hermes-q4", at: t0.addingTimeInterval(61.3))
            try checkEqual(dAfter.committedCategoryId, "hermes", "At 1.3s (>= 1.2s) tickDwell should commit fast switch without extra API call")

            // 3b. Ambiguous / high same_task switch (0.72 / same=0.70) uses standard anti-flicker dwell (2.5s)
            let cAmbiguous = SemanticClassification(
                categoryId: "infra-billing",
                confidence: 0.72,
                probabilities: ["infra-billing": 0.72],
                sameTaskAsPrevious: 0.70,
                isDistraction: 0.02,
                source: .jev,
                classifiedAt: t0.addingTimeInterval(90)
            )
            let dAmbPending = tracker.apply(classification: cAmbiguous, contextKey: "browser|chrome|aws.amazon.com|billing", at: t0.addingTimeInterval(90))
            try checkEqual(dAmbPending.committedCategoryId, "hermes", "Ambiguous high-same_task switch must wait in standard anti-flicker dwell")
            let dAmbMid = tracker.tickDwell(activeContextKey: "browser|chrome|aws.amazon.com|billing", at: t0.addingTimeInterval(91.5))
            try checkEqual(dAmbMid.committedCategoryId, "hermes", "At 1.5s (< 2.5s) standard anti-flicker switch must not commit yet")
            let dAmbCommit = tracker.tickDwell(activeContextKey: "browser|chrome|aws.amazon.com|billing", at: t0.addingTimeInterval(92.6))
            try checkEqual(dAmbCommit.committedCategoryId, "infra-billing", "At 2.6s (>= 2.5s) standard anti-flicker switch should commit")

            // 4. High-confidence switch (conf >= 0.80 & same <= 0.60) switches IMMEDIATELY
            let cImmediate = SemanticClassification(
                categoryId: AutoActivityIds.nonWork,
                confidence: 0.82,
                probabilities: [AutoActivityIds.nonWork: 0.84],
                sameTaskAsPrevious: 0.52,
                isDistraction: 0.90,
                source: .jev,
                classifiedAt: t0.addingTimeInterval(120)
            )
            let dImmediate = tracker.apply(classification: cImmediate, contextKey: "browser|chrome|bilibili.com|video", at: t0.addingTimeInterval(120))
            try checkEqual(dImmediate.committedCategoryId, AutoActivityIds.nonWork, "High-confidence switch (>= 0.80 & same <= 0.60) must commit immediately without waiting")
            try checkEqual(dImmediate.didSwitch, true, "High-confidence immediate switch must set didSwitch=true")

            // 5. Cache hit within 300s TTL & OCR-upgrade cache bypass
            let cached = tracker.cachedClassification(for: "app|obsidian|hermes-q4", budgetsVersion: 1, at: t0.addingTimeInterval(200))
            try checkEqual(cached?.categoryId, "hermes", "Same contextKey within TTL should hit local cache")
            try checkEqual(tracker.cachedClassification(for: "app|obsidian|hermes-q4", budgetsVersion: 2, at: t0.addingTimeInterval(200)), nil, "Budget change should invalidate cache")
            try checkEqual(
                tracker.cachedClassification(for: "app|obsidian|hermes-q4", budgetsVersion: 1, hasFreshOCR: true, at: t0.addingTimeInterval(200)),
                nil,
                "OCR-less cache entry must bypass once when fresh OCR arrives for the window"
            )
            tracker.storeCache(cSwitch, for: "app|obsidian|hermes-q4", budgetsVersion: 1, usedOCR: true, at: t0.addingTimeInterval(205))
            try checkEqual(
                tracker.cachedClassification(for: "app|obsidian|hermes-q4", budgetsVersion: 1, hasFreshOCR: true, at: t0.addingTimeInterval(210))?.categoryId,
                "hermes",
                "Cache entry already classified with OCR should hit cache"
            )

            // 6. Manual correction immediately commits and remembers contextKey for the day
            tracker.recordManualSelection(categoryId: "infra-billing", contextKey: "app|terminal|zsh", at: t0.addingTimeInterval(220))
            try checkEqual(tracker.currentCategoryId, "infra-billing", "Manual selection should immediately update currentCategoryId")
            try checkEqual(tracker.manualOverride(for: "app|terminal|zsh"), "infra-billing", "Manual override should be remembered for that contextKey")
        }

        try await runCheck("63. JevActivityClient two-layer & zero-project schema + response decoding via MockJevTransport") {
            let t0 = baseDate()
            let capturedRequest = LockedBox<URLRequest?>(nil)
            let mockResponseJSON = #"""
            {
              "model": "jev-1.14.0",
              "answers": {
                "activity_mode": {
                  "type": "choice",
                  "choice": "operate",
                  "confidence": 0.96,
                  "probabilities": {
                    "operate": 0.96,
                    "build": 0.02,
                    "break": 0.02
                  }
                },
                "focus_project": {
                  "type": "choice",
                  "choice": "ecommerce",
                  "confidence": 0.94,
                  "probabilities": {
                    "ecommerce": 0.95,
                    "none": 0.05
                  }
                },
                "same_task": {
                  "type": "noul",
                  "noul": 0.89
                }
              },
              "usage": {
                "input_tokens": 612,
                "output_tokens": 58
              }
            }
            """#

            let transport = MockJevTransport { request in
                capturedRequest.set(request)
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(mockResponseJSON.utf8), resp)
            }
            let client = JevActivityClient(transport: transport)
            let input = SemanticClassificationInput(
                timestamp: t0,
                contextKey: "app|photoshop|banner.psd",
                appName: "Adobe Photoshop",
                bundleId: "com.adobe.Photoshop",
                windowTitle: "banner.psd",
                url: nil,
                ocrSnippet: "SKU-101 秋季新品主图",
                redacted: false,
                recentHistory: [
                    SemanticHistoryEntry(appName: "Google Chrome", windowTitle: "Example Shop 主图管理", domain: "shop.example.com", durationSeconds: 240)
                ],
                budgets: [
                    TaskBudget(taskId: "ecommerce", displayName: "电商运营", description: "选品与主图优化", colorHex: "#3B82F6", targetMinutes: 90)
                ]
            )

            let result = try await client.classify(input: input, apiKey: "mock_key_abc", model: "jev-latest")
            try checkEqual(result.categoryId, "ecommerce", "Matched focus project should become resolved categoryId")
            try checkEqual(result.activityMode, .operate, "Parsed activityMode should match .operate")
            try checkEqual(result.focusProjectId, "ecommerce", "Parsed focusProjectId should match ecommerce")
            try checkApprox(result.confidence, 0.96, "Parsed confidence should match 0.96")
            try checkApprox(result.isDistraction, 0.02, "Parsed distraction probability should match break prob 0.02")
            try checkApprox(result.sameTaskAsPrevious ?? -1, 0.89, "Parsed same_task noul should match 0.89")

            let req = capturedRequest.get()
            try checkEqual(req?.httpMethod, "POST", "Jev endpoint must use POST")
            try checkEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer mock_key_abc", "Bearer auth header must be set")
            let bodyObj = try JSONSerialization.jsonObject(with: req?.httpBody ?? Data()) as? [String: Any]
            let questions = bodyObj?["questions"] as? [String: Any]
            let modeQ = questions?["activity_mode"] as? [String: Any]
            let modeCriteria = modeQ?["criteria"] as? [String: String]
            try checkEqual(modeCriteria?.count, ActivityMode.allCases.count, "activity_mode must include all 6 Layer-1 modes")
            try check(modeCriteria?[ActivityMode.build.rawValue]?.contains("GitHub") == true, "build criteria should explicitly cover GitHub code repositories")
            let projQ = questions?["focus_project"] as? [String: Any]
            let projCriteria = projQ?["criteria"] as? [String: String]
            try check(projCriteria?["ecommerce"]?.contains("选品与主图优化") == true, "Focus project criteria should include description")
            try check(projCriteria?["none"] != nil, "Focus project criteria should include 'none'")
            try check(questions?["same_task"] != nil, "Non-empty recentHistory should include same_task question")

            // Zero-project mode: budgets=[] must omit focus_project question
            let zeroPayload = JevActivityClient.buildRequestPayload(
                input: SemanticClassificationInput(timestamp: t0, contextKey: "app|zed|main", appName: "Zed", windowTitle: "main.swift", budgets: []),
                model: "jev-latest"
            )
            let zeroQuestions = zeroPayload["questions"] as? [String: Any]
            try check(zeroQuestions?["activity_mode"] != nil, "Zero-project payload must include activity_mode")
            try check(zeroQuestions?["focus_project"] == nil, "Zero-project payload must omit focus_project")
        }

        try await runCheck("64. DayHelmEngine auto-activity attribution for planned, otherWork & nonWork") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
            engine.setAutoTrackingActive(true)

            // Auto-attribute to otherWork for 10 minutes
            engine.applyAutoCategory(AutoActivityIds.otherWork, at: t0)
            for minute in 1...10 {
                let ts = t0.addingTimeInterval(TimeInterval(minute * 60))
                clock.advance(by: 60)
                let alerts = engine.ingest(ActivitySample(timestamp: ts, appName: "Mail", windowTitle: "Office Lease", idleSeconds: 1))
                try check(!alerts.contains(where: { if case .unassignedActivePrompt = $0.kind { return true }; return false }), "Auto-tracking should suppress manual unassignedActivePrompt")
            }
            try checkApprox(engine.otherWorkMinutes, 10.0, tolerance: 0.05, "otherWorkMinutes should accumulate 10m")

            // Switch to nonWork for 5 minutes
            let t1 = t0.addingTimeInterval(10 * 60)
            engine.applyAutoCategory(AutoActivityIds.nonWork, at: t1)
            for minute in 1...5 {
                let ts = t1.addingTimeInterval(TimeInterval(minute * 60))
                clock.advance(by: 60)
                _ = engine.ingest(ActivitySample(timestamp: ts, appName: "Google Chrome", windowTitle: "Entertainment Video", idleSeconds: 1))
            }
            try checkApprox(engine.nonWorkMinutes, 5.0, tolerance: 0.05, "nonWorkMinutes should accumulate 5m")

            // Switch to planned task ecommerce for 12 minutes
            let t2 = t1.addingTimeInterval(5 * 60)
            engine.applyAutoCategory("ecommerce", at: t2)
            for minute in 1...12 {
                let ts = t2.addingTimeInterval(TimeInterval(minute * 60))
                clock.advance(by: 60)
                _ = engine.ingest(ActivitySample(timestamp: ts, appName: "Google Chrome", windowTitle: "Example Shop", idleSeconds: 1))
            }
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 12.0, tolerance: 0.05, "Planned task should accumulate 12m automatically")
            try checkApprox(engine.otherWorkMinutes, 10.0, tolerance: 0.05, "otherWorkMinutes should stop incrementing when switched to planned task")
        }

        try await runCheck("65. Coordinator + Jev end-to-end auto-tracking, API key prompt & MenuBar text labels") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-65-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let keyStore = JevAPIKeyStore(directory: tmpDir, environment: [:], dotEnvSearchPaths: [])
            let callCount = LockedBox<Int>(0)
            let nextChoice = LockedBox<(String, Double, Double)>(("ecommerce", 0.96, 0.04))

            let mockJevTransport = MockJevTransport { request in
                callCount.modify { $0 += 1 }
                let (choice, conf, dist) = nextChoice.get()
                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "project": { "type": "choice", "choice": "\(choice)", "confidence": \(conf), "probabilities": { "\(choice)": \(conf) } },
                    "is_distraction": { "type": "noul", "noul": \(dist) },
                    "same_task_as_previous": { "type": "noul", "noul": 0.12 }
                  },
                  "usage": { "input_tokens": 500, "output_tokens": 40 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
            let inspector = MockInspector(currentSample: ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Example Shop — 主图优化",
                url: "https://shop.example.com/item/1",
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))
            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspector,
                    clock: clock,
                    jevClient: JevActivityClient(transport: mockJevTransport),
                    jevAPIKeyStore: keyStore
                )
            }

            // Enable Jev without key -> should flag jevNeedsAPIKey and make 0 API calls
            await MainActor.run {
                var s = coordinator.recorderSettings
                s.jevAutoTrackingEnabled = true
                s.menuBarDisplayMode = .standard
                coordinator.updateRecorderSettings(s)
            }
            try await MainActor.run {
                try checkEqual(coordinator.jevNeedsAPIKey, true, "Enabling Jev without key must prompt user for API key")
                coordinator.pollOnce()
            }
            clock.advance(by: 6)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Shop — 主图优化", url: "https://shop.example.com/item/1", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try checkEqual(callCount.get(), 0, "Missing API key must make zero outbound Jev calls")

            // Configure API key -> auto-classifies after >= 4s dwell and updates MenuBar label
            try await MainActor.run {
                try coordinator.saveJevAPIKey("synthetic_live_key")
                try checkEqual(coordinator.jevNeedsAPIKey, false, "Saving API key should clear jevNeedsAPIKey prompt")
                coordinator.pollOnce()
            }
            try await waitUntil("Jev cold-start auto-attribution to ecommerce") {
                await MainActor.run {
                    if case .focusing(let id, _) = coordinator.sessionState, id == "ecommerce" {
                        return true
                    }
                    return false
                }
            }
            try await MainActor.run {
                try check(coordinator.pillModel.text.hasPrefix("电商做深 "), "Menu bar should display text label for auto-tracked project (got: \(coordinator.pillModel.text))")
            }

            // Polling same window again hits cache (still 1 API call)
            clock.advance(by: 60)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Example Shop — 主图优化", url: "https://shop.example.com/item/1", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try checkEqual(callCount.get(), 1, "Repeated polling of same cached context must not re-call Jev")
            try await MainActor.run {
                try checkEqual(coordinator.pillModel.text, "电商做深 1/90m", "Auto-attributed planned task should accumulate 1m in menu bar")
            }

            // Switch to otherWork -> fast switch at >= 8s dwell -> menu bar shows Layer-1 ActivityMode (沟通杂务)
            nextChoice.set((AutoActivityIds.otherWork, 0.95, 0.05))
            clock.advance(by: 2)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Office Lease Contract", url: nil, idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 5)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Office Lease Contract", url: nil, idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Jev classifies Mail as otherWork") {
                callCount.get() >= 2
            }
            clock.advance(by: 10)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Office Lease Contract", url: nil, idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 60)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Mail", bundleId: "com.apple.mail", windowTitle: "Office Lease Contract", url: nil, idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.pillModel.visualState, .otherWork, "Menu bar visualState should reflect otherWork")
                try checkEqual(coordinator.pillModel.text, "沟通杂务 1m", "Menu bar should show Layer-1 ActivityMode label + elapsed minutes when no focus project matches")
            }

            // Switch to nonWork (distraction) -> menu bar shows 休息分心
            nextChoice.set((AutoActivityIds.nonWork, 0.98, 0.95))
            clock.advance(by: 2)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Fun Video - Bilibili", url: "https://www.bilibili.com/video/1", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 5)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Fun Video - Bilibili", url: "https://www.bilibili.com/video/1", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Jev classifies Bilibili as nonWork") {
                callCount.get() >= 3
            }
            clock.advance(by: 10)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Fun Video - Bilibili", url: "https://www.bilibili.com/video/1", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 60)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Fun Video - Bilibili", url: "https://www.bilibili.com/video/1", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.pillModel.visualState, .distraction, "Menu bar visualState should reflect distraction")
                try checkEqual(coordinator.pillModel.text, "休息分心 1m", "Menu bar should show Layer-1 break label + elapsed minutes for distraction")
            }
        }

        try await runCheck("66. JevDecisionLogEntry recording, persistence, metrics & clearing") {
            let t0 = baseDate()
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-66-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let keyStore = JevAPIKeyStore(directory: tmpDir, environment: [:], dotEnvSearchPaths: [])
            try keyStore.saveKey("synthetic_log_key")

            let mockJevTransport = MockJevTransport { request in
                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "project": { "type": "choice", "choice": "infra-billing", "confidence": 0.93, "probabilities": { "infra-billing": 0.94 } },
                    "is_distraction": { "type": "noul", "noul": 0.04 },
                    "same_task_as_previous": { "type": "noul", "noul": 0.11 }
                  },
                  "usage": { "input_tokens": 688, "output_tokens": 42 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
            let inspector = MockInspector(currentSample: ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "AWS Cost Explorer - Billing",
                url: "https://console.aws.amazon.com/costmanagement",
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true
            ))

            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspector,
                    clock: clock,
                    jevClient: JevActivityClient(transport: mockJevTransport),
                    jevAPIKeyStore: keyStore
                )
            }

            await MainActor.run {
                var s = coordinator.recorderSettings
                s.jevAutoTrackingEnabled = true
                coordinator.updateRecorderSettings(s)
                coordinator.pollOnce()
            }
            clock.advance(by: 5)
            await MainActor.run {
                inspector.currentSample = ActivitySample(
                    timestamp: clock.now(),
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "AWS Cost Explorer - Billing",
                    url: "https://console.aws.amazon.com/costmanagement",
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
                coordinator.pollOnce()
            }

            try await waitUntil("Jev decision log recorded") {
                await MainActor.run { !coordinator.jevDecisionLogs.isEmpty }
            }

            try await MainActor.run {
                let first = try {
                    guard let entry = coordinator.jevDecisionLogs.first else {
                        throw CheckFailure(description: "Expected at least one JevDecisionLogEntry")
                    }
                    return entry
                }()
                try checkEqual(first.predictedCategoryId, "infra-billing", "Log entry should capture predictedCategoryId")
                try checkEqual(first.predictedDisplayName, "Infra 维护", "Log entry should resolve displayName")
                try checkEqual(first.outcome, .committedSwitch, "Cold-start high-confidence should log committedSwitch")
                try checkEqual(first.inputTokens, 688, "Log entry should capture inputTokens")
                try checkEqual(first.domain, "amazon.com", "Log entry should capture registrable domain")
                try checkEqual(coordinator.pillModel.text, "Infra 维护 0/30m", "Menu bar should show full 'Infra 维护' without ellipsis")

                let persisted = store.loadJevDecisionLogs(forDate: DayHelmDateFormatting.dayString(from: t0))
                try checkEqual(persisted.count, 1, "Jev decision log should persist to jev-log.json for current day")

                coordinator.clearJevDecisionLogs()
                try checkEqual(coordinator.jevDecisionLogs.count, 0, "clearJevDecisionLogs should clear in-memory logs")
                try checkEqual(store.loadJevDecisionLogs(forDate: DayHelmDateFormatting.dayString(from: t0)).count, 0, "clearJevDecisionLogs should clear persisted logs")
            }
        }

        try await runCheck("67. Zero-project Layer-1 auto-tracking, semantic switch suppression & OCR gating") {
            let t0 = baseDate()

            // 1. OCR gating: strong single-purpose title skips OCR; weak titles & multi-purpose dashboards/workbenches attach body-cleaned OCR
            try checkEqual(SemanticPayloadSanitizer.shouldAttachOCR(appName: "Google Chrome", windowTitle: "商品上货-抖店妙手", url: "https://shop.example.com/move"), false, "Clear single-purpose title+URL should skip full-screen OCR")
            try checkEqual(SemanticPayloadSanitizer.shouldAttachOCR(appName: "Google Chrome", windowTitle: "Hermes Agent - Dashboard - Google Chrome", url: "http://127.0.0.1:8787/dashboard"), true, "Multi-purpose Hermes Dashboard must attach body OCR")
            try checkEqual(SemanticPayloadSanitizer.shouldAttachOCR(appName: "Google Chrome", windowTitle: "Discord | 电商计划", url: "https://discord.com/channels/1/2"), true, "Multi-purpose Discord channel must attach body OCR")
            try checkEqual(SemanticPayloadSanitizer.shouldAttachOCR(appName: "QQ", windowTitle: "QQ", url: nil), true, "Weak app-only title should attach OCR")
            try checkEqual(SemanticPayloadSanitizer.shouldAttachOCR(appName: "Obsidian", windowTitle: "2026-11-19 - Vault", url: nil), true, "Date-only journal title should attach OCR")
            let noisyOCR = "Chrome 文件 编辑 显示 历史记录 书签 个人资料 标签页 窗口 帮助\n正文第一行 电商选品分析"
            let cleanedOCR = SemanticPayloadSanitizer.stripTopChromeNoise(from: noisyOCR)
            try check(!cleanedOCR.contains("历史记录"), "stripTopChromeNoise should drop leading macOS menu-bar line")
            try check(cleanedOCR.contains("电商选品分析"), "stripTopChromeNoise should preserve body text")

            // Address-bar anchor stripping removes macOS menu bar + Chrome background tabs and keeps Hermes body
            let browserOCR = [
                "Chrome 文件 编辑 显示 历史记录 书签 窗口 帮助",
                "开发构建 12m  11:24",
                "GitHub - focus-guard  |  Claude  |  Hermes Agent - Dashboard",
                "http://127.0.0.1:8787/dashboard",
                "Hermes Agent",
                "电商任务看板 · 抖店选品与主图巡检 · 每日定时任务"
            ].joined(separator: "\n")
            let browserBody = SemanticPayloadSanitizer.stripTopChromeNoise(from: browserOCR, url: "http://127.0.0.1:8787/dashboard")
            try check(!browserBody.contains("GitHub - focus-guard"), "Address-bar anchored stripping must drop Chrome background tab titles")
            try check(browserBody.contains("电商任务看板"), "Address-bar anchored stripping must keep actual page body")

            // Fine-grained semanticContextKey distinguishes different pages/channels on same domain while ignoring unread badge jitter
            let discordEcom = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "(413) Discord | 电商计划 - Google Chrome", url: "https://discord.com/channels/1/2", idleSeconds: 0)
            let discordEcomUnread = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "(414) Discord | 电商计划 - Google Chrome", url: "https://discord.com/channels/1/2", idleSeconds: 0)
            let discordDev = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Discord | 内容创作 - Google Chrome", url: "https://discord.com/channels/1/3", idleSeconds: 0)
            try checkEqual(
                SemanticPayloadSanitizer.semanticContextKey(for: discordEcom),
                SemanticPayloadSanitizer.semanticContextKey(for: discordEcomUnread),
                "Unread count jitter should share the same semanticContextKey"
            )
            try check(
                SemanticPayloadSanitizer.semanticContextKey(for: discordEcom) != SemanticPayloadSanitizer.semanticContextKey(for: discordDev),
                "Different Discord channels on discord.com must have distinct semanticContextKeys"
            )
            try checkEqual(JevDecisionOutcome.pendingConfirmation.displayName, "防抖观察", "Pending outcome label must clarify automatic anti-flicker dwell, not user confirmation")

            // Auxiliary overlays & blank browser new-tab transitions should skip outbound Jev calls
            let xnipSample = ActivitySample(timestamp: t0, appName: "Xnip Helper", bundleId: "com.xnipapp.Xnip", windowTitle: "Window", url: nil, idleSeconds: 0)
            let newTabSample = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "新标签页 - Google Chrome", url: "chrome://newtab/", idleSeconds: 0)
            let wechatSample = ActivitySample(timestamp: t0, appName: "微信", bundleId: "com.tencent.xinWeChat", windowTitle: nil, url: nil, idleSeconds: 0, redacted: true)
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: xnipSample), true, "Screenshot helper overlay should skip Jev")
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: newTabSample), true, "Blank browser New Tab page should skip Jev")
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: wechatSample), false, "Redacted WeChat must still be classified as comms_admin")

            // 2. Semantic switch suppression: 12 rapid cross-app spans in same semanticGroup "mode:build" produce 0 thrashing windows
            var sameSemSpans: [EnrichedSpan] = []
            let apps = [("T3 Code", "com.t3.code", "A.swift"), ("Google Chrome", "com.google.Chrome", "Claude"), ("Ghostty", "com.mitchellh.ghostty", "zsh"), ("Electron", "com.electron.dev", "Preview")]
            for i in 0..<14 {
                let s = t0.addingTimeInterval(Double(i * 15))
                let item = apps[i % apps.count]
                sameSemSpans.append(EnrichedSpan(
                    startedAt: s,
                    endedAt: s.addingTimeInterval(14),
                    appName: item.0,
                    bundleId: item.1,
                    windowTitle: "\(item.2) \(i)",
                    url: item.0 == "Google Chrome" ? "https://claude.ai/chat/\(i)" : nil,
                    semanticGroup: "mode:build"
                ))
            }
            let semThrashing = SpectrumBuilder.detectThrashingWindows(spans: sameSemSpans, budgets: [])
            try checkEqual(semThrashing.count, 0, "Cross-app collaboration sharing the same semanticGroup must never trigger thrashing")

            // 3. Zero-project coordinator flow: budgets == [] automatically displays Layer-1 ActivityMode in MenuBar
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-67-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let keyStore = JevAPIKeyStore(directory: tmpDir, environment: [:], dotEnvSearchPaths: [])
            try keyStore.saveKey("synthetic_zero_proj_key")

            let nextMode = LockedBox<(String, Double)>((ActivityMode.build.rawValue, 0.96))
            let mockTransport = MockJevTransport { request in
                let (m, conf) = nextMode.get()
                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "activity_mode": { "type": "choice", "choice": "\(m)", "confidence": \(conf), "probabilities": { "\(m)": \(conf) } },
                    "same_task": { "type": "noul", "noul": 0.10 }
                  },
                  "usage": { "input_tokens": 520, "output_tokens": 30 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engine = DayHelmEngine(budgets: [], clock: clock)
            let inspector = MockInspector(currentSample: ActivitySample(timestamp: t0, appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0))
            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspector,
                    clock: clock,
                    jevClient: JevActivityClient(transport: mockTransport),
                    jevAPIKeyStore: keyStore
                )
            }

            await MainActor.run {
                var s = coordinator.recorderSettings
                s.jevAutoTrackingEnabled = true
                coordinator.updateRecorderSettings(s)
                coordinator.pollOnce()
            }
            clock.advance(by: 5)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Zero-project cold-start auto-classifies as build") {
                await MainActor.run { coordinator.activeActivityMode == .build }
            }
            clock.advance(by: 60)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.pillModel.text, "开发构建 1m", "Zero-project mode should display Layer-1 ActivityMode + elapsed minutes")
                try checkEqual(coordinator.pillModel.visualState, .focusing, "Active build mode should show focusing dot")
            }

            // Switch to break -> menu bar shows 休息分心
            nextMode.set((ActivityMode.breakTime.rawValue, 0.99))
            clock.advance(by: 2)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X", url: "https://x.com/home", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 5)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X", url: "https://x.com/home", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Jev classifies X home as break") {
                await MainActor.run { coordinator.jevDecisionLogs.first?.activityMode == .breakTime }
            }
            clock.advance(by: 10)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X", url: "https://x.com/home", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 60)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X", url: "https://x.com/home", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.pillModel.text, "休息分心 1m", "Break mode should display 休息分心 in menu bar")
                try checkEqual(coordinator.pillModel.visualState, .distraction, "Break mode should show distraction red dot")
            }
        }

        try await runCheck("68. 3-minute idle backtrack deduction, auto-resume vs manual pause, sleep & gap cap") {
            let t0 = baseDate()

            // 1. Default idle threshold is 3 minutes (180s / 180_000ms)
            try checkApprox(DayHelmEngineConfig.default.idleThresholdSeconds, 180.0, "Default DayHelmEngineConfig idle threshold must be 180s (3m)")
            try checkEqual(DayHelmSettings.default.recorderIdleThresholdMs, 180_000, "Default DayHelmSettings recorderIdleThresholdMs must be 180_000ms (3m)")

            // 2. Live 2s polling: 5m active + 3m walking away (idle ramps 2..180s) -> backtracks the 3m idle time cleanly
            let clock = ManualClock(now: t0)
            let engine = DayHelmEngine(
                budgets: sampleBudgets(),
                clock: clock,
                config: DayHelmEngineConfig(maxTickGapSeconds: 60.0)
            )
            engine.applyAutoCategory("ecommerce", activityMode: .operate, at: t0)

            // 5 minutes of active work (2s ticks)
            for step in 1...150 {
                let ts = t0.addingTimeInterval(TimeInterval(step * 2))
                clock.advance(by: 2)
                engine.ingest(ActivitySample(timestamp: ts, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: 0, screenLocked: false, inputActive: true))
            }
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 5.0, tolerance: 0.05, "5m active work should accumulate 5.0m")
            try checkApprox(engine.activityModeMinutes[ActivityMode.operate.rawValue] ?? 0, 5.0, tolerance: 0.05, "Layer-1 operate mode should accumulate 5.0m")

            // User walks away without locking screen: idle climbs 2s..180s over 3 minutes
            let leaveAt = t0.addingTimeInterval(300)
            for step in 1...90 {
                let idleSec = TimeInterval(step * 2)
                let ts = leaveAt.addingTimeInterval(idleSec)
                clock.advance(by: 2)
                engine.ingest(ActivitySample(timestamp: ts, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: idleSec, screenLocked: false, inputActive: false))
            }
            let pausedAt = leaveAt.addingTimeInterval(180)
            try checkEqual(engine.focusState, .paused(taskId: "ecommerce", pausedAt: pausedAt), "Idle >= 180s must auto-pause focus")
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 5.0, tolerance: 0.05, "3m unoperated idle tail must be backtracked & deducted from focusedMinutes")
            try checkApprox(engine.activityModeMinutes[ActivityMode.operate.rawValue] ?? 0, 5.0, tolerance: 0.05, "3m unoperated idle tail must be backtracked & deducted from activityModeMinutes")

            // 3. Returning after auto-pause automatically resumes focus without manual click
            let returnAt = pausedAt.addingTimeInterval(120)
            clock.advance(by: 120)
            engine.ingest(ActivitySample(timestamp: returnAt, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: 0, screenLocked: false, inputActive: true))
            if case .focusing(let resumedId, _) = engine.focusState {
                try checkEqual(resumedId, "ecommerce", "Returning after idle auto-pause must auto-resume the previous focus task")
            } else {
                throw CheckFailure(description: "Expected auto-resume to .focusing after idle auto-pause, got \(engine.focusState)")
            }
            // Active 1 minute after returning
            for step in 1...30 {
                let ts = returnAt.addingTimeInterval(TimeInterval(step * 2))
                clock.advance(by: 2)
                engine.ingest(ActivitySample(timestamp: ts, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: 0, screenLocked: false, inputActive: true))
            }
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 6.0, tolerance: 0.05, "Auto-resumed session should accumulate +1m (total 6.0m)")

            // 4. System sleep (2 hours) + wake must add 0.0m, and >60s sudden wall-clock jump must also add 0.0m
            let sleepAt = returnAt.addingTimeInterval(60)
            engine.handleSystemSleep(at: sleepAt)
            let wakeAt = sleepAt.addingTimeInterval(7200)
            clock.advance(by: 7200)
            engine.ingest(ActivitySample(timestamp: wakeAt, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: 0, screenLocked: false, inputActive: true))
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 6.0, tolerance: 0.05, "2-hour system sleep must never add active minutes")

            // Sudden unannounced 30-minute wall-clock jump (even without will_sleep) must be rejected by maxTickGapSeconds
            let jumpAt = wakeAt.addingTimeInterval(1800)
            clock.advance(by: 1800)
            engine.ingest(ActivitySample(timestamp: jumpAt, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: 0, screenLocked: false, inputActive: true))
            try checkApprox(engine.focusedMinutes(for: "ecommerce"), 6.0, tolerance: 0.05, "Tick gap > maxTickGapSeconds (60s) must not accumulate ghost time")

            // 5. Manual pause must NOT auto-resume when user stays active
            engine.pauseFocus(at: jumpAt)
            let afterManualPause = jumpAt.addingTimeInterval(10)
            clock.advance(by: 10)
            engine.ingest(ActivitySample(timestamp: afterManualPause, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop", url: "https://shop.example.com", idleSeconds: 0, screenLocked: false, inputActive: true))
            try checkEqual(engine.focusState, .paused(taskId: "ecommerce", pausedAt: jumpAt), "Manual pause must remain paused even when active samples arrive")

            // 6. Zero-project Layer-1 ActivityMode also backtracks 3m idle cleanly
            let zeroClock = ManualClock(now: t0)
            let zeroEngine = DayHelmEngine(budgets: [], clock: zeroClock, config: DayHelmEngineConfig(maxTickGapSeconds: 60.0))
            zeroEngine.applyAutoCategory(AutoActivityIds.modeCategoryId(for: .build), activityMode: .build, at: t0)
            for step in 1...120 { // 4m active
                let ts = t0.addingTimeInterval(TimeInterval(step * 2))
                zeroClock.advance(by: 2)
                zeroEngine.ingest(ActivitySample(timestamp: ts, appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", url: nil, idleSeconds: 0))
            }
            for step in 1...90 { // 3m idle
                let idleSec = TimeInterval(step * 2)
                let ts = t0.addingTimeInterval(240 + idleSec)
                zeroClock.advance(by: 2)
                zeroEngine.ingest(ActivitySample(timestamp: ts, appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", url: nil, idleSeconds: idleSec))
            }
            try checkApprox(zeroEngine.activityModeMinutes[ActivityMode.build.rawValue] ?? 0, 4.0, tolerance: 0.05, "Zero-project Layer-1 mode must backtrack & deduct 3m idle tail (keep exact 4.0m)")
        }

        try await runCheck("69. Sub-2s event-driven Jev switching, anti-flicker Cmd+Tab filtering & cache dwell protection") {
            let t0 = baseDate()

            // Part A: Deterministic Cmd+Tab & cached pass-through anti-flicker + zero API surge
            let clock = ManualClock(now: t0)
            let tmpDirA = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-69a-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDirA, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDirA) }

            let storeA = DayHelmStore(directory: tmpDirA)
            let keyStoreA = JevAPIKeyStore(directory: tmpDirA, environment: [:], dotEnvSearchPaths: [])
            try keyStoreA.saveKey("synthetic_fast_key")

            let callsA = LockedBox<Int>(0)
            let nextResponseA = LockedBox<(String, Double, Double)>((ActivityMode.build.rawValue, 0.95, 0.10))
            let mockTransportA = MockJevTransport { request in
                callsA.modify { $0 += 1 }
                let (mode, conf, same) = nextResponseA.get()
                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "activity_mode": { "type": "choice", "choice": "\(mode)", "confidence": \(conf), "probabilities": { "\(mode)": \(conf) } },
                    "same_task": { "type": "noul", "noul": \(same) }
                  },
                  "usage": { "input_tokens": 500, "output_tokens": 20 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engineA = DayHelmEngine(budgets: [], clock: clock)
            let inspectorA = MockInspector(currentSample: ActivitySample(timestamp: t0, appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0))
            let coordA = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engineA,
                    store: storeA,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspectorA,
                    clock: clock,
                    jevClient: JevActivityClient(transport: mockTransportA),
                    jevAPIKeyStore: keyStoreA
                )
            }

            await MainActor.run {
                var s = coordA.recorderSettings
                s.jevAutoTrackingEnabled = true
                s.menuBarDisplayMode = .standard
                coordA.updateRecorderSettings(s)
                // Event-driven app_focus starts dwell tracking immediately without pollOnce()
                coordA.handleMonitorEventForTesting(NativeMonitorEvent(timestamp: clock.now(), kind: "app_focus", appName: "Zed", bundleId: "dev.zed.Zed"))
            }
            clock.advance(by: 0.95)
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordA.handleWindowContextChangedForTesting()
            }
            try await waitUntil("app_focus + 0.95s dwell classifies Zed as build") {
                await MainActor.run { coordA.activeActivityMode == .build }
            }
            try checkEqual(callsA.get(), 1, "Initial classification should take 1 Jev call")

            // Rapid Cmd+Tab cycling across 3 apps (300ms / 400ms / 300ms, all < 0.9s) must produce 0 Jev calls and 0 flicker
            nextResponseA.set((ActivityMode.breakTime.rawValue, 0.98, 0.05))
            let blips: [(String, String, String, String?, TimeInterval)] = [
                ("Google Chrome", "com.google.Chrome", "Bilibili Video", "https://www.bilibili.com/video/1", 0.3),
                ("Mail", "com.apple.mail", "Inbox", nil, 0.4),
                ("Google Chrome", "com.google.Chrome", "X Home", "https://x.com/home", 0.3)
            ]
            for (app, bundle, title, url, step) in blips {
                clock.advance(by: step)
                await MainActor.run {
                    inspectorA.currentSample = ActivitySample(timestamp: clock.now(), appName: app, bundleId: bundle, windowTitle: title, url: url, idleSeconds: 0)
                    coordA.handleMonitorEventForTesting(NativeMonitorEvent(timestamp: clock.now(), kind: "app_focus", appName: app, bundleId: bundle))
                }
            }
            try await MainActor.run {
                try checkEqual(callsA.get(), 1, "Rapid <0.9s Cmd+Tab blips must trigger 0 outbound Jev calls")
                try checkEqual(coordA.activeActivityMode, .build, "Rapid <0.9s Cmd+Tab blips must not flicker active mode")
            }

            // Settle on X Home for 0.95s -> switches to breakTime (call #2)
            clock.advance(by: 0.95)
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "X Home", url: "https://x.com/home", idleSeconds: 0)
                coordA.handleWindowContextChangedForTesting()
            }
            try await waitUntil("Settling 0.95s on X Home switches to breakTime") {
                await MainActor.run { coordA.activeActivityMode == .breakTime }
            }
            try checkEqual(callsA.get(), 2, "Settling on X Home should trigger 1 Jev call")

            // Cached pass-through back to Zed for only 0.2s (< 0.45s cacheSwitchDwellSeconds) must NOT flicker toolbar
            clock.advance(by: 0.2)
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordA.handleMonitorEventForTesting(NativeMonitorEvent(timestamp: clock.now(), kind: "app_focus", appName: "Zed", bundleId: "dev.zed.Zed"))
            }
            try await MainActor.run {
                try checkEqual(coordA.activeActivityMode, .breakTime, "0.2s pass-through over a cached app must not immediately flicker toolbar")
            }
            // Stay on cached Zed for 0.5s (>= 0.45s) -> commits from cache with 0 extra Jev calls
            clock.advance(by: 0.5)
            try await MainActor.run {
                inspectorA.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordA.handleWindowContextChangedForTesting()
                try checkEqual(coordA.activeActivityMode, .build, "Settling >=0.45s on cached app must switch toolbar from cache")
                try checkEqual(callsA.get(), 2, "Cached switch must make 0 additional Jev calls")
            }

            // Part B: Real wall-clock timer-driven sub-2s E2E check (simulated 220ms Jev RTT, ZERO pollOnce calls!)
            let tmpDirB = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-69b-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDirB, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDirB) }

            let storeB = DayHelmStore(directory: tmpDirB)
            let keyStoreB = JevAPIKeyStore(directory: tmpDirB, environment: [:], dotEnvSearchPaths: [])
            try keyStoreB.saveKey("synthetic_live_timer_key")

            let callsB = LockedBox<Int>(0)
            let nextResponseB = LockedBox<(String, Double, Double)>((ActivityMode.breakTime.rawValue, 0.96, 0.05))
            let mockTransportB = MockJevTransport { request in
                callsB.modify { $0 += 1 }
                try await Task.sleep(nanoseconds: 220_000_000) // Realistic 220ms Jev p50 RTT
                let (mode, conf, same) = nextResponseB.get()
                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "activity_mode": { "type": "choice", "choice": "\(mode)", "confidence": \(conf), "probabilities": { "\(mode)": \(conf) } },
                    "same_task": { "type": "noul", "noul": \(same) }
                  },
                  "usage": { "input_tokens": 500, "output_tokens": 20 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let sysClock = SystemClock()
            let engineB = DayHelmEngine(budgets: [], clock: sysClock)
            let inspectorB = MockInspector(currentSample: ActivitySample(timestamp: sysClock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X - Google Chrome", url: "https://x.com/home", idleSeconds: 0))
            let coordB = await MainActor.run {
                let c = HybridActivityCoordinator(
                    engine: engineB,
                    store: storeB,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspectorB,
                    clock: sysClock,
                    jevClient: JevActivityClient(transport: mockTransportB),
                    jevAPIKeyStore: keyStoreB
                )
                c.enableLiveTimersForTesting = true
                var s = c.recorderSettings
                s.jevAutoTrackingEnabled = true
                s.menuBarDisplayMode = .standard
                c.updateRecorderSettings(s)
                return c
            }
            defer {
                Task { @MainActor in coordB.stop() }
            }

            // 1. Cross-app switch via app_focus (NO pollOnce called!) -> must finish < 1.8s
            let tSwitch1 = Date()
            await MainActor.run {
                inspectorB.currentSample = ActivitySample(timestamp: sysClock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X - Google Chrome", url: "https://x.com/home", idleSeconds: 0)
                coordB.handleMonitorEventForTesting(NativeMonitorEvent(timestamp: sysClock.now(), kind: "app_focus", appName: "Google Chrome", bundleId: "com.google.Chrome"))
            }
            try await waitUntil("Sub-2s cross-app switch updates pillModel to break", timeoutSeconds: 2.5) {
                await MainActor.run { coordB.pillModel.text.hasPrefix("休息分心") }
            }
            let elapsed1 = Date().timeIntervalSince(tSwitch1)
            try check(elapsed1 < 1.8, "Cross-app switch with 220ms Jev RTT must complete < 1.8s (actual: \(String(format: "%.2f", elapsed1))s)")
            try checkEqual(callsB.get(), 1, "Cross-app switch should make exactly 1 Jev call")

            // 2. Same-browser tab switch via AX window_context_changed (NO pollOnce!) -> must finish < 1.8s
            nextResponseB.set((ActivityMode.build.rawValue, 0.94, 0.08))
            let tSwitch2 = Date()
            await MainActor.run {
                inspectorB.currentSample = ActivitySample(timestamp: sysClock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "focus-guard Pull Request - Google Chrome", url: "https://github.com/org/focus-guard/pull/1", idleSeconds: 0)
                coordB.handleWindowContextChangedForTesting()
            }
            try await waitUntil("Sub-2s same-browser tab switch updates pillModel to build", timeoutSeconds: 2.5) {
                await MainActor.run { coordB.pillModel.text.hasPrefix("开发构建") }
            }
            let elapsed2 = Date().timeIntervalSince(tSwitch2)
            try check(elapsed2 < 1.8, "Same-browser tab switch with 220ms Jev RTT must complete < 1.8s (actual: \(String(format: "%.2f", elapsed2))s)")
            try checkEqual(callsB.get(), 2, "Same-browser tab switch should make exactly 1 additional Jev call")

            // 3. Cached tab return via AX window_context_changed -> must finish < 0.9s with 0 new Jev calls
            let tSwitch3 = Date()
            await MainActor.run {
                inspectorB.currentSample = ActivitySample(timestamp: sysClock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "主页 / X - Google Chrome", url: "https://x.com/home", idleSeconds: 0)
                coordB.handleWindowContextChangedForTesting()
            }
            try await waitUntil("Cached tab return switches pillModel back to break", timeoutSeconds: 1.5) {
                await MainActor.run { coordB.pillModel.text.hasPrefix("休息分心") }
            }
            let elapsed3 = Date().timeIntervalSince(tSwitch3)
            try check(elapsed3 < 0.9, "Cached tab return must complete < 0.9s (actual: \(String(format: "%.2f", elapsed3))s)")
            try checkEqual(callsB.get(), 2, "Cached tab return must make 0 additional Jev calls")

            // 4. Ambiguous switch (0.77 / same=0.30) commits via precision pending confirm timer without pollOnce()
            nextResponseB.set((ActivityMode.operate.rawValue, 0.77, 0.30))
            let tSwitch4 = Date()
            await MainActor.run {
                inspectorB.currentSample = ActivitySample(timestamp: sysClock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "商家后台 - 订单管理 - Google Chrome", url: "https://shop.example.com/orders", idleSeconds: 0)
                coordB.handleWindowContextChangedForTesting()
            }
            try await waitUntil("Precision pending confirm timer commits ambiguous switch without pollOnce", timeoutSeconds: 3.5) {
                await MainActor.run { coordB.pillModel.text.hasPrefix("业务运营") }
            }
            let elapsed4 = Date().timeIntervalSince(tSwitch4)
            try check(elapsed4 >= 1.8 && elapsed4 < 3.0, "Ambiguous switch should respect 0.65s dwell + 0.22s RTT + 1.2s confirm (actual: \(String(format: "%.2f", elapsed4))s)")
        }

        try await runCheck("70. Calibrated Jev prompt criteria, self-hosted web OCR gating, transient Chrome skip & single-shot on-demand OCR wait") {
            let t0 = baseDate()

            // 1. JevActivityClient.buildRequestPayload prompt calibration
            let payload = JevActivityClient.buildRequestPayload(
                input: SemanticClassificationInput(
                    timestamp: t0,
                    contextKey: "app|electron|doujia",
                    appName: "Electron",
                    windowTitle: "豆荚 — 抖店多店智能运营工作台",
                    budgets: []
                ),
                model: "jev-latest"
            )
            let questions = payload["questions"] as? [String: Any]
            let modeQ = questions?["activity_mode"] as? [String: Any]
            let modeInstructions = modeQ?["instructions"] as? String ?? ""
            let modeCriteria = modeQ?["criteria"] as? [String: String] ?? [:]

            let buildText = modeCriteria[ActivityMode.build.rawValue] ?? ""
            let createText = modeCriteria[ActivityMode.create.rawValue] ?? ""
            let researchText = modeCriteria[ActivityMode.research.rawValue] ?? ""
            let commsText = modeCriteria[ActivityMode.commsAdmin.rawValue] ?? ""
            let breakText = modeCriteria[ActivityMode.breakTime.rawValue] ?? ""

            try check(
                (commsText.contains("SheerID") || modeInstructions.contains("SheerID"))
                    && (breakText.contains("SheerID") || modeInstructions.contains("NEVER 'break'") || modeInstructions.contains("不归入此类")),
                "activity_mode must route SheerID/subscription verification to comms_admin/research and never break"
            )
            try check(
                modeInstructions.contains("OpenMausBot") || (researchText.contains("Discord") && modeInstructions.contains("#general")),
                "activity_mode must keep open-source project Discord channels (e.g. #general | OpenMausBot) in research/build, not break"
            )
            try check(
                (createText.contains("Podcast Draft") || modeInstructions.contains("Podcast Draft"))
                    && (createText.contains("obsidian") || modeInstructions.contains("obsidian")),
                "activity_mode must route IDE/AI coding tool content review (obsidian / Podcast Draft) to create"
            )
            try check(
                modeInstructions.contains("Electron") && (modeInstructions.contains("运营工作台") || buildText.contains("Electron")),
                "activity_mode must prioritize unbundled local Electron dev process as build regardless of business title words"
            )

            // 2. Self-hosted / short-title web workbench OCR gating (preserving known sites & normal multi-clause titles)
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "MausBot - Google Chrome",
                    url: "https://maus-bot.lban2049.xyz/"
                ),
                true,
                "Short-title self-hosted web workbench MausBot must attach OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "MausBot",
                    url: "https://maus-bot.lban2049.xyz/chat"
                ),
                true,
                "Short-title MausBot even with subpath must attach OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "Memo Inbox - Google Chrome",
                    url: "https://memo.lban2049.xyz/"
                ),
                true,
                "Short/generic self-hosted web app Memo Inbox must attach OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "入站 - Google Chrome",
                    url: "https://maus-bot.lban2049.xyz/inbound"
                ),
                true,
                "Short generic CJK web title 入站 must attach OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "My Custom Workbench Overview",
                    url: "https://app.lban2049.xyz/"
                ),
                true,
                "Custom subdomain root workbench without explicit path semantics must attach OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "商品上货-抖店妙手",
                    url: "https://shop.example.com/move"
                ),
                false,
                "Clear CJK two-clause title with explicit path must continue skipping OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "focus-guard Pull Request - Google Chrome",
                    url: "https://github.com/org/focus-guard/pull/1"
                ),
                false,
                "Known dev site GitHub PR page must skip OCR"
            )
            try checkEqual(
                SemanticPayloadSanitizer.shouldAttachOCR(
                    appName: "Google Chrome",
                    windowTitle: "Hacker News",
                    url: "https://news.ycombinator.com/"
                ),
                false,
                "Known content site Hacker News must skip OCR"
            )

            // 3. Transient Chrome loading & account-sync overlays skip semantic classification
            let untitledChrome = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "无标题 - Google Chrome",
                url: nil,
                idleSeconds: 0
            )
            let untitledLoadingURL = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Untitled - Google Chrome",
                url: "https://example.com/loading",
                idleSeconds: 0
            )
            let chromeSyncPopup = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "账号和同步",
                url: nil,
                idleSeconds: 0
            )
            let chromeSyncPopupWithSuffix = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "账号和同步 - Google Chrome",
                url: nil,
                idleSeconds: 0
            )
            let realSyncArticle = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "账号和同步机制解析 - Google Chrome",
                url: "https://docs.example.com/sync-guide",
                idleSeconds: 0
            )
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: untitledChrome), true, "Chrome 无标题 loading window must skip Jev")
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: untitledLoadingURL), true, "Chrome Untitled loading window must skip Jev")
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: chromeSyncPopup), true, "Chrome 账号和同步 popup without URL must skip Jev")
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: chromeSyncPopupWithSuffix), true, "Chrome 账号和同步 - Google Chrome popup without URL must skip Jev")
            try checkEqual(SemanticPayloadSanitizer.shouldSkipSemanticClassification(sample: realSyncArticle), false, "Real web article with URL must NOT be skipped")

            // 4. On-demand OCR wait window eliminates noOCR->OCR double-fire & degrades cleanly on timeout
            // 4a. Clock-injected deterministic timeout fallback + single OCR-ready dispatch (no GUI, no network)
            let clock = ManualClock(now: t0)
            let tmpDirA = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-70a-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDirA, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDirA) }

            let storeA = DayHelmStore(directory: tmpDirA)
            let keyStoreA = JevAPIKeyStore(directory: tmpDirA, environment: [:], dotEnvSearchPaths: [])
            try keyStoreA.saveKey("synthetic_ocr_wait_key")

            let dbA = try ActivityDatabase(databaseURL: storeA.databaseURL)
            let imgMaus = try makeSyntheticTextImage(text: "MausBot Local Agent Terminal", backgroundWhite: true)
            let imgMemo = try makeSyntheticTextImage(text: "Memo Inbox Podcast Notes", backgroundWhite: false)
            let capturerA = MockScreenCapturer(image: imgMaus, isScreenCaptureTrusted: true)
            let recorderA = NativeScreenRecorder(
                database: dbA,
                snapshotsRootDir: storeA.snapshotsDirectory,
                capturer: capturerA,
                clock: clock
            )

            let capturedOCRFlagsA = LockedBox<[Bool]>([])
            let mockTransportA = MockJevTransport { request in
                let obj = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                let state = obj?["state"] as? [String: Any]
                let current = state?["current"] as? [String: Any]
                let hasOCR = (current?["ocr_snippet"] as? String)?.isEmpty == false
                capturedOCRFlagsA.modify { $0.append(hasOCR) }

                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "activity_mode": { "type": "choice", "choice": "build", "confidence": 0.94, "probabilities": { "build": 0.94 } },
                    "same_task": { "type": "noul", "noul": 0.15 }
                  },
                  "usage": { "input_tokens": 550, "output_tokens": 25 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engineA = DayHelmEngine(budgets: [], clock: clock)
            let mausSample0 = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "MausBot - Google Chrome",
                url: "https://maus-bot.lban2049.xyz/",
                idleSeconds: 0
            )
            let inspectorA = MockInspector(currentSample: mausSample0)
            let coordA = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engineA,
                    store: storeA,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspectorA,
                    clock: clock,
                    database: dbA,
                    screenRecorder: recorderA,
                    jevClient: JevActivityClient(transport: mockTransportA),
                    jevAPIKeyStore: keyStoreA
                )
            }

            await MainActor.run {
                var s = coordA.recorderSettings
                s.jevAutoTrackingEnabled = true
                s.jevSendOCRSnippet = true
                s.activityRecorderEnabled = true
                s.deepRecordingEnabled = true
                s.visionOCREnabled = true
                coordA.updateRecorderSettings(s)
                coordA.handleWindowContextChangedForTesting()
            }

            // Past 0.65s minDwellBeforeClassifySeconds, still inside ~1.4s on-demand OCR wait window -> 0 Jev calls
            clock.advance(by: 0.70)
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(
                    timestamp: clock.now(),
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "MausBot - Google Chrome",
                    url: "https://maus-bot.lban2049.xyz/",
                    idleSeconds: 0
                )
                coordA.pollOnce()
            }
            try checkEqual(capturedOCRFlagsA.get().count, 0, "Inside on-demand OCR wait window (0.70s < 1.4s), must defer noOCR call")

            // Past 1.4s timeout without OCR landing -> degrades to noOCR once
            clock.advance(by: 0.75)
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(
                    timestamp: clock.now(),
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "MausBot - Google Chrome",
                    url: "https://maus-bot.lban2049.xyz/",
                    idleSeconds: 0
                )
                coordA.pollOnce()
            }
            try await waitUntil("On-demand OCR timeout degrades to noOCR Jev call") {
                capturedOCRFlagsA.get().count == 1
            }
            try checkEqual(capturedOCRFlagsA.get(), [false], "Timeout fallback must send exactly 1 noOCR request")

            // Switch to Memo Inbox: defer at 0.70s, then OCR lands at 0.85s -> single OCR request only
            clock.advance(by: 5.0)
            let memoStart = clock.now()
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(
                    timestamp: memoStart,
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "Memo Inbox - Google Chrome",
                    url: "https://memo.lban2049.xyz/",
                    idleSeconds: 0
                )
                coordA.handleWindowContextChangedForTesting()
            }
            clock.advance(by: 0.70)
            await MainActor.run {
                inspectorA.currentSample = ActivitySample(
                    timestamp: clock.now(),
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "Memo Inbox - Google Chrome",
                    url: "https://memo.lban2049.xyz/",
                    idleSeconds: 0
                )
                coordA.pollOnce()
            }
            try checkEqual(capturedOCRFlagsA.get().count, 1, "Memo Inbox at 0.70s must still wait for OCR without sending noOCR")

            clock.advance(by: 0.15) // 0.85s total dwell
            let memoOCRSample = ActivitySample(
                timestamp: clock.now(),
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Memo Inbox - Google Chrome",
                url: "https://memo.lban2049.xyz/",
                idleSeconds: 0
            )
            let savedMemoOCR = try await recorderA.processCapturedImage(
                imgMemo,
                sample: memoOCRSample,
                trigger: "window_change",
                declaredTaskId: nil,
                runOCR: true
            )
            try checkEqual(savedMemoOCR, true, "Synthetic Memo Inbox image should save & OCR")
            await MainActor.run {
                inspectorA.currentSample = memoOCRSample
                coordA.pollOnce()
            }
            try await waitUntil("Memo Inbox classifies once with landed OCR") {
                capturedOCRFlagsA.get().count == 2
            }
            try checkEqual(capturedOCRFlagsA.get(), [false, true], "Memo Inbox must send exactly 1 OCR-enriched request and skip noOCR")

            // 4b. Live timer E2E (no pollOnce!): on-demand 0.35s OCR trigger completes inside wait window -> 1 single OCR request
            let tmpDirB = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-70b-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDirB, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDirB) }

            let storeB = DayHelmStore(directory: tmpDirB)
            let keyStoreB = JevAPIKeyStore(directory: tmpDirB, environment: [:], dotEnvSearchPaths: [])
            try keyStoreB.saveKey("synthetic_live_ocr_wait_key")

            let sysClock = SystemClock()
            let dbB = try ActivityDatabase(databaseURL: storeB.databaseURL)
            let capturerB = MockScreenCapturer(image: imgMaus, isScreenCaptureTrusted: true)
            let recorderB = NativeScreenRecorder(
                database: dbB,
                snapshotsRootDir: storeB.snapshotsDirectory,
                capturer: capturerB,
                clock: sysClock
            )
            let capturedOCRFlagsB = LockedBox<[Bool]>([])
            let mockTransportB = MockJevTransport { request in
                let obj = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                let state = obj?["state"] as? [String: Any]
                let current = state?["current"] as? [String: Any]
                let hasOCR = (current?["ocr_snippet"] as? String)?.isEmpty == false
                capturedOCRFlagsB.modify { $0.append(hasOCR) }

                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "activity_mode": { "type": "choice", "choice": "build", "confidence": 0.95, "probabilities": { "build": 0.95 } },
                    "same_task": { "type": "noul", "noul": 0.12 }
                  },
                  "usage": { "input_tokens": 580, "output_tokens": 25 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engineB = DayHelmEngine(budgets: [], clock: sysClock)
            let inspectorB = MockInspector(currentSample: ActivitySample(
                timestamp: sysClock.now(),
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "MausBot - Google Chrome",
                url: "https://maus-bot.lban2049.xyz/",
                idleSeconds: 0
            ))
            let coordB = await MainActor.run {
                let c = HybridActivityCoordinator(
                    engine: engineB,
                    store: storeB,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspectorB,
                    clock: sysClock,
                    database: dbB,
                    screenRecorder: recorderB,
                    jevClient: JevActivityClient(transport: mockTransportB),
                    jevAPIKeyStore: keyStoreB
                )
                c.enableLiveTimersForTesting = true
                var s = c.recorderSettings
                s.jevAutoTrackingEnabled = true
                s.jevSendOCRSnippet = true
                s.activityRecorderEnabled = true
                s.deepRecordingEnabled = true
                s.visionOCREnabled = true
                c.updateRecorderSettings(s)
                return c
            }
            defer {
                Task { @MainActor in coordB.stop() }
            }

            await MainActor.run {
                inspectorB.currentSample = ActivitySample(
                    timestamp: sysClock.now(),
                    appName: "Google Chrome",
                    bundleId: "com.google.Chrome",
                    windowTitle: "MausBot - Google Chrome",
                    url: "https://maus-bot.lban2049.xyz/",
                    idleSeconds: 0
                )
                coordB.handleWindowContextChangedForTesting()
            }
            try await waitUntil("Live timer on-demand OCR completes and sends single OCR-enriched Jev request", timeoutSeconds: 4.0) {
                capturedOCRFlagsB.get().count >= 1
            }
            // Wait past the fallback deadline (1.5s) to ensure no duplicate second Jev request fires
            try await Task.sleep(nanoseconds: 1_500_000_000)
            try checkEqual(capturedOCRFlagsB.get(), [true], "Live timer on-demand OCR must emit exactly 1 OCR request and 0 noOCR double-fires")
        }

        try await runCheck("71. OCR top menu bar cropping, fuzzy chrome denoising & Chrome title suffix/memory normalization") {
            // 1. Full-screen synthetic image: top 4% menu bar text must be excluded by VisionOCRService while body text is preserved
            let fullScreenImg = try makeSyntheticMenuBarAndBodyImage(
                menuBarText: "Chrome File Edit 开发构建 32m 11:24",
                bodyText: "Synthetic Body Dashboard 2026",
                width: 1280,
                height: 800
            )
            let fullOCR = try await VisionOCRService.recognizeText(from: fullScreenImg)
            try check(!fullOCR.text.contains("开发构建"), "Top menu bar DayHelm pill must be excluded from OCR (got: '\(fullOCR.text)')")
            try check(!fullOCR.text.contains("32m"), "Top menu bar duration must be excluded from OCR (got: '\(fullOCR.text)')")
            try check(!fullOCR.text.contains("File"), "Top menu bar File/Edit must be excluded from OCR (got: '\(fullOCR.text)')")
            try check(fullOCR.text.contains("Dashboard") || fullOCR.text.contains("2026"), "Body text must remain intact in OCR (got: '\(fullOCR.text)')")

            // Small synthetic banner (< 480px height) with text near top must NOT be mis-cropped
            let smallBanner = try makeSyntheticTopTextBanner(text: "SMALL_BANNER_KEEP_2026", width: 960, height: 240)
            let smallOCR = try await VisionOCRService.recognizeText(from: smallBanner)
            try check(smallOCR.text.contains("SMALL") || smallOCR.text.contains("2026"), "Small synthetic banner must not be cropped by top menu bar filter (got: '\(smallOCR.text)')")

            // 2. Chrome title suffix + Profile name normalization (buildInput + semanticContextKey)
            let t0 = baseDate()
            let budgets = sampleBudgets()
            let composioShopProfile = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Composio - Google Chrome - カネタ (抖音个人店铺)",
                url: "https://app.composio.dev/apps",
                idleSeconds: 0
            )
            let composioWorkProfile = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Composio - Google Chrome - 晓亮",
                url: "https://app.composio.dev/apps",
                idleSeconds: 0
            )
            let composioNoURL1 = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Composio - Google Chrome - カネタ (抖音个人店铺)",
                url: nil,
                idleSeconds: 0
            )
            let composioNoURL2 = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "Composio - Google Chrome - 晓亮",
                url: nil,
                idleSeconds: 0
            )

            let inputShop = SemanticPayloadSanitizer.buildInput(
                sample: composioShopProfile,
                ocrText: nil,
                recentSpans: [],
                budgets: budgets,
                sendOCRSnippet: true,
                privacyConfig: .default
            )
            let inputWork = SemanticPayloadSanitizer.buildInput(
                sample: composioWorkProfile,
                ocrText: nil,
                recentSpans: [],
                budgets: budgets,
                sendOCRSnippet: true,
                privacyConfig: .default
            )
            try checkEqual(inputShop?.windowTitle, "Composio", "buildInput must strip Chrome and Profile suffix")
            try checkEqual(inputWork?.windowTitle, "Composio", "buildInput must normalize different Chrome profiles to identical title")
            try checkEqual(
                SemanticPayloadSanitizer.semanticContextKey(for: composioShopProfile),
                SemanticPayloadSanitizer.semanticContextKey(for: composioWorkProfile),
                "Different Chrome profiles on same page must share the same semanticContextKey"
            )
            try checkEqual(
                SemanticPayloadSanitizer.semanticContextKey(for: composioNoURL1),
                SemanticPayloadSanitizer.semanticContextKey(for: composioNoURL2),
                "Different Chrome profiles without URL must also share the same semanticContextKey"
            )

            // 3. Dynamic memory usage suffix normalization
            let xHighMem = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "主页 / X - 内存用量高 - 883 MB - Google Chrome - 晓亮",
                url: "https://x.com/home",
                idleSeconds: 0
            )
            let xNormal = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "主页 / X - Google Chrome - 晓亮",
                url: "https://x.com/home",
                idleSeconds: 0
            )
            let xEnglishMem = ActivitySample(
                timestamp: t0,
                appName: "Google Chrome",
                bundleId: "com.google.Chrome",
                windowTitle: "主页 / X - High memory usage - 1.2 GB - Google Chrome - Work",
                url: "https://x.com/home",
                idleSeconds: 0
            )
            let inputXMem = SemanticPayloadSanitizer.buildInput(
                sample: xHighMem,
                ocrText: nil,
                recentSpans: [],
                budgets: budgets,
                sendOCRSnippet: true,
                privacyConfig: .default
            )
            try checkEqual(inputXMem?.windowTitle, "主页 / X", "buildInput must strip Chrome memory usage, browser, and profile suffixes")
            try checkEqual(
                SemanticPayloadSanitizer.semanticContextKey(for: xHighMem),
                SemanticPayloadSanitizer.semanticContextKey(for: xNormal),
                "High memory usage suffix must not fragment semanticContextKey"
            )
            try checkEqual(
                SemanticPayloadSanitizer.semanticContextKey(for: xEnglishMem),
                SemanticPayloadSanitizer.semanticContextKey(for: xNormal),
                "English high memory usage and profile difference must share semanticContextKey"
            )

            // 4. Fuzzy stripTopChromeNoise: OCR-typo menu bars, DayHelm pills, tab strips & www-stripped omnibox
            let typoChromeOCR = [
                "Chrome 文件 燴辑 显示 历史记承 书签 窗口 帮助",
                "FeEdit ViewWindow History Bookmarks",
                "开发构建 32m  11:24",
                "沟通杂务 18m",
                "GitHub × Composio × 新标签页 +",
                "正文第一行 电商选品与研发需求"
            ].joined(separator: "\n")
            let denoisedTypo = SemanticPayloadSanitizer.stripTopChromeNoise(from: typoChromeOCR)
            try check(!denoisedTypo.contains("燴辑"), "stripTopChromeNoise must remove OCR-typo Chinese menu bar line")
            try check(!denoisedTypo.contains("FeEdit"), "stripTopChromeNoise must remove glued English menu bar line")
            try check(!denoisedTypo.contains("开发构建"), "stripTopChromeNoise must remove DayHelm mode pill line")
            try check(!denoisedTypo.contains("沟通杂务"), "stripTopChromeNoise must remove DayHelm comms_admin pill line")
            try check(!denoisedTypo.contains("新标签页"), "stripTopChromeNoise must remove Chrome tab strip noise")
            try check(denoisedTypo.contains("电商选品与研发需求"), "stripTopChromeNoise must preserve body text")

            // www.-omitted Chrome address bar anchoring
            let wwwOmniboxOCR = [
                "Tab A × Tab B",
                "example.com/dashboard",
                "真实页面正文内容"
            ].joined(separator: "\n")
            let denoisedOmnibox = SemanticPayloadSanitizer.stripTopChromeNoise(from: wwwOmniboxOCR, url: "https://www.example.com/dashboard")
            try check(!denoisedOmnibox.contains("Tab A"), "www-stripped omnibox anchor must strip background tabs")
            try check(denoisedOmnibox.contains("真实页面正文内容"), "www-stripped omnibox anchor must keep body text")

            // Do not false-positive on normal prose containing menu words
            let normalProse = "历史记录显示昨天成交 12 笔\n第二行详细数据"
            try checkEqual(SemanticPayloadSanitizer.stripTopChromeNoise(from: normalProse), normalProse, "Normal prose must not be stripped by menu bar heuristic")
        }

        try await runCheck("72. Jev semantic write-back gating, late-response isolation & subdomain contextKey isolation") {
            let t0 = baseDate()

            // 1. Subdomain & channel isolation in semanticContextKey (even when titles are nil or identical)
            let taskEmptyTitle = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: nil, url: "https://task.lban2049.xyz", idleSeconds: 0)
            let mausEmptyTitle = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: nil, url: "https://maus-bot.lban2049.xyz", idleSeconds: 0)
            try check(
                SemanticPayloadSanitizer.semanticContextKey(for: taskEmptyTitle) != SemanticPayloadSanitizer.semanticContextKey(for: mausEmptyTitle),
                "Different subdomains with nil title must produce distinct semanticContextKeys"
            )

            let taskDashTitle = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Dashboard - Google Chrome - Work", url: "https://task.lban2049.xyz/", idleSeconds: 0)
            let mausDashTitle = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Dashboard - Google Chrome - Work", url: "https://maus-bot.lban2049.xyz/", idleSeconds: 0)
            try check(
                SemanticPayloadSanitizer.semanticContextKey(for: taskDashTitle) != SemanticPayloadSanitizer.semanticContextKey(for: mausDashTitle),
                "Different subdomains with identical title must produce distinct semanticContextKeys"
            )

            let wwwSame = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Example - Google Chrome", url: "https://www.example.com/a", idleSeconds: 0)
            let bareSame = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Example - Google Chrome", url: "https://example.com/a", idleSeconds: 0)
            try checkEqual(
                SemanticPayloadSanitizer.semanticContextKey(for: wwwSame),
                SemanticPayloadSanitizer.semanticContextKey(for: bareSame),
                "www. prefix stripping must remain consistent in semanticContextKey"
            )

            // 2. DayHelmEngine.stampSemanticGroup must not back-contaminate different subdomains or Discord channels within 60s
            let isoClock = ManualClock(now: t0)
            let isoEngine = DayHelmEngine(budgets: sampleBudgets(), clock: isoClock)
            isoEngine.setAutoTrackingActive(true)
            let vikunjaSample = ActivitySample(timestamp: t0, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Vikunja - Google Chrome", url: "https://task.lban2049.xyz/projects/1", idleSeconds: 0)
            isoEngine.applyAutoCategory(AutoActivityIds.modeCategoryId(for: .research), activityMode: .research, at: t0)
            isoEngine.ingest(vikunjaSample)
            isoEngine.stampSemanticGroup("mode:research", forContextKey: SemanticPayloadSanitizer.semanticContextKey(for: vikunjaSample), at: t0)

            let tMaus = t0.addingTimeInterval(15)
            isoClock.advance(by: 15)
            let mausSample = ActivitySample(timestamp: tMaus, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "MausBot - Google Chrome", url: "https://maus-bot.lban2049.xyz/", idleSeconds: 0)
            isoEngine.ingest(mausSample)
            isoEngine.applyAutoCategory(AutoActivityIds.modeCategoryId(for: .build), activityMode: .build, at: tMaus)
            isoEngine.stampSemanticGroup("mode:build", forContextKey: SemanticPayloadSanitizer.semanticContextKey(for: mausSample), at: tMaus)

            try checkEqual(isoEngine.enrichedSpans.count, 2, "Expected 2 distinct spans for Vikunja and MausBot")
            try checkEqual(isoEngine.enrichedSpans[0].semanticGroup, "mode:research", "MausBot stampSemanticGroup must NOT overwrite earlier Vikunja span on same parent domain")
            try checkEqual(isoEngine.enrichedSpans[1].semanticGroup, "mode:build", "MausBot span must be stamped mode:build")

            let tDiscordA = t0.addingTimeInterval(25)
            isoClock.advance(by: 10)
            let discordEcom = ActivitySample(timestamp: tDiscordA, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Discord | 电商计划 - Google Chrome", url: "https://discord.com/channels/1/2", idleSeconds: 0)
            isoEngine.ingest(discordEcom)
            isoEngine.applyAutoCategory("ecommerce", activityMode: .operate, at: tDiscordA)
            isoEngine.stampSemanticGroup("proj:ecommerce", forContextKey: SemanticPayloadSanitizer.semanticContextKey(for: discordEcom), at: tDiscordA)

            let tDiscordB = t0.addingTimeInterval(35)
            isoClock.advance(by: 10)
            let discordCreate = ActivitySample(timestamp: tDiscordB, appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Discord | 内容创作 - Google Chrome", url: "https://discord.com/channels/1/3", idleSeconds: 0)
            isoEngine.ingest(discordCreate)
            isoEngine.applyAutoCategory(AutoActivityIds.modeCategoryId(for: .create), activityMode: .create, at: tDiscordB)
            isoEngine.stampSemanticGroup("mode:create", forContextKey: SemanticPayloadSanitizer.semanticContextKey(for: discordCreate), at: tDiscordB)

            try checkEqual(isoEngine.enrichedSpans.count, 4, "Expected 4 spans including two Discord channels")
            try checkEqual(isoEngine.enrichedSpans[2].semanticGroup, "proj:ecommerce", "Discord create channel must NOT overwrite earlier Discord ecommerce channel span")
            try checkEqual(isoEngine.enrichedSpans[3].semanticGroup, "mode:create", "Discord create channel span must be stamped mode:create")

            // 3. Coordinator E2E: ignored_low_confidence, pending_confirmation, dwell commit, late response, cache hit & manualPin
            let clock = ManualClock(now: t0)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("dayhelm-check-72-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: tmpDir) }

            let store = DayHelmStore(directory: tmpDir)
            let keyStore = JevAPIKeyStore(directory: tmpDir, environment: [:], dotEnvSearchPaths: [])
            try keyStore.saveKey("synthetic_gate_key")

            struct MockReply {
                let mode: String
                let project: String
                let confidence: Double
                let sameTask: Double
                let delayGate: AsyncStream<Void>?
            }
            let replyBox = LockedBox<MockReply>(MockReply(mode: "build", project: "none", confidence: 0.96, sameTask: 0.10, delayGate: nil))
            let jevCalls = LockedBox<Int>(0)

            let mockTransport = MockJevTransport { request in
                jevCalls.modify { $0 += 1 }
                let spec = replyBox.get()
                if let gate = spec.delayGate {
                    for await _ in gate { break }
                }
                let json = """
                {
                  "model": "jev-1.14.0",
                  "answers": {
                    "activity_mode": { "type": "choice", "choice": "\(spec.mode)", "confidence": \(spec.confidence), "probabilities": { "\(spec.mode)": \(spec.confidence) } },
                    "focus_project": { "type": "choice", "choice": "\(spec.project)", "confidence": \(spec.confidence), "probabilities": { "\(spec.project)": \(spec.confidence) } },
                    "same_task": { "type": "noul", "noul": \(spec.sameTask) }
                  },
                  "usage": { "input_tokens": 400, "output_tokens": 25 }
                }
                """
                let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (Data(json.utf8), resp)
            }

            let engine = DayHelmEngine(budgets: sampleBudgets(), clock: clock)
            let zedSample0 = ActivitySample(timestamp: t0, appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
            let inspector = MockInspector(currentSample: zedSample0)
            let coordinator = await MainActor.run {
                HybridActivityCoordinator(
                    engine: engine,
                    store: store,
                    almaClient: AlmaActivityClient(baseURL: URL(string: "http://127.0.0.1:1")!, transport: MockAlmaTransport { _ in throw URLError(.cannotConnectToHost) }),
                    inspector: inspector,
                    clock: clock,
                    jevClient: JevActivityClient(transport: mockTransport),
                    jevAPIKeyStore: keyStore
                )
            }

            await MainActor.run {
                var s = coordinator.recorderSettings
                s.jevAutoTrackingEnabled = true
                coordinator.updateRecorderSettings(s)
                coordinator.pollOnce()
            }
            clock.advance(by: 1.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Initial Zed classifies as build") {
                await MainActor.run { coordinator.activeActivityMode == .build }
            }
            try checkEqual(engine.enrichedSpans.last?.semanticGroup, "mode:build", "Committed Zed span must be stamped mode:build")

            // 3a. Low-confidence prediction (ignored_low_confidence: conf 0.60 < 0.70) must NOT stamp span or mutate _currentSemanticGroup
            replyBox.set(MockReply(mode: "break", project: "none", confidence: 0.60, sameTask: 0.20, delayGate: nil))
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "News Portal - Google Chrome", url: "https://news.example.com/feed", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 1.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "News Portal - Google Chrome", url: "https://news.example.com/feed", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Low-confidence Jev decision logged") {
                await MainActor.run { coordinator.jevDecisionLogs.first?.outcome == .ignoredLowConfidence }
            }
            try await MainActor.run {
                try checkEqual(coordinator.activeActivityMode, .build, "Low-confidence prediction must keep activeActivityMode as .build")
                try checkEqual(engine.currentSemanticGroup, "mode:build", "Low-confidence prediction must keep currentSemanticGroup as mode:build")
                try checkEqual(engine.enrichedSpans.last?.semanticGroup, "mode:build", "Low-confidence prediction must NOT stamp span with 'break'")
            }

            // 3b. Pending confirmation (conf 0.76, same_task 0.40) must NOT stamp before 1.2s dwell completes
            replyBox.set(MockReply(mode: "research", project: "none", confidence: 0.76, sameTask: 0.40, delayGate: nil))
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Vikunja Tasks - Google Chrome", url: "https://task.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 1.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Vikunja Tasks - Google Chrome", url: "https://task.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Pending-confirmation Jev decision logged") {
                await MainActor.run { coordinator.jevDecisionLogs.first?.outcome == .pendingConfirmation }
            }
            let vikunjaPendingIdx = engine.enrichedSpans.count - 1
            try await MainActor.run {
                try checkEqual(coordinator.activeActivityMode, .build, "Pending confirmation must keep activeActivityMode as .build")
                try checkEqual(engine.currentSemanticGroup, "mode:build", "Pending confirmation must keep currentSemanticGroup as mode:build")
                try checkEqual(engine.enrichedSpans[vikunjaPendingIdx].semanticGroup, "mode:build", "Pending confirmation must NOT stamp span with 'mode:research' prematurely")
            }

            // Advance >= 1.2s -> dwell confirm commits research and stamps ONLY Vikunja span
            clock.advance(by: 1.3)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Vikunja Tasks - Google Chrome", url: "https://task.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await MainActor.run {
                try checkEqual(coordinator.activeActivityMode, .research, "Pending dwell >= 1.2s must commit research")
                try checkEqual(engine.currentSemanticGroup, "mode:research", "Committed dwell confirmation must update currentSemanticGroup to mode:research")
                try checkEqual(engine.enrichedSpans[vikunjaPendingIdx].semanticGroup, "mode:research", "Committed dwell confirmation must stamp current Vikunja span as mode:research")
                try checkEqual(engine.enrichedSpans[0].semanticGroup, "mode:build", "Previous Zed span must remain mode:build")
            }

            // 3c. Late Jev response arriving after user switched context must ONLY cache and NEVER mutate currentSemanticGroup or spans
            var slowGateContinuation: AsyncStream<Void>.Continuation?
            let slowGate = AsyncStream<Void> { cont in
                slowGateContinuation = cont
            }
            let callsBeforeSlow = jevCalls.get()
            replyBox.set(MockReply(mode: "break", project: "none", confidence: 0.99, sameTask: 0.05, delayGate: slowGate))
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Slow Tab - Google Chrome", url: "https://slow.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 1.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Slow Tab - Google Chrome", url: "https://slow.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Slow Jev request entered transport") {
                jevCalls.get() == callsBeforeSlow + 1
            }

            // User switches back to cached Zed (>= 0.45s) while slow request is still in flight
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 0.6)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.activeActivityMode, .build, "Cached switch back to Zed should restore .build")
            }

            // Now release the late response from Slow Tab (which returns break!)
            slowGateContinuation?.yield()
            slowGateContinuation?.finish()
            // Give MainActor task a brief moment to settle
            try await Task.sleep(nanoseconds: 80_000_000)

            // Verify Zed span & _currentSemanticGroup were NOT polluted by the late 'break' response
            clock.advance(by: 2.0)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "helper.swift", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.activeActivityMode, .build, "Late Jev response must NOT flip activeActivityMode to breakTime")
                try checkEqual(engine.currentSemanticGroup, "mode:build", "Late Jev response must keep currentSemanticGroup as mode:build")
                try checkEqual(engine.enrichedSpans.last?.semanticGroup, "mode:build", "Late Jev response must NOT pollute _currentSemanticGroup on subsequent spans")
                let slowSpans = engine.enrichedSpans.filter { $0.url == "https://slow.lban2049.xyz/" }
                try check(!slowSpans.contains(where: { $0.semanticGroup == "break" }), "Late Jev response must NOT stamp slow tab span when user already left")
            }

            // Cache WAS stored for slow.lban2049.xyz: switching back and settling >= 0.45s switches via cache with 0 extra API calls
            let callsAfterLate = jevCalls.get()
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Slow Tab - Google Chrome", url: "https://slow.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 0.6)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Slow Tab - Google Chrome", url: "https://slow.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.activeActivityMode, .breakTime, "Cached late response should activate when user returns for >= 0.45s")
                try checkEqual(jevCalls.get(), callsAfterLate, "Cache hit on slow tab must make 0 additional Jev calls")
                try checkEqual(engine.enrichedSpans.last?.semanticGroup, "break", "Cache hit after genuine adoption must stamp slow tab span")
                let vikunjaStillResearch = engine.enrichedSpans.filter { $0.url == "https://task.lban2049.xyz/" }
                try check(vikunjaStillResearch.allSatisfy { $0.semanticGroup == "mode:research" }, "Cache hit stamp on slow.lban2049.xyz must NOT overwrite task.lban2049.xyz")
            }

            // 3d. manualPin interception: an in-flight Jev response returning 'break' after user manually selected 'ecommerce' must NOT overwrite span or currentSemanticGroup
            var pinGateContinuation: AsyncStream<Void>.Continuation?
            let pinGate = AsyncStream<Void> { cont in
                pinGateContinuation = cont
            }
            let callsBeforePin = jevCalls.get()
            replyBox.set(MockReply(mode: "break", project: "none", confidence: 0.99, sameTask: 0.05, delayGate: pinGate))
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop Admin - Google Chrome", url: "https://shop.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 1.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop Admin - Google Chrome", url: "https://shop.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
            }
            try await waitUntil("Pin-test Jev request entered transport") {
                jevCalls.get() == callsBeforePin + 1
            }

            // User manually clicks ecommerce while Jev is in flight on the same window
            await MainActor.run {
                coordinator.selectTask("ecommerce")
            }
            pinGateContinuation?.yield()
            pinGateContinuation?.finish()
            try await waitUntil("ManualPin outcome logged") {
                await MainActor.run { coordinator.jevDecisionLogs.first?.outcome == .manualPinned }
            }
            try await MainActor.run {
                if case .focusing(let taskId, _) = coordinator.sessionState {
                    try checkEqual(taskId, "ecommerce", "manualPin must keep focusing on ecommerce")
                } else {
                    throw CheckFailure(description: "Expected focusing state on ecommerce while manualPin is active")
                }
                try checkEqual(engine.currentSemanticGroup, "proj:ecommerce", "manualPin must keep currentSemanticGroup as proj:ecommerce")
                try checkEqual(engine.enrichedSpans.last?.semanticGroup, "proj:ecommerce", "manualPin-intercepted Jev response must NOT overwrite span semanticGroup to 'break'")
            }

            // Switching to cached Zed (>= 0.45s) breaks context-scoped manualPin -> switches to build, then returning to shop.lban2049.xyz hits manualOverride -> restores proj:ecommerce & stamps span
            clock.advance(by: 2.0)
            await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
            }
            clock.advance(by: 0.6)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Zed", bundleId: "dev.zed.Zed", windowTitle: "main.swift", idleSeconds: 0)
                coordinator.pollOnce()
                try checkEqual(coordinator.activeActivityMode, .build, "Leaving pinned window to cached Zed should switch to .build")
                try checkEqual(engine.currentSemanticGroup, "mode:build", "Leaving pinned window should update currentSemanticGroup to mode:build")
            }

            clock.advance(by: 2.0)
            try await MainActor.run {
                inspector.currentSample = ActivitySample(timestamp: clock.now(), appName: "Google Chrome", bundleId: "com.google.Chrome", windowTitle: "Shop Admin - Google Chrome", url: "https://shop.lban2049.xyz/", idleSeconds: 0)
                coordinator.pollOnce()
                if case .focusing(let taskId, _) = coordinator.sessionState {
                    try checkEqual(taskId, "ecommerce", "Returning to manually overridden window must restore ecommerce")
                } else {
                    throw CheckFailure(description: "Expected focusing on ecommerce via manualOverride")
                }
                try checkEqual(engine.currentSemanticGroup, "proj:ecommerce", "manualOverride must update currentSemanticGroup to proj:ecommerce")
                try checkEqual(engine.enrichedSpans.last?.semanticGroup, "proj:ecommerce", "manualOverride must stamp current window span with proj:ecommerce")
            }
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

    private static func makeSyntheticMenuBarAndBodyImage(menuBarText: String, bodyText: String, width: Int = 1280, height: Int = 800) throws -> CGImage {
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
            throw CheckFailure(description: "Failed to create CGContext for menu-bar synthetic OCR image")
        }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let menuFont = CTFontCreateWithName("PingFangSC-Regular" as CFString, 18, nil)
        let bodyFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 42, nil)
        let fgColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

        let menuAttr = CFAttributedStringCreate(kCFAllocatorDefault, menuBarText as CFString, [
            kCTFontAttributeName: menuFont,
            kCTForegroundColorAttributeName: fgColor
        ] as CFDictionary)!
        let menuLine = CTLineCreateWithAttributedString(menuAttr)
        // Top 3% in CG bottom-left coordinates (y = 0.972 * height)
        ctx.textPosition = CGPoint(x: 24, y: CGFloat(height) * 0.972)
        CTLineDraw(menuLine, ctx)

        let bodyAttr = CFAttributedStringCreate(kCFAllocatorDefault, bodyText as CFString, [
            kCTFontAttributeName: bodyFont,
            kCTForegroundColorAttributeName: fgColor
        ] as CFDictionary)!
        let bodyLine = CTLineCreateWithAttributedString(bodyAttr)
        ctx.textPosition = CGPoint(x: 40, y: CGFloat(height) * 0.48)
        CTLineDraw(bodyLine, ctx)

        guard let cgImage = ctx.makeImage() else {
            throw CheckFailure(description: "Failed to finalize menu-bar synthetic CGImage")
        }
        return cgImage
    }

    private static func makeSyntheticTopTextBanner(text: String, width: Int = 960, height: Int = 240) throws -> CGImage {
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
            throw CheckFailure(description: "Failed to create CGContext for top-text synthetic banner")
        }
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 28, nil)
        let fgColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        let attr = CFAttributedStringCreate(kCFAllocatorDefault, text as CFString, [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: fgColor
        ] as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attr)
        // Draw near top of small 240px banner (~90% height)
        ctx.textPosition = CGPoint(x: 32, y: CGFloat(height) * 0.85)
        CTLineDraw(line, ctx)

        guard let cgImage = ctx.makeImage() else {
            throw CheckFailure(description: "Failed to finalize top-text synthetic banner")
        }
        return cgImage
    }
}
