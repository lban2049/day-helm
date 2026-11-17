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

public enum DayHelmCLI {
    /// Parses and runs CLI subcommands (`purge`, `status`, `--help`).
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
        case "purge":
            return runPurge(args: Array(args.dropFirst()))
        case "status":
            return runStatus(args: Array(args.dropFirst()), clock: clock)
        case "--help", "-h", "help":
            return DayHelmCLIResult(exitCode: 0, stdout: helpText)
        default:
            return nil
        }
    }

    private static var helpText: String {
        """
        DayHelm (日舵) - macOS Focus Quota & Telemetry Assistant

        Usage:
          dayhelm                                      Launch MenuBar UI
          dayhelm --synthetic-demo                     Launch MenuBar UI in synthetic demo mode
          dayhelm status [--store-dir <path>]          Print today's budget & telemetry summary
          dayhelm purge [--before YYYY-MM-DD] [--store-dir <path>]
                                                       Permanently delete stored capture data
          dayhelm --help                               Show this help message
        """ + "\n"
    }

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

        let directory = storeDirPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? DayHelmStore.defaultDirectory
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

    private static func runStatus(args: [String], clock: any DayHelmClock) -> DayHelmCLIResult {
        var storeDirPath: String?
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
            case "--help", "-h":
                return DayHelmCLIResult(exitCode: 0, stdout: helpText)
            default:
                return DayHelmCLIResult(exitCode: 1, stderr: "Error: Unknown option '\(arg)' for 'status'.\n")
            }
        }

        let directory = storeDirPath.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? DayHelmStore.defaultDirectory
        let store = DayHelmStore(directory: directory)
        let todayString = DayHelmDateFormatting.dayString(from: clock.now())

        let snapshot: DayHelmDaySnapshot?
        do {
            snapshot = try store.loadToday()
        } catch {
            return DayHelmCLIResult(exitCode: 1, stderr: "Error: Failed to read \(store.todayURL.path): \(error.localizedDescription)\n")
        }

        let budgetsToShow: [BudgetSnapshot]
        let focusDescription: String
        let metrics: DayMetrics
        let activeDate: String

        if let snapshot, snapshot.date == todayString {
            activeDate = snapshot.date
            budgetsToShow = snapshot.budgets
            metrics = snapshot.metrics
            switch snapshot.focusState {
            case .focusing(let taskId, let startedAt):
                let name = snapshot.budgets.first(where: { $0.taskId == taskId })?.displayName ?? taskId
                focusDescription = "Focusing: \(name) (since \(DayHelmDateFormatting.iso8601String(from: startedAt)))"
            case .paused(let taskId, let pausedAt):
                let name = snapshot.budgets.first(where: { $0.taskId == taskId })?.displayName ?? taskId
                focusDescription = "Paused: \(name) (at \(DayHelmDateFormatting.iso8601String(from: pausedAt)))"
            case .unassigned, .none:
                if let active = snapshot.activeFocus {
                    let name = snapshot.budgets.first(where: { $0.taskId == active.taskId })?.displayName ?? active.taskId
                    focusDescription = "Focusing: \(name) (since \(DayHelmDateFormatting.iso8601String(from: active.startedAt)))"
                } else {
                    focusDescription = "Standby (unassigned)"
                }
            }
        } else {
            activeDate = todayString
            let loadedBudgets = storeDirPath == nil
                ? TimeAuditConfigLoader.loadBudgets()
                : TimeAuditConfigLoader.loadBudgets(
                    timeAuditDirectory: directory.appendingPathComponent("__none__", isDirectory: true),
                    dayhelmConfigURL: store.configURL
                )
            budgetsToShow = loadedBudgets.map { b in
                BudgetSnapshot(
                    taskId: b.taskId,
                    displayName: b.displayName,
                    focusedMinutes: 0,
                    targetMinutes: b.targetMinutes,
                    capMinutes: b.capMinutes,
                    status: BudgetStatusCode(from: BudgetStatus.compute(focusedMinutes: 0, targetMinutes: b.targetMinutes, capMinutes: b.capMinutes))
                )
            }
            focusDescription = "Standby (no activity recorded for \(todayString))"
            metrics = DayMetrics(activeMinutes: 0, longestBlockMinutes: 0, solidBlocksCount: 0, recentSwitchesPerHour: 0)
        }

        var lines: [String] = []
        lines.append("DayHelm Status (\(activeDate))")
        lines.append("State: \(focusDescription)")
        lines.append("")
        lines.append("Daily Budgets:")
        for b in budgetsToShow {
            let focusedStr = String(format: "%.0fm", b.focusedMinutes)
            let quotaStr: String
            if let cap = b.capMinutes, let target = b.targetMinutes {
                quotaStr = "target \(target)m / cap \(cap)m"
            } else if let target = b.targetMinutes {
                quotaStr = "target \(target)m"
            } else if let cap = b.capMinutes {
                quotaStr = "cap \(cap)m"
            } else {
                quotaStr = "no quota"
            }
            lines.append("  - \(b.displayName) [\(b.taskId)]: \(focusedStr) (\(quotaStr), \(b.status.rawValue))")
        }
        lines.append("")
        lines.append("Telemetry:")
        lines.append(String(format: "  - Active time: %.0fm", metrics.activeMinutes))
        lines.append(String(format: "  - Longest continuous block: %.0fm", metrics.longestBlockMinutes))
        lines.append("  - Solid blocks (>=12m): \(metrics.solidBlocksCount)")
        lines.append(String(format: "  - Recent switches/hr: %.1f/h", metrics.recentSwitchesPerHour))

        return DayHelmCLIResult(exitCode: 0, stdout: lines.joined(separator: "\n") + "\n")
    }
}
