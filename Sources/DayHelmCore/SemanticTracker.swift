import Foundation

/// Reserved category identifiers for non-planned activities and Layer-1 ActivityModes tracked automatically.
public enum AutoActivityIds {
    public static let otherWork = "__other_work__"
    public static let nonWork = "__non_work__"

    public static func modeCategoryId(for mode: ActivityMode) -> String {
        mode.categoryId
    }

    public static func activityMode(from categoryId: String) -> ActivityMode? {
        if categoryId == otherWork { return .commsAdmin }
        if categoryId == nonWork { return .breakTime }
        guard categoryId.hasPrefix("__mode_"), categoryId.hasSuffix("__") else {
            return nil
        }
        let raw = String(categoryId.dropFirst(7).dropLast(2))
        return ActivityMode(rawValue: raw)
    }

    public static func isReserved(_ id: String) -> Bool {
        id == otherWork || id == nonWork || activityMode(from: id) != nil
    }

    public static func displayName(for id: String) -> String? {
        if id == otherWork { return "其他事务" }
        if id == nonWork { return "分心/休息" }
        if let mode = activityMode(from: id) {
            return mode.displayName
        }
        return nil
    }

    public static func menuBarLabel(for id: String, compact: Bool) -> String? {
        if id == otherWork { return compact ? "杂务" : "其他事务" }
        if id == nonWork { return compact ? "分心" : "分心中" }
        if let mode = activityMode(from: id) {
            return compact ? mode.compactLabel : mode.displayName
        }
        return nil
    }
}

public enum ClassificationSource: String, Sendable, Equatable, Codable {
    case jev
    case cache
    case localOverride = "local_override"
    case localRule = "local_rule"
}

public struct SemanticClassification: Sendable, Equatable, Codable {
    public let categoryId: String
    public let activityMode: ActivityMode?
    public let focusProjectId: String?
    public let focusProjectConfidence: Double?
    public let confidence: Double
    public let probabilities: [String: Double]
    public let sameTaskAsPrevious: Double?
    public let isDistraction: Double
    public let source: ClassificationSource
    public let classifiedAt: Date
    public let latencyMs: Int?
    public let inputTokens: Int?

    public init(
        categoryId: String,
        activityMode: ActivityMode? = nil,
        focusProjectId: String? = nil,
        focusProjectConfidence: Double? = nil,
        confidence: Double,
        probabilities: [String: Double] = [:],
        sameTaskAsPrevious: Double? = nil,
        isDistraction: Double = 0.0,
        source: ClassificationSource = .jev,
        classifiedAt: Date,
        latencyMs: Int? = nil,
        inputTokens: Int? = nil
    ) {
        self.categoryId = categoryId
        self.activityMode = activityMode ?? AutoActivityIds.activityMode(from: categoryId)
        self.focusProjectId = focusProjectId
        self.focusProjectConfidence = focusProjectConfidence
        self.confidence = confidence
        self.probabilities = probabilities
        self.sameTaskAsPrevious = sameTaskAsPrevious
        self.isDistraction = isDistraction
        self.source = source
        self.classifiedAt = classifiedAt
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
    }

    public var semanticGroupKey: String {
        if let mode = activityMode, mode.isDistraction {
            return "break"
        }
        if categoryId == AutoActivityIds.nonWork {
            return "break"
        }
        if let pid = focusProjectId, !pid.isEmpty {
            return "proj:\(pid)"
        }
        if !AutoActivityIds.isReserved(categoryId) {
            return "proj:\(categoryId)"
        }
        if let mode = activityMode {
            return "mode:\(mode.rawValue)"
        }
        return "mode:other"
    }
}

public enum JevDecisionOutcome: String, Sendable, Equatable, Codable {
    case committedSwitch = "committed_switch"
    case maintained = "maintained"
    case pendingConfirmation = "pending_confirmation"
    case ignoredLowConfidence = "ignored_low_confidence"
    case manualPinned = "manual_pinned"
    case manualOverride = "manual_override"
    case error = "error"

