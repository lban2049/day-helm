import DayHelmCore
import Foundation

public protocol JevHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public final class URLSessionJevTransport: JevHTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(timeoutSeconds: TimeInterval = 8.0) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutSeconds
        config.timeoutIntervalForResource = timeoutSeconds + 2.0
        config.httpMaximumConnectionsPerHost = 2
        self.session = URLSession(configuration: config)
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

public enum JevClientError: Error, LocalizedError, Sendable, Equatable {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 JEV API Key"
        case .invalidResponse:
            return "Jev 响应格式异常"
        case .httpError(let code, let message):
            return "Jev HTTP \(code): \(message)"
        }
    }
}

public struct JevPingResult: Sendable, Equatable {
    public let model: String
    public let latencyMs: Int
    public let inputTokens: Int

    public init(model: String, latencyMs: Int, inputTokens: Int) {
        self.model = model
        self.latencyMs = latencyMs
        self.inputTokens = inputTokens
    }
}

/// Async client for TypeSafe AI System One (`POST /v1/systemone`) semantic activity classification.
public final class JevActivityClient: @unchecked Sendable {
    public static let defaultEndpointURL = URL(string: "https://api.typesafe.ai/v1/systemone")!

    public let endpointURL: URL
    private let transport: any JevHTTPTransport

    public init(
        endpointURL: URL = defaultEndpointURL,
        transport: any JevHTTPTransport = URLSessionJevTransport()
    ) {
        self.endpointURL = endpointURL
        self.transport = transport
    }

    public func classify(
        input: SemanticClassificationInput,
        apiKey: String,
        model: String = DayHelmSettings.defaultJevModel
    ) async throws -> SemanticClassification {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw JevClientError.missingAPIKey
        }

