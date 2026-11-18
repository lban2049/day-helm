# 隐私与权限（DayHelm · 日舵）

本机采集的数据包含窗口标题、浏览器 URL，以及（可选开启时）屏幕快照与设备端 OCR 文本，属于高敏感个人数据。本文件是硬边界。

## 采集清单（全部，不多不少）

| 数据 | 粒度 | 开关 / 权限 | 用途 |
|---|---|---|---|
| 本机活动事件（`app_focus`, `browser_visit`, `click`, `keypress`, `typing_pause`, `lock`, `unlock`） | 毫秒级事件 + 2s 轮询（仅计数与时间戳，不录具体按键字符） | 基础监听（全局键鼠仅计次） | 构建完整会话边界、切换时间点与活跃度 |
| 前台应用名 + `bundleId` | 事件驱动 + 2s 轮询 | 无需权限 | 记录应用切换频次与活动归属 |
| 窗口标题 `windowTitle` | 2s 轮询 (AX `kAXTitleAttribute`) | Accessibility | 识别具体工作内容、补齐会话标题并辅助跑偏检测 |
| 浏览器当前 `url` | 2s 轮询 (AX `AXDocument`)，缺失时经隐私预检后用 1s 超时 AppleScript 兜底（含熔断） | Accessibility (+ 可选 Automation) | 区分不同项目页面与泛刷行为（写入前剥离敏感 query 参数；锁屏或命中 `PrivacyRedactor` 绝不调用 AppleScript） |
| 屏幕快照（可选深度录制） | 32-bin 直方图 (`>= 4%`) + 160×90 缩略像素差 (`>= 2%`) 双条件去重（`320px` 探针预检 + `1920px` JPEG 0.55） | **可选** `Screen Recording` + `deepRecordingEnabled` 开关 | 保留视觉工作上下文并驱动设备端 OCR；`>1天` 降采样为 `1280px/0.4` (`warm`)，`>7天` 降采样为 `640px/0.3` (`cold`)，默认保留 7 天且总磁盘上限 `10 GB`（超限裁至 `7.5 GB`） |
| 设备端 OCR 文本（可选深度录制） | 随去重快照（`app_focus` 立即执行，非 `app_focus` 最小间隔 `25s`，按 `ocrEveryN` + 会话内连续去重），由短命无头子进程 `DayHelm __ocr-worker`（空闲 `15s` 或满 `10` 帧退出）从落盘 JPEG 按 `1280px` 缩略解码后运行 Apple Vision OCR（`.accurate`、`usesLanguageCorrection = false`） | 同上（**完全本机离线识别**） | 为 AI Agent 与 `alma-time-audit` 提供可检索的屏幕语义摘要 |
| 空闲时长（秒数，不含内容） | 2s 轮询 (`CGEventSource` / `IOHIDSystem`) | 无需权限 | 判断人是否在场，避免空转计入专注时长 |
| 屏幕锁定状态 | `DistributedNotificationCenter` + 休眠/唤醒事件 | 无需权限 | 排除锁屏与休眠时段并立即终止截屏与 OCR |
| 专注事项元数据（当前事项、目标配额、备注） | 用户输入 | — | 当日配额追踪与上下文恢复 |
| Alma 历史回补事件（可选兼容） | 本地环回 `http://localhost:23001` 只读增量同步 | 无（仅当 Alma 运行时） | 兼容已有 Alma 会话历史 |

## 明确不采集

- 音频、摄像头
- 键盘输入**具体文本内容**（`NSEvent` 全局监听严格只记触发时间戳与聚合次数 `data.count`，**禁止访问 `characters` / `keyCode` / `modifierFlags` 推断用户输入文本，也不记录鼠标坐标**）
- 剪贴板
- 脱敏应用的屏幕截图与 OCR（命中 `PrivacyRedactor` 或锁屏时**绝对不截屏、不运行 OCR、不调用浏览器 AppleScript**）
- 出站公网网络请求内容

> 禁止通过按键监听推断用户输入文本。

## 本地存储

所有数据留在本机 `~/.config/alma/dayhelm/`：

