import Foundation

public struct ActivitySample: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?
    public let url: String?
    public let idleSeconds: TimeInterval
    public let screenLocked: Bool
    public let inputActive: Bool
    public let redacted: Bool

    public init(
        timestamp: Date,
        appName: String,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        idleSeconds: TimeInterval = 0,
        screenLocked: Bool = false,
        inputActive: Bool = true,
        redacted: Bool = false
    ) {
        self.timestamp = timestamp
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.idleSeconds = idleSeconds
        self.screenLocked = screenLocked
        self.inputActive = inputActive
        self.redacted = redacted
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp, appName, bundleId, windowTitle, url, idleSeconds, screenLocked, inputActive, redacted
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.appName = try container.decode(String.self, forKey: .appName)
        self.bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId)
        self.windowTitle = try container.decodeIfPresent(String.self, forKey: .windowTitle)
        self.url = try container.decodeIfPresent(String.self, forKey: .url)
        self.idleSeconds = try container.decode(TimeInterval.self, forKey: .idleSeconds)
        self.screenLocked = try container.decode(Bool.self, forKey: .screenLocked)
        self.inputActive = try container.decode(Bool.self, forKey: .inputActive)
        self.redacted = try container.decodeIfPresent(Bool.self, forKey: .redacted) ?? false
    }
}

public struct EnrichedSpan: Sendable, Equatable, Codable {
    public let startedAt: Date
    public var endedAt: Date
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?
    public let url: String?
    public let declaredTaskId: String?
    public let redacted: Bool
    public var semanticGroup: String?

    public var durationSeconds: TimeInterval {
        max(0, endedAt.timeIntervalSince(startedAt))
    }

    public init(
        startedAt: Date,
        endedAt: Date,
        appName: String,
        bundleId: String? = nil,
        windowTitle: String? = nil,
        url: String? = nil,
        declaredTaskId: String? = nil,
        redacted: Bool = false,
        semanticGroup: String? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.appName = appName
        self.bundleId = bundleId
        self.windowTitle = windowTitle
        self.url = url
        self.declaredTaskId = declaredTaskId
        self.redacted = redacted
        self.semanticGroup = semanticGroup
    }

    private enum CodingKeys: String, CodingKey {
        case startedAt, endedAt, appName, bundleId, windowTitle, url, declaredTaskId, redacted, semanticGroup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.startedAt = try c.decode(Date.self, forKey: .startedAt)
        self.endedAt = try c.decode(Date.self, forKey: .endedAt)
        self.appName = try c.decode(String.self, forKey: .appName)
        self.bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        self.windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.declaredTaskId = try c.decodeIfPresent(String.self, forKey: .declaredTaskId)
        self.redacted = try c.decodeIfPresent(Bool.self, forKey: .redacted) ?? false
        self.semanticGroup = try c.decodeIfPresent(String.self, forKey: .semanticGroup)
    }
}

public struct TaskBudget: Sendable, Equatable, Codable, Identifiable {
    public var id: String { taskId }
    public let taskId: String
    public let displayName: String
    public let shortName: String?
    public let description: String?
    public let colorHex: String
    public let targetMinutes: Int?
    public let capMinutes: Int?
    public let keywords: [String]
    public let appBundleIds: [String]
    public let domains: [String]

    public init(
        taskId: String,
        displayName: String,
        shortName: String? = nil,
        description: String? = nil,
        colorHex: String,
        targetMinutes: Int? = nil,
        capMinutes: Int? = nil,
        keywords: [String] = [],
        appBundleIds: [String] = [],
        domains: [String] = []
    ) {
        self.taskId = taskId
        self.displayName = displayName
        let trimmedShort = shortName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shortName = (trimmedShort?.isEmpty == false) ? trimmedShort : nil
        let trimmedDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = (trimmedDesc?.isEmpty == false) ? trimmedDesc : nil
        self.colorHex = colorHex
        self.targetMinutes = targetMinutes
        self.capMinutes = capMinutes
        self.keywords = keywords
        self.appBundleIds = appBundleIds
        self.domains = domains
    }

    private enum CodingKeys: String, CodingKey {
        case taskId, displayName, shortName, description, colorHex, targetMinutes, capMinutes, keywords, appBundleIds, domains
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.taskId = try container.decode(String.self, forKey: .taskId)
        self.displayName = try container.decode(String.self, forKey: .displayName)
        let decodedShort = try container.decodeIfPresent(String.self, forKey: .shortName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.shortName = (decodedShort?.isEmpty == false) ? decodedShort : nil
        let decodedDesc = try container.decodeIfPresent(String.self, forKey: .description)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.description = (decodedDesc?.isEmpty == false) ? decodedDesc : nil
        self.colorHex = try container.decode(String.self, forKey: .colorHex)
        self.targetMinutes = try container.decodeIfPresent(Int.self, forKey: .targetMinutes)
        self.capMinutes = try container.decodeIfPresent(Int.self, forKey: .capMinutes)
        self.keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        self.appBundleIds = try container.decodeIfPresent([String].self, forKey: .appBundleIds) ?? []
        self.domains = try container.decodeIfPresent([String].self, forKey: .domains) ?? []
    }
}

public enum ActivityMode: String, Sendable, Equatable, Codable, CaseIterable {
    case build = "build"
    case create = "create"
    case operate = "operate"
    case research = "research"
    case commsAdmin = "comms_admin"
    case breakTime = "break"

