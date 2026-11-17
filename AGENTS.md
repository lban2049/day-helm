# 专注守护 · 开发约定

一个 macOS 单人自用工具。目标不是"记录时间"，是**减少任务切换、保证重要任务每日连续投入**。
完整背景见 `docs/`，本文件只写**约束**。

## 这个项目要解决什么（写代码前先读）

用户实测基线（2026-11 月，来自 `~/.config/alma/time-audit/`）：

- session 中位时长 **4.1 分钟**；244 个 session 里只有 25 个 ≥10 分钟
- 活跃日切换 **50–78 次/小时**
- 切换发生在多个**正当工作**之间（`alma` / `ecommerce` / `hermes` / `infra-billing`）

两条由此推出的硬约束，任何设计不得违反：

1. **不设 25 分钟番茄钟作为默认目标。** 基线是 4 分钟，第一个可达成目标是"最长连续块 ≥12 分钟"。刚性 25/5 已被实证证明无生产率优势且疲劳更快上升（见 `docs/research/evidence.md`）。
2. **不做"网站/App 黑名单"式的分心拦截。** 用户的切换不是堕落，是在两个正事之间横跳，黑名单对这种情形 100% 放行。核心机制必须是**白名单 + 切换瞬间的摩擦**。

## 文档为主（Documentation-First）

**先改文档，再改代码。** 顺序不可颠倒：

| 要动的东西 | 先更新 |
|---|---|
| 产品范围、验收目标 | `docs/requirements.md` |
| 模块划分、数据流、存储格式 | `docs/architecture.md` |
| 采集范围、权限、数据留存与删除 | `docs/privacy.md` |
| 阶段划分与验证顺序 | `docs/roadmap.md` |
| 任何技术选型的取舍 | 新增 `docs/decisions/NNN-<slug>.md` |

- 文档描述**当前真实状态**，不写"打算以后做"。未实现的东西放在 `docs/roadmap.md`。
- 决策记录（ADR）格式：背景 / 候选方案 / 选择 / 理由 / 推翻条件。**必须写"推翻条件"**——不写就无法在未来判断该不该改。
- 代码里的关键常量（阈值、迟滞窗口、配额）必须在文档里有出处和理由，不能是拍脑袋的魔法数字。

## 测试先行（Test-First）

**没有失败的测试，就不写实现。**

- 顺序：写测试 → 跑，确认它**因为正确的原因失败** → 写最小实现 → 跑通 → 再重构。
- 测试必须能在**无 GUI、无网络、无真实用户数据**的条件下跑通。CI 友好。
- 时间相关逻辑一律**注入时钟**，不直接调 `Date()`。专注块引擎、迟滞、配额全部可确定性测试。
- 每个测试只断言一件事。断言失败信息要能直接指出哪条不变量破了。
- 修 bug 必须**先写复现测试**，确认它在旧代码上失败，再修。

### 测试组织（沿用本机既有习惯）

用 SwiftPM executable checks，不用 XCTest —— 便于在受限环境直接跑：

```
prototypes/<stage>/Package.swift        # library target + *Checks executable target
prototypes/<stage>/Sources/<Core>/      # 纯逻辑，无 UI、无 I/O
prototypes/<stage>/Sources/<Core>Checks # 断言，失败 exit 1
```

约定：
- 纯逻辑（专注块引擎、迟滞判定、配额计算、heartbeat 合并）放在 library target，**不 import AppKit**
- 采集层（AX / NSWorkspace / CGEventSource）单独 target，用协议隔离，测试里替换成假实现
- `swift test` 与 checks executable 两种都要能跑；checks 是可交付给用户的快速自检

## 工程约定

- **先用原型验证交互，再写产品。** 每个交互设计（尤其"切走时弹浮层"）必须先在 `prototypes/` 里让人真用一天。**烦人的交互宁可砍掉，不要上线后再发现。**
- 优先 Apple 原生框架。引入第三方依赖必须在 ADR 里记录理由、许可证、维护活跃度。
- 分层：采集 / 判定 / 存储 / 界面四层，互相之间只通过明确定义的接口通信，每层可单独关闭。
- 不做跨设备同步、不做云、不做账号。单人本机，这是**范围限制不是技术债**。
- 不做游戏化（种树、宠物、装饰）。对"两个正事之间切换"无效。
- 不生成"生产力评分"。用户已有的 `time-audit` 已经在做评分，重复且冲突。

## 技术事实（已验证，不要重新踩）

以下均已在本机 macOS 26.6.2 实测确认，写代码时直接采信：

