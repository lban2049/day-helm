# 隐私与权限（DayHelm · 日舵）

本机采集的数据包含窗口标题与浏览器 URL，属于高敏感个人数据。本文件是硬边界。

## 采集清单（全部，不多不少）

| 数据 | 粒度 | 用途 |
|---|---|---|
| Alma 实时活动事件 (`app_focus`, `browser_visit`, `click`, `keypress`, `unlock`) | 本地环回增量同步 | 获取当天完整会话边界、切换时间点与键鼠活跃计数 |
| 前台应用名 + bundleId | 事件 + 2s 轮询 | 记录应用切换频次与活动归属 |
| 窗口标题 | 2s 轮询 (AX) | 补齐 Alma 缺失的窗口标题，识别具体工作内容并辅助跑偏检测 |
| 浏览器当前 URL | 2s 轮询 (AX) | 区分不同项目页面与泛刷行为 |
| 空闲时长（秒数，不含内容） | 2s 轮询 | 判断人是否在场，避免空转计入专注时长 |
| 屏幕锁定状态 | 事件 | 排除锁屏时段 |
| 专注事项元数据（当前事项、目标配额、备注） | 用户输入 | 当日配额追踪与上下文恢复 |

## 明确不采集

- 音频、摄像头
- 键盘输入**具体文本内容**（只取活跃计数与空闲时长，不取具体按键内容）
- 剪贴板
- 屏幕截图、OCR 文本（DayHelm 自身不做截图）
- 出站公网网络请求内容

> 禁止通过按键监听推断用户输入文本。

## 本地存储

所有数据留在本机：

```
~/.config/alma/dayhelm/
  today.json           # 今日热数据
  days/*.json          # 日终定稿
  config.json          # 每日各事项配额目标与提醒阈值
```

- 无遥测、无崩溃上报、无云同步、无网络分析
- 进程**不发任何出站公网网络请求**（仅通过环回地址 `http://localhost:23001` 只读读取本机 Alma `activity-recorder` 的实时事件）
- 不修改 `~/.config/alma/time-audit/` 下的任何文件（仅只读读取 `focus.json` 与 `config.json`）

## 敏感应用过滤

以下应用命中时，**只记录应用名，不记录标题和 URL**：

| 类别 | bundleId / 判断依据 |
|---|---|
| 密码管理器 | `com.1password.*`、`com.bitwarden.*`、`com.agilebits.*` |
| 银行 / 支付 | 标题或 URL 命中 `bank`、`pay`、`checkout`、`stripe`、`alipay`、`paypal` |
| 私密通信 | `com.tencent.xinWeChat` 的私聊窗口、`com.apple.MobileSMS`（可通过配置开关） |
| 医疗 / 证件 | 标题命中 `病历`、`诊断`、`身份证`、`护照` |
| 系统隐私面板 | `com.apple.systempreferences` 的隐私相关页 |

命中后的行为：

```
记录  { app: "1Password", title: null, url: null, redacted: true }
```

**不记录任何标题片段、不做哈希、不做长度。** 只留 app 名。

## 权限

| 权限 | 必需性 | 用途 | 拒绝后的降级 |
|---|---|---|
| Accessibility（辅助功能） | 必需 | 读窗口标题与浏览器 URL（补齐 Alma 缺失的窗口标题） | 仅记录 app 名与 Alma 基础事件 |
| Screen Recording | **不需要** | — | DayHelm 自身不做截图 |

关于 Screen Recording：窗口标题有两条路，AX 或 `CGWindowList`。本工具**只走 AX**，因此不需要 Screen Recording 权限。这一点正好补齐了 Alma recorder（`windowTitle` 硬编码为 null）的短板。

权限被拒绝时：

- 不弹反复纠缠的对话框
- 在菜单栏主屏明确显示"权限缺失，标题不可用"，并给一个跳转系统设置的按钮
- 采集继续运行，降级为仅记录 app 名与 Alma 基础事件

## 数据删除

必须提供一条命令，删除后不可恢复：

```bash
dayhelm purge            # 删除 ~/.config/alma/dayhelm/ 全部内容
dayhelm purge --before 2026-11-01   # 按日期删除
```

删除时必须：

- 同时清理 `today.json`、`days/`、`config.json` 中的用户输入内容（备注文本等）
- 明确打印删除了什么、多少字节
- 不做"软删除"、不留备份

## Git 边界

**不得提交到 Git：**

- `*.json` 采集数据（真实标题、URL）
- 任何截图
- 任何数据库文件
- 任何含真实窗口标题的测试夹具

`.gitignore` 必须覆盖：

```
data/
today.json
days/
blocks/
*.sqlite
*.sqlite-*
*.db
*.db-*
```

测试一律使用**合成数据**。合成数据里的标题必须明显是假的（如 `Example Doc — Editor`），不得复制真实标题。

## 风险清单

| 风险 | 缓解 |
|---|---|
| 窗口标题含客户名、文件名、未公开项目名 | 只存本地；敏感过滤；提供 purge |
| URL 含 token（如 `?session=...`） | 写入前剥离 query string 中的 `token`/`key`/`session`/`sig` 参数 |
| AX 遍历可能读到页面正文 | 本工具**只读 `kAXTitleAttribute` 和 `AXDocument`**，不遍历子树、不读 `kAXValueAttribute` |
| ad-hoc 重签导致 TCC 反复重置、用户图省事全开权限 | 文档写明；建议用固定路径 + 免费开发证书 |
| 常驻进程被遗忘 | 菜单栏常驻可见；提供暂停开关；进程崩溃不自动重启到无声状态 |

## 与其它系统的数据边界的说明

`focus.json` 中已有用户的**主攻方向、目标、逃避信号**等高度私密的自省内容。本工具：

- 只读取 `primary_focus.project_keys` 和过程目标，用于配额计算
- 不修改、不回写
- 不在日志或界面中展示 `why`、`escape_signal`、`reminders` 等字段内容
