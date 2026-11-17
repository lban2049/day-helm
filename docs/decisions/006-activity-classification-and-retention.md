# 006 · 活动分类、截图触发与留存降采样

## 背景

独立原生采集器落地后，真实运行暴露出七类问题，直接影响 `activity.sqlite` 的可检索性与可信度：

1. **`browser_visit` 误判**：只要 AX 的 `AXDocument` 返回了 URL 就记成 `browser_visit`，于是 Preview 打开 `file:///.../Earnings Call.pdf`、TextEdit 打开本地文档、Xcode 打开工程文件都被误标为浏览器访问。
2. **标题抖动放大事件量**：`windowTitle` 里带未读数 `(3)`、倒计时 `14:52`、进度 `87%`、加载省略号等易变片段。2s 轮询把每次抖动都当成一次变化，产生大量无意义 `app_focus` 事件（高峰可达 1800 条/小时）。
3. **idle 会话与截图**：长空闲时既有会话不关闭，`duration_ms` 与「当前会话」状态悬空；同时 120s 心跳截图和 `app_focus` 截图仍在人离开时继续落盘。
4. **截图触发单一**：只有 `app_focus` / `visual_change` / `heartbeat`，缺少「点击后」「打字停下来后」这两个最有信息量的时刻；且 `app_focus` 绕过直方图去重，画面没变也会存。
5. **凭据泄漏风险**：事件 `data`、快照 `window_title`、OCR 文本可能包含可见的 API Key、JWT、`password=...`、带 `token=` 的 URL；现有 `sanitizeURL` 只清洗了事件主 URL 字段。
6. **结构化标签为空**：`activity_sessions` 的 `topics` / `entities` / `highlights` 列从未被填充，Agent 检索只能靠标题字符串。
7. **旧快照一刀切删除**：超过留存天数的整天目录直接删除，无法保留低成本缩略图证据。

## 候选方案

- **方案 A：只做表面修补**（改 `browser_visit` 判断、加长心跳）。问题：标题抖动与 idle 截图仍会持续污染数据，凭据风险未解，Agent 仍拿不到结构化标签。
- **方案 B：抽离纯逻辑分类器 + 统一触发与留存策略**（本 ADR 选择）。把「事件种类判定 / 标题归一化 / 密钥脱敏 / 结构化标签」放进 `DayHelmCore` 纯函数，把「触发去重 / 降采样」放进 `DayHelmCapture`，全部可注入时钟、可确定性测试。

## 选择

选择 **方案 B**，具体规则如下。

### 1. 事件分类（`ActivityClassifier`，纯逻辑）

- `browser_visit` 必须同时满足：URL scheme 为 `http`/`https`，且应用是已知浏览器（bundle 前缀或应用名关键词命中）。
- 其余带 `AXDocument` 的应用（Preview / TextEdit / Xcode / Finder 的 `file://`）一律记 `app_focus`。
- `redacted == true` 时永远记 `app_focus`，且不写标题/URL。
- `click` / `keypress` / `typing_pause` 是输入类事件，不参与此判定。
- 浏览器内 URL 未变化、只有标题变化时记 `app_focus`，避免把标题抖动伪装成「新页面访问」。

### 2. 标题抖动归一化（`ActivityTextNormalizer`）

比较用「归一化键」，落盘仍保留原始标题：

- 折叠空白、统一大小写；
- 去掉括号/方括号内的纯计数：`(3)`、`[12+]`；
- 去掉时间 `14:52`、百分比 `87%`、裸数字（保留与字母紧邻的版本号片段）；
- 去掉尾部省略号 `…` / `...`；
- 归一化后相同即视为「同一画面」，不产生新事件。

另外设最小变化间隔（`minTitleChangeInterval = 5s`）：归一化键变化但距上次落盘不足 5s 时丢弃；**应用切换不受此限**，保证快速 Cmd+Tab 仍能记录。

### 3. idle 会话与截图

- 空闲达到 `idleThresholdSeconds`（默认 300s）或锁屏：关闭当前打开会话，`ended_at` 取最后一条活动时间（不把空闲时长计入 `duration_ms`）。
- 恢复活动时自然开启新会话（沿用 120s 会话间隔规则）。
- 所有截图触发在人离开时直接返回：`sample.idleSeconds >= idleThresholdSeconds` 或 `screenLocked` 或 `redacted` 一律不截屏、不 OCR。

