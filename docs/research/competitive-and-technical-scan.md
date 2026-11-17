# 专注守护 App 调研报告

调研日期：2026-11-17
目的：为一款「防止频繁任务切换、保证重要任务每日投入」的自建工具做参考与选型

---

## 一、先看你的真实数据

从 `~/.config/alma/time-audit/daily/*.json` 统计（只算有输入的活跃日）：

| 日期 | 活跃分钟 | 切换次数 | 次/小时 | 估算损耗 | <3min碎片 |
|---|---:|---:|---:|---:|---:|
| 2026-11-04 | 352 | 309 | 52.7 | 72m | 26 |
| 2026-11-05 | 510 | 494 | 58.2 | 122m | 25 |
| 2026-11-06 | 335 | 204 | 36.5 | 35m | 10 |
| 2026-11-09 | 265 | 257 | 58.1 | 63m | 10 |
| 2026-11-10 | 300 | 251 | 50.1 | 57m | 23 |
| 2026-11-11 | 318 | 412 | 77.7 | 80m | 21 |
| 2026-11-12 | 305 | 366 | 72.0 | 76m | 17 |
| 2026-11-13 | 74 | 42 | 33.9 | 7m | 5 |

全部 session（244 个）：

- **中位时长 4.1 分钟**
- <1 分钟：19 个；<3 分钟：79 个；**≥10 分钟：只有 25 个**

### 这个数字意味着什么

你不是"偶尔分心"，是**基本没有形成过连续工作块**。244 个 session 里只有 25 个超过 10 分钟。

关键推论有两条：

1. **25 分钟番茄钟对你是错的起点。** 你的现实基线是 4 分钟，直接上 25 分钟只会制造连续失败感。第一个目标应该是「最长连续块从 4 分钟推到 12 分钟」。
2. **你的切换大多不是"刷手机"式的堕落，是"在两个正事之间横跳"。** 从日报看，切换发生在 `alma` / `ecommerce` / `hermes` / `infra-billing` 之间——每一个都算正当工作。这就是为什么市面上所有 blocker（黑名单拦网站/App）对你几乎无效：你去切「另一个正事」时，它们全部放行。

> 这两点是整个方案的定位基准。任何参考应用如果只解决"拦住娱乐网站"，都不该抄。

---

## 二、参考应用对照：分四类，只有两类对你有用

### A. 纯番茄钟（全部做烂了，功能可抄、思路不要抄）

