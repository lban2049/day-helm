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

    private static let knownContentDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org", "stackoverflow.com",
        "ycombinator.com", "reddit.com", "medium.com", "substack.com",
        "wikipedia.org", "zhihu.com", "juejin.cn", "cnblogs.com",
        "csdn.net", "segmentfault.com", "v2ex.com", "bilibili.com",
        "youtube.com", "youtu.be", "x.com", "twitter.com", "weibo.com",
        "xiaohongshu.com", "douyin.com", "tiktok.com", "google.com",
        "bing.com", "baidu.com", "duckduckgo.com", "jinritemai.com",
        "taobao.com", "tmall.com", "jd.com", "1688.com", "pinduoduo.com",
        "shopify.com", "amazon.com", "aliyun.com", "tencent.com",
        "cloudflare.com", "vercel.com", "netlify.com", "apple.com",
        "swift.org", "anthropic.com", "openai.com", "x.ai"
    ]

    private static let genericWebTitleWords: Set<String> = [
        "inbox", "memo", "memo inbox", "home", "index", "overview",
        "workspace", "panel", "portal", "console", "admin", "app",
        "入站", "收件箱", "概览", "首页", "控制台", "面板", "工作台"
    ]

    private static let rootWorkbenchPaths: Set<String> = [
        "", "/", "/index.html", "/home", "/app", "/inbox"
    ]

    private static let browserSuffixGroups: [(family: String, tokens: [String])] = [
        ("chrome", ["google chrome canary", "google chrome beta", "google chrome dev", "google chrome", "chrome"]),
        ("edge", ["microsoft edge canary", "microsoft edge beta", "microsoft edge dev", "microsoft edge", "edge"]),
        ("safari", ["safari technology preview", "safari"]),
        ("firefox", ["mozilla firefox", "firefox developer edition", "firefox nightly", "firefox"]),
        ("brave", ["brave browser", "brave"]),
        ("arc", ["arc"]),
        ("dia", ["dia browser", "dia"]),
        ("vivaldi", ["vivaldi"]),
        ("opera", ["opera gx", "opera"]),
        ("orion", ["orion"]),
        ("comet", ["comet"]),
        ("sigmaos", ["sigmaos"])
    ]

    private static let browserSeparators: [String] = [" - ", " — ", " – ", " | "]

    private static let browserMemorySuffixRegex = try! NSRegularExpression(
        pattern: #"(?:\s+[-—–|]\s+)(?:内存用量高|内存用量|High\s+memory\s+usage|Memory\s+usage)(?:\s*[-—–|:：]\s*|\s+)\d+(?:\.\d+)?\s*[KMGT]?i?B\s*$"#,
        options: [.caseInsensitive]
    )

    /// Normalizes a browser window title by stripping trailing `<Browser>[ - <Profile>]`
    /// and volatile memory-usage indicators (e.g. `- 内存用量高 - 883 MB`), leaving the page title intact.
    public static func cleanBrowserWindowTitle(_ title: String, appName: String = "") -> String {
        var result = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return result }

        let trimmedApp = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var candidateSuffixes: [String] = []
        if !trimmedApp.isEmpty {
            candidateSuffixes.append(trimmedApp)
            var matchedFamily = false
            for group in browserSuffixGroups {
                if trimmedApp == group.family
                    || trimmedApp.contains(group.family)
                    || group.tokens.contains(where: { trimmedApp == $0 }) {
                    candidateSuffixes.append(contentsOf: group.tokens)
                    matchedFamily = true
                }
            }
            if !matchedFamily {
                candidateSuffixes.append(contentsOf: browserSuffixGroups.flatMap { $0.tokens })
            }
        } else {
            candidateSuffixes.append(contentsOf: browserSuffixGroups.flatMap { $0.tokens })
        }

        // Deduplicate while keeping longer suffixes first so "google chrome" beats "chrome".
        var seenSuffixes = Set<String>()
        let uniqueSuffixes = candidateSuffixes
            .filter { !$0.isEmpty && seenSuffixes.insert($0).inserted }
            .sorted { $0.count > $1.count }

        var bestCutIndex: String.Index?
        for suffix in uniqueSuffixes {
            for sep in browserSeparators {
                let needle = sep + suffix
                var searchStart = result.startIndex
                while let range = result.range(of: needle, options: [.caseInsensitive], range: searchStart..<result.endIndex) {
                    let tail = result[range.upperBound...]
                    let validTail = tail.isEmpty || browserSeparators.contains(where: { tail.hasPrefix($0) && tail.count > $0.count })
                    if validTail, range.lowerBound > result.startIndex {
                        if bestCutIndex == nil || range.lowerBound > bestCutIndex! {
                            bestCutIndex = range.lowerBound
                        }
                    }
                    searchStart = range.upperBound
                }
            }
        }

        if let cutIndex = bestCutIndex {
            let stripped = String(result[..<cutIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                result = stripped
            }
        }

        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        if let match = browserMemorySuffixRegex.firstMatch(in: result, options: [], range: nsRange),
           let swiftRange = Range(match.range, in: result),
           swiftRange.lowerBound > result.startIndex {
            let stripped = String(result[..<swiftRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !stripped.isEmpty {
                result = stripped
            }
        }

        return result
    }

    private static func isKnownContentHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        for domain in knownContentDomains {
            if lower == domain || lower.hasSuffix("." + domain) {
                return true
            }
        }
        return false
    }

    private static func titleVisualUnits(_ title: String) -> Int {
        var units = 0
        for scalar in title.unicodeScalars {
            let v = scalar.value
            let isCJK = (0x4E00...0x9FFF).contains(v)
                || (0x3400...0x4DBF).contains(v)
                || (0xF900...0xFAFF).contains(v)
            units += isCJK ? 2 : 1
        }
        return units
    }

    private static let dateOnlyTitleRegex = try! NSRegularExpression(
        pattern: #"^\d{4}-\d{2}-\d{2}(?:\s*[-—|]\s*.{1,30})?$"#,
        options: []
    )

    private static let menuBarNoiseRegex = try! NSRegularExpression(
        pattern: #"(?:文件\s+编辑\s+显示|File\s+Edit\s+(?:Format\s+)?View\s+Window|历史记录\s+书签|个人资料\s+标签页\s+窗口\s+帮助)"#,
        options: [.caseInsensitive]
    )

    private static let dayHelmMenuBarPillRegex = try! NSRegularExpression(
        pattern: #"(?:开发构建|内容创作|业务运营|研究规划|沟通杂务|休息分心|其他事务|分心中|开发|创作|运营|研究|杂务|分心)\s*\d+(?:\s*/\s*\d+)?\s*m(?:[▲!·|\s]|$)"#,
        options: []
    )

    private static let statusBarCompanionRegex = try! NSRegularExpression(
        pattern: #"(?:\b\d{1,2}:\d{2}(?::\d{2})?\b|\b\d{1,3}\s*%|周[一二三四五六日天]|\d{1,2}月\d{1,2}日|DayHelm)"#,
        options: [.caseInsensitive]
    )

    private static let cjkMenuBarFamilies: [(tokens: [String], isTypoMarker: Bool)] = [
        (["文件", "文伴"], false),
        (["编辑", "编缉", "編辑", "編輯"], false),
        (["燴辑", "绘辑"], true),
        (["显示", "顯示", "显式", "视图", "視圖"], false),
        (["历史记录", "歷史記錄", "历史记"], false),
        (["历史记承"], true),
        (["书签", "書籤"], false),
        (["书簽", "书簦"], true),
        (["个人资料", "個人資料", "个人资科"], false),
        (["标签页", "標籤頁", "标簽页"], false),
        (["标答页"], true),
        (["窗口", "视窗"], false),
        (["窗ロ"], true),
        (["帮助", "幫助"], false),
        (["帮肋", "帮动"], true),
        (["前往", "格式"], false)
    ]

    private static let englishMenuBarTokens: [String] = [
        "file", "edit", "view", "window", "history", "bookmarks", "bookmark",
        "profiles", "profile", "tab", "help", "format", "selection", "shell", "terminal"
    ]

    private static let englishMenuGluedPairs: [String] = [
        "feedit", "fileedit", "viewwindow", "file edit", "edit view", "view window",
        "history bookmark", "window help", "bookmarks profiles", "tab window"
    ]

    private static let englishProseStopwords: [String] = [
        " the ", " and ", " for ", " with ", " this ", " that ", " from ", " please ", " is ", " are "
    ]

    /// Fine-grained semantic context key used for Jev caching & dwell tracking.
    /// Unlike SwitchClassifier's domain-level key, browser tabs keep their normalized title
    /// (after stripping browser/Profile/memory suffixes) so different channels/dashboards/pages
    /// on the same host do not collide while Profile names & memory warnings share the cache.
    public static func semanticContextKey(for sample: ActivitySample) -> String {
        let isBrowser = ActivityClassifier.isBrowser(appName: sample.appName, bundleId: sample.bundleId)
        let cleanedBrowserTitle: String? = (!sample.redacted && isBrowser)
            ? sample.windowTitle.flatMap { raw -> String? in
                let cleaned = cleanBrowserWindowTitle(raw, appName: sample.appName)
                return cleaned.isEmpty ? nil : cleaned
            }
            : sample.windowTitle
        let probeSpan = EnrichedSpan(
            startedAt: sample.timestamp,
            endedAt: sample.timestamp,
            appName: sample.appName,
            bundleId: sample.bundleId,
            windowTitle: cleanedBrowserTitle,
            url: sample.url,
            declaredTaskId: nil,
            redacted: sample.redacted
        )
        let baseKey = SwitchClassifier.canonicalContextKey(for: probeSpan)
        guard !sample.redacted, isBrowser else {
            return baseKey
        }
        guard let normTitle = SwitchClassifier.switchNormalizedTitle(cleanedBrowserTitle),
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

        // Self-hosted / custom web apps & workbenches with short/generic titles or root-level URLs
        let isWebContext = !lowerURL.isEmpty || ActivityClassifier.isBrowser(appName: appName, bundleId: nil)
        if isWebContext {
            let cleanedTitle = cleanBrowserWindowTitle(rawTitle, appName: appName)
            let cleanedLower = cleanedTitle.lowercased()
            if cleanedTitle.isEmpty
                || weakExactTitles.contains(cleanedLower)
                || cleanedLower.hasPrefix("无标题")
                || cleanedLower.hasPrefix("untitled") {
                return true
            }

            let urlComponents = (lowerURL.hasPrefix("http://") || lowerURL.hasPrefix("https://"))
                ? URLComponents(string: lowerURL)
                : nil
            let host = urlComponents?.host?.lowercased()
            let knownSite = host.map { isKnownContentHost($0) } ?? false

            if !knownSite {
                if titleVisualUnits(cleanedTitle) <= 12 || genericWebTitleWords.contains(cleanedLower) {
                    return true
                }
                if let host {
                    let trimmedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                    let isCustomSubdomain = trimmedHost.split(separator: ".").count >= 3
                    let pathLower = urlComponents?.path.lowercased() ?? ""
                    let hasNoQuery = (urlComponents?.query?.isEmpty ?? true)
                    if isCustomSubdomain && rootWorkbenchPaths.contains(pathLower) && hasNoQuery {
                        return true
                    }
                }
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
            let rawTitle = sample.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let titleLower = rawTitle.lowercased()
            let cleanedTitleLower = cleanBrowserWindowTitle(rawTitle, appName: sample.appName).lowercased()
            if cleanedTitleLower == "新标签页"
                || cleanedTitleLower == "new tab"
                || cleanedTitleLower == "起始页"
                || cleanedTitleLower == "start page"
                || cleanedTitleLower == "无标题"
                || cleanedTitleLower == "untitled"
                || cleanedTitleLower == "正在加载"
                || cleanedTitleLower == "loading"
                || cleanedTitleLower == "loading..."
                || cleanedTitleLower == "loading…"
                || titleLower.hasPrefix("新标签页 -")
                || titleLower.hasPrefix("新标签页 —")
                || titleLower.hasPrefix("new tab -")
                || titleLower.hasPrefix("new tab —")
                || titleLower.hasPrefix("无标题 -")
                || titleLower.hasPrefix("无标题 —")
                || titleLower.hasPrefix("untitled -")
                || titleLower.hasPrefix("untitled —") {
                return true
            }
            if (urlLower.isEmpty || urlLower.hasPrefix("chrome://"))
                && (cleanedTitleLower.hasPrefix("账号和同步")
                    || cleanedTitleLower.hasPrefix("accounts and sync")
                    || cleanedTitleLower.hasPrefix("turn on sync")) {
                return true
            }
        }
        return false
    }

    private static func isMenuBarNoiseLine(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if menuBarNoiseRegex.firstMatch(in: line, options: [], range: range) != nil {
            return true
        }
        guard line.count <= 160 else { return false }

        // Fuzzy Chinese menu bar detection (supports OCR typos like 燴辑, 历史记承)
        var cjkMatchedCount = 0
        var hasCJKTypo = false
        for family in cjkMenuBarFamilies {
            if family.tokens.contains(where: { line.contains($0) }) {
                cjkMatchedCount += 1
                if family.isTypoMarker {
                    hasCJKTypo = true
                }
            }
        }
        if cjkMatchedCount >= 2 {
            let wsTokens = line.split(whereSeparator: { $0.isWhitespace })
            let wsMenuTokens = wsTokens.filter { token in
                cjkMenuBarFamilies.contains { family in family.tokens.contains(where: { token.contains($0) }) }
            }.count
            if wsMenuTokens >= 2 || hasCJKTypo || cjkMatchedCount >= 3 {
                return true
            }
        }

        // Fuzzy English menu bar detection (supports glued OCR like FeEdit ViewWindow)
        let lower = " " + line.lowercased() + " "
        let hasProseStopword = englishProseStopwords.contains(where: { lower.contains($0) })
        if !hasProseStopword {
            var engMatchedCount = 0
            for token in englishMenuBarTokens where lower.contains(token) {
                engMatchedCount += 1
            }
            if lower.contains("feedit") {
                engMatchedCount += 1
            }
            let hasGluedPair = englishMenuGluedPairs.contains(where: { lower.contains($0) })
            if engMatchedCount >= 3 || (engMatchedCount >= 2 && hasGluedPair) {
                return true
            }
        }
        return false
    }

    private static func isDayHelmMenuBarPillLine(_ line: String) -> Bool {
        guard line.count <= 100 else { return false }
        let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard dayHelmMenuBarPillRegex.firstMatch(in: line, options: [], range: fullRange) != nil else {
            return false
        }
        var stripped = dayHelmMenuBarPillRegex.stringByReplacingMatches(in: line, options: [], range: fullRange, withTemplate: " ")
        let companionRange = NSRange(stripped.startIndex..<stripped.endIndex, in: stripped)
        stripped = statusBarCompanionRegex.stringByReplacingMatches(in: stripped, options: [], range: companionRange, withTemplate: " ")
        let remainingMeaningfulChars = stripped.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || (0x4E00...0x9FFF).contains(scalar.value)
        }.count
        return remainingMeaningfulChars <= 12
    }

    private static func isBrowserTabStripNoiseLine(_ line: String) -> Bool {
        guard line.count <= 180 else { return false }
        let closeCount = line.filter { $0 == "×" || $0 == "✕" }.count
        if closeCount >= 2 {
            return true
        }
        let hasNewTabMarker = line.contains("新标签页") || line.lowercased().contains("new tab")
        if closeCount >= 1 && (line.hasSuffix("+") || hasNewTabMarker) {
            return true
        }
        if hasNewTabMarker && (line.contains("|") || line.contains("·")) {
            return true
        }
        return false
    }

    /// Strips leading macOS menu-bar (including OCR-typo variants & DayHelm's own status pill)
    /// and browser tab-bar/address-bar noise from OCR text, returning the actual page/app body text.
    public static func stripTopChromeNoise(from text: String, url: String? = nil) -> String {
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rawLines.isEmpty else { return text }

        var startIdx = 0

        // 1. Browser address-bar anchor: everything above and including the address bar
        // is macOS menu bar + Chrome/Safari background tab strip.
        let rawHost = url.flatMap { URLComponents(string: $0)?.host?.lowercased() }
        let bareHost = rawHost.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 }
        let searchLimit = min(24, max(4, Int(Double(rawLines.count) * 0.45)))
        if rawLines.count >= 2 {
            for i in 0..<min(searchLimit, rawLines.count - 1) {
                let lower = rawLines[i].lowercased()
                let isSchemeOrLocal = lower.hasPrefix("http://")
                    || lower.hasPrefix("https://")
                    || lower.hasPrefix("localhost:")
                    || lower.hasPrefix("127.0.0.1:")
                let matchesTargetHost = (bareHost != nil && !bareHost!.isEmpty && lower.contains(bareHost!) && rawLines[i].count <= 140)
                if (isSchemeOrLocal && rawLines[i].count <= 140) || matchesTargetHost {
                    startIdx = i + 1
                    break
                }
            }
        }

        // 2. Strip leading macOS menu-bar lines (exact + OCR-typo fuzzy), DayHelm mode/duration pills,
        // and Chrome background tab-strip lines.
        var strippedCount = 0
        while startIdx < rawLines.count && strippedCount < 8 {
            let line = rawLines[startIdx]
            if isMenuBarNoiseLine(line)
                || isDayHelmMenuBarPillLine(line)
                || isBrowserTabStripNoiseLine(line) {
                startIdx += 1
                strippedCount += 1
            } else {
                break
            }
        }

        if startIdx >= rawLines.count {
            return ""
        }
        if startIdx > 0 {
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
            let isBrowser = ActivityClassifier.isBrowser(appName: cleanSample.appName, bundleId: cleanSample.bundleId)
            sanitizedTitle = cleanSample.windowTitle.flatMap { raw in
                let cleaned = isBrowser ? cleanBrowserWindowTitle(raw, appName: cleanSample.appName) : raw
                let scrubbed = PrivacyRedactor.sanitizeMetadataValue(cleaned)
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
                let histIsBrowser = ActivityClassifier.isBrowser(appName: cleanHist.appName, bundleId: cleanHist.bundleId)
                histTitle = cleanHist.windowTitle.flatMap { raw in
                    let cleaned = histIsBrowser ? cleanBrowserWindowTitle(raw, appName: cleanHist.appName) : raw
                    return collapseAndTruncate(PrivacyRedactor.sanitizeMetadataValue(cleaned), maxChars: 120)
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
    public var onDemandOCRWaitSeconds: TimeInterval
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
        onDemandOCRWaitSeconds: TimeInterval = 1.4,
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
        self.onDemandOCRWaitSeconds = onDemandOCRWaitSeconds
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
