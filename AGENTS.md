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
2. **独立原生采集 + 开放数据中心，兼顾兼容。** 内置原生事件监听、AX 窗口标题与 URL 补齐、可选且可开关的去重屏幕快照与设备端 Apple Vision OCR（`activity.sqlite`），并暴露 Agent CLI 与兼容 `/api/activity-recorder/...` 的本地 HTTP 服务（`127.0.0.1:24001`，`24001...24009` 空闲选端，绝不抢占 Alma 的 `23001` 端口），无需启动 Alma 即可独立运行；当 Alma 运行时仍可平滑兼容。
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
- 时间相关逻辑一律**注入时钟**，不直接调 `Date()`。事件合并、配额累计、光谱条切分、滑动窗口检测、SQLite/CLI/HTTP 接口全部可确定性测试。
- 每个测试只断言一件事。断言失败信息要能直接指出哪条不变量破了。

### 测试组织

用 SwiftPM library + executable checks 组织：

```
Package.swift
Sources/DayHelmCore/        # 纯逻辑、SQLite3 存储、Agent CLI，严禁 import AppKit
Sources/DayHelmCapture/     # 原生 AX / 屏幕快照与 Vision OCR / 本地 HTTP 服务 / Alma 客户端
Sources/DayHelmApp/         # MenuBarExtra + NSPanel UI
Sources/DayHelmChecks/      # 确定性自检断言，失败 exit 1
```

## 技术事实（已验证，不要重新踩）

以下均已在本机 macOS 26.6.2 实测确认，写代码时直接采信：

| 结论 | 含义 |
|---|---|
| Alma `http://localhost:23001/api/activity-recorder/sessions` 为 Alma 专用端口 | DayHelm 自身服务绑定 `127.0.0.1:24001`（`24001...24009` 空闲选端），绝不绑定 `23001` 以免导致 Alma 异常；Alma 运行时可从 `23001` 只读回补 |
| AX `kAXTitleAttribute` 读窗口标题、**AX `AXDocument` 读浏览器当前 URL** | 需要 Accessibility。实测都拿到了，补齐 `windowTitle` |
| `ScreenCaptureKit` + `Vision.VNRecognizeTextRequest` | `Screen Recording` 为可选权限：开启并授权时捕获 32-bin 直方图去重 JPEG + 本机离线 OCR；拒绝或关闭时不纠缠 |
| `NSWorkspace.frontmostApplication`、`CGEventSource.secondsSinceLastEventType` | 均**无需权限** |
| 空闲检测**不能用 `.keyDown`** | 只用鼠标时会误判离开。用 `CGEventType(rawValue: 0xFFFFFFFF)` 结合 `NSEvent` 计次活跃 |
| `NSPanel` + `.nonactivatingPanel` + `.floating` | 可以在右上角弹出带按钮的提醒卡片，且**不抢夺用户当前正在打字的窗口焦点** |
| `MenuBarExtra` 的图标被用户拖掉后 **app 会自动终止** | 需要 launchd 兜底 |
| `~/.config/alma/time-audit/daily/*.json` 是**次日 08:00** 才生成 | "今日已投入"必须由 DayHelm 实时计算，**不能读日报** |

## 数据与隐私边界

- 采集范围：**本机活动事件（含计次级键鼠活跃，不读按键内容）+ 前台应用名、窗口标题、浏览器当前 URL、屏幕锁定状态、空闲时长 + 可选的去重屏幕快照与本机 Apple Vision OCR 文本**。
- **不采**：音频、摄像头、键盘输入**具体文本内容**、剪贴板、脱敏应用或锁屏时的屏幕截图与 OCR。
- 命中 `PrivacyRedactor` 脱敏规则（`redacted == true`）或锁屏时：**绝不保存标题/URL，且绝不截屏、绝不运行 OCR**。
- 所有数据留在本机 `~/.config/alma/dayhelm/`（`activity.sqlite`、`snapshots/`、`today.json`、`days/`、`config.json`）。不加遥测、崩溃上报、云同步；内置 HTTP API 仅绑定 `127.0.0.1` 环回地址。
- 真实窗口标题、URL、快照、数据库**不得提交到 Git**。测试一律用合成数据（含合成渲染图像）。
- 提供 `dayhelm purge` 命令彻底删除所有采集数据（含 JSON、SQLite、快照），并在文档里写明。