    public var displayName: String {
        switch self {
        case .committedSwitch: return "已自动切换"
        case .maintained: return "保持当前"
        case .pendingConfirmation: return "防抖观察"
        case .ignoredLowConfidence: return "低置信忽略"
        case .manualPinned: return "手动锁定中"
        case .manualOverride: return "手动纠偏"
        case .error: return "调用异常"
        }
    }
}

public struct JevDecisionLogEntry: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let appName: String
    public let windowTitle: String?
    public let domain: String?
    public let redacted: Bool
    public let usedOCRSnippet: Bool
    public let ocrSnippetPreview: String?
    public let predictedCategoryId: String
    public let predictedDisplayName: String
    public let activityMode: ActivityMode?
    public let focusProjectDisplayName: String?
    public let confidence: Double
    public let sameTaskAsPrevious: Double?
    public let isDistraction: Double
    public let source: ClassificationSource
    public let outcome: JevDecisionOutcome
    public let latencyMs: Int?
    public let inputTokens: Int?
    public let errorMessage: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: Date,
        appName: String,
        windowTitle: String?,
        domain: String?,
        redacted: Bool,
        usedOCRSnippet: Bool,
        ocrSnippetPreview: String? = nil,
        predictedCategoryId: String,
        predictedDisplayName: String,
        activityMode: ActivityMode? = nil,
        focusProjectDisplayName: String? = nil,
        confidence: Double,
        sameTaskAsPrevious: Double? = nil,
        isDistraction: Double = 0.0,
        source: ClassificationSource,
        outcome: JevDecisionOutcome,
        latencyMs: Int? = nil,
        inputTokens: Int? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.domain = domain
        self.redacted = redacted
        self.usedOCRSnippet = usedOCRSnippet
        self.ocrSnippetPreview = ocrSnippetPreview
        self.predictedCategoryId = predictedCategoryId
        self.predictedDisplayName = predictedDisplayName
        self.activityMode = activityMode
        self.focusProjectDisplayName = focusProjectDisplayName
        self.confidence = confidence
        self.sameTaskAsPrevious = sameTaskAsPrevious
        self.isDistraction = isDistraction
        self.source = source
        self.outcome = outcome
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
        self.errorMessage = errorMessage
    }
}

/// Objective historical window entry passed to Jev (never carries previous model predictions).
public struct SemanticHistoryEntry: Sendable, Equatable, Codable {
    public let appName: String
    public let windowTitle: String?
    public let domain: String?
    public let durationSeconds: Int

    public init(
        appName: String,
        windowTitle: String?,
        domain: String?,
        durationSeconds: Int
    ) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.domain = domain
        self.durationSeconds = max(1, durationSeconds)
    }
}

public struct SemanticClassificationInput: Sendable, Equatable {
    public let timestamp: Date
    public let contextKey: String
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?
    public let url: String?
    public let ocrSnippet: String?
    public let redacted: Bool
    public let recentHistory: [SemanticHistoryEntry]
    public let budgets: [TaskBudget]

    public init(
        timestamp: Date,
        contextKey: String,
        appName: String,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        ocrSnippet: String? = nil,
        redacted: Bool = false,
        recentHistory: [SemanticHistoryEntry] = [],
        budgets: [TaskBudget]
    ) {
        self.timestamp = timestamp
        self.contextKey = contextKey
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.ocrSnippet = ocrSnippet
        self.redacted = redacted
        self.recentHistory = recentHistory
        self.budgets = budgets
    }
}

/// Hard privacy boundary before any context leaves the local machine to Jev.
public enum SemanticPayloadSanitizer {
    public static let maxOCRSnippetChars: Int = 600
    public static let maxTitleChars: Int = 180
    public static let maxHistoryEntries: Int = 3

    private static let weakExactTitles: Set<String> = [
        "", "window", "untitled", "new tab", "新标签页", "无标题", "无标题文档",
        "zsh", "bash", "fish", "~", "terminal", "终端",
        "qq", "wechat", "微信", "豆包", "chatgpt", "claude", "gemini", "obsidian", "discord", "alma"
    ]

