import Foundation

/// Session-independent, day-level input totals (click / keypress counts only, never key contents).
public struct DayInputTotals: Sendable, Equatable, Codable {
    public let clickCount: Int
    public let keypressCount: Int
    public let totalSessionDurationMs: Int64
    public let inputEventsPerMinute: Double

    public init(
        clickCount: Int,
        keypressCount: Int,
        totalSessionDurationMs: Int64,
        inputEventsPerMinute: Double
    ) {
        self.clickCount = clickCount
        self.keypressCount = keypressCount
        self.totalSessionDurationMs = totalSessionDurationMs
        self.inputEventsPerMinute = inputEventsPerMinute
    }

    public static func density(clickCount: Int, keypressCount: Int, durationMs: Int64) -> Double {
        guard durationMs > 0 else { return 0 }
        return Double(clickCount + keypressCount) / (Double(durationMs) / 60_000.0)
    }
}

/// Alma-compatible daily summary statistics (`GET /api/activity-recorder/summary/daily/<dateKey>`).
public struct ActivityDailySummaryStats: Sendable, Equatable, Codable {
    public struct AppDuration: Sendable, Equatable, Codable {
        public let app: String
        public let durationMs: Int64

        public init(app: String, durationMs: Int64) {
            self.app = app
            self.durationMs = durationMs
        }
    }

    public struct HourBucket: Sendable, Equatable, Codable {
        public let hour: Int
        public let count: Int

        public init(hour: Int, count: Int) {
            self.hour = hour
            self.count = count
        }
    }

    public struct KeyMoment: Sendable, Equatable, Codable {
        public let sessionId: String
        public let title: String
        public let startedAt: Int64
        public let durationMs: Int64

        public init(sessionId: String, title: String, startedAt: Int64, durationMs: Int64) {
            self.sessionId = sessionId
            self.title = title
            self.startedAt = startedAt
            self.durationMs = durationMs
        }
    }

    public let dateKey: String
    public let sessionCount: Int
    public let totalActiveMs: Int64
    public let analyzedCount: Int
    public let notWorthCount: Int
    public let eventCount: Int
    public let snapshotCount: Int
    public let ocrFrameCount: Int
    public let ocrCharCount: Int
    public let clickCount: Int
    public let keypressCount: Int
    public let inputEventsPerMinute: Double
    public let apps: [AppDuration]
    public let hours: [HourBucket]
    public let keyMoments: [KeyMoment]

    public init(
        dateKey: String,
        sessionCount: Int,
        totalActiveMs: Int64,
        analyzedCount: Int,
        notWorthCount: Int,
        eventCount: Int,
        snapshotCount: Int,
        ocrFrameCount: Int,
        ocrCharCount: Int,
        clickCount: Int,
        keypressCount: Int,
        inputEventsPerMinute: Double,
        apps: [AppDuration],
        hours: [HourBucket],
        keyMoments: [KeyMoment]
    ) {
        self.dateKey = dateKey
        self.sessionCount = sessionCount
        self.totalActiveMs = totalActiveMs
        self.analyzedCount = analyzedCount
        self.notWorthCount = notWorthCount
        self.eventCount = eventCount
        self.snapshotCount = snapshotCount
        self.ocrFrameCount = ocrFrameCount
        self.ocrCharCount = ocrCharCount
        self.clickCount = clickCount
        self.keypressCount = keypressCount
        self.inputEventsPerMinute = inputEventsPerMinute
        self.apps = apps
        self.hours = hours
        self.keyMoments = keyMoments
    }
}

/// Alma-compatible weekly summary statistics (`GET /api/activity-recorder/summary/weekly/<weekKey>`).
public struct ActivityWeeklySummaryStats: Sendable, Equatable, Codable {
    public struct DailySlice: Sendable, Equatable, Codable {
        public let dateKey: String
        public let activeMs: Int64
        public let sessionCount: Int

        public init(dateKey: String, activeMs: Int64, sessionCount: Int) {
            self.dateKey = dateKey
            self.activeMs = activeMs
            self.sessionCount = sessionCount
        }
    }

    public let weekKey: String
    public let startDate: String
    public let endDate: String
    public let totalActiveMs: Int64
    public let sessionCount: Int
    public let clickCount: Int
    public let keypressCount: Int
    public let inputEventsPerMinute: Double
    public let apps: [ActivityDailySummaryStats.AppDuration]
    public let daily: [DailySlice]

