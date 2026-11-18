# 008 · 对标 Alma 采集引擎：浏览器兜底、键鼠聚合、双阶段探针、分层留存、FTS5 与性能收敛

- 状态：已采纳
- 日期：2026-11-17

## 背景

将 DayHelm 现有采集与兼容层与 Alma `activity-recorder` 做逐模块对比后，发现 11 项直接影响采集完整度、时长准确性、磁盘/CPU 开销与接口兼容性的缺口：

1. **浏览器识别与 URL 兜底不足**：`ActivityClassifier` 漏掉 Dia（`company.thebrowser.dia` / `com.thebrowser.dia`）与 Safari Technology Preview（`com.apple.safaritechnologypreview`）；对隐藏或未实现 `AXDocument` 的 Chromium/Safari 场景无 AppleScript 兜底。
2. **键鼠输入计数被 2s 节流静默丢弃**：`NativeEventMonitor` 每 2 秒丢弃多余点击/按键，导致高强度敲击时 `click_count` / `keypress_count` 与真实 `inputEventsPerMinute` 严重偏低。
3. **30s 空闲心跳污染会话时长与异常退出残留**：`recordSampleToDatabaseIfNeeded` 在 `idleSeconds` 为 `30s..299s` 期间仍写入 30s 心跳事件，把空闲尾巴拉进 `ended_at` / `duration_ms`；系统休眠/唤醒未闭合会话、进程崩溃后未闭合的 `ended_at IS NULL` 会话也未在启动时自动收口。
4. **会话计数器全表扫描与高频重算摘要**：每次插入事件/快照都在 `activity_events` / `activity_snapshots` 上做 `COUNT(*)/SUM(...)` 并重建摘要，长会话写放大明显。
5. **全分辨率盲截屏与单像素变化漏检**：12s `visual_change` 直接抓全屏再比较直方图，既吃 CPU，又抓不住直方图分布近似但画面局部显著变化（如代码滚动/终端输出）；`1920px` 上限在 Retina 屏略糊；多屏下固定抓主屏而非前台窗口所在屏；`isCaptureInFlight` 时直接丢弃高优先级 `app_focus`/`click`；`typing_pause` 依赖 2s 轮询检查，精度差。
6. **旧快照缺失文件死循环与无磁盘上限**：`downsampleOldSnapshots` 遇到已不在磁盘的文件时跳过不改 `storage_tier`，下次维护继续重复扫描这批 500 条记录，导致真旧快照被卡死；缺少 `warm`/`cold` 分层与总容量封顶。
7. **OCR 采样固定 1:1 且无连续去重**：每次截图必跑 Vision OCR、相邻帧完全相同的 OCR 文本重复入库、检索走全表 `LOWER(text) LIKE`。
8. **摘要语义维度偏窄**：`is_meeting` 恒为 0；`entities` 仅含 `task`/`app`/`domain`，缺少代码协作常见实体（`repo` / `pr` / `local_port`）。
9. **凭据脱敏缺少常见格式**：PEM 私钥块、Google `AIza...` Key、美国 SSN、Luhn 校验银行卡号尚未覆盖。
10. **HTTP 兼容面缺少分页/短 ID/部分只读端点**：`/sessions` 缺 `offset` 与 `analysisStatus`；`/sessions/<id>` 不支持 6 位以上短前缀匹配；缺 `/permissions`、`/config`、`/digest`、`/report/<dateKey>`。
11. **权限诊断不透明**：缺少 `keypressMonitoringEffective`（全局键盘监听依赖辅助功能授权）状态暴露。

## 候选方案

- **方案 A：全盘照搬 Alma 架构**（引入 `23001`、接入 LLM 摘要与向量 embedding、每 100ms 轮询）。代价：违背 DayHelm 零 LLM 成本、严格端口隔离、本地轻量低功耗的定位。
- **方案 B：保持 DayHelm 纯本地零 LLM 边界，对上述 11 项做精准工程对标与收敛**（本 ADR 选择）。纯逻辑与 SQLite 留在 `DayHelmCore`（可注时钟单测），系统 API 留在 `DayHelmCapture`（可注入桩对象单测）。

