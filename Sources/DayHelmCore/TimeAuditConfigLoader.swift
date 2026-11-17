import Foundation

public enum TimeAuditConfigLoader {
    public static let defaultBudgets: [TaskBudget] = [
        TaskBudget(
            taskId: "ecommerce",
            displayName: "电商做深",
            colorHex: "#3B82F6",
            targetMinutes: 90,
            capMinutes: 120,
            keywords: ["抖店", "jinritemai", "1688", "ecommerce", "电商", "主图", "选品"]
        ),
        TaskBudget(
            taskId: "ecommerce-ops",
            displayName: "电商日常运营",
            colorHex: "#F59E0B",
            targetMinutes: nil,
            capMinutes: 30,
            keywords: ["客服", "售后", "退货", "发货", "订单处理", "ecommerce-ops"]
        ),
        TaskBudget(
            taskId: "hermes",
            displayName: "Hermes 投研",
            colorHex: "#10B981",
            targetMinutes: 45,
            capMinutes: 60,
            keywords: ["hermes", "投研", "研报", "research"]
        ),
        TaskBudget(
            taskId: "infra-billing",
            displayName: "Infra 维护",
            colorHex: "#8B5CF6",
            targetMinutes: nil,
            capMinutes: 30,
            keywords: ["infra", "billing", "aws", "cloudflare", "terraform", "deploy"]
        )
    ]

    public static var defaultTimeAuditDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/alma/time-audit", isDirectory: true)
    }

    public static var defaultDayHelmConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/alma/dayhelm/config.json", isDirectory: false)
    }

    private struct TimeAuditProjectDTO: Decodable {
        let name: String
        let keywords: [String]?
    }

    private struct TimeAuditConfigDTO: Decodable {
        let projects: [TimeAuditProjectDTO]?
    }

    private struct TimeAuditPrimaryFocusDTO: Decodable {
        let project_keys: [String]?
    }

    private struct TimeAuditFocusDTO: Decodable {
        let primary_focus: TimeAuditPrimaryFocusDTO?
    }

    private struct DayHelmConfigFileDTO: Decodable {
        let budgets: [TaskBudget]?
    }

    public static func loadBudgets(
        timeAuditDirectory: URL = defaultTimeAuditDirectory,
        dayhelmConfigURL: URL? = defaultDayHelmConfigURL
    ) -> [TaskBudget] {
        if let dayhelmConfigURL,
           let data = try? Data(contentsOf: dayhelmConfigURL),
           let decoded = try? JSONDecoder().decode(DayHelmConfigFileDTO.self, from: data),
           let savedBudgets = decoded.budgets {
            return savedBudgets
        }

        var budgets: [TaskBudget] = defaultBudgets

        let configURL = timeAuditDirectory.appendingPathComponent("config.json")
        var projectKeywordsByName: [String: [String]] = [:]
        if let data = try? Data(contentsOf: configURL),
           let decoded = try? JSONDecoder().decode(TimeAuditConfigDTO.self, from: data),
           let projects = decoded.projects {
            for project in projects {
                if let kws = project.keywords {
                    projectKeywordsByName[project.name] = kws
                }
            }
        }

        // Read only primary_focus.project_keys (never log/expose private introspection fields).
        let focusURL = timeAuditDirectory.appendingPathComponent("focus.json")
        var primaryKeys: [String] = []
        if let data = try? Data(contentsOf: focusURL),
           let decoded = try? JSONDecoder().decode(TimeAuditFocusDTO.self, from: data),
           let keys = decoded.primary_focus?.project_keys {
            primaryKeys = keys
        }

        budgets = budgets.map { budget in
            guard let extraKeywords = projectKeywordsByName[budget.taskId] else {
                return budget
            }
            let merged = mergeKeywords(existing: budget.keywords, additional: extraKeywords)
            return TaskBudget(
                taskId: budget.taskId,
                displayName: budget.displayName,
                colorHex: budget.colorHex,
                targetMinutes: budget.targetMinutes,
                capMinutes: budget.capMinutes,
                keywords: merged
            )
        }

        let existingIds = Set(budgets.map(\.taskId))
        for key in primaryKeys where !existingIds.contains(key) {
            let kws = projectKeywordsByName[key] ?? [key]
            budgets.append(
                TaskBudget(
                    taskId: key,
                    displayName: key,
                    colorHex: "#3B82F6",
                    targetMinutes: 60,
                    capMinutes: nil,
                    keywords: kws
                )
            )
        }

        return budgets
    }

    private static func mergeKeywords(existing: [String], additional: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for kw in existing + additional {
            let normalized = kw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let lower = normalized.lowercased()
            if seen.insert(lower).inserted {
                result.append(normalized)
            }
        }
        return result
    }
}