    public init(
        weekKey: String,
        startDate: String,
        endDate: String,
        totalActiveMs: Int64,
        sessionCount: Int,
        clickCount: Int,
        keypressCount: Int,
        inputEventsPerMinute: Double,
        apps: [ActivityDailySummaryStats.AppDuration],
        daily: [DailySlice]
    ) {
        self.weekKey = weekKey
        self.startDate = startDate
        self.endDate = endDate
        self.totalActiveMs = totalActiveMs
        self.sessionCount = sessionCount
        self.clickCount = clickCount
        self.keypressCount = keypressCount
        self.inputEventsPerMinute = inputEventsPerMinute
        self.apps = apps
        self.daily = daily
    }
}

/// Alma `activity_summaries` row shape for a day. DayHelm computes this on demand and never calls an LLM,
/// so `summary` / `model` stay `nil`.
public struct DailyActivitySummaryRecord: Sendable, Equatable, Codable {

    private enum CodingKeys: String, CodingKey {
        case id, kind, dateKey, summary, stats, model, isPartial, createdAt, updatedAt
    }
    public let id: String
    public let kind: String
    public let dateKey: String
    public let summary: String?
    public let stats: ActivityDailySummaryStats
    public let model: String?
    public let isPartial: Bool
    public let createdAt: Int64
    public let updatedAt: Int64

