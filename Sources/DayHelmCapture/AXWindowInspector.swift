import AppKit
import ApplicationServices
import CoreGraphics
import DayHelmCore
import Foundation
import IOKit

public protocol ActivityInspecting: AnyObject, Sendable {
    var isAccessibilityTrusted: Bool { get }
    func inspectCurrent() -> ActivitySample
}

public final class AXWindowInspector: ActivityInspecting, @unchecked Sendable {
    private let clock: any DayHelmClock
    private let privacyConfig: PrivacyRedactorConfig
    private let lock = NSLock()
    private var _screenLocked: Bool = false
    private var observers: [NSObjectProtocol] = []

    public init(
        clock: any DayHelmClock = SystemClock(),
        privacyConfig: PrivacyRedactorConfig = .default,
        observeScreenLock: Bool = true
    ) {
        self.clock = clock
        self.privacyConfig = privacyConfig
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

    public var isScreenLocked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _screenLocked
    }

    public func inspectCurrent() -> ActivitySample {
        let now = clock.now()
        let locked = isScreenLocked
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
        return PrivacyRedactor.redact(raw, config: privacyConfig)
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