    /// Multi-purpose dashboards, workbenches, chat apps, AI assistants, docs, and local web tools
    /// whose window titles alone do not reveal the actual on-screen task content.
    private static let multiPurposeKeywords: [String] = [
        "hermes", "dashboard", "kanban", "board", "看板", "工作台", "控制台",
        "discord", "vikunja", "notion", "feishu", "飞书", "lark", "slack", "telegram",
        "wechat", "微信", "qq", "claude", "chatgpt", "gemini", "doubao", "豆包",
        "alma", "obsidian", "wps", "excel", "numbers", "google docs", "google sheets",
        "terminal", "ghostty", "iterm", "warp"
    ]

    private static let dateOnlyTitleRegex = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}(?:\s*[-—|]\s*.{1,30})?$"#,
        options: []
    )

    private static let menuBarNoiseRegex = try! NSRegularExpression(
        pattern: #"(?:文件\s+编辑\s+显示|File\s+Edit\s+(?:Format\s+)?View\s+Window|历史记录\s+书签|个人资料\s+标签页\s+窗口\s+帮助)"#,
        options: [.caseInsensitive]
    )

    /// Fine-grained semantic context key used for Jev caching & dwell tracking.
    /// Unlike SwitchClassifier's domain-level key, browser tabs keep their normalized title
    /// so different channels/dashboards/pages on the same host (e.g. discord.com, x.com, localhost)
    /// do not collide in the 5-minute semantic cache.
    public static func semanticContextKey(for sample: ActivitySample) -> String {
        let probeSpan = EnrichedSpan(
            startedAt: sample.timestamp,
            endedAt: sample.timestamp,
            appName: sample.appName,
            bundleId: sample.bundleId,
            windowTitle: sample.windowTitle,
            url: sample.url,
            declaredTaskId: nil,
            redacted: sample.redacted
        )
        let baseKey = SwitchClassifier.canonicalContextKey(for: probeSpan)
        guard !sample.redacted,
              ActivityClassifier.isBrowser(appName: sample.appName, bundleId: sample.bundleId) else {
            return baseKey
        }
        guard let normTitle = SwitchClassifier.switchNormalizedTitle(sample.windowTitle),
              !normTitle.isEmpty else {
            return baseKey
        }
        if baseKey.hasSuffix("|\(normTitle)") {
            return baseKey
        }
        return "\(baseKey)|\(normTitle)"
    }

    /// Returns true when window title/URL is weak/generic OR belongs to a multi-purpose
    /// dashboard/workbench/chat/AI/local app where on-screen body OCR is essential.
    public static func shouldAttachOCR(appName: String, windowTitle: String?, url: String?) -> Bool {
        let rawTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lowerTitle = rawTitle.lowercased()
        let lowerApp = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let lowerURL = url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        if rawTitle.isEmpty || weakExactTitles.contains(lowerTitle) || lowerTitle == lowerApp {
            return true
        }
        if lowerTitle.hasPrefix("无标题") || lowerTitle.hasPrefix("untitled") || lowerTitle.hasPrefix("请稍候") {
            return true
        }
        let range = NSRange(rawTitle.startIndex..<rawTitle.endIndex, in: rawTitle)
        if dateOnlyTitleRegex.firstMatch(in: rawTitle, options: [], range: range) != nil {
            return true
        }
        // Very short generic titles without a meaningful web URL
        if rawTitle.count <= 6 && lowerURL.isEmpty {
            return true
        }
        // Local / tailnet / multi-purpose web tools & dashboards (e.g. Hermes Agent Dashboard, Vikunja, Discord)
        if lowerURL.contains("localhost") || lowerURL.contains("127.0.0.1") || lowerURL.contains(".ts.net") {
            return true
        }
        let combined = "\(lowerApp) \(lowerTitle) \(lowerURL)"
        for kw in multiPurposeKeywords {
            if combined.contains(kw) {
                return true
            }
        }
        return false
    }

    /// Transient auxiliary overlays and blank browser transition pages carry no standalone task intent;
    /// skipping Jev preserves the current active task and prevents noisy low-confidence records.
    private static let skippedOverlayAppPrefixes: [String] = [
        "dayhelm", "xnip", "cleanshot", "shottr", "spotlight", "raycast", "alfred",
        "stats", "maccy", "popclip", "digital color meter", "screenshot"
    ]

    private static let skippedOverlayBundlePrefixes: [String] = [
        "com.dayhelm", "com.xnipapp", "com.cleanshot", "cc.ffitch.shottr",
        "com.apple.spotlight", "com.raycast.macos", "com.runningwithcrayons.alfred",
        "eu.exelban.stats", "org.p0deje.maccy", "com.pilotmoon.popclip",
        "com.apple.screenshot.launcher", "com.apple.digitalcolormeter"
    ]

    public static func shouldSkipSemanticClassification(sample: ActivitySample) -> Bool {
        let appLower = sample.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bundleLower = sample.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if skippedOverlayAppPrefixes.contains(where: { appLower == $0 || appLower.hasPrefix($0 + " ") }) {
            return true
        }
        if !bundleLower.isEmpty && skippedOverlayBundlePrefixes.contains(where: { bundleLower.hasPrefix($0) }) {
            return true
        }
        if ActivityClassifier.isBrowser(appName: sample.appName, bundleId: sample.bundleId) {
            let urlLower = sample.url?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if urlLower.hasPrefix("chrome://newtab")
                || urlLower.hasPrefix("edge://newtab")
                || urlLower.hasPrefix("arc://newtab")
                || urlLower == "about:blank"
                || urlLower == "about:newtab" {
                return true
            }
            let titleLower = sample.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            if titleLower == "新标签页"
                || titleLower.hasPrefix("新标签页 -")
                || titleLower.hasPrefix("新标签页 —")
                || titleLower == "new tab"
                || titleLower.hasPrefix("new tab -")
                || titleLower.hasPrefix("new tab —")
                || titleLower == "起始页"
                || titleLower == "start page" {
                return true
            }
        }
        return false
    }

    /// Strips leading macOS menu-bar and browser tab-bar/address-bar noise from full-screen OCR text,
    /// returning the actual page/app body text.
    public static func stripTopChromeNoise(from text: String, url: String? = nil) -> String {
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard rawLines.count > 1 else { return text }

        var startIdx = 0

        // 1. Browser address-bar anchor: everything above and including the address bar
        // is macOS menu bar + Chrome/Safari background tab strip.
        let urlHost = url.flatMap { URLComponents(string: $0)?.host?.lowercased() }
        let searchLimit = min(24, max(4, Int(Double(rawLines.count) * 0.45)))
        if rawLines.count >= 4 {
            for i in 0..<min(searchLimit, rawLines.count - 1) {
                let lower = rawLines[i].lowercased()
                let isAddressLine = lower.hasPrefix("http://")
                    || lower.hasPrefix("https://")
                    || lower.hasPrefix("localhost:")
                    || lower.hasPrefix("127.0.0.1:")
                    || (urlHost != nil && !urlHost!.isEmpty && lower.contains(urlHost!) && rawLines[i].count <= 140)
                if isAddressLine {
                    startIdx = i + 1
                    break
                }
            }
        }

        // 2. Strip any remaining leading macOS menu-bar lines from startIdx onward.
        while startIdx < min(startIdx + 3, rawLines.count - 1) {
            let line = rawLines[startIdx]
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            if menuBarNoiseRegex.firstMatch(in: line, options: [], range: range) != nil {
                startIdx += 1
            } else {
                break
            }
        }

        if startIdx > 0 && startIdx < rawLines.count {
            return rawLines[startIdx...].joined(separator: " ")
        }
        return text
    }

    public static func buildInput(
        sample: ActivitySample,
        ocrText: String?,
        recentSpans: [EnrichedSpan],
        budgets: [TaskBudget],
        sendOCRSnippet: Bool,
        privacyConfig: PrivacyRedactorConfig
    ) -> SemanticClassificationInput? {
        guard !sample.screenLocked else { return nil }

        let cleanSample = PrivacyRedactor.redact(sample, config: privacyConfig)
        let contextKey = semanticContextKey(for: cleanSample)

        let sanitizedTitle: String?
        let sanitizedURL: String?
        let sanitizedOCR: String?

        if cleanSample.redacted {
            sanitizedTitle = nil
            sanitizedURL = nil
            sanitizedOCR = nil
        } else {
            sanitizedTitle = cleanSample.windowTitle.flatMap { raw in
                let scrubbed = PrivacyRedactor.sanitizeMetadataValue(raw)
                return collapseAndTruncate(scrubbed, maxChars: maxTitleChars)
            }
            sanitizedURL = cleanSample.url.flatMap { raw in
                let cleaned = PrivacyRedactor.sanitizeURL(raw) ?? raw
                let scrubbed = PrivacyRedactor.redactSecrets(in: cleaned)
                return collapseAndTruncate(scrubbed, maxChars: 240)
            }
            if sendOCRSnippet, let ocrText, !ocrText.isEmpty {
                let denoised = stripTopChromeNoise(from: ocrText, url: sanitizedURL)
                let scrubbedOCR = PrivacyRedactor.redactSecrets(in: denoised)
                sanitizedOCR = collapseAndTruncate(scrubbedOCR, maxChars: maxOCRSnippetChars)
            } else {
                sanitizedOCR = nil
            }
        }

        // Extract last N objective recent spans (excluding the current active contextKey).
        var history: [SemanticHistoryEntry] = []
        history.reserveCapacity(maxHistoryEntries)
        for span in recentSpans.reversed() {
            if history.count >= maxHistoryEntries { break }
            guard span.durationSeconds >= SwitchClassifier.defaultMinEffectiveDwellSeconds else { continue }

            let spanAsSample = ActivitySample(
                timestamp: span.endedAt,
                appName: span.appName,
                bundleId: span.bundleId,
                windowTitle: span.windowTitle,
                url: span.url,
                idleSeconds: 0,
                screenLocked: false,
                inputActive: true,
                redacted: span.redacted
            )
            let spanKey = semanticContextKey(for: spanAsSample)
            if spanKey == contextKey { continue }
            let cleanHist = PrivacyRedactor.redact(spanAsSample, config: privacyConfig)
            let histTitle: String?
            let histDomain: String?
            if cleanHist.redacted {
                histTitle = nil
                histDomain = nil
            } else {
                histTitle = cleanHist.windowTitle.flatMap {
                    collapseAndTruncate(PrivacyRedactor.sanitizeMetadataValue($0), maxChars: 120)
                }
                histDomain = SwitchClassifier.registrableDomain(from: cleanHist.url)
            }
            history.append(
                SemanticHistoryEntry(
                    appName: cleanHist.appName,
                    windowTitle: histTitle,
                    domain: histDomain,
                    durationSeconds: Int(span.durationSeconds.rounded())
                )
            )
        }
        history.reverse()

        return SemanticClassificationInput(
            timestamp: cleanSample.timestamp,
            contextKey: contextKey,
            appName: cleanSample.appName,
            bundleId: cleanSample.bundleId,
            windowTitle: sanitizedTitle,
            url: sanitizedURL,
            ocrSnippet: sanitizedOCR,
            redacted: cleanSample.redacted,
            recentHistory: history,
            budgets: budgets
        )
    }

    private static func collapseAndTruncate(_ text: String, maxChars: Int) -> String? {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= maxChars {
            return collapsed
        }
        return String(collapsed.prefix(maxChars))
    }
}

