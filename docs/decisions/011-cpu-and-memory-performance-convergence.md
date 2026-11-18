# 011. CPU 与内存性能收敛：Core 记忆化、SQLite 索引、单次像素签名、OCR 降采样与 UI 按需解码

- 状态：已采纳
- 日期：2026-11-18

## 背景

在实机连续录制场景下的性能剖析显示，DayHelm 后台常驻进程存在 **33.6% 持续 CPU 占用**与 **432.9 MB 内存峰值**。根因分布在核心分析、数据库与采集/UI 多个环节：

1. **每 2 秒全量重算光谱与切换指标**：`SpectrumBuilder.build` 每次全量排序并调用两次 `SwitchClassifier.prepareSequence`，`DayHelmEngine.evaluateHighFrequencySwitchLocked` 遍历全部 2,000 条历史 span，`taskProgress()` 对每个配额重复扫描 `_focusSessions`。
2. **未缓存的正则表达式与重复 URL 解析**：`ActivityTextNormalizer` 每次调用重新编译 6 个 `NSRegularExpression`；`PrivacyRedactor` 对干净的 OCR 文本无前置快检直接遍历 `range(of: .regularExpression)` 与 10 余条 ICU 正则；`SwitchClassifier` 对历史 span 重复执行 5 条标题正则、`URLComponents` 与项目 token 提取。
3. **SQLite 缺少关键索引与热路径重复查询**：`activity_sessions`（未关闭会话）、`activity_snapshots`（时间戳与层级）和 `activity_ocr_frames`（`created_at`）缺少索引，导致 `EXPLAIN QUERY PLAN` 出现 `SCAN activity_ocr_frames` / `SCAN activity_snapshots`；每次写事件/快照时重复执行 `currentOpenSessionIdLocked()`、3 路 `UNION ALL` 与两次 `fetchSessionSummaryLocked()`（单事件 8 次 JSON 解码）；`synthesizeSessionSummaryLocked` 全表扫描该会话所有事件逐行提取信号。
4. **采集与 OCR 瞬时内存尖峰**：`NativeScreenRecorder` 对 `2560px` 帧执行多遍 `CIContext`/`CGContext` 栅格化，且 Apple Vision OCR 直接输入 `2560px` 图像且外层缺少 `autoreleasepool`，导致 Espresso/Metal 瞬时缓冲区激增；浏览器 AppleScript 每 2 秒无缓存重新编译执行。
5. **HTTP 与 UI 无效刷新/全尺寸解码**：每 2 秒主动复制 `DayHelmDaySnapshot`；菜单栏 Popover 闭合时仍保持 1Hz 计时器失效重绘；历史会话视图将 `2560px` 快照全尺寸解码至内存（单张 ~16.4 MB）再缩放到 `184×112pt` 卡片。

## 候选方案

- **方案 A（仅降低采集与刷新频率）**：例如将轮询从 2s 放宽至 10s、关闭实时光谱更新或关闭 Vision OCR。代价：牺牲毫秒级切换与输入停顿响应精度，属于功能退化而非架构收敛。
- **方案 B（两阶段全链路性能收敛，保持功能与精度零退化）**：
  - **阶段 1（`DayHelmCore` 与 `ActivityDatabase`）**：预编译正则与保守子串快检；`SwitchClassifier` 有界记忆化缓存；`SpectrumBuilder` 线性有序检测与单次 `prepareSequence` 复用；`DayHelmEngine` 尾部逆序切片与单次会话聚合；`ActivityDatabase` 增补 4 条热查询索引、内存缓存活跃会话状态与 SQL `GROUP BY` 聚合摘要合成。
  - **阶段 2（`DayHelmCapture` 与 `DayHelmApp`）**：单次 `160×90` 视觉签名计算；Vision OCR 输入最长边降采样至 `1600px`（保留 `2560px` 热 JPEG 快照）并包裹 `autoreleasepool`；浏览器 AppleScript 编译与标题未变 `15s` TTL 缓存；HTTP 运行态快照按需懒生成；Popover 闭合时门控 1Hz 计时器；历史缩略图使用 `ImageIO` `kCGImageSourceThumbnailMaxPixelSize = 368` 解码。
  - **阶段 3（短命独立 OCR 子进程、采集内存收紧与零隐藏 UI 布局重绘）**：
    1. **短命无头 OCR 子进程（`DayHelm __ocr-worker`）**：在 `DayHelmEntry.main()` 最前沿拦截 `__ocr-worker` 参数（不初始化 `NSApplication`/AppKit），以 `stdin/stdout` JSON 行协议串行接收已落盘的 JPEG 路径，用 `ImageIO` 降采样解码为最长边 `1280px` `CGImage` 后运行 `VNRecognizeTextRequest`（`.accurate`、`usesLanguageCorrection = false`），每次请求后执行 `malloc_zone_pressure_relief(nil, 0)`，并在空闲 `15s` 或处理满 `10` 帧后自动退出，彻底释放 Vision/Espresso/CoreNLP 约 `110–130 MB` 私有脏内存与瞬时张量；当不在 `DayHelm` 主可执行文件内运行（如单元测试与 `DayHelmChecks`）时透明回退为同进程执行。
    2. **采集像素尺寸与显示枚举收敛**：`captureMainDisplayImage` / `captureActiveDisplayImage` 最大宽度由 `2560px` 收紧至 `1920px`；`[SCDisplay]` 缓存 `60s`（改用 `SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)` 避免每 2.5s 枚举 500+ `SCWindow`）；单显示器环境下跳过 `CGWindowListCopyWindowInfo`；`launchCaptureTask` 与 `processCapturedImage` 在 `await` OCR 前通过同步 `autoreleasepool` 释放 `CGImage` / `IOSurface` 缓冲区；非 `app_focus` 触发的次级/周期快照增设 `minNonFocusOCRIntervalSeconds = 25.0` 冷却时间（`app_focus` 与首帧始终立即 OCR）。
    3. **隐藏 UI 零布局重绘**：新增 `MenuBarPopoverHostView`，仅在菜单栏 Popover 打开时挂载 `MenuBarPopoverView`，闭合时从 SwiftUI `AttributeGraph` 彻底卸载；`DaySpectrumRibbonView` 改为单 `Canvas` 绘制（`O(1)` 视图节点替代 `O(N)` `ForEach` 矩形与 `.help`）；`HybridActivityCoordinator` 新增 `isRecorderWindowVisible`，移除启动时急切的 `refreshRecorderSessions()`，在 `isStarted && !isPopoverVisible && !isRecorderWindowVisible` 后台守护态下跳过 `@Published` UI 属性赋值、`SpectrumBuilder` 全量计算与 `refreshRecorderCountsAsync()`，并将 `today.json` 周期落盘间隔由 `10s` 放宽至 `30s`；当任一窗口打开时立即 `forceUI: true` 全量刷新。

