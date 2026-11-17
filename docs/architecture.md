# 技术方案

## 分层

四层，只通过明确定义的接口通信，每层可单独关闭。

```
┌─────────────────────────────────────────────┐
│ 界面层  MenuBarExtra / NSWindow 浮层          │  可关：无 UI 时仍能采集
├─────────────────────────────────────────────┤
│ 判定层  专注块状态机 · 迟滞 · 配额计算         │  纯逻辑，无 I/O，可完全单测
├─────────────────────────────────────────────┤
│ 采集层  NSWorkspace · AX · CGEventSource      │  可关：关闭后判定层退化
├─────────────────────────────────────────────┤
│ 存储层  heartbeat 事件流 · 日切片 JSON         │  可关：内存模式
└─────────────────────────────────────────────┘
```

**判定层不得 import AppKit。** 这是硬约束——它必须能在命令行里用假时钟确定性测试。

## 采集层

### 采集什么

| 数据 | API | 权限 | 频率 |
|---|---|---|---|
| 前台应用 | `NSWorkspace.frontmostApplication` + `didActivateApplicationNotification` | 无 | 事件驱动 |
| 窗口标题 | AX `kAXTitleAttribute`（`kAXFocusedWindowAttribute` → title） | Accessibility | 2s 轮询 |
| 浏览器 URL | AX `AXDocument` on focused window | Accessibility | 2s 轮询 |
| 空闲时长 | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, any)` | 无 | 2s 轮询 |
| 屏幕锁定 | `DistributedNotificationCenter` 的 `com.apple.screenIsLocked` / `Unlocked` | 无 | 事件驱动 |

### 已验证的实现要点（本机实测）

- `AXIsProcessTrusted()` 在 Alma.app 与终端环境下均为 `true`；独立 ad-hoc 签名的二进制也能读到标题
- 标题降级链：`kAXFocusedWindow` → `kAXWindows[0]` → 只记 app 名
- **`AXDocument` 是意外收获**：浏览器当前 URL 直接可读，不用 AppleScript、不用浏览器扩展
- 空闲检测**必须**用 `CGEventType(rawValue: 0xFFFFFFFF)`（整体空闲），**不能**用 `.keyDown`——实测 `.keyDown` 给出 82s 而整体空闲是 7s，只用鼠标时会误判离开
- `0xFFFFFFFF` 不是公开 API，需用 IOKit `HIDIdleTime` 做一致性校验，偏差过大时降级
- **不要在 `main()` 顶部裸调空闲 API**：实测在极短生命周期进程里会偶发阻塞。必须在有 RunLoop 的上下文调用

### 采集层接口

```swift
protocol ActivitySource {
    var events: AsyncStream<ActivitySample> { get }
}

struct ActivitySample {
    let timestamp: Date
    let appName: String
    let bundleId: String?
    let windowTitle: String?     // nil = 读不到，不是空字符串
    let url: String?             // 仅浏览器
    let idleSeconds: TimeInterval
    let screenLocked: Bool
}
```

测试用 `FakeActivitySource` 回放录制好的合成样本，**不碰真实屏幕**。

## 判定层：专注块状态机

核心逻辑，必须可完全确定性测试。

### 状态

```swift
enum FocusState {
    case idle                                  // 未开始
    case focused(since: Date, blockId: UUID)   // 在块内
    case drifting(since: Date, from: UUID)     // 越界，但未判定为中断
    case interrupted(blockId: UUID)            // 已确认中断
}
```

### 状态迁移

| 从 | 事件 | 到 | 条件 |
|---|---|---|---|
| idle | 用户开始 | focused | 已填交付物 + 归属项目 |
| focused | 前台应用离开白名单 | drifting | 立即 |
| drifting | 回到白名单内 | focused | 原块延续，**不重新计时** |
| drifting | 持续越界 > `interruptGracePeriod` | 用户确认后 interrupted | 默认 30s |
| drifted→focused | — | focused | 记录一次 `microReturn`（微切换），计入切换次数但不打断块 |
| interrupted | 用户回位并确认 | focused | 新块，`resumeNote` 显示 |
| focused | 空闲 > `idleThreshold` | idle | 默认 5 min，不记中断（人不在不算打断） |

### 迟滞（必须）

原始信号会抖动。规则：

- 状态迁移需**连续 3 个采样周期**（2s × 3 = 6s）观察到一致信号才生效
- 单次 2s 抖动不得产生任何 UI 或计数
- 依据：用户切换率 50–78 次/小时，按瞬时信号提醒会疯狂误报

### 专注块判定

一个"有效长块"必须同时满足：

- 时长 ≥ `minBlockDuration`（初值 **12 分钟**，不是 25）
- 块内无 `interrupted` 状态
- `microReturn` 次数 ≤ `maxMicroReturns`（初值 5）——允许少量微切，超过则降级为"碎块"

块分级：

| 分级 | 条件 | 呈现 |
|---|---|---|
| `deep` | ≥25 min 且无中断、微切 ≤2 | 主屏高亮 |
| `solid` | ≥12 min 且无中断 | 计入配额 |
| `fragmented` | 有中断或微切超标 | 只记录，不计配额 |

### 配额计算

```
今日投入(项目) = Σ solid 及以上块中归属于该项目的分钟数
缺口 = 配额 - 今日投入
```

- 配额来源：`~/.config/alma/time-audit/focus.json` 的 `primary_focus`
- **只读不写。** 本工具不产生新的配置真源
- 若 `focus.json` 存在但解析失败 → 主屏明确显示"配额不可用"，**不猜默认值**
- 若 `focus.json` 不存在 → 无配额模式，只显示连续块指标

## 存储层

### 格式：heartbeat 事件流（抄 ActivityWatch）

不做"每 2 秒写一条"。同一 `data` 的相邻事件在 `pulsetime`（默认 60s）窗口内**合并**为一条并延长 `duration`。

```json
{
  "schemaVersion": 1,
  "date": "2026-11-17",
  "blocks": [
    {
      "id": "uuid",
      "project": "ecommerce",
      "intent": "上 3 个新品的主图",
      "startedAt": "2026-11-17T09:12:00+08:00",
      "endedAt": null,
      "minutes": 34.5,
      "grade": "deep",
      "interruptions": 1,
      "microReturns": 2,
      "resumeNote": "改到第 2 个品的详情图，停在这",
      "interruptLog": [
        { "at": "2026-11-17T09:31:00+08:00", "app": "WeChat", "seconds": 47 }
      ]
    }
  ],
  "switches": [
    { "at": "2026-11-17T09:31:00+08:00", "from": "ecommerce", "to": "WeChat", "kind": "interrupt" }
  ],
  "totals": {
    "activeMinutes": 186,
    "longestBlockMinutes": 41,
    "blocksSolidOrAbove": 4,
    "switchesPerHour": 22.1
  }
}
```

### 路径

```
~/.config/alma/focus-live/
  today.json          # 秒级更新，原子写入（写临时文件 + rename）
  blocks/YYYY-MM-DD.json  # 日终定稿，只追加
  config.json         # 本工具自己的设置（阈值、白名单），不含配额
