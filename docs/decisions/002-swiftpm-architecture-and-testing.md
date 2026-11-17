# 002. 工程架构与测试规范：SwiftPM 四模块分层与可注入时钟自检

- 状态：已采纳
- 日期：2026-11-17

## 背景
DayHelm 计划作为高质量开源 macOS 工具维护，核心包含实时事件流合并、双向时间预算追踪、时间光谱条计算、Alma+AX 双通道采集与高密度菜单栏 UI。需要确立清晰的模块边界与可在无 GUI / 无网络 / 无真实用户数据环境下运行的自动化测试机制。

## 候选方案
- **方案 A**：单一 App target，逻辑与 SwiftUI 视图混写。代价：计时、配额与滑动窗口逻辑耦合 `AppKit` 和系统时钟 `Date()`，无法确定性单测。
- **方案 B**：SwiftPM 四模块分层（`DayHelmCore` / `DayHelmCapture` / `DayHelmApp` / `DayHelmChecks`）+ `Tests/DayHelmCoreTests`。`DayHelmCore` 严禁 `import AppKit`，所有时间推进通过显式传入时间戳或注入 `Clock` 协议完成；同时提供 `DayHelmChecks` 可执行自检与标准 `swift test`。

## 选择
选择 **方案 B**，最低系统版本定为 **macOS 14 (`.v14`)**。

## 理由
1. `DayHelmCore` 纯逻辑零 UI 依赖，可在任何 CI 或命令行环境毫秒级跑完所有边界测试（保底/封顶状态跃迁、空闲自动暂停、Alma+AX 区间合并、敏感信息脱敏、光谱条切分）。
2. 同时支持 `swift test` 与 `swift run DayHelmChecks`，兼顾开源社区标准与受限环境快速自检。
3. macOS 14 原生提供成熟的 `MenuBarExtra(.window)` 与 Swift Concurrency 支持，无需引入任何第三方依赖。

## 推翻条件
当未来需要支持 macOS 13 或更旧系统，或 SwiftPM 的资源打包无法满足复杂 App Bundle 需求时，再考虑引入 Xcode 工程文件。
