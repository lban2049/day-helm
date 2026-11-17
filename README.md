# DayHelm（日舵）

单人自用的 macOS 当日时间配额、实时记录分析与跑偏监督工具。

**掌舵当天的方向，偏航时及时修正，不再等第二天事后诸葛亮。**

`alma-time-audit` 解决了“第二天复盘昨天时间花在哪”，而 **DayHelm** 解决的是**“在今天当下，实时结合活动采集看清各事项投入进度，并在跑偏、高频乱切或超时的时候及时拉我一把”**。

它只做三件事：

1. **独立原生全量记录与分析（Record & Analyze）**：彻底脱离 Alma 独立运行——内置原生应用焦点/键鼠活跃监听、AX 窗口标题与 URL 采集、可选的 32-bin 直方图去重屏幕快照与本机 Apple Vision OCR，并将全部会话/事件/快照/OCR 写入开放的 `~/.config/alma/dayhelm/activity.sqlite`。
2. **双向时间预算管理（Target & Cap）**：核心推进事项设**保底（Target）**，看清还差多少；容易失控的事务（如日常运营）设**封顶（Cap）**，到点提醒换挡，避免在一件事上耗尽全天。
3. **温和趋势监督与开放 Agent 数据中心（Nudge & Open Hub）**：声明专注事项后容许跨多应用正常协作；通过右上角非抢占式卡片温和提醒，并开放 `dayhelm query/search/sessions` CLI 与本地兼容 HTTP API（`127.0.0.1:24001` / `2400x`）供任意 AI Agent 与 `alma-time-audit` 读取。

## 为什么需要它

本机实测基线（2026-11 月）：

| 指标 | 数值 |
|---|---|
| session 中位时长 | **4.1 分钟** |
| ≥10 分钟的 session | 25 / 244 |
| 活跃日切换频次 | **50–78 次/小时** |

更关键的是现实工作流的特征：
1. **单任务天然跨多应用**：处理电商事务时，需要在浏览器、图片工具、表格、终端等多个应用间正常切换，**靠“锁死单一应用/白名单”完全行不通**，只会产生海量误报。
2. **切换发生在多个正当工作之间**：在 `alma` / `ecommerce` / `hermes` / `infra-billing` 之间横跳，或者在某一项运营事务上不知不觉耗掉半天。
3. **彻底摆脱外部黑盒采集与事后滞后**：DayHelm 自行完成窗口标题、URL、去重截图与设备端 Vision OCR 录制并写入开放 SQLite，既能在当天实时监督，也能通过独立的 `localhost:24001`（`2400x` 段，不抢占 Alma 的 `23001`）服务 `alma-time-audit` 与本机 AI Agent。

## 核心设计原则

- **监督与校准，而不是强制锁死。** 不拦截 Cmd+Tab，不隐藏窗口，不搞全屏读秒锁。用右上角**不抢键盘焦点**的轻量 HUD 卡片提醒，把无意识切换变成有意识决定。
- **高密度精密仪表风（Precision Telemetry）。** 菜单栏胶囊常驻显示当前事项与配额进度（如 `● 电商做深 · 52/90m`），下拉面板一屏呈现专注切换器、采集与 OCR 引擎状态、双向预算条、今日时间光谱条（Day Spectrum Ribbon）与连续度微指标。
- **独立原生采集 + 可选 Vision OCR + 隐私优先。** `Screen Recording` 为可选权限，开启后自动执行 32-bin 直方图去重与设备端多语言 Vision OCR（`zh-Hans`/`zh-Hant`/`en-US`/`ja`）；权限拒绝或关闭时静默运行纯 AX 录制。命中敏感应用过滤（`redacted == true`）或锁屏时绝不截屏、不跑 OCR。
- **开放 Agent CLI & 兼容 HTTP API。** 提供 `query` / `search` / `sessions` / `status --format json` CLI 与 `127.0.0.1:24001`（若被占用则在 `24001...24009` 自动选端）环回接口，兼容 Alma 形状的 `/api/activity-recorder/status`、`/sessions`、`/sessions/<id>`（含 `ocr`）、`/sessions/<id>/events`、`/search/keyword`、`/snapshot-file`、`/summary/daily|weekly`，另提供 `/api/dayhelm/context` 与 `/api/dayhelm/search`，且绝不冲突占用 Alma 的 `23001` 端口。

## 快速开始（Build & Run）

系统要求：macOS 14.0+，Swift 5.10+。

