# 012. 基于 Jev (System One) 的零手工语义自动追踪与时间归属

- 状态：已采纳
- 日期：2026-11-19

## 背景
在前期实践中，仅靠静态关键词（`keywords`）、域名（`domains`）、应用 Bundle ID（`appBundleIds`）与人工点击「开始专注 / 切换任务」暴露出三类核心痛点：
1. **同应用/同域名下语义混杂**：例如 `fxg.jinritemai.com` 同时承载「商品开发/主图优化（电商做深）」与「售后退款/飞鸽客服（电商日常运营）」；同一 IDE / 终端 / 浏览器承载多个项目，静态规则难以区分。
2. **手工维护成本高且易忘切换**：用户刚上手就需要配规则，工作中忘记点击切换会导致时长归属失真，违背「低干预」初衷。
3. **跨应用协同与弱标题窗口难判定**：处理单一事项时频繁在浏览器、Photoshop、Excel、Finder、预览、AI 对话与微信之间穿梭；标题无信息时（如「无标题文档」「zsh」「Claude」）规则几乎失效。

经本机合成基准实测（`POST https://api.typesafe.ai/v1/systemone`，模型 `jev-1.14.0`）：
- 项目仅配置「名称 + 一句话说明」（零关键词/域名规则）时，21 条跨场景分类准确率 **100%**，同任务跨应用延续 vs 真实切换判定 **100%**，分心识别 **100%**；
- HTTP Keep-Alive 稳态延迟 **p50 = 224ms / p95 = 277ms**，单次约 765 input tokens（~$0.000032/次，输出 $0，日均 500 次约 $0.48/月）；
- 14 步无反馈泄露的闭环工作日模拟中，结合迟滞平滑后时长归属加权一致率达 **99.7%**。

## 候选方案
- **方案 A（继续堆叠本机正则与词典规则）**：完全离线、零成本，但无法理解自然语言语义与跨应用上下文，用户仍需手工维护大量规则并高频手工切换。
- **方案 B（调用通用自回归 LLM / Chat Completions）**：语义理解强，但输出为非结构化文本，存在 JSON 解析失败、延迟偏高（通常 800ms–3s）、缺少校准置信度概率、按输出 token 计费成本更高等问题。
- **方案 C（可选开启的 Jev System One 语义分类 + 本机前置去噪与确定性迟滞状态机）**：
  1. 在设置中提供**可开关的 `jevAutoTrackingEnabled` 选项**（默认关闭）；开启后若未检测到 `JEV_API_KEY`，明确提示用户配置 API Key 并支持一键连通性测试。
  2. 新手只需填写「项目名称 + 一句话说明（可选） + 计划时长（保底/封顶）」，无需维护关键词与域名规则。
  3. 采用**自动归属（无需手工确认）**：通过前台应用切换通知（`NSWorkspace.didActivateApplicationNotification`）与单进程轻量 `AXObserver`（监听当前前台应用及焦点窗口的 `kAXTitleChangedNotification` / `kAXFocusedWindowChangedNotification`，60ms 标题合并防抖）在 `< 80ms` 内事件驱动感知应用/标签页切换，不再受 2 秒轮询网格约束；本机以一次性精确防抖计时器过滤 `< 0.65s` 的瞬时路过（缓存回切过滤 `< 0.45s` 防闪烁），并按细粒度同上下文（含浏览器归一化标题）5 分钟缓存，仅在真实上下文稳定后异步调用 Jev，传入「经 `PrivacyRedactor` 脱敏与凭据清洗的当前窗口（含可选 ≤600 字正文 OCR 摘要） + 最近 3 条客观原始历史窗口（不回传模型历史标签，防自激漂移）」。
  4. 在 `DayHelmCore` 内通过纯逻辑、可注入时钟的确定性状态机（`SemanticAutoTracker`）做置信度门控与时间迟滞平滑，自动更新今日计划事项、`其他事务`（`__other_work__`）与 `分心中`（`__non_work__`）的时长累计及顶部菜单栏实时文字标签；手工点选退居为「即时纠偏/当日上下文记忆」；同时记录最近 100 条结构化判断日志（`JevDecisionLogEntry`，持久化至当日 `jev-log.json` 并在设置页实时可查），便于用户核查判断效果与微调项目说明。
  5. 断网、无 Key 或关闭开关时自动无缝退化回既有本机规则引擎。

