# DayHelm（日舵）

单人自用的 macOS 当日时间配额、实时记录分析与跑偏监督工具。

**掌舵当天的方向，偏航时及时修正，不再等第二天事后诸葛亮。**

`alma-time-audit` 解决了“第二天复盘昨天时间花在哪”，而 **DayHelm** 解决的是**“在今天当下，实时结合活动采集看清各事项投入进度，并在跑偏、高频乱切或超时的时候及时拉我一把”**。

它只做三件事：

1. **实时混合记录与分析（Record & Analyze）**：结合本机常驻的 Alma `activity-recorder` 实时事件流与 DayHelm 自身的轻量 AX 窗口标题采集，实时合成今日活动光谱与连续块指标。
2. **双向时间预算管理（Target & Cap）**：核心推进事项设**保底（Target）**，看清还差多少；容易失控的事务（如日常运营）设**封顶（Cap）**，到点提醒换挡，避免在一件事上耗尽全天。
3. **温和趋势监督提醒（Nudge）**：声明当前专注事项后，容许跨多应用正常协作；仅在滑动窗口检测到**持续跑偏到其它项目**、**高频碎片化乱切**、或**配额到点**时，通过右上角非抢占式卡片温和提醒。

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
3. **原有采集缺窗口标题、且事后审计滞后**：Alma 的实时采集没有保存非浏览器窗口标题（`windowTitle: null`），且 `time-audit` 要到次日 08:00 才出日报，当天跑偏或超时无法实时感知。

## 核心设计原则

- **监督与校准，而不是强制锁死。** 不拦截 Cmd+Tab，不隐藏窗口，不搞全屏读秒锁。用右上角**不抢键盘焦点**的轻量 HUD 卡片提醒，把无意识切换变成有意识决定。
- **高密度精密仪表风（Precision Telemetry）。** 菜单栏胶囊常驻显示当前事项与配额进度（如 `● 电商做深 · 52/90m`），下拉面板一屏呈现专注切换器、双向预算条、今日时间光谱条（Day Spectrum Ribbon）与连续度微指标。
- **双通道混合采集（Alma 实时流 + AX 标题补齐）。** 直接增量读取 Alma `localhost:23001` 的实时事件（重启不丢当天历史），并用本机轻量 AX 采样补齐缺失的窗口标题与 URL。
- **复用既有配置。** 项目定义与主攻方向来自 `~/.config/alma/time-audit/`（`focus.json` / `config.json`），不在多处重复维护项目字典。

## 快速开始（Build & Run）

系统要求：macOS 14.0+，Swift 5.10+。

```bash
# 1. 运行全量确定性自检断言（无需 GUI、无需网络、不读写用户真实数据）
swift run DayHelmChecks

# 2. 打包生成 build/DayHelm.app（含 ad-hoc 签名）
./scripts/build-app.sh

# 3. 以合成演示模式预览 UI（不读写 ~/.config/alma/dayhelm/）
./build/DayHelm.app/Contents/MacOS/DayHelmApp --synthetic-demo

# 4. 查看今日配额状态或彻底清理本地数据（CLI 模式）
./build/DayHelm.app/Contents/MacOS/DayHelmApp status
./build/DayHelm.app/Contents/MacOS/DayHelmApp purge --before 2026-11-01
```

## 工程模块结构

| 模块 | 职责 | 约束 |
|---|---|---|
| [`Sources/DayHelmCore`](Sources/DayHelmCore) | 纯逻辑引擎：时钟协议、双向配额追踪、heartbeat 合并、隐私脱敏、光谱条切分、JSON 原子存储 | **严禁 `import AppKit`**，100% 确定性可单测 |
| [`Sources/DayHelmCapture`](Sources/DayHelmCapture) | 双通道混合采集：`AlmaActivityClient` (`localhost:23001`) + `AXWindowInspector` (标题/URL/HID 空闲) | 协议隔离，支持离线无缝退化与合成演示模式 |
| [`Sources/DayHelmApp`](Sources/DayHelmApp) | 界面与入口：菜单栏实时胶囊、`330pt` Precision Telemetry 面板、右上角 `.nonactivatingPanel` 提醒卡片、CLI | 仅通过 `HybridActivityCoordinator` 驱动 |
| [`Sources/DayHelmChecks`](Sources/DayHelmChecks) | 18 项确定性自检套件（同步镜像于 [`Tests/DayHelmCoreTests`](Tests/DayHelmCoreTests)） | 失败即 `exit(1)`，CI 与命令行即跑 |

## 当前阶段

**阶段 1 已完成实现并通过自检**：双通道混合采集 + 菜单栏今日配额仪表盘 + 配额到点换挡提醒 + CLI 状态与数据清理。

下一步（见 [roadmap](docs/roadmap.md)）：在日常使用中观察采集数据，进入 **阶段 2** 细化项目映射与跨项目跑偏提醒阈值。

## 文档

- [产品需求](docs/requirements.md)：问题定义、用户故事、验收标准与待细化问题
- [技术方案与 UI 规范](docs/architecture.md)：分层架构、Alma+AX 混合采集、判定模型、存储格式与 Precision Telemetry UI 规范
- [隐私与权限](docs/privacy.md)：采集清单、TCC 权限、过滤规则、删除
- [路线图](docs/roadmap.md)：阶段划分与验证顺序
- [调研报告](docs/research/competitive-and-technical-scan.md)：竞品机制、价格、macOS 可行性实测
- [设计依据](docs/research/evidence.md)：每条设计取舍背后的学术实证
- [决策记录](docs/decisions/)：技术选型的取舍与推翻条件

## 开发约定

见 [AGENTS.md](AGENTS.md)。核心三条：**文档先行、测试先行、轻量验证**。

## 与既有系统的关系

```
Alma activity-recorder (localhost:23001) ──实时事件流──┐
~/.config/alma/time-audit/{focus,config}.json ──只读──┼──▶ DayHelm (+ AX 标题补齐)
                                                      │       │
                                                      │    产出实时与日终数据
                                                      │       ▼
                                                      └── ~/.config/alma/dayhelm/*.json ──读取──▶ time-audit（次日交叉验证与标题补全）
```

- **实时掌舵 vs 事后审计**：`DayHelm` 管当天实时记录、配额进度与跑偏提醒，`alma-time-audit` 管次日深度复盘与评分，职责互补。
- **补齐窗口标题短板**：`DayHelm` 采集的 `windowTitle` 落盘后，可供次日 `time-audit` 提升项目归属率。

## 硬性边界与开源许可

单人本机使用。不做团队监控、远程管理、云同步、遥测、游戏化。所有数据留在 `~/.config/alma/dayhelm/`，一条命令可彻底删除。

本项目基于 [MIT License](LICENSE) 开源。
