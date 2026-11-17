# 隐私与权限

本机采集的数据包含窗口标题与浏览器 URL，属于高敏感个人数据。本文件是硬边界。

## 采集清单（全部，不多不少）

| 数据 | 粒度 | 用途 |
|---|---|---|
| 前台应用名 + bundleId | 事件 + 2s 轮询 | 判断是否在白名单内 |
| 窗口标题 | 2s 轮询 | 识别具体在做什么，供项目归属 |
| 浏览器当前 URL | 2s 轮询 | 区分"目标性访问"与"泛刷" |
| 空闲时长（秒数，不含内容） | 2s 轮询 | 判断人是否在 |
| 屏幕锁定状态 | 事件 | 排除锁屏时段 |
| 专注块元数据（交付物、备注） | 用户输入 | 会话记录与回位 |

## 明确不采集

- 音频、摄像头
- 键盘输入**内容**（只取空闲时长，不取按键内容）
- 剪贴板
- 鼠标轨迹、点击坐标
- 屏幕截图、OCR 文本
- 网络请求内容

> 禁止通过按键监听推断用户输入。空闲检测只读取"距上次事件多少秒"，不读取事件本身。

## 本地存储

所有数据留在本机：

```
~/.config/alma/focus-live/
  today.json           # 今日热数据
  blocks/*.json        # 日终定稿
  config.json          # 阈值与白名单
```

- 无遥测、无崩溃上报、无云同步、无网络分析
- 进程**不发任何出站网络请求**。若未来需要，必须先改本文件并取得用户明确同意
- 不读写 `~/.config/alma/time-audit/` 下除 `focus.json`（只读）以外的任何文件

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
|---|---|---|---|
| Accessibility（辅助功能） | 必需 | 读窗口标题与浏览器 URL | 仅记录 app 名，项目归属退化为"按应用" |
| Screen Recording | **不需要** | — | 本工具不做截图 |

关于 Screen Recording：窗口标题有两条路，AX 或 `CGWindowList`。本工具**只走 AX**，因此不需要 Screen Recording 权限。这一点与 Alma recorder 不同（它虽然也写 AX 路径，但字段被硬编码为 null）。

权限被拒绝时：

- 不弹反复纠缠的对话框
- 在菜单栏主屏明确显示"权限缺失，标题不可用"，并给一个跳转系统设置的按钮
- 采集继续运行，降级为仅 app 名

## 数据删除

必须提供一条命令，删除后不可恢复：

```bash
focus-guard purge            # 删除 ~/.config/alma/focus-live/ 全部内容
focus-guard purge --before 2026-11-01   # 按日期删除
```

删除时必须：

- 同时清理 `today.json`、`blocks/`、`config.json` 中的用户输入内容（交付物文本、备注）
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