```bash
# 1. 运行全量确定性自检断言（无需 GUI、无需网络、不读写用户真实数据）
swift run DayHelmChecks

# 2. 打包生成 build/DayHelm.app 或安装至 /Applications/DayHelm.app
./scripts/build-app.sh
./scripts/install-app.sh --launch

# 3. 以合成演示模式预览 UI（不读写 ~/.config/alma/dayhelm/）
./build/DayHelm.app/Contents/MacOS/DayHelmApp --synthetic-demo

# 4. Agent CLI：查询今日上下文、检索窗口/OCR 关键词、查看会话或彻底清理数据
/Applications/DayHelm.app/Contents/MacOS/DayHelm query --today --format md
/Applications/DayHelm.app/Contents/MacOS/DayHelm search "抖店" --limit 10 --format json
/Applications/DayHelm.app/Contents/MacOS/DayHelm sessions --date 2026-11-17 --format md
/Applications/DayHelm.app/Contents/MacOS/DayHelm status
/Applications/DayHelm.app/Contents/MacOS/DayHelm status --format json
/Applications/DayHelm.app/Contents/MacOS/DayHelm purge --before 2026-11-01
```

## 工程模块结构

| 模块 | 职责 | 约束 |
|---|---|---|
| [`Sources/DayHelmCore`](Sources/DayHelmCore) | 纯逻辑引擎 + 开放 SQLite 数据库（`ActivityDatabase`）+ `DayHelmCLI` + 隐私脱敏 + JSON 存储 | **严禁 `import AppKit`**，100% 确定性可单测 |
| [`Sources/DayHelmCapture`](Sources/DayHelmCapture) | 原生采集与本地服务：`AXWindowInspector`、`NativeScreenRecorder`（直方图去重 + Vision OCR）、`LocalActivityHTTPServer`、`AlmaActivityClient` | 协议隔离，支持离线与合成测试 |
| [`Sources/DayHelmApp`](Sources/DayHelmApp) | 界面与入口：菜单栏实时胶囊、`330pt` Precision Telemetry 面板（含采集与 OCR 引擎控制条）、`.nonactivatingPanel` 提醒卡片 | 仅通过 `HybridActivityCoordinator` 驱动 |
| [`Sources/DayHelmChecks`](Sources/DayHelmChecks) | 确定性自检套件（同步镜像于 [`Tests/DayHelmCoreTests`](Tests/DayHelmCoreTests)） | 失败即 `exit(1)`，CI 与命令行即跑 |

## 当前阶段

**独立原生采集与开放数据中心已就绪**：无需启动 Alma，DayHelm 即可完成活动事件 + AX 标题/URL + 可选去重截图与 Apple Vision OCR 录制，并通过 `activity.sqlite`、Agent CLI 与本地兼容 HTTP API（`24001` / `2400x`）对外开放。

## 文档

- [产品需求](docs/requirements.md)：问题定义、用户故事、验收标准与待细化问题
- [技术方案与 UI 规范](docs/architecture.md)：分层架构、原生采集与 OCR、开放 SQLite 表结构、CLI/HTTP 接口与 UI 规范
- [隐私与权限](docs/privacy.md)：采集清单、TCC 分级权限、敏感过滤与截屏阻断、留存与删除
- [路线图](docs/roadmap.md)：阶段划分与验证顺序
- [调研报告](docs/research/competitive-and-technical-scan.md)：竞品机制、价格、macOS 可行性实测
- [设计依据](docs/research/evidence.md)：每条设计取舍背后的学术实证
- [决策记录](docs/decisions/)：技术选型的取舍与推翻条件

## 开发约定

见 [AGENTS.md](AGENTS.md)。核心三条：**文档先行、测试先行、轻量验证**。

## 与既有系统的关系

```
原生 AX + 事件监听 + 可选 ScreenCaptureKit & Vision OCR ──▶ DayHelm
                                                            ├─▶ ~/.config/alma/dayhelm/activity.sqlite & snapshots/
                                                            ├─▶ ~/.config/alma/dayhelm/{today,days/*.json}
                                                            ├─▶ CLI: dayhelm query / search / sessions
                                                            └─▶ HTTP 127.0.0.1:24001 (2400x 空闲自动选端)
                                                                  ├─▶ alma-time-audit（次日审计，含完整 windowTitle）
                                                                  └─▶ AI Agents（Claude Code / Codex / Hermes）
```

- **实时掌舵 vs 事后审计**：`DayHelm` 负责当天实时采集、配额监督与即时 Agent 上下文检索，`alma-time-audit` 负责次日深度复盘与评分。
- **端口隔离兼容 Alma 接口**：DayHelm 监听独立的 `127.0.0.1:24001`（`2400x` 段）提供兼容 `/api/activity-recorder/...` 数据（包含完整 `windowTitle`、`declared_task_id` 与 OCR 帧），绝不占用 Alma 自身的 `23001` 端口。

## 硬性边界与开源许可

单人本机使用。不做团队监控、远程管理、云同步、遥测、游戏化。所有数据留在 `~/.config/alma/dayhelm/`，一条命令可彻底删除。

本项目基于 [MIT License](LICENSE) 开源。