    public init(
        id: String,
        dateKey: String,
        summary: String? = nil,
        stats: ActivityDailySummaryStats,
        model: String? = nil,
        isPartial: Bool,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.kind = "daily"
        self.dateKey = dateKey
        self.summary = summary
        self.stats = stats
        self.model = model
        self.isPartial = isPartial
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Encodes `summary` / `model` as explicit JSON `null` (Alma's row shape always includes those keys).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(summary, forKey: .summary)
        try container.encode(stats, forKey: .stats)
        try container.encode(model, forKey: .model)
        try container.encode(isPartial, forKey: .isPartial)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Alma `activity_summaries` row shape for an ISO week.
public struct WeeklyActivitySummaryRecord: Sendable, Equatable, Codable {

    private enum CodingKeys: String, CodingKey {
        case id, kind, dateKey, summary, stats, model, isPartial, createdAt, updatedAt
    }
    public let id: String
    public let kind: String
    public let dateKey: String
    public let summary: String?
    public let stats: ActivityWeeklySummaryStats
    public let model: String?
    public let isPartial: Bool
    public let createdAt: Int64
    public let updatedAt: Int64

    public init(
        id: String,
        weekKey: String,
        summary: String? = nil,
        stats: ActivityWeeklySummaryStats,
        model: String? = nil,
        isPartial: Bool,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.kind = "weekly"
        self.dateKey = weekKey
        self.summary = summary
        self.stats = stats
        self.model = model
        self.isPartial = isPartial
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Encodes `summary` / `model` as explicit JSON `null` (Alma's row shape always includes those keys).
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(dateKey, forKey: .dateKey)
        try container.encode(summary, forKey: .summary)
        try container.encode(stats, forKey: .stats)
        try container.encode(model, forKey: .model)
        try container.encode(isPartial, forKey: .isPartial)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// Alma-compatible `/api/activity-recorder/digest` response payload.
public struct ActivityDigestSummary: Sendable, Equatable, Codable {
    public let sinceMs: Int64
    public let untilMs: Int64
    public let hours: Int
    public let sessionCount: Int
    public let totalActiveMs: Int64
    public let eventCount: Int
    public let snapshotCount: Int
    public let ocrFrameCount: Int
    public let clickCount: Int
    public let keypressCount: Int
    public let inputEventsPerMinute: Double
    public let topApps: [ActivityDailySummaryStats.AppDuration]
    public let topDomains: [String]
    public let highlights: [String]

    public init(
        sinceMs: Int64,
        untilMs: Int64,
        hours: Int,
        sessionCount: Int,
        totalActiveMs: Int64,
        eventCount: Int,
        snapshotCount: Int,
        ocrFrameCount: Int,
        clickCount: Int,
        keypressCount: Int,
        inputEventsPerMinute: Double,
        topApps: [ActivityDailySummaryStats.AppDuration],
        topDomains: [String],
        highlights: [String]
    ) {
        self.sinceMs = sinceMs
        self.untilMs = untilMs
        self.hours = hours
        self.sessionCount = sessionCount
        self.totalActiveMs = totalActiveMs
        self.eventCount = eventCount
        self.snapshotCount = snapshotCount
        self.ocrFrameCount = ocrFrameCount
        self.clickCount = clickCount
        self.keypressCount = keypressCount
        self.inputEventsPerMinute = inputEventsPerMinute
        self.topApps = topApps
        self.topDomains = topDomains
        self.highlights = highlights
    }
}

/// Alma-compatible deterministic skeleton report (`/api/activity-recorder/report/<dateKey>`, no LLM).
public struct ActivityDailyReport: Sendable, Equatable, Codable {
    public let dateKey: String
    public let skeletonOnly: Bool
    public let markdown: String
    public let stats: ActivityDailySummaryStats

    public init(
        dateKey: String,
        skeletonOnly: Bool = true,
        markdown: String,
        stats: ActivityDailySummaryStats
    ) {
        self.dateKey = dateKey
        self.skeletonOnly = skeletonOnly
        self.markdown = markdown
        self.stats = stats
    }

    public static func renderMarkdown(dateKey: String, stats: ActivityDailySummaryStats) -> String {
        let activeMinutes = Int((Double(stats.totalActiveMs) / 60_000.0).rounded())
        var lines: [String] = [
            "# Activity Report · \(dateKey)",
            "",
            "- Sessions: \(stats.sessionCount)",
            "- Active Time: \(activeMinutes)m (\(stats.totalActiveMs) ms)",
            "- Events: \(stats.eventCount) (Clicks: \(stats.clickCount), Keypresses: \(stats.keypressCount), \(String(format: "%.1f", stats.inputEventsPerMinute))/min)",
            "- Snapshots: \(stats.snapshotCount) · OCR Frames: \(stats.ocrFrameCount) (\(stats.ocrCharCount) chars)"
        ]
        if !stats.apps.isEmpty {
            lines.append("")
            lines.append("## Top Applications")
            for entry in stats.apps {
                let mins = Int((Double(entry.durationMs) / 60_000.0).rounded())
                lines.append("- \(entry.app): \(mins)m")
            }
        }
        if !stats.keyMoments.isEmpty {
            lines.append("")
            lines.append("## Key Moments")
            for moment in stats.keyMoments {
                let mins = Int((Double(moment.durationMs) / 60_000.0).rounded())
                lines.append("- \(moment.title) (\(mins)m)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum ActivitySummaryError: Error, CustomStringConvertible, Equatable {
    case invalidDateKey(String)
    case invalidWeekKey(String)

    public var description: String {
        switch self {
        case .invalidDateKey(let value):
            return "Invalid date key '\(value)'. Expected YYYY-MM-DD."
        case .invalidWeekKey(let value):
            return "Invalid week key '\(value)'. Expected YYYY-Www or YYYY-MM-DD."
        }
    }
}

/// ISO-8601 week helpers in the app's fixed Asia/Shanghai day domain.
public enum DayHelmISOWeek {
    public static let timeZone = DayHelmDateFormatting.shanghaiTimeZone

    private static func isoCalendar() -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = timeZone
        return cal
    }

    /// `2026-11-17` → `2026-W47`.
    public static func weekKey(for date: Date) -> String {
        let comps = isoCalendar().dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = comps.yearForWeekOfYear ?? 1970
        let week = comps.weekOfYear ?? 1
        return String(format: "%04d-W%02d", year, week)
    }

    public static func weekKey(fromDateKey dateKey: String) -> String? {
        guard let date = DayHelmDateFormatting.parseDayString(dateKey) else { return nil }
        return weekKey(for: date)
    }

    /// Accepts `YYYY-Www` or a `YYYY-MM-DD` date inside the week. Returns the Monday 00:00 (inclusive)
    /// and the following Monday 00:00 (exclusive) in the app time zone.
    public static func dateRange(forWeekKey raw: String) -> (start: Date, end: Date)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let cal = isoCalendar()

        if let date = DayHelmDateFormatting.parseDayString(trimmed) {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return range(year: comps.yearForWeekOfYear, week: comps.weekOfYear, calendar: cal)
        }

        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: true)
        guard parts.count == 2,
              parts[0].count == 4,
              let year = Int(parts[0]),
              parts[1].count == 3,
              (parts[1].first == "W" || parts[1].first == "w"),
              let week = Int(parts[1].dropFirst()),
              (1...53).contains(week) else {
            return nil
        }
        return range(year: year, week: week, calendar: cal)
    }

    public static func dateKey(for date: Date) -> String {
        DayHelmDateFormatting.dayString(from: date, timeZone: timeZone)
    }

    private static func range(year: Int?, week: Int?, calendar: Calendar) -> (start: Date, end: Date)? {
        guard let year, let week else { return nil }
        var comps = DateComponents()
        comps.yearForWeekOfYear = year
        comps.weekOfYear = week
        comps.weekday = 2 // Monday in Gregorian
        guard let start = calendar.date(from: comps) else { return nil }
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return nil }
        return (start, end)
    }
}
