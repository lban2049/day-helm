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
        updatedAt: Int64
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

        return try fetchSessionSummaryLocked(sessionId: sessionId)!
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

        try refreshSessionMetadataLocked(
            sessionId: targetSessionId,
            activityAtMs: timestampMs,
            addedAppName: cleanApp,
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
        limit: Int = 100
    ) throws -> [RecordedSessionSummary] {
        lock.lock()
        defer { lock.unlock() }

        var clauses: [String] = []
        if sinceMs != nil {
            clauses.append("(COALESCE(ended_at, updated_at, started_at) >= ?)")
        }
        if untilMs != nil {
            clauses.append("(started_at <= ?)")
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, started_at, ended_at, duration_ms, trigger_kind, app_names,
               event_count, snapshot_count, total_bytes, analysis_status,
               analysis_title, analysis_description, analysis_model, analysis_error,
               analyzed_at, worth_memory, worth_knowledge, is_meeting, storage_tier,
               entities, topics, project, highlights, declared_task_id, created_at, updated_at
        FROM activity_sessions
        \(whereClause)
        ORDER BY started_at DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw ActivityDatabaseError.prepareFailed(sql: sql, message: lastErrorMessageLocked())
        }
        defer { sqlite3_finalize(stmt) }

        var bindIdx: Int32 = 1
        if let sinceMs {
            sqlite3_bind_int64(stmt, bindIdx, sinceMs)
            bindIdx += 1
        }
        if let untilMs {
            sqlite3_bind_int64(stmt, bindIdx, untilMs)
            bindIdx += 1
        }
        sqlite3_bind_int(stmt, bindIdx, Int32(max(1, limit)))

        var results: [RecordedSessionSummary] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                results.append(readSessionRow(stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw ActivityDatabaseError.stepFailed(sql: sql, message: lastErrorMessageLocked())
            }
        }
        return results
    }

    public func getSessionDetail(sessionId: String) throws -> RecordedSessionDetail? {
        lock.lock()
        defer { lock.unlock() }

        guard let session = try fetchSessionSummaryLocked(sessionId: sessionId) else {
            return nil
        }
        let events = try fetchEventsLocked(sessionId: sessionId)
        let snapshots = try fetchSnapshotsLocked(sessionId: sessionId)
        let ocrFrames = try fetchOCRFramesLocked(sessionId: sessionId)

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

        // 1. Search OCR frames
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

    public func currentOpenSessionId() throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return try currentOpenSessionIdLocked()
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
        SET storage_tier = 'pruned'
        WHERE timestamp < ? AND storage_tier != 'pruned';
        """
        try runStatementLocked(updateSQL) { stmt in
            sqlite3_bind_int64(stmt, 1, cutoffMs)
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
            "CREATE INDEX IF NOT EXISTS idx_activity_events_session_ts ON activity_events(session_id, timestamp ASC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_events_ts ON activity_events(timestamp DESC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_snapshots_session_ts ON activity_snapshots(session_id, timestamp ASC);",
            "CREATE INDEX IF NOT EXISTS idx_activity_ocr_session ON activity_ocr_frames(session_id);",
            "CREATE INDEX IF NOT EXISTS idx_activity_ocr_snapshot ON activity_ocr_frames(snapshot_id);"
        ]

        for sql in statements {
            try executeLocked(sql)
        }

        // Forward compatibility if upgrading an older database file
        try ensureColumnExistsLocked(table: "activity_sessions", column: "declared_task_id", definition: "TEXT")
        try ensureColumnExistsLocked(table: "activity_events", column: "window_title", definition: "TEXT")
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
        if let openId = try currentOpenSessionIdLocked(),
           let existing = try fetchSessionSummaryLocked(sessionId: openId) {
            let lastMs = try latestSessionTimestampLocked(sessionId: openId) ?? existing.startedAt
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
        declaredTaskId: String?,
        project: String?
    ) throws {
        guard let existing = try fetchSessionSummaryLocked(sessionId: sessionId) else { return }

        var apps = existing.appNames
        if let app = nonEmpty(addedAppName), !apps.contains(app) {
            apps.append(app)
        }

        var eventCount = 0
        try queryStatementLocked("SELECT COUNT(*) FROM activity_events WHERE session_id = ?;", bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            eventCount = Int(sqlite3_column_int64(stmt, 0))
        })

        var snapshotCount = 0
        var totalBytes: Int64 = 0
        try queryStatementLocked("SELECT COUNT(*), COALESCE(SUM(size_bytes), 0) FROM activity_snapshots WHERE session_id = ?;", bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            snapshotCount = Int(sqlite3_column_int64(stmt, 0))
            totalBytes = sqlite3_column_int64(stmt, 1)
        })

        let effectiveEnd = max(existing.endedAt ?? existing.startedAt, activityAtMs)
        let durationMs = max(0, effectiveEnd - existing.startedAt)
        let resolvedTaskId = nonEmpty(declaredTaskId) ?? existing.declaredTaskId
        let resolvedProject = nonEmpty(project) ?? existing.project ?? resolvedTaskId
        let appsJSON = encodeJSONString(apps) ?? "[]"

        let updateSQL = """
        UPDATE activity_sessions
        SET app_names = ?,
            event_count = ?,
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
            sqlite3_bind_int(stmt, 3, Int32(snapshotCount))
            sqlite3_bind_int64(stmt, 4, totalBytes)
            sqlite3_bind_int64(stmt, 5, durationMs)
            bindOptionalText(stmt, index: 6, value: resolvedProject)
            bindOptionalText(stmt, index: 7, value: resolvedTaskId)
            sqlite3_bind_int64(stmt, 8, max(existing.updatedAt, activityAtMs))
            bindText(stmt, index: 9, value: sessionId)
        }

        try synthesizeSessionSummaryLocked(sessionId: sessionId, nowMs: activityAtMs)
    }

    private func closeSessionLocked(sessionId: String, endedAtMs: Int64) throws {
        guard let existing = try fetchSessionSummaryLocked(sessionId: sessionId) else { return }
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

        try synthesizeSessionSummaryLocked(sessionId: sessionId, nowMs: finalEnd)
    }

    private func synthesizeSessionSummaryLocked(sessionId: String, nowMs: Int64) throws {
        guard let session = try fetchSessionSummaryLocked(sessionId: sessionId) else { return }

        var titleCounts: [(key: String, count: Int)] = []
        var countsByKey: [String: Int] = [:]
        var orderedKeys: [String] = []

        var orderedApps: [String] = []
        var orderedDomains: [String] = []

        let evtSQL = """
        SELECT app_name, window_title, url FROM activity_events
        WHERE session_id = ?
        ORDER BY timestamp ASC;
        """
        try queryStatementLocked(evtSQL, bind: { stmt in
            bindText(stmt, index: 1, value: sessionId)
        }, onRow: { stmt in
            let app = nonEmpty(readText(stmt, 0))
            let title = nonEmpty(readText(stmt, 1))
            if let app, !orderedApps.contains(app) {
                orderedApps.append(app)
            }
            if let rawURL = nonEmpty(readText(stmt, 2)),
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
                countsByKey[label, default: 0] += 1
            }
        })

        titleCounts = orderedKeys
            .map { (key: $0, count: countsByKey[$0] ?? 1) }
            .sorted { $0.count > $1.count }

        var topTitles = titleCounts.prefix(2).map(\.key)
        if topTitles.isEmpty {
            let snapSQL = """
            SELECT app_name, window_title FROM activity_snapshots
            WHERE session_id = ? AND window_title IS NOT NULL
            ORDER BY timestamp ASC LIMIT 5;
            """
            try queryStatementLocked(snapSQL, bind: { stmt in
                bindText(stmt, index: 1, value: sessionId)
            }, onRow: { stmt in
                let app = nonEmpty(readText(stmt, 0))
                let title = nonEmpty(readText(stmt, 1))
                if let title {
                    let label = app.map { "\($0): \(title)" } ?? title
                    if !topTitles.contains(label) && topTitles.count < 2 {
                        topTitles.append(label)
                    }
                }
            })
        }

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
            topics = ?,
            entities = ?,
            highlights = ?
        WHERE id = ?;
        """
        try runStatementLocked(updateSQL) { stmt in
            bindText(stmt, index: 1, value: headline)
            bindText(stmt, index: 2, value: description)
            sqlite3_bind_int64(stmt, 3, nowMs)
            bindText(stmt, index: 4, value: topicsJSON)
            bindText(stmt, index: 5, value: entitiesJSON)
            bindText(stmt, index: 6, value: highlightsJSON)
            bindText(stmt, index: 7, value: sessionId)
        }
    }

    private func fetchSessionSummaryLocked(sessionId: String) throws -> RecordedSessionSummary? {
        var found: RecordedSessionSummary?
        let sql = """
        SELECT id, started_at, ended_at, duration_ms, trigger_kind, app_names,
               event_count, snapshot_count, total_bytes, analysis_status,
               analysis_title, analysis_description, analysis_model, analysis_error,
               analyzed_at, worth_memory, worth_knowledge, is_meeting, storage_tier,
               entities, topics, project, highlights, declared_task_id, created_at, updated_at
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

    private func listSessionsLocked(sinceMs: Int64?, untilMs: Int64?, limit: Int) throws -> [RecordedSessionSummary] {
        var clauses: [String] = []
        if sinceMs != nil {
            clauses.append("(COALESCE(ended_at, updated_at, started_at) >= ?)")
        }
        if untilMs != nil {
            clauses.append("(started_at <= ?)")
        }

        let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, started_at, ended_at, duration_ms, trigger_kind, app_names,
               event_count, snapshot_count, total_bytes, analysis_status,
               analysis_title, analysis_description, analysis_model, analysis_error,
               analyzed_at, worth_memory, worth_knowledge, is_meeting, storage_tier,
               entities, topics, project, highlights, declared_task_id, created_at, updated_at
        FROM activity_sessions
        \(whereClause)
        ORDER BY started_at DESC
        LIMIT ?;
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
            sqlite3_bind_int(stmt, idx, Int32(max(1, limit)))
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
            updatedAt: sqlite3_column_int64(stmt, 25)
        )
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
}