public struct SemanticTrackerConfig: Sendable, Equatable {
    public var minDwellBeforeClassifySeconds: TimeInterval
    public var cacheSwitchDwellSeconds: TimeInterval
    public var coldStartConfidence: Double
    public var minConfidenceToSwitch: Double
    public var immediateSwitchConfidence: Double
    public var immediateSwitchMaxSameTaskProb: Double
    public var fastSwitchConfidence: Double
    public var fastSwitchMaxSameTaskProb: Double
    public var minSwitchConfirmSeconds: TimeInterval
    public var fastSwitchConfirmSeconds: TimeInterval
    public var contextCacheTTLSeconds: TimeInterval
    public var manualPinCooldownSeconds: TimeInterval

    public static let `default` = SemanticTrackerConfig()

    public init(
        minDwellBeforeClassifySeconds: TimeInterval = 0.65,
        cacheSwitchDwellSeconds: TimeInterval = 0.45,
        coldStartConfidence: Double = 0.55,
        minConfidenceToSwitch: Double = 0.70,
        immediateSwitchConfidence: Double = 0.80,
        immediateSwitchMaxSameTaskProb: Double = 0.60,
        fastSwitchConfidence: Double = 0.75,
        fastSwitchMaxSameTaskProb: Double = 0.65,
        minSwitchConfirmSeconds: TimeInterval = 2.5,
        fastSwitchConfirmSeconds: TimeInterval = 1.2,
        contextCacheTTLSeconds: TimeInterval = 300.0,
        manualPinCooldownSeconds: TimeInterval = 600.0
    ) {
        self.minDwellBeforeClassifySeconds = minDwellBeforeClassifySeconds
        self.cacheSwitchDwellSeconds = cacheSwitchDwellSeconds
        self.coldStartConfidence = coldStartConfidence
        self.minConfidenceToSwitch = minConfidenceToSwitch
        self.immediateSwitchConfidence = immediateSwitchConfidence
        self.immediateSwitchMaxSameTaskProb = immediateSwitchMaxSameTaskProb
        self.fastSwitchConfidence = fastSwitchConfidence
        self.fastSwitchMaxSameTaskProb = fastSwitchMaxSameTaskProb
        self.minSwitchConfirmSeconds = minSwitchConfirmSeconds
        self.fastSwitchConfirmSeconds = fastSwitchConfirmSeconds
        self.contextCacheTTLSeconds = contextCacheTTLSeconds
        self.manualPinCooldownSeconds = manualPinCooldownSeconds
    }
}

