import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum ActivityDatabaseError: Error, CustomStringConvertible {
    case openFailed(path: String, message: String)
    case prepareFailed(sql: String, message: String)
    case stepFailed(sql: String, message: String)

    public var description: String {
        switch self {
        case .openFailed(let path, let message):
            return "Failed to open SQLite database at \(path): \(message)"
        case .prepareFailed(let sql, let message):
            return "SQLite prepare failed [\(sql)]: \(message)"
        case .stepFailed(let sql, let message):
            return "SQLite step failed [\(sql)]: \(message)"
        }
    }
}

public struct RecordedSessionSummary: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let startedAt: Int64
    public let endedAt: Int64?
    public let durationMs: Int64?
    public let triggerKind: String
    public let appNames: [String]
    public let eventCount: Int
    public let snapshotCount: Int
    public let totalBytes: Int64
    public let analysisStatus: String
    public let analysisTitle: String?
    public let analysisDescription: String?
    public let analysisModel: String?
    public let analysisError: String?
    public let analyzedAt: Int64?
    public let worthMemory: Bool
    public let worthKnowledge: Bool
    public let isMeeting: Bool
    public let storageTier: String
    public let entities: [String: [String]]
    public let topics: [String]
    public let project: String?
    public let highlights: [String]
    public let declaredTaskId: String?
    public let createdAt: Int64
    public let updatedAt: Int64
    /// Count of recorded `click` events in this session. Counts only, never key contents.
    public let clickCount: Int
    /// Count of recorded `keypress` events in this session. Counts only, never key contents.
    public let keypressCount: Int
    /// Derived input density: `(clickCount + keypressCount) / session minutes`.
    public let inputEventsPerMinute: Double

    public init(
        id: String,
        startedAt: Int64,
        endedAt: Int64? = nil,
        durationMs: Int64? = nil,
        triggerKind: String = "idle",
        appNames: [String] = [],
        eventCount: Int = 0,
        snapshotCount: Int = 0,
        totalBytes: Int64 = 0,
        analysisStatus: String = "pending",
        analysisTitle: String? = nil,
        analysisDescription: String? = nil,
        analysisModel: String? = nil,
        analysisError: String? = nil,
        analyzedAt: Int64? = nil,
        worthMemory: Bool = false,
        worthKnowledge: Bool = false,
        isMeeting: Bool = false,
        storageTier: String = "hot",
        entities: [String: [String]] = [:],
        topics: [String] = [],
        project: String? = nil,
        highlights: [String] = [],
        declaredTaskId: String? = nil,
        createdAt: Int64,
        updatedAt: Int64,
        clickCount: Int = 0,
        keypressCount: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationMs = durationMs
        self.triggerKind = triggerKind
        self.appNames = appNames
        self.eventCount = eventCount
        self.snapshotCount = snapshotCount
        self.totalBytes = totalBytes
        self.analysisStatus = analysisStatus
        self.analysisTitle = analysisTitle
        self.analysisDescription = analysisDescription
        self.analysisModel = analysisModel
        self.analysisError = analysisError
        self.analyzedAt = analyzedAt
        self.worthMemory = worthMemory
        self.worthKnowledge = worthKnowledge
        self.isMeeting = isMeeting
        self.storageTier = storageTier
        self.entities = entities
        self.topics = topics
        self.project = project
        self.highlights = highlights
        self.declaredTaskId = declaredTaskId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.clickCount = clickCount
        self.keypressCount = keypressCount
        let effectiveDurationMs = durationMs ?? endedAt.map { max(0, $0 - startedAt) } ?? 0
        self.inputEventsPerMinute = DayInputTotals.density(
            clickCount: clickCount,
            keypressCount: keypressCount,
            durationMs: effectiveDurationMs
        )
    }
}

public struct RecordedActivityEvent: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let sessionId: String
    public let timestamp: Int64
    public let kind: String
    public let appName: String?
    public let windowTitle: String?
    public let url: String?
    public let data: [String: String]
    public let createdAt: Int64

    public init(
        id: String,
        sessionId: String,
        timestamp: Int64,
        kind: String,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        data: [String: String] = [:],
        createdAt: Int64
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.kind = kind
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.data = data
        self.createdAt = createdAt
    }
}

public struct RecordedSnapshot: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let sessionId: String
    public let timestamp: Int64
    public let filePath: String
    public let width: Int
    public let height: Int
    public let sizeBytes: Int64
    public let trigger: String
    public let appName: String?
    public let windowTitle: String?
    public let hashHex: String?
    public let histogram: [Double]?
    public let diffPct: Double?
    public let storageTier: String
    public let createdAt: Int64

    public init(
        id: String,
        sessionId: String,
        timestamp: Int64,
        filePath: String,
        width: Int = 0,
        height: Int = 0,
        sizeBytes: Int64 = 0,
        trigger: String = "heartbeat",
        appName: String? = nil,
        windowTitle: String? = nil,
        hashHex: String? = nil,
        histogram: [Double]? = nil,
        diffPct: Double? = nil,
        storageTier: String = "hot",
        createdAt: Int64
    ) {
        self.id = id
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.filePath = filePath
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.trigger = trigger
        self.appName = appName
        self.windowTitle = windowTitle
        self.hashHex = hashHex
        self.histogram = histogram
        self.diffPct = diffPct
        self.storageTier = storageTier
        self.createdAt = createdAt
    }
}

public struct RecordedOCRFrame: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let snapshotId: String
    public let sessionId: String
    public let text: String
    public let charCount: Int
    public let tokenCount: Int
    public let createdAt: Int64

    public init(
        id: String,
        snapshotId: String,
        sessionId: String,
        text: String,
        charCount: Int,
        tokenCount: Int,
        createdAt: Int64
    ) {
        self.id = id
        self.snapshotId = snapshotId
        self.sessionId = sessionId
        self.text = text
        self.charCount = charCount
        self.tokenCount = tokenCount
        self.createdAt = createdAt
    }
}

public struct SnapshotMaintenanceRecord: Sendable, Equatable {
    public let id: String
    public let filePath: String
    public let timestamp: Int64
    public let width: Int
    public let height: Int
    public let sizeBytes: Int64
    public let storageTier: String

    public init(
        id: String,
        filePath: String,
        timestamp: Int64,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        storageTier: String
    ) {
        self.id = id
        self.filePath = filePath
        self.timestamp = timestamp
        self.width = width
        self.height = height
        self.sizeBytes = sizeBytes
        self.storageTier = storageTier
    }
}

public struct RecordedSessionDetail: Sendable, Equatable, Codable {
    public let session: RecordedSessionSummary
    public let events: [RecordedActivityEvent]
    public let snapshots: [RecordedSnapshot]
    public let ocrFrames: [RecordedOCRFrame]

    public init(
        session: RecordedSessionSummary,
        events: [RecordedActivityEvent],
        snapshots: [RecordedSnapshot],
        ocrFrames: [RecordedOCRFrame]
    ) {
        self.session = session
        self.events = events
        self.snapshots = snapshots
        self.ocrFrames = ocrFrames
    }
}

public struct RecorderStorageStats: Sendable, Equatable, Codable {
    public let totalSessions: Int
    public let totalEvents: Int
    public let totalSnapshots: Int
    public let totalOCRFrames: Int
    public let usedSnapshotBytes: Int64
    public let activeSessionId: String?
    public let activeSessionStartedAt: Int64?

    public init(
        totalSessions: Int = 0,
        totalEvents: Int = 0,
        totalSnapshots: Int = 0,
        totalOCRFrames: Int = 0,
        usedSnapshotBytes: Int64 = 0,
        activeSessionId: String? = nil,
        activeSessionStartedAt: Int64? = nil
    ) {
        self.totalSessions = totalSessions
        self.totalEvents = totalEvents
        self.totalSnapshots = totalSnapshots
        self.totalOCRFrames = totalOCRFrames
        self.usedSnapshotBytes = usedSnapshotBytes
        self.activeSessionId = activeSessionId
        self.activeSessionStartedAt = activeSessionStartedAt
    }
}

public struct ActivitySearchHit: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let sourceKind: String
    public let sessionId: String
    public let timestamp: Int64
    public let appName: String?
    public let windowTitle: String?
    public let url: String?
    public let snippet: String
    public let declaredTaskId: String?

    public init(
        id: String,
        sourceKind: String,
        sessionId: String,
        timestamp: Int64,
        appName: String?,
        windowTitle: String?,
        url: String?,
        snippet: String,
        declaredTaskId: String?
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.snippet = snippet
        self.declaredTaskId = declaredTaskId
    }
}

public struct OCRActivitySearchResult: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let sessionId: String
    public let snapshotId: String
    public let text: String
    public let createdAt: Int64

    public init(id: String, sessionId: String, snapshotId: String, text: String, createdAt: Int64) {
        self.id = id
        self.sessionId = sessionId
        self.snapshotId = snapshotId
        self.text = text
        self.createdAt = createdAt
    }
}

public struct RecentWindowEntry: Sendable, Equatable, Codable {
    public let appName: String
    public let windowTitle: String?
    public let url: String?
    public let lastSeenAt: Int64
    public let declaredTaskId: String?

    public init(
        appName: String,
        windowTitle: String?,
        url: String?,
        lastSeenAt: Int64,
        declaredTaskId: String?
    ) {
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.lastSeenAt = lastSeenAt
        self.declaredTaskId = declaredTaskId
    }
}

public struct AgentOCRSnippet: Sendable, Equatable, Codable {
    public let snapshotId: String
    public let sessionId: String
    public let timestamp: Int64
    public let appName: String?
    public let windowTitle: String?
    public let text: String
    public let charCount: Int

    public init(
        snapshotId: String,
        sessionId: String,
        timestamp: Int64,
        appName: String?,
        windowTitle: String?,
        text: String,
        charCount: Int
    ) {
        self.snapshotId = snapshotId
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.appName = appName
        self.windowTitle = windowTitle
        self.text = text
        self.charCount = charCount
    }
}

public struct AgentActivityContext: Sendable, Equatable, Codable {
    public let sinceMs: Int64
    public let untilMs: Int64
    public let sessionCount: Int
    public let eventCount: Int
    public let snapshotCount: Int
    public let ocrFrameCount: Int
    public let totalActiveMs: Int64
    public let sessions: [RecordedSessionSummary]
    public let recentWindows: [RecentWindowEntry]
    public let ocrHighlights: [AgentOCRSnippet]

    public init(
        sinceMs: Int64,
        untilMs: Int64,
        sessionCount: Int,
        eventCount: Int,
        snapshotCount: Int,
        ocrFrameCount: Int,
        totalActiveMs: Int64,
        sessions: [RecordedSessionSummary],
        recentWindows: [RecentWindowEntry],
        ocrHighlights: [AgentOCRSnippet]
    ) {
        self.sinceMs = sinceMs
        self.untilMs = untilMs
        self.sessionCount = sessionCount
        self.eventCount = eventCount
        self.snapshotCount = snapshotCount
        self.ocrFrameCount = ocrFrameCount
        self.totalActiveMs = totalActiveMs
        self.sessions = sessions
        self.recentWindows = recentWindows
        self.ocrHighlights = ocrHighlights
    }
}

public final class ActivityDatabase: @unchecked Sendable {
    public let databaseURL: URL
    public let sessionIdleGapMs: Int64

    private let lock = NSLock()
    private var db: OpaquePointer?
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    public private(set) var fullCounterResyncCount: Int = 0
    private var syncedSessionIds: Set<String> = []
    private var cachedOpenSession: (summary: RecordedSessionSummary, lastActivityMs: Int64)?

    public static func defaultDatabaseURL(in storeDirectory: URL = DayHelmStore.defaultDirectory) -> URL {
        storeDirectory.appendingPathComponent("activity.sqlite")
    }

    public init(
        databaseURL: URL = ActivityDatabase.defaultDatabaseURL(),
        sessionIdleGapMs: Int64 = 120_000
    ) throws {
        self.databaseURL = databaseURL
        self.sessionIdleGapMs = max(30_000, sessionIdleGapMs)

        let parent = databaseURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(databaseURL.path, &handle, flags, nil)
        guard rc == SQLITE_OK, let opened = handle else {
            let msg = handle.flatMap { sqlite3_errmsg($0).map { String(cString: $0) } } ?? "unknown error"
            if let handle { sqlite3_close_v2(handle) }
            throw ActivityDatabaseError.openFailed(path: databaseURL.path, message: msg)
        }
        self.db = opened
        sqlite3_busy_timeout(opened, 5000)

        try executeLocked("PRAGMA journal_mode=WAL;")
        try executeLocked("PRAGMA synchronous=NORMAL;")
        try executeLocked("PRAGMA foreign_keys=ON;")
        try createSchemaLocked()
    }

    deinit {
        lock.lock()
        if let db {
            sqlite3_close_v2(db)
            self.db = nil
        }
        lock.unlock()
    }

    // MARK: - Session Lifecycle & Event Recording

