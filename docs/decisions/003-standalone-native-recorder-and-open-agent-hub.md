# 003. 独立原生采集、屏幕 OCR 与开放 Agent 数据中心

- 状态：已采纳
- 日期：2026-11-17

## 背景

DayHelm 最初依赖本机常驻的 Alma `activity-recorder`（`localhost:23001`）提供实时 `sessions`、`events`、`snapshots` 与 OCR 管道，并仅通过 AX 轮询补齐缺失的 `windowTitle`。然而这带来了三个结构性限制：

1. **强依赖 Alma 进程**：一旦退出或未启动 Alma，全天实时事件流、快照去重与 OCR 文本采集随之停摆，`alma-time-audit` 的上游接口（`http://localhost:23001/api/activity-recorder/...`）也会断开。
2. **闭源黑盒与数据孤岛**：原有事件、快照与 OCR 结果分散在外部应用私有目录中，AI Agent（Claude Code、Codex、Hermes 等）无法通过标准 CLI 或统一本地上下文接口低成本检索当天屏幕语义与窗口轨迹。
3. **缺少统一的原生活动数据库**：DayHelm 仅落盘 `today.json` 与 `days/*.json` 聚合结果，缺少毫秒级事件、去重屏幕快照与 Vision OCR 帧的开放 SQLite 持久化层。

## 候选方案

- **方案 A：继续强依赖 Alma `activity-recorder`**
  - 代价：无法脱离 Alma 独立运行；外部进程关闭时丢失输入事件、快照与 OCR；外部接口不返回完整 `windowTitle` 且无 DayHelm 任务配额上下文。
- **方案 B：在 DayHelm 内构建独立原生采集引擎 + 开放 SQLite 数据库 + Agent CLI/HTTP 数据中心，同时保持对 Alma API 的兼容**
  - 利用 macOS 原生 `ScreenCaptureKit` + 32-bin 直方图/8×8 感知哈希去重 + 设备端 `Vision` OCR（`zh-Hans` / `zh-Hant` / `en-US` / `ja`）+ `NSWorkspace` / `NSEvent` 轻量活动监听，将全部数据写入开放的 `~/.config/alma/dayhelm/activity.sqlite`。
  - 屏幕录制权限设为**可选且可开关**：未授权或关闭深度录制时，无痛降级为纯 AX 窗口标题 + URL + 事件录制，不反复弹窗。
  - 通过 `Network` 框架在 `127.0.0.1:24001`（若被占用则在 `24001...24009` 自动选端，避免占用 Alma 的 `23001` 端口）提供本地兼容 HTTP API；同时提供 `dayhelm query` / `search` / `sessions` CLI 供任意 AI Agent 调用。
  - 代价：工程新增 SQLite 存储层、原生截图去重与 OCR 调度、本地环回 HTTP 服务，需要严格守住隐私脱敏与磁盘留存边界。

## 选择

选择 **方案 B**：将完整的原生屏幕快照去重、Apple Vision OCR、开放 SQLite 数据库（`activity.sqlite`）、Agent CLI（`query` / `search` / `sessions`）与兼容本地 HTTP API（`:24001` / `2400x`）全部内置于 DayHelm，且不占用 Alma 的 `23001` 端口。

## 理由

1. **零第三方依赖且彻底脱离 Alma**：纯 Swift + macOS 系统框架（`SQLite3`、`ScreenCaptureKit`、`Vision`、`Network`），无需 Node/Python 运行时或外部常驻进程即可独立完成全天采集。
2. **无缝兼容下游生态**：`activity.sqlite` 沿用并扩展 `activity_sessions` / `activity_events` / `activity_snapshots` / `activity_ocr_frames` 四表结构，HTTP API 兼容 `/api/activity-recorder/*` 且补齐 `windowTitle` 与 `declared_task_id`，`alma-time-audit` 无需改动即可直接工作。
3. **隐私优先与零惩罚降级**：命中 `PrivacyRedactor` 脱敏规则或锁屏时绝对不截屏、不运行 OCR；32-bin 直方图（`diffPct >= 0.04`）过滤静止画面，JPEG 快照默认 7 天自动清理而 OCR 文本与结构化元数据保留可检索。
4. **对 AI Agent 极度友好**：提供 `dayhelm query` / `search` / `sessions`（支持 `md` 与 `json` 输出）和 `/api/dayhelm/context`，让任意本机 Agent 可一键读取当前专注配额、窗口上下文与屏幕 OCR 摘要。

## 推翻条件

当出现以下任一情况时，应重开并评估推翻本决定：
1. 连续日常运行中，设备端 Vision OCR 或 ScreenCaptureKit 快照导致持续 CPU 占用 > 8% 或显著影响电池续航，且无法通过调整采样间隔（12s 检测 / 120s 心跳）缓解；
2. 用户决定彻底停用任何形式的屏幕快照与 OCR，仅保留纯 AX 文本轨迹（届时仅需关闭或移除 `NativeScreenRecorder` 模块，保留 `activity.sqlite` 事件层即可）。
