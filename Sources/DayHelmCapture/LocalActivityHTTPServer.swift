import DayHelmCore
import Foundation
import Network

public struct LocalRecorderStatusSnapshot: Sendable, Codable {
    public let running: Bool
    public let recording: Bool
    public let source: String
    public let version: String
    public let ports: [UInt16]
    public let axTrusted: Bool
    public let screenCaptureTrusted: Bool
    public let deepRecordingEnabled: Bool
    public let activeSessionId: String?
    public let todaySessions: Int
    public let todayEvents: Int
    public let todaySnapshots: Int
    public let todayOCRFrames: Int

    public init(
        running: Bool,
        recording: Bool,
        source: String = "dayhelm",
        version: String = "0.1.0",
        ports: [UInt16],
        axTrusted: Bool,
        screenCaptureTrusted: Bool,
        deepRecordingEnabled: Bool,
        activeSessionId: String?,
        todaySessions: Int,
        todayEvents: Int,
        todaySnapshots: Int,
        todayOCRFrames: Int
    ) {
        self.running = running
        self.recording = recording
        self.source = source
        self.version = version
        self.ports = ports
        self.axTrusted = axTrusted
        self.screenCaptureTrusted = screenCaptureTrusted
        self.deepRecordingEnabled = deepRecordingEnabled
        self.activeSessionId = activeSessionId
        self.todaySessions = todaySessions
        self.todayEvents = todayEvents
        self.todaySnapshots = todaySnapshots
        self.todayOCRFrames = todayOCRFrames
    }
}

public struct DayHelmContextAPIResponse: Sendable, Codable {
    public let schemaVersion: Int
    public let date: String
    public let generatedAt: String
    public let focusState: FocusSessionState?
    public let activeFocus: ActiveFocusSnapshot?
    public let budgets: [BudgetSnapshot]
    public let metrics: DayMetrics
    public let activity: AgentActivityContext

    public init(
        schemaVersion: Int = 1,
        date: String,
        generatedAt: String,
        focusState: FocusSessionState?,
        activeFocus: ActiveFocusSnapshot?,
        budgets: [BudgetSnapshot],
        metrics: DayMetrics,
        activity: AgentActivityContext
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.generatedAt = generatedAt
        self.focusState = focusState
        self.activeFocus = activeFocus
        self.budgets = budgets
        self.metrics = metrics
        self.activity = activity
    }
}

private struct SessionsListAPIResponse: Codable {
    let sessions: [RecordedSessionSummary]
    let total: Int
}

private struct SessionEventsAPIResponse: Codable {
    let events: [RecordedActivityEvent]
    let total: Int
}

/// Alma's session detail shape: `{ session, events, snapshots, ocr }`. DayHelm keeps `ocrFrames` as well so
/// existing callers keep working, and adds `ocr` because Alma's own store uses that key name.
private struct SessionDetailAPIResponse: Codable {
    let session: RecordedSessionSummary
    let events: [RecordedActivityEvent]
    let snapshots: [RecordedSnapshot]
    let ocrFrames: [RecordedOCRFrame]
    let ocr: [OCRFrameCompatItem]
}

/// Alma OCR frame shape. `hasEmbedding` is always `false` because DayHelm runs no embedding model.
private struct OCRFrameCompatItem: Codable {
    let id: String
    let sessionId: String
    let snapshotId: String
    let text: String
    let charCount: Int
    let tokenCount: Int
    let hasEmbedding: Bool
    let createdAt: Int64

    init(frame: RecordedOCRFrame) {
        self.id = frame.id
        self.sessionId = frame.sessionId
        self.snapshotId = frame.snapshotId
        self.text = frame.text
        self.charCount = frame.charCount
        self.tokenCount = frame.tokenCount
        self.hasEmbedding = false
        self.createdAt = frame.createdAt
    }
}

private struct OCRKeywordSearchItem: Codable {
    let id: String
    let sessionId: String
    let snapshotId: String
    let text: String
    let createdAt: Int64
}

private struct OCRKeywordSearchAPIResponse: Codable {
    let results: [OCRKeywordSearchItem]
}

private struct DayHelmSearchAPIResponse: Codable {
    let keyword: String
    let total: Int
    let hits: [ActivitySearchHit]
}

