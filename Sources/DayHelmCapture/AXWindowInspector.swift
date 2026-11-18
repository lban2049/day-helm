import AppKit
import ApplicationServices
import CoreGraphics
import DayHelmCore
import Foundation
import IOKit

public protocol ActivityInspecting: AnyObject, Sendable {
    var isAccessibilityTrusted: Bool { get }
    func requestAccessibilityPrompt() -> Bool
    func updatePrivacyConfig(_ config: PrivacyRedactorConfig)
    func inspectCurrent() -> ActivitySample
}

public extension ActivityInspecting {
    func requestAccessibilityPrompt() -> Bool {
        isAccessibilityTrusted
    }

    func updatePrivacyConfig(_ config: PrivacyRedactorConfig) {}
}

public enum BrowserTabScriptRouter {
    private static let safariBundlePrefixes: [String] = [
        "com.apple.safari",
        "com.apple.safaritechnologypreview"
    ]

    private static let chromiumAppleScriptBundlePrefixes: [String] = [
        "com.google.chrome",
        "com.microsoft.edgemac",
        "com.brave.browser",
        "company.thebrowser.browser", // Arc
        "company.thebrowser.dia",     // Dia
        "com.thebrowser.dia",         // Dia
        "com.operasoftware.opera",
        "com.vivaldi.vivaldi",
        "ai.perplexity.comet",
        "com.kagi.kagi"               // Orion
    ]

    public static func appleScriptSource(appName: String, bundleId: String?) -> String? {
        guard ActivityClassifier.isBrowser(appName: appName, bundleId: bundleId) else {
            return nil
        }

        let trimmedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetName = trimmedApp.isEmpty ? "Safari" : trimmedApp
        let escapedTarget = targetName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let lowerBundle = bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let lowerApp = targetName.lowercased()

        let isSafari = safariBundlePrefixes.contains { lowerBundle == $0 || lowerBundle.hasPrefix($0 + ".") }
            || lowerApp.contains("safari")
        if isSafari {
            return """
            with timeout of 1 seconds
                tell application "\(escapedTarget)"
                    if (count of documents) = 0 then return ""
                    set docURL to URL of front document
                    set docTitle to name of front document
                    return (docURL as text) & "\\n" & (docTitle as text)
                end tell
            end timeout
            """
        }

        let isChromium = chromiumAppleScriptBundlePrefixes.contains { lowerBundle == $0 || lowerBundle.hasPrefix($0 + ".") }
            || ["chrome", "edge", "brave", "arc", "opera", "vivaldi", "comet", "orion"].contains { lowerApp.contains($0) }
            || lowerApp == "dia" || lowerApp == "dia browser"

        if isChromium {
            return """
            with timeout of 1 seconds
                tell application "\(escapedTarget)"
                    if (count of windows) = 0 then return ""
                    set tabURL to URL of active tab of front window
                    set tabTitle to title of active tab of front window
                    return (tabURL as text) & "\\n" & (tabTitle as text)
                end tell
            end timeout
            """
        }

        return nil
    }

    public static func parseScriptOutput(_ raw: String?) -> (url: String?, title: String?)? {
        guard let raw else { return nil }
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = (firstLine?.isEmpty == false) ? firstLine : nil
        let remainder = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = remainder.isEmpty ? nil : remainder
        if url == nil && title == nil {
            return nil
        }
        return (url, title)
    }
}

public final class BrowserAppleScriptCircuitBreaker: @unchecked Sendable {
    private struct Entry {
        var consecutiveFailures: Int = 0
        var openUntil: Date?
    }

    private let clock: any DayHelmClock
    private let cooldownSeconds: TimeInterval
    private let maxConsecutiveFailures: Int
    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    public init(
        clock: any DayHelmClock = SystemClock(),
        cooldownSeconds: TimeInterval = 300,
        maxConsecutiveFailures: Int = 3
    ) {
        self.clock = clock
        self.cooldownSeconds = max(1, cooldownSeconds)
        self.maxConsecutiveFailures = max(1, maxConsecutiveFailures)
    }

