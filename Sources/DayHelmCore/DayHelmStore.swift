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
    public let otherWorkMinutes: Double?
    public let nonWorkMinutes: Double?
    public let activityModeMinutes: [String: Double]?

    public init(
        schemaVersion: Int = 1,
        date: String,
        focusState: FocusSessionState? = nil,
        activeFocus: ActiveFocusSnapshot? = nil,
        budgets: [BudgetSnapshot],
        focusSessions: [FocusSessionRecord],
        enrichedSpans: [EnrichedSpan],
        metrics: DayMetrics,
        otherWorkMinutes: Double? = nil,
        nonWorkMinutes: Double? = nil,
        activityModeMinutes: [String: Double]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.date = date
        self.focusState = focusState
        self.activeFocus = activeFocus
        self.budgets = budgets
        self.focusSessions = focusSessions
        self.enrichedSpans = enrichedSpans
        self.metrics = metrics
        self.otherWorkMinutes = otherWorkMinutes
        self.nonWorkMinutes = nonWorkMinutes
        self.activityModeMinutes = activityModeMinutes
    }
}

public enum MenuBarDisplayMode: String, Sendable, Equatable, Codable, CaseIterable {
    case compact
    case standard
    case iconOnly

    public var displayName: String {
        switch self {
        case .compact: return "极简"
        case .standard: return "标准"
        case .iconOnly: return "仅图标"
        }
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
    public var menuBarDisplayMode: MenuBarDisplayMode
    public var jevAutoTrackingEnabled: Bool
    public var jevModel: String
    public var jevSendOCRSnippet: Bool

    public static let defaultJevModel = "jev-latest"
    public static let `default` = DayHelmSettings()

    public init(
        activityRecorderEnabled: Bool = true,
        deepRecordingEnabled: Bool = true,
        visionOCREnabled: Bool = true,
        inputMonitoringEnabled: Bool = true,
        appFocusDebounceMs: Int = 4000,
        heartbeatIntervalMs: Int = 120_000,
        recorderIdleThresholdMs: Int = 180_000,
        typingPauseQuietMs: Int = 2000,
        visualCheckIntervalMs: Int = 12_000,
        jpegQuality: Int = 55,
        ocrLanguages: [String] = DayHelmSettings.defaultOCRLanguages,
        sensitiveBundleIds: [String] = DayHelmSettings.defaultSensitiveBundleIds,
        snapshotRetentionDays: Int = 7,
        snapshotMaxStorageBytes: Int64 = DayHelmSettings.defaultMaxStorageBytes,
        ocrEveryN: Int = 1,
        menuBarDisplayMode: MenuBarDisplayMode = .standard,
        jevAutoTrackingEnabled: Bool = false,
        jevModel: String = DayHelmSettings.defaultJevModel,
        jevSendOCRSnippet: Bool = true
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
        self.menuBarDisplayMode = menuBarDisplayMode
        self.jevAutoTrackingEnabled = jevAutoTrackingEnabled
        let trimmedModel = jevModel.trimmingCharacters(in: .whitespacesAndNewlines)
        self.jevModel = trimmedModel.isEmpty ? Self.defaultJevModel : trimmedModel
        self.jevSendOCRSnippet = jevSendOCRSnippet
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
        case menuBarDisplayMode
        case jevAutoTrackingEnabled
        case jevModel
        case jevSendOCRSnippet
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let activityRecorderEnabled = try container.decodeIfPresent(Bool.self, forKey: .activityRecorderEnabled) ?? true
        let deepRecordingEnabled = try container.decodeIfPresent(Bool.self, forKey: .deepRecordingEnabled) ?? true
        let visionOCREnabled = try container.decodeIfPresent(Bool.self, forKey: .visionOCREnabled) ?? true
        let inputMonitoringEnabled = try container.decodeIfPresent(Bool.self, forKey: .inputMonitoringEnabled) ?? true
        let appFocusDebounceMs = try container.decodeIfPresent(Int.self, forKey: .appFocusDebounceMs) ?? 4000
        let heartbeatIntervalMs = try container.decodeIfPresent(Int.self, forKey: .heartbeatIntervalMs) ?? 120_000
        let recorderIdleThresholdMs = try container.decodeIfPresent(Int.self, forKey: .recorderIdleThresholdMs) ?? 180_000
        let typingPauseQuietMs = try container.decodeIfPresent(Int.self, forKey: .typingPauseQuietMs) ?? 2000
        let visualCheckIntervalMs = try container.decodeIfPresent(Int.self, forKey: .visualCheckIntervalMs) ?? 12_000
        let jpegQuality = try container.decodeIfPresent(Int.self, forKey: .jpegQuality) ?? 55
        let ocrLanguages = try container.decodeIfPresent([String].self, forKey: .ocrLanguages) ?? Self.defaultOCRLanguages
        let sensitiveBundleIds = try container.decodeIfPresent([String].self, forKey: .sensitiveBundleIds) ?? Self.defaultSensitiveBundleIds
        let snapshotRetentionDays = try container.decodeIfPresent(Int.self, forKey: .snapshotRetentionDays) ?? 7
        let snapshotMaxStorageBytes = try container.decodeIfPresent(Int64.self, forKey: .snapshotMaxStorageBytes) ?? Self.defaultMaxStorageBytes
        let ocrEveryN = try container.decodeIfPresent(Int.self, forKey: .ocrEveryN) ?? 1
        let menuBarDisplayMode = try container.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .standard
        let jevAutoTrackingEnabled = try container.decodeIfPresent(Bool.self, forKey: .jevAutoTrackingEnabled) ?? false
        let jevModel = try container.decodeIfPresent(String.self, forKey: .jevModel) ?? Self.defaultJevModel
        let jevSendOCRSnippet = try container.decodeIfPresent(Bool.self, forKey: .jevSendOCRSnippet) ?? true

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
            ocrEveryN: ocrEveryN,
            menuBarDisplayMode: menuBarDisplayMode,
            jevAutoTrackingEnabled: jevAutoTrackingEnabled,
            jevModel: jevModel,
            jevSendOCRSnippet: jevSendOCRSnippet
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

    public var jevLogURL: URL {
        directory.appendingPathComponent("jev-log.json")
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

    /// Lists valid `YYYY-MM-DD` archived day strings under `days/`, sorted descending.
    public func listArchivedDayStrings() -> [String] {
        guard fileManager.fileExists(atPath: daysDirectory.path),
              let items = try? fileManager.contentsOfDirectory(
                  at: daysDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        var dates: [String] = []
        for item in items where item.pathExtension.lowercased() == "json" {
            let stem = item.deletingPathExtension().lastPathComponent
            guard stem.count == 10,
                  let parsed = DayHelmDateFormatting.parseDayString(stem),
                  DayHelmDateFormatting.dayString(from: parsed) == stem else {
                continue
            }
            dates.append(stem)
        }
        return dates.sorted(by: >)
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
        var menuBarDisplayMode: MenuBarDisplayMode?
        var jevAutoTrackingEnabled: Bool?
        var jevModel: String?
        var jevSendOCRSnippet: Bool?
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
            recorderIdleThresholdMs: dto.recorderIdleThresholdMs ?? 180_000,
            typingPauseQuietMs: dto.typingPauseQuietMs ?? 2000,
            visualCheckIntervalMs: dto.visualCheckIntervalMs ?? 12_000,
            jpegQuality: dto.jpegQuality ?? 55,
            ocrLanguages: dto.ocrLanguages ?? DayHelmSettings.defaultOCRLanguages,
            sensitiveBundleIds: dto.sensitiveBundleIds ?? DayHelmSettings.defaultSensitiveBundleIds,
            snapshotRetentionDays: dto.snapshotRetentionDays ?? 7,
            snapshotMaxStorageBytes: dto.snapshotMaxStorageBytes ?? DayHelmSettings.defaultMaxStorageBytes,
            ocrEveryN: dto.ocrEveryN ?? 1,
            menuBarDisplayMode: dto.menuBarDisplayMode ?? .standard,
            jevAutoTrackingEnabled: dto.jevAutoTrackingEnabled ?? false,
            jevModel: dto.jevModel ?? DayHelmSettings.defaultJevModel,
            jevSendOCRSnippet: dto.jevSendOCRSnippet ?? true
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
            ocrEveryN: settings.ocrEveryN,
            menuBarDisplayMode: settings.menuBarDisplayMode,
            jevAutoTrackingEnabled: settings.jevAutoTrackingEnabled,
            jevModel: settings.jevModel,
            jevSendOCRSnippet: settings.jevSendOCRSnippet
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
        payload.menuBarDisplayMode = normalized.menuBarDisplayMode
        payload.jevAutoTrackingEnabled = normalized.jevAutoTrackingEnabled
        payload.jevModel = normalized.jevModel
        payload.jevSendOCRSnippet = normalized.jevSendOCRSnippet
        let data = try encoder.encode(payload)
        try writeAtomically(data: data, to: configURL, tempURL: directory.appendingPathComponent("config.json.tmp"))
    }

    private struct JevDecisionLogFileDTO: Codable {
        var date: String
        var entries: [JevDecisionLogEntry]
    }

    public func saveJevDecisionLogs(_ entries: [JevDecisionLogEntry], forDate dateString: String) throws {
        try ensureDirectory(directory)
        let capped = Array(entries.prefix(100))
        let payload = JevDecisionLogFileDTO(date: dateString, entries: capped)
        let data = try encoder.encode(payload)
        try writeAtomically(data: data, to: jevLogURL, tempURL: directory.appendingPathComponent("jev-log.json.tmp"))
    }

    public func loadJevDecisionLogs(forDate dateString: String) -> [JevDecisionLogEntry] {
        guard fileManager.fileExists(atPath: jevLogURL.path),
              let data = try? Data(contentsOf: jevLogURL),
              let decoded = try? decoder.decode(JevDecisionLogFileDTO.self, from: data),
              decoded.date == dateString else {
            return []
        }
        return decoded.entries
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

public enum JevAPIKeySource: String, Sendable, Equatable {
    case localKeyFile = "local_key_file"
    case environment = "environment"
    case dotEnv = "dot_env"

    public var displayName: String {
        switch self {
        case .localKeyFile: return "本地密钥文件"
        case .environment: return "环境变量"
        case .dotEnv: return "本地 .env"
        }
    }
}

public struct ResolvedJevAPIKey: Sendable, Equatable {
    public let key: String
    public let source: JevAPIKeySource

    public init(key: String, source: JevAPIKeySource) {
        self.key = key
        self.source = source
    }
}

/// Manages `JEV_API_KEY` isolated from `config.json` with 0600 permissions and env/.env fallbacks.
public final class JevAPIKeyStore: @unchecked Sendable {
    public let directory: URL
    public let keyFileURL: URL
    private let environment: [String: String]
    private let dotEnvSearchPaths: [URL]
    private let fileManager: FileManager

    public init(
        directory: URL = DayHelmStore.defaultDirectory,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnvSearchPaths: [URL]? = nil,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.keyFileURL = directory.appendingPathComponent("jev.key", isDirectory: false)
        self.environment = environment
        if let dotEnvSearchPaths {
            self.dotEnvSearchPaths = dotEnvSearchPaths
        } else {
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            self.dotEnvSearchPaths = [cwd.appendingPathComponent(".env", isDirectory: false)]
        }
        self.fileManager = fileManager
    }

    public func resolveKey() -> ResolvedJevAPIKey? {
        if fileManager.fileExists(atPath: keyFileURL.path),
           let raw = try? String(contentsOf: keyFileURL, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ResolvedJevAPIKey(key: trimmed, source: .localKeyFile)
            }
        }

        for envKey in ["JEV_API_KEY", "TYPESAFE_API_KEY"] {
            if let val = environment[envKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !val.isEmpty {
                return ResolvedJevAPIKey(key: val, source: .environment)
            }
        }

        for envURL in dotEnvSearchPaths where fileManager.fileExists(atPath: envURL.path) {
            if let found = Self.parseKey(fromDotEnv: envURL) {
                return ResolvedJevAPIKey(key: found, source: .dotEnv)
            }
        }

        return nil
    }

    public func saveKey(_ rawKey: String) throws {
        let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteKey()
            return
        }
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let tmpURL = directory.appendingPathComponent("jev.key.tmp", isDirectory: false)
        if fileManager.fileExists(atPath: tmpURL.path) {
            try? fileManager.removeItem(at: tmpURL)
        }
        let data = Data((trimmed + "\n").utf8)
        fileManager.createFile(
            atPath: tmpURL.path,
            contents: data,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o600))]
        )
        if fileManager.fileExists(atPath: keyFileURL.path) {
            _ = try fileManager.replaceItemAt(keyFileURL, withItemAt: tmpURL, backupItemName: nil, options: [])
        } else {
            try fileManager.moveItem(at: tmpURL, to: keyFileURL)
        }
        try? fileManager.setAttributes([.posixPermissions: NSNumber(value: Int16(0o600))], ofItemAtPath: keyFileURL.path)
    }

    public func deleteKey() throws {
        if fileManager.fileExists(atPath: keyFileURL.path) {
            try fileManager.removeItem(at: keyFileURL)
        }
    }

    private static func parseKey(fromDotEnv url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            for prefix in ["JEV_API_KEY=", "TYPESAFE_API_KEY="] {
                if line.hasPrefix(prefix) {
                    var value = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                        value = String(value.dropFirst().dropLast())
                    }
                    if !value.isEmpty {
                        return value
                    }
                }
            }
        }
        return nil
    }
}