## 选择
选择 **方案 C（升级为两层正交分类：活动模式 × 可选焦点项目）**。

### 两层正交分类模型（v1 优先零项目开箱即用）
实机使用验证发现，单层强制归入用户手填的细粒度项目会在未配置项目（如临时开发新工具、写日常笔记）时把置信度打散至 `0.18–0.46`。因此演进为两层正交结构，在单次 Jev `POST /v1/systemone` 请求中并行判定：
1. **第 1 层：活动模式（`ActivityMode`，系统内置 6 个 MECE 大类，零配置即开即用）**：
   - `build`（开发构建）、`create`（内容创作）、`operate`（业务运营）、`research`（研究规划）、`comms_admin`（沟通杂务）、`break`（休息分心）。
2. **第 2 层：焦点项目（`Focus Project`，用户可选配置 0–N 项，含保底/封顶配额）**：
   - 当用户未配置任何焦点项目时，仅查询 `activity_mode` + `same_task`；配置了焦点项目时并行查询 `focus_project`（含 `none`）。
   - 顶部菜单栏遵循「**命中焦点项目展示项目名与配额，未命中展示第 1 层活动模式与今日累计时长**」。
3. **语义驱动的上下文切换降噪 + 静态规则修补**：
   - 开启 Jev 时，窗口 `EnrichedSpan` 携带 `semanticGroup`（优先 `proj:<id>`，否则 `mode:<mode>`，分心为 `break`），`SwitchClassifier` 同语义组内跨应用协作不再计为跨任务切换；
   - 离线/静态规则下，非浏览器 `distinctContexts` 按应用级聚合（不因 IDE 内切文件膨胀），并将主流 AI 助手/截图/DayHelm 自身纳入协作/辅助白名单，且重启后给予 `120s` 启动宽限期避免历史 span 立即弹窗。
4. **OCR 正文提取、切页保鲜与过渡噪声过滤**：
   - 实机采样表明整屏 OCR 顶部常混入 macOS 菜单栏（含 DayHelm 自身胶囊）与浏览器标签栏；因此通过精确匹配同 `window_title` 避免串页，并借助地址栏/菜单栏锚点（扫描前 24 行）剥离顶部 Chrome/系统栏噪声、提取 **≤600 字页面正文**。对弱标题及多用途工作台/看板/聊天/AI/本地页面（如 Hermes Agent Dashboard、Discord、Vikunja、Notion、飞书、localhost 等）均附带正文 OCR；若首轮调用在 OCR 落盘前完成，待同窗口新 OCR 帧就绪后自动穿透无-OCR 缓存重判一次。
   - 实测发现同浏览器切换标签页走非 `app_focus` 触发时容易命中 `25s` OCR 冷却且等待 `10s/12s` 周期截屏，导致弱标题/多用途新标签页首轮无 OCR、十几秒后才重判；调整为：仅对**同窗口标题**维持 `25s` 冷却，切至不同窗口/标签页标题且命中 `shouldAttachOCR` 且无 180s 内新 OCR 时，停留 `0.35s`（等待页面绘制完成）后触发一次受 `3s` 冷却与去重门控的按需截屏 + OCR，完成后立刻唤醒 Jev 评估。
   - 进一步在实机日志（2026-11-23/24）中发现两类长尾误判与双发问题：（1）`maus-bot.lban2049.xyz | MausBot`、`memo.lban2049.xyz | Memo Inbox` 等短标题自建 Web 工作台未命中多用途关键词，全程 `noOCR` 漂移；因此在 `shouldAttachOCR` 中对清洗浏览器后缀后标题较短（CJK=2/ASCII=1 权重 `≤ 12`）或通用、或无明确路径语义的自定义域名/子域名工作台（排除知名内容/开发/电商站点）自动触发 OCR。（2）`minDwellBeforeClassifySeconds = 0.65s` 早于按需截屏 + Vision OCR 完成（~0.75–1.1s），导致 1 秒内 `noOCR → OCR` 连续双发；因此在具备按需 OCR 条件且 `needsOCR && ocrText == nil` 时，引入 `onDemandOCRWaitSeconds = 1.4s` 短等待上限：OCR 在窗口内落地（且停留 `>= 0.65s`）时立即收敛为**单次带 OCR 请求**，超时或无有效 OCR 时降级发 `noOCR` 不阻塞分类。
   - 调用 Jev 前直接过滤辅助浮层（`DayHelm` / `Xnip` / `Stats` / `Spotlight` / `Raycast` / `Alfred` 等）、浏览器空白新标签页（`新标签页` / `New Tab` / `chrome://newtab` / `about:blank`）、加载中 `无标题` / `Untitled` 页面以及无 URL/`chrome://` 的 Chrome `账号和同步` 弹窗，保持当前任务不变、消除无意义低置信与 1–3s 过场切换；对隐私脱敏的即时通讯/邮件/系统应用（如 `微信 redacted=true`）提示词明确确定性归入 `comms_admin`，并校准 `break` 边界（排除 SheerID/Google One 订阅认证与开源项目 Discord 技术频道）、IDE 内容创作例外（如 `obsidian`/`Podcast Draft` 归 `create`）及未打包本地 `Electron` 进程优先归 `build`。

