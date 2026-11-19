# 决策记录（ADR）

每份记录回答：**当时为什么这么选，什么条件下该推翻。**

## 格式

```markdown
# NNN. 标题

- 状态：提议 / 已采纳 / 已推翻 / 被 NNN 取代
- 日期：YYYY-MM-DD

## 背景
什么问题需要决定，不做的代价是什么。

## 候选方案
A / B / C，各自的代价，不要只写优点。

## 选择

## 理由
具体到证据，不写"感觉更好"。

## 推翻条件
什么观察结果出现时，应该重开这个决定。
**没有这一节的决定不算完成。**
```

## 已采纳与规划清单

| 编号 | 主题 | 状态 |
|---|---|---|
| [001](001-lightweight-quota-and-supervision.md) | 定位转向：从"切换瞬间强制摩擦/白名单锁"转为"轻量配额监督与趋势提醒"（定名 DayHelm） | 已采纳 |
| [002](002-swiftpm-architecture-and-testing.md) | 工程架构与测试规范：SwiftPM 四模块分层与可注入时钟自检 | 已采纳 |
| [003](003-standalone-native-recorder-and-open-agent-hub.md) | 独立原生采集、屏幕 OCR 与开放 Agent 数据中心 | 已采纳 |
| [006](006-activity-classification-and-retention.md) | 活动分类与标题抖动抑制、idle 会话/截图、截图触发去重、凭据脱敏、结构化标签与旧快照降采样 | 已采纳 |
| [007](007-alma-compat-contract-alignment.md) | Alma 兼容面跟随真实服务端契约：敲击密度、`ocr` 别名、关键词搜索、快照文件、日/周汇总 | 已采纳 |
| [008](008-alma-parity-capture-retention-and-perf.md) | 对标 Alma 采集引擎：浏览器兜底、键鼠聚合、双阶段探针、分层留存、FTS5 与性能收敛 | 已采纳 |
| [009](009-activity-recorder-settings-and-session-history-ui.md) | 采集器配置面板与历史会话检视器（独立窗口 + Precision Telemetry 风格） | 已采纳 |
| [010](010-cross-app-same-task-switch-detection.md) | 跨应用同任务切换判定与高频切换降噪机制 | 已采纳 |
| [011](011-cpu-and-memory-performance-convergence.md) | CPU 与内存性能收敛：Core 记忆化、SQLite 索引、单次像素签名、OCR 降采样与 UI 按需解码 | 已采纳 |
| [012](012-jev-semantic-auto-tracking.md) | 基于 Jev (System One) 的零手工语义自动追踪与时间归属 | 已采纳 |
| 004 | 项目映射机制（如何区分"切去其它项目"与"多应用正常协同"） | 被 010 / 012 演进覆盖 |
| 005 | 跑偏与高频乱切的滑动窗口判定阈值及提醒交互 | 已在阶段 2 持续迭代 |