    public func shouldAllow(key: String) -> Bool {
        let now = clock.now()
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return true }
        if let openUntil = entry.openUntil {
            if now < openUntil {
                return false
            }
            entry.openUntil = nil
            entry.consecutiveFailures = 0
            entries[key] = entry
        }
        return true
    }

    public func recordFailure(key: String, errorCode: Int) {
        let now = clock.now()
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[key] ?? Entry()
        if errorCode == -1743 {
            entry.consecutiveFailures = maxConsecutiveFailures
            entry.openUntil = now.addingTimeInterval(cooldownSeconds)
        } else {
            entry.consecutiveFailures += 1
            if entry.consecutiveFailures >= maxConsecutiveFailures {
                entry.openUntil = now.addingTimeInterval(cooldownSeconds)
            }
        }
        entries[key] = entry
    }

    public func recordSuccess(key: String) {
        lock.lock()
        entries.removeValue(forKey: key)
        lock.unlock()
    }
}

public final class AXWindowInspector: ActivityInspecting, @unchecked Sendable {
    public typealias BrowserTabProvider = @Sendable (_ appName: String, _ bundleId: String?) -> (url: String?, title: String?)?

    private struct BrowserCacheEntry {
        let appKey: String
        let titleKey: String
        let result: (title: String?, url: String?)
        let timestamp: Date
    }

    private let clock: any DayHelmClock
    private var _privacyConfig: PrivacyRedactorConfig
    private let browserTabProvider: BrowserTabProvider
    private let browserCacheTTLSeconds: TimeInterval
    private let lock = NSLock()
    private var _screenLocked: Bool = false
    private var _browserCache: BrowserCacheEntry?
    private var observers: [NSObjectProtocol] = []

    private static let appleScriptLock = NSLock()
    private static var compiledAppleScripts: [String: NSAppleScript] = [:]

    public init(
        clock: any DayHelmClock = SystemClock(),
        privacyConfig: PrivacyRedactorConfig = .default,
        observeScreenLock: Bool = true,
        browserCacheTTLSeconds: TimeInterval = 15.0,
        browserTabProvider: BrowserTabProvider? = nil
    ) {
        self.clock = clock
        self._privacyConfig = privacyConfig
        self.browserCacheTTLSeconds = max(0, browserCacheTTLSeconds)
        if let browserTabProvider {
            self.browserTabProvider = browserTabProvider
        } else {
            let circuitBreaker = BrowserAppleScriptCircuitBreaker(clock: clock)
            self.browserTabProvider = { appName, bundleId in
                Self.executeBrowserAppleScript(
                    appName: appName,
                    bundleId: bundleId,
                    circuitBreaker: circuitBreaker
                )
            }
        }
        if observeScreenLock {
            registerScreenLockObservers()
        }
    }

    deinit {
        let center = DistributedNotificationCenter.default()
        for observer in observers {
            center.removeObserver(observer)
        }
    }

    public var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public func requestAccessibilityPrompt() -> Bool {
        let promptKey = "AXTrustedCheckOptionPrompt" as CFString
        let options = [promptKey: kCFBooleanTrue as Any] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func updatePrivacyConfig(_ config: PrivacyRedactorConfig) {
        lock.lock()
        _privacyConfig = config
        lock.unlock()
    }

    public var currentPrivacyConfig: PrivacyRedactorConfig {
        lock.lock()
        defer { lock.unlock() }
        return _privacyConfig
    }

    public var isScreenLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _screenLocked
    }

    public func inspectCurrent() -> ActivitySample {
        let now = clock.now()
        let locked = isScreenLocked
        let activePrivacyConfig = currentPrivacyConfig
        let idleSeconds = Self.readSystemIdleSeconds()

        let frontApp = NSWorkspace.shared.frontmostApplication
        let appName = frontApp?.localizedName ?? frontApp?.bundleIdentifier ?? "Unknown"
        let bundleId = frontApp?.bundleIdentifier

        var windowTitle: String?
        var documentURL: String?

        if !locked, let pid = frontApp?.processIdentifier, isAccessibilityTrusted {
            let axInfo = Self.readFocusedWindowInfo(pid: pid)
            windowTitle = axInfo.windowTitle
            documentURL = axInfo.documentURL
        }

        let resolvedBrowser = resolveBrowserFallbackWithCache(
            appName: appName,
            bundleId: bundleId,
            existingTitle: windowTitle,
            existingURL: documentURL,
            screenLocked: locked
        )
        windowTitle = resolvedBrowser.title
        documentURL = resolvedBrowser.url

        let inputActive = !locked && idleSeconds < 2.0
        let raw = ActivitySample(
            timestamp: now,
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: documentURL,
            idleSeconds: idleSeconds,
            screenLocked: locked,
            inputActive: inputActive
        )
        return PrivacyRedactor.redact(raw, config: activePrivacyConfig)
    }