在 41 条基准用例（38 条核心真实/合成用例 + 3 条实机低置信/漏检回归用例：脱敏微信、`Vikunja My Open Tasks`、带正文 OCR 的 `Hermes Agent Dashboard`）上实测：
- **零项目模式（v1 优先）**：第 1 层大类准确率 **41/41（100.0%）**，脱敏微信 `1.00`、Vikunja `1.00`、Hermes 看板 `0.96`，同任务 vs 切换 **26/27（96.3%，切换召回 13/13 = 100%）**，延迟 p50 **226ms**；
- **两层模式（6 大类 × 3 焦点项目）**：第 1 层 **38/38（100.0%）**，第 2 层 **36/38（94.7%）**，同任务 vs 切换 **26/27（96.3%）**，延迟 p50 **223ms**。

## 理由
1. **单次前向多题并行 + 校准概率**：Jev 在单次 ~220ms 请求内同时输出 `activity_mode`、`focus_project`（可选）与 `same_task`，可直接驱动确定性防抖逻辑；面对空白 `Finder` 等无证据窗口会诚实输出低置信度，避免误切。
2. **关键常量与依据（2s 内响应、防闪烁与低调用量平衡）**：
   - `AXWindowChangeObserver` 标题合并防抖 = `60ms`：只挂载于当前单个前台 PID（切换应用时自动换绑），零后台轮询 CPU；将网页加载/终端刷新期间的连发标题变化合并为单次采样，同时保持 `< 80ms` 切页感知。
   - `minDwellBeforeClassifySeconds = 0.65`（配合一次性精确防抖 `Task`，消除 2s 轮询网格将 3s 向上取整为 4–6s 的放大效应）：实机基准表明超过 2 分钟无请求后的 HTTP/2 Keep-Alive 冷 TLS 重连会把单次 Jev RTT 从 p50 `230ms` 推高到 `1050–1250ms`；将前置防抖自 `0.90s` 校准至 `0.65s` 后，仍可完全过滤 `150–500ms` 的快速 `Cmd+Tab` / 连续切 Tab 路过（0 次多余 Jev 请求），热连接端到端 **~0.9–1.0s**，即使命中冷 TLS 重连也能压在 **`<= 2.0s`** 以内。
   - `cacheSwitchDwellSeconds = 0.45`：命中 5 分钟缓存回切已知页面时，仍保留 `0.45s` 微防抖（冷启动与同类别保持 0 等待），既能在 **~0.5–0.6s** 内零 API 成本响应，又避免 `Cmd+Tab` 划过已缓存窗口时状态栏闪烁。
   - `coldStartConfidence = 0.55`：刚启动尚未归属任何事务时，中等以上置信度即可立刻给出归属反馈。
   - `minConfidenceToSwitch = 0.70`：已有归属时要求更高置信度才发起切换候选，防止弱信号引起菜单栏抖动。
   - `immediateSwitchConfidence = 0.80`（且 `same_task <= 0.60`）：高置信明确切换在首次 Jev 返回后**立即切换**（热连接端到端 ~0.9–1.0s，冷 TLS 重连仍 `<= 2.0s`），无需再进入二次等待；若 `same_task > 0.60`（跨应用同任务协作），仍阻止立即切换以防闪烁。
   - `fastSwitchConfirmSeconds = 1.2`（`confidence >= 0.75` 且 `same_task <= 0.65`）/ `minSwitchConfirmSeconds = 2.5`（中置信 `0.70–0.75` 或高 `same_task`）：仅在信号存在歧义时通过一次性精确定时器进入短暂自动**防抖观察**（全自动，绝不弹窗要求用户确认），彻底告别 2s 轮询对齐导致的 4–6s 拖尾。
   - `contextOCRDelaySeconds = 0.35` / `minWindowChangeOCRIntervalSeconds = 3.0` / `onDemandOCRWaitSeconds = 1.4`：仅当新页面命中 `shouldAttachOCR` 且无 180s 内 OCR 帧时在 `0.35s` 后按需抓帧 OCR（跳过普通清晰标题页，且受 `3s` 冷却与视觉去重保护），避免推高 CPU/内存或惊扰 `__ocr-worker`；具备按需 OCR 条件时，将首次 Jev 分类等待上限由 `0.65s` 短暂放宽至 `1.4s`（`0.35s` 绘制稳定 + `0.4–1.0s` 截屏与 Vision OCR），OCR 就绪且停留 `>= 0.65s` 后立即发单次带 OCR 请求，超时或无有效 OCR 则在 `1.4s` 降级发 `noOCR`，消除 1 秒内 `noOCR → OCR` 连续双发。
   - `contextCacheTTLSeconds = 300.0`：按细粒度语义上下文键（浏览器包含归一化窗口标题，区分 Discord 不同频道、X 发帖页与首页、localhost 不同看板）在 5 分钟内缓存；若缓存记录无 OCR 且同窗口新 OCR 就绪，允许单次升级重判。
   - `maxOCRSnippetChars = 600`：剥离顶栏/标签栏噪声后提取 ≤600 字正文，覆盖 Hermes 看板、飞书文档、聊天频道与终端内容，同时保持单次请求延迟 ~220ms、极低 token 成本。
   - `manualOverrideCooldownSeconds = 600.0`：用户手工点选纠偏时，将该上下文记入当日局部覆写表并在当前上下文锁定 10 分钟；切去其它窗口后自动追踪照常生效。
3. **隐私底线可控**：严格 opt-in；API Key 独立保存在 `~/.config/alma/dayhelm/jev.key`（权限 `0600`，不写入 `config.json`），亦兼容 `JEV_API_KEY` 环境变量与本地 `.env`；命中 `PrivacyRedactor`（`redacted == true`）或锁屏时绝不外发标题、URL 或 OCR；所有外发文本均先走凭据脱敏与 URL 敏感参数清洗，永不上传屏幕截图。

## 推翻条件
如果实际日常使用满 5 个工作日后出现以下任一情况，需重开本决策：
1. 真实工作流下自动归属准确率低于 85%，或需要每天手工纠偏超过 5 次；
2. Jev 服务延迟 P95 长期超过 2000ms、可用率低于 98%，或定价大幅上涨导致单人月成本超过 $5；
3. 本机端侧小模型（Apple Silicon MLX / Foundation Models）在同等内存开销（<300MB 常驻）下能达到同等准确率与延迟，届时应切换为完全离线端侧推理。
