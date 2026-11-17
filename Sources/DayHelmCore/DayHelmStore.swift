import Foundation

public struct ActiveFocusSnapshot: Sendable, Equatable, Codable {
    public let taskId: String
    public let startedAt: Date

    public init(taskId: String, startedAt: Date) {
        self.taskId = taskId
        self.startedAt = startedAt
    }
}

public enum BudgetStatusCode: String, Sendable, Equatable, Codable {
    case underTarget = "under_target"
    case targetMet = "target_met"
    case approachingCap = "approaching_cap"
    case capReached = "cap_reached"
    case noBudget = "no_budget"

    public init(from status: BudgetStatus) {
        switch status {
        case .underTarget:
            self = .underTarget
        case .targetMet:
            self = .targetMet
        case .approachingCap:
            self = .approachingCap
        case .capReached:
            self = .capReached
        case .noBudget:
            self = .noBudget
        }
    }
}

public struct BudgetSnapshot: Sendable, Equatable, Codable {
    public let taskId: String
    public let displayName: String
    public let focusedMinutes: Double
    public let targetMinutes: Int?
    public let capMinutes: Int?
    public let status: BudgetStatusCode

    public init(
        taskId: String,
        displayName: String,
        focusedMinutes: Double,
        targetMinutes: Int?,
        capMinutes: Int?,
        status: BudgetStatusCode
    ) {
        self.taskId = taskId
        self.displayName = displayName
        self.focusedMinutes = focusedMinutes
        self.targetMinutes = targetMinutes
        self.capMinutes = capMinutes
        self.status = status
    }
}

public struct DayHelmDaySnapshot: Sendable, Equatable, Codable {
    public let schemaVersion: Int
    public let date: String
    public let focusState: FocusSessionState?
    public let activeFocus: ActiveFocusSnapshot?
    public let budgets: [BudgetSnapshot]
    public let focusSessions: [FocusSessionRecord]
    public let enrichedSpans: [EnrichedSpan]
    public let metrics: DayMetrics

    public init(
        schemaVersion: Int = 1,
        date: String,
        focusState: FocusSessionState? = nil,
        activeFocus: ActiveFocusSnapshot? = nil,
        budgets: [BudgetSnapshot],
        focusSessions: [FocusSessionRecord],
        enrichedSpans: [EnrichedSpan],
        metrics: DayMetrics
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.focusState = focusState
        self.activeFocus = activeFocus
        self.budgets = budgets
        self.focusSessions = focusSessions
        self.enrichedSpans = enrichedSpans
        self.metrics = metrics
    }
}

public struct DayHelmSettings: Sendable, Equatable, Codable {
    public var deepRecordingEnabled: Bool
    public var snapshotRetentionDays: Int

    public static let `default` = DayHelmSettings()

    public init(
        deepRecordingEnabled: Bool = true,
        snapshotRetentionDays: Int = 7
    ) {
        self.deepRecordingEnabled = deepRecordingEnabled
        self.snapshotRetentionDays = max(1, snapshotRetentionDays)
    }
}

