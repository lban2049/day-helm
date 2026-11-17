# 技术方案与 UI 规范（DayHelm · 日舵）

## 一、 整体分层架构

四层解耦，只通过明确定义的协议通信，每层可单独关闭或替换假实现：

```
┌─────────────────────────────────────────────────────────────────────────┐
│ 界面层 (DayHelmApp)                                                     │
│   ├─ MenuBar 实时胶囊 (MenuBarExtra) + 330pt 高密度下拉仪表盘           │
│   └─ 右上角非抢占式监督浮窗 (NSPanel: .nonactivatingPanel)              │
├─────────────────────────────────────────────────────────────────────────┤
│ 判定与分析层 (DayHelmCore · 纯 Swift，严禁 import AppKit)               │
│   ├─ EventMerger: 融合 Alma 实时事件与 AX 窗口标题为连续 ActivitySpan   │
│   ├─ QuotaTracker: 计算各事项今日累计时长、保底缺口(Target)与封顶(Cap)  │
│   ├─ SpectrumBuilder: 生成今日时间光谱条数据与连续块/切换频次指标       │
│   └─ SlidingSupervisor: 滑动窗口检测配额到点、持续跑偏与高频碎片化乱切  │
├─────────────────────────────────────────────────────────────────────────┤
│ 混合采集层 (DayHelmCapture)                                             │
│   ├─ AlmaActivityClient: 增量拉取 localhost:23001 实时 sessions/events  │
│   └─ AXWindowInspector: 2s 轮询 NSWorkspace + AX 补齐窗口标题与 URL     │
├─────────────────────────────────────────────────────────────────────────┤
│ 存储层 (DayHelmStore)                                                   │
│   └─ ~/.config/alma/dayhelm/ (today.json 原子写 + days/YYYY-MM-DD.json) │
└─────────────────────────────────────────────────────────────────────────┘
```

### SwiftPM 模块划分（统一工程结构）

```
Package.swift
├── Sources/DayHelmCore/        # 纯逻辑与数据模型（无 AppKit，注入 Clock，100% 可单测）
├── Sources/DayHelmCapture/     # Alma HTTP 客户端 + macOS AX/NSWorkspace/CGEvent 采集实现
├── Sources/DayHelmApp/         # SwiftUI 菜单栏仪表盘 + NSPanel 非抢占提醒窗
└── Sources/DayHelmChecks/      # 确定性自检可执行程序（合成数据验证配额、合并与监督触发）
```

---

## 二、 混合采集层：结合 Alma 实时数据 + AX 标题补齐

### 1. 为什么要做双通道混合采集？

本机已有常驻运行的 **Alma `activity-recorder`**（`http://localhost:23001/api/activity-recorder/...`），经实测：
- **Alma 已具备的实时数据**：
  - 当前与今日所有 `sessions`（毫秒级 `startedAt`, `endedAt`, `triggerKind`）
  - 实时 `events` 流：`app_focus`（应用切换时间点与 `bundleId`）、`browser_visit`（Chrome URL 与 Tab 名）、`keypress` / `click`（键鼠活跃计数）、`unlock`（解锁事件）。
- **Alma 缺失的数据**：
  - `snapshots` 中的 `windowTitle` 字段全部为 `null`（未保存非 Chrome 应用的窗口标题）。

因此，DayHelm 采用 **「Alma 实时流 + 本机 AX 标题增补」** 的双通道混合方案：
1. **开机/重启即拥有全天完整历史**：DayHelm 启动时直接拉取 `localhost:23001` 今日已有的 `sessions` 与 `events`，哪怕中途重启 App，当天的活动轨迹、切换次数也分秒不差。
2. **2 秒轮询补齐窗口标题与 URL**：DayHelm 自身运行极轻量的 `AXWindowInspector`，每 2 秒通过 `NSWorkspace.frontmostApplication` + Accessibility (`kAXTitleAttribute` & `AXDocument`) 获取当前前台窗口标题与浏览器 URL，按时间戳增补到活动流中。
3. **离线无缝降级**：若 `localhost:23001` 未响应，自动退化为纯本机 `NSWorkspace + AX + CGEventSource` 独立采样，保证任何情况下工具可用。

### 2. 采集数据清单与 API

