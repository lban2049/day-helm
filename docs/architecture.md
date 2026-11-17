# 技术方案与 UI 规范（DayHelm · 日舵）

## 一、 整体分层架构

四层解耦，只通过明确定义的协议通信，每层可单独关闭或替换假实现：

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 界面层 (DayHelmApp)                                                     │
│   ├─ MenuBar 实时胶囊 (MenuBarExtra) + 330pt 高密度下拉仪表盘           │
│   ├─ 采集与 OCR 引擎状态条（AX 标题 / 屏幕 OCR 开关与帧数 / Agent API） │
│   └─ 右上角非抢占式监督浮窗 (NSPanel: .nonactivatingPanel)              │
├─────────────────────────────────────────────────────────────────────────┤
│ 判定与数据中心层 (DayHelmCore · 纯 Swift，严禁 import AppKit)           │
│   ├─ EventMerger / QuotaTracker / SpectrumBuilder / SlidingSupervisor   │
│   ├─ ActivityDatabase: 开放 SQLite (SQLite3 WAL)，兼容 Alma 四表模型    │
│   └─ DayHelmCLI: query / search / sessions / status / purge             │
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
│       └─ today.json + days/YYYY-MM-DD.json + config.json                │
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
| **本机 AX** | 前台应用 `appName` + `bundleId` | `NSWorkspace.frontmostApplication` + `didActivateApplicationNotification` | 无 | 事件驱动 + 2s 轮询 |
| **本机 AX** | 窗口标题 `windowTitle` & `url` | AX `kAXFocusedWindowAttribute` → `kAXTitleAttribute` + `AXDocument` | Accessibility | 2s 轮询 |
| **原生事件监听** | `app_focus` / `browser_visit` / `lock` / `unlock` / `click` / `keypress` / 计次活跃 | `NSWorkspace` / `DistributedNotificationCenter` / `NSEvent` 计次（不读按键内容） | 无 / 辅助功能 | 事件驱动（键鼠节流） |
| **原生屏幕快照** | 去重 JPEG + 32-bin 直方图 + `hashHex` | `ScreenCaptureKit` (`SCScreenshotManager`) | **可选** Screen Recording | `app_focus` 4s / `click` 10s / `typing_pause` 静默 2s 后（最小 15s） / 12s 视觉检查 / 120s 心跳；全部走 `diffPct >= 4%` 去重 |
| **设备端 OCR** | `text` / `charCount` / `tokenCount` | Apple `Vision.VNRecognizeTextRequest` (`.accurate`) | 同上（本机离线） | 随去重快照在后台 `.utility` 队列执行 |
| **本机 HID** | 全局空闲秒数 `idleSeconds` | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, 0xFFFFFFFF)` + `HIDIdleTime` | 无 | 2s 轮询 |

> **分类与抖动抑制**（见 `docs/decisions/006-activity-classification-and-retention.md`）：`browser_visit` 仅当 URL 为 `http(s)` 且当前应用是已知浏览器；Preview/TextEdit/Finder 等 `file://` 文档记 `app_focus`。事件变更检测使用归一化标题（去除 `(3)`、`14:52`、`87%`、`…` 等易变片段）与归一化 URL，应用切换不受 5s 最小变化间隔限制。`idleSeconds >= 300s` 或锁屏时关闭当前会话（`ended_at` 取最后活动时间）并停止一切截图/OCR。旧快照超过 1 天降采样为 480px/0.4，超过留存天数再删除。