public struct SemanticTrackerDecision: Sendable, Equatable {
    public let committedCategoryId: String?
    public let didSwitch: Bool
    public let pendingCategoryId: String?

    public init(committedCategoryId: String?, didSwitch: Bool, pendingCategoryId: String?) {
        self.committedCategoryId = committedCategoryId
        self.didSwitch = didSwitch
        self.pendingCategoryId = pendingCategoryId
    }
}

/// Pure, deterministic, clock-injected hysteresis state machine for semantic auto-tracking.
public final class SemanticAutoTracker: @unchecked Sendable {
    private struct PendingCandidate {
        let categoryId: String
        var contextKey: String
        let firstSeenAt: Date
        var latestConfidence: Double
        var latestSameTaskProb: Double?
    }

    private struct CacheEntry {
        let classification: SemanticClassification
        let budgetsVersion: Int
        let usedOCR: Bool
        let cachedAt: Date
    }

    private let lock = NSLock()
    public let config: SemanticTrackerConfig

    private var _currentCategoryId: String?
    private var _latestClassification: SemanticClassification?
    private var pending: PendingCandidate?
    private var cache: [String: CacheEntry] = [:]
    private var manualOverridesByContextKey: [String: String] = [:]
    private var manualPin: (contextKey: String?, until: Date)?

