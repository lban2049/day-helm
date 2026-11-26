import Foundation

public struct DayHelmCLIResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String = "", stderr: String = "") {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum DayHelmCLIFormat: String, Sendable {
    case md
    case json
}

private struct CLIQueryPayload: Codable {
    let date: String
    let since: String
    let until: String
    let focusState: String
    let activeTaskId: String?
    let budgets: [BudgetSnapshot]
    let metrics: DayMetrics
    let activity: AgentActivityContext
}

private struct CLISearchPayload: Codable {
    let keyword: String
    let count: Int
    let hits: [ActivitySearchHit]
}

private struct CLISessionsListPayload: Codable {
    let date: String
    let count: Int
    let sessions: [RecordedSessionSummary]
}

private struct CLIRecorderCounts: Codable {
    let sessions: Int
    let events: Int
    let snapshots: Int
    let ocrFrames: Int
    let clickCount: Int
    let keypressCount: Int
    let inputEventsPerMinute: Double
}

private struct CLIStatusPayload: Codable {
    let schemaVersion: Int
    let date: String
    let focusState: FocusSessionState
    let activeTaskId: String?
    let budgets: [BudgetSnapshot]
    let metrics: DayMetrics
    let recorder: CLIRecorderCounts?
}

public enum DayHelmCLI {
    /// Parses and runs CLI subcommands (`query`, `search`, `sessions`, `status`, `purge`, `--help`).
    /// Returns `nil` when the process should continue to launch the GUI app.
    public static func run(
        arguments: [String],
        clock: any DayHelmClock = SystemClock()
    ) -> DayHelmCLIResult? {
        let args = Array(arguments.dropFirst())
        guard let first = args.first else {
            return nil
        }

        switch first {
        case "query":
            return runQuery(args: Array(args.dropFirst()), clock: clock)
        case "search":
            return runSearch(args: Array(args.dropFirst()), clock: clock)
        case "sessions":
            return runSessions(args: Array(args.dropFirst()), clock: clock)
        case "stats":
            return runStats(args: Array(args.dropFirst()), clock: clock)
        case "purge":
            return runPurge(args: Array(args.dropFirst()))
        case "status":
            return runStatus(args: Array(args.dropFirst()), clock: clock)
        case "--help", "-h", "help":
            return DayHelmCLIResult(exitCode: 0, stdout: helpText)
        case "--synthetic-demo":
            return nil
        default:
            if first.hasPrefix("-psn_") || first.hasPrefix("-NS") || first.hasPrefix("-Apple") {
                return nil
            }
            return DayHelmCLIResult(
                exitCode: 1,
                stderr: "Error: Unknown command or option '\(first)'. Run 'dayhelm --help' for usage.\n"
            )
        }
    }

    private static var helpText: String {
        """
        DayHelm (日舵) - Standalone Native Activity Recorder & Focus Quota Assistant

        Usage:
          dayhelm                                      Launch MenuBar UI
          dayhelm --synthetic-demo                     Launch MenuBar UI in synthetic demo mode
          dayhelm query [--today | --since <2h|30m|YYYY-MM-DD>] [--format json|md] [--store-dir <path>]
                                                       Query activity timeline, budgets, windows, URLs & OCR
          dayhelm search <keyword> [--limit 20] [--format json|md] [--store-dir <path>]
                                                       Search window titles, URLs, sessions & OCR text
          dayhelm sessions [--date YYYY-MM-DD] [--id <session_id>] [--limit 50] [--format json|md] [--store-dir <path>]
                                                       List sessions or inspect full session details
          dayhelm stats [--date YYYY-MM-DD] [--format json|md] [--json] [--store-dir <path>]
                                                       Deterministic daily telemetry, allocation & switch stats
          dayhelm status [--format json|md] [--store-dir <path>]
                                                       Print today's budget & telemetry summary (--json alias for --format json)
          dayhelm purge [--before YYYY-MM-DD] [--store-dir <path>]
                                                       Permanently delete stored JSON, SQLite & snapshot data
          dayhelm --help                               Show this help message
        """ + "\n"
    }