## 与既有系统的关系（重要）

| 系统 | 位置 | 关系 |
|---|---|---|
| `Alma activity-recorder` | `http://localhost:23001` | 可选只读兼容。DayHelm 已内置独立原生采集器与 `activity.sqlite`，并使用 `24001`（`2400x`）端口，不抢占 `23001` |
| `alma-time-audit` | `~/.config/alma/scripts/`、`~/dev/code/alma-time-audit/` | 产出日/周报，做事后审计与评分。**DayHelm 负责当天实时掌舵并在 24001 开放完整数据，与它互补** |
| 本机 AI Agents (Claude Code / Codex / Hermes) | CLI & `127.0.0.1:24001` | 通过 `dayhelm query/search/sessions` 或 `/api/dayhelm/context` 获取当日实时上下文 |

## 开发规范

- 完成阶段性修改后，按规范提交变更，避免大量变更积累在本地未提交

## 未得到用户明确要求时

- 不运行会真正采集用户数据的常驻进程
- 不推送、不部署
- 不在 `/Applications` 下的任何 app 包里改代码

## 任务看板与需求建卡规范（`vboard`）

本项目已绑定本地异步任务看板（项目标识：`focus-guard`，对应看板空间「DayHelm」）。在需求讨论、体验复盘或缺陷梳理过程中，当用户要求把结论记录为任务卡时，**通过本机 `vboard` CLI 按以下规范直接建卡**（严禁将任何看板 Token 或私密地址写入代码仓库）：

### 建卡命令与默认落列
```bash
vboard add focus-guard \
  --title "<动词开头的简明标题，30字内>" \
  --desc "<按下方模板整理的结构化描述>" \
  --column draft \
  [--size S|M|L]
```
- 多行长描述优先用 `--desc-file <path>` 传入，避免 Shell 转义问题；建卡后务必向用户汇报返回的 `taskId`、落列、档位与卡片链接。
- **默认落入 `draft`（草稿箱）**，不触发后台自动执行；**仅当用户明确要求“直接进 Ready / 立刻排队执行”时**才传 `--column ready`。
- 后台任务按 `Ready` 列顺序在独立 Git Worktree 串行消费，整批清空后自动合并回 `main` 并执行 `./scripts/install-app.sh --launch` 更新 `/Applications/DayHelm.app`。

### 复杂度档位（`--size`，可选）
未传 `--size` 时，批次主控会在领取后自动推测并在验收不通过时自动升档；复杂度明确时建议直接附带：
- **`S`（简单微调 → `DeepSeek V4.1 Flash`）**：文案/排版微调、单配置项、明显单点小修（预估 ≤ 2 文件，不涉核心状态机或文档架构变更）。
- **`M`（标准任务 → `Gemini 4 Hydrogen`）**：常规 Bug 修复、单模块新功能、菜单栏/面板交互调整、需补齐确定性自检（约 3~6 文件）。
- **`L`（复杂核心 → `Gemini 4 Neon`）**：采集引擎/SQLite/HTTP/配额算法/隐私脱敏边界变更、架构重构或需新增 ADR 决策记录的复杂任务。

### 任务卡描述标准模板（确保异步 Agent 无需追问即可闭环）
```markdown
## 背景与目标
- 当前体验痛点 / 需求背景与期望结果

## 改动范围与设计要点
- 涉及模块（`DayHelmCore` / `DayHelmCapture` / `DayHelmApp` / `DayHelmChecks`）与关键交互细节
- 需同步更新的文档（`docs/requirements.md` / `docs/architecture.md` / `docs/privacy.md` / ADR）

## 约束与边界
- 需遵守的四条硬约束、隐私脱敏边界及明确不做的范围

## 验收标准（AC）
- [ ] `DayHelmChecks` 新增的确定性测试断言（无 GUI/无网络/注入时钟）
- [ ] 用户可复现的桌面预览验收步骤
```
