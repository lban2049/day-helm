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
        let upperMethod = method.uppercased()
        guard upperMethod == "GET" else {
            return (405, encodeJSON(APIErrorResponse(error: "Method not allowed")))
        }

        let normalizedTarget = target.hasPrefix("/") ? target : "/" + target
        guard let components = URLComponents(string: "http://127.0.0.1" + normalizedTarget) else {
            return (400, encodeJSON(APIErrorResponse(error: "Invalid request URI")))
        }

        let path = components.path
        let queryItems = components.queryItems ?? []

        if path == "/api/activity-recorder/status" {
            return handleStatus()
        }

        if path == "/api/activity-recorder/sessions" {
            return handleListSessions(queryItems: queryItems)
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
                return (400, encodeJSON(APIErrorResponse(error: "Missing session id")))
            }
            if wantsEventsOnly {
                return handleSessionEvents(sessionId: sessionId)
            }
            return handleSessionDetail(sessionId: sessionId)
        }

        if path == "/api/dayhelm/context" {
            return handleDayHelmContext(queryItems: queryItems)
        }

        return (404, encodeJSON(APIErrorResponse(error: "Not found: \(path)")))
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
        let routed = handleRawHTTPRequestLineAndRoute(target: target, method: method)
        let statusText: String
        switch routed.statusCode {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Internal Server Error"
        }
        return makeHTTPResponse(statusCode: routed.statusCode, statusText: statusText, bodyData: routed.body)
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
            return (200, encodeJSON(detail))
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

    private func makeHTTPResponse(statusCode: Int, statusText: String, bodyData: Data) -> Data {
        let headers = [
            "HTTP/1.1 \(statusCode) \(statusText)",
            "Content-Type: application/json; charset=utf-8",
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