    @discardableResult
    public func ensureActiveSession(
        atMs timestampMs: Int64,
        triggerKind: String = "app_focus",
        appName: String? = nil,
        declaredTaskId: String? = nil,
        project: String? = nil
    ) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        return try ensureActiveSessionLocked(
            atMs: timestampMs,
            triggerKind: triggerKind,
            appName: appName,
            declaredTaskId: declaredTaskId,
            project: project
        )
    }

    @discardableResult
    public func startSession(
        id: String? = nil,
        startedAtMs: Int64,
        triggerKind: String = "manual",
        appNames: [String] = [],
        declaredTaskId: String? = nil,
        project: String? = nil
    ) throws -> RecordedSessionSummary {
        lock.lock()
        defer { lock.unlock() }

        if let openId = try currentOpenSessionIdLocked() {
            let lastMs = try latestSessionTimestampLocked(sessionId: openId) ?? startedAtMs
            try closeSessionLocked(sessionId: openId, endedAtMs: max(lastMs, startedAtMs))
        }

        let sessionId = id ?? makeSessionId(timestampMs: startedAtMs)
        let appNamesJSON = encodeJSONString(appNames) ?? "[]"
        let effectiveProject = nonEmpty(project) ?? nonEmpty(declaredTaskId)

        let sql = """
        INSERT INTO activity_sessions (
            id, started_at, ended_at, duration_ms, trigger_kind, app_names,
            event_count, snapshot_count, total_bytes, analysis_status,
            project, declared_task_id, created_at, updated_at
        ) VALUES (?, ?, NULL, 0, ?, ?, 0, 0, 0, 'pending', ?, ?, ?, ?);
        """
        try runStatementLocked(sql) { stmt in
            bindText(stmt, index: 1, value: sessionId)
            sqlite3_bind_int64(stmt, 2, startedAtMs)
            bindText(stmt, index: 3, value: triggerKind)
            bindText(stmt, index: 4, value: appNamesJSON)
            bindOptionalText(stmt, index: 5, value: effectiveProject)
            bindOptionalText(stmt, index: 6, value: nonEmpty(declaredTaskId))
            sqlite3_bind_int64(stmt, 7, startedAtMs)
            sqlite3_bind_int64(stmt, 8, startedAtMs)
        }
        syncedSessionIds.insert(sessionId)

        let summary = RecordedSessionSummary(
            id: sessionId,
            startedAt: startedAtMs,
            endedAt: nil,
            durationMs: 0,
            triggerKind: triggerKind,
            appNames: appNames,
            eventCount: 0,
            snapshotCount: 0,
            totalBytes: 0,
            analysisStatus: "pending",
            project: effectiveProject,
            declaredTaskId: nonEmpty(declaredTaskId),
            createdAt: startedAtMs,
            updatedAt: startedAtMs
        )
        cachedOpenSession = (summary: summary, lastActivityMs: startedAtMs)
        return summary
    }

    public func closeSession(sessionId: String, endedAtMs: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        try closeSessionLocked(sessionId: sessionId, endedAtMs: endedAtMs)
    }

    public func closeActiveSessionIfNeeded(endedAtMs: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        if let openId = try currentOpenSessionIdLocked() {
            let lastMs = try latestSessionTimestampLocked(sessionId: openId) ?? endedAtMs
            try closeSessionLocked(sessionId: openId, endedAtMs: max(lastMs, endedAtMs))
        }
    }

    /// Finalizes any sessions left with `ended_at IS NULL` from a previous crash or force-quit
    /// so subsequent sessions do not inherit stale open bounds.
    @discardableResult
    public func finalizeStaleOpenSessionsOnStartup() throws -> Int {
        lock.lock()
        defer { lock.unlock() }

        var openSessions: [(id: String, startedAt: Int64)] = []
        try queryStatementLocked(
            "SELECT id, started_at FROM activity_sessions WHERE ended_at IS NULL ORDER BY started_at ASC;",
            bind: { _ in },
            onRow: { stmt in
                if let id = readText(stmt, 0) {
                    openSessions.append((id: id, startedAt: sqlite3_column_int64(stmt, 1)))
                }
            }
        )

        for entry in openSessions {
            let lastMs = try latestSessionTimestampLocked(sessionId: entry.id) ?? entry.startedAt
            try closeSessionLocked(sessionId: entry.id, endedAtMs: max(entry.startedAt, lastMs))
        }
        cachedOpenSession = nil
        return openSessions.count
    }

    /// Closes the current open session at its last observed activity timestamp.
    /// Used when the user goes idle so idle time is never counted into `duration_ms`.
    public func closeActiveSessionAtLastActivity() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let openId = try currentOpenSessionIdLocked() else { return }
        let summary = try fetchSessionSummaryLocked(sessionId: openId)
        guard let endMs = try latestSessionTimestampLocked(sessionId: openId) ?? summary?.startedAt, endMs > 0 else {
            return
        }
        try closeSessionLocked(sessionId: openId, endedAtMs: endMs)
    }

    @discardableResult
    public func insertEvent(
        id: String? = nil,
        sessionId: String? = nil,
        timestampMs: Int64,
        kind: String,
        appName: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        data: [String: String] = [:],
        declaredTaskId: String? = nil,
        project: String? = nil
    ) throws -> RecordedActivityEvent {
        lock.lock()
        defer { lock.unlock() }

        let targetSessionId: String
        if let explicit = sessionId {
            targetSessionId = explicit
        } else if kind == "lock" {
            if let openId = try currentOpenSessionIdLocked() {
                targetSessionId = openId
            } else {
                targetSessionId = try ensureActiveSessionLocked(
                    atMs: timestampMs,
                    triggerKind: kind,
                    appName: appName,
                    declaredTaskId: declaredTaskId,
                    project: project
                )
            }
        } else {
            targetSessionId = try ensureActiveSessionLocked(
                atMs: timestampMs,
                triggerKind: kind,
                appName: appName,
                declaredTaskId: declaredTaskId,
                project: project
            )
        }

        let eventId = id ?? "evt_\(timestampMs)_\(UUID().uuidString.prefix(8).lowercased())"
        let cleanApp = nonEmpty(appName)
        let cleanTitle = nonEmpty(windowTitle).map { PrivacyRedactor.redactSecrets(in: $0) }
        let cleanURL = PrivacyRedactor.sanitizeURL(nonEmpty(url))
        let sanitizedData: [String: String] = data.reduce(into: [:]) { acc, pair in
            let value = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return }
            acc[pair.key] = PrivacyRedactor.sanitizeMetadataValue(value)
        }
        let dataJSON = encodeJSONString(sanitizedData) ?? "{}"

        let sql = """
        INSERT INTO activity_events (
            id, session_id, timestamp, kind, app_name, window_title, url, data, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try runStatementLocked(sql) { stmt in
            bindText(stmt, index: 1, value: eventId)
            bindText(stmt, index: 2, value: targetSessionId)
            sqlite3_bind_int64(stmt, 3, timestampMs)
            bindText(stmt, index: 4, value: kind)
            bindOptionalText(stmt, index: 5, value: cleanApp)
            bindOptionalText(stmt, index: 6, value: cleanTitle)
            bindOptionalText(stmt, index: 7, value: cleanURL)
            bindText(stmt, index: 8, value: dataJSON)
            sqlite3_bind_int64(stmt, 9, timestampMs)
        }

        let inputCountDelta: Int
        if kind == "click" || kind == "keypress" {
            inputCountDelta = max(1, Int(sanitizedData["count"] ?? "1") ?? 1)
        } else {
            inputCountDelta = 0
        }

        try refreshSessionMetadataLocked(
            sessionId: targetSessionId,
            activityAtMs: timestampMs,
            addedAppName: cleanApp,
            addedEventKind: kind,
            addedEventInputCount: inputCountDelta,
            addedSnapshotBytes: nil,
            declaredTaskId: declaredTaskId,
            project: project
        )

        if kind == "lock" {
            try closeSessionLocked(sessionId: targetSessionId, endedAtMs: timestampMs)
        }

        return RecordedActivityEvent(
            id: eventId,
            sessionId: targetSessionId,
            timestamp: timestampMs,
            kind: kind,
            appName: cleanApp,
            windowTitle: cleanTitle,
            url: cleanURL,
            data: sanitizedData,
            createdAt: timestampMs
        )
    }

    @discardableResult
    public func insertSnapshot(
        id: String? = nil,
        sessionId: String? = nil,
        timestampMs: Int64,
        filePath: String,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        trigger: String = "heartbeat",
        appName: String? = nil,
        windowTitle: String? = nil,
        hashHex: String? = nil,
        histogram: [Double]? = nil,
        diffPct: Double? = nil,
        storageTier: String = "hot",
        declaredTaskId: String? = nil,
        project: String? = nil
    ) throws -> RecordedSnapshot {
        lock.lock()
        defer { lock.unlock() }

        let targetSessionId: String
        if let explicit = sessionId {
            targetSessionId = explicit
        } else {
            targetSessionId = try ensureActiveSessionLocked(
                atMs: timestampMs,
                triggerKind: trigger,
                appName: appName,
                declaredTaskId: declaredTaskId,
                project: project
            )
        }

        let snapshotId = id ?? "snap_\(timestampMs)_\(UUID().uuidString.prefix(8).lowercased())"
        let cleanApp = nonEmpty(appName)
        let cleanTitle = nonEmpty(windowTitle).map { PrivacyRedactor.redactSecrets(in: $0) }
        let histJSON = histogram.flatMap { encodeJSONString($0) }

        let sql = """
        INSERT INTO activity_snapshots (
            id, session_id, timestamp, file_path, width, height, size_bytes,
            trigger, app_name, window_title, hash_hex, histogram, diff_pct,
            storage_tier, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        try runStatementLocked(sql) { stmt in
            bindText(stmt, index: 1, value: snapshotId)
            bindText(stmt, index: 2, value: targetSessionId)
            sqlite3_bind_int64(stmt, 3, timestampMs)
            bindText(stmt, index: 4, value: filePath)
            sqlite3_bind_int(stmt, 5, Int32(width))
            sqlite3_bind_int(stmt, 6, Int32(height))
            sqlite3_bind_int64(stmt, 7, sizeBytes)
            bindText(stmt, index: 8, value: trigger)
            bindOptionalText(stmt, index: 9, value: cleanApp)
            bindOptionalText(stmt, index: 10, value: cleanTitle)
            bindOptionalText(stmt, index: 11, value: nonEmpty(hashHex))
            bindOptionalText(stmt, index: 12, value: histJSON)
            if let diffPct {
                sqlite3_bind_double(stmt, 13, diffPct)
            } else {
                sqlite3_bind_null(stmt, 13)
            }
            bindText(stmt, index: 14, value: storageTier)
            sqlite3_bind_int64(stmt, 15, timestampMs)
        }

        try refreshSessionMetadataLocked(
            sessionId: targetSessionId,
            activityAtMs: timestampMs,
            addedAppName: cleanApp,
            addedEventKind: nil,
            addedEventInputCount: 0,
            addedSnapshotBytes: sizeBytes,
            declaredTaskId: declaredTaskId,
            project: project
        )

        return RecordedSnapshot(
            id: snapshotId,
            sessionId: targetSessionId,
            timestamp: timestampMs,
            filePath: filePath,
            width: width,
            height: height,
            sizeBytes: sizeBytes,
            trigger: trigger,
            appName: cleanApp,
            windowTitle: cleanTitle,
            hashHex: nonEmpty(hashHex),
            histogram: histogram,
            diffPct: diffPct,
            storageTier: storageTier,
            createdAt: timestampMs
        )
    }

    @discardableResult
    public func insertOCRFrame(
        id: String? = nil,
        snapshotId: String,
        sessionId: String,
        text: String,
        charCount: Int? = nil,
        tokenCount: Int? = nil,
        createdAtMs: Int64
    ) throws -> RecordedOCRFrame {
        lock.lock()
        defer { lock.unlock() }

        let frameId = id ?? "ocr_\(createdAtMs)_\(UUID().uuidString.prefix(8).lowercased())"
        let trimmed = PrivacyRedactor.redactSecrets(in: text.trimmingCharacters(in: .whitespacesAndNewlines))
        let resolvedChars = charCount ?? trimmed.count
        let resolvedTokens = tokenCount ?? Self.estimateTokenCount(trimmed)

        let sql = """
        INSERT INTO activity_ocr_frames (
            id, snapshot_id, session_id, text, char_count, token_count, created_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        try runStatementLocked(sql) { stmt in
            bindText(stmt, index: 1, value: frameId)
            bindText(stmt, index: 2, value: snapshotId)
            bindText(stmt, index: 3, value: sessionId)
            bindText(stmt, index: 4, value: trimmed)
            sqlite3_bind_int(stmt, 5, Int32(resolvedChars))
            sqlite3_bind_int(stmt, 6, Int32(resolvedTokens))
            sqlite3_bind_int64(stmt, 7, createdAtMs)
        }

        try synthesizeSessionSummaryLocked(sessionId: sessionId, nowMs: createdAtMs)

        return RecordedOCRFrame(
            id: frameId,
            snapshotId: snapshotId,
            sessionId: sessionId,
            text: trimmed,
            charCount: resolvedChars,
            tokenCount: resolvedTokens,
            createdAt: createdAtMs
        )
    }

    // MARK: - Queries & Agent Context

    public func listSessions(
        sinceMs: Int64? = nil,
        untilMs: Int64? = nil,
        limit: Int = 100,
        offset: Int = 0,
        analysisStatus: String? = nil
    ) throws -> [RecordedSessionSummary] {
        lock.lock()
        defer { lock.unlock() }
        return try listSessionsLocked(
            sinceMs: sinceMs,
            untilMs: untilMs,
            limit: limit,
            offset: offset,
            analysisStatus: analysisStatus
        )
    }

    public func countSessions(
        sinceMs: Int64? = nil,
        untilMs: Int64? = nil,
        analysisStatus: String? = nil
    ) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return try countSessionsLocked(sinceMs: sinceMs, untilMs: untilMs, analysisStatus: analysisStatus)
    }

    public func resolveSessionId(prefixOrId: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try resolveSessionIdLocked(prefixOrId: prefixOrId)
    }

    public func getSessionDetail(sessionId: String) throws -> RecordedSessionDetail? {
        lock.lock()
        defer { lock.unlock() }

        guard let resolvedId = try resolveSessionIdLocked(prefixOrId: sessionId),
              let session = try fetchSessionSummaryLocked(sessionId: resolvedId) else {
            return nil
        }
        let events = try fetchEventsLocked(sessionId: resolvedId)
        let snapshots = try fetchSnapshotsLocked(sessionId: resolvedId)
        let ocrFrames = try fetchOCRFramesLocked(sessionId: resolvedId)

        return RecordedSessionDetail(
            session: session,
            events: events,
            snapshots: snapshots,
            ocrFrames: ocrFrames
        )
    }

    public func search(keyword: String, limit: Int = 20) throws -> [ActivitySearchHit] {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let pattern = "%\(escapeLike(trimmed.lowercased()))%"
        let maxResults = max(1, limit)

        var hits: [ActivitySearchHit] = []

        // 1. Search OCR frames (FTS5 trigram for >= 3 chars, LIKE fallback for < 3 chars)
        if trimmed.count >= 3 {
            let ftsPhrase = makeFTS5TrigramPhrase(trimmed)
            let ocrSQL = """
            SELECT f.id, f.session_id, f.created_at, s.app_name, s.window_title, f.text, sess.declared_task_id
            FROM activity_ocr_fts fts
            JOIN activity_ocr_frames f ON f.id = fts.frame_id
            LEFT JOIN activity_snapshots s ON f.snapshot_id = s.id
            LEFT JOIN activity_sessions sess ON f.session_id = sess.id
            WHERE activity_ocr_fts MATCH ?
            ORDER BY f.created_at DESC
            LIMIT ?;
            """
            try queryStatementLocked(ocrSQL, bind: { stmt in
                bindText(stmt, index: 1, value: ftsPhrase)
                sqlite3_bind_int(stmt, 2, Int32(maxResults))
            }, onRow: { stmt in
                let id = readText(stmt, 0) ?? UUID().uuidString
                let sessionId = readText(stmt, 1) ?? ""
                let ts = sqlite3_column_int64(stmt, 2)
                let appName = readText(stmt, 3)
                let windowTitle = readText(stmt, 4)
                let text = readText(stmt, 5) ?? ""
                let taskId = readText(stmt, 6)
                hits.append(ActivitySearchHit(
                    id: "ocr:\(id)",
                    sourceKind: "ocr",
                    sessionId: sessionId,
                    timestamp: ts,
                    appName: appName,
                    windowTitle: windowTitle,
                    url: nil,
                    snippet: makeSnippet(from: text, keyword: trimmed),
                    declaredTaskId: taskId
                ))
            })
        } else {
            let ocrSQL = """
            SELECT f.id, f.session_id, f.created_at, s.app_name, s.window_title, f.text, sess.declared_task_id
            FROM activity_ocr_frames f
            LEFT JOIN activity_snapshots s ON f.snapshot_id = s.id
            LEFT JOIN activity_sessions sess ON f.session_id = sess.id
            WHERE LOWER(f.text) LIKE ? ESCAPE '\\'
            ORDER BY f.created_at DESC
            LIMIT ?;
            """
            try queryStatementLocked(ocrSQL, bind: { stmt in
                bindText(stmt, index: 1, value: pattern)
                sqlite3_bind_int(stmt, 2, Int32(maxResults))
            }, onRow: { stmt in
                let id = readText(stmt, 0) ?? UUID().uuidString
                let sessionId = readText(stmt, 1) ?? ""
                let ts = sqlite3_column_int64(stmt, 2)
                let appName = readText(stmt, 3)
                let windowTitle = readText(stmt, 4)
                let text = readText(stmt, 5) ?? ""
                let taskId = readText(stmt, 6)
                hits.append(ActivitySearchHit(
                    id: "ocr:\(id)",
                    sourceKind: "ocr",
                    sessionId: sessionId,
                    timestamp: ts,
                    appName: appName,
                    windowTitle: windowTitle,
                    url: nil,
                    snippet: makeSnippet(from: text, keyword: trimmed),
                    declaredTaskId: taskId
                ))
            })
        }

        // 2. Search events (window_title, url, app_name)
        let eventSQL = """
        SELECT e.id, e.session_id, e.timestamp, e.app_name, e.window_title, e.url, sess.declared_task_id
        FROM activity_events e
        LEFT JOIN activity_sessions sess ON e.session_id = sess.id
        WHERE LOWER(COALESCE(e.window_title, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(e.url, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(e.app_name, '')) LIKE ? ESCAPE '\\'
        ORDER BY e.timestamp DESC
        LIMIT ?;
        """
        try queryStatementLocked(eventSQL, bind: { stmt in
            bindText(stmt, index: 1, value: pattern)
            bindText(stmt, index: 2, value: pattern)
            bindText(stmt, index: 3, value: pattern)
            sqlite3_bind_int(stmt, 4, Int32(maxResults))
        }, onRow: { stmt in
            let id = readText(stmt, 0) ?? UUID().uuidString
            let sessionId = readText(stmt, 1) ?? ""
            let ts = sqlite3_column_int64(stmt, 2)
            let appName = readText(stmt, 3)
            let windowTitle = readText(stmt, 4)
            let url = readText(stmt, 5)
            let taskId = readText(stmt, 6)
            let combined = [appName, windowTitle, url].compactMap { $0 }.joined(separator: " | ")
            hits.append(ActivitySearchHit(
                id: "event:\(id)",
                sourceKind: "event",
                sessionId: sessionId,
                timestamp: ts,
                appName: appName,
                windowTitle: windowTitle,
                url: url,
                snippet: makeSnippet(from: combined, keyword: trimmed),
                declaredTaskId: taskId
            ))
        })

        // 3. Search session titles & descriptions
        let sessSQL = """
        SELECT id, started_at, app_names, analysis_title, analysis_description, declared_task_id
        FROM activity_sessions
        WHERE LOWER(COALESCE(analysis_title, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(analysis_description, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(project, '')) LIKE ? ESCAPE '\\'
        ORDER BY started_at DESC
        LIMIT ?;
        """
        try queryStatementLocked(sessSQL, bind: { stmt in
            bindText(stmt, index: 1, value: pattern)
            bindText(stmt, index: 2, value: pattern)
            bindText(stmt, index: 3, value: pattern)
            sqlite3_bind_int(stmt, 4, Int32(maxResults))
        }, onRow: { stmt in
            let id = readText(stmt, 0) ?? ""
            let ts = sqlite3_column_int64(stmt, 1)
            let appNames = decodeJSON([String].self, from: readText(stmt, 2)) ?? []
            let title = readText(stmt, 3)
            let desc = readText(stmt, 4)
            let taskId = readText(stmt, 5)
            let combined = [title, desc].compactMap { $0 }.joined(separator: " — ")
            hits.append(ActivitySearchHit(
                id: "session:\(id)",
                sourceKind: "session",
                sessionId: id,
                timestamp: ts,
                appName: appNames.first,
                windowTitle: title,
                url: nil,
                snippet: makeSnippet(from: combined, keyword: trimmed),
                declaredTaskId: taskId
            ))
        })

        return hits
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(maxResults)
            .map { $0 }
    }

    public func latestOCRText(
        withinSeconds: TimeInterval = 180,
        appName: String? = nil,
        windowTitle: String? = nil,
        nowMs: Int64
    ) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let cutoffMs = nowMs - Int64(max(1.0, withinSeconds) * 1000.0)

        let trimmedApp = appName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasApp = (trimmedApp?.isEmpty == false)
        let hasTitle = (trimmedTitle?.isEmpty == false)

        let sql: String
        if hasApp && hasTitle {
            sql = """
            SELECT f.text
            FROM activity_ocr_frames f
            JOIN activity_snapshots s ON f.snapshot_id = s.id
            WHERE f.created_at >= ? AND f.created_at <= ?
              AND s.app_name = ?
              AND s.window_title = ?
            ORDER BY f.created_at DESC
            LIMIT 1;
            """
        } else if hasApp {
            sql = """
            SELECT f.text
            FROM activity_ocr_frames f
            LEFT JOIN activity_snapshots s ON f.snapshot_id = s.id
            WHERE f.created_at >= ? AND f.created_at <= ?
              AND (s.app_name IS NULL OR s.app_name = ?)
            ORDER BY f.created_at DESC
            LIMIT 1;
            """
        } else {
            sql = """
            SELECT text
            FROM activity_ocr_frames
            WHERE created_at >= ? AND created_at <= ?
            ORDER BY created_at DESC
            LIMIT 1;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, cutoffMs)
        sqlite3_bind_int64(stmt, 2, nowMs)
        if hasApp && hasTitle {
            bindText(stmt, index: 3, value: trimmedApp!)
            bindText(stmt, index: 4, value: trimmedTitle!)
        } else if hasApp {
            bindText(stmt, index: 3, value: trimmedApp!)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }
        let text = readText(stmt, 0)
        return text?.isEmpty == false ? text : nil
    }

    public func queryAgentContext(
        sinceMs: Int64,
        untilMs: Int64,
        maxOCRChars: Int = 2400
    ) throws -> AgentActivityContext {
        lock.lock()
        defer { lock.unlock() }

        let sessions = try listSessionsLocked(sinceMs: sinceMs, untilMs: untilMs, limit: 100)
        let eventCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_events WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: sinceMs,
            untilMs: untilMs
        )
        let snapshotCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_snapshots WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: sinceMs,
            untilMs: untilMs
        )
        let ocrFrameCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_ocr_frames WHERE created_at >= ? AND created_at <= ?;",
            sinceMs: sinceMs,
            untilMs: untilMs
        )

        let totalActiveMs = sessions.reduce(Int64(0)) { acc, s in
            if let dur = s.durationMs {
                return acc + max(0, dur)
            }
            if let end = s.endedAt {
                return acc + max(0, end - s.startedAt)
            }
            return acc
        }

        // Deduplicated recent windows (most recent first)
        var recentWindows: [RecentWindowEntry] = []
        var seenWindowKeys = Set<String>()
        let winSQL = """
        SELECT e.app_name, e.window_title, e.url, e.timestamp, sess.declared_task_id
        FROM activity_events e
        LEFT JOIN activity_sessions sess ON e.session_id = sess.id
        WHERE e.timestamp >= ? AND e.timestamp <= ?
          AND e.app_name IS NOT NULL
        ORDER BY e.timestamp DESC
        LIMIT 200;
        """
        try queryStatementLocked(winSQL, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, sinceMs)
            sqlite3_bind_int64(stmt, 2, untilMs)
        }, onRow: { stmt in
            let app = readText(stmt, 0) ?? "Unknown"
            let title = readText(stmt, 1)
            let url = readText(stmt, 2)
            let ts = sqlite3_column_int64(stmt, 3)
            let taskId = readText(stmt, 4)
            let key = "\(app)|\(title ?? "")|\(url ?? "")"
            if seenWindowKeys.insert(key).inserted, recentWindows.count < 25 {
                recentWindows.append(RecentWindowEntry(
                    appName: app,
                    windowTitle: title,
                    url: url,
                    lastSeenAt: ts,
                    declaredTaskId: taskId
                ))
            }
        })

        // Recent OCR highlights capped at maxOCRChars
        var ocrHighlights: [AgentOCRSnippet] = []
        var remainingChars = max(0, maxOCRChars)
        let ocrSQL = """
        SELECT f.snapshot_id, f.session_id, f.created_at, s.app_name, s.window_title, f.text, f.char_count
        FROM activity_ocr_frames f
        LEFT JOIN activity_snapshots s ON f.snapshot_id = s.id
        WHERE f.created_at >= ? AND f.created_at <= ?
          AND f.char_count > 0
        ORDER BY f.created_at DESC
        LIMIT 40;
        """
        try queryStatementLocked(ocrSQL, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, sinceMs)
            sqlite3_bind_int64(stmt, 2, untilMs)
        }, onRow: { stmt in
            guard remainingChars > 0 else { return }
            let snapshotId = readText(stmt, 0) ?? ""
            let sessionId = readText(stmt, 1) ?? ""
            let ts = sqlite3_column_int64(stmt, 2)
            let app = readText(stmt, 3)
            let title = readText(stmt, 4)
            let rawText = (readText(stmt, 5) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { return }

            let snippetText: String
            if rawText.count > remainingChars {
                snippetText = String(rawText.prefix(remainingChars)) + "…"
                remainingChars = 0
            } else {
                snippetText = rawText
                remainingChars -= rawText.count
            }

            ocrHighlights.append(AgentOCRSnippet(
                snapshotId: snapshotId,
                sessionId: sessionId,
                timestamp: ts,
                appName: app,
                windowTitle: title,
                text: snippetText,
                charCount: rawText.count
            ))
        })

        return AgentActivityContext(
            sinceMs: sinceMs,
            untilMs: untilMs,
            sessionCount: sessions.count,
            eventCount: eventCount,
            snapshotCount: snapshotCount,
            ocrFrameCount: ocrFrameCount,
            totalActiveMs: totalActiveMs,
            sessions: sessions,
            recentWindows: recentWindows,
            ocrHighlights: ocrHighlights
        )
    }

    public func queryDigest(sinceMs: Int64, untilMs: Int64, hours: Int) throws -> ActivityDigestSummary {
        lock.lock()
        defer { lock.unlock() }

        let sessions = try listSessionsLocked(sinceMs: sinceMs, untilMs: untilMs, limit: 1_000)
        var totalActiveMs: Int64 = 0
        var appDurations: [String: Int64] = [:]
        var highlights: [String] = []

        for session in sessions {
            let effectiveMs = session.durationMs
                ?? session.endedAt.map { max(0, $0 - session.startedAt) }
                ?? 0
            totalActiveMs += max(0, effectiveMs)
            let sessionEnd = max(session.endedAt ?? session.updatedAt, session.startedAt)
            for (app, ms) in try perAppDurationsLocked(sessionId: session.id, sessionEndMs: sessionEnd) {
                appDurations[app, default: 0] += ms
            }
            if let title = nonEmpty(session.analysisTitle), !highlights.contains(title), highlights.count < 10 {
                highlights.append(title)
            }
        }

        let topApps = appDurations
            .map { ActivityDailySummaryStats.AppDuration(app: $0.key, durationMs: $0.value) }
            .sorted { $0.durationMs > $1.durationMs }
            .prefix(10)
            .map { $0 }

        var domainCounts: [String: Int] = [:]
        try queryStatementLocked(
            "SELECT url FROM activity_events WHERE timestamp >= ? AND timestamp <= ? AND url IS NOT NULL;",
            bind: { stmt in
                sqlite3_bind_int64(stmt, 1, sinceMs)
                sqlite3_bind_int64(stmt, 2, untilMs)
            },
            onRow: { stmt in
                if let rawURL = nonEmpty(readText(stmt, 0)),
                   let host = URLComponents(string: rawURL)?.host?.lowercased(),
                   !host.isEmpty {
                    domainCounts[host, default: 0] += 1
                }
            }
        )
        let topDomains = domainCounts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(10)
            .map(\.key)

        let eventCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_events WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: sinceMs,
            untilMs: untilMs
        )
        let snapshotCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_snapshots WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: sinceMs,
            untilMs: untilMs
        )
        let ocrFrameCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_ocr_frames WHERE created_at >= ? AND created_at <= ?;",
            sinceMs: sinceMs,
            untilMs: untilMs
        )
        let inputTotals = try dayInputTotalsLocked(dayStartMs: sinceMs, dayEndMs: untilMs)

        return ActivityDigestSummary(
            sinceMs: sinceMs,
            untilMs: untilMs,
            hours: max(1, hours),
            sessionCount: sessions.count,
            totalActiveMs: totalActiveMs,
            eventCount: eventCount,
            snapshotCount: snapshotCount,
            ocrFrameCount: ocrFrameCount,
            clickCount: inputTotals.clickCount,
            keypressCount: inputTotals.keypressCount,
            inputEventsPerMinute: DayInputTotals.density(
                clickCount: inputTotals.clickCount,
                keypressCount: inputTotals.keypressCount,
                durationMs: totalActiveMs
            ),
            topApps: topApps,
            topDomains: topDomains,
            highlights: highlights
        )
    }

    /// Alma-compatible OCR-only keyword search (`GET /api/activity-recorder/search/keyword`).
    public func searchOCR(keyword: String, limit: Int = 50) throws -> [OCRActivitySearchResult] {
        lock.lock()
        defer { lock.unlock() }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let maxResults = max(1, limit)
        var results: [OCRActivitySearchResult] = []

        if trimmed.count >= 3 {
            let ftsPhrase = makeFTS5TrigramPhrase(trimmed)
            let sql = """
            SELECT f.id, f.session_id, f.snapshot_id, f.text, f.created_at
            FROM activity_ocr_fts fts
            JOIN activity_ocr_frames f ON f.id = fts.frame_id
            WHERE activity_ocr_fts MATCH ?
            ORDER BY f.created_at DESC
            LIMIT ?;
            """
            try queryStatementLocked(sql, bind: { stmt in
                bindText(stmt, index: 1, value: ftsPhrase)
                sqlite3_bind_int(stmt, 2, Int32(maxResults))
            }, onRow: { stmt in
                results.append(OCRActivitySearchResult(
                    id: readText(stmt, 0) ?? "",
                    sessionId: readText(stmt, 1) ?? "",
                    snapshotId: readText(stmt, 2) ?? "",
                    text: readText(stmt, 3) ?? "",
                    createdAt: sqlite3_column_int64(stmt, 4)
                ))
            })
        } else {
            let pattern = "%\(escapeLike(trimmed.lowercased()))%"
            let sql = """
            SELECT id, session_id, snapshot_id, text, created_at
            FROM activity_ocr_frames
            WHERE LOWER(text) LIKE ? ESCAPE '\\'
            ORDER BY created_at DESC
            LIMIT ?;
            """
            try queryStatementLocked(sql, bind: { stmt in
                bindText(stmt, index: 1, value: pattern)
                sqlite3_bind_int(stmt, 2, Int32(maxResults))
            }, onRow: { stmt in
                results.append(OCRActivitySearchResult(
                    id: readText(stmt, 0) ?? "",
                    sessionId: readText(stmt, 1) ?? "",
                    snapshotId: readText(stmt, 2) ?? "",
                    text: readText(stmt, 3) ?? "",
                    createdAt: sqlite3_column_int64(stmt, 4)
                ))
            })
        }
        return results
    }

    /// Looks up a single snapshot record; used by `GET /api/activity-recorder/snapshot-file?id=`.
    public func snapshot(id: String) throws -> RecordedSnapshot? {
        lock.lock()
        defer { lock.unlock() }

        var found: RecordedSnapshot?
        let sql = """
        SELECT id, session_id, timestamp, file_path, width, height, size_bytes,
               trigger, app_name, window_title, hash_hex, histogram, diff_pct,
               storage_tier, created_at
        FROM activity_snapshots
        WHERE id = ?
        LIMIT 1;
        """
        try queryStatementLocked(sql, bind: { stmt in
            bindText(stmt, index: 1, value: id)
        }, onRow: { stmt in
            let hist = decodeJSON([Double].self, from: readText(stmt, 11))
            let diffPct: Double? = sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 12)
            found = RecordedSnapshot(
                id: readText(stmt, 0) ?? "",
                sessionId: readText(stmt, 1) ?? "",
                timestamp: sqlite3_column_int64(stmt, 2),
                filePath: readText(stmt, 3) ?? "",
                width: Int(sqlite3_column_int(stmt, 4)),
                height: Int(sqlite3_column_int(stmt, 5)),
                sizeBytes: sqlite3_column_int64(stmt, 6),
                trigger: readText(stmt, 7) ?? "heartbeat",
                appName: readText(stmt, 8),
                windowTitle: readText(stmt, 9),
                hashHex: readText(stmt, 10),
                histogram: hist,
                diffPct: diffPct,
                storageTier: readText(stmt, 13) ?? "hot",
                createdAt: sqlite3_column_int64(stmt, 14)
            )
        })
        return found
    }

    /// Day-level click/keypress counters plus session duration, for input density (`click`/`keypress` counts only).
    public func dayInputTotals(dayStartMs: Int64, dayEndMs: Int64) throws -> DayInputTotals {
        lock.lock()
        defer { lock.unlock() }
        return try dayInputTotalsLocked(dayStartMs: dayStartMs, dayEndMs: dayEndMs)
    }

    /// Derives Alma-compatible daily summary stats from the local tables (no LLM, no stored summary row).
    public func dailySummaryStats(dateKey: String) throws -> ActivityDailySummaryStats {
        lock.lock()
        defer { lock.unlock() }
        return try dailySummaryStatsLocked(dateKey: dateKey)
    }

    /// Derives Alma-compatible weekly summary stats over the ISO week that contains `weekKey`.
    public func weeklySummaryStats(weekKey: String) throws -> ActivityWeeklySummaryStats {
        lock.lock()
        defer { lock.unlock() }
        return try weeklySummaryStatsLocked(weekKey: weekKey)
    }

    public func todayCounts(dayStartMs: Int64, dayEndMs: Int64) throws -> (sessions: Int, events: Int, snapshots: Int, ocrFrames: Int) {
        lock.lock()
        defer { lock.unlock() }
        let sessions = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_sessions WHERE started_at >= ? AND started_at <= ?;",
            sinceMs: dayStartMs,
            untilMs: dayEndMs
        )
        let events = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_events WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: dayStartMs,
            untilMs: dayEndMs
        )
        let snapshots = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_snapshots WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: dayStartMs,
            untilMs: dayEndMs
        )
        let ocr = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_ocr_frames WHERE created_at >= ? AND created_at <= ?;",
            sinceMs: dayStartMs,
            untilMs: dayEndMs
        )
        return (sessions, events, snapshots, ocr)
    }

    public func countMeetingSessions(dayStartMs: Int64, dayEndMs: Int64) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        return try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_sessions WHERE is_meeting = 1 AND started_at >= ? AND started_at <= ?;",
            sinceMs: dayStartMs,
            untilMs: dayEndMs
        )
    }

    /// Returns distinct `YYYY-MM-DD` (UTC+8) date strings with sessions in `activity_sessions`, sorted descending.
    public func listSessionDayStrings() throws -> [String] {
        lock.lock()
        defer { lock.unlock() }
        var seen = Set<String>()
        let sql = "SELECT DISTINCT CAST((started_at + 28800000) / 86400000 AS INTEGER) AS day_idx FROM activity_sessions WHERE started_at >= 0 ORDER BY day_idx DESC;"
        try queryStatementLocked(sql, bind: { _ in }, onRow: { stmt in
            let dayIndex = sqlite3_column_int64(stmt, 0)
            let noonEpoch = TimeInterval(dayIndex) * 86_400.0 - 28_800.0 + 43_200.0
            let date = Date(timeIntervalSince1970: noonEpoch)
            seen.insert(DayHelmDateFormatting.dayString(from: date))
        })
        return seen.sorted(by: >)
    }

    public func currentOpenSessionId() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try currentOpenSessionIdLocked()
    }

    public func recorderStorageStats() throws -> RecorderStorageStats {
        lock.lock()
        defer { lock.unlock() }

        func scalarInt(_ sql: String) throws -> Int {
            var val = 0
            try queryStatementLocked(sql, bind: { _ in }, onRow: { stmt in
                val = Int(sqlite3_column_int64(stmt, 0))
            })
            return val
        }

        let totalSessions = try scalarInt("SELECT COUNT(*) FROM activity_sessions;")
        let totalEvents = try scalarInt("SELECT COUNT(*) FROM activity_events;")
        let totalSnapshots = try scalarInt("SELECT COUNT(*) FROM activity_snapshots;")
        let totalOCRFrames = try scalarInt("SELECT COUNT(*) FROM activity_ocr_frames;")

        var usedBytes: Int64 = 0
        try queryStatementLocked(
            "SELECT COALESCE(SUM(size_bytes), 0) FROM activity_snapshots WHERE storage_tier != 'pruned';",
            bind: { _ in },
            onRow: { stmt in
                usedBytes = sqlite3_column_int64(stmt, 0)
            }
        )

        var activeId: String?
        var activeStartedAt: Int64?
        try queryStatementLocked(
            "SELECT id, started_at FROM activity_sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;",
            bind: { _ in },
            onRow: { stmt in
                activeId = readText(stmt, 0)
                activeStartedAt = sqlite3_column_int64(stmt, 1)
            }
        )

        return RecorderStorageStats(
            totalSessions: totalSessions,
            totalEvents: totalEvents,
            totalSnapshots: totalSnapshots,
            totalOCRFrames: totalOCRFrames,
            usedSnapshotBytes: usedBytes,
            activeSessionId: activeId,
            activeSessionStartedAt: activeStartedAt
        )
    }

    public func searchSessions(keyword: String, limit: Int = 100) throws -> [RecordedSessionSummary] {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try listSessions(limit: limit)
        }

        lock.lock()
        defer { lock.unlock() }

        let pattern = "%\(escapeLike(trimmed.lowercased()))%"
        let maxResults = max(1, limit)
        let sql = """
        SELECT DISTINCT s.id, s.started_at, s.ended_at, s.duration_ms, s.trigger_kind, s.app_names,
               s.event_count, s.snapshot_count, s.total_bytes, s.analysis_status,
               s.analysis_title, s.analysis_description, s.analysis_model, s.analysis_error,
               s.analyzed_at, s.worth_memory, s.worth_knowledge, s.is_meeting, s.storage_tier,
               s.entities, s.topics, s.project, s.highlights, s.declared_task_id, s.created_at, s.updated_at,
               s.click_count, s.keypress_count
        FROM activity_sessions s
        WHERE LOWER(COALESCE(s.analysis_title, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(s.analysis_description, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(s.app_names, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(s.project, '')) LIKE ? ESCAPE '\\'
           OR LOWER(COALESCE(s.declared_task_id, '')) LIKE ? ESCAPE '\\'
           OR EXISTS (
               SELECT 1 FROM activity_events e
               WHERE e.session_id = s.id
                 AND (
                     LOWER(COALESCE(e.app_name, '')) LIKE ? ESCAPE '\\'
                     OR LOWER(COALESCE(e.window_title, '')) LIKE ? ESCAPE '\\'
                     OR LOWER(COALESCE(e.url, '')) LIKE ? ESCAPE '\\'
                 )
           )
           OR EXISTS (
               SELECT 1 FROM activity_ocr_frames f
               WHERE f.session_id = s.id
                 AND LOWER(f.text) LIKE ? ESCAPE '\\'
           )
        ORDER BY s.started_at DESC
        LIMIT ?;
        """

        var results: [RecordedSessionSummary] = []
        try queryStatementLocked(sql, bind: { stmt in
            for idx in Int32(1)...Int32(9) {
                bindText(stmt, index: idx, value: pattern)
            }
            sqlite3_bind_int(stmt, 10, Int32(maxResults))
        }, onRow: { stmt in
            results.append(readSessionRow(stmt))
        })
        return results
    }

    public func journalMode() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        var mode = ""
        try queryStatementLocked("PRAGMA journal_mode;", bind: { _ in }, onRow: { stmt in
            mode = readText(stmt, 0) ?? ""
        })
        return mode
    }

    public func integrityCheck() throws -> String {
        lock.lock()
        defer { lock.unlock() }
        var result = ""
        try queryStatementLocked("PRAGMA integrity_check;", bind: { _ in }, onRow: { stmt in
            result = readText(stmt, 0) ?? ""
        })
        return result
    }

    // MARK: - Pruning & Purge

    /// Lists snapshots older than `cutoffMs` that still sit at the given storage tier.
    /// Used by the recorder to downscale old frames before final retention pruning.
    public func listSnapshotsForMaintenance(
        olderThanMs cutoffMs: Int64,
        storageTier: String = "hot",
        limit: Int = 500
    ) throws -> [SnapshotMaintenanceRecord] {
        lock.lock()
        defer { lock.unlock() }

        var records: [SnapshotMaintenanceRecord] = []
        let sql = """
        SELECT id, file_path, timestamp, width, height, size_bytes, storage_tier
        FROM activity_snapshots
        WHERE timestamp < ? AND storage_tier = ?
        ORDER BY timestamp ASC
        LIMIT ?;
        """
        try queryStatementLocked(sql, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, cutoffMs)
            bindText(stmt, index: 2, value: storageTier)
            sqlite3_bind_int(stmt, 3, Int32(max(1, limit)))
        }, onRow: { stmt in
            records.append(SnapshotMaintenanceRecord(
                id: readText(stmt, 0) ?? "",
                filePath: readText(stmt, 1) ?? "",
                timestamp: sqlite3_column_int64(stmt, 2),
                width: Int(sqlite3_column_int(stmt, 3)),
                height: Int(sqlite3_column_int(stmt, 4)),
                sizeBytes: sqlite3_column_int64(stmt, 5),
                storageTier: readText(stmt, 6) ?? "hot"
            ))
        })
        return records
    }

    /// Updates a snapshot row after its JPEG has been re-encoded at a smaller size.
    public func updateSnapshotStorage(
        snapshotId: String,
        width: Int,
        height: Int,
        sizeBytes: Int64,
        storageTier: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let sql = """
        UPDATE activity_snapshots
        SET width = ?, height = ?, size_bytes = ?, storage_tier = ?
        WHERE id = ?;
        """
        try runStatementLocked(sql) { stmt in
            sqlite3_bind_int(stmt, 1, Int32(max(0, width)))
            sqlite3_bind_int(stmt, 2, Int32(max(0, height)))
            sqlite3_bind_int64(stmt, 3, max(0, sizeBytes))
            bindText(stmt, index: 4, value: storageTier)
            bindText(stmt, index: 5, value: snapshotId)
        }
    }

    @discardableResult
    public func pruneOldSnapshots(
        olderThanDays: Int,
        snapshotsRootDir: URL,
        now: Date = Date()
    ) throws -> (deletedFiles: Int, deletedBytes: Int64) {
        lock.lock()
        defer { lock.unlock() }

        let retentionDays = max(1, olderThanDays)
        let cutoffDate = now.addingTimeInterval(-TimeInterval(retentionDays) * 86_400)
        let cutoffDay = DayHelmDateFormatting.dayString(from: cutoffDate)
        let cutoffMs = Int64(cutoffDate.timeIntervalSince1970 * 1000)

        var deletedFiles = 0
        var deletedBytes: Int64 = 0
        let fm = FileManager.default

        if fm.fileExists(atPath: snapshotsRootDir.path) {
            let dayDirs = (try? fm.contentsOfDirectory(
                at: snapshotsRootDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for dayDir in dayDirs {
                let isDir = (try? dayDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                guard isDir else { continue }
                let folderName = dayDir.lastPathComponent
                if folderName < cutoffDay {
                    let files = (try? fm.contentsOfDirectory(
                        at: dayDir,
                        includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    for file in files {
                        let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        try fm.removeItem(at: file)
                        deletedFiles += 1
                        deletedBytes += size
                    }
                    try? fm.removeItem(at: dayDir)
                }
            }
        }

        let updateSQL = """
        UPDATE activity_snapshots
        SET storage_tier = 'pruned', size_bytes = 0
        WHERE timestamp < ? AND storage_tier != 'pruned';
        """
        try runStatementLocked(updateSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, cutoffMs)
        }

        return (deletedFiles, deletedBytes)
    }

    @discardableResult
    public func enforceSnapshotStorageCap(
        maxTotalBytes: Int64,
        targetBytes: Int64,
        snapshotsRootDir: URL
    ) throws -> (deletedFiles: Int, deletedBytes: Int64) {
        lock.lock()
        defer { lock.unlock() }

        guard maxTotalBytes > 0 else { return (0, 0) }
        var totalBytes: Int64 = 0
        try queryStatementLocked(
            "SELECT COALESCE(SUM(size_bytes), 0) FROM activity_snapshots WHERE storage_tier != 'pruned';",
            bind: { _ in },
            onRow: { stmt in
                totalBytes = sqlite3_column_int64(stmt, 0)
            }
        )
        guard totalBytes > maxTotalBytes else { return (0, 0) }

        let goalBytes = min(maxTotalBytes, max(0, targetBytes))
        var candidates: [(id: String, filePath: String, sizeBytes: Int64)] = []
        try queryStatementLocked(
            "SELECT id, file_path, size_bytes FROM activity_snapshots WHERE storage_tier != 'pruned' ORDER BY timestamp ASC, created_at ASC;",
            bind: { _ in },
            onRow: { stmt in
                if let id = readText(stmt, 0), let path = readText(stmt, 1) {
                    candidates.append((id: id, filePath: path, sizeBytes: sqlite3_column_int64(stmt, 2)))
                }
            }
        )

        var remaining = totalBytes
        var deletedFiles = 0
        var deletedBytes: Int64 = 0
        let fm = FileManager.default
        let resolvedRoot = snapshotsRootDir.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"

        for row in candidates {
            guard remaining > goalBytes else { break }
            let candidateURL = URL(fileURLWithPath: row.filePath).standardizedFileURL.resolvingSymlinksInPath()
            if (candidateURL.path == resolvedRoot.path || candidateURL.path.hasPrefix(rootPrefix)),
               fm.fileExists(atPath: candidateURL.path) {
                let actualSize = Int64((try? candidateURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                if (try? fm.removeItem(at: candidateURL)) != nil {
                    deletedFiles += 1
                    deletedBytes += actualSize > 0 ? actualSize : row.sizeBytes
                }
            }
            try runStatementLocked("UPDATE activity_snapshots SET storage_tier = 'pruned', size_bytes = 0 WHERE id = ?;") { stmt in
                bindText(stmt, index: 1, value: row.id)
            }
            remaining -= max(0, row.sizeBytes)
        }

        return (deletedFiles, deletedBytes)
    }

    @discardableResult
    public func purgeRecords(
        before cutoffDate: Date?,
        snapshotsRootDir: URL
    ) throws -> (deletedFiles: Int, deletedBytes: Int64) {
        lock.lock()
        defer { lock.unlock() }

        var deletedFiles = 0
        var deletedBytes: Int64 = 0
        let fm = FileManager.default

        if let cutoffDate {
            let cutoffDay = DayHelmDateFormatting.dayString(from: cutoffDate)
            let cutoffMs = Int64(cutoffDate.timeIntervalSince1970 * 1000)

            try runStatementLocked("DELETE FROM activity_ocr_frames WHERE created_at < ?;") { stmt in
                sqlite3_bind_int64(stmt, 1, cutoffMs)
            }
            try runStatementLocked("DELETE FROM activity_snapshots WHERE timestamp < ?;") { stmt in
                sqlite3_bind_int64(stmt, 1, cutoffMs)
            }
            try runStatementLocked("DELETE FROM activity_events WHERE timestamp < ?;") { stmt in
                sqlite3_bind_int64(stmt, 1, cutoffMs)
            }
            try runStatementLocked("DELETE FROM activity_sessions WHERE COALESCE(ended_at, updated_at, started_at) < ?;") { stmt in
                sqlite3_bind_int64(stmt, 1, cutoffMs)
            }

            if fm.fileExists(atPath: snapshotsRootDir.path) {
                let dayDirs = (try? fm.contentsOfDirectory(
                    at: snapshotsRootDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                )) ?? []
                for dayDir in dayDirs where dayDir.lastPathComponent < cutoffDay {
                    let files = (try? fm.contentsOfDirectory(
                        at: dayDir,
                        includingPropertiesForKeys: [.fileSizeKey],
                        options: [.skipsHiddenFiles]
                    )) ?? []
                    for file in files {
                        let size = Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                        try fm.removeItem(at: file)
                        deletedFiles += 1
                        deletedBytes += size
                    }
                    try? fm.removeItem(at: dayDir)
                }
            }
        } else {
            try executeLocked("DELETE FROM activity_ocr_frames;")
            try executeLocked("DELETE FROM activity_snapshots;")
            try executeLocked("DELETE FROM activity_events;")
            try executeLocked("DELETE FROM activity_sessions;")

            if fm.fileExists(atPath: snapshotsRootDir.path),
               let enumerator = fm.enumerator(
                   at: snapshotsRootDir,
                   includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                   options: [.skipsHiddenFiles]
               ) {
                var urls: [URL] = []
                for case let url as URL in enumerator {
                    if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        urls.append(url)
                    }
                }
                for url in urls {
                    let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    try fm.removeItem(at: url)
                    deletedFiles += 1
                    deletedBytes += size
                }
                try? fm.removeItem(at: snapshotsRootDir)
            }
        }

        syncedSessionIds.removeAll()
        cachedOpenSession = nil
        try? executeLocked("VACUUM;")
        return (deletedFiles, deletedBytes)
    }

    public static func estimateTokenCount(_ text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let words = trimmed.split { $0.isWhitespace || $0.isNewline }.count
        let cjkCount = trimmed.unicodeScalars.filter { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
                || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value)
        }.count
        return max(1, words + cjkCount)
    }

    // MARK: - Private SQLite Implementation (must hold lock)

    private func createSchemaLocked() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS activity_sessions (
                id TEXT PRIMARY KEY,
                started_at INTEGER NOT NULL,
                ended_at INTEGER,
                duration_ms INTEGER,
                trigger_kind TEXT NOT NULL DEFAULT 'idle',
                app_names TEXT NOT NULL DEFAULT '[]',
                event_count INTEGER NOT NULL DEFAULT 0,
                click_count INTEGER NOT NULL DEFAULT 0,
                keypress_count INTEGER NOT NULL DEFAULT 0,
                snapshot_count INTEGER NOT NULL DEFAULT 0,
                total_bytes INTEGER NOT NULL DEFAULT 0,
                analysis_status TEXT NOT NULL DEFAULT 'pending',
                analysis_title TEXT,
                analysis_description TEXT,
                analysis_model TEXT,
                analysis_error TEXT,
                analyzed_at INTEGER,
                worth_memory INTEGER NOT NULL DEFAULT 0,
                worth_knowledge INTEGER NOT NULL DEFAULT 0,
                is_meeting INTEGER NOT NULL DEFAULT 0,
                storage_tier TEXT NOT NULL DEFAULT 'hot',
                entities TEXT NOT NULL DEFAULT '{}',
                topics TEXT NOT NULL DEFAULT '[]',
                project TEXT,
                highlights TEXT NOT NULL DEFAULT '[]',
                declared_task_id TEXT,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS activity_events (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                kind TEXT NOT NULL,
                app_name TEXT,
                window_title TEXT,
                url TEXT,
                data TEXT NOT NULL DEFAULT '{}',
                created_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS activity_snapshots (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                timestamp INTEGER NOT NULL,
                file_path TEXT NOT NULL,
                width INTEGER NOT NULL DEFAULT 0,
                height INTEGER NOT NULL DEFAULT 0,
                size_bytes INTEGER NOT NULL DEFAULT 0,
                trigger TEXT NOT NULL DEFAULT 'heartbeat',
                app_name TEXT,
                window_title TEXT,
                hash_hex TEXT,
                histogram TEXT,
                diff_pct REAL,
                storage_tier TEXT NOT NULL DEFAULT 'hot',
                created_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS activity_ocr_frames (
                id TEXT PRIMARY KEY,
                snapshot_id TEXT NOT NULL,
                session_id TEXT NOT NULL,
                text TEXT NOT NULL,
                char_count INTEGER NOT NULL DEFAULT 0,
                token_count INTEGER NOT NULL DEFAULT 0,
                created_at INTEGER NOT NULL
            );
            """,
            "CREATE INDEX IF NOT EXISTS idx_activity_sessions_started_at ON activity_sessions(started_at DESC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_sessions_open ON activity_sessions(started_at DESC) WHERE ended_at IS NULL;",
            "CREATE INDEX IF NOT EXISTS idx_activity_events_session_ts ON activity_events(session_id, timestamp ASC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_events_ts ON activity_events(timestamp DESC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_snapshots_session_ts ON activity_snapshots(session_id, timestamp ASC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_snapshots_ts ON activity_snapshots(timestamp DESC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_snapshots_tier_ts ON activity_snapshots(storage_tier, timestamp ASC, size_bytes);",
            "CREATE INDEX IF NOT EXISTS idx_activity_ocr_session ON activity_ocr_frames(session_id);",
            "CREATE INDEX IF NOT EXISTS idx_activity_ocr_snapshot ON activity_ocr_frames(snapshot_id);",
            "CREATE INDEX IF NOT EXISTS idx_activity_ocr_created_at ON activity_ocr_frames(created_at DESC);"
        ]

        for sql in statements {
            try executeLocked(sql)
        }

        // Forward compatibility if upgrading an older database file
        try ensureColumnExistsLocked(table: "activity_sessions", column: "declared_task_id", definition: "TEXT")
        try ensureColumnExistsLocked(table: "activity_sessions", column: "click_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try ensureColumnExistsLocked(table: "activity_sessions", column: "keypress_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try ensureColumnExistsLocked(table: "activity_events", column: "window_title", definition: "TEXT")

        // FTS5 trigram full-text index for OCR frames (CJK + English substring acceleration)
        try executeLocked("""
        CREATE VIRTUAL TABLE IF NOT EXISTS activity_ocr_fts USING fts5(
            frame_id UNINDEXED,
            session_id UNINDEXED,
            snapshot_id UNINDEXED,
            text,
            tokenize='trigram'
        );
        """)
        try executeLocked("""
        CREATE TRIGGER IF NOT EXISTS trg_activity_ocr_ai AFTER INSERT ON activity_ocr_frames BEGIN
            INSERT INTO activity_ocr_fts(frame_id, session_id, snapshot_id, text)
            VALUES (new.id, new.session_id, new.snapshot_id, new.text);
        END;
        """)
        try executeLocked("""
        CREATE TRIGGER IF NOT EXISTS trg_activity_ocr_ad AFTER DELETE ON activity_ocr_frames BEGIN
            DELETE FROM activity_ocr_fts WHERE frame_id = old.id;
        END;
        """)
        try executeLocked("""
        INSERT INTO activity_ocr_fts(frame_id, session_id, snapshot_id, text)
        SELECT f.id, f.session_id, f.snapshot_id, f.text
        FROM activity_ocr_frames f
        WHERE f.id NOT IN (SELECT frame_id FROM activity_ocr_fts);
        """)
    }

    private func ensureColumnExistsLocked(table: String, column: String, definition: String) throws {
        var found = false
        try queryStatementLocked("PRAGMA table_info(\(table));", bind: { _ in }, onRow: { stmt in
            if readText(stmt, 1) == column {
                found = true
            }
        })
        if !found {
            try executeLocked("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
        }
    }

    private func ensureActiveSessionLocked(
        atMs timestampMs: Int64,
        triggerKind: String,
        appName: String?,
        declaredTaskId: String?,
        project: String?
    ) throws -> String {
        if cachedOpenSession == nil,
           let openId = try currentOpenSessionIdLocked(),
           let existing = try fetchSessionSummaryLocked(sessionId: openId) {
            let lastMs = try latestSessionTimestampLocked(sessionId: openId) ?? existing.startedAt
            cachedOpenSession = (summary: existing, lastActivityMs: lastMs)
        }

        if let cached = cachedOpenSession {
            let openId = cached.summary.id
            let lastMs = cached.lastActivityMs
            let lastDay = DayHelmDateFormatting.dayString(from: Date(timeIntervalSince1970: TimeInterval(lastMs) / 1000.0))
            let newDay = DayHelmDateFormatting.dayString(from: Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0))
            let gapMs = timestampMs - lastMs

            if lastDay == newDay && gapMs <= sessionIdleGapMs {
                return openId
            }

            try closeSessionLocked(sessionId: openId, endedAtMs: lastMs)
        }

        let newId = makeSessionId(timestampMs: timestampMs)
        let initialApps = nonEmpty(appName).map { [$0] } ?? []
        let appNamesJSON = encodeJSONString(initialApps) ?? "[]"
        let effectiveProject = nonEmpty(project) ?? nonEmpty(declaredTaskId)

        let sql = """
        INSERT INTO activity_sessions (
            id, started_at, ended_at, duration_ms, trigger_kind, app_names,
            event_count, snapshot_count, total_bytes, analysis_status,
            project, declared_task_id, created_at, updated_at
        ) VALUES (?, ?, NULL, 0, ?, ?, 0, 0, 0, 'pending', ?, ?, ?, ?);
        """
        try runStatementLocked(sql) { stmt in
            bindText(stmt, index: 1, value: newId)
            sqlite3_bind_int64(stmt, 2, timestampMs)
            bindText(stmt, index: 3, value: triggerKind)
            bindText(stmt, index: 4, value: appNamesJSON)
            bindOptionalText(stmt, index: 5, value: effectiveProject)
            bindOptionalText(stmt, index: 6, value: nonEmpty(declaredTaskId))
            sqlite3_bind_int64(stmt, 7, timestampMs)
            sqlite3_bind_int64(stmt, 8, timestampMs)
        }
        syncedSessionIds.insert(newId)
        cachedOpenSession = (
            summary: RecordedSessionSummary(
                id: newId,
                startedAt: timestampMs,
                endedAt: nil,
                durationMs: 0,
                triggerKind: triggerKind,
                appNames: initialApps,
                eventCount: 0,
                snapshotCount: 0,
                totalBytes: 0,
                analysisStatus: "pending",
                project: effectiveProject,
                declaredTaskId: nonEmpty(declaredTaskId),
                createdAt: timestampMs,
                updatedAt: timestampMs
            ),
            lastActivityMs: timestampMs
        )

        return newId
    }

    private func currentOpenSessionIdLocked() throws -> String? {
        var openId: String?
        let sql = "SELECT id FROM activity_sessions WHERE ended_at IS NULL ORDER BY started_at DESC LIMIT 1;"
        try queryStatementLocked(sql, bind: { _ in }, onRow: { stmt in
            openId = readText(stmt, 0)
        })
        return openId
    }

    private func latestSessionTimestampLocked(sessionId: String) throws -> Int64? {
        var maxTs: Int64?
        let sql = """
        SELECT MAX(ts) FROM (
            SELECT started_at AS ts FROM activity_sessions WHERE id = ?
            UNION ALL
            SELECT MAX(timestamp) AS ts FROM activity_events WHERE session_id = ?
            UNION ALL
            SELECT MAX(timestamp) AS ts FROM activity_snapshots WHERE session_id = ?
        );
        """
        try queryStatementLocked(sql, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
            bindText(stmt, index: 2, value: sessionId)
            bindText(stmt, index: 3, value: sessionId)
        }, onRow: { stmt in
            if sqlite3_column_type(stmt, 0) != SQLITE_NULL {
                maxTs = sqlite3_column_int64(stmt, 0)
            }
        })
        return maxTs
    }

    private func refreshSessionMetadataLocked(
        sessionId: String,
        activityAtMs: Int64,
        addedAppName: String?,
        addedEventKind: String?,
        addedEventInputCount: Int,
        addedSnapshotBytes: Int64?,
        declaredTaskId: String?,
        project: String?
    ) throws {
        let existing: RecordedSessionSummary
        if let cached = cachedOpenSession, cached.summary.id == sessionId {
            existing = cached.summary
        } else if let fetched = try fetchSessionSummaryLocked(sessionId: sessionId) {
            existing = fetched
        } else {
            return
        }

        var apps = existing.appNames
        if let app = nonEmpty(addedAppName), !apps.contains(app) {
            apps.append(app)
        }

        let eventCount: Int
        let clickCount: Int
        let keypressCount: Int
        let snapshotCount: Int
        let totalBytes: Int64

        if syncedSessionIds.contains(sessionId) {
            eventCount = existing.eventCount + (addedEventKind != nil ? 1 : 0)
            clickCount = existing.clickCount + (addedEventKind == "click" ? addedEventInputCount : 0)
            keypressCount = existing.keypressCount + (addedEventKind == "keypress" ? addedEventInputCount : 0)
            if let bytes = addedSnapshotBytes {
                snapshotCount = existing.snapshotCount + 1
                totalBytes = existing.totalBytes + max(0, bytes)
            } else {
                snapshotCount = existing.snapshotCount
                totalBytes = existing.totalBytes
            }
        } else {
            fullCounterResyncCount += 1
            syncedSessionIds.insert(sessionId)

            var ec = 0
            var cc = 0
            var kc = 0
            try queryStatementLocked("""
            SELECT COUNT(*),
                   COALESCE(SUM(CASE WHEN kind = 'click' THEN MAX(1, COALESCE(CAST(json_extract(data, '$.count') AS INTEGER), 1)) ELSE 0 END), 0),
                   COALESCE(SUM(CASE WHEN kind = 'keypress' THEN MAX(1, COALESCE(CAST(json_extract(data, '$.count') AS INTEGER), 1)) ELSE 0 END), 0)
            FROM activity_events WHERE session_id = ?;
            """, bind: { stmt in
                bindText(stmt, index: 1, value: sessionId)
            }, onRow: { stmt in
                ec = Int(sqlite3_column_int64(stmt, 0))
                cc = Int(sqlite3_column_int64(stmt, 1))
                kc = Int(sqlite3_column_int64(stmt, 2))
            })

            var sc = 0
            var tb: Int64 = 0
            try queryStatementLocked("SELECT COUNT(*), COALESCE(SUM(size_bytes), 0) FROM activity_snapshots WHERE session_id = ?;", bind: { stmt in
                bindText(stmt, index: 1, value: sessionId)
            }, onRow: { stmt in
                sc = Int(sqlite3_column_int64(stmt, 0))
                tb = sqlite3_column_int64(stmt, 1)
            })

            eventCount = ec
            clickCount = cc
            keypressCount = kc
            snapshotCount = sc
            totalBytes = tb
        }

        let effectiveEnd = max(existing.endedAt ?? existing.startedAt, activityAtMs)
        let durationMs = max(0, effectiveEnd - existing.startedAt)
        let resolvedTaskId = nonEmpty(declaredTaskId) ?? existing.declaredTaskId
        let resolvedProject = nonEmpty(project) ?? existing.project ?? resolvedTaskId
        let appsJSON = encodeJSONString(apps) ?? "[]"

        let updatedAtMs = max(existing.updatedAt, activityAtMs)
        let updateSQL = """
        UPDATE activity_sessions
        SET app_names = ?,
            event_count = ?,
            click_count = ?,
            keypress_count = ?,
            snapshot_count = ?,
            total_bytes = ?,
            duration_ms = ?,
            project = ?,
            declared_task_id = ?,
            updated_at = ?
        WHERE id = ?;
        """
        try runStatementLocked(updateSQL) { stmt in
            bindText(stmt, index: 1, value: appsJSON)
            sqlite3_bind_int(stmt, 2, Int32(eventCount))
            sqlite3_bind_int(stmt, 3, Int32(clickCount))
            sqlite3_bind_int(stmt, 4, Int32(keypressCount))
            sqlite3_bind_int(stmt, 5, Int32(snapshotCount))
            sqlite3_bind_int64(stmt, 6, totalBytes)
            sqlite3_bind_int64(stmt, 7, durationMs)
            bindOptionalText(stmt, index: 8, value: resolvedProject)
            bindOptionalText(stmt, index: 9, value: resolvedTaskId)
            sqlite3_bind_int64(stmt, 10, updatedAtMs)
            bindText(stmt, index: 11, value: sessionId)
        }

        if existing.endedAt == nil {
            let prevLastMs = (cachedOpenSession?.summary.id == sessionId) ? (cachedOpenSession?.lastActivityMs ?? existing.startedAt) : existing.startedAt
            let updatedSummary = RecordedSessionSummary(
                id: existing.id,
                startedAt: existing.startedAt,
                endedAt: nil,
                durationMs: durationMs,
                triggerKind: existing.triggerKind,
                appNames: apps,
                eventCount: eventCount,
                snapshotCount: snapshotCount,
                totalBytes: totalBytes,
                analysisStatus: existing.analysisStatus,
                analysisTitle: existing.analysisTitle,
                analysisDescription: existing.analysisDescription,
                analysisModel: existing.analysisModel,
                analysisError: existing.analysisError,
                analyzedAt: existing.analyzedAt,
                worthMemory: existing.worthMemory,
                worthKnowledge: existing.worthKnowledge,
                isMeeting: existing.isMeeting,
                storageTier: existing.storageTier,
                entities: existing.entities,
                topics: existing.topics,
                project: resolvedProject,
                highlights: existing.highlights,
                declaredTaskId: resolvedTaskId,
                createdAt: existing.createdAt,
                updatedAt: updatedAtMs,
                clickCount: clickCount,
                keypressCount: keypressCount
            )
            cachedOpenSession = (summary: updatedSummary, lastActivityMs: max(prevLastMs, activityAtMs))
        }

        let shouldSynthesize = existing.analyzedAt.map { activityAtMs - $0 >= 30_000 } ?? true
        if shouldSynthesize {
            try synthesizeSessionSummaryLocked(sessionId: sessionId, nowMs: activityAtMs)
        }
    }

    private func closeSessionLocked(sessionId: String, endedAtMs: Int64) throws {
        let existing: RecordedSessionSummary
        if let cached = cachedOpenSession, cached.summary.id == sessionId {
            existing = cached.summary
        } else if let fetched = try fetchSessionSummaryLocked(sessionId: sessionId) {
            existing = fetched
        } else {
            return
        }
        let finalEnd = max(existing.startedAt, endedAtMs)
        let durationMs = max(0, finalEnd - existing.startedAt)

        try runStatementLocked("""
        UPDATE activity_sessions
        SET ended_at = ?, duration_ms = ?, updated_at = ?
        WHERE id = ?;
        """) { stmt in
            sqlite3_bind_int64(stmt, 1, finalEnd)
            sqlite3_bind_int64(stmt, 2, durationMs)
            sqlite3_bind_int64(stmt, 3, max(existing.updatedAt, finalEnd))
            bindText(stmt, index: 4, value: sessionId)
        }

        if cachedOpenSession?.summary.id == sessionId {
            cachedOpenSession = nil
        }

        try synthesizeSessionSummaryLocked(sessionId: sessionId, nowMs: finalEnd)
    }

    private func synthesizeSessionSummaryLocked(sessionId: String, nowMs: Int64) throws {
        let session: RecordedSessionSummary
        if let cached = cachedOpenSession, cached.summary.id == sessionId {
            session = cached.summary
        } else if let fetched = try fetchSessionSummaryLocked(sessionId: sessionId) {
            session = fetched
        } else {
            return
        }

        var titleCounts: [(key: String, count: Int)] = []
        var countsByKey: [String: Int] = [:]
        var orderedKeys: [String] = []

        var orderedApps: [String] = []
        var orderedDomains: [String] = []
        var isMeeting = session.isMeeting
        var extractedRepos: [String] = []
        var extractedPRs: [String] = []
        var extractedLocalPorts: [String] = []

        func collectSignals(app: String?, title: String?, url: String?) {
            if !isMeeting && Self.matchesMeetingSignal(appName: app, windowTitle: title, url: url) {
                isMeeting = true
            }
            for text in [title, url].compactMap({ $0 }) {
                Self.extractRegexEntities(
                    from: text,
                    repos: &extractedRepos,
                    prs: &extractedPRs,
                    localPorts: &extractedLocalPorts
                )
            }
        }

        let evtSQL = """
        SELECT app_name, window_title, url, COUNT(*) AS cnt, MIN(timestamp) AS first_ts
        FROM activity_events
        WHERE session_id = ?
        GROUP BY app_name, window_title, url
        ORDER BY first_ts ASC;
        """
        try queryStatementLocked(evtSQL, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            let app = nonEmpty(readText(stmt, 0))
            let title = nonEmpty(readText(stmt, 1))
            let rawURL = nonEmpty(readText(stmt, 2))
            let cnt = max(1, Int(sqlite3_column_int64(stmt, 3)))
            if let app, !orderedApps.contains(app) {
                orderedApps.append(app)
            }
            if let rawURL,
               let host = URLComponents(string: rawURL)?.host?.lowercased(),
               !host.isEmpty,
               !orderedDomains.contains(host) {
                orderedDomains.append(host)
            }
            if let title {
                let label = app.map { "\($0): \(title)" } ?? title
                if countsByKey[label] == nil {
                    orderedKeys.append(label)
                }
                countsByKey[label, default: 0] += cnt
            }
            collectSignals(app: app, title: title, url: rawURL)
        })

        titleCounts = orderedKeys
            .map { (key: $0, count: countsByKey[$0] ?? 1) }
            .sorted { $0.count > $1.count }

        var topTitles = titleCounts.prefix(2).map(\.key)
        let snapSQL = """
        SELECT app_name, window_title FROM activity_snapshots
        WHERE session_id = ? AND window_title IS NOT NULL
        ORDER BY timestamp ASC LIMIT 20;
        """
        try queryStatementLocked(snapSQL, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            let app = nonEmpty(readText(stmt, 0))
            let title = nonEmpty(readText(stmt, 1))
            if let title {
                if titleCounts.isEmpty {
                    let label = app.map { "\($0): \(title)" } ?? title
                    if !topTitles.contains(label) && topTitles.count < 2 {
                        topTitles.append(label)
                    }
                }
                collectSignals(app: app, title: title, url: nil)
            }
        })

        var ocrCount = 0
        try queryStatementLocked("SELECT COUNT(*) FROM activity_ocr_frames WHERE session_id = ?;", bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            ocrCount = Int(sqlite3_column_int64(stmt, 0))
        })

        let taskPrefix = (session.project ?? session.declaredTaskId).map { "[\($0)] " } ?? ""
        let headline: String
        if !topTitles.isEmpty {
            headline = taskPrefix + topTitles.joined(separator: " · ")
        } else if !session.appNames.isEmpty {
            headline = taskPrefix + session.appNames.prefix(3).joined(separator: " · ")
        } else {
            headline = taskPrefix + "Activity Session"
        }

        var descParts: [String] = []
        if !session.appNames.isEmpty {
            descParts.append("Apps: \(session.appNames.joined(separator: ", "))")
        }
        if !topTitles.isEmpty {
            descParts.append("Windows: \(topTitles.joined(separator: "; "))")
        }
        if let task = session.declaredTaskId ?? session.project {
            descParts.append("Task: \(task)")
        }
        descParts.append("Events: \(session.eventCount), Snapshots: \(session.snapshotCount), OCR: \(ocrCount)")
        if session.clickCount + session.keypressCount > 0 {
            descParts.append(String(
                format: "Clicks: %d, Keypresses: %d (%.1f/min)",
                session.clickCount,
                session.keypressCount,
                session.inputEventsPerMinute
            ))
        }
        let description = descParts.joined(separator: " | ")

        // Structured tags: task + high-frequency apps + web domains + headline windows.
        var topics: [String] = []
        func appendTopic(_ value: String?) {
            guard let value = nonEmpty(value), !topics.contains(value) else { return }
            topics.append(value)
        }
        let taskTag = session.declaredTaskId ?? session.project
        appendTopic(taskTag)
        if orderedApps.isEmpty {
            for app in session.appNames.prefix(3) { appendTopic(app) }
        } else {
            for app in orderedApps.prefix(3) { appendTopic(app) }
        }
        for domain in orderedDomains.prefix(3) { appendTopic(domain) }
        topics = Array(topics.prefix(8))

        var entities: [String: [String]] = [:]
        if let taskTag = nonEmpty(taskTag) { entities["task"] = [taskTag] }
        let appEntities = Array(orderedApps.prefix(8))
        if !appEntities.isEmpty { entities["app"] = appEntities }
        let domainEntities = Array(orderedDomains.prefix(8))
        if !domainEntities.isEmpty { entities["domain"] = domainEntities }
        if !extractedRepos.isEmpty { entities["repo"] = Array(extractedRepos.prefix(8)) }
        if !extractedPRs.isEmpty { entities["pr"] = Array(extractedPRs.prefix(8)) }
        if !extractedLocalPorts.isEmpty { entities["local_port"] = Array(extractedLocalPorts.prefix(8)) }
        let highlights = Array(topTitles.prefix(3))

        let topicsJSON = encodeJSONString(topics) ?? "[]"
        let entitiesJSON = encodeJSONString(entities) ?? "{}"
        let highlightsJSON = encodeJSONString(highlights) ?? "[]"

        let updateSQL = """
        UPDATE activity_sessions
        SET analysis_status = 'completed',
            analysis_title = ?,
            analysis_description = ?,
            analysis_model = 'dayhelm-native',
            analyzed_at = ?,
            is_meeting = ?,
            topics = ?,
            entities = ?,
            highlights = ?
        WHERE id = ?;
        """
        try runStatementLocked(updateSQL) { stmt in
            bindText(stmt, index: 1, value: headline)
            bindText(stmt, index: 2, value: description)
            sqlite3_bind_int64(stmt, 3, nowMs)
            sqlite3_bind_int(stmt, 4, isMeeting ? 1 : 0)
            bindText(stmt, index: 5, value: topicsJSON)
            bindText(stmt, index: 6, value: entitiesJSON)
            bindText(stmt, index: 7, value: highlightsJSON)
            bindText(stmt, index: 8, value: sessionId)
        }

        if let cached = cachedOpenSession, cached.summary.id == sessionId {
            let s = cached.summary
            let updatedSummary = RecordedSessionSummary(
                id: s.id,
                startedAt: s.startedAt,
                endedAt: s.endedAt,
                durationMs: s.durationMs,
                triggerKind: s.triggerKind,
                appNames: s.appNames,
                eventCount: s.eventCount,
                snapshotCount: s.snapshotCount,
                totalBytes: s.totalBytes,
                analysisStatus: "completed",
                analysisTitle: headline,
                analysisDescription: description,
                analysisModel: "dayhelm-native",
                analysisError: s.analysisError,
                analyzedAt: nowMs,
                worthMemory: s.worthMemory,
                worthKnowledge: s.worthKnowledge,
                isMeeting: isMeeting,
                storageTier: s.storageTier,
                entities: entities,
                topics: topics,
                project: s.project,
                highlights: highlights,
                declaredTaskId: s.declaredTaskId,
                createdAt: s.createdAt,
                updatedAt: s.updatedAt,
                clickCount: s.clickCount,
                keypressCount: s.keypressCount
            )
            cachedOpenSession = (summary: updatedSummary, lastActivityMs: cached.lastActivityMs)
        }
    }

    private func fetchSessionSummaryLocked(sessionId: String) throws -> RecordedSessionSummary? {
        var found: RecordedSessionSummary?
        let sql = """
        SELECT id, started_at, ended_at, duration_ms, trigger_kind, app_names,
               event_count, snapshot_count, total_bytes, analysis_status,
               analysis_title, analysis_description, analysis_model, analysis_error,
               analyzed_at, worth_memory, worth_knowledge, is_meeting, storage_tier,
               entities, topics, project, highlights, declared_task_id, created_at, updated_at,
               click_count, keypress_count
        FROM activity_sessions
        WHERE id = ?
        LIMIT 1;
        """
        try queryStatementLocked(sql, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            found = readSessionRow(stmt)
        })
        return found
    }

    private func resolveSessionIdLocked(prefixOrId: String) throws -> String? {
        let trimmed = prefixOrId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var exactMatch: String?
        try queryStatementLocked(
            "SELECT id FROM activity_sessions WHERE id = ? LIMIT 1;",
            bind: { stmt in
                bindText(stmt, index: 1, value: trimmed)
            },
            onRow: { stmt in
                exactMatch = readText(stmt, 0)
            }
        )
        if let exactMatch { return exactMatch }

        guard trimmed.count >= 6 else { return nil }
        let prefixPattern = "\(escapeLike(trimmed))%"
        var matches: [String] = []
        try queryStatementLocked(
            "SELECT id FROM activity_sessions WHERE id LIKE ? ESCAPE '\\' LIMIT 2;",
            bind: { stmt in
                bindText(stmt, index: 1, value: prefixPattern)
            },
            onRow: { stmt in
                if let id = readText(stmt, 0) {
                    matches.append(id)
                }
            }
        )
        return matches.count == 1 ? matches[0] : nil
    }

    private func sessionWhereClause(
        sinceMs: Int64?,
        untilMs: Int64?,
        analysisStatus: String?
    ) -> String {
        var clauses: [String] = []
        if sinceMs != nil {
            clauses.append("(COALESCE(ended_at, updated_at, started_at) >= ?)")
        }
        if untilMs != nil {
            clauses.append("(started_at <= ?)")
        }
        if nonEmpty(analysisStatus) != nil {
            clauses.append("(analysis_status = ?)")
        }
        return clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
    }

    private func countSessionsLocked(
        sinceMs: Int64? = nil,
        untilMs: Int64? = nil,
        analysisStatus: String? = nil
    ) throws -> Int {
        let whereClause = sessionWhereClause(sinceMs: sinceMs, untilMs: untilMs, analysisStatus: analysisStatus)
        let sql = "SELECT COUNT(*) FROM activity_sessions \(whereClause);"
        var count = 0
        try queryStatementLocked(sql, bind: { stmt in
            var idx: Int32 = 1
            if let sinceMs {
                sqlite3_bind_int64(stmt, idx, sinceMs)
                idx += 1
            }
            if let untilMs {
                sqlite3_bind_int64(stmt, idx, untilMs)
                idx += 1
            }
            if let status = nonEmpty(analysisStatus) {
                bindText(stmt, index: idx, value: status)
            }
        }, onRow: { stmt in
            count = Int(sqlite3_column_int64(stmt, 0))
        })
        return count
    }

    private func listSessionsLocked(
        sinceMs: Int64? = nil,
        untilMs: Int64? = nil,
        limit: Int = 100,
        offset: Int = 0,
        analysisStatus: String? = nil
    ) throws -> [RecordedSessionSummary] {
        let whereClause = sessionWhereClause(sinceMs: sinceMs, untilMs: untilMs, analysisStatus: analysisStatus)
        let sql = """
        SELECT id, started_at, ended_at, duration_ms, trigger_kind, app_names,
               event_count, snapshot_count, total_bytes, analysis_status,
               analysis_title, analysis_description, analysis_model, analysis_error,
               analyzed_at, worth_memory, worth_knowledge, is_meeting, storage_tier,
               entities, topics, project, highlights, declared_task_id, created_at, updated_at,
               click_count, keypress_count
        FROM activity_sessions
        \(whereClause)
        ORDER BY started_at DESC
        LIMIT ? OFFSET ?;
        """
        var results: [RecordedSessionSummary] = []
        try queryStatementLocked(sql, bind: { stmt in
            var idx: Int32 = 1
            if let sinceMs {
                sqlite3_bind_int64(stmt, idx, sinceMs)
                idx += 1
            }
            if let untilMs {
                sqlite3_bind_int64(stmt, idx, untilMs)
                idx += 1
            }
            if let status = nonEmpty(analysisStatus) {
                bindText(stmt, index: idx, value: status)
                idx += 1
            }
            sqlite3_bind_int(stmt, idx, Int32(max(1, limit)))
            idx += 1
            sqlite3_bind_int(stmt, idx, Int32(max(0, offset)))
        }, onRow: { stmt in
            results.append(readSessionRow(stmt))
        })
        return results
    }

    private func fetchEventsLocked(sessionId: String) throws -> [RecordedActivityEvent] {
        var events: [RecordedActivityEvent] = []
        let sql = """
        SELECT id, session_id, timestamp, kind, app_name, window_title, url, data, created_at
        FROM activity_events
        WHERE session_id = ?
        ORDER BY timestamp ASC, created_at ASC;
        """
        try queryStatementLocked(sql, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            let dataDict = decodeJSON([String: String].self, from: readText(stmt, 7)) ?? [:]
            events.append(RecordedActivityEvent(
                id: readText(stmt, 0) ?? "",
                sessionId: readText(stmt, 1) ?? sessionId,
                timestamp: sqlite3_column_int64(stmt, 2),
                kind: readText(stmt, 3) ?? "app_focus",
                appName: readText(stmt, 4),
                windowTitle: readText(stmt, 5),
                url: readText(stmt, 6),
                data: dataDict,
                createdAt: sqlite3_column_int64(stmt, 8)
            ))
        })
        return events
    }

    private func fetchSnapshotsLocked(sessionId: String) throws -> [RecordedSnapshot] {
        var snapshots: [RecordedSnapshot] = []
        let sql = """
        SELECT id, session_id, timestamp, file_path, width, height, size_bytes,
               trigger, app_name, window_title, hash_hex, histogram, diff_pct,
               storage_tier, created_at
        FROM activity_snapshots
        WHERE session_id = ?
        ORDER BY timestamp ASC;
        """
        try queryStatementLocked(sql, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            let hist = decodeJSON([Double].self, from: readText(stmt, 11))
            let diffPct: Double? = sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 12)
            snapshots.append(RecordedSnapshot(
                id: readText(stmt, 0) ?? "",
                sessionId: readText(stmt, 1) ?? sessionId,
                timestamp: sqlite3_column_int64(stmt, 2),
                filePath: readText(stmt, 3) ?? "",
                width: Int(sqlite3_column_int(stmt, 4)),
                height: Int(sqlite3_column_int(stmt, 5)),
                sizeBytes: sqlite3_column_int64(stmt, 6),
                trigger: readText(stmt, 7) ?? "heartbeat",
                appName: readText(stmt, 8),
                windowTitle: readText(stmt, 9),
                hashHex: readText(stmt, 10),
                histogram: hist,
                diffPct: diffPct,
                storageTier: readText(stmt, 13) ?? "hot",
                createdAt: sqlite3_column_int64(stmt, 14)
            ))
        })
        return snapshots
    }

    private func fetchOCRFramesLocked(sessionId: String) throws -> [RecordedOCRFrame] {
        var frames: [RecordedOCRFrame] = []
        let sql = """
        SELECT id, snapshot_id, session_id, text, char_count, token_count, created_at
        FROM activity_ocr_frames
        WHERE session_id = ?
        ORDER BY created_at ASC;
        """
        try queryStatementLocked(sql, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            frames.append(RecordedOCRFrame(
                id: readText(stmt, 0) ?? "",
                snapshotId: readText(stmt, 1) ?? "",
                sessionId: readText(stmt, 2) ?? sessionId,
                text: readText(stmt, 3) ?? "",
                charCount: Int(sqlite3_column_int(stmt, 4)),
                tokenCount: Int(sqlite3_column_int(stmt, 5)),
                createdAt: sqlite3_column_int64(stmt, 6)
            ))
        })
        return frames
    }

    private func countRowsLocked(sql: String, sinceMs: Int64, untilMs: Int64) throws -> Int {
        var count = 0
        try queryStatementLocked(sql, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, sinceMs)
            sqlite3_bind_int64(stmt, 2, untilMs)
        }, onRow: { stmt in
            count = Int(sqlite3_column_int64(stmt, 0))
        })
        return count
    }

    private func readSessionRow(_ stmt: OpaquePointer) -> RecordedSessionSummary {
        let endedAt: Int64? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 2)
        let durationMs: Int64? = sqlite3_column_type(stmt, 3) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 3)
        let analyzedAt: Int64? = sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 14)
        let appNames = decodeJSON([String].self, from: readText(stmt, 5)) ?? []
        let entities = decodeJSON([String: [String]].self, from: readText(stmt, 19)) ?? [:]
        let topics = decodeJSON([String].self, from: readText(stmt, 20)) ?? []
        let highlights = decodeJSON([String].self, from: readText(stmt, 22)) ?? []

        return RecordedSessionSummary(
            id: readText(stmt, 0) ?? "",
            startedAt: sqlite3_column_int64(stmt, 1),
            endedAt: endedAt,
            durationMs: durationMs,
            triggerKind: readText(stmt, 4) ?? "idle",
            appNames: appNames,
            eventCount: Int(sqlite3_column_int(stmt, 6)),
            snapshotCount: Int(sqlite3_column_int(stmt, 7)),
            totalBytes: sqlite3_column_int64(stmt, 8),
            analysisStatus: readText(stmt, 9) ?? "pending",
            analysisTitle: readText(stmt, 10),
            analysisDescription: readText(stmt, 11),
            analysisModel: readText(stmt, 12),
            analysisError: readText(stmt, 13),
            analyzedAt: analyzedAt,
            worthMemory: sqlite3_column_int(stmt, 15) != 0,
            worthKnowledge: sqlite3_column_int(stmt, 16) != 0,
            isMeeting: sqlite3_column_int(stmt, 17) != 0,
            storageTier: readText(stmt, 18) ?? "hot",
            entities: entities,
            topics: topics,
            project: readText(stmt, 21),
            highlights: highlights,
            declaredTaskId: readText(stmt, 23),
            createdAt: sqlite3_column_int64(stmt, 24),
            updatedAt: sqlite3_column_int64(stmt, 25),
            clickCount: Int(sqlite3_column_int64(stmt, 26)),
            keypressCount: Int(sqlite3_column_int64(stmt, 27))
        )
    }

    // MARK: - Summary Helpers (lock held by caller)

    private func dayStartMsLocked(dateKey: String) -> Int64? {
        guard let date = DayHelmDateFormatting.parseDayString(dateKey) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        return Int64(cal.startOfDay(for: date).timeIntervalSince1970 * 1000)
    }

    private func dayInputTotalsLocked(dayStartMs: Int64, dayEndMs: Int64) throws -> DayInputTotals {
        var clickCount = 0
        var keypressCount = 0
        try queryStatementLocked("""
        SELECT COALESCE(SUM(CASE WHEN kind = 'click' THEN MAX(1, COALESCE(CAST(json_extract(data, '$.count') AS INTEGER), 1)) ELSE 0 END), 0),
               COALESCE(SUM(CASE WHEN kind = 'keypress' THEN MAX(1, COALESCE(CAST(json_extract(data, '$.count') AS INTEGER), 1)) ELSE 0 END), 0)
        FROM activity_events WHERE timestamp >= ? AND timestamp <= ?;
        """, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, dayStartMs)
            sqlite3_bind_int64(stmt, 2, dayEndMs)
        }, onRow: { stmt in
            clickCount = Int(sqlite3_column_int64(stmt, 0))
            keypressCount = Int(sqlite3_column_int64(stmt, 1))
        })

        var totalSessionMs: Int64 = 0
        try queryStatementLocked("""
        SELECT COALESCE(SUM(
                   COALESCE(duration_ms, CASE WHEN ended_at IS NOT NULL THEN MAX(0, ended_at - started_at) ELSE 0 END)
               ), 0)
        FROM activity_sessions WHERE started_at >= ? AND started_at <= ?;
        """, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, dayStartMs)
            sqlite3_bind_int64(stmt, 2, dayEndMs)
        }, onRow: { stmt in
            totalSessionMs = sqlite3_column_int64(stmt, 0)
        })

        return DayInputTotals(
            clickCount: clickCount,
            keypressCount: keypressCount,
            totalSessionDurationMs: totalSessionMs,
            inputEventsPerMinute: DayInputTotals.density(
                clickCount: clickCount,
                keypressCount: keypressCount,
                durationMs: totalSessionMs
            )
        )
    }

    private func ocrTotalsLocked(dayStartMs: Int64, dayEndMs: Int64) throws -> (frames: Int, chars: Int) {
        var frames = 0
        var chars = 0
        try queryStatementLocked("""
        SELECT COUNT(*), COALESCE(SUM(char_count), 0)
        FROM activity_ocr_frames WHERE created_at >= ? AND created_at <= ?;
        """, bind: { stmt in
            sqlite3_bind_int64(stmt, 1, dayStartMs)
            sqlite3_bind_int64(stmt, 2, dayEndMs)
        }, onRow: { stmt in
            frames = Int(sqlite3_column_int64(stmt, 0))
            chars = Int(sqlite3_column_int64(stmt, 1))
        })
        return (frames, chars)
    }

    private func snapshotCountLocked(dayStartMs: Int64, dayEndMs: Int64) throws -> Int {
        var count = 0
        try queryStatementLocked(
            "SELECT COUNT(*) FROM activity_snapshots WHERE timestamp >= ? AND timestamp <= ?;",
            bind: { stmt in
                sqlite3_bind_int64(stmt, 1, dayStartMs)
                sqlite3_bind_int64(stmt, 2, dayEndMs)
            },
            onRow: { stmt in
                count = Int(sqlite3_column_int64(stmt, 0))
            }
        )
        return count
    }

    /// Per-app time attribution inside one session: each event's app holds until the next event
    /// (or the session end), mirroring Alma's `perAppDurationsForSession`.
    private func perAppDurationsLocked(sessionId: String, sessionEndMs: Int64) throws -> [String: Int64] {
        var rows: [(timestamp: Int64, app: String)] = []
        try queryStatementLocked("""
        SELECT timestamp, app_name FROM activity_events
        WHERE session_id = ? AND app_name IS NOT NULL
        ORDER BY timestamp ASC;
        """, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            guard let app = nonEmpty(readText(stmt, 1)) else { return }
            rows.append((sqlite3_column_int64(stmt, 0), app))
        })

        var durations: [String: Int64] = [:]
        for (index, row) in rows.enumerated() {
            let nextTimestamp = index + 1 < rows.count ? rows[index + 1].timestamp : sessionEndMs
            let heldMs = min(nextTimestamp, sessionEndMs) - row.timestamp
            guard heldMs > 0 else { continue }
            durations[row.app, default: 0] += heldMs
        }
        return durations
    }

    private func dailySummaryStatsLocked(dateKey: String) throws -> ActivityDailySummaryStats {
        guard let startMs = dayStartMsLocked(dateKey: dateKey) else {
            throw ActivitySummaryError.invalidDateKey(dateKey)
        }
        let endMs = startMs + 86_400_000 - 1
        let sessions = try listSessionsLocked(sinceMs: startMs, untilMs: endMs, limit: 1_000)

        var totalActiveMs: Int64 = 0
        var analyzedCount = 0
        var notWorthCount = 0
        var appDurations: [String: Int64] = [:]
        var hours = [Int](repeating: 0, count: 24)
        var keyMoments: [ActivityDailySummaryStats.KeyMoment] = []

        for session in sessions {
            let effectiveMs = session.durationMs
                ?? session.endedAt.map { max(0, $0 - session.startedAt) }
                ?? 0
            totalActiveMs += max(0, effectiveMs)
            if session.analysisStatus == "analyzed" || session.analysisStatus == "completed" {
                analyzedCount += 1
            }
            if session.analysisStatus == "not_worth" {
                notWorthCount += 1
            }
            let sessionEnd = max(session.endedAt ?? session.updatedAt, session.startedAt)
            for (app, ms) in try perAppDurationsLocked(sessionId: session.id, sessionEndMs: sessionEnd) {
                appDurations[app, default: 0] += ms
            }
            let hour = hourOfDayMs(session.startedAt)
            if hour >= 0, hour < 24 {
                hours[hour] += 1
            }
            if let title = session.analysisTitle, !title.isEmpty {
                keyMoments.append(ActivityDailySummaryStats.KeyMoment(
                    sessionId: session.id,
                    title: title,
                    startedAt: session.startedAt,
                    durationMs: max(0, effectiveMs)
                ))
            }
        }

        keyMoments.sort { $0.durationMs > $1.durationMs }
        let inputTotals = try dayInputTotalsLocked(dayStartMs: startMs, dayEndMs: endMs)
        let ocr = try ocrTotalsLocked(dayStartMs: startMs, dayEndMs: endMs)
        let eventCount = try countRowsLocked(
            sql: "SELECT COUNT(*) FROM activity_events WHERE timestamp >= ? AND timestamp <= ?;",
            sinceMs: startMs,
            untilMs: endMs
        )
        let snapshots = try snapshotCountLocked(dayStartMs: startMs, dayEndMs: endMs)

        let apps = appDurations
            .map { ActivityDailySummaryStats.AppDuration(app: $0.key, durationMs: $0.value) }
            .sorted { $0.durationMs > $1.durationMs }
            .prefix(10)
            .map { $0 }

        return ActivityDailySummaryStats(
            dateKey: dateKey,
            sessionCount: sessions.count,
            totalActiveMs: totalActiveMs,
            analyzedCount: analyzedCount,
            notWorthCount: notWorthCount,
            eventCount: eventCount,
            snapshotCount: snapshots,
            ocrFrameCount: ocr.frames,
            ocrCharCount: ocr.chars,
            clickCount: inputTotals.clickCount,
            keypressCount: inputTotals.keypressCount,
            inputEventsPerMinute: DayInputTotals.density(
                clickCount: inputTotals.clickCount,
                keypressCount: inputTotals.keypressCount,
                durationMs: totalActiveMs
            ),
            apps: apps,
            hours: hours.enumerated().map { ActivityDailySummaryStats.HourBucket(hour: $0.offset, count: $0.element) },
            keyMoments: Array(keyMoments.prefix(10))
        )
    }

    private func weeklySummaryStatsLocked(weekKey: String) throws -> ActivityWeeklySummaryStats {
        guard let range = DayHelmISOWeek.dateRange(forWeekKey: weekKey) else {
            throw ActivitySummaryError.invalidWeekKey(weekKey)
        }

        var daily: [ActivityWeeklySummaryStats.DailySlice] = []
        var appDurations: [String: Int64] = [:]
        var totalActiveMs: Int64 = 0
        var sessionCount = 0
        var clickCount = 0
        var keypressCount = 0

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone

        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: range.start) else { continue }
            let dateKey = DayHelmDateFormatting.dayString(from: day)
            let stats = try dailySummaryStatsLocked(dateKey: dateKey)
            daily.append(ActivityWeeklySummaryStats.DailySlice(
                dateKey: dateKey,
                activeMs: stats.totalActiveMs,
                sessionCount: stats.sessionCount
            ))
            totalActiveMs += stats.totalActiveMs
            sessionCount += stats.sessionCount
            clickCount += stats.clickCount
            keypressCount += stats.keypressCount
            for entry in stats.apps {
                appDurations[entry.app, default: 0] += entry.durationMs
            }
        }

        let apps = appDurations
            .map { ActivityDailySummaryStats.AppDuration(app: $0.key, durationMs: $0.value) }
            .sorted { $0.durationMs > $1.durationMs }
            .prefix(10)
            .map { $0 }

        let lastDay = cal.date(byAdding: .day, value: -1, to: range.end) ?? range.start

        return ActivityWeeklySummaryStats(
            weekKey: DayHelmISOWeek.weekKey(for: range.start),
            startDate: DayHelmDateFormatting.dayString(from: range.start),
            endDate: DayHelmDateFormatting.dayString(from: lastDay),
            totalActiveMs: totalActiveMs,
            sessionCount: sessionCount,
            clickCount: clickCount,
            keypressCount: keypressCount,
            inputEventsPerMinute: DayInputTotals.density(
                clickCount: clickCount,
                keypressCount: keypressCount,
                durationMs: totalActiveMs
            ),
            apps: apps,
            daily: daily
        )
    }

    private func hourOfDayMs(_ timestampMs: Int64) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000.0)
        return cal.component(.hour, from: date)
    }

    // MARK: - Low-Level SQLite Helpers

    private func executeLocked(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? lastErrorMessageLocked()
            if let errMsg { sqlite3_free(errMsg) }
            throw ActivityDatabaseError.stepFailed(sql: sql, message: msg)
        }
    }

    private func runStatementLocked(_ sql: String, bind: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ActivityDatabaseError.prepareFailed(sql: sql, message: lastErrorMessageLocked())
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw ActivityDatabaseError.stepFailed(sql: sql, message: lastErrorMessageLocked())
        }
    }

    private func queryStatementLocked(
        _ sql: String,
        bind: (OpaquePointer) -> Void,
        onRow: (OpaquePointer) -> Void
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ActivityDatabaseError.prepareFailed(sql: sql, message: lastErrorMessageLocked())
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt)
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                onRow(stmt)
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw ActivityDatabaseError.stepFailed(sql: sql, message: lastErrorMessageLocked())
            }
        }
    }

    private func bindText(_ stmt: OpaquePointer, index: Int32, value: String) {
        _ = value.withCString { cStr in
            sqlite3_bind_text(stmt, index, cStr, -1, sqliteTransient)
        }
    }

    private func bindOptionalText(_ stmt: OpaquePointer, index: Int32, value: String?) {
        if let value {
            bindText(stmt, index: index, value: value)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func readText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let ptr = sqlite3_column_text(stmt, index) else {
            return nil
        }
        return String(cString: ptr)
    }

    private func lastErrorMessageLocked() -> String {
        guard let db, let msg = sqlite3_errmsg(db) else {
            return "unknown SQLite error"
        }
        return String(cString: msg)
    }

    private func makeSessionId(timestampMs: Int64) -> String {
        "sess_\(timestampMs)_\(UUID().uuidString.prefix(6).lowercased())"
    }

    private func encodeJSONString<T: Encodable>(_ value: T) -> String? {
        guard let data = try? jsonEncoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from text: String?) -> T? {
        guard let text, !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? jsonDecoder.decode(type, from: data)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func escapeLike(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func makeFTS5TrigramPhrase(_ keyword: String) -> String {
        "\"\(keyword.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func makeSnippet(from text: String, keyword: String, radius: Int = 80) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = collapsed.range(of: keyword, options: .caseInsensitive) else {
            return collapsed.count > 160 ? String(collapsed.prefix(160)) + "…" : collapsed
        }

        let startDist = collapsed.distance(from: collapsed.startIndex, to: range.lowerBound)
        let endDist = collapsed.distance(from: collapsed.startIndex, to: range.upperBound)
        let sliceStartOffset = max(0, startDist - radius)
        let sliceEndOffset = min(collapsed.count, endDist + radius)

        let startIdx = collapsed.index(collapsed.startIndex, offsetBy: sliceStartOffset)
        let endIdx = collapsed.index(collapsed.startIndex, offsetBy: sliceEndOffset)
        var snippet = String(collapsed[startIdx..<endIdx])
        if sliceStartOffset > 0 { snippet = "…" + snippet }
        if sliceEndOffset < collapsed.count { snippet += "…" }
        return snippet
    }

    private static let meetingSignals: [String] = [
        "zoom.us", "us.zoom.xos", "zoom meeting", "zoom workplace",
        "meet.google.com", "google meet",
        "com.microsoft.teams", "teams.microsoft.com", "microsoft teams",
        "com.electron.lark", "vc.feishu.cn", "vc.larksuite.com", "飞书会议", "feishu meeting", "lark meeting",
        "com.tencent.meeting", "meeting.tencent.com", "tencent meeting", "腾讯会议", "voov meeting",
        "cisco.webex", "webex.com", "webex meeting",
        "钉钉会议"
    ]

    private static func matchesMeetingSignal(appName: String?, windowTitle: String?, url: String?) -> Bool {
        let lowerApp = appName?.lowercased() ?? ""
        let lowerTitle = windowTitle?.lowercased() ?? ""
        let lowerURL = url?.lowercased() ?? ""
        let combined = "\(lowerApp) \(lowerTitle) \(lowerURL)"
        if meetingSignals.contains(where: { combined.contains($0) }) {
            return true
        }
        if (lowerApp.contains("dingtalk") || lowerApp.contains("alibaba.dingtalk"))
            && (lowerTitle.contains("meeting") || lowerTitle.contains("会议")) {
            return true
        }
        return false
    }

    private static let repoRegex = try? NSRegularExpression(
        pattern: #"(?:github\.com|gitlab\.com)/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)"#,
        options: [.caseInsensitive]
    )
    private static let urlPRRegex = try? NSRegularExpression(
        pattern: #"(?:github\.com|gitlab\.com)/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/(?:pull|issues|merge_requests)/(\d+)"#,
        options: [.caseInsensitive]
    )
    private static let hashPRRegex = try? NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9])#(\d{2,7})\b"#,
        options: []
    )
    private static let localPortRegex = try? NSRegularExpression(
        pattern: #"(?:localhost|127\.0\.0\.1):(\d{2,5})\b"#,
        options: [.caseInsensitive]
    )

    private static func extractRegexEntities(
        from text: String,
        repos: inout [String],
        prs: inout [String],
        localPorts: inout [String]
    ) {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        if let repoRegex {
            for match in repoRegex.matches(in: text, options: [], range: fullRange) where match.numberOfRanges > 1 {
                var repo = nsText.substring(with: match.range(at: 1))
                if repo.hasSuffix(".git") {
                    repo = String(repo.dropLast(4))
                }
                if !repo.isEmpty && !repos.contains(repo) {
                    repos.append(repo)
                }
            }
        }
        if let urlPRRegex {
            for match in urlPRRegex.matches(in: text, options: [], range: fullRange) where match.numberOfRanges > 1 {
                let pr = "#" + nsText.substring(with: match.range(at: 1))
                if !prs.contains(pr) {
                    prs.append(pr)
                }
            }
        }
        if let hashPRRegex {
            for match in hashPRRegex.matches(in: text, options: [], range: fullRange) where match.numberOfRanges > 1 {
                let pr = "#" + nsText.substring(with: match.range(at: 1))
                if !prs.contains(pr) {
                    prs.append(pr)
                }
            }
        }
        if let localPortRegex {
            for match in localPortRegex.matches(in: text, options: [], range: fullRange) {
                let hostPort = nsText.substring(with: match.range(at: 0)).lowercased()
                if !localPorts.contains(hostPort) {
                    localPorts.append(hostPort)
                }
            }
        }
    }
}