    public init(config: SemanticTrackerConfig = .default) {
        self.config = config
    }

    public var currentCategoryId: String? {
        lock.withLock { _currentCategoryId }
    }

    public var latestClassification: SemanticClassification? {
        lock.withLock { _latestClassification }
    }

    public var isManualPinActive: Bool {
        lock.withLock { manualPin != nil }
    }

    public func manualOverride(for contextKey: String) -> String? {
        lock.withLock { manualOverridesByContextKey[contextKey] }
    }

    public func cachedClassification(
        for contextKey: String,
        budgetsVersion: Int,
        hasFreshOCR: Bool = false,
        at now: Date
    ) -> SemanticClassification? {
        lock.withLock {
            guard let entry = cache[contextKey],
                  entry.budgetsVersion == budgetsVersion,
                  now.timeIntervalSince(entry.cachedAt) <= config.contextCacheTTLSeconds else {
                return nil
            }
            // If previously classified before OCR finished, allow a one-time re-evaluation now that OCR is ready.
            if hasFreshOCR && !entry.usedOCR {
                return nil
            }
            return SemanticClassification(
                categoryId: entry.classification.categoryId,
                activityMode: entry.classification.activityMode,
                focusProjectId: entry.classification.focusProjectId,
                focusProjectConfidence: entry.classification.focusProjectConfidence,
                confidence: entry.classification.confidence,
                probabilities: entry.classification.probabilities,
                sameTaskAsPrevious: entry.classification.sameTaskAsPrevious,
                isDistraction: entry.classification.isDistraction,
                source: .cache,
                classifiedAt: entry.classification.classifiedAt,
                latencyMs: entry.classification.latencyMs,
                inputTokens: entry.classification.inputTokens
            )
        }
    }