### 4. 截图触发与去重

新增两类触发，全部走 32-bin 直方图去重：

| 触发 | 时机 | 最小间隔 | 去重 |
|---|---|---|---|
| `app_focus` | 前台应用切换 | 4s | `diffPct >= 4%` 或心跳 |
| `click` | 全局鼠标点击后 | 10s | 同上 |
| `typing_pause` | 最后一次按键后静默 2s | 15s | 同上 |
| `visual_change` | 12s 周期视觉检查 | 12s | 同上 |
| `heartbeat` | 距上次保存 ≥ 120s | 120s | 强制保存 |

去重规则统一为：首帧、心跳到点、或 `diffPct >= 4%` 才落盘。`app_focus` 不再无条件保存。

### 5. 凭据脱敏（`PrivacyRedactor.redactSecrets` / `sanitizeMetadataValue`）

- 事件 `data` 的每个值、快照 `window_title`、OCR 文本在写库前统一脱敏。
- 覆盖：`Bearer/Basic <token>`、`api_key|token|secret|password|pwd|authorization ... = <value>`、`sk-...`、`ghp_...`、`xoxb-...`、`AKIA...`、JWT 三段式；URL 值额外走 `sanitizeURL` 去除 `token/session/sig/secret/password/auth/key` 查询参数。
- 只替换敏感片段为 `***`，保留其余可读上下文，避免把整段 OCR 变成空串。

### 6. 结构化标签

会话摘要合成时同步写入：

- `topics`：声明任务 / 项目 + 高频应用名 + 出现过的网页域名，去重后最多 8 个；
- `entities`：`{"task": [...], "app": [...], "domain": [...]}`，空分组不写；
- `highlights`：出现频次最高的窗口标题（最多 3 条）。

这些字段同时通过 `/api/activity-recorder/sessions` 与 `dayhelm query/sessions` 暴露给 Agent。

### 7. 旧快照降采样

两阶段留存：

1. 快照超过 `downsampleAfterDays`（默认 1 天）且仍为 `hot`：原地重编码为最长边 `480px`、JPEG 质量 `0.4`，更新 `width/height/size_bytes`，`storage_tier = 'downsampled'`。
2. 超过 `snapshotRetentionDays`（默认 7 天）：按既有规则删除文件并标记 `pruned`。

只有 `retentionDays > downsampleAfterDays` 时才执行降采样，避免刚降采样就被删除。

## 理由

- 分类/归一化放在 Core 纯函数里，可注入时钟、无 GUI 依赖，符合「测试先行」与模块边界。
- 事件主键仍保留原始标题，归一化只用于变更检测，不损失可读证据。
- idle 关会话在源头修正 `duration_ms`，比事后在报表里剔除更可靠。
- 统一「直方图去重 + 每触发最小间隔」，新增触发不会造成存储爆炸。
- 脱敏放在 `ActivityDatabase` 写入口，任何调用方（CLI、HTTP 回填、测试）都无法绕过。
- 降采样优先于删除，保留审计与回溯能力，同时把 7 天内磁盘占用压到较低水平。

## 推翻条件

- 浏览器识别误判超过可接受范围（例如大量 Electron 工作台被漏判为 `browser_visit`，或真实浏览器被漏判）：改为以 bundle 白名单为准，并补充可配置 `extraBrowserBundles`。
- 标题归一化把语义不同的页面合并（不同 SKU 仅数字不同被抹平）：改为只去掉明确的时间/百分比/括号计数，保留裸数字。
- 空闲判定与「深读思考」冲突（长时间无输入但确实在工作）：把 `idleThresholdSeconds` 拆成「关会话」与「停截图」两个阈值，截图阈值更长。
- 降采样后 OCR/回溯质量不足：提高 `maxWidth` 或把 OCR 文本保留与图片降采样解耦。
- 脱敏误伤正常文本（例如正文里出现 "token: ..." 讨论）：收窄正则或改为按 `redacted` 应用白名单。