```
~/.config/alma/dayhelm/
  activity.sqlite        # 开放 SQLite 数据库（WAL 模式）：sessions / events / snapshots / ocr_frames / ocr_fts
  snapshots/YYYY-MM-DD/  # 去重后的 JPEG 快照（>1天 warm 1280px/0.4；>7天 cold 640px/0.3；默认 7 天过期清理 + 10GB 容量封顶）
  today.json             # 今日实时配额与上下文热数据（原子写）
  days/YYYY-MM-DD.json   # 日终定稿归档
  config.json            # 事项配额、关键词与采集器设置（含采集启停、防抖/心跳/空闲/停顿/轮询/JPEG 质量、Vision OCR 与语言/采样间隔、全局键鼠监听开关、sensitiveBundleIds、留存天数与存储上限）
```

- 无遥测、无崩溃上报、无云同步、无网络分析
- 进程**不发任何出站公网网络请求**
- 内置本地 HTTP API 服务**严格只绑定环回地址 `127.0.0.1`**（主端口 `24001`，若被占用则在 `24001...24009` 自动选端，不占用 Alma 的 `23001`），绝不绑定外部网卡（`0.0.0.0`）
- `GET /api/activity-recorder/snapshot-file` 只读服务 `~/.config/alma/dayhelm/snapshots/` 目录内的文件：解析软链接后的规范路径不在该目录内一律 `403`，不接受 `?path=` 指向数据库、`today.json` 或其他任意本地文件；快照已删除则 `404`，不隐式重新生成
- 不修改 `~/.config/alma/time-audit/` 下的任何文件（仅在初次初始化时只读读取 `focus.json` 与 `config.json`）

## 敏感应用过滤（含截图与 OCR 阻断）

以下应用或窗口命中 `PrivacyRedactor` 时（`redacted == true`），**只记录应用名，不记录标题和 URL，且绝对不截屏、不运行 OCR**：

| 类别 | bundleId / 判断依据 |
|---|---|
| 密码管理器 | `com.1password.*`、`com.bitwarden.*`、`com.agilebits.*` |
| 银行 / 支付 | 标题或 URL 命中 `bank`、`pay`、`checkout`、`stripe`、`alipay`、`paypal`、`wechatpay`、`unionpay` |
| 私密通信 | `com.tencent.xinWeChat` 的私聊窗口、`com.apple.MobileSMS`（可通过配置开关） |
| 医疗 / 证件 | 标题命中 `病历`、`诊断`、`身份证`、`护照` |
| 系统隐私面板 | `com.apple.systempreferences` / `com.apple.systemsettings` 的隐私安全相关页 |

命中后的行为：

```
事件记录  { app: "1Password", title: null, url: null, redacted: true }
屏幕与 OCR  跳过截屏、跳过 Vision OCR（零图片落盘、零文本入库）
```

**不记录任何标题片段、不做哈希、不做长度。** 只留 app 名。

## 凭据脱敏（写入前强制）

即使未被 `PrivacyRedactor` 整条拦截，写入 SQLite 前仍会对以下字段做凭据擦除：

- 事件 `data` 的每个值、快照 `window_title`、OCR 文本；
- `Bearer/Basic <token>`、`api_key|token|secret|password|pwd|authorization ... = <value>`、`sk-...`、`ghp_...`、`xoxb-...`、`AKIA...`、`AIza...`（Google API Key）、JWT 三段式、PEM 私钥块（`-----BEGIN ... PRIVATE KEY-----`）、美国 SSN（`\d{3}-\d{2}-\d{4}`）以及通过 Luhn 校验的 13–19 位银行卡号 → 敏感片段替换为脱敏掩码（如 `***` 或 `****-****-****-<last4>`）；
- 任何形似 URL 的值额外走 `sanitizeURL`，删除 `token/session/sig/secret/password/auth/key` 查询参数。

该脱敏位于 `ActivityDatabase` 写入口，CLI、HTTP 回填与测试均无法绕过。

## 权限（分级与无痛降级）