    public func storeCache(
        _ classification: SemanticClassification,
        for contextKey: String,
        budgetsVersion: Int,
        usedOCR: Bool = false,
        at now: Date
    ) {
        lock.withLock {
            if cache.count >= 512 {
                cache.removeAll(keepingCapacity: true)
            }
            cache[contextKey] = CacheEntry(
                classification: classification,
                budgetsVersion: budgetsVersion,
                usedOCR: usedOCR,
                cachedAt: now
            )
        }
    }

    @discardableResult
    public func apply(
        classification: SemanticClassification,
        contextKey: String,
        budgetsVersion: Int = 1,
        usedOCR: Bool = false,
        at now: Date
    ) -> SemanticTrackerDecision {
        lock.withLock {
            if classification.source == .jev {
                if cache.count >= 512 {
                    cache.removeAll(keepingCapacity: true)
                }
                cache[contextKey] = CacheEntry(
                    classification: classification,
                    budgetsVersion: budgetsVersion,
                    usedOCR: usedOCR,
                    cachedAt: now
                )
            }
            _latestClassification = classification

            // Respect active manual pin while still on the pinned context.
            if let pin = manualPin {
                if now < pin.until && (pin.contextKey == nil || pin.contextKey == contextKey) {
                    pending = nil
                    return SemanticTrackerDecision(
                        committedCategoryId: _currentCategoryId,
                        didSwitch: false,
                        pendingCategoryId: nil
                    )
                } else {
                    manualPin = nil
                }
            }

            // Day-scoped user correction memory for this contextKey.
            if let overrideId = manualOverridesByContextKey[contextKey] {
                let changed = (_currentCategoryId != overrideId)
                _currentCategoryId = overrideId
                pending = nil
                return SemanticTrackerDecision(
                    committedCategoryId: overrideId,
                    didSwitch: changed,
                    pendingCategoryId: nil
                )
            }

            // Cold start: adopt immediately if confidence >= coldStartConfidence.
            if _currentCategoryId == nil {
                if classification.confidence >= config.coldStartConfidence {
                    _currentCategoryId = classification.categoryId
                    pending = nil
                    return SemanticTrackerDecision(
                        committedCategoryId: classification.categoryId,
                        didSwitch: true,
                        pendingCategoryId: nil
                    )
                }
                return SemanticTrackerDecision(committedCategoryId: nil, didSwitch: false, pendingCategoryId: nil)
            }

            // Staying in the same category clears any pending candidate.
            if classification.categoryId == _currentCategoryId {
                pending = nil
                return SemanticTrackerDecision(
                    committedCategoryId: _currentCategoryId,
                    didSwitch: false,
                    pendingCategoryId: nil
                )
            }

            // Low-confidence predictions do not initiate a switch.
            if classification.confidence < config.minConfidenceToSwitch {
                if classification.confidence < 0.50 {
                    pending = nil
                }
                return SemanticTrackerDecision(
                    committedCategoryId: _currentCategoryId,
                    didSwitch: false,
                    pendingCategoryId: pending?.categoryId
                )
            }

            // Clear high-confidence switch: commit immediately after the initial 0.65s pre-classify dwell
            // so the menu bar responds in ~0.9–1.0s (<= 2.0s even on cold TLS reconnect) instead of stalling in anti-flicker dwell.
            if classification.confidence >= config.immediateSwitchConfidence
                && (classification.sameTaskAsPrevious ?? 0.0) <= config.immediateSwitchMaxSameTaskProb {
                _currentCategoryId = classification.categoryId
                pending = nil
                return SemanticTrackerDecision(
                    committedCategoryId: classification.categoryId,
                    didSwitch: true,
                    pendingCategoryId: nil
                )
            }

            // Moderate-confidence or ambiguous candidate: apply brief automatic anti-flicker dwell (1.2s-2.5s).
            // Update contextKey when another window confirms the same target category so cross-app work advances dwell cleanly.
            if var existing = pending, existing.categoryId == classification.categoryId {
                existing.contextKey = contextKey
                existing.latestConfidence = classification.confidence
                existing.latestSameTaskProb = classification.sameTaskAsPrevious
                pending = existing
                return evaluatePendingLocked(at: now)
            } else {
                pending = PendingCandidate(
                    categoryId: classification.categoryId,
                    contextKey: contextKey,
                    firstSeenAt: now,
                    latestConfidence: classification.confidence,
                    latestSameTaskProb: classification.sameTaskAsPrevious
                )
                return SemanticTrackerDecision(
                    committedCategoryId: _currentCategoryId,
                    didSwitch: false,
                    pendingCategoryId: classification.categoryId
                )
            }
        }
    }