> **结构化标签**：会话摘要合成时写入 `topics`（任务/项目 + 高频应用 + 网页域名）、`entities`（`task`/`app`/`domain` 分组）与 `highlights`（头部窗口标题），并通过 CLI 与 HTTP API 暴露给 Agent。

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
    public let colorHex: String         // 用于光谱条与标签颜色
    public let targetMinutes: Int?      // 保底目标时长（如 90 分钟）
    public let capMinutes: Int?         // 封顶上限时长（如运营最多 30 分钟）
    public let keywords: [String]       // 窗口标题 / URL 关键词（用于跑偏识别）
}
```

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

- **跨应用包容原则**：当用户声明处于 `.focusing(taskId: "ecommerce")` 时，只要人在场（未锁屏、且未超过 `idleThreshold` 5 分钟长空闲），期间切换到预览、Finder、表格、终端或通用网页等辅助工具，**时长持续累计入当前声明的 `taskId`**，不会因为切换应用而打断连续块。
- **在场判定（Presence）**：结合 `screenLocked == false` 且（`idleSeconds < 300s` 或 Alma 当前 session 处于活跃态），避免阅读思考时被误判离开。

### 3. 今日时间光谱条（Day Spectrum Ribbon）与连续度计算

将当天从首个活跃时刻到当前的连续时间轴，切分为带语义的区间（`SpectrumSegment`）：

- **事项专注段**：按当前归属的 `taskId` 着色（如蓝色代表 `电商做深`，琥珀色代表 `电商运营`，绿色代表 `Hermes`）。
- **高频乱切段（Thrashing Segment）**：当滑动窗口（如 5–10 分钟）内切换频次超过阈值（如折合 > 45 次/小时且平均停留 < 45 秒）时，在光谱条上标记为**斜纹警示段**，直观暴露注意力溃散时段。
- **空闲/离开段**：灰色底色。

### 4. 三类轻量监督提醒触发器（Supervisor Triggers）

| 触发器 | 触发条件 | 冷却与防打扰策略 |
|---|---|---|
| **1. 配额封顶/达标提醒** (`quotaAlert`) | 当前专注事项累计时长刚达到 `capMinutes`（强制提醒换挡）或 `targetMinutes`（温和知会达标） | 每个事项每天默认触发 1 次；用户点「+15m 收尾」后延后 15 分钟再提醒一次 |
| **2. 跨项目跑偏提醒** (`driftAlert`) | 阶段 2 细化：声明在做事项 A，但最近连续 N 分钟窗口标题/URL 明确命中事项 B 的特征关键词 | 用户可点「改计入事项 B」、「回到事项 A」或「顺手处理（静音 10 分钟）」 |
| **3. 高频乱切提醒** (`thrashingAlert`) | 阶段 2 细化：短滑动窗口内应用/标签高频横跳，无法形成连续块 | 触发后至少冷却 30 分钟，绝不连续弹窗 |

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
- 常驻系统菜单栏，左侧带自定义矢量日舵（Helm）模板图标，无需点击即可用余光瞥见当前状态：
  - **专注推进中**：`● 电商做深 · 52/90m`
  - **触达封顶上限**：`▲ 日常运营 · 31/30m (已到点)`
  - **未指定专注**：`○ DayHelm · 待命`

#### 载体 B：菜单栏下拉高密度仪表盘（Popover，固定宽 `330pt`，一屏免滚动）
由上至下分为 5 个紧凑模块（内边距 `14pt`，模块间距 `11pt`）：
1. **顶部品牌与采集状态栏 + 引擎状态微条**：左侧自定义日舵矢量徽标 + `DayHelm` 标识，右侧实时状态胶囊；下方紧凑展示 **「采集与 OCR 引擎」** 状态条（`AX 标题` 状态、`屏幕 OCR (X 帧)` 开关/授权按钮、`Agent API :24001` 端口指示）。
2. **当前专注控制盒（Active Focus Box）**：
   - 右上角大号等宽计时器（如 `26:40`），左侧显示当前专注事项名称。
   - 单行等宽小字实时回显当前捕获到的窗口标题/URL（如 `当前窗口: 抖店后台 - 商品主图 (Chrome)`），让用户直观看到采集器在工作。
   - **任务一键切换胶囊行（Quick Switcher Pills）**：动态展示当前已配置的全部事项及 `⏸ 杂事/休息`，单击即切，零输入成本。
3. **今日时间配额进度条与事项管理（Quota Budget List & Task CRUD）**：
   - 标题栏提供 `+ 新增事项` 与 `排序/管理` 控件，支持在界面内直接完成事项增删改排，无需手改 JSON。
   - 每个事项一行：左侧事项名，右侧等宽进度 `52 / 90m` + 状态微标签（`保底差 38m` / `⚠️ 已达上限` / `✓ 已达标`），管理模式下显示上下排序按钮，下方 `7pt` 细圆角进度条。
   - 点击编辑图标（或 `+ 新增事项`）弹出约 `300pt` 宽的**事项与配额编辑器**：
     - 事项名称（`TextField`）、6 色语义色点选择、匹配关键词（逗号分隔 `TextField`）。
     - **保底目标（`targetMinutes`）**与**封顶上限（`capMinutes`）**均提供独立开关及**双模联动时长控件（`Slider(5...240, step: 5)` + 同步直输数字 `TextField`）**，支持直接键入任意分钟数或拖动滑块。
     - 编辑模式提供`删除`与`保存`操作（删除当前正在专注的事项时自动切回待命 `.unassigned`）。
4. **今日时间光谱条（Day Spectrum Ribbon）**：
   - 一条 `22pt` 高的横向彩色分段条（从今日开始工作到当前时刻），直观展示各事项分布与斜纹碎片化段。
5. **底部三格遥测微指标（Telemetry Footer）**：
   - 三等分小格：`今日最长连续块 (34m)` ｜ `近期切换热度 (19/h)` ｜ `≥12m 有效块 (3个)`。

#### 载体 C：右上角非抢占式监督浮窗（Non-activating HUD Toast，宽 `350pt`）
- **实现方式**：使用 `NSPanel`，设置 `styleMask: [.nonactivatingPanel, .borderless]`，`level: .floating`，`collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary]`。
- **核心体验保证**：**绝不抢占当前键盘焦点（Key Window）**——当你正在终端或浏览器打字时，它从屏幕右上角温和滑出，不会吞掉你的任何按键，也不搞 15 秒倒计时锁死。
- **卡片结构**：
  - 左侧 `4pt` 语义色竖条（琥珀色=配额封顶，蓝色=跑偏提醒）。
  - 顶部一句话结论（如 `⏰ 【电商日常运营】已达到今日 30m 上限`）。
  - 中部一行客观数据说明（如 `今天「电商做深」还差 38 分钟达标，建议现在换挡`）。
  - 底部 2–3 个快捷动作按钮（如 `[ 切到「电商做深」 ]`、`[ +15m 收尾 ]`、`[ 转入休息 ]`）。

---

## 五、 存储层、开放 SQLite、Agent CLI 与本地 HTTP API

### 1. 本地存储路径（`~/.config/alma/dayhelm/`）

```
~/.config/alma/dayhelm/
  activity.sqlite           # 开放 SQLite 数据库（WAL 模式）
  snapshots/YYYY-MM-DD/     # 去重 JPEG 快照（0.55 质量；超过 1 天降采样为 480px/0.4，默认保留 7 天自动清理）
  today.json                # 今日实时热数据（原子写入：today.json.tmp -> rename）
  days/YYYY-MM-DD.json      # 每日定稿归档（含补齐了 windowTitle 的活动区间与专注会话）
  config.json               # 事项配额配置 + deepRecordingEnabled / snapshotRetentionDays
