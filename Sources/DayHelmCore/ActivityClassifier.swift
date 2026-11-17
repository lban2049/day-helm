import Foundation

/// Canonical event kinds written to `activity_events.kind`.
///
/// Keep the raw values stable: they are part of the Alma-compatible HTTP contract.
public enum ActivityEventKind: String, Sendable, Equatable, CaseIterable {
    case appFocus = "app_focus"
    case browserVisit = "browser_visit"
    case click = "click"
    case keypress = "keypress"
    case typingPause = "typing_pause"
    case lock = "lock"
    case unlock = "unlock"
}

/// Decides whether an activity sample is a browser visit or a plain app focus.
///
/// A `browser_visit` must be a real web URL opened in a known browser. Any other
/// `AXDocument` value (e.g. `file:///.../Report.pdf` from Preview, a project file
/// from Xcode, a folder from Finder) is recorded as `app_focus`, which is what
/// Alma consumers expect.
public enum ActivityClassifier {
    /// Bundle-id prefixes (case-insensitive) of known web browsers.
    public static let knownBrowserBundlePrefixes: [String] = [
        "com.apple.safari",
        "com.google.chrome",
        "com.microsoft.edgemac",
        "org.mozilla.firefox",
        "com.brave.browser",
        "company.thebrowser.browser", // Arc
        "com.operasoftware.opera",
        "com.vivaldi.vivaldi",
        "com.duckduckgo.macos.browser",
        "ai.perplexity.comet",
        "com.kagi.kagi", // Orion
        "com.sigmaos.sigmaos.macos" // SigmaOS
    ]

    /// Application-name keywords used when a bundle id is unavailable.
    public static let browserAppNameKeywords: [String] = [
        "chrome", "safari", "firefox", "edge", "brave", "arc",
        "opera", "vivaldi", "orion", "comet", "sigmaos"
    ]

    public static func isWebURL(_ rawURL: String?) -> Bool {
        guard let trimmed = nonEmpty(rawURL),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    public static func isBrowser(appName: String?, bundleId: String?) -> Bool {
        if let bundle = bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !bundle.isEmpty {
            for prefix in knownBrowserBundlePrefixes where bundle == prefix || bundle.hasPrefix(prefix + ".") {
                return true
            }
        }
        let name = appName?.lowercased() ?? ""
        guard !name.isEmpty else { return false }
        return browserAppNameKeywords.contains { name.contains($0) }
    }

    /// Returns `browser_visit` only for a web URL in a known browser; otherwise `app_focus`.
    public static func eventKind(
        appName: String?,
        bundleId: String?,
        url: String?,
        redacted: Bool
    ) -> String {
        guard !redacted,
              isWebURL(url),
              isBrowser(appName: appName, bundleId: bundleId) else {
            return ActivityEventKind.appFocus.rawValue
        }
        return ActivityEventKind.browserVisit.rawValue
    }

    /// Stable change-detection key for a URL: drops the fragment and lowercases only scheme/host.
    public static func normalizedURLKey(_ rawURL: String?) -> String? {
        guard let trimmed = nonEmpty(rawURL) else { return nil }
        guard var components = URLComponents(string: trimmed) else {
            return trimmed
        }
        components.fragment = nil
        if let scheme = components.scheme {
            components.scheme = scheme.lowercased()
        }
        if let host = components.host {
            components.host = host.lowercased()
        }
        return components.string ?? trimmed
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

/// Normalizes volatile window-title fragments so that page counters, clocks,
/// percentages and loading ellipses do not generate a new event on every poll.
///
/// The original title is still persisted verbatim; only change detection uses the key.
public enum ActivityTextNormalizer {
    /// Returns a comparison key, or `nil` for an empty title.
    public static func normalizedTitleKey(_ title: String?) -> String? {
        guard let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        var text = raw.replacingOccurrences(of: "\u{00A0}", with: " ")

        // Bracketed counters: "(3)", "[12+]", "（5）"
        text = replace(#"[\(\[]\s*\d{1,4}\s*\+?\s*[\)\]]"#, in: text)
        text = replace(#"[（【]\s*\d{1,4}\s*\+?\s*[）】]"#, in: text)
        // Clocks: 14:52, 09:03:11
        text = replace(#"\b\d{1,2}:\d{2}(?::\d{2})?\b"#, in: text)
        // Percentages: 87%, 12.5 %
        text = replace(#"\b\d{1,3}(?:\.\d+)?\s*%"#, in: text)
        // Loading / progress ellipses
        text = text
            .replacingOccurrences(of: "…", with: " ")
            .replacingOccurrences(of: "...", with: " ")
        // Bare numbers (year, unread badge, step count). Keep digits glued to letters (v2, Q4).
        text = replace(#"(?<![A-Za-z0-9])\d+(?![A-Za-z0-9])"#, in: text)
        // Decorative separators
        text = replace(#"[•·|–—]+"#, in: text)

        text = text.lowercased()
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    public static func isVolatileOnlyChange(previous: String?, current: String?) -> Bool {
        guard previous != current else { return false }
        return normalizedTitleKey(previous) == normalizedTitleKey(current)
    }

    /// Composite change key used by the recorder for event de-duplication.
    public static func normalizedChangeKey(
        appName: String,
        bundleId: String?,
        title: String?,
        url: String?
    ) -> String {
        let app = appName.lowercased()
        let bundle = bundleId?.lowercased() ?? ""
        let titleKey = normalizedTitleKey(title) ?? ""
        let urlKey = ActivityClassifier.normalizedURLKey(url) ?? ""
        return "\(app)|\(bundle)|\(titleKey)|\(urlKey)"
    }

    private static func replace(_ pattern: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }
}