        let payload = Self.buildRequestPayload(input: input, model: model)
        let bodyData = try JSONSerialization.data(withJSONObject: payload, options: [])

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let startedAt = Date()
        let (data, response) = try await transport.data(for: request)
        let latencyMs = max(1, Int((Date().timeIntervalSince(startedAt) * 1000.0).rounded()))
        guard let httpResp = response as? HTTPURLResponse else {
            throw JevClientError.invalidResponse
        }
        guard (200..<300).contains(httpResp.statusCode) else {
            let msg = Self.extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResp.statusCode)
            throw JevClientError.httpError(statusCode: httpResp.statusCode, message: msg)
        }

        return try Self.parseClassificationResponse(
            data: data,
            budgets: input.budgets,
            at: input.timestamp,
            latencyMs: latencyMs
        )
    }

    public func testConnection(
        apiKey: String,
        model: String = DayHelmSettings.defaultJevModel
    ) async throws -> JevPingResult {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw JevClientError.missingAPIKey
        }

        let payload: [String: Any] = [
            "model": model.isEmpty ? DayHelmSettings.defaultJevModel : model,
            "state": [
                "current": [
                    "app": "DayHelm",
                    "title": "Connection Check"
                ]
            ],
            "questions": [
                "ok": [
                    "type": "noul",
                    "instructions": "Is this a valid connection check?"
                ]
            ]
        ]

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let start = Date()
        let (data, response) = try await transport.data(for: request)
        let elapsedMs = Int((Date().timeIntervalSince(start) * 1000.0).rounded())

        guard let httpResp = response as? HTTPURLResponse else {
            throw JevClientError.invalidResponse
        }
        guard (200..<300).contains(httpResp.statusCode) else {
            let msg = Self.extractErrorMessage(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResp.statusCode)
            throw JevClientError.httpError(statusCode: httpResp.statusCode, message: msg)
        }

        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw JevClientError.invalidResponse
        }
        let resolvedModel = (obj["model"] as? String) ?? model
        let usage = obj["usage"] as? [String: Any]
        let inputTokens = (usage?["input_tokens"] as? Int) ?? 0
        return JevPingResult(model: resolvedModel, latencyMs: max(1, elapsedMs), inputTokens: inputTokens)
    }

    // MARK: - Two-Layer Payload & Parsing (Verified on 38-Case Real-World Benchmark)

    private static let activityModeCriteria: [String: String] = [
        ActivityMode.build.rawValue: "开发构建：编写、审查或测试代码，在 GitHub / GitLab 等代码托管平台浏览或查阅开源/自有项目仓库、源码、PR、Issue 或 Commit，使用代码编辑器/IDE/终端/正在开发调试中的本地软件运行时（如未打包的 Electron 进程或本地前端/桌面App）构建软件产品，查看正在集成的 AI/云 API 用量控制台或官方技术文档，以及配合编码过程中的截图辅助。注意：只要是在写代码、跑终端、查阅 GitHub 代码仓库或调试自己正在开发的软件（尤其是进程名为 Electron 的本地开发调试窗口，无论界面标题是否含“运营工作台/抖店”等业务词），仍属于「开发构建」；例外：若在 IDE/AI 编程工具中打开个人知识库或创作/审阅内容稿件（如 obsidian / Podcast Draft），则归「内容创作」；若使用已部署在 localhost 的个人业务看板或 Agent 管理面板，则依据页面正文实际处理的业务归类",
        ActivityMode.create.rawValue: "内容创作：主动生产或审阅原创图文、音视频或播客稿件，包括撰写/审阅文章、播客脚本（含在 IDE / AI 编程工具如 T3 Code 中打开个人知识库或内容稿件仓库如 obsidian / Podcast Draft）、编辑和发布社交媒体帖子（URL 含 compose/post/publish/edit 等发帖编辑页）、视频剪辑制作、以及专门的内容创作/选题频道（如 Discord #内容创作）。注意：单纯阅读他人文章不属于内容创作",
        ActivityMode.operate.rawValue: "业务运营：店铺与商业日常执行，包括商品上架、选品与货源采集、RPA 采集运行、采购下单、订单与售后工单处理、商品定价表格，以及专门用于管理具体业务计划、业务定时任务或业务事务的频道与看板（如 Discord #电商事务/周电商计划、电商任务看板；不含进程名为 Electron 的本地开发调试窗口）",
        ActivityMode.research.rawValue: "研究规划：使用任务管理/待办看板工具（如 Vikunja/Linear/Notion Tasks）梳理需求与待办清单、行业/市场与竞品调研、查阅技术文档与开源/自建软件项目的社区讨论频道（如 Discord #general | OpenMausBot）、订阅或认证攻略调研、浏览技术社区新闻与讨论（如 Hacker News / ycombinator.com）、在 Web AI 对话/Agent 面板中排查系统报错问题、阅读文章与资料、以及写个人日记、知识笔记与复盘总结",
        ActivityMode.commsAdmin.rawValue: "沟通杂务：收发通用电子邮件、私密脱敏的聊天或系统应用（当 redacted=true 且仅可见微信/WeChat/QQ/Mail/Slack/1Password 等应用名时，直接确定性归为此类）、常规无特定主题的私聊沟通、云服务/AI 会员订阅与学生/开发者优惠认证（如 SheerID、Google One、学信网、账单与账号绑定）、向 AI 问答助手（如 Grok/ChatGPT/豆包）咨询个人账号/工具/系统配置等日常杂务，以及行政事务。注意：若聊天窗口标题或正文明确显示为特定业务/创作/开源技术频道或闲聊优惠福利群，则优先按主题归入 operate/create/research/break",
        ActivityMode.breakTime.rawValue: "休息分心：仅限浏览社交媒体主页信息流（如 /home）、在闲聊水群或纯生活优惠/抢券群水群、看影视娱乐视频等非工作放松或分心活动。注意：云服务/AI 会员订阅及学生/开发者认证（如 SheerID/Google One/学信网）归 comms_admin/research，开源/自建项目技术频道（如 OpenMausBot）归 research/build，均不归入此类"
    ]

    public static func buildRequestPayload(
        input: SemanticClassificationInput,
        model: String
    ) -> [String: Any] {
        var currentObj: [String: Any] = [
            "app": input.appName
        ]
        if input.redacted {
            currentObj["redacted"] = true
        } else {
            if let title = input.windowTitle, !title.isEmpty {
                currentObj["title"] = title
            }
            if let url = input.url, !url.isEmpty {
                currentObj["url"] = url
            }
            if let ocr = input.ocrSnippet, !ocr.isEmpty {
                currentObj["ocr_snippet"] = ocr
            }
        }

        var stateObj: [String: Any] = [
            "current": currentObj
        ]
        if !input.recentHistory.isEmpty {
            stateObj["recent_history"] = input.recentHistory.map { entry -> [String: Any] in
                var item: [String: Any] = [
                    "app": entry.appName,
                    "duration_sec": entry.durationSeconds
                ]
                if let title = entry.windowTitle, !title.isEmpty {
                    item["title"] = title
                }
                if let domain = entry.domain, !domain.isEmpty {
                    item["domain"] = domain
                }
                return item
            }
        }

        var questions: [String: Any] = [
            "activity_mode": [
                "type": "choice",
                "instructions": "Classify the user's CURRENT activity mode based primarily on state.current (app, title, url, optional ocr_snippet). Key disambiguation rules: (1) Building or locally debugging a software app you are coding (IDE, terminal, local macOS app opened right after coding in an IDE), browsing code/PRs/issues on github.com/gitlab.com, or official developer API docs is 'build', even if its domain is ecommerce. In particular, when state.current.app is 'Electron' (unbundled local dev runtime), ALWAYS prioritize 'build' regardless of business keywords in its title (e.g. 运营工作台/抖店) or recent_history from a browser. EXCEPTION for IDE/AI coding tools (e.g. T3 Code, Zed, Cursor): if the workspace/session title clearly points to personal knowledge or content/editorial draft review (e.g. obsidian, Podcast Draft, article/script writing), classify as 'create' instead of 'build'. For deployed localhost dashboards/agent workbenches (e.g. Hermes Agent Dashboard), classify by what the page body (ocr_snippet) actually manages (ecommerce ops -> 'operate', system troubleshooting -> 'research'). (2) If state.current.redacted is true (privacy-redacted IM/mail/system app like 微信, WeChat, QQ, Mail, Slack, Messages, 1Password where title/OCR are hidden), deterministically choose 'comms_admin' with high confidence. (3) For unredacted chat/Discord/QQ windows, classify by channel/project topic & recent_history: business ops channels -> 'operate', content creation channels -> 'create', open-source/self-hosted software project channels (e.g. #general | OpenMausBot) -> 'research' or 'build' (do NOT default '#general' in a dev project server to 'break'), casual gossip/coupon-hunting groups -> 'break'. (4) Generic task/todo trackers (e.g. Vikunja) are 'research' unless ocr_snippet shows live business ops. (5) AI assistants (x.com/i/grok, chatgpt, doubao, web agent sessions) are classified by topic ('research' for tech/market research or troubleshooting, 'comms_admin' for personal account/Apple ID admin), NOT social browsing. (6) Cloud/AI subscriptions, billing/account binding, and student/developer discount verification (e.g. SheerID, Google One, 学信网) are 'comms_admin' (reading guides/tutorials -> 'research'), NEVER 'break'. (7) Pay attention to URL paths (compose/post -> 'create', social /home feed -> 'break'), and inherit from recent_history for neutral helpers (screenshot tools, Finder, API usage dashboards opened while coding). (8) Tech news/community discussions (Hacker News) and reading technical articles are 'research', NOT 'break'.",
                "criteria": activityModeCriteria
            ]
        ]

        // Layer 2 (Focus Project) is queried only when the user has configured at least one focus project.
        if !input.budgets.isEmpty {
            var projectCriteria: [String: String] = [:]
            for budget in input.budgets {
                var parts: [String] = [budget.displayName]
                if let desc = budget.description, !desc.isEmpty {
                    parts.append(desc)
                } else if !budget.keywords.isEmpty {
                    parts.append("相关线索：" + budget.keywords.prefix(6).joined(separator: "、"))
                }
                projectCriteria[budget.taskId] = parts.joined(separator: "：")
            }
            projectCriteria["none"] = "无特定焦点项目：不属于上述具体焦点项目的通用工作、个人日记复盘、通用助手排错、普通文章阅读、通用邮件、脱敏私聊（redacted=true）、账号杂务，或休息分心"

            questions["focus_project"] = [
                "type": "choice",
                "instructions": "Determine whether state.current clearly belongs to one of the user's focus projects, or 'none'. Key rules: (1) If state.current.redacted is true (no title/URL/OCR), ALWAYS choose 'none' — never guess a project for redacted private apps. (2) Coding, running terminal commands in a repo, or debugging a local Electron/macOS app right after IDE coding belongs to the software-development focus project (if present), even if the software's domain is ecommerce. (3) Reading general articles, writing personal daily journals, troubleshooting an unrelated personal assistant, checking generic email, or taking a break -> 'none'. (4) Neutral helpers (screenshot tool, local app being tested, API usage console, task tracker) right after working on a project inherit that project.",
                "criteria": projectCriteria
            ]
        }

        if !input.recentHistory.isEmpty {
            questions["same_task"] = [
                "type": "noul",
                "instructions": "Is state.current a direct continuation of the SAME work task/project as state.recent_history? Answer YES (high probability) for natural cross-app steps of the SAME workflow: coding <-> editor/terminal/local app debugging/testing own app/screenshot helper/API usage console/planning tasks for that product; business ops <-> product listing/sourcing/RPA scraping/pricing spreadsheet/same-topic business channel; content planning channel <-> composing a social post or editing video. Answer NO (low probability) whenever the user switches to a different project, domain, or channel topic, or switches from work to generic email, personal journal, unrelated assistant troubleshooting, social feeds, or entertainment."
            ]
        }

        return [
            "model": model.isEmpty ? DayHelmSettings.defaultJevModel : model,
            "state": stateObj,
            "questions": questions
        ]
    }

    public static func parseClassificationResponse(
        data: Data,
        budgets: [TaskBudget] = [],
        at timestamp: Date,
        latencyMs: Int? = nil
    ) throws -> SemanticClassification {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = root["answers"] as? [String: Any] else {
            throw JevClientError.invalidResponse
        }

        let usage = root["usage"] as? [String: Any]
        let inputTokens = (usage?["input_tokens"] as? Int)
            ?? (usage?["input_tokens"] as? NSNumber)?.intValue

        // Support new two-layer schema (`activity_mode` + optional `focus_project` + `same_task`)
        if let modeObj = answers["activity_mode"] as? [String: Any],
           let rawMode = modeObj["choice"] as? String,
           let mode = ActivityMode(rawValue: rawMode) {
            let modeConf = extractDouble(modeObj["confidence"]) ?? 0.0
            let modeProbs = extractProbabilities(modeObj["probabilities"])

            let sameTask = (answers["same_task"] as? [String: Any]).flatMap { extractDouble($0["noul"]) }
                ?? (answers["same_task_as_previous"] as? [String: Any]).flatMap { extractDouble($0["noul"]) }
            let breakProb = modeProbs[ActivityMode.breakTime.rawValue] ?? (mode == .breakTime ? modeConf : 0.0)

            var matchedProjectId: String?
            var matchedProjectConf: Double?
            let validBudgetIds = Set(budgets.map(\.taskId))

            if let projObj = answers["focus_project"] as? [String: Any],
               let rawProj = projObj["choice"] as? String,
               rawProj != "none",
               !rawProj.isEmpty,
               (validBudgetIds.isEmpty || validBudgetIds.contains(rawProj)) {
                let pConf = extractDouble(projObj["confidence"]) ?? 0.0
                matchedProjectConf = pConf
                // Commit to focus project only when confidence >= 0.45 and not a break
                if pConf >= 0.45 && mode != .breakTime {
                    matchedProjectId = rawProj
                }
            }

            let resolvedCategoryId = matchedProjectId ?? mode.categoryId
            let resolvedConfidence = matchedProjectId != nil
                ? max(modeConf, matchedProjectConf ?? modeConf)
                : modeConf

            return SemanticClassification(
                categoryId: resolvedCategoryId,
                activityMode: mode,
                focusProjectId: matchedProjectId,
                focusProjectConfidence: matchedProjectConf,
                confidence: resolvedConfidence,
                probabilities: modeProbs,
                sameTaskAsPrevious: sameTask,
                isDistraction: breakProb,
                source: .jev,
                classifiedAt: timestamp,
                latencyMs: latencyMs,
                inputTokens: inputTokens
            )
        }

        // Backward-compatible fallback for legacy single-layer `project` responses (e.g. older mocks)
        guard let project = answers["project"] as? [String: Any],
              let choice = project["choice"] as? String,
              !choice.isEmpty else {
            throw JevClientError.invalidResponse
        }

        let confidence = extractDouble(project["confidence"]) ?? 0.0
        let probabilities = extractProbabilities(project["probabilities"])
        let isDistraction = (answers["is_distraction"] as? [String: Any]).flatMap { extractDouble($0["noul"]) } ?? 0.0
        let sameTask = (answers["same_task_as_previous"] as? [String: Any]).flatMap { extractDouble($0["noul"]) }
            ?? (answers["same_task"] as? [String: Any]).flatMap { extractDouble($0["noul"]) }

        return SemanticClassification(
            categoryId: choice,
            activityMode: AutoActivityIds.activityMode(from: choice),
            focusProjectId: AutoActivityIds.isReserved(choice) ? nil : choice,
            focusProjectConfidence: AutoActivityIds.isReserved(choice) ? nil : confidence,
            confidence: confidence,
            probabilities: probabilities,
            sameTaskAsPrevious: sameTask,
            isDistraction: isDistraction,
            source: .jev,
            classifiedAt: timestamp,
            latencyMs: latencyMs,
            inputTokens: inputTokens
        )
    }

    private static func extractDouble(_ raw: Any?) -> Double? {
        if let d = raw as? Double { return d }
        if let n = raw as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func extractProbabilities(_ raw: Any?) -> [String: Double] {
        guard let dict = raw as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        for (k, v) in dict {
            if let d = extractDouble(v) {
                out[k] = d
            }
        }
        return out
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let detail = obj["detail"] as? [String: Any], let msg = detail["message"] as? String {
                return msg
            }
            if let msg = obj["detail"] as? String {
                return msg
            }
            if let msg = obj["message"] as? String {
                return msg
            }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw?.isEmpty == false ? String(raw!.prefix(160)) : nil
    }
}