| 数据源 | 字段 | 实现方式 | 权限 | 频率 |
|---|---|---|---|---|
| **Alma API** | `sessions` / `events` (`app_focus`, `browser_visit`, `click`, `keypress`, `unlock`) | `GET http://localhost:23001/api/activity-recorder/sessions` | 无（本地 HTTP） | 启动全量 + 10s 增量同步 |
| **本机 AX** | 前台应用 `appName` + `bundleId` | `NSWorkspace.frontmostApplication` + 激活通知 | 无 | 事件驱动 + 2s 轮询 |
| **本机 AX** | 窗口标题 `windowTitle` | AX `kAXFocusedWindowAttribute` → `kAXTitleAttribute`（降级 `kAXWindows[0]`） | Accessibility | 2s 轮询 |
| **本机 AX** | 浏览器当前 `url` | AX `AXDocument` on focused window | Accessibility | 2s 轮询 |
| **本机 HID** | 全局空闲秒数 `idleSeconds` | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, 0xFFFFFFFF)` + `HIDIdleTime` 校验 | 无 | 2s 轮询 |
| **系统通知** | 屏幕锁定 `screenLocked` | `DistributedNotificationCenter` (`com.apple.screenIsLocked` / `Unlocked`) | 无 | 事件驱动 |

### 3. 采集层统一接口

```swift
public struct ActivitySample: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let appName: String
    public let bundleId: String?
    public let windowTitle: String?     // 由 AX 补齐；敏感应用过滤后置 nil
    public let url: String?             // 由 AXDocument 或 Alma browser_visit 提供
    public let idleSeconds: TimeInterval
    public let screenLocked: Bool
    public let inputActive: Bool        // 结合 Alma click/keypress 或 idleSeconds < 2s
}
```

---

## 三、 判定与分析层（DayHelmCore）

### 1. 任务与双向配额模型（Target & Cap）

```swift
public struct TaskBudget: Sendable, Equatable, Codable, Identifiable {
    public var id: String { taskId }
    public let taskId: String           // 如 "ecommerce", "ecommerce-ops", "hermes"
    public let displayName: String      // 如 "电商做深", "电商日常运营", "Hermes 投研"
    public let colorHex: String         // 用于光谱条与标签颜色
    public let targetMinutes: Int?      // 保底目标时长（如 90 分钟）
    public let capMinutes: Int?         // 封顶上限时长（如运营最多 30 分钟）
}
```

- **配置复用**：项目基础清单与关键词从 `~/.config/alma/time-audit/config.json` 与 `focus.json` 只读加载；每个事项的每日 `targetMinutes` / `capMinutes` 保存在 `~/.config/alma/dayhelm/config.json`。
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
- 常驻系统菜单栏，无需点击即可用余光瞥见当前状态：
  - **专注推进中**：`● 电商做深 · 52/90m`
  - **触达封顶上限**：`▲ 日常运营 · 31/30m (已到点)`
  - **未指定专注**：`○ DayHelm · 待命`

#### 载体 B：菜单栏下拉高密度仪表盘（Popover，固定宽 `330pt`，一屏免滚动）
由上至下分为 5 个紧凑模块（内边距 `16pt`，模块间距 `12pt`）：
1. **顶部品牌与采集状态栏**：左侧 `DayHelm` 标识，右侧实时状态胶囊 `● Alma + AX 采集中`。
2. **当前专注控制盒（Active Focus Box）**：
   - 右上角大号等宽计时器（如 `26:40`），左侧显示当前专注事项名称。
   - 单行等宽小字实时回显当前捕获到的窗口标题/URL（如 `当前窗口: 抖店后台 - 商品主图 (Chrome)`），让用户直观看到采集器在工作。
   - **任务一键切换胶囊行（Quick Switcher Pills）**：横排展示 `电商做深`、`电商运营`、`Hermes`、`Infra`、`⏸ 杂事/休息`，单击即切，零输入成本。
3. **今日时间配额进度条（Quota Budget List）**：
   - 每个事项一行：左侧事项名，右侧等宽进度 `52 / 90m` + 状态微标签（`保底差 38m` / `⚠️ 已达上限` / `✓ 已达标`），下方 `7pt` 细圆角进度条。
4. **今日时间光谱条（Day Spectrum Ribbon）**：
   - 一条 `20pt` 高的横向彩色分段条（从今日开始工作到当前时刻），直观展示各事项分布与斜纹碎片化段。
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

## 五、 存储层与外部系统契约

### 1. 本地存储路径（`~/.config/alma/dayhelm/`）

```
~/.config/alma/dayhelm/
  today.json              # 今日实时热数据（原子写入：today.json.tmp -> rename）
  days/YYYY-MM-DD.json    # 每日定稿归档（含补齐了 windowTitle 的活动区间与专注会话）
  config.json             # 每日各事项配额配置（targetMinutes / capMinutes）与提醒阈值
```

### 2. `today.json` 核心结构示例

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

### 3. 与 `alma-time-audit` 的协同契约
- **读取配置**：DayHelm 只读读取 `~/.config/alma/time-audit/focus.json` 与 `config.json`。
- **反哺标题与归因**：DayHelm 产出的 `enrichedSpans`（带真實 `windowTitle` 和 `declaredTaskId`）保存在 `~/.config/alma/dayhelm/days/YYYY-MM-DD.json`，次日 `time-audit` 可直接读取，彻底解决原本因 `windowTitle: null` 和多应用协同导致的项目归属率低问题。
