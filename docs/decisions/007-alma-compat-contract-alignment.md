# 007 · Alma 兼容面跟随真实服务端契约（搜索 / 快照文件 / 日周汇总 / OCR 字段）

- 状态：已采纳
- 日期：2026-11-17

## 背景

阶段 1 只实现了 `/api/activity-recorder/status`、`/sessions`、`/sessions/<id>`、`/api/dayhelm/context` 四条路由。复核时发现两类缺口：

1. **敲击密度不可见**：`click` / `keypress` 事件虽然落库，但会话摘要只有 `eventCount`，看不出「这段会话是人在高强度敲打，还是页面挂着人走了」；Agent 与日汇总因此拿不到输入强度信号。
2. **兼容面不完整**：Alma 真实服务端（`/Applications/Alma.app/Contents/Resources/alma-server/lib/server.mjs`，只读核对）实际暴露的兼容路由是
   - `GET /api/activity-recorder/search/keyword?q=&limit=`
   - `GET /api/activity-recorder/snapshot-file?path=`
   - `GET /api/activity-recorder/summary/daily/:dateKey`
   - `GET /api/activity-recorder/summary/weekly/:weekKey`
   且会话详情返回的 OCR 数组键名是 `ocr`（`{ session, events, snapshots, ocr }`），DayHelm 只回了 `ocrFrames`。

照旧实现会让「只认 Alma 字段的下游工具」在读取 OCR 与汇总时静默拿到空结果。

## 候选方案

- **方案 A：只补 `/sessions/<id>/events`，其余按 DayHelm 自有命名自定**。代价：下游必须为 DayHelm 写专用分支，`alma-time-audit` 与既有 Alma 工具链无法直接切换。
- **方案 B：按真实服务端契约逐条对齐**（本 ADR 选择）。字段名、路由、参数名、越界行为（`403 forbidden path`、空 `q` 返回 `{results:[]}`）都以 Alma 现有实现为准；DayHelm 自有的富检索另开 `/api/dayhelm/search`，不混进兼容面。

## 选择

选择 **方案 B**，落地为：

1. **会话级敲击密度**：`activity_sessions` 新增 `click_count` / `keypress_count` 列（写事件时同一条 `GROUP BY kind` 刷新），摘要 JSON 暴露 `clickCount` / `keypressCount` / 派生的 `inputEventsPerMinute`。只计次，绝不读按键内容。
2. **`ocr` 别名**：`/sessions/<id>` 同时返回 `ocrFrames`（DayHelm 既有调用方）与 `ocr`（Alma 形状，同源同值），迁移期两边都不破。
3. **关键词搜索**：`/api/activity-recorder/search/keyword` 只搜 OCR 文本（Alma 语义），形状 `{results:[{id,sessionId,snapshotId,text,createdAt}]}`；跨标题/URL/会话摘要的富检索放在 `/api/dayhelm/search`，返回 `{keyword,total,hits}`。
4. **快照文件**：`/api/activity-recorder/snapshot-file` 支持 `?path=`（Alma 契约）与 `?id=`（DayHelm 便利），只允许 `snapshots/` 目录内的文件，越界 `403`、缺失 `404`、未配置存储 `503`；响应用 `image/jpeg` 原始字节，不再套 JSON。
5. **日/周汇总**：`/summary/daily/<dateKey>`、`/summary/weekly/<weekKey>` 输出 Alma `activity_summaries` 形状（`id/kind/dateKey/summary/stats/model/isPartial/createdAt/updatedAt`），`stats` 键名照抄 Alma 的日/周统计（`sessionCount`/`totalActiveMs`/`analyzedCount`/`notWorthCount`/`snapshotCount`/`ocrCharCount`/`apps[{app,durationMs}]`/`hours[{hour,count}]`/`keyMoments`，周级 `weekKey`/`startDate`/`endDate`/`daily`）。**现场聚合、不落表**：Alma 的 `activity_summaries` 只是存储实现，DayHelm 不复制第二份真源；`summary`（叙事）恒为 `null`、`model` 恒为 `null`，因为 DayHelm 不调用任何 LLM。
6. **`dayhelm status --format json` / `--json`**：CLI 与 HTTP 同一套事实，输出 `recorder` 计数（含敲击密度），Agent 不必解析 md。

## 理由

- 兼容对象的形状由**正在运行的那份服务端实现**决定，不是由猜测决定；按真实实现对齐可以用最小代价换来「下游零改动」。
- 敲击密度用存列而非每次 `COUNT(*)` 子查询：会话列表一次最多 5000 行，子查询会把它变成 5000 次扫表。
- 汇总现场计算避免双写漂移：`days/*.json`、SQLite 与会话摘要已经是一份事实，再存一份 summary 只会产生「哪个是真的」的争议。
- 快照文件按目录白名单鉴权，避免把 `?path=` 变成任意文件读取。

## 推翻条件

1. Alma 后续把 `ocr` 改名或改结构，且下游已全部迁移到新名字 → 去掉别名，只留新契约。
2. 日/周汇总现场聚合出现可感知延迟（单次 > 300ms，例如保留 90 天以上大量会话）→ 增加 `activity_summaries` 表做缓存，并补「过期即失效」规则。
3. 派生 `inputEventsPerMinute` 被证明误导（例如长会话中一段高强度输入被平均稀释到无意义）→ 改为按分钟桶的直方图或滑动窗口峰值，而不是会话平均值。
4. 快照文件服务带来安全或隐私风险（例如软链接逃逸未被拦住）→ 改为只允许 `?id=`，路径一律由数据库解析。