## 选择

选择 **方案 B**，具体决策如下：

1. **浏览器扩展与 AppleScript 兜底**：
   - `ActivityClassifier` 加入 `company.thebrowser.dia`、`com.thebrowser.dia`、`com.apple.safaritechnologypreview`；应用名匹配对 `"dia"` / `"dia browser"` 做整名匹配，避免误伤 `Obsidian`。
   - `AXWindowInspector` 在已知浏览器未通过 `AXDocument` 取到 `http(s)` URL 或标题为空时，先经 `PrivacyRedactor.shouldRedact` 与锁屏检查放行，再以 `with timeout of 1 seconds` 的 AppleScript 兜底读取活跃标签页 URL/标题；附带按 bundle 维度的熔断器（`-1743` 立即冷却 300s，连续失败 3 次冷却 300s）。
2. **计次级键鼠聚合**：
   - `NativeEventMonitor` 仍禁止读取 `characters` / `keyCode` / `modifierFlags` / 鼠标坐标，只在内存累加点击与按键次数，按 1 秒定时、单桶达 `40` 次、或 `app_focus` / `lock` / `will_sleep` / `stop` 时批量刷出 `NativeMonitorEvent(count: N)`。
   - 写入 `activity_events.data.count`，数据库统计时使用 `COALESCE(CAST(json_extract(data, '$.count') AS INTEGER), 1)`，兼容无 `count` 的历史事件。
   - 提供 `onRawInput` 回调即时重置 `typing_pause` 静默计时器，并暴露 `isKeypressMonitoringEffective` 供权限诊断使用。
3. **空闲心跳过滤、休眠/唤醒与启动清理**：
   - `recordSampleToDatabaseIfNeeded` 仅当 `sample.idleSeconds < 30.0` 时才允许 30s 周期心跳事件写库，防止 `30s..299s` 空闲轮询持续推后 `ended_at`。
   - `ActivityDatabase.finalizeStaleOpenSessionsOnStartup()` 在协调器启动时关闭所有历史未闭合会话并补齐摘要。
   - 监听 `NSWorkspace.willSleepNotification` / `didWakeNotification`：休眠前刷出聚合输入并在最后活动时刻闭合会话；唤醒及解锁时调用 `resetDeduplicationBaseline()` 重置视觉去重基线（不伪造 `unlock` 事件）。
4. **$O(1)$ 增量计数与 30s 节流摘要**：
   - `ActivityDatabase` 维护内存 `syncedSessionIds`：新建会话直接入集，写事件/快照执行 $O(1)$ 增量更新（`event_count + 1`、`click_count/keypress_count + count`、`snapshot_count + 1`、`total_bytes + sizeBytes`）；遇到未同步过的既有会话时仅首写重算一次，兼顾旧库迁移兼容性。
   - `synthesizeSessionSummaryLocked` 在首次分析、距上次分析 `>= 30s`、插入 OCR 帧、以及关闭会话时触发，避免高频事件每次全扫会话事件。
5. **双阶段小图探针、像素差、2560px、多屏、优先级队列与独立防抖计时**：
   - `ImageHistogram` 新增 `160x90` 缩略 RGB 像素差（通道差 `>= 30` 且变更像素占比 `minPixelDiffPct >= 0.02`），与 `minHistogramDiffPct >= 0.04` 取并集触发保存（`diff_pct = max(histDiff, pixelDiff)`）。
   - `ScreenSnapshotCapturer` 将全尺寸上限从 `1920px` 提至 `2560px`；根据前台应用层-0 在屏窗口交集面积动态选择所属显示器（`DisplayGeometry.selectDisplayID`）；`12s` `visual_change` 且非心跳到期时先抓 `320px` 探针图比较，未达阈值则跳过 `2560px` 捕获。
   - 捕获并发冲突时保留单槽最高优先级挂起队列（`app_focus > click > typing_pause`），当前捕获结束后自动补采。
   - `HybridActivityCoordinator` 用独立可取消 `typingPauseTask`（静默 `2.0s`）取代 2s 轮询触发 `typing_pause`。