public final class DayHelmStore: @unchecked Sendable {
    public let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/alma/dayhelm", isDirectory: true)
    }

    public var todayURL: URL {
        directory.appendingPathComponent("today.json")
    }

    public var daysDirectory: URL {
        directory.appendingPathComponent("days", isDirectory: true)
    }

    public var snapshotsDirectory: URL {
        directory.appendingPathComponent("snapshots", isDirectory: true)
    }

    public var databaseURL: URL {
        directory.appendingPathComponent("activity.sqlite")
    }

    public var configURL: URL {
        directory.appendingPathComponent("config.json")
    }

    public init(directory: URL = defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = DayHelmDateFormatting.makeEncoder()
        self.decoder = DayHelmDateFormatting.makeDecoder()
    }

    public func saveToday(_ snapshot: DayHelmDaySnapshot) throws {
        try ensureDirectory(directory)
        let data = try encoder.encode(snapshot)
        try writeAtomically(data: data, to: todayURL, tempURL: directory.appendingPathComponent("today.json.tmp"))
    }

    public func loadToday() throws -> DayHelmDaySnapshot? {
        guard fileManager.fileExists(atPath: todayURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: todayURL)
        return try decoder.decode(DayHelmDaySnapshot.self, from: data)
    }

    public func archiveDay(_ snapshot: DayHelmDaySnapshot) throws {
        try ensureDirectory(daysDirectory)
        let dayURL = daysDirectory.appendingPathComponent("\(snapshot.date).json")
        let tmpURL = daysDirectory.appendingPathComponent("\(snapshot.date).json.tmp")
        let data = try encoder.encode(snapshot)
        try writeAtomically(data: data, to: dayURL, tempURL: tmpURL)
    }

    public func loadDay(dateString: String) throws -> DayHelmDaySnapshot? {
        let dayURL = daysDirectory.appendingPathComponent("\(dateString).json")
        guard fileManager.fileExists(atPath: dayURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: dayURL)
        return try decoder.decode(DayHelmDaySnapshot.self, from: data)
    }

    private struct DayHelmConfigFileDTO: Codable {
        var budgets: [TaskBudget]?
        var deepRecordingEnabled: Bool?
        var snapshotRetentionDays: Int?
    }

    private func loadConfigDTO() -> DayHelmConfigFileDTO {
        guard fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let decoded = try? decoder.decode(DayHelmConfigFileDTO.self, from: data) else {
            return DayHelmConfigFileDTO(budgets: nil, deepRecordingEnabled: nil, snapshotRetentionDays: nil)
        }
        return decoded
    }

    public func saveBudgets(_ budgets: [TaskBudget]) throws {
        try ensureDirectory(directory)
        var payload = loadConfigDTO()
        payload.budgets = budgets
        let data = try encoder.encode(payload)
        try writeAtomically(data: data, to: configURL, tempURL: directory.appendingPathComponent("config.json.tmp"))
    }

    public func loadSettings() -> DayHelmSettings {
        let dto = loadConfigDTO()
        return DayHelmSettings(
            deepRecordingEnabled: dto.deepRecordingEnabled ?? true,
            snapshotRetentionDays: dto.snapshotRetentionDays ?? 7
        )
    }

    public func saveSettings(_ settings: DayHelmSettings) throws {
        try ensureDirectory(directory)
        var payload = loadConfigDTO()
        payload.deepRecordingEnabled = settings.deepRecordingEnabled
        payload.snapshotRetentionDays = max(1, settings.snapshotRetentionDays)
        let data = try encoder.encode(payload)
        try writeAtomically(data: data, to: configURL, tempURL: directory.appendingPathComponent("config.json.tmp"))
    }

    @discardableResult
    public func rolloverIfNeeded(currentSnapshot: DayHelmDaySnapshot, newDateString: String) throws -> Bool {
        guard currentSnapshot.date != newDateString else {
            return false
        }
        try archiveDay(currentSnapshot)
        if fileManager.fileExists(atPath: todayURL.path) {
            try fileManager.removeItem(at: todayURL)
        }
        return true
    }

    @discardableResult
    public func purge(before cutoffDate: Date? = nil) throws -> (deletedFiles: Int, deletedBytes: Int64) {
        guard fileManager.fileExists(atPath: directory.path) else {
            return (0, 0)
        }

        var deletedFiles = 0
        var deletedBytes: Int64 = 0

        if let cutoffDate {
            let cutoffDay = DayHelmDateFormatting.dayString(from: cutoffDate)

            if fileManager.fileExists(atPath: daysDirectory.path) {
                let items = try fileManager.contentsOfDirectory(at: daysDirectory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
                for item in items where item.pathExtension == "json" {
                    let stem = item.deletingPathExtension().lastPathComponent
                    if stem < cutoffDay {
                        let size = fileSize(at: item)
                        try fileManager.removeItem(at: item)
                        deletedFiles += 1
                        deletedBytes += size
                    }
                }
            }

            if let today = try? loadToday(), today.date < cutoffDay {
                let size = fileSize(at: todayURL)
                try fileManager.removeItem(at: todayURL)
                deletedFiles += 1
                deletedBytes += size
            }

            if fileManager.fileExists(atPath: databaseURL.path) {
                let db = try ActivityDatabase(databaseURL: databaseURL)
                let dbPurge = try db.purgeRecords(before: cutoffDate, snapshotsRootDir: snapshotsDirectory)
                deletedFiles += dbPurge.deletedFiles
                deletedBytes += dbPurge.deletedBytes
            } else if fileManager.fileExists(atPath: snapshotsDirectory.path) {
                let dayDirs = (try? fileManager.contentsOfDirectory(at: snapshotsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
                for dayDir in dayDirs where dayDir.lastPathComponent < cutoffDay {
                    let files = (try? fileManager.contentsOfDirectory(at: dayDir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])) ?? []
                    for file in files {
                        deletedBytes += fileSize(at: file)
                        try fileManager.removeItem(at: file)
                        deletedFiles += 1
                    }
                    try? fileManager.removeItem(at: dayDir)
                }
            }

            return (deletedFiles, deletedBytes)
        }

        // Full purge: permanently remove all files under directory (no soft delete, no backup).
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            var fileURLs: [URL] = []
            for case let fileURL as URL in enumerator {
                let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true {
                    fileURLs.append(fileURL)
                }
            }
            for fileURL in fileURLs {
                deletedBytes += fileSize(at: fileURL)
                try fileManager.removeItem(at: fileURL)
                deletedFiles += 1
            }
        }

        for subDir in [daysDirectory, snapshotsDirectory] where fileManager.fileExists(atPath: subDir.path) {
            try? fileManager.removeItem(at: subDir)
        }

        return (deletedFiles, deletedBytes)
    }

    // MARK: - Private Helpers

    private func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func writeAtomically(data: Data, to destinationURL: URL, tempURL: URL) throws {
        if fileManager.fileExists(atPath: tempURL.path) {
            try fileManager.removeItem(at: tempURL)
        }
        try data.write(to: tempURL, options: [])
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: tempURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: tempURL, to: destinationURL)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}