    // MARK: - query

    private static func runQuery(args: [String], clock: any DayHelmClock) -> DayHelmCLIResult {
        var sinceSpec: String?
        var format: DayHelmCLIFormat = .md
        var storeDirPath: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--today":
                sinceSpec = nil
                i += 1
            case "--since":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --since requires a duration or date argument (e.g. 2h, 30m, 2026-11-17).\n")
                }
                sinceSpec = args[i + 1]
                i += 2
            case "--format":
                guard i + 1 < args.count, let parsed = DayHelmCLIFormat(rawValue: args[i + 1].lowercased()) else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --format must be 'json' or 'md'.\n")
                }
                format = parsed
                i += 2
            case "--store-dir":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --store-dir requires a directory path.\n")
                }
                storeDirPath = args[i + 1]
                i += 2
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'query'.\n")
            }
        }

        let now = clock.now()
        let sinceDate: Date
        if let sinceSpec {
            guard let parsed = parseSinceSpec(sinceSpec, now: now) else {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Invalid --since value '\(sinceSpec)'. Use <N>m, <N>h, <N>d, YYYY-MM-DD, or ISO8601.\n")
            }
            sinceDate = parsed
        } else {
            sinceDate = startOfDay(for: now)
        }

        let directory = resolveDirectory(storeDirPath)
        let store = DayHelmStore(directory: directory)
        let todayString = DayHelmDateFormatting.dayString(from: now)
        let summary = loadFocusAndBudgets(store: store, storeDirPath: storeDirPath, todayString: todayString)

        let sinceMs = Int64(sinceDate.timeIntervalSince1970 * 1000)
        let untilMs = Int64(now.timeIntervalSince1970 * 1000)

        let activityContext: AgentActivityContext
        if FileManager.default.fileExists(atPath: store.databaseURL.path) {
            do {
                let db = try ActivityDatabase(databaseURL: store.databaseURL)
                activityContext = try db.queryAgentContext(sinceMs: sinceMs, untilMs: untilMs, maxOCRChars: 2400)
            } catch {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Failed to query activity.sqlite: \(error)\n")
            }
        } else {
            activityContext = AgentActivityContext(
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
        }

        let payload = CLIQueryPayload(
            date: summary.activeDate,
            since: DayHelmDateFormatting.iso8601String(from: sinceDate),
            until: DayHelmDateFormatting.iso8601String(from: now),
            focusState: summary.focusDescription,
            activeTaskId: summary.activeTaskId,
            budgets: summary.budgets,
            metrics: summary.metrics,
            activity: activityContext
        )

        if format == .json {
            return encodeJSONResult(payload)
        }

        var lines: [String] = []
        lines.append("# DayHelm Activity Context (\(payload.date))")
        lines.append("")
        lines.append("- Window: `\(payload.since)` .. `\(payload.until)`")
        lines.append("- Focus State: \(payload.focusState)")
        lines.append(String(format: "- Telemetry: active=%.0fm, longest_block=%.0fm, solid_blocks=%d, switches=%.1f/h",
                            payload.metrics.activeMinutes,
                            payload.metrics.longestBlockMinutes,
                            payload.metrics.solidBlocksCount,
                            payload.metrics.recentSwitchesPerHour))
        lines.append("- Recorded Activity: \(activityContext.sessionCount) sessions, \(activityContext.eventCount) events, \(activityContext.snapshotCount) snapshots, \(activityContext.ocrFrameCount) OCR frames")
        lines.append("")
        lines.append("## Daily Task Budgets")
        for b in payload.budgets {
            let focusedStr = String(format: "%.0fm", b.focusedMinutes)
            let quotaStr = formatQuota(target: b.targetMinutes, cap: b.capMinutes)
            lines.append("- **\(b.displayName)** [`\(b.taskId)`]: \(focusedStr) (\(quotaStr), `\(b.status.rawValue)`)")
        }

        if !activityContext.sessions.isEmpty {
            lines.append("")
            lines.append("## Recorded Sessions")
            for s in activityContext.sessions.prefix(15) {
                let durMin = Double(s.durationMs ?? 0) / 60_000.0
                let apps = s.appNames.isEmpty ? "-" : s.appNames.joined(separator: ", ")
                let title = s.analysisTitle ?? "(untitled)"
                let taskBadge = s.declaredTaskId.map { " [task: `\($0)`]" } ?? ""
                lines.append(String(format: "- `%@` (%@ .. %@, %.1fm)%@ — %@ | Apps: %@",
                                    s.id,
                                    formatTimeHHmmss(ms: s.startedAt),
                                    s.endedAt.map { formatTimeHHmmss(ms: $0) } ?? "active",
                                    durMin,
                                    taskBadge,
                                    title,
                                    apps))
            }
        }

        if !activityContext.recentWindows.isEmpty {
            lines.append("")
            lines.append("## Recent Windows & URLs")
            for w in activityContext.recentWindows {
                let titlePart = w.windowTitle.map { " — \($0)" } ?? ""
                let urlPart = w.url.map { " (`\($0)`)" } ?? ""
                let taskPart = w.declaredTaskId.map { " [task: `\($0)`]" } ?? ""
                lines.append("- [\(formatTimeHHmmss(ms: w.lastSeenAt))] **\(w.appName)**\(titlePart)\(urlPart)\(taskPart)")
            }
        }

        if !activityContext.ocrHighlights.isEmpty {
            lines.append("")
            lines.append("## OCR Highlights")
            for ocr in activityContext.ocrHighlights {
                let appLabel = ocr.appName ?? "Screen"
                let winLabel = ocr.windowTitle.map { " (\($0))" } ?? ""
                let singleLine = ocr.text.replacingOccurrences(of: "\n", with: " ")
                lines.append("- [\(formatTimeHHmmss(ms: ocr.timestamp))] **\(appLabel)**\(winLabel): \(singleLine)")
            }
        }

        return DayHelmCLIResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n")
    }

    // MARK: - search

    private static func runSearch(args: [String], clock _: any DayHelmClock) -> DayHelmCLIResult {
        var keywordParts: [String] = []
        var limit = 20
        var format: DayHelmCLIFormat = .md
        var storeDirPath: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--limit":
                guard i + 1 < args.count, let parsed = Int(args[i + 1]), parsed > 0 else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --limit requires a positive integer.\n")
                }
                limit = parsed
                i += 2
            case "--format":
                guard i + 1 < args.count, let parsed = DayHelmCLIFormat(rawValue: args[i + 1].lowercased()) else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --format must be 'json' or 'md'.\n")
                }
                format = parsed
                i += 2
            case "--store-dir":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --store-dir requires a directory path.\n")
                }
                storeDirPath = args[i + 1]
                i += 2
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                if arg.hasPrefix("--") {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'search'.\n")
                }
                keywordParts.append(arg)
                i += 1
            }
        }

        let keyword = keywordParts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return DayHelmCLIResult(exitCode: 1, stderr: "Error: 'search' requires a <keyword> argument.\n")
        }

        let directory = resolveDirectory(storeDirPath)
        let store = DayHelmStore(directory: directory)
        let hits: [ActivitySearchHit]

        if FileManager.default.fileExists(atPath: store.databaseURL.path) {
            do {
                let db = try ActivityDatabase(databaseURL: store.databaseURL)
                hits = try db.search(keyword: keyword, limit: limit)
            } catch {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Failed to search activity.sqlite: \(error)\n")
            }
        } else {
            hits = []
        }

        if format == .json {
            return encodeJSONResult(CLISearchPayload(keyword: keyword, count: hits.count, hits: hits))
        }

        var lines: [String] = []
        lines.append("# DayHelm Search: \"\(keyword)\" (\(hits.count) hits)")
        if hits.isEmpty {
            lines.append("")
            lines.append("No matching sessions, window titles, URLs, or OCR frames found.")
        } else {
            lines.append("")
            for hit in hits {
                let ts = formatDateTime(ms: hit.timestamp)
                let app = hit.appName ?? "Unknown"
                let win = hit.windowTitle.map { " — \($0)" } ?? ""
                let urlPart = hit.url.map { " (`\($0)`)" } ?? ""
                let taskPart = hit.declaredTaskId.map { " [task: `\($0)`]" } ?? ""
                lines.append("- [\(ts)] [`\(hit.sourceKind)`] **\(app)**\(win)\(urlPart)\(taskPart) (session `\(hit.sessionId)`): \(hit.snippet)")
            }
        }
        return DayHelmCLIResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n")
    }

    // MARK: - sessions

    private static func runSessions(args: [String], clock: any DayHelmClock) -> DayHelmCLIResult {
        var dateString: String?
        var sessionId: String?
        var limit = 50
        var format: DayHelmCLIFormat = .md
        var storeDirPath: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--date":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --date requires a YYYY-MM-DD argument.\n")
                }
                dateString = args[i + 1]
                i += 2
            case "--id":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --id requires a session ID.\n")
                }
                sessionId = args[i + 1]
                i += 2
            case "--limit":
                guard i + 1 < args.count, let parsed = Int(args[i + 1]), parsed > 0 else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --limit requires a positive integer.\n")
                }
                limit = parsed
                i += 2
            case "--format":
                guard i + 1 < args.count, let parsed = DayHelmCLIFormat(rawValue: args[i + 1].lowercased()) else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --format must be 'json' or 'md'.\n")
                }
                format = parsed
                i += 2
            case "--store-dir":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --store-dir requires a directory path.\n")
                }
                storeDirPath = args[i + 1]
                i += 2
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'sessions'.\n")
            }
        }

        let directory = resolveDirectory(storeDirPath)
        let store = DayHelmStore(directory: directory)

        if let sessionId {
            guard FileManager.default.fileExists(atPath: store.databaseURL.path) else {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Session '\(sessionId)' not found (no activity.sqlite).\n")
            }
            do {
                let db = try ActivityDatabase(databaseURL: store.databaseURL)
                guard let detail = try db.getSessionDetail(sessionId: sessionId) else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: Session '\(sessionId)' not found.\n")
                }
                if format == .json {
                    return encodeJSONResult(detail)
                }
                return DayHelmCLIResult(exitCode: 0, stdout: formatSessionDetailMarkdown(detail))
            } catch {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Failed to load session '\(sessionId)': \(error)\n")
            }
        }

        let targetDayString = dateString ?? DayHelmDateFormatting.dayString(from: clock.now())
        guard let dayStart = DayHelmDateFormatting.parseDayString(targetDayString) else {
            return DayHelmCLIResult(exitCode: 1, stderr: "Error: Invalid date '\(targetDayString)'. Expected YYYY-MM-DD.\n")
        }
        let dayEnd = dayStart.addingTimeInterval(86_400)
        let sinceMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let untilMs = Int64(dayEnd.timeIntervalSince1970 * 1000) - 1

        let sessions: [RecordedSessionSummary]
        if FileManager.default.fileExists(atPath: store.databaseURL.path) {
            do {
                let db = try ActivityDatabase(databaseURL: store.databaseURL)
                sessions = try db.listSessions(sinceMs: sinceMs, untilMs: untilMs, limit: limit)
            } catch {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Failed to list sessions: \(error)\n")
            }
        } else {
            sessions = []
        }

        if format == .json {
            return encodeJSONResult(CLISessionsListPayload(date: targetDayString, count: sessions.count, sessions: sessions))
        }

        var lines: [String] = []
        lines.append("# DayHelm Sessions (\(targetDayString), \(sessions.count) total)")
        if sessions.isEmpty {
            lines.append("")
            lines.append("No sessions recorded for \(targetDayString).")
        } else {
            lines.append("")
            for s in sessions {
                let durMin = Double(s.durationMs ?? 0) / 60_000.0
                let apps = s.appNames.isEmpty ? "-" : s.appNames.joined(separator: ", ")
                let title = s.analysisTitle ?? "(untitled)"
                let taskBadge = s.declaredTaskId.map { " [task: `\($0)`]" } ?? ""
                lines.append(String(format: "- `%@` %@..%@ (%.1fm)%@ — %@ | apps: %@ | events: %d, snapshots: %d",
                                    s.id,
                                    formatTimeHHmmss(ms: s.startedAt),
                                    s.endedAt.map { formatTimeHHmmss(ms: $0) } ?? "active",
                                    durMin,
                                    taskBadge,
                                    title,
                                    apps,
                                    s.eventCount,
                                    s.snapshotCount))
            }
        }
        return DayHelmCLIResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n")
    }

    // MARK: - stats

    private static func runStats(args: [String], clock: any DayHelmClock) -> DayHelmCLIResult {
        var dateString: String?
        var format: DayHelmCLIFormat = .md
        var storeDirPath: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--date":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --date requires a YYYY-MM-DD argument.\n")
                }
                dateString = args[i + 1]
                i += 2
            case "--json":
                format = .json
                i += 1
            case "--format":
                guard i + 1 < args.count, let parsed = DayHelmCLIFormat(rawValue: args[i + 1].lowercased()) else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --format must be 'json' or 'md'.\n")
                }
                format = parsed
                i += 2
            case "--store-dir":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --store-dir requires a directory path.\n")
                }
                storeDirPath = args[i + 1]
                i += 2
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'stats'.\n")
            }
        }

        let targetDate = dateString ?? DayHelmDateFormatting.dayString(from: clock.now())
        guard targetDate.count == 10,
              let parsedDate = DayHelmDateFormatting.parseDayString(targetDate),
              DayHelmDateFormatting.dayString(from: parsedDate) == targetDate else {
            return DayHelmCLIResult(exitCode: 1, stderr: "Error: Invalid date '\(targetDate)'. Expected YYYY-MM-DD.\n")
        }

        let directory = resolveDirectory(storeDirPath)
        let store = DayHelmStore(directory: directory)
        let budgets = storeDirPath == nil
            ? TimeAuditConfigLoader.loadBudgets()
            : TimeAuditConfigLoader.loadBudgets(
                timeAuditDirectory: store.directory.appendingPathComponent("__none__", isDirectory: true),
                dayhelmConfigURL: store.configURL
            )
        let database: ActivityDatabase? = FileManager.default.fileExists(atPath: store.databaseURL.path)
            ? (try? ActivityDatabase(databaseURL: store.databaseURL))
            : nil

        let report = DailyStatsAggregator.aggregate(
            dateString: targetDate,
            liveSnapshot: nil,
            budgets: budgets,
            store: store,
            database: database,
            clock: clock,
            includeBaseline: true
        )

        if format == .json {
            return encodeJSONResult(report)
        }
        return DayHelmCLIResult(exitCode: 0, stdout: DailyStatsMarkdownRenderer.render(report))
    }

    // MARK: - purge

    private static func runPurge(args: [String]) -> DayHelmCLIResult {
        var beforeString: String?
        var storeDirPath: String?

        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--before":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --before requires a YYYY-MM-DD date argument.\n")
                }
                beforeString = args[i + 1]
                i += 2
            case "--store-dir":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --store-dir requires a directory path.\n")
                }
                storeDirPath = args[i + 1]
                i += 2
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'purge'.\n")
            }
        }

        var cutoffDate: Date?
        if let beforeString {
            guard let parsed = DayHelmDateFormatting.parseDayString(beforeString) else {
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Invalid date '\(beforeString)'. Expected YYYY-MM-DD.\n")
            }
            cutoffDate = parsed
        }

        let directory = resolveDirectory(storeDirPath)
        let store = DayHelmStore(directory: directory)

        do {
            let result = try store.purge(before: cutoffDate)
            let scopeDesc = beforeString.map { "before \($0)" } ?? "all data in \(directory.path)"
            let out = """
            DayHelm purge completed (\(scopeDesc)).
            Deleted files: \(result.deletedFiles)
            Deleted bytes: \(result.deletedBytes) bytes
            """
            return DayHelmCLIResult(exitCode: 0, stdout: out + "\n")
        } catch {
            return DayHelmCLIResult(exitCode: 1, stderr: "Error: Failed to purge data: \(error.localizedDescription)\n")
        }
    }

    // MARK: - status

    private static func runStatus(args: [String], clock: any DayHelmClock) -> DayHelmCLIResult {
        var storeDirPath: String?
        var format: DayHelmCLIFormat = .md
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--store-dir":
                guard i + 1 < args.count else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --store-dir requires a directory path.\n")
                }
                storeDirPath = args[i + 1]
                i += 2
            case "--json":
                format = .json
                i += 1
            case "--format":
                guard i + 1 < args.count, let parsed = DayHelmCLIFormat(rawValue: args[i + 1]) else {
                    return DayHelmCLIResult(exitCode: 1, stderr: "Error: --format requires 'json' or 'md'.\n")
                }
                format = parsed
                i += 2
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'status'.\n")
            }
        }

        let directory = resolveDirectory(storeDirPath)
        let store = DayHelmStore(directory: directory)
        let todayString = DayHelmDateFormatting.dayString(from: clock.now())
        let summary = loadFocusAndBudgets(store: store, storeDirPath: storeDirPath, todayString: todayString)
        if let loadErr = summary.errorMessage {
            return DayHelmCLIResult(exitCode: 1, stderr: loadErr)
        }

        let recorder = loadRecorderCounts(store: store, now: clock.now())

        if format == .json {
            return encodeJSONResult(CLIStatusPayload(
                schemaVersion: 1,
                date: summary.activeDate,
                focusState: summary.focusState,
                activeTaskId: summary.activeTaskId,
                budgets: summary.budgets,
                metrics: summary.metrics,
                recorder: recorder
            ))
        }

        var lines: [String] = []
        lines.append("DayHelm Status (\(summary.activeDate))")
        lines.append("State: \(summary.focusDescription)")
        lines.append("")
        lines.append("Daily Budgets:")
        for b in summary.budgets {
            let focusedStr = String(format: "%.0fm", b.focusedMinutes)
            let quotaStr = formatQuota(target: b.targetMinutes, cap: b.capMinutes)
            lines.append("  - \(b.displayName) [\(b.taskId)]: \(focusedStr) (\(quotaStr), \(b.status.rawValue))")
        }
        lines.append("")
        lines.append("Telemetry:")
        lines.append(String(format: "  - Active time: %.0fm", summary.metrics.activeMinutes))
        lines.append(String(format: "  - Longest continuous block: %.0fm", summary.metrics.longestBlockMinutes))
        lines.append("  - Solid blocks (>=12m): \(summary.metrics.solidBlocksCount)")
        lines.append(String(format: "  - Recent switches/hr: %.1f/h", summary.metrics.recentSwitchesPerHour))

        if let recorder {
            lines.append("")
            lines.append("Native Recorder (activity.sqlite):")
            lines.append("  - Today sessions: \(recorder.sessions), events: \(recorder.events), snapshots: \(recorder.snapshots), OCR frames: \(recorder.ocrFrames)")
            lines.append(String(
                format: "  - Input density: clicks %d, keypresses %d, %.1f/min",
                recorder.clickCount,
                recorder.keypressCount,
                recorder.inputEventsPerMinute
            ))
        }

        return DayHelmCLIResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n")
    }

    private static func loadRecorderCounts(store: DayHelmStore, now: Date) -> CLIRecorderCounts? {
        guard FileManager.default.fileExists(atPath: store.databaseURL.path),
              let db = try? ActivityDatabase(databaseURL: store.databaseURL) else {
            return nil
        }
        let dayStart = startOfDay(for: now)
        let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
        let dayEndMs = dayStartMs + 86_400_000 - 1
        guard let counts = try? db.todayCounts(dayStartMs: dayStartMs, dayEndMs: dayEndMs) else {
            return nil
        }
        let density = (try? db.dayInputTotals(dayStartMs: dayStartMs, dayEndMs: dayEndMs))
            ?? DayInputTotals(clickCount: 0, keypressCount: 0, totalSessionDurationMs: 0, inputEventsPerMinute: 0)
        return CLIRecorderCounts(
            sessions: counts.sessions,
            events: counts.events,
            snapshots: counts.snapshots,
            ocrFrames: counts.ocrFrames,
            clickCount: density.clickCount,
            keypressCount: density.keypressCount,
            inputEventsPerMinute: density.inputEventsPerMinute
        )
    }

    // MARK: - Helpers

    private static func resolveDirectory(_ storeDirPath: String?) -> URL {
        storeDirPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? DayHelmStore.defaultDirectory
    }

    private struct LoadedStatusSummary {
        let activeDate: String
        let budgets: [BudgetSnapshot]
        let focusDescription: String
        let activeTaskId: String?
        let focusState: FocusSessionState
        let metrics: DayMetrics
        let errorMessage: String?
    }

    private static func loadFocusAndBudgets(
        store: DayHelmStore,
        storeDirPath: String?,
        todayString: String
    ) -> LoadedStatusSummary {
        let snapshot: DayHelmDaySnapshot?
        do {
            snapshot = try store.loadToday()
        } catch {
            return LoadedStatusSummary(
                activeDate: todayString,
                budgets: [],
                focusDescription: "Error",
                activeTaskId: nil,
                focusState: .unassigned,
                metrics: DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0),
                errorMessage: "Error: Failed to read \(store.todayURL.path): \(error.localizedDescription)\n"
            )
        }

        if let snapshot, snapshot.date == todayString {
            let focusDescription: String
            var activeTaskId: String?
            switch snapshot.focusState {
            case .focusing(let taskId, let startedAt):
                let name = snapshot.budgets.first(where: { $0.taskId == taskId })?.displayName ?? taskId
                focusDescription = "Focusing: \(name) (since \(DayHelmDateFormatting.iso8601String(from: startedAt)))"
                activeTaskId = taskId
            case .paused(let taskId, let pausedAt):
                let name = snapshot.budgets.first(where: { $0.taskId == taskId })?.displayName ?? taskId
                focusDescription = "Paused: \(name) (at \(DayHelmDateFormatting.iso8601String(from: pausedAt)))"
            case .unassigned, .none:
                if let active = snapshot.activeFocus {
                    let name = snapshot.budgets.first(where: { $0.taskId == active.taskId })?.displayName ?? active.taskId
                    focusDescription = "Focusing: \(name) (since \(DayHelmDateFormatting.iso8601String(from: active.startedAt)))"
                    activeTaskId = active.taskId
                } else {
                    focusDescription = "Standby (unassigned)"
                }
            }
            return LoadedStatusSummary(
                activeDate: snapshot.date,
                budgets: snapshot.budgets,
                focusDescription: focusDescription,
                activeTaskId: activeTaskId,
                focusState: snapshot.focusState ?? .unassigned,
                metrics: snapshot.metrics,
                errorMessage: nil
            )
        }

        let loadedBudgets = storeDirPath == nil
            ? TimeAuditConfigLoader.loadBudgets()
            : TimeAuditConfigLoader.loadBudgets(
                timeAuditDirectory: store.directory.appendingPathComponent("__none__", isDirectory: true),
                dayhelmConfigURL: store.configURL
            )
        let budgetsToShow = loadedBudgets.map { b in
            BudgetSnapshot(
                taskId: b.taskId,
                displayName: b.displayName,
                focusedMinutes: 0,
                targetMinutes: b.targetMinutes,
                capMinutes: b.capMinutes,
                status: BudgetStatusCode(from: BudgetStatus.compute(focusedMinutes: 0, targetMinutes: b.targetMinutes, capMinutes: b.capMinutes))
            )
        }
        return LoadedStatusSummary(
            activeDate: todayString,
            budgets: budgetsToShow,
            focusDescription: "Standby (no activity recorded for \(todayString))",
            activeTaskId: nil,
            focusState: .unassigned,
            metrics: DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0),
            errorMessage: nil
        )
    }

    private static func formatQuota(target: Int?, cap: Int?) -> String {
        if let cap, let target {
            return "target \(target)m / cap \(cap)m"
        } else if let target {
            return "target \(target)m"
        } else if let cap {
            return "cap \(cap)m"
        } else {
            return "no quota"
        }
    }

    private static func formatSessionDetailMarkdown(_ detail: RecordedSessionDetail) -> String {
        let s = detail.session
        let durMin = Double(s.durationMs ?? 0) / 60_000.0
        var lines: [String] = []
        lines.append("# Session `\(s.id)`")
        lines.append("")
        lines.append("- Title: \(s.analysisTitle ?? "(untitled)")")
        if let desc = s.analysisDescription {
            lines.append("- Description: \(desc)")
        }
        lines.append(String(format: "- Time: `%@` .. `%@` (%.1fm)",
                            formatDateTime(ms: s.startedAt),
                            s.endedAt.map { formatDateTime(ms: $0) } ?? "active",
                            durMin))
        lines.append("- Apps: \(s.appNames.isEmpty ? "-" : s.appNames.joined(separator: ", "))")
        if let task = s.declaredTaskId {
            lines.append("- Declared Task: `\(task)`")
        }

        lines.append("")
        lines.append("## Events (\(detail.events.count))")
        for e in detail.events {
            let app = e.appName ?? "-"
            let title = e.windowTitle.map { " — \($0)" } ?? ""
            let url = e.url.map { " (`\($0)`)" } ?? ""
            lines.append("- [\(formatTimeHHmmss(ms: e.timestamp))] `\(e.kind)` **\(app)**\(title)\(url)")
        }

        lines.append("")
        lines.append("## Snapshots (\(detail.snapshots.count))")
        for snap in detail.snapshots {
            let app = snap.appName ?? "-"
            let title = snap.windowTitle.map { " — \($0)" } ?? ""
            lines.append(String(format: "- [\(formatTimeHHmmss(ms: snap.timestamp))] `\(snap.id)` (%@, %dx%d, %lld bytes, diff=%.1f%%) **%@**%@ -> `%@`",
                                snap.trigger,
                                snap.width,
                                snap.height,
                                snap.sizeBytes,
                                (snap.diffPct ?? 0) * 100.0,
                                app,
                                title,
                                snap.filePath))
        }

        lines.append("")
        lines.append("## OCR Frames (\(detail.ocrFrames.count))")
        for ocr in detail.ocrFrames {
            let oneLine = ocr.text.replacingOccurrences(of: "\n", with: " ")
            lines.append("- [\(formatTimeHHmmss(ms: ocr.createdAt))] `\(ocr.snapshotId)` (\(ocr.charCount) chars): \(oneLine)")
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func encodeJSONResult<T: Encodable>(_ value: T) -> DayHelmCLIResult {
        let encoder = DayHelmDateFormatting.makeEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            let json = String(data: data, encoding: .utf8) ?? "{}"
            return DayHelmCLIResult(exitCode: 0, stdout: json + "\n")
        } catch {
            return DayHelmCLIResult(exitCode: 1, stderr: "Error: JSON encoding failed: \(error)\n")
        }
    }

    public static func parseSinceSpec(_ raw: String, now: Date) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()
        if lower.hasSuffix("m"), let val = Double(lower.dropLast()), val >= 0 {
            return now.addingTimeInterval(-val * 60.0)
        }
        if lower.hasSuffix("h"), let val = Double(lower.dropLast()), val >= 0 {
            return now.addingTimeInterval(-val * 3600.0)
        }
        if lower.hasSuffix("d"), let val = Double(lower.dropLast()), val >= 0 {
            return now.addingTimeInterval(-val * 86_400.0)
        }
        if lower.hasSuffix("s"), let val = Double(lower.dropLast()), val >= 0 {
            return now.addingTimeInterval(-val)
        }
        if let day = DayHelmDateFormatting.parseDayString(trimmed) {
            return day
        }
        return DayHelmDateFormatting.parseISO8601(trimmed)
    }

    private static func startOfDay(for date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        return cal.startOfDay(for: date)
    }

    private static func formatTimeHHmmss(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = DayHelmDateFormatting.shanghaiTimeZone
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: date)
    }

    private static func formatDateTime(ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        return DayHelmDateFormatting.iso8601String(from: date)
    }
}