    public func remainingConfirmSeconds(for activeContextKey: String, at now: Date) -> TimeInterval? {
        lock.withLock {
            guard let candidate = pending, candidate.contextKey == activeContextKey else {
                return nil
            }
            let elapsed = max(0, now.timeIntervalSince(candidate.firstSeenAt))
            let isFastUnmistakable = candidate.latestConfidence >= config.fastSwitchConfidence
                && (candidate.latestSameTaskProb ?? 1.0) <= config.fastSwitchMaxSameTaskProb
            let required = isFastUnmistakable ? config.fastSwitchConfirmSeconds : config.minSwitchConfirmSeconds
            return max(0, required - elapsed)
        }
    }

    @discardableResult
    public func tickDwell(activeContextKey: String, at now: Date) -> SemanticTrackerDecision {
        lock.withLock {
            if let pin = manualPin, now >= pin.until || (pin.contextKey != nil && pin.contextKey != activeContextKey) {
                manualPin = nil
            }
            guard let existing = pending else {
                return SemanticTrackerDecision(committedCategoryId: _currentCategoryId, didSwitch: false, pendingCategoryId: nil)
            }
            // If user navigated away from the pending candidate's context before confirmation, wait unless same category re-confirms.
            if existing.contextKey != activeContextKey {
                return SemanticTrackerDecision(
                    committedCategoryId: _currentCategoryId,
                    didSwitch: false,
                    pendingCategoryId: existing.categoryId
                )
            }
            return evaluatePendingLocked(at: now)
        }
    }

    public func recordManualSelection(categoryId: String?, contextKey: String?, at now: Date) {
        lock.withLock {
            _currentCategoryId = categoryId
            pending = nil
            if let categoryId {
                if let contextKey, !contextKey.isEmpty {
                    manualOverridesByContextKey[contextKey] = categoryId
                }
                manualPin = (
                    contextKey: contextKey,
                    until: now.addingTimeInterval(config.manualPinCooldownSeconds)
                )
            } else {
                manualPin = nil
            }
        }
    }

    public func clearManualPin() {
        lock.withLock {
            manualPin = nil
        }
    }

    public func resetForNewDay() {
        lock.withLock {
            _currentCategoryId = nil
            _latestClassification = nil
            pending = nil
            cache.removeAll(keepingCapacity: true)
            manualOverridesByContextKey.removeAll(keepingCapacity: true)
            manualPin = nil
        }
    }

    private func evaluatePendingLocked(at now: Date) -> SemanticTrackerDecision {
        guard let candidate = pending else {
            return SemanticTrackerDecision(committedCategoryId: _currentCategoryId, didSwitch: false, pendingCategoryId: nil)
        }
        let elapsed = max(0, now.timeIntervalSince(candidate.firstSeenAt))
        let isFastUnmistakable = candidate.latestConfidence >= config.fastSwitchConfidence
            && (candidate.latestSameTaskProb ?? 1.0) <= config.fastSwitchMaxSameTaskProb
        let required = isFastUnmistakable ? config.fastSwitchConfirmSeconds : config.minSwitchConfirmSeconds
        if elapsed >= required {
            let committed = candidate.categoryId
            let changed = (_currentCategoryId != committed)
            _currentCategoryId = committed
            pending = nil
            return SemanticTrackerDecision(
                committedCategoryId: committed,
                didSwitch: changed,
                pendingCategoryId: nil
            )
        }
        return SemanticTrackerDecision(
            committedCategoryId: _currentCategoryId,
            didSwitch: false,
            pendingCategoryId: candidate.categoryId
        )
    }
}
