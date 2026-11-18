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
    public static let defaultMaxStorageBytes: Int64 = 10 * 1024 * 1024 * 1024 // 10 GB
    public static let defaultOCRLanguages: [String] = ["zh-Hans", "zh-Hant", "en-US", "ja"]
    public static let defaultSensitiveBundleIds: [String] = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "org.bitwarden.desktop",
        "com.lastpass.LastPass"
    ]

    public var activityRecorderEnabled: Bool
    public var deepRecordingEnabled: Bool
    public var visionOCREnabled: Bool
    public var inputMonitoringEnabled: Bool
    public var appFocusDebounceMs: Int
    public var heartbeatIntervalMs: Int
    public var recorderIdleThresholdMs: Int
    public var typingPauseQuietMs: Int
    public var visualCheckIntervalMs: Int
    public var jpegQuality: Int
    public var ocrLanguages: [String]
    public var sensitiveBundleIds: [String]
    public var snapshotRetentionDays: Int
    public var snapshotMaxStorageBytes: Int64
    public var ocrEveryN: Int

    public static let `default` = DayHelmSettings()

    public init(
        activityRecorderEnabled: Bool = true,
        deepRecordingEnabled: Bool = true,
        visionOCREnabled: Bool = true,
        inputMonitoringEnabled: Bool = true,
        appFocusDebounceMs: Int = 4000,
        heartbeatIntervalMs: Int = 120_000,
        recorderIdleThresholdMs: Int = 300_000,
        typingPauseQuietMs: Int = 2000,
        visualCheckIntervalMs: Int = 12_000,
        jpegQuality: Int = 55,
        ocrLanguages: [String] = DayHelmSettings.defaultOCRLanguages,
        sensitiveBundleIds: [String] = DayHelmSettings.defaultSensitiveBundleIds,
        snapshotRetentionDays: Int = 7,
        snapshotMaxStorageBytes: Int64 = DayHelmSettings.defaultMaxStorageBytes,
        ocrEveryN: Int = 1
    ) {
        self.activityRecorderEnabled = activityRecorderEnabled
        self.deepRecordingEnabled = deepRecordingEnabled
        self.visionOCREnabled = visionOCREnabled
        self.inputMonitoringEnabled = inputMonitoringEnabled
        self.appFocusDebounceMs = max(0, appFocusDebounceMs)
        self.heartbeatIntervalMs = max(1000, heartbeatIntervalMs)
        self.recorderIdleThresholdMs = max(5000, recorderIdleThresholdMs)
        self.typingPauseQuietMs = max(200, typingPauseQuietMs)
        self.visualCheckIntervalMs = max(0, visualCheckIntervalMs)
        self.jpegQuality = min(100, max(1, jpegQuality))
        self.ocrLanguages = Self.normalizeOCRLanguages(ocrLanguages)
        self.sensitiveBundleIds = Self.normalizeBundleIds(sensitiveBundleIds)
        self.snapshotRetentionDays = max(1, snapshotRetentionDays)
        self.snapshotMaxStorageBytes = max(0, snapshotMaxStorageBytes)
        self.ocrEveryN = max(1, ocrEveryN)
    }

    private enum CodingKeys: String, CodingKey {
        case activityRecorderEnabled
        case deepRecordingEnabled
        case visionOCREnabled
        case inputMonitoringEnabled
        case appFocusDebounceMs
        case heartbeatIntervalMs
        case recorderIdleThresholdMs
        case typingPauseQuietMs
        case visualCheckIntervalMs
        case jpegQuality
        case ocrLanguages
        case sensitiveBundleIds
        case snapshotRetentionDays
        case snapshotMaxStorageBytes
        case ocrEveryN
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let activityRecorderEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityRecorderEnabled) ?? true
        let deepRecordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .deepRecordingEnabled) ?? true
        let visionOCREnabled = try container.decodeIfPresent(Bool.self, forKey: .visionOCREnabled) ?? true
        let inputMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .inputMonitoringEnabled) ?? true
        let appFocusDebounceMs = try container.decodeIfPresent(Int.self, forKey: .appFocusDebounceMs) ?? 4000
        let heartbeatIntervalMs = try container.decodeIfPresent(Int.self, forKey: .heartbeatIntervalMs) ?? 120_000
        let recorderIdleThresholdMs = try container.decodeIfPresent(Int.self, forKey: .recorderIdleThresholdMs) ?? 300_000
        let typingPauseQuietMs = try container.decodeIfPresent(Int.self, forKey: .typingPauseQuietMs) ?? 2000
        let visualCheckIntervalMs = try container.decodeIfPresent(Int.self, forKey: .visualCheckIntervalMs) ?? 12_000
        let jpegQuality = try container.decodeIfPresent(Int.self, forKey: .jpegQuality) ?? 55
        let ocrLanguages = try container.decodeIfPresent([String].self, forKey: .ocrLanguages) ?? Self.defaultOCRLanguages
        let sensitiveBundleIds = try container.decodeIfPresent([String].self, forKey: .sensitiveBundleIds) ?? Self.defaultSensitiveBundleIds
        let snapshotRetentionDays = try container.decodeIfPresent(Int.self, forKey: .snapshotRetentionDays) ?? 7
        let snapshotMaxStorageBytes = try container.decodeIfPresent(Int64.self, forKey: .snapshotMaxStorageBytes) ?? Self.defaultMaxStorageBytes
        let ocrEveryN = try container.decodeIfPresent(Int.self, forKey: .ocrEveryN) ?? 1

        self.init(
            activityRecorderEnabled: activityRecorderEnabled,
            deepRecordingEnabled: deepRecordingEnabled,
            visionOCREnabled: visionOCREnabled,
            inputMonitoringEnabled: inputMonitoringEnabled,
            appFocusDebounceMs: appFocusDebounceMs,
            heartbeatIntervalMs: heartbeatIntervalMs,
            recorderIdleThresholdMs: recorderIdleThresholdMs,
            typingPauseQuietMs: typingPauseQuietMs,
            visualCheckIntervalMs: visualCheckIntervalMs,
            jpegQuality: jpegQuality,
            ocrLanguages: ocrLanguages,
            sensitiveBundleIds: sensitiveBundleIds,
            snapshotRetentionDays: snapshotRetentionDays,
            snapshotMaxStorageBytes: snapshotMaxStorageBytes,
            ocrEveryN: ocrEveryN
        )
    }

    public func makePrivacyRedactorConfig(base: PrivacyRedactorConfig = .default) -> PrivacyRedactorConfig {
        var merged = base.additionalSensitiveBundlePrefixes
        var seen = Set(merged.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        for bundleId in sensitiveBundleIds {
            let trimmed = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            if !trimmed.isEmpty, seen.insert(lower).inserted {
                merged.append(trimmed)
            }
        }
        return PrivacyRedactorConfig(
            redactWeChat: base.redactWeChat,
            redactMessages: base.redactMessages,
            additionalSensitiveBundlePrefixes: merged,
            additionalSensitiveKeywords: base.additionalSensitiveKeywords
        )
    }

    private static func normalizeOCRLanguages(_ langs: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for raw in langs {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            result.append(trimmed)
        }
        return result.isEmpty ? defaultOCRLanguages : result
    }

    private static func normalizeBundleIds(_ ids: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for raw in ids {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(trimmed)
        }
        return result
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
        var activityRecorderEnabled: Bool?
        var deepRecordingEnabled: Bool?
        var visionOCREnabled: Bool?
        var inputMonitoringEnabled: Bool?
        var appFocusDebounceMs: Int?
        var heartbeatIntervalMs: Int?
        var recorderIdleThresholdMs: Int?
        var typingPauseQuietMs: Int?
        var visualCheckIntervalMs: Int?
        var jpegQuality: Int?
        var ocrLanguages: [String]?
        var sensitiveBundleIds: [String]?
        var snapshotRetentionDays: Int?
        var snapshotMaxStorageBytes: Int64?
        var ocrEveryN: Int?
    }

    private func loadConfigDTO() -> DayHelmConfigFileDTO {
        guard fileManager.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let decoded = try? decoder.decode(DayHelmConfigFileDTO.self, from: data) else {
            return DayHelmConfigFileDTO()
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
            activityRecorderEnabled: dto.activityRecorderEnabled ?? true,
            deepRecordingEnabled: dto.deepRecordingEnabled ?? true,
            visionOCREnabled: dto.visionOCREnabled ?? true,
            inputMonitoringEnabled: dto.inputMonitoringEnabled ?? true,
            appFocusDebounceMs: dto.appFocusDebounceMs ?? 4000,
            heartbeatIntervalMs: dto.heartbeatIntervalMs ?? 120_000,
            recorderIdleThresholdMs: dto.recorderIdleThresholdMs ?? 300_000,
            typingPauseQuietMs: dto.typingPauseQuietMs ?? 2000,
            visualCheckIntervalMs: dto.visualCheckIntervalMs ?? 12_000,
            jpegQuality: dto.jpegQuality ?? 55,
            ocrLanguages: dto.ocrLanguages ?? DayHelmSettings.defaultOCRLanguages,
            sensitiveBundleIds: dto.sensitiveBundleIds ?? DayHelmSettings.defaultSensitiveBundleIds,
            snapshotRetentionDays: dto.snapshotRetentionDays ?? 7,
            snapshotMaxStorageBytes: dto.snapshotMaxStorageBytes ?? DayHelmSettings.defaultMaxStorageBytes,
            ocrEveryN: dto.ocrEveryN ?? 1
        )
    }

    public func saveSettings(_ settings: DayHelmSettings) throws {
        try ensureDirectory(directory)
        let normalized = DayHelmSettings(
            activityRecorderEnabled: settings.activityRecorderEnabled,
            deepRecordingEnabled: settings.deepRecordingEnabled,
            visionOCREnabled: settings.visionOCREnabled,
            inputMonitoringEnabled: settings.inputMonitoringEnabled,
            appFocusDebounceMs: settings.appFocusDebounceMs,
            heartbeatIntervalMs: settings.heartbeatIntervalMs,
            recorderIdleThresholdMs: settings.recorderIdleThresholdMs,
            typingPauseQuietMs: settings.typingPauseQuietMs,
            visualCheckIntervalMs: settings.visualCheckIntervalMs,
            jpegQuality: settings.jpegQuality,
            ocrLanguages: settings.ocrLanguages,
            sensitiveBundleIds: settings.sensitiveBundleIds,
            snapshotRetentionDays: settings.snapshotRetentionDays,
            snapshotMaxStorageBytes: settings.snapshotMaxStorageBytes,
            ocrEveryN: settings.ocrEveryN
        )
        var payload = loadConfigDTO()
        payload.activityRecorderEnabled = normalized.activityRecorderEnabled
        payload.deepRecordingEnabled = normalized.deepRecordingEnabled
        payload.visionOCREnabled = normalized.visionOCREnabled
        payload.inputMonitoringEnabled = normalized.inputMonitoringEnabled
        payload.appFocusDebounceMs = normalized.appFocusDebounceMs
        payload.heartbeatIntervalMs = normalized.heartbeatIntervalMs
        payload.recorderIdleThresholdMs = normalized.recorderIdleThresholdMs
        payload.typingPauseQuietMs = normalized.typingPauseQuietMs
        payload.visualCheckIntervalMs = normalized.visualCheckIntervalMs
        payload.jpegQuality = normalized.jpegQuality
        payload.ocrLanguages = normalized.ocrLanguages
        payload.sensitiveBundleIds = normalized.sensitiveBundleIds
        payload.snapshotRetentionDays = normalized.snapshotRetentionDays
        payload.snapshotMaxStorageBytes = normalized.snapshotMaxStorageBytes
        payload.ocrEveryN = normalized.ocrEveryN
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