```

### 2. 开放 SQLite 数据库结构（`activity.sqlite`）

启用 `PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;`，包含四张与 Alma 兼容并扩展了 `window_title` 与 `declared_task_id` 的核心表：

- `activity_sessions`：`id`, `started_at`, `ended_at`, `duration_ms`, `trigger_kind`, `app_names`, `event_count`, `snapshot_count`, `total_bytes`, `analysis_status`, `analysis_title`, `analysis_description`, `analysis_model`, `analysis_error`, `analyzed_at`, `worth_memory`, `worth_knowledge`, `is_meeting`, `storage_tier`, `entities`, `topics`, `project`, `highlights`, `declared_task_id`, `created_at`, `updated_at`
  - 空闲超过会话间隔（默认 `120s`，可在 `30s–300s` 间配置）、锁屏或跨日时自动切分新会话，并基于高频应用、窗口标题与专注事项自动合成 `analysis_title` 与 `analysis_description`。
- `activity_events`：`id`, `session_id`, `timestamp`, `kind` (`app_focus` / `browser_visit` / `click` / `keypress` / `lock` / `unlock`), `app_name`, `window_title`, `url`, `data`, `created_at`
- `activity_snapshots`：`id`, `session_id`, `timestamp`, `file_path`, `width`, `height`, `size_bytes`, `trigger` (`app_focus` / `click` / `typing_pause` / `visual_change` / `heartbeat`), `app_name`, `window_title`, `hash_hex`, `histogram` (32-bin JSON), `diff_pct`, `storage_tier` (`hot` / `downsampled` / `pruned`), `created_at`
- `activity_ocr_frames`：`id`, `snapshot_id`, `session_id`, `text`, `char_count`, `token_count`, `created_at`

### 3. Agent CLI 接口（`DayHelm`）

任意 AI Agent 可直接通过命令行读取或检索当日活动上下文（支持 `md` 与 `json`）：

```bash
dayhelm query [--today | --since <2h|30m|YYYY-MM-DD>] [--format json|md] [--store-dir <path>]
dayhelm search <keyword> [--limit 20] [--format json|md] [--store-dir <path>]
dayhelm sessions [--date YYYY-MM-DD] [--id <session_id>] [--format json|md] [--store-dir <path>]
dayhelm status [--store-dir <path>]
dayhelm purge [--before YYYY-MM-DD] [--store-dir <path>]
```

### 4. 本地兼容 HTTP API（`127.0.0.1` 环回）

由 `LocalActivityHTTPServer`（`Network.NWListener`）仅在 `127.0.0.1` 提供服务，默认端口 **`24001`**（若被占用则在 `24001...24009` 范围内自动选择首个未占用端口；绝不占用 Alma 使用的 `23001`）：

- `GET /api/activity-recorder/status`：采集器状态、端口、AX/Screen Recording 权限状态、今日会话/事件/快照/OCR 计数
- `GET /api/activity-recorder/sessions?limit=...&since=...&until=...`：兼容 Alma 会话列表格式（`{sessions:[...], total}`；`since`/`until` 同时接受毫秒时间戳与 ISO8601）
- `GET /api/activity-recorder/sessions/<id>`：返回 `{ session, events, snapshots, ocrFrames }`（含完整 `windowTitle` 与 `declaredTaskId`）
- `GET /api/activity-recorder/sessions/<id>/events`：仅返回 `{ events, total }`，兼容只需要事件流的 Alma/审计调用方；`kind` 保留 `app_focus` / `browser_visit` / `click` / `keypress` / `lock` / `unlock` / `typing_pause`
- `GET /api/dayhelm/context?since=...`：面向 AI Agent 的结构化摘要（当前专注状态、今日配额、连续度指标、最近窗口标题/URL 与 OCR 片段）

### 5. `today.json` 核心结构示例

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

### 6. 与 `alma-time-audit` 的协同契约
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