```

- `today.json` **不可被 time-audit 直接依赖**（它是热文件，随时变化）。定稿数据在 `blocks/`
- 原子写入：先写 `today.json.tmp` 再 `rename`，避免读到半个 JSON
- 日切：跨零点时把 `today.json` 定稿到 `blocks/<前一天>.json`，再初始化新的

### 与 time-audit 的契约

- `focus-guard` **只产出**，不读 time-audit 的日报
- time-audit 可选地读 `blocks/*.json` 来提升项目归属率（该改动属 time-audit 项目）
- schema 变更必须升 `schemaVersion`，并在 `docs/decisions/` 记录迁移方式

## 界面层

### 菜单栏

`MenuBarExtra(systemImage:)` + `.menuBarExtraStyle(.window)`，`LSUIElement = true`。

已知风险：图标被拖掉后 app 自动终止（官方文档明说）→ 需要 launchd 保活。

主屏四个数：
```
当前块   12:34
今日最长 41 分钟
今日切换 17 次
每小时   22.1 次
---
电商做深  缺口 56 分钟
```

### 切换浮层

```swift
window.level = .screenSaver                     // rawValue 1000
window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                             .stationary, .ignoresCycle]
window.styleMask = [.borderless]
window.canBecomeKey = true                      // .borderless 默认 false，必须手动设
```

内容（三样，不多不少）：

```
你要产出的是：
「上 3 个新品的主图」

[ 继续原任务 ]        [ 记录中断并离开 ]

离开将在 15 秒后可用
```

### 能力边界（必须对用户诚实）

浮层**做不到**的事，要在文档和 UI 里说明，不做虚假承诺：

- 盖不住菜单栏（WindowServer 独立合成通道，layer 排序绕不过）
- 挡不住 Cmd+Tab（浮层仍在，但用户已经切走了）
- 挡不住三指切 Space / Mission Control
- 挡不住 Cmd+Opt+Esc 强制退出

因此设计上**不宣称"锁定"**，只宣称"摩擦 + 记录"。

### 提醒不用通知

`UNUserNotificationCenter` 无法做到"必须交互才消失"（`alertStyle` 是用户侧设置，只能读）。
所有需要强交互的提醒一律用自己的 NSWindow。

`interruptionLevel = .timeSensitive` 可用于**不需要强制交互**的轻提示（可穿透专注模式）。

## 依赖

- Swift / SwiftUI，SwiftPM
- 无第三方依赖（目标）。任何引入需 ADR
- 最低 macOS 版本：待定，倾向 `.v14`（与 local-screen-time-journal 一致）

## 打包

个人自用，**不需要签名与公证**。

- `codesign --force --deep --sign - App.app`（ad-hoc）即可
- 风险：ad-hoc 重签可能触发 TCC 重置 → 开发期用**固定路径**原地替换二进制
- 更稳的做法：申请**免费的 Apple Development 证书**（不需付费账号），签名身份稳定，TCC 授权稳定得多
- 参考 `~/dev/code/local-screen-time-journal/prototypes/stage0/build-app.sh` 的打包脚本

## 未验证 / 需要实测的部分

| 项 | 状态 |
|---|---|
| macOS 26 是否进一步限制窗口标题读取 | 本机宽松，不可外推 |
| Stage Manager 开启时浮层行为 | 本机 Stage Manager 关闭，未测 |
| ad-hoc 重签是否触发 TCC 重置 | 未敢动现有授权，未测 |
| 多显示器下 `.canJoinAllSpaces` 的实际覆盖范围 | 未测 |
| `0xFFFFFFFF` 空闲 API 与 `HIDIdleTime` 的偏差范围 | 未测 |