6. **分层降采样、缺图熔断与存储封顶**：
   - 修复 `downsampleOldSnapshots` 缺图或解码失败死循环：改将数据库该行标记为 `storage_tier = 'pruned'`、`size_bytes = 0`；先写临时文件确认体积确实变小再覆盖原图，否则保留原图并更新层标签。
   - 自动维护执行二级降采样：`hot -> warm`（超过 1 天、`1280px`、质量 `0.4`）与 `warm -> cold`（留存 > 7 天且超过 7 天、`640px`、质量 `0.3`）；保留手动显式参数调用 `downsampleOldSnapshots(..., storageTier = "downsampled")` 的契约不变。
   - `DayHelmSettings` 新增 `snapshotMaxStorageBytes`（默认 `10 GB`）与 `ocrEveryN`（默认 `1`）；超限后按时间从旧到新清理文件并标 `pruned`，裁减至配额 `75%`。
7. **OCR 采样、连续去重、FTS5 与实体/会议识别**：
   - 支持按 `ocrEveryN` 间隔执行 OCR（`app_focus` 与首帧必跑），且同一会话内与上一帧相同的 OCR 文本不重复入库。
   - 建 `activity_ocr_fts USING fts5(frame_id UNINDEXED, session_id UNINDEXED, snapshot_id UNINDEXED, text, tokenize='trigram')` 与 `INSERT/DELETE` 触发器，关键词长度 `>= 3` 走 FTS5 `MATCH`，`< 3` 回退 `LIKE`。
   - `synthesizeSessionSummaryLocked` 自动识别主流会议软件/网页（Zoom、Google Meet、Teams、飞书/Lark 会议、腾讯会议、Webex、钉钉会议）设置 `is_meeting = 1`，并用正则从 URL 与标题提取 `repo`、`pr`、`local_port` 实体。
8. **扩展凭据脱敏**：
   - `PrivacyRedactor.redactSecrets` 补充 PEM 私钥块、`AIza...` Google API Key、SSN（`\d{3}-\d{2}-\d{4}`）以及通过 Luhn 校验的 13–19 位银行卡号。
9. **HTTP 兼容补齐**：
   - `/api/activity-recorder/sessions` 支持 `offset` 与 `analysisStatus` 过滤（`total` 为匹配总数）。
   - `/sessions/<id>` 与 `/sessions/<id>/events` 支持 6 字符及以上唯一 ID 前缀解析。
   - 新增 `GET /api/activity-recorder/permissions`、`GET /api/activity-recorder/config`、`GET /api/activity-recorder/digest`、`GET /api/activity-recorder/report/<dateKey>`（无 LLM 确定性 Markdown 日报，带 `skeletonOnly: true`）。

## 理由

- 每项阈值（30s 空闲心跳门限、1s/40 次键鼠聚合、30s 摘要节流、320px 探针、2% 像素差、10 GB -> 7.5 GB 水位线、FTS5 `trigram` 长度阈值 3）均可依据实机性能测量独立调优。
- 所有新增逻辑保持无外部依赖、无 LLM 调用、无按键内容记录。

## 推翻条件

1. 若某些浏览器因系统弹窗反复拒绝 AppleScript 自动化授权导致频繁卡顿 → 在默认配置中关闭 AppleScript 兜底或改为显式开关。
2. 若 1280px `warm` 档导致 `snapshots/` 体积接近 10 GB 的速度过快 → 将 `warm` 下调至 `960px` 或收紧 `snapshotMaxStorageBytes` 默认值。
3. 若 30s 摘要节流导致 Agent 读取刚结束前最后几秒上下文有明显延迟 → 改为事件数变化 + 标题切换也触发轻量摘要更新。
4. 若正则实体提取在非 GitHub 网页产生过高误报（例如 `#100` 价格被误标为 PR）→ 仅从 PR/Issue URL 或特定标题模式提取 `pr`。
