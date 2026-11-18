import DayHelmCore
import Foundation

public protocol AlmaHTTPTransport: Sendable {
    func data(from url: URL) async throws -> (Data, URLResponse)
}

public final class URLSessionAlmaTransport: AlmaHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(timeoutInterval: TimeInterval = 2.0) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeoutInterval
        config.timeoutIntervalForResource = timeoutInterval + 1.0
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    public func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session.data(from: url)
    }
}

public struct AlmaEventData: Sendable, Equatable, Decodable {
    public let bundleId: String?
    public let url: String?
    public let title: String?
    public let windowTitle: String?
    public let tabTitle: String?
    public let appName: String?

    public init(
        bundleId: String? = nil,
        url: String? = nil,
        title: String? = nil,
        windowTitle: String? = nil,
        tabTitle: String? = nil,
        appName: String? = nil
    ) {
        self.bundleId = bundleId
        self.url = url
        self.title = title
        self.windowTitle = windowTitle
        self.tabTitle = tabTitle
        self.appName = appName
    }
}

public struct AlmaEvent: Sendable, Equatable, Decodable {
    public let id: String
    public let timestampMs: Int64
    public let kind: String
    public let appName: String?
    public let data: AlmaEventData?

    enum CodingKeys: String, CodingKey {
        case id, timestamp, kind, appName, data
    }

    public init(
        id: String,
        timestampMs: Int64,
        kind: String,
        appName: String? = nil,
        data: AlmaEventData? = nil
    ) {
        self.id = id
        self.timestampMs = timestampMs
        self.kind = kind
        self.appName = appName
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        if let intVal = try? container.decode(Int64.self, forKey: .timestamp) {
            self.timestampMs = intVal
        } else {
            let doubleVal = try container.decode(Double.self, forKey: .timestamp)
            self.timestampMs = Int64(doubleVal)
        }
        self.kind = try container.decode(String.self, forKey: .kind)
        self.appName = try container.decodeIfPresent(String.self, forKey: .appName)
        self.data = try container.decodeIfPresent(AlmaEventData.self, forKey: .data)
    }
}

public struct AlmaSession: Sendable, Equatable, Decodable {
    public let id: String
    public let startedAtMs: Int64
    public let endedAtMs: Int64?
    public let durationMs: Int64?
    public let appNames: [String]?
    public let events: [AlmaEvent]?

    enum CodingKeys: String, CodingKey {
        case id, startedAt, endedAt, durationMs, appNames, events
    }

    public init(
        id: String,
        startedAtMs: Int64,
        endedAtMs: Int64? = nil,
        durationMs: Int64? = nil,
        appNames: [String]? = nil,
        events: [AlmaEvent]? = nil
    ) {
        self.id = id
        self.startedAtMs = startedAtMs
        self.endedAtMs = endedAtMs
        self.durationMs = durationMs
        self.appNames = appNames
        self.events = events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.startedAtMs = Self.decodeMs(container: container, key: .startedAt) ?? 0
        self.endedAtMs = Self.decodeMs(container: container, key: .endedAt)
        self.durationMs = Self.decodeMs(container: container, key: .durationMs)
        self.appNames = try container.decodeIfPresent([String].self, forKey: .appNames)
        self.events = try container.decodeIfPresent([AlmaEvent].self, forKey: .events)
    }

    private static func decodeMs(container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int64? {
        if let intVal = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return intVal
        }
        if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int64(doubleVal)
        }
        return nil
    }
}

public struct AlmaSyncResult: Sendable, Equatable {
    public let samples: [ActivitySample]
    public let latestEventTimestampMs: Int64?
    public let connected: Bool

    public init(samples: [ActivitySample], latestEventTimestampMs: Int64?, connected: Bool) {
        self.samples = samples
        self.latestEventTimestampMs = latestEventTimestampMs
        self.connected = connected
    }
}