| 结论 | 含义 |
|---|---|
| `FamilyControls` / `ManagedSettings` / `DeviceActivity` 在 macOS 上**每个有用符号都标 `@available(macOS, unavailable)`** | Screen Time API 路线彻底不可行。写 `AuthorizationCenter.shared` 直接编译失败。**不要尝试，不要申请 entitlement** |
| 无 API 可以拦截 Cmd+Tab / 点 Dock / Spotlight | 做不了"阻止切换"，只能做"切换后的摩擦 + 记录"。AX 能写窗口位置但**发不出按键** |
| `NSWindow` level=`.screenSaver`(1000) + `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` + `.borderless` + **手动 `canBecomeKey = true`** | 能盖住所有普通 app 窗口。**盖不住菜单栏**，挡不住 Cmd+Tab / 三指切 Space / Mission Control |
| `NSWorkspace.frontmostApplication`、`CGEventSource.secondsSinceLastEventType` | 均**无需权限** |
| AX `kAXTitleAttribute` 读窗口标题、**AX `AXDocument` 读浏览器当前 URL** | 需要 Accessibility。实测都拿到了（`Hermes - Google Chrome - 晓亮` / `http://127.0.0.1:9120/#/...`） |
| 空闲检测**不能用 `.keyDown`** | 只用鼠标时会误判离开。用 `CGEventType(rawValue: 0xFFFFFFFF)` 或 IOKit `HIDIdleTime` 兜底 |
| `UNUserNotificationCenter` 必须有真实 `.app` bundle，裸二进制崩溃；且**通知无法做到"必须交互才消失"** | 强制交互的提醒必须用自己的 NSWindow，不用通知 |
| `MenuBarExtra` 的图标被用户拖掉后 **app 会自动终止** | 需要 launchd 兜底 |
| `~/.config/alma/time-audit/daily/*.json` 是**次日 08:00** 才生成 | "今日已投入"必须自己实时算，**不能读日报** |

## 数据与隐私边界

- 采集范围：**前台应用名、窗口标题、浏览器当前 URL、屏幕锁定状态、空闲时长**。就这些。
- **不采**：音频、键盘输入内容、剪贴板、鼠标轨迹。不得通过按键监听推断用户输入。
- 所有数据留在本机 `~/.config/alma/focus-live/`。不加遥测、崩溃上报、云同步。
- 标题和 URL 按高敏感数据处理。写入前过滤密码管理器、银行、私人聊天类应用（名单在 `docs/privacy.md`）。
- 真实窗口标题、URL、截图、数据库**不得提交到 Git**。测试一律用合成数据。
- 提供一条命令彻底删除所有采集数据，并在文档里写明。

## 与既有系统的关系（重要）

本机已有两个相关系统，**不要重复造**：

| 系统 | 位置 | 关系 |
|---|---|---|
| `alma-time-audit` | `~/.config/alma/scripts/`、`~/dev/code/alma-time-audit/` | 产出日/周报，做事后审计与评分。**本工具不替代它** |
| `local-screen-time-journal` | `~/dev/code/local-screen-time-journal/` | 截图+OCR 的时间线记录器，阶段 0。**本工具不重复截图与 OCR** |

**单向依赖，不许反向**：

```
focus-guard  ──产出──▶  ~/.config/alma/focus-live/*.json  ──读取──▶  time-audit（次日交叉验证）
```

- 本工具**不读** time-audit 的日报，不读它的评分。
- time-audit 可以在未来**读**本工具的实时数据来提升项目归属率，但不得反向依赖。
- 项目清单、主攻方向、配额目标**唯一来源是 `~/.config/alma/time-audit/focus.json`**，本工具只读不写，不另外维护一份。

## 提交前自检

每次改动前问这五个问题，答不上来就别提交：

1. 文档更新了吗？代码里的阈值有文档出处吗？
2. 有失败的测试吗？还是先写了实现再补测试？
3. 这次改动碰了采集范围或隐私边界吗？`docs/privacy.md` 同步了吗？
4. 和 time-audit / local-screen-time-journal 的边界有被越过吗？
5. 这个交互我**自己真的用了一天**吗，还是只是"看起来合理"？

## 未得到用户明确要求时

- 不运行会真正采集用户数据的常驻进程
- 不修改 `~/.config/alma/time-audit/` 下的任何既有配置
- 不提交、不推送、不部署
- 不在 `/Applications` 下的任何 app 包里改代码（破坏签名，且会被更新覆盖）