    public func resolveBrowserFallbackWithCache(
        appName: String,
        bundleId: String?,
        existingTitle: String?,
        existingURL: String?,
        screenLocked: Bool
    ) -> (title: String?, url: String?) {
        let trimmedTitle = existingTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        let trimmedURL = existingURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = (trimmedURL?.isEmpty == false) ? trimmedURL : nil

        let activePrivacyConfig = currentPrivacyConfig
        guard !screenLocked, ActivityClassifier.isBrowser(appName: appName, bundleId: bundleId) else {
            return (cleanTitle, cleanURL)
        }

        let hasValidURL = ActivityClassifier.isWebURL(cleanURL)
        let hasValidTitle = (cleanTitle != nil)
        if hasValidURL && hasValidTitle {
            return (cleanTitle, cleanURL)
        }

        let appKey = (bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let titleKey = cleanTitle ?? ""
        let now = clock.now()

        if browserCacheTTLSeconds > 0 {
            lock.lock()
            let cached = _browserCache
            lock.unlock()
            if let cached,
               cached.appKey == appKey,
               cached.titleKey == titleKey,
               now.timeIntervalSince(cached.timestamp) < browserCacheTTLSeconds {
                return cached.result
            }
        }

        let resolved = Self.resolveBrowserFallbackIfNeeded(
            appName: appName,
            bundleId: bundleId,
            existingTitle: cleanTitle,
            existingURL: cleanURL,
            screenLocked: screenLocked,
            privacyConfig: activePrivacyConfig,
            provider: browserTabProvider
        )

        if browserCacheTTLSeconds > 0 {
            lock.lock()
            _browserCache = BrowserCacheEntry(
                appKey: appKey,
                titleKey: titleKey,
                result: resolved,
                timestamp: now
            )
            lock.unlock()
        }
        return resolved
    }

    public static func resolveBrowserFallbackIfNeeded(
        appName: String,
        bundleId: String?,
        existingTitle: String?,
        existingURL: String?,
        screenLocked: Bool,
        privacyConfig: PrivacyRedactorConfig,
        provider: (_ appName: String, _ bundleId: String?) -> (url: String?, title: String?)?
    ) -> (title: String?, url: String?) {
        let trimmedTitle = existingTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTitle = (trimmedTitle?.isEmpty == false) ? trimmedTitle : nil
        let trimmedURL = existingURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanURL = (trimmedURL?.isEmpty == false) ? trimmedURL : nil

        guard !screenLocked, ActivityClassifier.isBrowser(appName: appName, bundleId: bundleId) else {
            return (cleanTitle, cleanURL)
        }

        // Skip AppleScript completely if initial metadata or app already triggers privacy redaction
        let preSample = ActivitySample(
            timestamp: Date(timeIntervalSince1970: 0),
            appName: appName,
            bundleId: bundleId,
            windowTitle: cleanTitle,
            url: cleanURL,
            idleSeconds: 0,
            screenLocked: screenLocked,
            inputActive: true
        )
        guard !PrivacyRedactor.shouldRedact(preSample, config: privacyConfig) else {
            return (cleanTitle, cleanURL)
        }

        let hasValidURL = ActivityClassifier.isWebURL(cleanURL)
        let hasValidTitle = (cleanTitle != nil)
        guard !(hasValidURL && hasValidTitle) else {
            return (cleanTitle, cleanURL)
        }

        guard let scriptResult = provider(appName, bundleId) else {
            return (cleanTitle, cleanURL)
        }

        let fallbackURL = cleanURL ?? scriptResult.url
        let fallbackTitle = cleanTitle ?? scriptResult.title
        return (fallbackTitle, fallbackURL)
    }

    private static func executeBrowserAppleScript(
        appName: String,
        bundleId: String?,
        circuitBreaker: BrowserAppleScriptCircuitBreaker
    ) -> (url: String?, title: String?)? {
        let key = (bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? appName.lowercased()
        guard circuitBreaker.shouldAllow(key: key),
              let source = BrowserTabScriptRouter.appleScriptSource(appName: appName, bundleId: bundleId) else {
            return nil
        }

        appleScriptLock.lock()
        defer { appleScriptLock.unlock() }

        let script: NSAppleScript
        if let existing = compiledAppleScripts[source] {
            script = existing
        } else {
            guard let compiled = NSAppleScript(source: source) else {
                return nil
            }
            if compiledAppleScripts.count >= 16 {
                compiledAppleScripts.removeAll(keepingCapacity: true)
            }
            compiledAppleScripts[source] = compiled
            script = compiled
        }

        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if let errorDict {
            let code = (errorDict[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -1
            circuitBreaker.recordFailure(key: key, errorCode: code)
            return nil
        }

        circuitBreaker.recordSuccess(key: key)
        return BrowserTabScriptRouter.parseScriptOutput(descriptor.stringValue)
    }

    // MARK: - Screen Lock Observers

    private func registerScreenLockObservers() {
        let center = DistributedNotificationCenter.default()
        let lockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.setScreenLocked(true)
        }
        let unlockObserver = center.addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.setScreenLocked(false)
        }
        observers = [lockObserver, unlockObserver]
    }

    private func setScreenLocked(_ locked: Bool) {
        lock.lock()
        _screenLocked = locked
        lock.unlock()
    }

    // MARK: - Accessibility Helpers (kAXTitleAttribute & AXDocument only, no subtree walk)

    private static func readFocusedWindowInfo(pid: pid_t) -> (windowTitle: String?, documentURL: String?) {
        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, 0.25)

        var windowElement: AXUIElement?
        if let focused = copyAXElementAttribute(appElement, attribute: kAXFocusedWindowAttribute) {
            windowElement = focused
        } else if let windows = copyAXElementArrayAttribute(appElement, attribute: kAXWindowsAttribute),
                  let first = windows.first {
            windowElement = first
        }

        guard let window = windowElement else {
            return (nil, nil)
        }

        let title = copyAXStringAttribute(window, attribute: kAXTitleAttribute)
        var docURL = copyAXStringAttribute(window, attribute: kAXDocumentAttribute)

        if docURL == nil, let focusedUI = copyAXElementAttribute(appElement, attribute: kAXFocusedUIElementAttribute) {
            docURL = copyAXStringAttribute(focusedUI, attribute: kAXDocumentAttribute)
        }

        return (title, docURL)
    }

    private static func copyAXElementAttribute(_ element: AXUIElement, attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let cfVal = value else { return nil }
        guard CFGetTypeID(cfVal) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(cfVal, to: AXUIElement.self)
    }

    private static func copyAXElementArrayAttribute(_ element: AXUIElement, attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success, let array = value as? [AXUIElement] else { return nil }
        return array
    }

    private static func copyAXStringAttribute(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard err == .success else { return nil }
        if let str = value as? String {
            let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let url = value as? URL {
            return url.absoluteString
        }
        return nil
    }

    // MARK: - System Idle Time (Combined HID + IOKit Fallback)

    public static func readSystemIdleSeconds() -> TimeInterval {
        if let anyInputType = CGEventType(rawValue: 0xFFFFFFFF) {
            let cgIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputType)
            if cgIdle.isFinite && cgIdle >= 0 && cgIdle < 86_400 * 30 {
                return cgIdle
            }
        }
        return readIOKitHIDIdleSeconds() ?? 0
    }

    private static func readIOKitHIDIdleSeconds() -> TimeInterval? {
        let matching = IOServiceMatching("IOHIDSystem")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return nil
        }

        if let num = prop as? NSNumber {
            let nanos = num.doubleValue
            if nanos.isFinite && nanos >= 0 {
                return nanos / 1_000_000_000.0
            }
        }
        return nil
    }
}