    public var displayName: String {
        switch self {
        case .build: return "开发构建"
        case .create: return "内容创作"
        case .operate: return "业务运营"
        case .research: return "研究规划"
        case .commsAdmin: return "沟通杂务"
        case .breakTime: return "休息分心"
        }
    }

    public var compactLabel: String {
        switch self {
        case .build: return "开发"
        case .create: return "创作"
        case .operate: return "运营"
        case .research: return "研究"
        case .commsAdmin: return "杂务"
        case .breakTime: return "分心"
        }
    }

    public var colorHex: String {
        switch self {
        case .build: return "#3B82F6"
        case .create: return "#8B5CF6"
        case .operate: return "#F59E0B"
        case .research: return "#10B981"
        case .commsAdmin: return "#64748B"
        case .breakTime: return "#EF4444"
        }
    }

    public var isDistraction: Bool {
        self == .breakTime
    }

    public var categoryId: String {
        "__mode_\(rawValue)__"
    }
}

public enum AutoNonBudgetActivity: String, Sendable, Equatable, Codable {
    case otherWork = "other_work"
    case nonWork = "non_work"
}

public enum BudgetStatus: Sendable, Equatable, Codable {
    case underTarget(remainingMinutes: Double)
    case targetMet
    case approachingCap(remainingMinutes: Double)
    case capReached(overMinutes: Double)
    case noBudget

    public static func compute(focusedMinutes: Double, targetMinutes: Int?, capMinutes: Int?) -> BudgetStatus {
        if let cap = capMinutes {
            let capDouble = Double(cap)
            if focusedMinutes >= capDouble {
                return .capReached(overMinutes: focusedMinutes - capDouble)
            }
            if cap > 0, focusedMinutes >= capDouble * 0.85 {
                return .approachingCap(remainingMinutes: capDouble - focusedMinutes)
            }
        }
        if let target = targetMinutes {
            let targetDouble = Double(target)
            if focusedMinutes < targetDouble {
                return .underTarget(remainingMinutes: targetDouble - focusedMinutes)
            }
            return .targetMet
        }
        return .noBudget
    }
}

public struct TaskProgress: Sendable, Equatable, Codable, Identifiable {
    public var id: String { budget.taskId }
    public let budget: TaskBudget
    public let focusedMinutes: Double
    public let status: BudgetStatus

    public init(budget: TaskBudget, focusedMinutes: Double, status: BudgetStatus) {
        self.budget = budget
        self.focusedMinutes = focusedMinutes
        self.status = status
    }
}

public enum FocusSessionState: Sendable, Equatable, Codable {
    case unassigned
    case focusing(taskId: String, startedAt: Date)
    case paused(taskId: String, pausedAt: Date)
}

public struct FocusSessionRecord: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let taskId: String
    public let startedAt: Date
    public var endedAt: Date?
    public var minutes: Double
    public var note: String?

    public init(
        id: String,
        taskId: String,
        startedAt: Date,
        endedAt: Date? = nil,
        minutes: Double = 0,
        note: String? = nil
    ) {
        self.id = id
        self.taskId = taskId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.minutes = minutes
        self.note = note
    }
}

public enum SpectrumSegmentKind: Sendable, Equatable, Codable {
    case task(taskId: String, displayName: String, colorHex: String)
    case activityMode(rawValue: String)
    case thrashing(switchCount: Int)
    case idle
    case unassigned
}

public struct SpectrumSegment: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let startedAt: Date
    public let endedAt: Date
    public let kind: SpectrumSegmentKind
    public let durationMinutes: Double

    public init(
        id: String,
        startedAt: Date,
        endedAt: Date,
        kind: SpectrumSegmentKind,
        durationMinutes: Double
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.durationMinutes = durationMinutes
    }
}

public struct DayMetrics: Sendable, Equatable, Codable {
    public let activeMinutes: Double
    public let longestBlockMinutes: Double
    public let solidBlocksCount: Int
    public let recentSwitchesPerHour: Double

    public init(
        activeMinutes: Double,
        longestBlockMinutes: Double,
        solidBlocksCount: Int,
        recentSwitchesPerHour: Double
    ) {
        self.activeMinutes = activeMinutes
        self.longestBlockMinutes = longestBlockMinutes
        self.solidBlocksCount = solidBlocksCount
        self.recentSwitchesPerHour = recentSwitchesPerHour
    }
}

public enum SupervisorAction: Sendable, Equatable, Codable {
    case switchTask(taskId: String, label: String)
    case snooze(minutes: Int, label: String)
    case pauseFocus(label: String)
    case dismiss(label: String)
}

public enum SupervisorAlertKind: Sendable, Equatable, Codable {
    case quotaCapReached(taskId: String, minutes: Double, cap: Int)
    case quotaTargetMet(taskId: String, minutes: Double, target: Int)
    case taskDrift(declaredTaskId: String, detectedTaskId: String, minutes: Double)
    case highFrequencySwitch(switchesInWindow: Int, windowMinutes: Int)
    case unassignedActivePrompt(activeMinutes: Double)
}

public struct SupervisorAlert: Sendable, Equatable, Codable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let kind: SupervisorAlertKind
    public let title: String
    public let message: String
    public let actions: [SupervisorAction]

    public init(
        id: String,
        timestamp: Date,
        kind: SupervisorAlertKind,
        title: String,
        message: String,
        actions: [SupervisorAction]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.title = title
        self.message = message
        self.actions = actions
    }
}
