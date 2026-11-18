# 009 · 采集器配置面板与历史会话检视器（独立窗口 + Precision Telemetry 风格）

- 状态：已采纳
- 日期：2026-11-17

## 背景

DayHelm 的 `DayHelmCore` 与 `DayHelmCapture` 已经内置完整的原生活动采集、视觉去重、Apple Vision OCR、敏感应用脱敏与分层留存能力，但菜单栏面板（`330pt` 固定宽度）只暴露了极简的开关微条（`AX 标题`、`屏幕 OCR`、`API :24001`）：

1. 用户无法在界面内查看或调整采集防抖、心跳间隔、空闲关闭阈值、输入停顿窗口、画面变化轮询、JPEG 质量、Vision OCR 开关/语言/采样步长、全局键鼠监听开关、敏感应用 Bundle ID 列表以及存储配额上限。
2. 用户无法在界面内直观查看 SQLite 中的历史录制会话（`activity_sessions`）、事件时间线、去重快照与 OCR 文本，也无法直观看到各存储配额占用百分比和权限状态。

## 候选方案

- **方案 A：把所有配置表单与会话列表塞进 330pt 菜单栏 Popover（折叠/滚动）**。
  - 代价：破坏 `AGENTS.md` 规定的「330pt 免滚动菜单栏高密度仪表盘」核心交互体验；多行 Bundle ID 编辑框、数值配置网格与会话详情在 330pt 宽度内过于局促。
- **方案 B：保持 330pt 菜单栏 Popover 精简免滚动，新增独立原生 `ActivityRecorderWindow`（`NSWindow`，双标签页：采集配置 + 历史会话），并沿用 DayHelm Precision Telemetry 视觉体系**（本 ADR 选择）。
  - 菜单栏 Popover 底部与引擎栏提供一键直达入口；独立窗口支持完整采集参数持久化、权限检查与跳转、存储进度条、近期会话预览以及带事件/快照/OCR 详情的会话检视器。

## 选择

选择 **方案 B**：

1. **配置模型向后兼容扩展（`DayHelmSettings`）**：
   - 在 `DayHelmSettings` 中补充 `activityRecorderEnabled`、`visionOCREnabled`、`inputMonitoringEnabled`、`appFocusDebounceMs`（默认 `4000`）、`heartbeatIntervalMs`（默认 `120000`）、`recorderIdleThresholdMs`（默认 `300000`）、`typingPauseQuietMs`（默认 `2000`）、`visualCheckIntervalMs`（默认 `12000`，`0` 表示关闭轮询）、`jpegQuality`（`1...100`，默认 `55`）、`ocrLanguages`（默认 `["zh-Hans", "zh-Hant", "en-US", "ja"]`）与 `sensitiveBundleIds`（默认 `["com.apple.keychainaccess", "com.1password.1password", "org.bitwarden.desktop", "com.lastpass.LastPass"]`）。
   - 所有新增字段均提供默认值与 `decodeIfPresent` 回退，旧版 `config.json` 无需迁移即可直接读取。
2. **运行时全链路生效**：
   - `NativeScreenRecorder` 支持实时更新防抖/心跳/轮询/JPEG 质量参数；`visualCheckIntervalMs == 0` 时跳过 `visual_change` 探针。
   - `NativeEventMonitor` 支持按 `inputMonitoringEnabled` 动态启停全局 `NSEvent` 点击/按键计数监听（仍严禁读取按键字符与坐标）。
   - `AXWindowInspector` 与 `HybridActivityCoordinator` 动态同步 `sensitiveBundleIds` 到 `PrivacyRedactorConfig.additionalSensitiveBundlePrefixes`，确保命中后不采标题/URL、不截屏、不运行 OCR、不触发浏览器 AppleScript。
3. **存储统计与历史会话检视**：
   - `ActivityDatabase` 提供 `recorderStorageStats()`（总会话数、事件数、快照数、OCR 帧数、非 `pruned` 快照已用字节数、当前活跃会话 ID）。
   - `ActivityRecorderView` 以 DayHelm Precision Telemetry 卡片风格呈现（`SF Pro` + `.monospacedDigit()` + 语义色条），包含「采集配置」页（含总览卡片、macOS 权限、采集参数网格、OCR 与输入、敏感应用列表、存储配额与最近会话预览）与「历史会话」页（左侧可搜索会话列表 + 右侧事件时间线/快照缩略图/OCR 详情）。

## 理由

- 保持日常高频使用的 330pt 菜单栏面板轻量免滚动，同时让低频深度配置与历史追溯拥有宽敞的原生桌面体验。
- 所有界面配置直接驱动底层 `NativeScreenRecorder`、`NativeEventMonitor`、`AXWindowInspector` 与 `HybridActivityCoordinator`，不存在"只存不管用"的空壳配置项。

## 推翻条件

1. 若用户几乎只在菜单栏里快速扫一眼最近 3 条会话而不愿打开独立窗口 → 可在 330pt Popover 中追加一个可折叠的 3 行最近会话微视图，同时保留独立详情窗。
2. 若独立窗口与多屏全屏切换在 `.accessory` 模式下频繁被遮挡 → 可增加全局快捷键或 Dock 临时激活切换策略。