private struct RoutedResponse {
    let statusCode: Int
    let body: Data
    let contentType: String

    init(statusCode: Int, body: Data, contentType: String = "application/json; charset=utf-8") {
        self.statusCode = statusCode
        self.body = body
        self.contentType = contentType
    }
}

private struct APIErrorResponse: Codable {
    let error: String
}

public final class LocalActivityHTTPServer: @unchecked Sendable {
    public static let defaultPrimaryPort: UInt16 = 24001
    public static let defaultPortCandidates: [UInt16] = Array(24001...24009)
    public static let almaReservedPort: UInt16 = 23001

    public struct RuntimeState: Sendable {
        public var axTrusted: Bool
        public var screenCaptureTrusted: Bool
        public var deepRecordingEnabled: Bool
        public var daySnapshot: DayHelmDaySnapshot?

        public init(
            axTrusted: Bool = false,
            screenCaptureTrusted: Bool = false,
            deepRecordingEnabled: Bool = true,
            daySnapshot: DayHelmDaySnapshot? = nil
        ) {
            self.axTrusted = axTrusted
            self.screenCaptureTrusted = screenCaptureTrusted
            self.deepRecordingEnabled = deepRecordingEnabled
            self.daySnapshot = daySnapshot
        }
    }

    private let database: ActivityDatabase
    private let store: DayHelmStore?
    private let clock: any DayHelmClock
    private let stateProvider: @Sendable () -> RuntimeState
    private let queue = DispatchQueue(label: "com.dayhelm.http-server", qos: .utility)

    private let lock = NSLock()
    private var listeners: [(requestedPort: UInt16, listener: NWListener, boundPort: UInt16?)] = []
    private let encoder: JSONEncoder

    public init(
        database: ActivityDatabase,
        store: DayHelmStore? = nil,
        clock: any DayHelmClock = SystemClock(),
        stateProvider: @escaping @Sendable () -> RuntimeState = { RuntimeState() }
    ) {
        self.database = database
        self.store = store
        self.clock = clock
        self.stateProvider = stateProvider
        let enc = DayHelmDateFormatting.makeEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = enc
    }

    deinit {
        stop()
    }

    public var activePorts: [UInt16] {
        lock.lock()
        defer { lock.unlock() }
        return listeners.compactMap(\.boundPort)
    }

    public func isServingPort(_ port: UInt16) -> Bool {
        activePorts.contains(port)
    }

    @discardableResult
    public func start(
        primaryPort: UInt16 = LocalActivityHTTPServer.defaultPrimaryPort,
        fallbackPort: UInt16? = nil
    ) async -> [UInt16] {
        stop()

        let candidates: [UInt16]
        if primaryPort == LocalActivityHTTPServer.defaultPrimaryPort && fallbackPort == nil {
            candidates = LocalActivityHTTPServer.defaultPortCandidates
        } else {
            var requested: [UInt16] = [primaryPort]
            if let fallbackPort, fallbackPort != primaryPort, fallbackPort != LocalActivityHTTPServer.almaReservedPort {
                requested.append(fallbackPort)
            }
            candidates = requested
        }

        var boundPorts: [UInt16] = []
        for port in candidates {
            guard port != LocalActivityHTTPServer.almaReservedPort else { continue }
            if let bound = await startSingleListener(port: port) {
                boundPorts.append(bound)
                // When searching 24001...24009 for an unused port, stop once one port succeeds
                if primaryPort == LocalActivityHTTPServer.defaultPrimaryPort && fallbackPort == nil {
                    break
                }
            }
        }
        return boundPorts
    }

    public func stop() {
        lock.lock()
        let current = listeners
        listeners.removeAll()
        lock.unlock()

        for entry in current {
            entry.listener.cancel()
        }
    }

    // MARK: - Listener Lifecycle (Loopback 127.0.0.1 ONLY)

    private func startSingleListener(port: UInt16) async -> UInt16? {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let nwPort: NWEndpoint.Port = (port == 0)
            ? .any
            : (NWEndpoint.Port(rawValue: port) ?? .any)
        params.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: nwPort
        )

