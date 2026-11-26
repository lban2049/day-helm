# 技术方案与 UI 规范（DayHelm · 日舵）

## 一、 整体分层架构

四层解耦，只通过明确定义的协议通信，每层可单独关闭或替换假实现：

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 界面层 (DayHelmApp)                                                     │
│   ├─ MenuBar 实时胶囊 (MenuBarExtra) + 330pt 高密度下拉仪表盘           │
│   ├─ 采集与 OCR 引擎状态条（AX 标题 / 屏幕 OCR 开关与帧数 / Agent API） │
│   ├─ 右上角非抢占式监督浮窗 (NSPanel: .nonactivatingPanel)              │
│   └─ 独立设置与活动记录窗口 (NSWindow: 设置中心 + 历史会话检视器)       │
├─────────────────────────────────────────────────────────────────────────┤
│ 判定与数据中心层 (DayHelmCore · 纯 Swift，严禁 import AppKit)           │
│   ├─ EventMerger / QuotaTracker / SpectrumBuilder / SlidingSupervisor   │
│   ├─ DailyStatsAggregator / DailyStatsMaterializer / AgentAnalysisPromptBuilder │
│   ├─ ActivityDatabase: 开放 SQLite (SQLite3 WAL)，兼容 Alma 四表模型    │
│   └─ DayHelmCLI: query / search / sessions / stats / status / purge     │
├─────────────────────────────────────────────────────────────────────────┤
│ 独立原生采集与接口层 (DayHelmCapture)                                   │
│   ├─ AXWindowInspector: 2s 轮询 NSWorkspace + AX 窗口标题与 URL         │
│   ├─ NativeScreenRecorder: 32-bin 直方图去重 + JPEG 0.55 + Vision OCR   │
│   ├─ NativeEventMonitor: app_focus / lock / unlock / 计次级键鼠活跃     │
│   ├─ LocalActivityHTTPServer: 127.0.0.1:24001 (支持 24001..24009 空闲选端) │
│   └─ AlmaActivityClient: 仅当 Alma 运行于 23001 时只读增量兼容回补      │
├─────────────────────────────────────────────────────────────────────────┤
│ 存储层 (DayHelmStore & ActivityDatabase)                                │
│   └─ ~/.config/alma/dayhelm/                                            │
│       ├─ activity.sqlite (sessions / events / snapshots / ocr_frames)   │
│       ├─ snapshots/YYYY-MM-DD/*.jpg (默认保留 7 天自动清理)             │
│       └─ today.json + days/YYYY-MM-DD.json + stats/YYYY-MM-DD.json + config.json │
└─────────────────────────────────────────────────────────────────────────┘
```

### SwiftPM 模块划分（统一工程结构）

```
Package.swift
├── Sources/DayHelmCore/        # 纯逻辑、SQLite 存储与 Agent CLI（严禁 import AppKit，注入 Clock，100% 可单测）
├── Sources/DayHelmCapture/     # 原生 AX + ScreenCaptureKit + Vision OCR + NWListener HTTP API + Alma 兼容客户端
├── Sources/DayHelmApp/         # SwiftUI 菜单栏仪表盘 + NSPanel 非抢占提醒窗
└── Sources/DayHelmChecks/      # 确定性自检可执行程序（合成数据验证配额、SQLite、OCR、CLI 与 HTTP API）
```

---

## 二、 独立原生采集与兼容层：彻底脱离 Alma 运行

### 1. 为什么内置独立原生采集引擎？

DayHelm 内置完整的 macOS 原生活动采集、视觉去重、设备端 Vision OCR、开放 SQLite 存储与兼容 HTTP API，彻底取代外部 Alma `activity-recorder` 依赖：
1. **无需 Alma 即可独立运行**：内置 `AXWindowInspector`、`NativeEventMonitor` 与 `NativeScreenRecorder`，自行产出毫秒级 `app_focus`、`browser_visit`、`click`、`keypress`、`lock`/`unlock`、窗口标题、URL、去重快照与 OCR 文本。
2. **可选且可开关的深度屏幕与 OCR 录制**：`Screen Recording` 权限为**可选**。当启用 `deepRecordingEnabled` 且已授权时，通过 `ImageHistogram`（32-bin 亮度直方图 + 8×8 感知哈希）执行去重捕获：仅在 `app_focus`（4s 防抖）、`click`（10s）、`typing_pause`（最后一次按键静默 2s 后，最小 15s）、12s 视觉检查且变化率 `diffPct >= 0.04`（4%）、或 120s 心跳时保存 JPEG（质量 0.55）并在后台 `.utility` 队列运行 Apple Vision OCR（`["zh-Hans", "zh-Hant", "en-US", "ja"]`）。所有触发均经直方图去重，画面未变不落盘。若权限被拒或关闭，则静默无痛降级为纯 AX 窗口标题 + URL + 事件录制，绝不弹窗纠缠。
3. **严格隐私阻断**：当 `PrivacyRedactor` 判定当前样品 `redacted == true` 或屏幕处于锁屏状态时，**绝不截屏、绝不运行 OCR**。
4. **独立 `2400x` 端口隔离与 Agent 数据中心**：内置 `LocalActivityHTTPServer`（仅绑定 `127.0.0.1`）默认监听 **`24001`**（若被占用则在 `24001...24009` 范围内自动选择首个空闲端口），**绝不监听或抢占 Alma 专用的 `23001` 端口**，确保 Alma 随时启动均不会因端口冲突异常。若 Alma 正在 `23001` 运行，DayHelm 可按需只读同步其历史事件。

### 2. 采集数据清单与触发频率

| 数据源 | 字段 | 实现方式 | 权限 | 频率 / 阈值 |
|---|---|---|---|---|
| **本机 AX** | 前台应用 `appName` + `bundleId` | `NSWorkspace.frontmostApplication` + `didActivateApplicationNotification` + 休眠/唤醒监听 | 无 | 事件驱动 + 2s 轮询 |
| **本机 AX** | 窗口标题 `windowTitle` & `url` | AX `kAXFocusedWindowAttribute` → `kAXTitleAttribute` + `AXDocument`；浏览器缺失时经隐私预检后用 1s 超时 AppleScript 兜底（含按 bundle 熔断） | Accessibility (+ 可选 Automation) | 2s 轮询 |
| **原生事件监听** | `app_focus` / `browser_visit` / `lock` / `unlock` / `click` / `keypress` / 计次活跃 | `NSWorkspace` / `DistributedNotificationCenter` / `NSEvent` 内存聚合计次（每 1s 或满 40 次或切应用/锁屏/休眠时批量刷出 `data.count`，绝不读按键内容） | 无 / 辅助功能 | 事件驱动 + `typing_pause` 2s 可取消计时器 |
| **原生屏幕快照** | 去重 JPEG (`maxWidth=1920`) + 单次 `160×90` 缩略像素差与 32-bin 直方图 + `hashHex` | `ScreenCaptureKit` (`SCScreenshotManager`)，缓存 `[SCDisplay]` `60s`（`excludingDesktopWindows(true, onScreenWindowsOnly: false)`），单显示器跳过 `CGWindowListCopyWindowInfo`；12s `visual_change` 先抓 `320px` 探针图预检 | **可选** Screen Recording | `app_focus` 4s / `click` 10s / `typing_pause` 静默 2s 后（最小 15s） / 12s 探针检查 / 120s 心跳；高优先级单槽排队 |
| **设备端 OCR** | `text` / `charCount` / `tokenCount` | 短命无头子进程 `DayHelm __ocr-worker`（空闲 `15s` 或满 `10` 帧退出；测试环境透明回退同进程）：从落盘 JPEG 按 `1280px` 缩略解码后运行 `VNRecognizeTextRequest`（`.accurate`、`usesLanguageCorrection = false`），对全屏高度达标图像（`height >= 480px`，覆盖 16:9/16:10/21:9 缩略图同时避免误裁 `960×240` 等小尺寸合成测试图）默认以 Vision 左下角归一化坐标排除顶部 `4%` 菜单栏区域（`regionOfInterest = (0, 0, 1, 0.96)` 并校验 `obs.boundingBox.maxY <= 0.965`，覆盖标准 `24pt` 与刘海屏 `37–38pt` 菜单栏而不误切浏览器或终端正文首行，且支持 `excludeTopMenuBar` 参数开关），彻底阻断系统菜单栏与 DayHelm 自身状态胶囊进入 `activity_ocr_frames` 与 FTS 索引 + 会话内连续帧去重 + `ocrEveryN` 间隔 | 同上（本机离线） | `app_focus` 与首帧立即执行；非 `app_focus` 触发最短间隔 `25s`（`minNonFocusOCRIntervalSeconds`），均在释放 `CGImage` 后异步执行 |
| **本机 HID** | 全局空闲秒数 `idleSeconds` | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, 0xFFFFFFFF)` + `HIDIdleTime` | 无 | 2s 轮询 |

> **分类与抖动抑制**（见 `docs/decisions/006-activity-classification-and-retention.md` 与 `docs/decisions/008-alma-parity-capture-retention-and-perf.md`）：`browser_visit` 仅当 URL 为 `http(s)` 且当前应用是已知浏览器（含 Chrome / Safari / Safari Technology Preview / Arc / Dia 等）；Preview/TextEdit/Finder 等 `file://` 文档记 `app_focus`。事件变更检测使用归一化标题与归一化 URL，应用切换不受 5s 最小变化间隔限制。30s 周期心跳事件仅在 `idleSeconds < 30s` 时写入，避免长空闲尾巴污染 `duration_ms`；`idleSeconds >= 180s`（3 分钟）、系统休眠或锁屏时在最后活动时间闭合会话，启动时自动收口残留未关闭会话。

> **视觉去重与分层留存**：同时检查 32-bin 直方图总变差距离（`>= 4%`）与 `160×90` 缩略图 RGB 像素差（通道差 `>= 30` 且占比 `>= 2%`）。自动维护执行两级降采样：`hot -> warm`（超过 1 天，最长边 `1280px`、质量 `0.4`）与 `warm -> cold`（留存 > 7 天且超过 7 天，`640px`、质量 `0.3`）；缺图或损坏文件直接标 `pruned` 防死循环；超过总容量封顶（默认 `10 GB`）按时间清理最旧快照至配额 `75%`（`7.5 GB`）。

> **结构化标签与会议/实体识别**：会话摘要采用 30s 节流重建，除写入 `topics`、`entities`（`task`/`app`/`domain` 及正则提取的 `repo`/`pr`/`local_port`）与 `highlights` 外，自动识别 Zoom / Google Meet / Teams / 飞书会议 / 腾讯会议 / Webex / 钉钉会议并标记 `is_meeting = 1`。

### 3. 采集层统一接口

```swift
public struct ActivitySample: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?     // 由 AX 补齐；敏感应用过滤后置 nil
    public let url: String?             // 由 AXDocument 提供并剥离敏感参数
    public let idleSeconds: TimeInterval
    public let screenLocked: Bool
    public let inputActive: Bool        // 结合键鼠活跃事件或 idleSeconds < 2s
    public let redacted: Bool           // true 时绝不保存标题/URL，且绝不截屏或 OCR
}
```

---

## 三、 判定与分析层（DayHelmCore）

### 1. 任务与双向配额模型（Target & Cap + 动态事项管理）

```swift
public struct TaskBudget: Sendable, Equatable, Codable, Identifiable {
    public var id: String { taskId }
    public let taskId: String           // 如 "ecommerce", "ecommerce-ops", "hermes" 或自动生成的唯一 slug
    public let displayName: String      // 如 "电商做深", "电商日常运营", "Hermes 投研"
    public let shortName: String?       // 菜单栏短名（可选）
    public let description: String?     // 一句话自然语言说明（可选，供 Jev 语义归类）
    public let colorHex: String         // 用于光谱条与标签颜色
    public let targetMinutes: Int?      // 保底目标时长（如 90 分钟）
    public let capMinutes: Int?         // 封顶上限时长（如运营最多 30 分钟）
    public let keywords: [String]       // 高级可选：窗口标题 / URL 关键词（用于离线兜底）
    public let appBundleIds: [String]   // 高级可选：关联应用 Bundle ID
    public let domains: [String]        // 高级可选：关联域名
}
```

### 1.5 可选 Jev 两层语义自动归属引擎（`SemanticAutoTracker` + `JevActivityClient`）

详见 [ADR 012](decisions/012-jev-semantic-auto-tracking.md)：
- **配置与密钥隔离**：`DayHelmSettings` 新增 `jevAutoTrackingEnabled`（默认 `false`）、`jevModel`（默认 `jev-latest`）与 `jevSendOCRSnippet`（默认 `true`）；API Key 独立保存在 `~/.config/alma/dayhelm/jev.key`（`0600`），亦支持 `JEV_API_KEY` 环境变量 / 本地 `.env`。开启开关但缺少 Key 时，设置页与菜单栏面板均提示配置 API Key。
- **两层正交模型（优先支持零项目开箱即用）**：
  - **第 1 层（`ActivityMode`，内置 6 大类，无需配置）**：`开发构建 (build)`、`内容创作 (create)`、`业务运营 (operate)`、`研究规划 (research)`、`沟通杂务 (comms_admin)`、`休息分心 (break)`，自动按类累计今日时长。
  - **第 2 层（`TaskBudget` 焦点项目，完全可选）**：用户配置了焦点项目时并行判定所属项目（或 `none`），命中项目优先展示项目名与配额进度，未命中或未配置项目时直接展示第 1 层活动大类与今日时长。
- **零手工确认闭环与语义切换联动**：
  1. 通过 `NSWorkspace.didActivateApplicationNotification`（跨应用）与前台单 PID `AXWindowChangeObserver`（同应用切窗/浏览器切 Tab，`60ms` 标题合并防抖）在 `< 80ms` 内事件驱动感知上下文变化（2 秒 `pollOnce()` 退居兜底，稳态零额外轮询 CPU）；随后以一次性精确防抖计时器过滤 `< 0.65s` 瞬时路过与加载中间态（缓存回切过滤 `< 0.45s` 防闪烁），并跳过 DayHelm 自身、辅助浮层、空白新标签页、浏览器加载中 `无标题` / `Untitled` 页面以及无 URL/`chrome://` 的 `账号和同步` 过场弹窗，按细粒度 `semanticContextKey`（浏览器保留**完整子域名主机名**——仅剥离 `www.` 并在非默认端口时保留端口如 `127.0.0.1:8787`，避免 `registrableDomain` 将 `task.lban2049.xyz` 与 `maus-bot.lban2049.xyz` 合并——并拼接**规范化清洗后的窗口标题**，剥离末尾 ` - Google Chrome - <Profile名>` / ` - Google Chrome` / Edge / Arc / Safari 等浏览器与 Profile 后缀以及 `- 内存用量高 - \d+(?:\.\d+)?\s*[KMGT]?B` / `High memory usage` 等动态内存提示，确保不同 Profile 与内存提示抖动共享同一缓存键，同时严格隔离同主域不同子站以及同域不同频道/看板/发帖页）缓存 5 分钟（`contextCacheTTLSeconds = 300s`）。
  2. **短标题/自建 Web 工作台 OCR 触发与防双发等待窗口**：除弱标题、日期标题、多用途关键词（Discord/Hermes/Vikunja 等）与本地/Tailnet 地址外，`SemanticPayloadSanitizer.shouldAttachOCR` 进一步覆盖「清洗浏览器后缀后标题较短（按 CJK=2 / ASCII=1 权重 `≤ 12`）或通用、或无明确路径语义的自定义域名/子域名 Web 工作台」（如 `MausBot` / `Memo Inbox` / `入站`，且排除知名内容/开发/电商站点），同时保持清晰单用途长标题页（如 `商品上货-抖店妙手` + `/move`）跳过 OCR。命中 `shouldAttachOCR` 且无 180s 内同窗口 OCR、且具备屏录与 Vision OCR 条件时，在 `0.35s` 后触发受 `3s` 冷却保护的按需截屏 OCR，并将首次 Jev 调用的等待上限由 `minDwellBeforeClassifySeconds`（`0.65s`）短时延后至 `onDemandOCRWaitSeconds`（`1.4s`）：若 OCR 在窗口内落地（且停留 `>= 0.65s`）则立即收敛为**单次带 OCR 请求**并取消超时计时器，消除 `noOCR → OCR` 连续双发；若超过 `1.4s` 超时或无有效 OCR，则降级发 `noOCR` 请求，绝不阻塞分类。
  3. `SemanticPayloadSanitizer` 对外发上下文执行锁屏阻断、`PrivacyRedactor` 脱敏阻断、URL 敏感参数剥离、凭据掩码与**浏览器窗口标题后缀规范化**（同步应用于当前窗口与最近 3 条历史窗口，保留真实页面标题、剥离浏览器/Profile 名与动态内存后缀），并对命中的目标窗口附带同窗口标题匹配且通过 `stripTopChromeNoise` 清洗后的 OCR 正文摘要（≤ 600 字符）：`stripTopChromeNoise` 除支持剥离 `www.` 后的地址栏锚点（`urlHost` 命中时从 2 行起即可锚定）剥离 Chrome 标签栏/地址栏外，还对前导行执行容错去噪——过滤带 OCR 错字的 macOS 顶部中英文菜单栏（如 `燴辑`、`历史记承`、`FeEdit ViewWindow`）、DayHelm 自身菜单栏模式与时长胶囊（如 `开发构建 32m`、`沟通杂务 18m`）以及未含地址栏的浏览器后台标签栏行，只附带最近 3 条原始客观窗口历史（不回传模型历史标签）。
  4. `JevActivityClient`（`DayHelmCapture`）通过单次 `POST /v1/systemone` 并行返回 `activity_mode`、可选 `focus_project` 与 `same_task`。其两层分类口径明确界定：`break` 仅限娱乐视频、社交媒体主页信息流（如 `/home`）、闲聊或纯生活抢券水群，云服务/AI 会员订阅与学生/开发者认证（如 SheerID、Google One、学信网、账单绑定）归 `comms_admin`（查阅攻略归 `research`）；开源/自建项目 Discord 频道（如 `#general | OpenMausBot`）结合上下文归 `research`/`build`；IDE/AI 编程工具中明确指向个人知识库或内容稿件创作/审阅（如 `obsidian`、`Podcast Draft`）归 `create`；进程名为 `Electron` 的未打包本地调试窗口（不论界面标题是否含运营/抖店等业务词或是否刚从浏览器切入）一律优先归 `build`。
  5. `SemanticAutoTracker`（`DayHelmCore`，纯逻辑可注入时钟）在窗口满足停留门控后由精确计时器准时调用 Jev：高置信度（`>= 0.80` 且 `same_task <= 0.60`）**立即自动切换**（热连接端到端 ~0.9–1.0s，冷 TLS 重连仍 `<= 2.0s`，命中缓存 ~0.5–0.6s）；中置信度（`0.70–0.80`）或高 `same_task` 通过精确计时器进入全自动短暂**防抖观察**（`1.2s–2.5s`，绝不弹窗打扰，同一目标跨窗口延续时不重置计时），自动提交切换并更新计划事项时长、配额提醒与 6 大活动模式累计时长。**语义回写事务性与采纳门控**：
     - **禁止迟到回包越权**：当在途 Jev 回包到达时若用户已切换至其他上下文（`observedContextKey != contextKey`），该回包仅按自身 `contextKey` 写入 5 分钟缓存并立即返回，绝不调用 `stampSemanticGroup` 或改写当前窗口的 `currentSemanticGroup` 与已有 span。
     - **禁止未采纳预测越权**：无论在线回包、缓存命中、防抖确认还是手工覆写路径，仅当 `SemanticAutoTracker` 真实采纳或维持该分类（非 `ignored_low_confidence`、非 `pending_confirmation`、且未被 `manualPin` 拦截）时，才更新 `engine.currentSemanticGroup` 并执行 `engine.stampSemanticGroup`。
     - **细粒度 `semanticContextKey` 匹配回写**：`DayHelmEngine.stampSemanticGroup(_:forContextKey:withinSeconds:at:)` 统一使用 `SemanticPayloadSanitizer.semanticContextKey(for: EnrichedSpan)` 匹配 60 秒内最近 span（替代主域名级 `SwitchClassifier.canonicalContextKey`），确保同主域不同子域名与同域不同频道/标签页的 `EnrichedSpan.semanticGroup` 互不倒灌污染，并与 `activityModeMinutes` 计时严格一致。
  6. 手工点击任一事项立即覆写当前归属并记入当日该 `contextKey` 的纠偏缓存（同步刷新当前上下文 span 语义组并在冷却期内以 `manualPin` 拦截自动覆盖），切至新窗口后自动追踪继续生效。

- **配置真源与冷启动初始化**：
  - 用户在 UI 中对事项的增删改查、排序与配额调整，全量持久化至 `~/.config/alma/dayhelm/config.json`。
  - 一旦 `dayhelm/config.json` 中已保存事项列表，`TimeAuditConfigLoader.loadBudgets` **直接以该文件为唯一真源**（不会重新灌入用户已删除的默认项或外部项）。
  - 仅在首次启动且 `dayhelm/config.json` 尚无已保存事项时，才使用内置默认列表并与只读的 `~/.config/alma/time-audit/config.json` / `focus.json` 合并初始化。
- **进度状态**：
  - `underTarget`：保底尚未达标（显示还差 X 分钟）
  - `targetMet`：已达保底目标（绿色达标标记）
  - `approachingCap`：已达封顶上限的 85%（预警）
  - `capReached`：已触达或超过封顶上限（琥珀色高亮 + 触发换挡提醒）

### 2. 专注会话与时间累计（容许跨应用协同）

```swift
public enum FocusSessionState: Sendable, Equatable, Codable {
    case unassigned                                     // 杂事/未指定专注事项（后台仍记录客观活动）
    case focusing(taskId: String, startedAt: Date)      // 正在专注某事项
    case paused(taskId: String, pausedAt: Date)         // 锁屏或长空闲自动暂停
}
```

- **跨应用包容原则**：当用户声明处于 `.focusing(taskId: "ecommerce")` 时，只要人在场（未锁屏、且未超过 `idleThreshold` 3 分钟长空闲），期间切换到预览、Finder、表格、终端或通用网页等辅助工具，**时长持续累计入当前声明的 `taskId`**，不会因为切换应用而打断连续块。
- **在场判定（Presence）、空闲回扣与休眠断档保护**：
  - 结合 `screenLocked == false` 且 `idleSeconds < 180s`（3 分钟）。
  - **空闲自动回扣**：离开电脑未锁屏时，轮询在 `0–179s` 间累计的时长会在首次达到 `180s` 空闲时按 `lastActiveAt = timestamp - idleSeconds` 精确回扣（仅扣当前连续段，绝不倒扣历史时段），确保离座前的 3 分钟不会虚增今日投入时长。
  - **休眠与断档保护**：系统触发 `will_sleep` 时立即调用 `engine.handleSystemSleep(at:)` 封口当前会话并清空计时基线；同时实机模式下启用单次 tick 步长硬上限（`maxTickGapSeconds = 60s`），任何超过 60 秒的时钟跳跃/休眠断档只重置基线、绝不计入活跃时长。
  - **自动暂停 vs 手动暂停**：因离座/锁屏/休眠触发的自动暂停在用户回到电脑重新活跃后自动恢复计时；用户手动点击的暂停保持暂停直到手动继续或切换任务。

### 3. 今日时间光谱条（Day Spectrum Ribbon）与连续度计算

将当天从首个活跃时刻到当前的连续时间轴，切分为带语义的区间（`SpectrumSegment`）：

- **优先级**：高频乱切 > 用户设定的具体事项 > Jev 活动大类 > 未指定专注 > 空闲。高优先级区间覆盖低优先级区间。
- **事项专注段**：区间匹配到用户设定的 `TaskBudget` 时，按该事项颜色着色（如蓝色代表 `电商做深`，琥珀色代表 `电商运营`，绿色代表 `Hermes`）。
- **活动大类段**：区间没有匹配到具体事项，但 `EnrichedSpan.semanticGroup` 命中 Jev 活动大类时，按 `ActivityMode` 的语义色着色（开发/创作/运营/研究/杂务/休息），让尚未配置事项的新用户也能直接看出今天的时间结构。
- **高频乱切段（Thrashing Segment）**：当滑动窗口（如 5–10 分钟）内切换频次超过阈值（如折合 > 45 次/小时且平均停留 < 45 秒）时，在光谱条上标记为**斜纹警示段**，直观暴露注意力溃散时段。
- **空闲/离开段**：灰色底色；**休息分心**作为活动大类单独着色，但不计入「最长连续块」与「≥12m 有效块」。

### 4. 三类轻量监督提醒触发器（Supervisor Triggers）

| 触发器 | 触发条件 | 冷却与防打扰策略 |
|---|---|---|
| **1. 配额封顶/达标提醒** (`quotaAlert`) | 当前专注事项累计时长刚达到 `capMinutes`（强制提醒换挡）或 `targetMinutes`（温和知会达标） | 每个事项每天默认触发 1 次；用户点「+15m 收尾」后延后 15 分钟再提醒一次 |
| **2. 跨项目跑偏提醒** (`driftAlert`) | 阶段 2 细化：声明在做事项 A，但最近连续 N 分钟窗口标题/URL 明确命中事项 B 的特征关键词 | 用户可点「改计入事项 B」、「回到事项 A」或「顺手处理（静音 10 分钟）」 |
| **3. 高频乱切提醒** (`thrashingAlert`) | 10 分钟滑动窗口内出现 ≥10 次有效跨任务切换，且跨 ≥4 类活动或 ≥4 次打断型切换、平均有效停留 <45s；按 `semanticGroup` / 域名 / 应用聚合，不把同一活动的多应用配合误报为乱切 | 触发后至少冷却 30 分钟，绝不连续弹窗 |

---

## 四、 UI 方案与视觉设计规范（Precision Telemetry 精密仪表风）

摒弃传统番茄钟的大留白和本地截图工具的笨重窗口，采用类似 **Linear / Raycast / iStat Menus** 的高信息密度、等宽数字对齐、语义化色彩设计。

### 1. 视觉 Token（Design System）

- **字体与数字排版**：
  - 界面文本：系统原生 `SF Pro Text`
  - 所有计时、配额比值、窗口路径、统计数字：**强制使用等宽数字 `.system(..., design: .monospaced)` 或 `.monospacedDigit()`**，确保秒表跳动与进度对齐时零抖动。
- **四色语义体系**：
  - **推进蓝 (`Primary Blue`)**：当前专注进行中、保底配额正常累积。
  - **达标绿 (`Success Emerald`)**：今日保底目标（Target）已达成、采集状态健康。
  - **封顶琥珀 (`Warning Amber`)**：触达今日时间上限（Cap，如日常运营满 30m），需要立即收尾换挡。
  - **斜纹警示红 (`Destructive Hatch`)**：高频碎片化乱切时段。

### 2. 三个核心界面载体（无笨重主窗口）

#### 载体 A：macOS 顶部菜单栏实时胶囊（MenuBar Live Pill）
- 常驻系统菜单栏，左侧带自定义矢量日舵（Helm）模板图标，并通过图标明暗与右下角 `5pt` 语义状态点区分状态（在**仅图标模式**下同样一眼可辨）：
  - **待命（`standby`）**：日舵图标呈半透明（`0.48`），无状态圆点；
  - **专注推进中（`focusing`）**：日舵图标全亮 + 右下角**推进蓝**圆点；
  - **已达保底（`targetMet`）**：日舵图标全亮 + 右下角**达标绿**圆点；
  - **触达封顶（`capReached`）**：日舵图标全亮 + 右下角**封顶琥珀**圆点；
  - **其他事务（`otherWork`）**：日舵图标全亮 + 右下角**中性灰蓝**圆点；
  - **分心/休息（`distraction`）**：日舵图标全亮 + 右下角**警示红**圆点。
- 文本采用系统比例字体 `11.5pt` + `.monospacedDigit()`（仅数字等宽防抖动），去掉冗余 `"DayHelm"` 品牌文字与前置状态符号，悬停（`.help()`）展示完整事项名称与进度；支持在设置中切换 3 档显示密度（`DayHelmSettings.menuBarDisplayMode`，默认 **`standard`**）：
  - **标准模式（`standard`，默认）**：始终以文字标签表明当前事务类型 + 进度/已用时长；命中焦点项目时优先展示项目名（优先 `TaskBudget.shortName`，未设置时按视觉宽度 CJK=2/ASCII=1 保留至多 16 单位），未配置或未命中项目时展示第 1 层活动模式与今日累计时长：
    - 命中焦点项目推进中：`电商运营 52/90m`、`独立产品开发 25/60m`
    - 触达封顶上限：`电商运营 31/30m▲`
    - 未命中项目（或零项目模式）：`开发构建 32m`、`内容创作 18m`、`业务运营 45m`、`研究规划 14m`、`沟通杂务 8m`、`休息分心 6m`
    - 未指定专注（待命）：`待命`
  - **极简模式（`compact`）**：兼顾刘海屏与多图标环境：
    - 专注推进中：`52/90m`（触达上限 `31/30m!`）
    - 自动识别为其他事务/分心：`杂务 12m` / `分心 6m`
    - 未指定专注（待命）：仅显示日舵图标（无额外文字）
  - **仅图标模式（`iconOnly`）**：始终仅显示日舵图标，通过悬停提示或点击 Popover 查看详情。

#### 载体 B：菜单栏下拉高密度仪表盘（Popover，固定宽 `330pt`，一屏免滚动）
由 `MenuBarPopoverHostView` 托管，闭合时彻底从 SwiftUI `AttributeGraph` 卸载，后台运行态同步门控非可见 `@Published` UI 计算与 `refreshRecorderCountsAsync()`，打开时立即全量刷新。由上至下分为 5 个紧凑模块（内边距 `14pt`，模块间距 `11pt`）：
1. **顶部品牌与采集状态栏 + 引擎状态微条**：左侧自定义日舵矢量徽标 + `DayHelm` 标识，右侧实时状态胶囊；下方紧凑展示 **「采集与 OCR 引擎」** 状态条（`AX 标题` 状态、`屏幕 OCR (X 帧)` 开关/授权按钮、`Agent API :24001` 端口指示）。
2. **当前专注控制盒（Active Focus Box）**：
   - 右上角大号等宽计时器（如 `26:40`），左侧显示当前专注事项名称。
   - 单行等宽小字实时回显当前捕获到的窗口标题/URL（如 `当前窗口: 抖店后台 - 商品主图 (Chrome)`），让用户直观看到采集器在工作。
   - **任务一键切换胶囊行（Quick Switcher Pills）**：动态展示当前已配置的全部事项及 `⏸ 杂事/休息`，单击即切，零输入成本。
3. **今日事项配额进度条（Quota Budget List，精简展示与一键切换）**：
   - 保持悬浮窗精简免滚动，仅展示今日已投总时长与达标汇总，以及每个事项的实时配额进度。
   - 每个事项一行：左侧圆点 + 事项名 + `专注中` 状态徽标，右侧状态微标签（`保底差 38m` / `已达上限` / `✓ 已达标`）+ 等宽进度 `52/90m`，下方 `6pt` 细圆角进度条与百分比；整行单击即可切换当前专注事项。
   - 事项的新增、编辑、排序、删除以及关键词 / 关联应用 / 域名规则全部移至独立设置窗口的「事项与配额」分区。
4. **今日时间光谱条（Day Spectrum Ribbon）**：
   - 一条 `22pt` 高的横向彩色分段条（基于单 SwiftUI `Canvas` 绘制，从今日开始工作到当前时刻），直观展示各事项分布与斜纹碎片化段。
5. **底部三格遥测微指标（Telemetry Footer）** + **精简操作底栏**：
   - 三等分小格：`今日最长连续块 (34m)` ｜ `近期切换热度 (19/h)` ｜ `≥12m 有效块 (3个)`。
   - 底栏保留高频轻操作：`提醒测试`、`设置`、`统计`（直达「每日统计」Tab）、`历史会话`、配置目录快捷图标、`退出`。

#### 载体 C：右上角非抢占式监督浮窗（Non-activating HUD Toast，宽 `350pt`）
- **实现方式**：使用 `NSPanel`，设置 `styleMask: [.nonactivatingPanel, .borderless]`，`level: .floating`，`collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`。
- **核心体验保证**：**绝不抢占当前键盘焦点（Key Window）**——当你正在终端或浏览器打字时，它从屏幕右上角温和滑出，不会吞掉你的任何按键，也不搞 15 秒倒计时锁死。
- **卡片结构**：
  - 左侧 `4pt` 语义色竖条（琥珀色=配额封顶，蓝色=跑偏提醒）。
  - 顶部一句话结论（如 `⏰ 【电商日常运营】已达到今日 30m 上限`）。
  - 中部一行客观数据说明（如 `今天「电商做深」还差 38 分钟达标，建议现在换挡`）。
  - 底部 2–3 个快捷动作按钮（如 `[ 切到「电商做深」 ]`、`[ +15m 收尾 ]`、`[ 转入休息 ]`）。
- **高频乱切文案规范**：标题写明观测窗口、切换次数与活动类别数（如 `近 10m 跨了 5 类活动（10 次切换）`）；正文用用户可理解的标签解释识别到了哪些活动类型（Jev 模式名或项目名，不展示窗口标题 / URL），并给出二选一动作：同一事项的多应用配合可忽略，否则先固定一个活动约 10 分钟再处理其他分支。10 分钟与检测窗口一致，且明显高于本机 session 中位时长 4.1 分钟，足以打破本次报警条件。

#### 载体 D：独立设置与活动记录窗口（`ActivityRecorderWindow`）
- **定位与触发**：从菜单栏 Popover 顶栏设置图标或底部 `设置` / `历史会话`（或引擎状态条）打开，并在打开时自动收起菜单栏 Popover；打开独立窗口期间自动将应用激活策略切为 `.regular`（在底部 Dock 与 `Cmd+Tab` 展示应用图标，点击 Dock 图标可一键唤回），窗口关闭后恢复 `.accessory` 静默菜单栏模式。集中承载所有低频/复杂配置，避免破坏 `330pt` 菜单栏面板一屏免滚动体验；遵循 Precision Telemetry 卡片网格与 `.monospacedDigit()` 规范。
- **一体化工具栏导航（Unified Toolbar）**：窗口采用标准非重叠标题栏（不使用 `.fullSizeContentView` 透明穿透，确保内容区向上滚动严格裁切在工具栏下方、绝不与导航栏重叠）+ `titleVisibility = .hidden` + `.unified` 工具栏，红黄绿窗口控制钮右侧依次排列会话侧栏折叠按钮（仅「历史会话」显示）、DayHelm Logo 与名称、平级导航项（`事项与配额` ｜ `每日统计` ｜ `Jev 识别` ｜ `活动采集` ｜ `隐私与存储` ｜ `历史会话`；其中 `isSettingsSection` 排除 `每日统计` 与 `历史会话`，确保菜单栏「设置」入口始终落入设置分区），右侧展示采集状态胶囊与刷新按钮：
  - **「事项与配额」**：专注管理今日可选焦点项目与菜单栏显示密度——包含事项新增/编辑弹窗（名称、短名、一句话说明、6 色语义色点、保底目标与封顶上限滑块/直输联动控件、折叠式高级离线匹配规则）、上下排序、删除确认，修改立即生效并同步至悬浮窗；不配置项目时亦可完全依赖 Jev Layer-1 活动大类运行。
  - **「每日统计」**（`DailyStatsView`）：按天预计算历史统计看板与本地 Agent 深度分析提示词生成器（**仅查看前一天及更早历史日期，不在主线程或切换 Tab 时实时计算当天**）：
    1. **后台预计算与异步非阻塞加载**：App 启动与每日跨天切换（`rollover`）时，在后台 `.utility` 串行队列通过 `DailyStatsMaterializer` 自动扫描缺失（或 `schemaVersion` 过期）的 `< today` 历史日期并原子落盘至 `stats/YYYY-MM-DD.json`；切换 Tab 或切换日期时仅异步读取已持久化报表（若该天仍在后台生成则展示非阻塞加载占位并在完成后自动刷新），默认定位到最近一个有数据的历史日期（通常为昨天），无历史数据时展示清晰空状态提示；支持异步后台触发单日重算。
    2. **顶部日期切换与主操作栏（防换行单行设计）**：左侧紧凑切换组（`<` 图标钮 + 日期下拉菜单 + `>` 图标钮 + `最新` 胶囊 + 异步重算刷新图标，按钮统一 `.lineLimit(1)` 与 `.fixedSize(horizontal: true, vertical: false)`），中部展示起止活跃时段与跨度（或加载状态胶囊），右侧主操作按钮「复制 Agent 提示词」，在 720–900pt 窄宽下均保持单行不折行。
    3. **4 格等宽等高核心遥测卡（带近 7 日均值微对比 `baseline7d`）**：严格 4 等宽等高且标题/主数值/对比胶囊/副指标基线对齐：总活跃时长（含起止跨度）、**持续专注占比**（`≥3m` 连续工作块占比 + `pp vs 7d` 百分点微对比，副行展示时长加权 `典型连续块 X.Xm` / `最长 Ym` / `≥12m 有效块 Z 个`，悬停 `.help` 解释口径）、有效跨任务切换数/每小时切换热度与高频乱切累计时长/段数、键鼠输入密度（`clickCount`/`keypressCount`/`inputEventsPerMinute`）与会话/会议/快照/OCR 计数。
    4. **放大版日时间光谱条** + **等高对齐双栏布局**：全页卡片统一内边距（`14pt`）、圆角（`10pt`）与标准标题栏（图标 + 标题 + 右侧图例/切换开关）；「时间分配双卡」（事项配额与 6 大活动大类 ｜ Top 应用与 Top 浏览器站点）与「行为习惯双卡」（5 档连续停留时长分布 ｜ 高频切换路径 Top 8）采用等高双栏行，左右卡片顶底边严格齐平，列表内所有数字列（段数/次数、时长、占比、均停秒数）固定宽右对齐 `.monospacedDigit()`。
    5. **24 小时分时节律图**（单小时活跃分钟/有效切换/乱切分布，支持悬停查看单小时详情）与 **本地 Agent 深度分析提示词卡片**（等宽等高双预设按钮「每日复盘与习惯诊断」「工作产出与日报草稿」、展开只读预览与一键复制，内嵌动态本地路径、`dayhelm` CLI 命令、`sqlite3 -readonly` 示例、轻量统计骨架及只读/隐私脱敏护栏）。
  - **「Jev 识别」**：独立承载所有 Jev System One 智能自动识别配置与判断历史：
    1. **智能自动识别配置卡片**：开关、API Key 状态/录入/连通性测试、发送脱敏本机 OCR 摘要开关（弱标题门控）。未配置 API Key 且已开启时，标题栏该 Tab 显示琥珀色提醒圆点，菜单栏悬浮窗横幅亦直达此页。
    2. **Jev 判断记录卡片**：今日调用统计摘要（总次数、自动切换次数、平均耗时、累计输入 Token）、按状态过滤（全部/已切换/待确认或忽略/异常）、清空按钮与完整记录列表（每条展示时间、决策结果、`[活动大类]`、`→ 焦点项目`、置信度/同任务概率/分心概率、耗时与输入 Token、脱敏后窗口上下文与 OCR 预览）。
  - **「活动采集」**：
    1. **活动记录器总览卡片**：总开关（`activityRecorderEnabled`）、4 格实时遥测胶囊（总会话数 / 已用快照存储与张数 / 当前会话状态 / 前台应用）及存储上限进度条。
    2. **macOS 权限卡片**：屏幕录制、辅助功能（AX 标题与全局键鼠监听）实时状态检测、刷新与一键授权/跳转。
    3. **采集参数网格（2 列）**：快照防抖（`appFocusDebounceMs`）、心跳间隔（`heartbeatIntervalMs`）、空闲关闭阈值（`recorderIdleThresholdMs`）、输入停顿（`typingPauseQuietMs`）、画面变化轮询（`visualCheckIntervalMs`，`0` 关闭）与 JPEG 质量（`jpegQuality`，`1–100`）。
    4. **OCR 与输入卡片**：屏幕快照总开关（`deepRecordingEnabled`）、Vision OCR 开关（`visionOCREnabled`）、全局键鼠计数开关（`inputMonitoringEnabled`）、OCR 语言列表（`ocrLanguages`）与采样步长（`ocrEveryN`）。
    5. **最近会话快速预览**：展示近期数条会话，点击直接跳转至「历史会话」视图并定位详情。
  - **「隐私与存储」**：
    1. **敏感应用（永不采集）卡片**：多行 Bundle ID 编辑器（`sensitiveBundleIds`），实时同步至 `PrivacyRedactor` 与 `AXWindowInspector`。
    2. **存储配额卡片**：最大存储（MB）、快照保留天数、数据目录展示及 Finder 打开入口。
  - **「历史会话」**：支持通过标题栏折叠按钮显隐左侧可搜索会话列表（含任务标签颜色、相对时间、时长/活跃徽标、快照与事件计数），右侧详情检视器（应用列表、实体标签、输入密度、事件时间线、快照缩略图与 OCR 文本）。

---

## 五、 存储层、开放 SQLite、Agent CLI 与本地 HTTP API

### 1. 本地存储路径（`~/.config/alma/dayhelm/`）

```
~/.config/alma/dayhelm/
  activity.sqlite           # 开放 SQLite 数据库（WAL 模式 + FTS5 trigram OCR 索引）
  snapshots/YYYY-MM-DD/     # 去重 JPEG 快照（1920px/0.55；>1天 warm 1280px/0.4；>7天 cold 640px/0.3；默认 10GB 封顶裁至 75%）
  today.json                # 今日实时热数据（原子写入：today.json.tmp -> rename；周期刷新间隔 30s）
  days/YYYY-MM-DD.json      # 每日定稿归档（含补齐了 windowTitle 的活动区间与专注会话）
  stats/YYYY-MM-DD.json     # 历史单日预计算统计报表（仅含 < today 日期，启动与跨天后台生成，原子写入）
  config.json               # 事项配额配置 + DayHelmSettings（采集开关/防抖/心跳/空闲/停顿/轮询/JPEG质量/OCR语言与步长/sensitiveBundleIds/留存与存储上限）
```

### 2. 开放 SQLite 数据库结构（`activity.sqlite`）

启用 `PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;`，包含四张与 Alma 兼容的业务表与一张 OCR FTS5 虚表：

- `activity_sessions`：`id`, `started_at`, `ended_at`, `duration_ms`, `trigger_kind`, `app_names`, `event_count`, `click_count`, `keypress_count`, `snapshot_count`, `total_bytes`, `analysis_status`, `analysis_title`, `analysis_description`, `analysis_model`, `analysis_error`, `analyzed_at`, `worth_memory`, `worth_knowledge`, `is_meeting`, `storage_tier`, `entities`, `topics`, `project`, `highlights`, `declared_task_id`, `created_at`, `updated_at`
  - 空闲超过会话间隔（默认 `120s`）、休眠、锁屏或跨日时自动切分新会话；写事件/快照采用 $O(1)$ 增量更新会话计数器，摘要合成按 30s 节流触发（关闭或 OCR 写入时强制刷新）。
  - `click_count` / `keypress_count` 按事件 `data.count`（缺失时计 1）累加刷新（不读按键内容，只计次）。会话摘要额外派生 `inputEventsPerMinute`。
- **日/周汇总不另建表**：`/summary/daily|weekly`、`/digest`、`/report/<dateKey>` 由核心四表现场聚合。
- `activity_events`：`id`, `session_id`, `timestamp`, `kind` (`app_focus` / `browser_visit` / `click` / `keypress` / `lock` / `unlock`), `app_name`, `window_title`, `url`, `data`, `created_at`
- `activity_snapshots`：`id`, `session_id`, `timestamp`, `file_path`, `width`, `height`, `size_bytes`, `trigger`, `app_name`, `window_title`, `hash_hex`, `histogram` (32-bin JSON), `diff_pct`, `storage_tier` (`hot` / `warm` / `cold` / `downsampled` / `pruned`), `created_at`
- `activity_ocr_frames`：`id`, `snapshot_id`, `session_id`, `text`, `char_count`, `token_count`, `created_at`
- `activity_ocr_fts`：基于 `FTS5 tokenize='trigram'` 的全文索引虚表（通过触发器自动同步），关键词长度 `>= 3` 走 FTS5 `MATCH`，`< 3` 回退 `LIKE`。
- **热查询索引与运行态收敛**（见 `docs/decisions/011-cpu-and-memory-performance-convergence.md`）：建表时自动创建 `idx_activity_sessions_open`（部分索引 `WHERE ended_at IS NULL`）、`idx_activity_snapshots_ts`、`idx_activity_snapshots_tier_ts` 与 `idx_activity_ocr_created_at` 消除全表扫描；活跃会话计数在内存中增量缓存，摘要合成对 `(app_name, window_title, url)` 先做 SQL `GROUP BY` 聚合再提取实体与主题；本地 HTTP 运行态快照改为按需懒生成。

### 3. 单日确定性聚合、后台预计算与本地 Agent 提示词（`DailyStats.swift`）

- **`DailyStatsAggregator`**（`DayHelmCore`，无 `AppKit` 依赖，`schemaVersion = 2`）：
  - **单一真源口径**：时间分配、日时间光谱、连续块（**持续专注占比** `sustainedFocusShare` = `≥3m` 非乱切、非休息连续工作块累计时长 / 总活跃时长、**时长加权中位块时长** `weightedMedianBlockMinutes`、最长连续块与 `≥12m` 有效块；保留 `medianBlockMinutes` 兼容字段）与跨任务切换指标以 `DayHelmDaySnapshot`（`days/YYYY-MM-DD.json` 或指定 `today.json`）为准，输入密度（`clickCount`/`keypressCount`/`inputEventsPerMinute`）及会话/会议/快照/OCR 计数由 `ActivityDatabase` 按日补齐；自动读取 `stats/YYYY-MM-DD.json`（优先且校验 `schemaVersion == DailyStatsReport.currentSchemaVersion`）或 `days/YYYY-MM-DD.json` 中目标日期之前最多 7 个历史日计算 `baseline7d` 均值基线（含 `avgWeightedMedianBlockMinutes` 与 `avgSustainedFocusShare`）。
  - **站点与隐私脱敏规则**：Top 浏览器站点从 `http(s)` URL 解析 Host，统一小写、剥离前导 `www.` 并保留非默认端口（剥离 `http:80` / `https:443`）；`redacted == true` 记录绝不泄露窗口标题或域名至 Top 站点、高频切换路径 `A → B`、`stats/*.json` 或 Prompt 骨架。
- **`DailyStatsMaterializer`**（`DayHelmCore`，无 `AppKit` 依赖）：
  - 扫描 `days/YYYY-MM-DD.json` 与 `activity.sqlite` 中的历史会话日期，**严格跳过当天（`todayDateString`）及未来日期**；对尚未生成 `stats/YYYY-MM-DD.json` 或落盘 `schemaVersion < DailyStatsReport.currentSchemaVersion` 的历史日期按时间升序调用 `DailyStatsAggregator` 计算并原子写入（同版本幂等跳过，旧版本平滑升级重建）。
  - `HybridActivityCoordinator` 在启动后及每次跨天 `rollover` 时，通过专用串行后台 `.utility` 队列调用 `DailyStatsMaterializer` 补齐历史报表，并在完成后刷新可用历史日期列表通知 UI。
- **`DailyStatsMarkdownRenderer` & `AgentAnalysisPromptBuilder`**：
  - `DailyStatsMarkdownRenderer` 将 `DailyStatsReport` 渲染为紧凑 Markdown 骨架（输出持续专注占比、时长加权典型连续块、最长块、`≥12m` 有效块及 7 日均值对照），同时供 `dayhelm stats --format md` 与 Prompt 复用；
  - `AgentAnalysisPromptBuilder` 根据 `AgentAnalysisPromptPreset`（`dailyReview` / `workOutputDraft`）动态填充目标日期、本地数据目录（`stats/YYYY-MM-DD.json`、`days/YYYY-MM-DD.json` / `today.json`、`activity.sqlite`）、推荐 `dayhelm` CLI 下钻命令、`sqlite3 -readonly` 只读查询示例及隐私脱敏护栏。

### 4. Agent CLI 接口（`DayHelm`）

任意 AI Agent 可直接通过命令行读取或检索当日活动上下文（支持 `md` 与 `json`）：

```bash
dayhelm query [--today | --since <2h|30m|YYYY-MM-DD>] [--format json|md] [--store-dir <path>]
dayhelm search <keyword> [--limit 20] [--format json|md] [--store-dir <path>]
dayhelm sessions [--date YYYY-MM-DD] [--id <session_id>] [--format json|md] [--store-dir <path>]
dayhelm stats [--date YYYY-MM-DD] [--rebuild] [--format json|md] [--json] [--store-dir <path>]
dayhelm status [--format json|md] [--store-dir <path>]   # --json 等价于 --format json
dayhelm purge [--before YYYY-MM-DD] [--store-dir <path>]
```

`dayhelm status --format json` 输出 `{schemaVersion, date, focusState, activeTaskId, budgets, metrics, recorder}`；`recorder` 含今日 `sessions/events/snapshots/ocrFrames/clickCount/keypressCount/inputEventsPerMinute`，便于 Agent 直接判定采集是否健康、人在不在场。

### 5. 本地兼容 HTTP API（`127.0.0.1` 环回）

由 `LocalActivityHTTPServer`（`Network.NWListener`）仅在 `127.0.0.1` 提供服务，默认端口 **`24001`**（若被占用则在 `24001...24009` 范围内自动选择首个未占用端口；绝不占用 Alma 使用的 `23001`）：

- `GET /api/activity-recorder/status`：采集器状态、端口、AX/Screen Recording 权限状态、今日会话/事件/快照/OCR 计数
- `GET /api/activity-recorder/permissions`：返回 `{ axTrusted, screenCaptureTrusted, keypressMonitoringEffective }`
- `GET /api/activity-recorder/config`：返回 `{ deepRecordingEnabled, snapshotRetentionDays, snapshotMaxStorageBytes, ocrEveryN }`
- `GET /api/activity-recorder/sessions?limit=...&offset=...&since=...&until=...&analysisStatus=...`：兼容 Alma 会话列表格式（`{sessions:[...], total}`，支持分页与状态过滤，`since`/`until` 同时接受毫秒时间戳与 ISO8601）
- `GET /api/activity-recorder/sessions/<id>`：支持完整 ID 或 ≥6 位唯一前缀，返回 `{ session, events, snapshots, ocrFrames, ocr }`
- `GET /api/activity-recorder/sessions/<id>/events`：支持完整 ID 或 ≥6 位唯一前缀，返回 `{ events, total }`
- `GET /api/activity-recorder/search/keyword?q=<kw>&limit=50`：Alma 形状的 OCR 关键词检索（≥3 字符走 FTS5 trigram），`q` 为空时返回 `{ results: [] }`
- `GET /api/activity-recorder/snapshot-file?path=<file>`（或 `?id=<snapshot_id>`）：返回快照原始 JPEG 字节（`Content-Type: image/jpeg`）；越界一律 `403 forbidden path`，文件不存在 `404`
- `GET /api/activity-recorder/summary/daily/<YYYY-MM-DD>`：Alma `activity_summaries` 形状日汇总
- `GET /api/activity-recorder/summary/weekly/<YYYY-Www>`（也接受 `YYYY-MM-DD`）：Alma 形状周汇总
- `GET /api/activity-recorder/digest?hours=...&since=...`：结构化近窗口活动摘要（默认 24 小时）
- `GET /api/activity-recorder/report/<YYYY-MM-DD>`：无 LLM 确定性日报 `{ dateKey, skeletonOnly: true, markdown, stats }`
- `GET /api/dayhelm/context?since=...`：面向 AI Agent 的结构化摘要（当前专注状态、今日配额、连续度指标、最近窗口标题/URL 与 OCR 片段）
- `GET /api/dayhelm/search?q=<kw>&limit=20`：跨窗口标题 / URL / 应用名 / 会话摘要 / OCR（FTS5 加速）的富检索 `{ keyword, total, hits }`

### 6. `today.json` 核心结构示例

```json
{
  "schemaVersion": 1,
  "date": "2026-11-17",
  "activeFocus": {
    "taskId": "ecommerce",
    "startedAt": "2026-11-17T11:45:00+08:00"
  },
  "budgets": [
    {
      "taskId": "ecommerce",
      "displayName": "电商做深",
      "focusedMinutes": 52.0,
      "targetMinutes": 90,
      "capMinutes": 120,
      "status": "under_target"
    },
    {
      "taskId": "ecommerce-ops",
      "displayName": "电商日常运营",
      "focusedMinutes": 31.0,
      "targetMinutes": null,
      "capMinutes": 30,
      "status": "cap_reached"
    }
  ],
  "focusSessions": [
    {
      "id": "sess_focus_01",
      "taskId": "ecommerce",
      "startedAt": "2026-11-17T09:15:00+08:00",
      "endedAt": "2026-11-17T09:50:00+08:00",
      "minutes": 35.0,
      "note": "完成第 1 个品的主图筛选"
    }
  ],
  "enrichedSpans": [
    {
      "startedAt": "2026-11-17T09:15:00+08:00",
      "endedAt": "2026-11-17T09:22:10+08:00",
      "appName": "Google Chrome",
      "bundleId": "com.google.Chrome",
      "windowTitle": "抖店后台 - 商品管理",
      "url": "https://fxg.jinritemai.com/ffa/mshop/homepage/index",
      "declaredTaskId": "ecommerce"
    }
  ],
  "metrics": {
    "activeMinutes": 164.0,
    "longestBlockMinutes": 35.0,
    "solidBlocksCount": 3,
    "recentSwitchesPerHour": 19.2
  }
}
```

### 7. 与 `alma-time-audit` 的协同契约
- **读取配置**：DayHelm 仅在初次初始化时只读读取 `~/.config/alma/time-audit/focus.json` 与 `config.json`。
- **独立 `2400x` 兼容接口**：DayHelm 在 `127.0.0.1:24001`（`2400x` 段）提供兼容的 `/api/activity-recorder/sessions` 接口，回传已补齐的 `windowTitle`、OCR 文本与 `declaredTaskId`，同时不干扰 Alma 自身的 `23001` 服务；`days/YYYY-MM-DD.json` 中的 `enrichedSpans` 也可被 `time-audit` 直接读取。

---

## 六、 图标资产与生产安装隔离

- **应用图标生成 (`scripts/generate-icon.swift`)**：
  - 使用 `AppKit` / `CoreGraphics` 渲染 `1024x1024` macOS Squircle 图标至 `branding/dayhelm-icon-1024.png`（深邃海蓝仪表盘渐变 `#0F172A -> #1E293B`、微光内边框、光谱分段环形刻度 `#3B82F6` / `#10B981` / `#F59E0B` 与居中舵针），并通过 `iconutil` 打包为 `branding/AppIcon.icns`。
  - `scripts/build-app.sh` 构建 `.app` 时自动生成/更新图标并复制到 `Contents/Resources/`，并在 `Info.plist` 中配置 `CFBundleIconFile = AppIcon`。
- **生产安装脚本 (`scripts/install-app.sh`)**：
  - 编译 Release 包至 `build/DayHelm.app` 后，独立复制安装至 `/Applications/DayHelm.app`（仅当 `/Applications` 不可写时回退到 `~/Applications/DayHelm.app`），并重新进行 ad-hoc `codesign`。
  - 生产应用路径与代码签名身份完全独立于仓库开发目录，日常试用不受后续 `swift build` 或源码修改影响；支持 `--launch` 参数在安装后自动重启生产版。

