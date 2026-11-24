import Foundation

public enum WorkflowCluster: String, Sendable, Equatable {
    case engineering
    case designAndCommerce
    case researchAndWriting
}

public enum AppRole: Sendable, Equatable {
    case auxiliary
    case interrupt
    case workflowCluster(WorkflowCluster)
    case general
}

public struct PreparedActivitySpan: Sendable, Equatable {
    public let span: EnrichedSpan
    public let effectiveDwellSeconds: TimeInterval
    public let role: AppRole
    public let contextKey: String
    internal let appKey: String
    internal let bundleLower: String
    internal let isBrowser: Bool
    internal let urlHostLower: String?
    internal let registrableDomain: String?
    internal let projectTokens: Set<String>
    internal let searchableLower: String

    public init(
        span: EnrichedSpan,
        effectiveDwellSeconds: TimeInterval,
        role: AppRole,
        contextKey: String
    ) {
        let features = SwitchClassifier.cachedFeatures(for: span)
        self.span = span
        self.effectiveDwellSeconds = effectiveDwellSeconds
        self.role = role
        self.contextKey = contextKey
        self.appKey = features.appKey
        self.bundleLower = features.bundleLower
        self.isBrowser = features.isBrowser
        self.urlHostLower = features.urlHostLower
        self.registrableDomain = features.registrableDomain
        self.projectTokens = features.projectTokens
        self.searchableLower = features.searchableLower
    }

    internal init(
        span: EnrichedSpan,
        effectiveDwellSeconds: TimeInterval,
        features: SwitchClassifier.CachedSpanFeatures
    ) {
        self.span = span
        self.effectiveDwellSeconds = effectiveDwellSeconds
        self.role = features.role
        self.contextKey = features.contextKey
        self.appKey = features.appKey
        self.bundleLower = features.bundleLower
        self.isBrowser = features.isBrowser
        self.urlHostLower = features.urlHostLower
        self.registrableDomain = features.registrableDomain
        self.projectTokens = features.projectTokens
        self.searchableLower = features.searchableLower
    }
}

public enum SwitchClassifier {
    public static let defaultMinEffectiveDwellSeconds: TimeInterval = 4.0
    public static let defaultBridgeGapSeconds: TimeInterval = 60.0
    private static let spanFeaturesCacheCapacity = 4096
    private static let titleNormCacheCapacity = 2048

    private struct SpanFeaturesKey: Hashable {
        let appName: String
        let bundleId: String?
        let windowTitle: String?
        let url: String?
        let redacted: Bool

        init(span: EnrichedSpan) {
            self.appName = span.appName
            self.bundleId = span.bundleId
            self.windowTitle = span.windowTitle
            self.url = span.url
            self.redacted = span.redacted
        }
    }

    internal struct CachedSpanFeatures: Sendable, Equatable {
        let role: AppRole
        let contextKey: String
        let projectTokens: Set<String>
        let appKey: String
        let bundleLower: String
        let isBrowser: Bool
        let urlHostLower: String?
        let registrableDomain: String?
        let searchableLower: String
    }

    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var spanFeaturesCache: [SpanFeaturesKey: CachedSpanFeatures] = [:]
    private nonisolated(unsafe) static var titleNormCache: [String: String] = [:]

    // MARK: - Volatile Jitter Normalization (preserves meaningful numeric IDs like "Tab 0", "PR 12")

    public static func switchNormalizedTitle(_ title: String?) -> String? {
        guard let title, !title.isEmpty else { return nil }
        cacheLock.lock()
        if let cached = titleNormCache[title] {
            cacheLock.unlock()
            return cached.isEmpty ? nil : cached
        }
        cacheLock.unlock()

        let computed = computeSwitchNormalizedTitle(title)
        cacheLock.lock()
        if titleNormCache.count >= titleNormCacheCapacity {
            titleNormCache.removeAll(keepingCapacity: true)
        }
        titleNormCache[title] = computed ?? ""
        cacheLock.unlock()
        return computed
    }

    private static func computeSwitchNormalizedTitle(_ title: String) -> String? {
        let raw = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return nil
        }

        var text = raw.replacingOccurrences(of: "\u{00A0}", with: " ")

        // Bracketed counters: "(3)", "[12+]", "（5）"
        text = replace(bracketCounterRegex, in: text)
        text = replace(cjkBracketCounterRegex, in: text)
        // Clocks: 14:52, 09:03:11
        text = replace(clockRegex, in: text)
        // Percentages: 87%, 12.5 %
        text = replace(percentRegex, in: text)
        // Loading / progress ellipses
        text = text
            .replacingOccurrences(of: "…", with: " ")
            .replacingOccurrences(of: "...", with: " ")
        // Decorative separators (keep ASCII hyphen '-' inside repo/project names like focus-guard)
        text = replace(separatorRegex, in: text)

        text = text.lowercased()
        let collapsed = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    public static func isVolatileJitterOnly(previous: String?, current: String?) -> Bool {
        guard previous != current else { return false }
        guard let prevNorm = switchNormalizedTitle(previous),
              let currNorm = switchNormalizedTitle(current) else {
            return false
        }
        return prevNorm == currNorm
    }

    // MARK: - Domain & Context Keys

    public static func registrableDomain(from rawURL: String?) -> String? {
        guard let trimmed = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let rawHost = components.host?.lowercased(),
              !rawHost.isEmpty else {
            return nil
        }

        var host = rawHost
        if host.hasPrefix("www.") {
            host = String(host.dropFirst(4))
        }

        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            if let port = components.port {
                return "\(host):\(port)"
            }
            return host
        }

        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2 else { return host }