        let listener: NWListener
        do {
            listener = try NWListener(using: params)
        } catch {
            return nil
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        return await withCheckedContinuation { continuation in
            final class ResumeGuard: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                func claim() -> Bool {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return false }
                    resumed = true
                    return true
                }
            }
            let guardObj = ResumeGuard()

            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    let actualPort = listener.port?.rawValue
                    if let actualPort, let self {
                        self.lock.lock()
                        self.listeners.append((requestedPort: port, listener: listener, boundPort: actualPort))
                        self.lock.unlock()
                    }
                    if guardObj.claim() {
                        continuation.resume(returning: actualPort)
                    }
                case .failed, .cancelled:
                    listener.cancel()
                    if guardObj.claim() {
                        continuation.resume(returning: nil)
                    }
                case .waiting:
                    // EADDRINUSE (e.g. Alma already holds 23001) enters .waiting on some macOS versions
                    if port != 0 {
                        listener.cancel()
                        if guardObj.claim() {
                            continuation.resume(returning: nil)
                        }
                    }
                default:
                    break
                }
            }

            listener.start(queue: queue)
        }
    }

    // MARK: - Connection & HTTP Request Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var accumulated = buffer
            if let data {
                accumulated.append(data)
            }

            if let headerEnd = accumulated.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = accumulated[..<headerEnd.lowerBound]
                let responseData = self.routeHTTPRequest(headerData: headerData)
                connection.send(content: responseData, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if isComplete || accumulated.count > 131_072 {
                let bad = self.makeHTTPResponse(statusCode: 400, statusText: "Bad Request", jsonBody: APIErrorResponse(error: "Malformed HTTP request"))
                connection.send(content: bad, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            self.receiveRequest(on: connection, buffer: accumulated)
        }
    }

    public func handleRawHTTPRequestLineAndRoute(target: String, method: String = "GET") -> (statusCode: Int, body: Data) {
        let routed = route(target: target, method: method)
        return (routed.statusCode, routed.body)
    }

    private func route(target: String, method: String = "GET") -> RoutedResponse {
        let upperMethod = method.uppercased()
        guard upperMethod == "GET" else {
            return RoutedResponse(statusCode: 405, body: encodeJSON(APIErrorResponse(error: "Method not allowed")))
        }

        let normalizedTarget = target.hasPrefix("/") ? target : "/" + target
        guard let components = URLComponents(string: "http://127.0.0.1" + normalizedTarget) else {
            return RoutedResponse(statusCode: 400, body: encodeJSON(APIErrorResponse(error: "Invalid request URI")))
        }

        let path = components.path
        let queryItems = components.queryItems ?? []

        if path == "/api/activity-recorder/status" {
            return json(handleStatus())
        }

        if path == "/api/activity-recorder/sessions" {
            return json(handleListSessions(queryItems: queryItems))
        }

        if path.hasPrefix("/api/activity-recorder/sessions/") {
            var rawId = String(path.dropFirst("/api/activity-recorder/sessions/".count))
            var wantsEventsOnly = false
            if rawId.hasSuffix("/events") {
                wantsEventsOnly = true
                rawId = String(rawId.dropLast("/events".count))
            }
            let sessionId = rawId.removingPercentEncoding ?? rawId
            guard !sessionId.isEmpty else {
                return json((400, encodeJSON(APIErrorResponse(error: "Missing session id"))))
            }
            if wantsEventsOnly {
                return json(handleSessionEvents(sessionId: sessionId))
            }
            return json(handleSessionDetail(sessionId: sessionId))
        }

        if path == "/api/activity-recorder/search/keyword" {
            return json(handleOCRKeywordSearch(queryItems: queryItems))
        }

        if path == "/api/activity-recorder/snapshot-file" {
            return handleSnapshotFile(queryItems: queryItems)
        }

        if path.hasPrefix("/api/activity-recorder/summary/daily/") {
            let dateKey = String(path.dropFirst("/api/activity-recorder/summary/daily/".count)).removingPercentEncoding ?? ""
            return json(handleDailySummary(dateKey: dateKey))
        }

        if path.hasPrefix("/api/activity-recorder/summary/weekly/") {
            let weekKey = String(path.dropFirst("/api/activity-recorder/summary/weekly/".count)).removingPercentEncoding ?? ""
            return json(handleWeeklySummary(weekKey: weekKey))
        }

        if path == "/api/dayhelm/context" {
            return json(handleDayHelmContext(queryItems: queryItems))
        }

        if path == "/api/dayhelm/search" {
            return json(handleDayHelmSearch(queryItems: queryItems))
        }

        return json((404, encodeJSON(APIErrorResponse(error: "Not found: \(path)"))))
    }

    private func json(_ result: (Int, Data)) -> RoutedResponse {
        RoutedResponse(statusCode: result.0, body: result.1)
    }

    private func routeHTTPRequest(headerData: Data) -> Data {
        guard let headerString = String(data: headerData, encoding: .utf8),
              let firstLine = headerString.components(separatedBy: "\r\n").first else {
            return makeHTTPResponse(statusCode: 400, statusText: "Bad Request", jsonBody: APIErrorResponse(error: "Invalid request"))
        }

        let parts = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return makeHTTPResponse(statusCode: 400, statusText: "Bad Request", jsonBody: APIErrorResponse(error: "Invalid request line"))
        }

        let method = String(parts[0])
        let target = String(parts[1])
        let routed = route(target: target, method: method)
        let statusText: String
        switch routed.statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 403: statusText = "Forbidden"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        case 503: statusText = "Service Unavailable"
        default: statusText = "Internal Server Error"
        }
        return makeHTTPResponse(
            statusCode: routed.statusCode,
            statusText: statusText,
            bodyData: routed.body,
            contentType: routed.contentType
        )
    }

    // MARK: - Route Handlers

    private func handleStatus() -> (Int, Data) {
        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let dayEndMs = dayStartMs + 86_400_000 - 1
        let counts = (try? database.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs))
            ?? (sessions: 0, events: 0, snapshots: 0, ocrFrames: 0)
        let activeId = try? database.currentOpenSessionId()
        let runtime = stateProvider()

        let payload = LocalRecorderStatusSnapshot(
            running: true,
            recording: true,
            source: "dayhelm",
            version: "0.1.0",
            ports: activePorts,
            axTrusted: runtime.axTrusted,
            screenCaptureTrusted: runtime.screenCaptureTrusted,
            deepRecordingEnabled: runtime.deepRecordingEnabled,
            activeSessionId: activeId,
            todaySessions: counts.sessions,
            todayEvents: counts.events,
            todaySnapshots: counts.snapshots,
            todayOCRFrames: counts.ocrFrames
        )
        return (200, encodeJSON(payload))
    }

    private func handleListSessions(queryItems: [URLQueryItem]) -> (Int, Data) {
        let limit = queryItems.first(where: { $0.name == "limit" })?.value.flatMap(Int.init) ?? 200
        let sinceMs = queryItems.first(where: { $0.name == "since" })?.value.flatMap { parseTimestampMs($0) }
        let untilMs = queryItems.first(where: { $0.name == "until" })?.value.flatMap { parseTimestampMs($0) }

        do {
            let sessions = try database.listSessions(sinceMs: sinceMs, untilMs: untilMs, limit: max(1, min(limit, 5000)))
            return (200, encodeJSON(SessionsListAPIResponse(sessions: sessions, total: sessions.count)))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleSessionDetail(sessionId: String) -> (Int, Data) {
        do {
            guard let detail = try database.getSessionDetail(sessionId: sessionId) else {
                return (404, encodeJSON(APIErrorResponse(error: "Session not found")))
            }
            let payload = SessionDetailAPIResponse(
                session: detail.session,
                events: detail.events,
                snapshots: detail.snapshots,
                ocrFrames: detail.ocrFrames,
                ocr: detail.ocrFrames.map { OCRFrameCompatItem(frame: $0) }
            )
            return (200, encodeJSON(payload))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleOCRKeywordSearch(queryItems: [URLQueryItem]) -> (Int, Data) {
        let keyword = queryItems.first(where: { $0.name == "q" })?.value ?? ""
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (200, encodeJSON(OCRKeywordSearchAPIResponse(results: [])))
        }
        let limit = queryItems.first(where: { $0.name == "limit" })?.value.flatMap(Int.init) ?? 50
        do {
            let rows = try database.searchOCR(keyword: keyword, limit: max(1, min(limit, 500)))
            let results = rows.map {
                OCRKeywordSearchItem(
                    id: $0.id,
                    sessionId: $0.sessionId,
                    snapshotId: $0.snapshotId,
                    text: $0.text,
                    createdAt: $0.createdAt
                )
            }
            return (200, encodeJSON(OCRKeywordSearchAPIResponse(results: results)))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleSnapshotFile(queryItems: [URLQueryItem]) -> RoutedResponse {
        guard let store else {
            return RoutedResponse(statusCode: 503, body: encodeJSON(APIErrorResponse(error: "recorder not configured")))
        }

        let idParam = queryItems.first(where: { $0.name == "id" })?.value
        let pathParam = queryItems.first(where: { $0.name == "path" })?.value

        let requestedPath: String
        if let idParam, !idParam.isEmpty {
            do {
                guard let snapshot = try database.snapshot(id: idParam) else {
                    return RoutedResponse(statusCode: 404, body: encodeJSON(APIErrorResponse(error: "not found")))
                }
                requestedPath = snapshot.filePath
            } catch {
                return RoutedResponse(statusCode: 500, body: encodeJSON(APIErrorResponse(error: "\(error)")))
            }
        } else if let pathParam, !pathParam.isEmpty {
            requestedPath = pathParam
        } else {
            return RoutedResponse(statusCode: 400, body: encodeJSON(APIErrorResponse(error: "path required")))
        }

        let root = store.snapshotsDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidateURL = requestedPath.hasPrefix("/")
            ? URL(fileURLWithPath: requestedPath)
            : root.appendingPathComponent(requestedPath)
        let candidate = candidateURL.standardizedFileURL.resolvingSymlinksInPath()

        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            return RoutedResponse(statusCode: 403, body: encodeJSON(APIErrorResponse(error: "forbidden path")))
        }

        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return RoutedResponse(statusCode: 404, body: encodeJSON(APIErrorResponse(error: "not found")))
        }

        guard let bytes = try? Data(contentsOf: candidate) else {
            return RoutedResponse(statusCode: 500, body: encodeJSON(APIErrorResponse(error: "failed to read snapshot file")))
        }

        let contentType: String
        switch candidate.pathExtension.lowercased() {
        case "jpg", "jpeg": contentType = "image/jpeg"
        case "png": contentType = "image/png"
        default: contentType = "application/octet-stream"
        }
        return RoutedResponse(statusCode: 200, body: bytes, contentType: contentType)
    }

    private func handleDailySummary(dateKey: String) -> (Int, Data) {
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DayHelmDateFormatting.parseDayString(trimmed) != nil else {
            return (400, encodeJSON(APIErrorResponse(error: "Invalid date key '\(dateKey)'. Expected YYYY-MM-DD.")))
        }
        do {
            let stats = try database.dailySummaryStats(dateKey: trimmed)
            let nowMs = Int64(clock.now().timeIntervalSince1970 * 1000)
            let todayKey = DayHelmDateFormatting.dayString(from: clock.now())
            let record = DailyActivitySummaryRecord(
                id: "summary_daily_\(trimmed)",
                dateKey: trimmed,
                stats: stats,
                isPartial: trimmed >= todayKey,
                createdAt: nowMs,
                updatedAt: nowMs
            )
            return (200, encodeJSON(record))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleWeeklySummary(weekKey: String) -> (Int, Data) {
        let trimmed = weekKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DayHelmISOWeek.dateRange(forWeekKey: trimmed) != nil else {
            return (400, encodeJSON(APIErrorResponse(error: "Invalid week key '\(weekKey)'. Expected YYYY-Www or YYYY-MM-DD.")))
        }
        do {
            let stats = try database.weeklySummaryStats(weekKey: trimmed)
            let nowMs = Int64(clock.now().timeIntervalSince1970 * 1000)
            let currentWeek = DayHelmISOWeek.weekKey(for: clock.now())
            let record = WeeklyActivitySummaryRecord(
                id: "summary_weekly_\(stats.weekKey)",
                weekKey: stats.weekKey,
                stats: stats,
                isPartial: stats.weekKey >= currentWeek,
                createdAt: nowMs,
                updatedAt: nowMs
            )
            return (200, encodeJSON(record))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleDayHelmSearch(queryItems: [URLQueryItem]) -> (Int, Data) {
        let keyword = queryItems.first(where: { $0.name == "q" })?.value ?? ""
        let limit = queryItems.first(where: { $0.name == "limit" })?.value.flatMap(Int.init) ?? 20
        do {
            let hits = try database.search(keyword: keyword, limit: max(1, min(limit, 200)))
            return (200, encodeJSON(DayHelmSearchAPIResponse(keyword: keyword, total: hits.count, hits: hits)))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleSessionEvents(sessionId: String) -> (Int, Data) {
        do {
            guard let detail = try database.getSessionDetail(sessionId: sessionId) else {
                return (404, encodeJSON(APIErrorResponse(error: "Session not found")))
            }
            return (200, encodeJSON(SessionEventsAPIResponse(events: detail.events, total: detail.events.count)))
        } catch {
            return (500, encodeJSON(APIErrorResponse(error: "\(error)")))
        }
    }

    private func handleDayHelmContext(queryItems: [URLQueryItem]) -> (Int, Data) {
        let now = clock.now()
        let dayStart = startOfDay(for: now)
        let sinceParam = queryItems.first(where: { $0.name == "since" })?.value
        let sinceDate: Date
        if let sinceParam, !sinceParam.isEmpty {
            if let ms = Int64(sinceParam) {
                sinceDate = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
            } else if let parsed = DayHelmCLI.parseSinceSpec(sinceParam, now: now) {
                sinceDate = parsed
            } else {
                sinceDate = dayStart
            }
        } else {
            sinceDate = dayStart
        }

        let sinceMs = Int64(sinceDate.timeIntervalSince1970 * 1000)
        let untilMs = Int64(now.timeIntervalSince1970 * 1000)
        let activity = (try? database.queryAgentContext(sinceMs: sinceMs, untilMs: untilMs, maxOCRChars: 2400))
            ?? AgentActivityContext(
                sinceMs: sinceMs,
                untilMs: untilMs,
                sessionCount: 0,
                eventCount: 0,
                snapshotCount: 0,
                ocrFrameCount: 0,
                totalActiveMs: 0,
                sessions: [],
                recentWindows: [],
                ocrHighlights: []
            )

        let runtime = stateProvider()
        let todaySnapshot = runtime.daySnapshot ?? (try? store?.loadToday())
        let todayStr = DayHelmDateFormatting.dayString(from: now)

        let budgets: [BudgetSnapshot]
        let focusState: FocusSessionState?
        let activeFocus: ActiveFocusSnapshot?
        let metrics: DayMetrics

        if let todaySnapshot, todaySnapshot.date == todayStr {
            budgets = todaySnapshot.budgets
            focusState = todaySnapshot.focusState
            activeFocus = todaySnapshot.activeFocus
            metrics = todaySnapshot.metrics
        } else {
            budgets = []
            focusState = .unassigned
            activeFocus = nil
            metrics = DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0)
        }

        let response = DayHelmContextAPIResponse(
            schemaVersion: 1,
            date: todayStr,
            generatedAt: DayHelmDateFormatting.iso8601String(from: now),
            focusState: focusState,
            activeFocus: activeFocus,
            budgets: budgets,
            metrics: metrics,
            activity: activity
        )
        return (200, encodeJSON(response))
    }

    // MARK: - HTTP Serialization

    private func encodeJSON<T: Encodable>(_ value: T) -> Data {
        (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private func makeHTTPResponse<T: Encodable>(statusCode: Int, statusText: String, jsonBody: T) -> Data {
        makeHTTPResponse(statusCode: statusCode, statusText: statusText, bodyData: encodeJSON(jsonBody))
    }

    private func makeHTTPResponse(statusCode: Int, statusText: String, bodyData: Data, contentType: String = "application/json; charset=utf-8") -> Data {
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: \(contentType)",
            "Content-Length: \(bodyData.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var data = Data(headers.utf8)
        data.append(bodyData)
        return data
    }

    private func parseTimestampMs(_ raw: String) -> Int64? {
        if let ms = Int64(raw) {
            return ms
        }
        if let date = DayHelmDateFormatting.parseISO8601(raw) {
            return Int64(date.timeIntervalSince1970 * 1000)
        }
        return nil
    }

    private func startOfDay(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        return cal.startOfDay(for: date)
    }
}