| 产品 | 定位 | 核心机制 | 价格 | 致命缺陷 |
|---|---|---|---|---|
| [Flow](https://flow.app/) | 极简漂亮的番茄钟，菜单栏常驻 | 纯间隔计时；Pro 有 Commitment Mode（不可停止/跳过） | 官网 $1.49/月，App Store 实价 $2.99/月、$39.99 终身 | **Commitment Mode 强杀 App 即解除**（用户实测评论）。锁是表演 |
| [Session](https://stayinsession.com/) | 带 intention 与分析的番茄钟 | 开始前必须写 intention；intention 出现在通知/拦截页/widget | $4.99/月，$39.99/年 | 无会话锁；官方自认 iOS↔Mac 同步不可靠；窗口太大反成干扰源 |
| [Be Focused](https://apps.apple.com/us/app/be-focused-pomodoro-timer/id973134470?mt=12) | 老牌任务+间隔 | 仅计时 + 任务列表，无拦截无锁定 | Pro $19.99 买断 | 差评第一是跨设备同步；菜单栏图标会被刘海挡住 |
| [Llama Life](https://llamalife.co/) | 「一次只做一件事」的清单执行器 | 每个任务一个倒计时，只显示当前这一个；**长计时内每 N 分钟一声 chime 把注意力拉回** | $6/月，$39/年 | 无拦截能力，更新慢 |
| [Tide](https://apps.apple.com/us/app/tide-sleep-focus-meditation/id1077776989) | 白噪音+冥想+番茄钟打包 | 无拦截无防切换 | 订阅（App 内） | 纯氛围，不解决任何结构问题 |
| Focus Booster | **已停运**（官网为讣告） | — | — | — |
| Pomodoro One | 域名不解析、App Store 无记录，**疑似停运** | — | — | — |
| Forest / Flora | 种树，离开就枯死 | 手机端为主；**都没有原生 macOS App** | 买断+IAP | 对"两个正事之间切换"完全无效——你的树不会因为你回邮件而死 |

**这一类唯一值得抄的**：Session 的「开始前写 intention，并让这句话反复出现在你眼前」；Llama Life 的「长计时内周期性 chime」（走神只损失 N 分钟，不是整段报废）。

### B. 真正对抗切换的（← 主要参考源）

| 产品 | 机制 | 硬证据 | 价格 |
|---|---|---|---|
| **[one sec](https://one-sec.app/)** | 打开目标 App/网站前**强制插入摩擦**：呼吸、旋转、打随机文本；延迟随次数递增 | **PNAS 2023 田野实验（280人/6周）：36% 的打开被自己取消，实际打开减少 57%。后续 N=500 预注册实验拆解：有效的是「提供取消选项」和「时间延迟」，「说教文案」无效** | 免费版 1 个 App；Pro €14.99/年 |
| **[Focus (heyfocus)](https://heyfocus.com/)** | **Locked Mode 是全市场最硬的锁**：官方明写「即使你重启电脑或试图关掉 App，也不会让你这么做」；锁定期仍可拖网址进黑名单 | 机制层面已验证可行（SelfControl 同路线） | $49 买断 / $129 终身 |
| **[Cold Turkey Micromanager](https://getcoldturkey.com/micromanager/)** | **白名单锁定**：只允许你选的 App，其余「打开即被最小化」，进行中无法回退 | 全市场唯一直接拦「切换动作」本身而非「诱惑清单」 | 买断（价格页动态渲染，未核实） |
| **[SelfControl](https://selfcontrolapp.com/)** | 改 `/etc/hosts` + 特权 helper + launchd | 开源 4.4k★；「重启电脑或删除 App 也无法访问」 | 免费 |
| **[ScreenZen](https://www.screenzen.co/)** | 打开前延迟 + 延迟递增 + 限次；完全免费 | 4.86★ / 5.4万评分 | 免费 |
| **[Opal](https://www.opal.so/mac)** | Focus Rules + Hard Mode | Hard Mode 不可强杀（单一用户评论佐证，未核实） | $8.29/月起，终身 $399 |
| **[Sunsama](https://www.sunsama.com/)** | **不做拦截，用结构**：晨间规划→拖进日历 timebox→Focus Mode；**下个日程前 5 分钟弹「Starts soon. Shift focus?」把切换变成显式决定** | — | $17/月，无免费版 |
| **[Focusmate](https://www.focusmate.com/)** | 真人视频共处，开场互报目标，全程开摄像头 | body doubling，重度拖延者自述有效 | 免费 3 次/周；$8/月起 |
| [Contadino](https://apps.apple.com/us/app/contadino/id1672167389) | **把「中断」本身当指标计数**；让你写下"我停在哪" | 作者 HN 自述，理念最接近你 | 小额买断 |
| [HazeOver](https://hazeover.com/) | 非活动窗口自动变暗，不拦截 | 视觉聚焦 | 买断 |
| [Forfeit](https://forfeit.app/) / [Beeminder](https://www.beeminder.com/) | 金钱赌注，AI 审批解锁 | 承诺装置文献支持 | 扣钱 |

### C. 开源 / 可抄架构

| 项目 | 语言 | 可抄的点 |
|---|---|---|
| **[ActivityWatch](https://github.com/ActivityWatch/activitywatch)** 19.6k★ | Python + TS | **heartbeat + pulsetime 合并**：同 data 且在 pulsetime 窗口内的相邻事件合并为一条并延长 duration。解决"每10秒写一条"的存储爆炸。另外 **AFK 是独立事件流，不是窗口事件的属性**——正好治你 presence 判定失效的问题 |
| **[TomatoBar](https://github.com/ivoronin/TomatoBar)** 3.6k★ | **Swift** | 菜单栏番茄钟的完整原生实现，最小骨架起点 |
| **[Dayflow](https://github.com/JerryZLiu/Dayflow)** 7.4k★ | **Swift** | 截图+LLM 的自动工作日志，和你现有 recorder 同构；想做原生迁移时的架构参照 |
| **[Timewarrior](https://github.com/GothenburgBitFactory/timewarrior)** | C++ | 区间代数（union/intersect/subtract），处理重叠专注块的教科书 |
| **[Hammerspoon](https://github.com/Hammerspoon/hammerspoon)** | Lua | `hs.application.watcher` + `hs.window.filter`，**20 行就能做出「切走→遮罩」原型**。强烈建议先用它验证交互再写 Swift |
| [Traggo](https://github.com/traggo/traggo) | Go | **tag 而非项目树**——比层级灵活，适合你"同一件事跨项目"的痛点 |
| Super Productivity 23.7k★ | TS | 时间盒与任务绑定在一条记录 |

### D. 学术证据（决定设计取舍的部分）

| 结论 | 出处 |
|---|---|
| 367 个自控工具里，**真正用"延迟"机制的只有 2 个**；白名单只有 22 个（黑名单 101 个） | Lyngs et al., CHI 2019, [arXiv:1902.00157](https://arxiv.org/abs/1902.00157) |
| 摩擦有效顺序：**提供取消选项 > 时间延迟 >> 说教文案（无效）**；实际打开 -57% | one sec, PNAS 2023, [10.1073/pnas.2213114120](https://doi.org/10.1073/pnas.2213114120) |
| **自我打断比外部打断更具破坏性** | CHB 2016, [10.1016/j.chb.2016.06.037](https://doi.org/10.1016/j.chb.2016.06.037) |
| 多任务与绩效呈**倒 U 型**——超过最优点后切换越多绩效越差 | NBER 2007, [10.3386/w13172](https://doi.org/10.3386/w13172) |
| **刚性 25/5 没有实证优势**：Pomodoro / Flowtime / 自主休息三组在生产率、完成量、flow 上无差异，且 Pomodoro 组疲劳上升更快 | Behavioral Sciences 2025, [10.3390/bs15070861](https://doi.org/10.3390/bs15070861) |
| 物理指示灯+自动可打断性判定，使被打断次数 **-46%** | FlowLight, CHI 2017, [10.1145/3025453.3025662](https://doi.org/10.1145/3025453.3025662) |

> 最后一条对你是好消息也是坏消息：**你不需要做番茄钟**。刚性 25/5 有副作用。你要的是"连续块"而不是"番茄数"。

---

## 三、值得抄的 9 个设计模式（按对你的价值排序）

### 1. 把「切换次数 / 最长连续块」当一等指标，而不是分钟数
- **机制**：采集前台 App + 窗口标题（10s 粒度），每次切换归因到当前会话。输出四个数：每小时切换、最长连续块、**被打断后回到原任务的延迟（中位数）**、每次切换前的停留时长。
- **证据**：你的基线就是 50–78 次/小时、中位 4.1 分钟。这个指标你能立刻看到变化，而"今天专注了 3 小时"是假的。
- **稀缺性**：Lyngs 的 367 个工具里几乎无人把中断计数做成核心。这是你的护城河——**已有审计系统的人，别人抄不走**。
- **落地**：定义"有效长块" = ≥12 分钟且无越界切换。

### 2. 入口摩擦，而不是封锁（friction, not blocking）
- **机制**：在「想切」到「真切」之间插 5–15 秒 + 一个明确的二选一（继续 / 离开）。
- **证据**：PNAS 2023，实际打开 -57%。**关键是"提供取消选项"，不是文案。**
- **纪律**：文案不要写"你确定要走神吗"。写成：`你要产出的是「___」` + 两个按钮 `继续原任务` / `记录中断并离开（15 秒后可用）`。
- **落点**：摩擦必须发生在**切换的瞬间**（Cmd+Tab、点 Dock、新窗口），不是会话开始时。

### 3. 真·扛强杀的会话锁
- **机制**：状态持久化到磁盘 + launchd 开机恢复 + 结束时间戳校验；退出路径只有一条：30 秒倒计时 + 手打一句「我现在放弃，因为___」。
- **验收标准写死**：`kill -9` → 重启 App → 重启系统，锁仍在。否则视为未实现。
- **反例**：Flow 的 Commitment Mode 就是反面教材，强杀即解除。

### 4. 意图声明 + 在切换瞬间重现意图
- 开始前必须填：**交付物（一句话）+ 完成后可见的产物**。
- 检测到切走意图时，把它推回眼前。注意 #2 的纪律：**意图必须具体到"下一步做什么"，否则退化成说教，而说教已被证明无效**。

### 5. 白名单式单窗口模式（拦住"切到另一个正事"）
- 会话内只允许 1–3 个 App 前台，其余被**隐藏/最小化**（不 kill，避免丢工作）。
- 每次越界：记录 + 3 秒确认，不阻断但留痕。
- 必须配「临时放行」通道（如 15 分钟额度），否则会被自己的正当需求打爆。
- 这是唯一直接命中你痛点（两个正事之间横跳）的机制。

### 6. 中断时的「现场封存」+ 一键开放环停车场
- 任何中断 → 3 秒内可选：一句话记下「我停在哪 / 下一步」。
- 全局热键：一句话存进"未处理"列表，**不切走**，会话结束后统一处理。
- 恢复时：任务顶部直接显示上次的「我停在哪」。
- 这是 attention residue 的正解——切换的真实成本是"回不去"，不是"少干了 5 分钟"。

### 7. 重要任务的当日配额 + 只显示缺口
- 每天为 1–3 个重要任务设硬配额（例：`ecommerce ≥ 90 分钟`）。
- 主屏只显示**缺口**，不显示"已完成 N 个 session"。
- 时长不预设 25 分钟：默认正计时，到 12/25/50 分钟给**可选**休息提示。

### 8. 把专注状态对外可见
- Slack/DND 自动状态、阶段背景音、屏幕指示。
- 证据：FlowLight, CHI 2017，打断 -46%。
- 仅当你的切换有一部分来自"别人来找"时才值得做。

### 9. 打断的事前预告，而非事后惩罚
- Sunsama 的 "Starts soon. Shift focus?" 是全市场最好的设计——**把切换从自动行为变成需要点一下的决定**。

---

## 四、不要做的部分（全部已被做烂）

| 功能 | 理由 |
|---|---|
| 基础番茄钟（开始/暂停/跳过/自定义时长/长休周期） | 人人都有，且刚性 25/5 无实证优势 |
| 日/周/月统计图表 + streak | 你已有 time-audit，重复造 |
| 结束音效 / 音效选择 / 音量 / 励志语 | Flow 已做到天花板 |
| App / 网站黑名单、关键词、通配符 | 对"两个正事之间切换"完全无效 |
| 定时排程 | 同上 |
| 白噪音 / lo-fi / 双耳节拍 | 与目标无关 |
| **跨设备同步** | 所有产品差评第一大来源（Session 官方自认同步不可靠、Be Focused 差评第一是同步）。**单机自建直接不做，风险归零** |
| 日历集成 / 自动写日历 | 所有产品的 bug 热点 |
| 内置任务管理器 | Session 的边界值得照抄："To Do 不是替代你的待办 App，只做今天" |
| 游戏化皮肤 / 房间 / 装饰 | Forest 那套对你不适用 |

---

## 五、macOS 技术可行性（本机 macOS 26.6.2 实测）

### 三个"看起来能做但其实做不到"

| 你以为 | 实际 |
|---|---|
| 用 Screen Time API（FamilyControls/ManagedSettings）做应用屏蔽 | **macOS 上对第三方完全不可用**。SDK 里每个有用符号都标了 `@available(macOS, unavailable)`，写 `AuthorizationCenter.shared` 直接编译失败。`com.apple.developer.family-controls` entitlement 在 macOS 上无对象可授予。**个人自用也申请不到，因为根本没有可授权的 API** |
| 在别的 app 里按 Cmd+Tab 时"弹回"打断 | AX 只能**写窗口位置/大小**（实测 `AXPosition` 可写），**发不出按键**。要发按键得 CGEventPost，那是"注入"不是"拦截"，会产生闪烁、和你的截图 OCR 打架 |
| 用一个不可关闭的窗口"锁死"屏幕 | 全屏遮罩能盖住所有 app 窗口，但**盖不住菜单栏**（WindowServer 独立合成通道），也**挡不住 Cmd+Tab / 三指切 Space / Mission Control** |

### 已验证可行的能力

| 能力 | 方案 | 权限 |
|---|---|---|
| 前台 App | `NSWorkspace.shared.frontmostApplication` | **无** |
| 全局空闲 | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)` | **无** |
| 窗口标题 | `CGWindowListCopyWindowInfo`（实测拿到 44/51 个非空标题，含完整文件路径）**或** AX `AXTitle`/`AXDocument` | Screen Recording **或** Accessibility |
| **浏览器当前 URL** | AX `AXDocument` 属性直接给出（实测 `https://memo.lban2049.xyz/`） | Accessibility |
| 全屏遮罩 | `NSWindow` level=`.screenSaver`(1000)，`collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`，`.borderless` + **手动 `canBecomeKey = true`** | 无 |
| 菜单栏常驻 | `MenuBarExtra` + `LSUIElement=true` | 无 |

### 六个坑

1. **窗口标题会静默返回空，不报错。** 你的 recorder 已经踩了：`windowTitle` 0/1642 全空。这几乎确定是 Screen Recording 权限缺失。**修这个的 ROI 高于写新 app**——有了标题，你现有 53% 的项目归属率会显著提升，而新 app 也复用同一套归因。
2. **空闲检测别用 `.keyDown`。** 实测 `.keyDown` 给出 82 秒而整体空闲是 7 秒——只用鼠标时会误判离开。用 `CGEventType(rawValue: 0xFFFFFFFF)`（非公开但广泛使用）或 IOKit `HIDIdleTime` 兜底。
3. **`UNUserNotificationCenter` 必须有真实 .app bundle**，裸二进制直接崩溃。所以必须打包成 .app。而且**macOS 通知无法做到"必须交互才消失"**——想要强制交互就用你自己的 NSWindow，别用通知系统。
4. **纯菜单栏 app 的 `MenuBarExtra` 被用户拖掉后 App 会自动终止**（文档明说）。要有 launchd 兜底。
5. **ad-hoc 重签可能触发 TCC 重置。** 开发期用固定路径原地替换二进制；想要稳定就申请免费的 Apple Development 证书（不用付费账号）。
6. **日报是次日 08:00 才生成的**（实测 `generated_at: 2026-11-17T08:00`，`date: 2026-11-16`）。所以"今日已投入 X 分钟"必须自己实时算，**不能读日报**。

### 你的 presence 判定需要重建

实测 `2026-11-16.json`：122 个 session 里 **119 个被判为 `no_input`（离开）**，只有 3 个 anchored。说明纯空闲计时在这台机器上基本失效——你大量时间在阅读、思考、看录屏。

建议组合判据（三取二 + 迟滞）：

```
在场 = (空闲 < 60s)
    OR (前台 app 未变 AND 窗口标题未变 AND 有窗口)
    OR (屏幕未锁 AND 距上次 session 边界 < 5min)
并且：连续 3 个采样周期一致才切换状态
```

迟滞是必须的——50–78 次/小时意味着按瞬时信号提醒会疯狂误报。

---

## 六、产品建议：如果是我来做

### 定位

> **不是番茄钟，是「连续块守护器」。**
> 一句话：它不关心你今天坐了几小时，只关心你有几个 ≥12 分钟没被打断的连续块，以及重要任务的当日配额还差多少。

### MVP（三件套，形成闭环：锁住 → 记录 → 归因）

**P0-1 连续块引擎 + 切换归因看板**
- 采前台 App / 窗口标题 / URL，10s 粒度，heartbeat 合并落盘
- 主屏只显示四个数：当前块已持续多久、今日最长块、今日切换次数、每小时切换
- 每个切换打 `interruption` 标记并归因到当次会话

**P0-2 会话锁（扛强杀）**
- 磁盘持久化 + launchd 恢复
- 退出只有一条路：30 秒倒计时 + 手打放弃理由

**P0-3 切换瞬间的 30 秒冷却浮层**
- 全屏 NSWindow（.screenSaver 层）
- 内容：`你要产出的是「X」` + `继续原任务` / `记录中断并离开`
- 不写说教文案

### P1

- 白名单单窗口模式（允许 1–3 个 App，其余最小化，越界记 3 秒确认）
- 重要任务当日配额 + 缺口显示（默认正计时，12/25/50 分钟给可选休息提示）
- 中断时"我停在哪"现场封存 + 全局热键收杂念

### 数据模型（照 ActivityWatch 抄）

```
bucket: focus.block
event: {
  timestamp, duration,
  data: { project, kind: focused|drifted|broken,
          interrupted_by, resume_note, quota_id }
}
bucket: afk.status     ← 独立事件流，不混进窗口事件
```

落盘：`~/.config/alma/focus-live/today.json`（秒级更新，和 time-audit 同风格）
次日 time-audit 读它做交叉验证——**单向依赖，不要反向**。

### 技术栈建议

1. **先用 Hammerspoon 写 20 行原型验证交互**。`hs.application.watcher` + `hs.window.filter` + 一个遮罩，一天能看到「切走→弹层」到底烦不烦。这一步能省掉一周的 Swift 白写。
2. 原型验证通过后，Swift + SwiftUI，`MenuBarExtra` 做壳，抄 TomatoBar 的骨架。
3. 不要碰 Screen Time API。不要做网站拦截（你的问题不是网站）。

---

## 七、如果只能做三个

1. **连续块 + 切换归因**——给你别人没有的度量
2. **扛强杀的会话锁**——保证会话真的成立
3. **切换瞬间的 30 秒冷却浮层**——把自动切换变成需要决定的切换

合起来：锁住 → 记录 → 归因 → 下次更难切。

---

## 附：证据与未核实清单

**未核实项**
- Cold Turkey Blocker Pro 的一次性价格（Paddle 动态渲染）
- Flow 的 Pro 价格口径冲突（官网 $1.49/月 vs App Store $2.99/月）
- Opal Hard Mode 是否真的不可强杀（仅单一用户评论佐证）
- Llama Life 是否为原生 macOS App（技术特征像 PWA）
- macOS 26 是否进一步限制窗口标题读取（本机宽松，不可外推）
- Stage Manager 开启时遮罩的行为（本机 Stage Manager 关闭）
- ad-hoc 重签是否触发 TCC 重置（未敢动现有授权）
- Alma 是否有实时活动 API（`api-spec.md` 无相关端点）
- "打断后需 23 分钟恢复"——广泛流传但未在原始文献核实，**不要在产品文案里引用**

**已核实的硬证据**见第二节表格与链接。