        // Keep 3 labels for common second-level ccTLDs (e.g. .com.cn, .co.uk)
        let twoLevelSuffixes: Set<String> = ["com", "net", "org", "edu", "gov", "co"]
        if labels.count >= 3,
           labels[labels.count - 1].count == 2,
           twoLevelSuffixes.contains(labels[labels.count - 2]) {
            return labels.suffix(3).joined(separator: ".")
        }
        return labels.suffix(2).joined(separator: ".")
    }

    private static func computeFeatures(for span: EnrichedSpan) -> CachedSpanFeatures {
        let appKey = normalizedAppKey(appName: span.appName, bundleId: span.bundleId)
        let bundleLower = span.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let isBrowser = ActivityClassifier.isBrowser(appName: span.appName, bundleId: span.bundleId)
        let rawURLTrimmed = span.url?.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedComponents = (rawURLTrimmed?.isEmpty == false) ? URLComponents(string: rawURLTrimmed!) : nil
        let urlHostLower = parsedComponents?.host?.lowercased()
        let regDomain = registrableDomain(from: span.url)
        let searchableLower: String
        if span.redacted {
            searchableLower = ""
        } else {
            searchableLower = [span.windowTitle, span.url, span.appName]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
        }

        return CachedSpanFeatures(
            role: computeRole(for: span),
            contextKey: computeCanonicalContextKey(for: span),
            projectTokens: computeProjectTokens(for: span),
            appKey: appKey,
            bundleLower: bundleLower,
            isBrowser: isBrowser,
            urlHostLower: urlHostLower,
            registrableDomain: regDomain,
            searchableLower: searchableLower
        )
    }

    internal static func cachedFeatures(for span: EnrichedSpan) -> CachedSpanFeatures {
        let key = SpanFeaturesKey(span: span)
        cacheLock.lock()
        if let hit = spanFeaturesCache[key] {
            cacheLock.unlock()
            return hit
        }
        cacheLock.unlock()

        let features = computeFeatures(for: span)
        cacheLock.lock()
        if spanFeaturesCache.count >= spanFeaturesCacheCapacity {
            spanFeaturesCache.removeAll(keepingCapacity: true)
        }
        spanFeaturesCache[key] = features
        cacheLock.unlock()
        return features
    }

    internal static func cachedFeaturesBatch(for spans: [EnrichedSpan]) -> [CachedSpanFeatures] {
        guard !spans.isEmpty else { return [] }
        var keys: [SpanFeaturesKey] = []
        keys.reserveCapacity(spans.count)
        for span in spans {
            keys.append(SpanFeaturesKey(span: span))
        }

        var results = Array<CachedSpanFeatures?>(repeating: nil, count: spans.count)
        var missingIndices: [Int] = []

        cacheLock.lock()
        for i in 0..<keys.count {
            if let hit = spanFeaturesCache[keys[i]] {
                results[i] = hit
            } else {
                missingIndices.append(i)
            }
        }
        cacheLock.unlock()

        if !missingIndices.isEmpty {
            var computed: [(SpanFeaturesKey, CachedSpanFeatures)] = []
            computed.reserveCapacity(missingIndices.count)
            for idx in missingIndices {
                let features = computeFeatures(for: spans[idx])
                results[idx] = features
                computed.append((keys[idx], features))
            }

            cacheLock.lock()
            if spanFeaturesCache.count + computed.count > spanFeaturesCacheCapacity {
                spanFeaturesCache.removeAll(keepingCapacity: true)
            }
            for (k, v) in computed {
                spanFeaturesCache[k] = v
            }
            cacheLock.unlock()
        }

        return results.map { $0! }
    }

    public static func canonicalContextKey(for span: EnrichedSpan) -> String {
        cachedFeatures(for: span).contextKey
    }

    /// Coarse context key used for thrashing `distinctContexts` counting:
    /// - When Jev semanticGroup is present, groups by semantic group (same project/mode = 1 context).
    /// - For workflow-cluster apps (IDE, Terminal, Editor, Notes, Design), groups by appKey so intra-app file/pane switches don't inflate distinctContexts.
    /// - For browsers and other apps, keeps the canonical contextKey (registrableDomain or normalized title).
    public static func thrashingContextKey(for prepared: PreparedActivitySpan) -> String {
        if let sem = prepared.span.semanticGroup, !sem.isEmpty {
            return "sem|\(sem)"
        }
        if prepared.isBrowser {
            return prepared.contextKey
        }
        if case .workflowCluster = prepared.role {
            return "app|\(prepared.appKey)"
        }
        return prepared.contextKey
    }

    private static func computeCanonicalContextKey(for span: EnrichedSpan) -> String {
        let appKey = normalizedAppKey(appName: span.appName, bundleId: span.bundleId)
        if span.redacted {
            return "redacted|\(appKey)"
        }
        if ActivityClassifier.isBrowser(appName: span.appName, bundleId: span.bundleId) {
            if let domain = registrableDomain(from: span.url) {
                return "browser|\(appKey)|\(domain)"
            }
            let titleKey = switchNormalizedTitle(span.windowTitle) ?? ""
            return "browser|\(appKey)|\(titleKey)"
        }
        let titleKey = switchNormalizedTitle(span.windowTitle) ?? ""
        return "app|\(appKey)|\(titleKey)"
    }

    // MARK: - Project / Entity Anchor Extraction

    public static func projectTokens(for span: EnrichedSpan) -> Set<String> {
        cachedFeatures(for: span).projectTokens
    }

    private static func computeProjectTokens(for span: EnrichedSpan) -> Set<String> {
        guard !span.redacted else { return [] }
        var tokens: Set<String> = []

        if let rawURL = span.url?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawURL.isEmpty,
           let components = URLComponents(string: rawURL) {
            let host = components.host?.lowercased() ?? ""
            let pathParts = components.path
                .split(separator: "/")
                .map { String($0).lowercased() }
                .filter { !$0.isEmpty }

            if (host.contains("github.com") || host.contains("gitlab.com") || host.contains("bitbucket.org")),
               pathParts.count >= 2 {
                let owner = pathParts[0]
                let repo = pathParts[1].replacingOccurrences(of: ".git", with: "")
                if !owner.isEmpty && !repo.isEmpty {
                    tokens.insert("repo:\(owner)/\(repo)")
                    if isMeaningfulProjectToken(repo) {
                        tokens.insert(repo)
                    }
                }
            }
        }

        if let title = span.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            // Split on common window title delimiters
            let delimiters = [" — ", " – ", " - ", " | ", " · "]
            var parts = [title]
            for delim in delimiters {
                parts = parts.flatMap { $0.components(separatedBy: delim) }
            }

            for rawPart in parts {
                let candidate = cleanProjectCandidate(rawPart)
                if isMeaningfulProjectToken(candidate) {
                    tokens.insert(candidate)
                }

                // Extract last directory component from file paths like ~/dev/code/focus-guard
                if rawPart.contains("/") {
                    let pathSegments = rawPart
                        .split(separator: "/")
                        .map { cleanProjectCandidate(String($0)) }
                        .filter { !$0.isEmpty }
                    if let last = pathSegments.last {
                        if last.contains("."), pathSegments.count >= 2 {
                            let parent = pathSegments[pathSegments.count - 2]
                            if isMeaningfulProjectToken(parent) {
                                tokens.insert(parent)
                            }
                        } else if isMeaningfulProjectToken(last) {
                            tokens.insert(last)
                        }
                    }
                }
            }
        }

        return tokens
    }

    // MARK: - App & Workflow Role Classification

    public static func role(for span: EnrichedSpan) -> AppRole {
        cachedFeatures(for: span).role
    }

    private static func computeRole(for span: EnrichedSpan) -> AppRole {
        let bundle = span.bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let app = span.appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = span.windowTitle?.lowercased() ?? ""
        let urlString = span.url?.lowercased() ?? ""
        let domain = registrableDomain(from: span.url) ?? ""

        // 1. Auxiliary tools (helpers serving whichever primary task is active)
        if matchesAnyPrefix(bundle, prefixes: auxiliaryBundlePrefixes) || matchesAnyExactOrPrefix(app, keywords: auxiliaryAppNames) {
            return .auxiliary
        }

        // 2. Interrupt / communication / entertainment
        if matchesAnyPrefix(bundle, prefixes: interruptBundlePrefixes) || matchesAnyExactOrPrefix(app, keywords: interruptAppNames) {
            return .interrupt
        }
        if ActivityClassifier.isBrowser(appName: span.appName, bundleId: span.bundleId) {
            if interruptDomains.contains(domain) || interruptDomainFragments.contains(where: { urlString.contains($0) }) {
                return .interrupt
            }
            if urlString.isEmpty && interruptTitleHints.contains(where: { title.contains($0) }) {
                return .interrupt
            }
        }

        // 3. Workflow clusters
        if matchesAnyPrefix(bundle, prefixes: engineeringBundlePrefixes) || matchesAnyExactOrPrefix(app, keywords: engineeringAppNames) {
            return .workflowCluster(.engineering)
        }
        if matchesAnyPrefix(bundle, prefixes: designBundlePrefixes) || matchesAnyExactOrPrefix(app, keywords: designAppNames) {
            return .workflowCluster(.designAndCommerce)
        }
        if matchesAnyPrefix(bundle, prefixes: researchBundlePrefixes) || matchesAnyExactOrPrefix(app, keywords: researchAppNames) {
            return .workflowCluster(.researchAndWriting)
        }

        if ActivityClassifier.isBrowser(appName: span.appName, bundleId: span.bundleId) {
            if isEngineeringBrowserContext(domain: domain, urlString: urlString, title: title) {
                return .workflowCluster(.engineering)
            }
            if designCommerceDomains.contains(domain) {
                return .workflowCluster(.designAndCommerce)
            }
            if researchDomains.contains(domain) || urlString.contains("feishu.cn/docx") || urlString.contains("feishu.cn/wiki") {
                return .workflowCluster(.researchAndWriting)
            }
        }

        return .general
    }

    // MARK: - Task Budget Matching

    public struct NormalizedBudget: Sendable {
        public let taskId: String
        public let appBundleIds: [String]
        public let domains: [String]
        public let keywords: [String]

        public init(budget: TaskBudget) {
            self.taskId = budget.taskId
            self.appBundleIds = budget.appBundleIds
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            self.domains = budget.domains
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            self.keywords = budget.keywords
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        }
    }

    public static func matchesBudget(span: EnrichedSpan, budget: TaskBudget) -> Bool {
        matchesBudget(
            appName: span.appName,
            bundleId: span.bundleId,
            windowTitle: span.windowTitle,
            url: span.url,
            redacted: span.redacted,
            normalizedBudget: NormalizedBudget(budget: budget)
        )
    }

    public static func matchesBudget(sample: ActivitySample, budget: TaskBudget) -> Bool {
        matchesBudget(
            appName: sample.appName,
            bundleId: sample.bundleId,
            windowTitle: sample.windowTitle,
            url: sample.url,
            redacted: sample.redacted,
            normalizedBudget: NormalizedBudget(budget: budget)
        )
    }

    public static func matchesBudget(
        appName: String,
        bundleId: String?,
        windowTitle: String?,
        url: String?,
        redacted: Bool,
        budget: TaskBudget
    ) -> Bool {
        matchesBudget(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            url: url,
            redacted: redacted,
            normalizedBudget: NormalizedBudget(budget: budget)
        )
    }

    public static func matchesBudget(span: EnrichedSpan, normalizedBudget: NormalizedBudget) -> Bool {
        matchesBudget(
            appName: span.appName,
            bundleId: span.bundleId,
            windowTitle: span.windowTitle,
            url: span.url,
            redacted: span.redacted,
            normalizedBudget: normalizedBudget
        )
    }

    public static func matchesBudget(
        appName: String,
        bundleId: String?,
        windowTitle: String?,
        url: String?,
        redacted: Bool,
        normalizedBudget: NormalizedBudget
    ) -> Bool {
        if !normalizedBudget.appBundleIds.isEmpty,
           let bundle = bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !bundle.isEmpty {
            for norm in normalizedBudget.appBundleIds {
                if bundle == norm || bundle.hasPrefix(norm + ".") {
                    return true
                }
            }
        }

        guard !redacted else { return false }

        if !normalizedBudget.domains.isEmpty,
           let rawURL = url,
           !rawURL.isEmpty,
           let host = URLComponents(string: rawURL)?.host?.lowercased(),
           !host.isEmpty {
            for norm in normalizedBudget.domains {
                if host == norm || host.hasSuffix("." + norm) {
                    return true
                }
            }
        }

        guard !normalizedBudget.keywords.isEmpty else { return false }

        let searchable = [windowTitle, url, appName]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        guard !searchable.isEmpty else { return false }

        for trimmed in normalizedBudget.keywords {
            if searchable.range(of: trimmed, options: .literal) != nil {
                return true
            }
        }
        return false
    }

    public static func inferredTaskId(for span: EnrichedSpan, budgets: [TaskBudget]) -> String? {
        inferredTaskId(for: span, normalizedBudgets: budgets.map(NormalizedBudget.init))
    }

    public static func inferredTaskId(for span: EnrichedSpan, normalizedBudgets: [NormalizedBudget]) -> String? {
        let features = cachedFeatures(for: span)
        for budget in normalizedBudgets where matchesBudget(features: features, redacted: span.redacted, normalizedBudget: budget) {
            return budget.taskId
        }
        return nil
    }

    internal static func inferredTaskId(for prepared: PreparedActivitySpan, normalizedBudgets: [NormalizedBudget]) -> String? {
        for budget in normalizedBudgets {
            if matchesBudget(
                bundleLower: prepared.bundleLower,
                urlHostLower: prepared.urlHostLower,
                searchableLower: prepared.searchableLower,
                redacted: prepared.span.redacted,
                normalizedBudget: budget
            ) {
                return budget.taskId
            }
        }
        return nil
    }

    private static func matchesBudget(
        features: CachedSpanFeatures,
        redacted: Bool,
        normalizedBudget: NormalizedBudget
    ) -> Bool {
        matchesBudget(
            bundleLower: features.bundleLower,
            urlHostLower: features.urlHostLower,
            searchableLower: features.searchableLower,
            redacted: redacted,
            normalizedBudget: normalizedBudget
        )
    }

    private static func matchesBudget(
        bundleLower: String,
        urlHostLower: String?,
        searchableLower: String,
        redacted: Bool,
        normalizedBudget: NormalizedBudget
    ) -> Bool {
        if !normalizedBudget.appBundleIds.isEmpty, !bundleLower.isEmpty {
            for norm in normalizedBudget.appBundleIds {
                if bundleLower == norm || bundleLower.hasPrefix(norm + ".") {
                    return true
                }
            }
        }

        guard !redacted else { return false }

        if !normalizedBudget.domains.isEmpty, let host = urlHostLower, !host.isEmpty {
            for norm in normalizedBudget.domains {
                if host == norm || host.hasSuffix("." + norm) {
                    return true
                }
            }
        }

        guard !normalizedBudget.keywords.isEmpty, !searchableLower.isEmpty else { return false }

        for trimmed in normalizedBudget.keywords {
            if utf8Contains(searchableLower, trimmed) {
                return true
            }
        }
        return false
    }

    private static func utf8Contains(_ haystack: String, _ needle: String) -> Bool {
        if needle.isEmpty { return true }
        if haystack.isEmpty { return false }
        if let result = haystack.utf8.withContiguousStorageIfAvailable({ hBuf -> Bool? in
            needle.utf8.withContiguousStorageIfAvailable { nBuf -> Bool in
                let hCount = hBuf.count
                let nCount = nBuf.count
                if nCount > hCount { return false }
                let first = nBuf[0]
                if nCount == 1 {
                    for i in 0..<hCount where hBuf[i] == first {
                        return true
                    }
                    return false
                }
                let limit = hCount - nCount
                for i in 0...limit {
                    if hBuf[i] == first {
                        var match = true
                        for j in 1..<nCount where hBuf[i + j] != nBuf[j] {
                            match = false
                            break
                        }
                        if match { return true }
                    }
                }
                return false
            }
        }), let matched = result {
            return matched
        }
        return haystack.range(of: needle, options: .literal) != nil
    }

    // MARK: - Sequence Preparation (Debouncing + Auxiliary Bridging + Coalescing)

    internal final class IncrementalSequenceState: @unchecked Sendable {
        var stableSortedCount: Int = 0
        var nonTransientLast: PreparedActivitySpan?
        var coalescedStable: [PreparedActivitySpan] = []
        var coalescedLast: PreparedActivitySpan?
    }

    public static func prepareSequence(
        spans: [EnrichedSpan],
        minEffectiveDwellSeconds: TimeInterval = defaultMinEffectiveDwellSeconds,
        bridgeGapSeconds: TimeInterval = defaultBridgeGapSeconds
    ) -> [PreparedActivitySpan] {
        let state = IncrementalSequenceState()
        let tail = prepareSequenceIncremental(
            sortedSpans: sortedByStart(spans),
            state: state,
            minEffectiveDwellSeconds: minEffectiveDwellSeconds,
            bridgeGapSeconds: bridgeGapSeconds
        )
        var result = state.coalescedStable
        result.append(contentsOf: tail)
        return result
    }

    /// Updates `state.coalescedStable` in-place for the immutable prefix `0..<(sorted.count - 1)`
    /// and returns only the mutable tail `PreparedActivitySpan` items after `state.coalescedStable`.
    internal static func prepareSequenceIncremental(
        sortedSpans sorted: [EnrichedSpan],
        state: IncrementalSequenceState,
        minEffectiveDwellSeconds: TimeInterval = defaultMinEffectiveDwellSeconds,
        bridgeGapSeconds: TimeInterval = defaultBridgeGapSeconds
    ) -> [PreparedActivitySpan] {
        guard !sorted.isEmpty else {
            state.stableSortedCount = 0
            state.nonTransientLast = nil
            state.coalescedStable.removeAll(keepingCapacity: true)
            state.coalescedLast = nil
            return []
        }

        let startIndex: Int
        var nonTransient: [PreparedActivitySpan] = []
        var coalescedTail: [PreparedActivitySpan] = []

        if state.stableSortedCount >= 2, sorted.count >= state.stableSortedCount {
            startIndex = state.stableSortedCount - 1
            if let ntLast = state.nonTransientLast {
                nonTransient.append(ntLast)
            }
            if let cLast = state.coalescedLast {
                coalescedTail.append(cLast)
            }
        } else {
            startIndex = 0
            state.stableSortedCount = 0
            state.nonTransientLast = nil
            state.coalescedStable.removeAll(keepingCapacity: true)
            state.coalescedLast = nil
            nonTransient.reserveCapacity(sorted.count)
        }

        var keptIndices: [Int] = []
        var keptDwells: [TimeInterval] = []
        keptIndices.reserveCapacity(sorted.count - startIndex)
        keptDwells.reserveCapacity(sorted.count - startIndex)

        for i in startIndex..<sorted.count {
            let curr = sorted[i]
            let isLast = (i == sorted.count - 1)
            let effectiveDwell: TimeInterval
            if isLast {
                effectiveDwell = max(1.0, curr.durationSeconds)
            } else {
                let next = sorted[i + 1]
                let gap = next.startedAt.timeIntervalSince(curr.endedAt)
                if gap >= 0 && gap <= bridgeGapSeconds {
                    effectiveDwell = max(curr.durationSeconds, next.startedAt.timeIntervalSince(curr.startedAt))
                } else {
                    effectiveDwell = curr.durationSeconds
                }
            }
            if !isLast && effectiveDwell < minEffectiveDwellSeconds {
                continue
            }
            keptIndices.append(i)
            keptDwells.append(effectiveDwell)
        }

        let keptSpans = keptIndices.map { sorted[$0] }
        let featuresList = cachedFeaturesBatch(for: keptSpans)

        let nextStableSortedCount = sorted.count - 1
        var didAdvanceCheckpoint = false

        func advanceCheckpointIfNeeded(beforeSortedIndex i: Int) {
            guard !didAdvanceCheckpoint,
                  nextStableSortedCount >= 2,
                  nextStableSortedCount > state.stableSortedCount,
                  i >= nextStableSortedCount - 1 else { return }
            didAdvanceCheckpoint = true
            if nonTransient.count > 1 {
                for j in 0..<(nonTransient.count - 1) {
                    appendToCoalesced(nonTransient[j], bridgeGapSeconds: bridgeGapSeconds, coalesced: &coalescedTail)
                }
                nonTransient.removeFirst(nonTransient.count - 1)
            }
            state.nonTransientLast = nonTransient.last
            if coalescedTail.count > 1 {
                state.coalescedStable.append(contentsOf: coalescedTail.dropLast())
                coalescedTail = [coalescedTail.last!]
            }
            state.coalescedLast = coalescedTail.last
            state.stableSortedCount = nextStableSortedCount
        }

        for k in 0..<keptIndices.count {
            let i = keptIndices[k]
            advanceCheckpointIfNeeded(beforeSortedIndex: i)

            let curr = keptSpans[k]
            let effectiveDwell = keptDwells[k]
            let features = featuresList[k]

            if features.role == .auxiliary {
                if let lastIdx = nonTransient.indices.last {
                    let prev = nonTransient[lastIdx]
                    let gap = curr.startedAt.timeIntervalSince(prev.span.endedAt)
                    if gap >= 0 && gap <= bridgeGapSeconds {
                        let bridgedEnd = max(prev.span.endedAt, curr.endedAt)
                        let bridgedSpan = EnrichedSpan(
                            startedAt: prev.span.startedAt,
                            endedAt: bridgedEnd,
                            appName: prev.span.appName,
                            bundleId: prev.span.bundleId,
                            windowTitle: prev.span.windowTitle,
                            url: prev.span.url,
                            declaredTaskId: prev.span.declaredTaskId,
                            redacted: prev.span.redacted,
                            semanticGroup: prev.span.semanticGroup
                        )
                        nonTransient[lastIdx] = PreparedActivitySpan(
                            span: bridgedSpan,
                            effectiveDwellSeconds: prev.effectiveDwellSeconds + effectiveDwell,
                            features: CachedSpanFeatures(
                                role: prev.role,
                                contextKey: prev.contextKey,
                                projectTokens: prev.projectTokens,
                                appKey: prev.appKey,
                                bundleLower: prev.bundleLower,
                                isBrowser: prev.isBrowser,
                                urlHostLower: prev.urlHostLower,
                                registrableDomain: prev.registrableDomain,
                                searchableLower: prev.searchableLower
                            )
                        )
                    }
                }
                continue
            }

            nonTransient.append(
                PreparedActivitySpan(
                    span: curr,
                    effectiveDwellSeconds: effectiveDwell,
                    features: features
                )
            )
        }

        advanceCheckpointIfNeeded(beforeSortedIndex: sorted.count - 1)

        for item in nonTransient {
            appendToCoalesced(item, bridgeGapSeconds: bridgeGapSeconds, coalesced: &coalescedTail)
        }

        return coalescedTail
    }

    private static func sortedByStart(_ spans: [EnrichedSpan]) -> [EnrichedSpan] {
        guard spans.count > 1 else { return spans }
        for i in 1..<spans.count where spans[i].startedAt < spans[i - 1].startedAt {
            return spans.sorted { $0.startedAt < $1.startedAt }
        }
        return spans
    }

    private static func appendToCoalesced(
        _ item: PreparedActivitySpan,
        bridgeGapSeconds: TimeInterval,
        coalesced: inout [PreparedActivitySpan]
    ) {
        if let last = coalesced.last,
           last.contextKey == item.contextKey,
           last.span.declaredTaskId == item.span.declaredTaskId,
           item.span.startedAt.timeIntervalSince(last.span.endedAt) <= bridgeGapSeconds {
            let resolvedURL = last.span.url ?? item.span.url
            let mergedSpan = EnrichedSpan(
                startedAt: last.span.startedAt,
                endedAt: max(last.span.endedAt, item.span.endedAt),
                appName: last.span.appName,
                bundleId: last.span.bundleId,
                windowTitle: last.span.windowTitle,
                url: resolvedURL,
                declaredTaskId: last.span.declaredTaskId,
                redacted: last.span.redacted && item.span.redacted,
                semanticGroup: last.span.semanticGroup ?? item.span.semanticGroup
            )
            coalesced[coalesced.count - 1] = PreparedActivitySpan(
                span: mergedSpan,
                effectiveDwellSeconds: last.effectiveDwellSeconds + item.effectiveDwellSeconds,
                features: CachedSpanFeatures(
                    role: last.role,
                    contextKey: last.contextKey,
                    projectTokens: last.projectTokens.isEmpty ? item.projectTokens : last.projectTokens,
                    appKey: last.appKey,
                    bundleLower: last.bundleLower,
                    isBrowser: last.isBrowser,
                    urlHostLower: last.urlHostLower ?? item.urlHostLower,
                    registrableDomain: last.registrableDomain ?? item.registrableDomain,
                    searchableLower: last.searchableLower
                )
            )
        } else {
            coalesced.append(item)
        }
    }

    // MARK: - Cross-Task Switch Decision

    public static func isCrossTaskSwitch(
        from lhs: PreparedActivitySpan,
        to rhs: PreparedActivitySpan,
        budgets: [TaskBudget]
    ) -> Bool {
        isCrossTaskSwitch(
            from: lhs,
            to: rhs,
            normalizedBudgets: budgets.map(NormalizedBudget.init)
        )
    }

    public static func isCrossTaskSwitch(
        from lhs: PreparedActivitySpan,
        to rhs: PreparedActivitySpan,
        normalizedBudgets: [NormalizedBudget],
        lhsTokens: (() -> Set<String>)? = nil,
        rhsTokens: (() -> Set<String>)? = nil,
        lhsTaskId: (() -> String?)? = nil,
        rhsTaskId: (() -> String?)? = nil
    ) -> Bool {
        // Identical canonical context is never a switch.
        if lhs.contextKey == rhs.contextKey {
            return false
        }

        // Level 0 (Semantic): When Jev semantic group is attached to both spans, trust semantic grouping.
        if let g1 = lhs.span.semanticGroup, !g1.isEmpty,
           let g2 = rhs.span.semanticGroup, !g2.isEmpty {
            if g1 == "break" || g2 == "break" {
                return true
            }
            return g1 != g2
        }

        // Any transition involving an interrupt app/site (IM, social, video) counts as a switch.
        if lhs.role == .interrupt || rhs.role == .interrupt {
            return true
        }

        let sameApp = lhs.appKey == rhs.appKey

        if sameApp {
            // Intra-app switches in native non-browser apps (e.g., switching files in IDE or tabs in Terminal)
            // are intra-app navigation, not cross-app task switching.
            if !lhs.isBrowser {
                return false
            }
            // In a browser, same registrable domain is intra-site work.
            if let d1 = lhs.registrableDomain,
               let d2 = rhs.registrableDomain,
               d1 == d2 {
                return false
            }
        }

        // Level 1: Shared project / workspace / repository anchor across apps.
        let resolvedLhsTokens = lhsTokens != nil ? lhsTokens!() : lhs.projectTokens
        if !resolvedLhsTokens.isEmpty {
            let resolvedRhsTokens = rhsTokens != nil ? rhsTokens!() : rhs.projectTokens
            if !resolvedLhsTokens.isDisjoint(with: resolvedRhsTokens) {
                return false
            }
        }

        // Level 2: Both belong to the same configured TaskBudget.
        if !normalizedBudgets.isEmpty {
            let t1 = lhsTaskId != nil ? lhsTaskId!() : inferredTaskId(for: lhs, normalizedBudgets: normalizedBudgets)
            if let t1 {
                let t2 = rhsTaskId != nil ? rhsTaskId!() : inferredTaskId(for: rhs, normalizedBudgets: normalizedBudgets)
                if t1 == t2 {
                    return false
                }
            }
        }

        // Level 3: Same workflow cluster (e.g., IDE <-> Terminal <-> Dev Docs Browser).
        if case .workflowCluster(let c1) = lhs.role,
           case .workflowCluster(let c2) = rhs.role,
           c1 == c2 {
            return false
        }

        return true
    }

    public static func isInterruptTransition(from lhs: PreparedActivitySpan, to rhs: PreparedActivitySpan) -> Bool {
        if lhs.span.semanticGroup == "break" || rhs.span.semanticGroup == "break" {
            return true
        }
        if let g1 = lhs.span.semanticGroup, !g1.isEmpty,
           let g2 = rhs.span.semanticGroup, !g2.isEmpty,
           g1 == g2 {
            return false
        }
        return lhs.role == .interrupt || rhs.role == .interrupt
    }

    // MARK: - Private Helpers & Static Dictionaries

    private static let bracketCounterRegex = try! NSRegularExpression(
        pattern: #"[\(\[]\s*\d{1,4}\s*\+?\s*[\)\]]"#,
        options: [.caseInsensitive]
    )
    private static let cjkBracketCounterRegex = try! NSRegularExpression(
        pattern: #"[（【]\s*\d{1,4}\s*\+?\s*[）】]"#,
        options: [.caseInsensitive]
    )
    private static let clockRegex = try! NSRegularExpression(
        pattern: #"\b\d{1,2}:\d{2}(?::\d{2})?\b"#,
        options: [.caseInsensitive]
    )
    private static let percentRegex = try! NSRegularExpression(
        pattern: #"\b\d{1,3}(?:\.\d+)?\s*%"#,
        options: [.caseInsensitive]
    )
    private static let separatorRegex = try! NSRegularExpression(
        pattern: #"[•·|–—]+"#,
        options: [.caseInsensitive]
    )
    private static let candidateTagRegex = try! NSRegularExpression(
        pattern: #"[\(\[]\s*(?:beta|preview|dev|modified|edited|\d+)\s*[\)\]]"#,
        options: [.caseInsensitive]
    )
    private static let syntheticLabelRegex = try! NSRegularExpression(
        pattern: #"^(?:tab|switch|window|slide|page|item|untitled|synthetic tab)\s*\d+$"#,
        options: [.caseInsensitive]
    )
    private static let trimCharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)

    internal static func normalizedAppKey(appName: String, bundleId: String?) -> String {
        if let bundle = bundleId?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !bundle.isEmpty {
            return bundle
        }
        return appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func cleanProjectCandidate(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = replace(candidateTagRegex, in: text)
        text = text.trimmingCharacters(in: trimCharacterSet)
        return text
    }

    private static func isMeaningfulProjectToken(_ token: String) -> Bool {
        guard token.count >= 3 else { return false }
        if genericProjectNoise.contains(token) { return false }
        if token.allSatisfy(\.isNumber) { return false }
        // Reject synthetic or generic numbered labels like "tab 0", "switch 1", "window 2"
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        if syntheticLabelRegex.firstMatch(in: token, options: [], range: range) != nil {
            return false
        }
        return true
    }

    private static func matchesAnyPrefix(_ value: String, prefixes: [String]) -> Bool {
        guard !value.isEmpty else { return false }
        return prefixes.contains { value == $0 || value.hasPrefix($0 + ".") }
    }

    private static func matchesAnyExactOrPrefix(_ value: String, keywords: [String]) -> Bool {
        guard !value.isEmpty else { return false }
        return keywords.contains { value == $0 || value.contains($0) }
    }

    private static func isEngineeringBrowserContext(domain: String, urlString: String, title: String) -> Bool {
        if domain.hasPrefix("localhost") || domain.hasPrefix("127.0.0.1") || domain.hasPrefix("::1") {
            return true
        }
        if engineeringDomains.contains(domain) || domain.hasPrefix("docs.") {
            return true
        }
        if !urlString.isEmpty {
            return false
        }
        return engineeringTitleHints.contains { title.contains($0) }
    }

    private static func replace(_ regex: NSRegularExpression, in text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: " ")
    }

    private static let auxiliaryBundlePrefixes: [String] = [
        "com.apple.finder",
        "com.apple.preview",
        "com.apple.spotlight",
        "com.raycast.macos",
        "com.runningwithcrayons.alfred",
        "com.1password",
        "com.apple.keychainaccess",
        "org.bitwarden",
        "com.lastpass",
        "com.apple.screenshot.launcher",
        "com.cleanshot",
        "com.xnipapp",
        "eu.exelban.stats",
        "com.dayhelm",
        "org.p0deje.maccy",
        "com.pilotmoon.popclip",
        "com.apple.digitalcolormeter"
    ]

    private static let auxiliaryAppNames: [String] = [
        "finder", "访达", "preview", "预览", "raycast", "alfred", "spotlight",
        "1password", "keychain access", "cleanshot", "xnip", "maccy", "dayhelm", "stats"
    ]

    private static let interruptBundlePrefixes: [String] = [
        "com.tencent.xinwechat",
        "com.tencent.qq",
        "com.electron.lark",
        "com.bytedance.feishu",
        "com.tinyspeck.slackmacgap",
        "com.hnc.discord",
        "ru.keepcoder.telegram",
        "com.alibaba.dingtalkmac",
        "com.apple.mobilesms",
        "net.whatsapp.whatsapp"
    ]

    private static let interruptAppNames: [String] = [
        "wechat", "微信", "feishu", "飞书", "lark", "slack", "discord",
        "telegram", "dingtalk", "钉钉", "messages", "信息", "whatsapp"
    ]

    private static let interruptDomains: Set<String> = [
        "bilibili.com", "youtube.com", "youtu.be", "weibo.com", "xiaohongshu.com",
        "douyin.com", "tiktok.com", "x.com", "twitter.com", "reddit.com",
        "netflix.com", "twitch.tv", "douyu.com", "huya.com", "zhihu.com"
    ]

    private static let interruptDomainFragments: [String] = [
        "web.wechat.com", "wx.qq.com", "app.slack.com", "discord.com/channels", "web.whatsapp.com"
    ]

    private static let interruptTitleHints: [String] = [
        "bilibili", "youtube", "weibo", "微博", "小红书", "抖音"
    ]

    private static let engineeringBundlePrefixes: [String] = [
        "com.apple.dt.xcode",
        "com.microsoft.vscode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "dev.zed.zed",
        "com.jetbrains",
        "com.sublimetext",
        "com.panic.nova",
        "com.apple.terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.warp-stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "co.zeit.hyper",
        "com.postmanlabs.mac",
        "com.konghq.insomnia",
        "com.usebruno.app",
        "com.proxyman",
        "com.tinyapp.tableplus",
        "com.docker.docker",
        "dev.kdrag0n.orbstack",
        "com.github.githubclient",
        "com.danpristupov.fork",
        "com.fournova.tower"
    ]

    private static let engineeringAppNames: [String] = [
        "xcode", "cursor", "visual studio code", "vs code", "vscode", "t3 code",
        "zed", "windsurf", "trae", "sublime text", "terminal", "终端",
        "iterm", "iterm2", "ghostty", "warp", "kitty", "alacritty",
        "postman", "insomnia", "bruno", "proxyman", "tableplus", "orbstack",
        "github desktop", "fork", "sourcetree"
    ]

    private static let engineeringDomains: Set<String> = [
        "github.com", "gitlab.com", "bitbucket.org", "stackoverflow.com",
        "developer.apple.com", "developer.mozilla.org", "swift.org",
        "npmjs.com", "pypi.org", "crates.io", "vercel.com", "cloudflare.com",
        "aws.amazon.com", "linear.app", "sentry.io", "grafana.com",
        "claude.ai", "chatgpt.com", "openai.com", "typesafe.ai", "gemini.google.com"
    ]

    private static let engineeringTitleHints: [String] = [
        "localhost", "127.0.0.1", "github", "gitlab", "pull request",
        "stack overflow", "documentation", "api reference"
    ]

    private static let designBundlePrefixes: [String] = [
        "com.figma.desktop",
        "com.bohemiancoding.sketch3",
        "com.adobe.photoshop",
        "com.adobe.illustrator",
        "com.seriflabs.affinityphoto",
        "com.seriflabs.affinitydesigner",
        "com.pixelmatorteam.pixelmator",
        "com.canva.canvadesktop"
    ]

    private static let designAppNames: [String] = [
        "figma", "sketch", "photoshop", "illustrator", "affinity", "pixelmator", "canva"
    ]

    private static let designCommerceDomains: Set<String> = [
        "figma.com", "canva.com", "jinritemai.com", "1688.com", "taobao.com",
        "tmall.com", "jd.com", "pinduoduo.com", "shopify.com"
    ]

    private static let researchBundlePrefixes: [String] = [
        "md.obsidian",
        "notion.id",
        "net.shinyfrog.bear",
        "abnerworks.typora",
        "com.lukilabs.lukiapp", // Craft
        "com.electron.logseq",
        "com.microsoft.word",
        "com.microsoft.excel",
        "com.apple.iwork.pages",
        "com.apple.iwork.numbers",
        "com.apple.ibooksx",
        "com.readdle.pdfexpert",
        "org.zotero.zotero"
    ]

    private static let researchAppNames: [String] = [
        "obsidian", "notion", "bear", "typora", "craft", "logseq",
        "microsoft word", "microsoft excel", "pages", "numbers",
        "books", "图书", "pdf expert", "zotero"
    ]

    private static let researchDomains: Set<String> = [
        "notion.so", "docs.google.com", "arxiv.org", "scholar.google.com",
        "wikipedia.org", "ssrn.com", "google.com", "perplexity.ai", "doubao.com"
    ]

    private static let genericProjectNoise: Set<String> = [
        "google chrome", "chrome", "safari", "arc", "dia", "dia browser", "firefox", "microsoft edge",
        "t3 code", "t3 code beta", "cursor", "visual studio code", "vs code", "xcode", "zed",
        "terminal", "iterm", "iterm2", "ghostty", "warp", "zsh", "bash", "fish", "sh",
        "finder", "preview", "figma", "notion", "obsidian", "dayhelm",
        "new tab", "新标签页", "untitled", "settings", "preferences", "loading", "home",
        "dashboard", "inbox", "tab", "window", "switch", "beta", "main", "work", "workspace"
    ]
}
