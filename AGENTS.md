# DayHelm（日舵）· 开发约定

一个 macOS 单人自用工具。定位是**当日时间配额掌舵、实时活动分析（结合 Alma 实时采集 + AX 标题补齐）与跑偏/到点温和监督**。
完整背景见 `docs/`，本文件只写**约束**。

## 这个项目要解决什么（写代码前先读）

用户实测基线（2026-11 月，来自 `~/.config/alma/time-audit/`）：

- session 中位时长 **4.1 分钟**；244 个 session 里只有 25 个 ≥10 分钟
- 活跃日切换 **50–78 次/小时**
- 切换发生在多个**正当工作**之间（`alma` / `ecommerce` / `hermes` / `infra-billing`），且处理单个任务（如电商）时天然需要在多个应用（浏览器、表格、图片工具、终端）之间协同切换
- 本机已有 Alma `activity-recorder` (`localhost:23001`) 实时记录事件，但**未保存应用窗口标题**（`windowTitle: null`）；且 `alma-time-audit` 只能**次日**分析，当天缺乏实时配额监督

四条由此推出的硬约束，任何设计不得违反：

1. **轻量监督与校准，不做强制锁死。** 不做单次 Cmd+Tab 全屏读秒拦截，不做应用白名单强行隐藏/最小化，不做"扛强杀会话锁"。提醒一律使用右上角**不抢键盘焦点**的轻量卡片（`.nonactivatingPanel`）。
2. **双通道混合采集，不重复造底层钩子。** 复用 Alma `localhost:23001` 的实时 session/event 数据，并用本机轻量 AX 采样补齐缺失的 `windowTitle` 与 `AXDocument` URL；当 Alma 未运行时可无缝降级为纯本机采样。
3. **支持双向配额（保底 Target + 封顶 Cap）。** 既要监督核心任务是否达到每日保底时长，也要在容易超时的任务（如日常运营）达到设定上限时提醒换挡，避免在一件事上耗尽全天。
4. **UI 保持高密度精密仪表风（Precision Telemetry）。** 统一采用等宽数字（`.monospacedDigit()`）、四色语义系统（推进蓝/达标绿/封顶琥珀/乱切斜纹红）、330pt 免滚动菜单栏面板与今日时间光谱条。

## 文档为主（Documentation-First）

**先改文档，再改代码。** 顺序不可颠倒：

| 要动的东西 | 先更新 |
|---|---|
| 产品范围、验收目标 | `docs/requirements.md` |
| 模块划分、数据流、存储格式、UI 规范 | `docs/architecture.md` |
| 采集范围、权限、数据留存与删除 | `docs/privacy.md` |
| 阶段划分与验证顺序 | `docs/roadmap.md` |
| 任何技术选型的取舍 | 新增 `docs/decisions/NNN-<slug>.md` |

- 文档描述**当前真实状态**，不写"打算以后做"。未实现或待细化的东西放在 `docs/roadmap.md` 或需求的"待细化问题"中。
- 决策记录（ADR）格式：背景 / 候选方案 / 选择 / 理由 / 推翻条件。**必须写"推翻条件"**。
- 代码里的关键常量（阈值、迟滞窗口、配额）必须在文档里有出处和理由，不能是拍脑袋的魔法数字。

## 测试先行（Test-First）

**没有失败的测试，就不写实现。**

- 顺序：写测试 → 跑，确认它**因为正确的原因失败** → 写最小实现 → 跑通 → 再重构。
- 测试必须能在**无 GUI、无网络、无真实用户数据**的条件下跑通。CI 友好。
- 时间相关逻辑一律**注入时钟**，不直接调 `Date()`。事件合并、配额累计、光谱条切分、滑动窗口检测全部可确定性测试。
- 每个测试只断言一件事。断言失败信息要能直接指出哪条不变量破了。

### 测试组织

用 SwiftPM library + executable checks 组织：

```
Package.swift
Sources/DayHelmCore/        # 纯逻辑，严禁 import AppKit
Sources/DayHelmCapture/     # Alma HTTP + AX 采集实现，用协议隔离
Sources/DayHelmApp/         # MenuBarExtra + NSPanel UI
Sources/DayHelmChecks/      # 确定性自检断言，失败 exit 1
```

## 技术事实（已验证，不要重新踩）

以下均已在本机 macOS 26.6.2 实测确认，写代码时直接采信：

| 结论 | 含义 |
|---|---|
| Alma `http://localhost:23001/api/activity-recorder/sessions` 实时可用 | 能直接拿到今日 `sessions` 和毫秒级 `app_focus`、`browser_visit`、`keypress`、`click`、`unlock` 事件，但 `snapshots.windowTitle` 为 `null` |
| AX `kAXTitleAttribute` 读窗口标题、**AX `AXDocument` 读浏览器当前 URL** | 需要 Accessibility。实测都拿到了，正好补齐 Alma 缺失的窗口标题 |
| `NSWorkspace.frontmostApplication`、`CGEventSource.secondsSinceLastEventType` | 均**无需权限** |
| 空闲检测**不能用 `.keyDown`** | 只用鼠标时会误判离开。用 `CGEventType(rawValue: 0xFFFFFFFF)` 或结合 Alma 实时 `click/keypress` 事件 |
| `NSPanel` + `.nonactivatingPanel` + `.floating` | 可以在右上角弹出带按钮的提醒卡片，且**不抢夺用户当前正在打字的窗口焦点** |
| `MenuBarExtra` 的图标被用户拖掉后 **app 会自动终止** | 需要 launchd 兜底 |
| `~/.config/alma/time-audit/daily/*.json` 是**次日 08:00** 才生成 | "今日已投入"必须由 DayHelm 实时计算，**不能读日报** |

## 数据与隐私边界

- 采集范围：**Alma 实时活动事件 + 前台应用名、窗口标题、浏览器当前 URL、屏幕锁定状态、空闲时长**。
- **不采**：音频、键盘输入具体文本内容、剪贴板、屏幕截图（DayHelm 自身不截图）。
- 所有数据留在本机 `~/.config/alma/dayhelm/`。不加遥测、崩溃上报、云同步。
- 标题和 URL 按高敏感数据处理。写入前过滤密码管理器、银行、私人聊天类应用（名单在 `docs/privacy.md`）。
- 真实窗口标题、URL、数据库**不得提交到 Git**。测试一律用合成数据。
- 提供一条命令彻底删除所有采集数据，并在文档里写明。

## 与既有系统的关系（重要）

| 系统 | 位置 | 关系 |
|---|---|---|
| `Alma activity-recorder` | `http://localhost:23001` | 底层实时事件源之一。DayHelm 读取其实时事件，并补齐其缺失的 `windowTitle` |
| `alma-time-audit` | `~/.config/alma/scripts/`、`~/dev/code/alma-time-audit/` | 产出日/周报，做事后审计与评分。**DayHelm 负责当天实时掌舵，与它互补** |

## 未得到用户明确要求时

- 不运行会真正采集用户数据的常驻进程
- 不修改 `~/.config/alma/time-audit/` 下的任何既有配置
- 不提交、不推送、不部署
- 不在 `/Applications` 下的任何 app 包里改代码