public final class AlmaActivityClient: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "http://localhost:23001")!

    public let baseURL: URL
    private let transport: any AlmaHTTPTransport
    private let decoder = JSONDecoder()
    private let cacheLock = NSLock()
    private var endedSessionEventsCache: [String: [AlmaEvent]] = [:]
    private var endedSessionOrder: [String] = []
    private let maxCachedEndedSessions = 64

    public init(
        baseURL: URL = AlmaActivityClient.defaultBaseURL,
        transport: any AlmaHTTPTransport = URLSessionAlmaTransport()
    ) {
        self.baseURL = baseURL
        self.transport = transport
    }

    private struct SessionsWrapperDTO: Decodable {
        let sessions: [AlmaSession]?
        let data: [AlmaSession]?
    }

    private struct SessionDetailWrapperDTO: Decodable {
        let session: AlmaSession?
        let events: [AlmaEvent]?
    }

    public func fetchSessions(sinceMs: Int64, untilMs: Int64, limit: Int = 2000) async throws -> [AlmaSession] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/activity-recorder/sessions"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "since", value: String(sinceMs)),
            URLQueryItem(name: "until", value: String(untilMs))
        ]
        guard let url = components.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await transport.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        if let direct = try? decoder.decode([AlmaSession].self, from: data) {
            return direct
        }
        let wrapped = try decoder.decode(SessionsWrapperDTO.self, from: data)
        return wrapped.sessions ?? wrapped.data ?? []
    }

    public func fetchSessionEvents(sessionId: String) async throws -> [AlmaEvent] {
        let url = baseURL
            .appendingPathComponent("api/activity-recorder/sessions")
            .appendingPathComponent(sessionId)

        let (data, response) = try await transport.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        if let session = try? decoder.decode(AlmaSession.self, from: data), let events = session.events {
            return events
        }
        if let wrapped = try? decoder.decode(SessionDetailWrapperDTO.self, from: data) {
            if let events = wrapped.events {
                return events
            }
            if let events = wrapped.session?.events {
                return events
            }
        }
        if let events = try? decoder.decode([AlmaEvent].self, from: data) {
            return events
        }
        return []
    }

    public func fetchTodaySamples(
        dayStart: Date,
        dayEnd: Date,
        sinceEventMs: Int64? = nil,
        privacyConfig: PrivacyRedactorConfig = .default
    ) async -> AlmaSyncResult {
        let sinceMs = sinceEventMs ?? Int64(dayStart.timeIntervalSince1970 * 1000)
        let untilMs = Int64(dayEnd.timeIntervalSince1970 * 1000)

        do {
            let sessions = try await fetchSessions(sinceMs: sinceMs, untilMs: untilMs)
            var allEvents: [AlmaEvent] = []
            var fallbackSamples: [ActivitySample] = []

            for session in sessions {
                if let embedded = session.events {
                    allEvents.append(contentsOf: embedded)
                } else {
                    let cachedEvents: [AlmaEvent]?
                    if session.endedAtMs != nil {
                        cachedEvents = cacheLock.withLock { endedSessionEventsCache[session.id] }
                    } else {
                        cachedEvents = nil
                    }

                    if let cachedEvents {
                        allEvents.append(contentsOf: cachedEvents)
                    } else {
                        do {
                            let events = try await fetchSessionEvents(sessionId: session.id)
                            if session.endedAtMs != nil {
                                cacheLock.withLock {
                                    if endedSessionEventsCache[session.id] == nil {
                                        while endedSessionOrder.count >= maxCachedEndedSessions {
                                            let evicted = endedSessionOrder.removeFirst()
                                            endedSessionEventsCache.removeValue(forKey: evicted)
                                        }
                                        endedSessionOrder.append(session.id)
                                    }
                                    endedSessionEventsCache[session.id] = events
                                }
                            }
                            if events.isEmpty, let firstApp = session.appNames?.first, !firstApp.isEmpty {
                                let start = Date(timeIntervalSince1970: TimeInterval(session.startedAtMs) / 1000.0)
                                fallbackSamples.append(
                                    ActivitySample(
                                        timestamp: start,
                                        appName: firstApp,
                                    bundleId: nil,
                                    windowTitle: nil,
                                    url: nil,
                                    idleSeconds: 0,
                                    screenLocked: false,
                                    inputActive: true
                                )
                            )
                        } else {
                            allEvents.append(contentsOf: events)
                        }
                        } catch {
                            // Individual session detail failure shouldn't drop already fetched sessions
                            continue
                        }
                    }
                }
            }

            let filteredEvents = allEvents.filter { event in
                if let sinceEventMs, event.timestampMs <= sinceEventMs {
                    return false
                }
                return event.timestampMs >= Int64(dayStart.timeIntervalSince1970 * 1000)
                    && event.timestampMs <= untilMs
            }

            var samples = Self.convertToSamples(events: filteredEvents, privacyConfig: privacyConfig)
            if samples.isEmpty && !fallbackSamples.isEmpty {
                samples = fallbackSamples
                    .map { PrivacyRedactor.redact($0, config: privacyConfig) }
                    .sorted { $0.timestamp < $1.timestamp }
            }

            let latestMs = filteredEvents.map(\.timestampMs).max()
            return AlmaSyncResult(samples: samples, latestEventTimestampMs: latestMs, connected: true)
        } catch {
            return AlmaSyncResult(samples: [], latestEventTimestampMs: nil, connected: false)
        }
    }

    public static func convertToSamples(
        events: [AlmaEvent],
        privacyConfig: PrivacyRedactorConfig = .default
    ) -> [ActivitySample] {
        let sorted = events.sorted {
            if $0.timestampMs != $1.timestampMs {
                return $0.timestampMs < $1.timestampMs
            }
            return $0.id < $1.id
        }

        var currentAppName: String?
        var currentBundleId: String?
        var currentWindowTitle: String?
        var currentURL: String?

        var samples: [ActivitySample] = []
        samples.reserveCapacity(sorted.count)

        for event in sorted {
            let timestamp = Date(timeIntervalSince1970: TimeInterval(event.timestampMs) / 1000.0)

            switch event.kind {
            case "app_focus":
                let appName = nonEmpty(event.appName) ?? nonEmpty(event.data?.appName) ?? currentAppName ?? "Unknown"
                let bundleId = nonEmpty(event.data?.bundleId)
                let title = nonEmpty(event.data?.windowTitle) ?? nonEmpty(event.data?.title)
                let parsedURL = parseBrowserVisitURL(event.data?.url)
                let cleanURL = PrivacyRedactor.sanitizeURL(parsedURL.url)
                let effectiveTitle = title ?? parsedURL.tabTitle

                currentAppName = appName
                currentBundleId = bundleId
                currentWindowTitle = effectiveTitle
                currentURL = cleanURL

                let raw = ActivitySample(
                    timestamp: timestamp,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: effectiveTitle,
                    url: cleanURL,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
                samples.append(PrivacyRedactor.redact(raw, config: privacyConfig))

            case "browser_visit":
                let parsed = parseBrowserVisitURL(event.data?.url)
                let cleanURL = PrivacyRedactor.sanitizeURL(parsed.url)
                let appName = nonEmpty(event.appName) ?? nonEmpty(event.data?.appName) ?? currentAppName ?? "Browser"
                let bundleId = nonEmpty(event.data?.bundleId) ?? (appName == currentAppName ? currentBundleId : nil)
                let title = nonEmpty(event.data?.windowTitle)
                    ?? nonEmpty(event.data?.title)
                    ?? nonEmpty(event.data?.tabTitle)
                    ?? parsed.tabTitle

                currentAppName = appName
                currentBundleId = bundleId
                currentWindowTitle = title
                currentURL = cleanURL

                let raw = ActivitySample(
                    timestamp: timestamp,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: title,
                    url: cleanURL,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
                samples.append(PrivacyRedactor.redact(raw, config: privacyConfig))

            case "click", "keypress":
                let resolvedApp = nonEmpty(event.appName) ?? nonEmpty(event.data?.appName) ?? currentAppName
                guard let appName = resolvedApp else {
                    continue
                }
                let sameApp = (appName == currentAppName)
                let bundleId = nonEmpty(event.data?.bundleId) ?? (sameApp ? currentBundleId : nil)
                let title = nonEmpty(event.data?.windowTitle) ?? nonEmpty(event.data?.title) ?? (sameApp ? currentWindowTitle : nil)
                let url = nonEmpty(event.data?.url).flatMap { PrivacyRedactor.sanitizeURL(parseBrowserVisitURL($0).url) } ?? (sameApp ? currentURL : nil)

                currentAppName = appName
                currentBundleId = bundleId
                currentWindowTitle = title
                currentURL = url

                let raw = ActivitySample(
                    timestamp: timestamp,
                    appName: appName,
                    bundleId: bundleId,
                    windowTitle: title,
                    url: url,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
                samples.append(PrivacyRedactor.redact(raw, config: privacyConfig))

            case "unlock":
                let appName = nonEmpty(event.appName) ?? currentAppName ?? "loginwindow"
                let raw = ActivitySample(
                    timestamp: timestamp,
                    appName: appName,
                    bundleId: appName == currentAppName ? currentBundleId : nil,
                    windowTitle: nil,
                    url: nil,
                    idleSeconds: 0,
                    screenLocked: false,
                    inputActive: true
                )
                samples.append(PrivacyRedactor.redact(raw, config: privacyConfig))

            default:
                if let appName = nonEmpty(event.appName) ?? nonEmpty(event.data?.appName) {
                    let raw = ActivitySample(
                        timestamp: timestamp,
                        appName: appName,
                        bundleId: nonEmpty(event.data?.bundleId),
                        windowTitle: nonEmpty(event.data?.windowTitle) ?? nonEmpty(event.data?.title),
                        url: PrivacyRedactor.sanitizeURL(parseBrowserVisitURL(event.data?.url).url),
                        idleSeconds: 0,
                        screenLocked: false,
                        inputActive: true
                    )
                    samples.append(PrivacyRedactor.redact(raw, config: privacyConfig))
                }
            }
        }

        return samples
    }

    /// Parses Alma's `browser_visit` `data.url`, which occasionally concatenates `"tab<TabTitle>"` onto the URL.
    public static func parseBrowserVisitURL(_ rawURL: String?) -> (url: String?, tabTitle: String?) {
        guard let raw = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return (nil, nil)
        }

        // 1. Whitespace-delimited URL + "tab<TabTitle>" (e.g. "https://example.com/page\ntabTitle")
        if let wsIndex = raw.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " }) {
            let urlPart = String(raw[..<wsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(raw[wsIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.hasPrefix("tab"), remainder.count > 3 {
                let title = String(remainder.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                return (urlPart, title.isEmpty ? nil : title)
            }
        }

        // 2. Direct concatenation: "...tab<TabTitle>" (including when <TabTitle> itself contains spaces)
        if let schemeRange = raw.range(of: "://") {
            var searchStart = schemeRange.upperBound
            while let tabRange = raw.range(of: "tab", options: [], range: searchStart..<raw.endIndex) {
                let prefix = String(raw[..<tabRange.lowerBound])
                let suffix = String(raw[tabRange.upperBound...])

                if !prefix.contains(" ") && !prefix.contains("\n") && !prefix.contains("\t")
                    && isLikelyConcatenatedTabTitle(prefix: prefix, suffix: suffix) {
                    let title = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
                    return (prefix, title.isEmpty ? nil : title)
                }

                searchStart = tabRange.upperBound
            }
        }

        // 3. Fallback: plain whitespace-separated URL and title
        if let wsIndex = raw.firstIndex(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" || $0 == " " }) {
            let urlPart = String(raw[..<wsIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remainder = String(raw[wsIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (urlPart, remainder.isEmpty ? nil : remainder)
        }

        return (raw, nil)
    }

    private static func isLikelyConcatenatedTabTitle(prefix: String, suffix: String) -> Bool {
        guard !suffix.isEmpty else { return false }

        // Never split query parameters like ?tab=orders or &tab=1
        if prefix.hasSuffix("?") || prefix.hasSuffix("&") {
            return false
        }
        guard let firstScalar = suffix.unicodeScalars.first else {
            return false
        }
        // Never split normal URL continuations like =, &, /, ., -, _
        if ["=", "&", "/", ".", "-", "_", "#", "?"].contains(Character(firstScalar)) {
            return false
        }

        // If suffix contains spaces, it cannot be a valid unencoded URL continuation
        if suffix.contains(" ") {
            return true
        }

        // If suffix starts with uppercase ASCII, non-ASCII (e.g., CJK), or title bracket
        let isUppercaseASCII = firstScalar.value >= 65 && firstScalar.value <= 90
        let isNonASCII = !firstScalar.isASCII
        let isBracket = ["[", "【", "("].contains(Character(firstScalar))

        if (isUppercaseASCII || isNonASCII || isBracket), prefix.contains(".") {
            return true
        }

        return false
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