| 权限 | 必需性 | 用途 | 拒绝或关闭后的降级 |
|---|---|---|---|
| Accessibility（辅助功能） | 推荐（核心标题/URL） | 读窗口标题（`kAXTitleAttribute`）与浏览器 URL（`AXDocument`） | 仅记录应用名与基础活动事件 |
| Screen Recording（屏幕录制） | **可选**（深度快照与 OCR） | 仅当 `deepRecordingEnabled == true` 且已授权时捕获去重屏幕快照并运行 Apple Vision OCR | **不弹反复纠缠对话框**；无缝运行纯 AX 窗口标题 + URL + 事件录制 |

权限被拒绝或未开启时：

- 不弹反复纠缠的对话框
- 在菜单栏面板「采集与 OCR 引擎」状态栏中温和提示，并提供一键开启/跳转系统设置按钮
- 所有核心功能（配额监督、光谱条、AX 标题、SQLite 事件与 Agent CLI/API）继续正常运行

## 数据删除与留存

1. **自动留存清理**：`snapshots/YYYY-MM-DD/*.jpg` 在超过配置保留天数（默认 **7 天**）后自动删除磁盘 JPEG 文件，并将 `activity_snapshots.storage_tier` 标记为 `pruned`（OCR 文本与会话元数据仍可搜索）。
2. **手动彻底删除**：提供 CLI 命令，删除后不可恢复：

```bash
dayhelm purge                       # 删除 ~/.config/alma/dayhelm/ 全部内容（JSON、activity.sqlite、snapshots/、config.json）
dayhelm purge --before 2026-11-01   # 按日期删除：清理该日期前的 days/*.json、SQLite 记录与 snapshots/YYYY-MM-DD/
```

删除时必须：

- 同时清理 `today.json`、`days/`、`config.json`、`activity.sqlite`（含 `-wal` / `-shm`）及 `snapshots/`
- 明确打印删除了什么、多少文件、多少字节
- 不做"软删除"、不留备份

## Git 边界

**不得提交到 Git：**

- `*.json` 采集数据（真实标题、URL）
- 任何截图（`snapshots/`、`*.jpg`、`*.jpeg`、`*.png` 采集产物）
- 任何数据库文件（`*.sqlite`、`*.sqlite-*`、`*.db`、`*.db-*`）
- 任何含真实窗口标题或真实 OCR 文本的测试夹具

`.gitignore` 必须覆盖：

```
data/
today.json
days/
blocks/
captures/
snapshots/
exports/
*.jpg
*.jpeg
*.sqlite
*.sqlite-*
*.db
*.db-*
```

测试一律使用**合成数据**。合成数据里的标题与 OCR 测试图必须明显是假的（如 `Example Doc — Editor`、`DayHelm OCR 2026`），不得复制真实标题或真实屏幕截图。

## 风险清单

| 风险 | 缓解 |
|---|---|
| 窗口标题或 OCR 含客户名、密码、私人对话 | 只存本地；敏感应用触发 `redacted == true` 时阻断截屏与 OCR；提供 `purge` |
| URL 含 token（如 `?session=...`） | 写入前剥离 query string 中的 `token`/`key`/`session`/`sig`/`secret`/`password`/`auth` 参数 |
| AX 遍历可能读到页面正文 | 本工具**只读 `kAXTitleAttribute` 和 `AXDocument`**，不遍历子树、不读 `kAXValueAttribute` |
| 磁盘截图膨胀 | 32-bin 直方图 `diffPct >= 0.04` 去重 + JPEG 0.55 压缩 + 默认 7 天自动清理原图 |
| 本地 HTTP 端口被局域网访问 | `NWListener` 强制 `requiredLocalEndpoint = 127.0.0.1`，绝不绑定 `0.0.0.0` |
| ad-hoc 重签导致 TCC 反复重置 | `scripts/install-app.sh` 支持固定生产路径 `/Applications/DayHelm.app` 与本地代码签名证书 |

## 与其它系统的数据边界的说明

`focus.json` 中已有用户的**主攻方向、目标、逃避信号**等高度私密的自省内容。本工具：

- 只读取 `primary_focus.project_keys` 和过程目标，用于配额计算
- 不修改、不回写
- 不在日志或界面中展示 `why`、`escape_signal`、`reminders` 等字段内容