## 选择

选择 **方案 B**，按阶段 1（Core & SQLite）与阶段 2（Capture, HTTP & UI）顺序推进落地，并以确定性测试与性能回归守卫锁定不变量。

## 理由

1. **关键常量与设计依据**：
   - **`SwitchClassifier` 有界记忆化缓存容量 = `4096`（易变标题归一化缓存 = `2048`）**：单日去重后的独立 `(appName, bundleId, windowTitle, url, redacted)` 组合通常在数百至两千条以内，4096 槽位可覆盖全天历史 span 而无需重复运行正则与 `URLComponents`，内存开销 `< 2 MB`，且硬上限防止长期运行无界增长。
   - **Vision OCR 子进程隔离 + `1280px` 缩略解码 + `usesLanguageCorrection = false`（热 JPEG 快照 `1920px`）**：实测 Apple Vision `.accurate` 4 语种识别在主进程内会通过 `dispatch_once` 永久驻留约 `110–130 MB` Espresso/CoreNLP 私有脏内存，并在推理期产生 `+90–140 MB` 峰值。改为短命无头子进程（空闲 `15s` 或满 `10` 帧退出）后，主进程稳态物理内存脱离 Vision 权重锁死；关闭 4 语种自然语言词典纠错（屏幕文本多为混排 UI、代码、SKU 与 URL）并从已落盘 JPEG 按 `1280px` 解码输入，可在不降级 `.accurate` 检测精度的前提下显著降低 OCR CPU 与峰值内存；同时 `1920px` 热快照较 `2560px` 减少 `44%` `IOSurface` 占用。
   - **非 `app_focus` OCR 冷却 = `25s` & `[SCDisplay]` 缓存 = `60s`**：切应用（`app_focus`）与首帧始终立即 OCR，保证上下文切换语义零丢失；同一应用内的次级/周期视觉变化（`click`、`typing_pause`、`visual_change`）以 `25s` 为最短 OCR 间隔（仍正常保存去重 JPEG 快照），避免高密度打字/滚动期间每 `4–12s` 重复跑 4 语种神经推理。`[SCDisplay]` 仅随显示器插拔变化，缓存 `60s` 并改用 `excludingDesktopWindows(true, onScreenWindowsOnly: false)` 可避免每 `2.5s` 枚举数百个 `SCWindow`；单显示器跳过 `CGWindowListCopyWindowInfo`。
   - **Popover 卸载 + 单 `Canvas` 光谱条 + 后台 UI 门控（`today.json` 落盘 `30s`）**：`MenuBarExtra(.window)` 在闭合时仍保留 `NSHostingView`，每次 `objectWillChange` 都会触发隐藏布局；通过 `MenuBarPopoverHostView` 卸载子视图、`DaySpectrumRibbonView` 单 `Canvas` 绘制与后台态跳过非必要 `@Published` 计算，彻底消除闭合态主线程 SwiftUI 布局样本。
   - **浏览器 AppleScript 标题未变缓存 TTL = `15s`**：前台应用 PID 或 AX 窗口标题变化时立即刷新；仅在标题完全未变（如同一标签页内 SPA 路由切换）时以 `15s` 为周期兜底重查 URL，将无谓的 AppleScript 编译与跨进程 IPC 开销降低约 `7.5×`。
   - **历史缩略图解码 `kCGImageSourceThumbnailMaxPixelSize = 368`**：对应历史详情卡片 `184×112pt` 在 `2×` Retina 下的精确像素上限（`184 × 2 = 368`），单张解码位图由 ~16.4 MB 降至 ~0.3 MB，杜绝多张快照浏览时的内存飙升。
2. **零行为退化**：所有正则快检与 SQL 聚合均以现有行为为真值基准，并通过完整单元测试与 `EXPLAIN QUERY PLAN` 断言验证等价性。

## 推翻条件

如果出现以下任一情况，需重开本决策：
1. `1280px` OCR 输入或关闭 `usesLanguageCorrection` 导致高分屏小字号或中文长句识别召回率明显下降并影响搜索可用性；
2. 短命 OCR 子进程在高频连续切窗下频繁冷启动反而推高总 CPU（可通过调整 `15s` 空闲超时或 `10` 帧上限重校准）；
3. 用户在固定标题的单页应用（SPA）内高频切换关键页面且 `15s` URL 刷新延迟导致配额或跑偏判定失准；
4. 实际使用中单日独立窗口上下文经常超过 `4096` 导致缓存频繁淘汰重算、CPU 回升；或
5. 后续剖析显示主要 CPU/内存热点已转移至其他未覆盖模块。
