# Flutter 原生端深度 Bug 审查与集中修复

日期：2026-09-07。范围：`matrixflow-native/`。审查基线：`e3856349f11fd06a44bff053c05406facc9c9e8b`。修复与报告纳入本轮收尾提交，下一轮按 [HANDOFF](HANDOFF.md) 定位并尝试解决 B01。

## 执行计划

1. 阅读 README、HANDOFF、ARCHITECTURE、DEVELOPMENT、CHANGELOG 与原生端说明；完整检查 Dart 源码、测试和 Android / Windows 宿主配置。
2. 对已确认的交互、异步、备份与数据完整性、AI 协议缺陷补充回归测试，集中修复。
3. 执行 Flutter 测试、静态分析及可行的 Android 构建验证；记录实际证据和实机复测边界。
4. 完成问题分级、触发步骤、修复位置、验证结果与剩余项；同步项目交接文档。

## 基线

- 工作区初始 clean；Flutter 3.31.0-1.0.pre.88 / Dart 3.8.0 开发版。
- `flutter test --reporter expanded`：20 项通过。
- 原测试均位于 `test/`；`integration_test/app_test.dart` 需要设备单独运行，不在上述 20 项内。

## 当前评估

已完成全部 13 个原有 Dart 源文件、已有测试、Android 主配置及 Windows runner / 构建配置的静态走查。以下将相关根因归纳为 **29 类已处理问题：P1 8 类、P2 19 类、P3 2 类**。这是本轮确认的问题集合，不代表能够证明工程不存在其他 Bug。

应用层修复已收敛，**64 项测试通过，`flutter analyze` 为 0 issues**。当前剩余工作主要是构建兼容性和真机验收，不建议继续无边界扩大代码改动。按用户最新要求，优先交付本报告，未关闭项单独列出。

- P1：可能丢失用户输入/数据、破坏导航或使核心功能不可用。
- P2：常用交互错误、状态不一致、异常处理或兼容性缺陷。
- P3：资源管理或较轻的体验问题。

## 已修复问题

下表代码路径均相对于 `matrixflow-native/lib/`。验证标记：**D** = `test/bug_regression_test.dart`；**A** = `test/ai_regression_test.dart`；**W** = `test/widget_regression_test.dart`；**S** = 源码/依赖源码确认，未单独注入对应故障。

| ID | 等级 | 触发方式与原问题 | 修复及定位 | 验证 |
|---|---|---|---|---|
| N01 | P1 | 本地任务缺少 id、字段类型错误或偏好值类型不符，`init()` 抛异常，首页一直加载 | `storage.dart:init` 分区、逐记录捕获；保留合法记录并提示；读取失败提供重试入口 | D |
| N02 | P2 | 首条任务有 boardId，但后续旧任务无 boardId，或任务指向已丢失的板，任务从界面消失 | 启动时检查每条任务，恢复到首个有效任务板 | D |
| N03 | P1 | 覆盖导入先替换 boards/tasks，随后解析 settings 失败，出现内存半更新 | `importData` 先完成解析及引用校验，再修改状态；拒绝未知版本；覆盖遇到非空孤儿引用整次拒绝 | D |
| N04 | P1 | 同一备份内部含重复 board/task id，原去重仅对比导入前集合 | 导入批内和现有数据分别去重，启动也去重 | D |
| N05 | P1 | 编组已有子任务的任务，原实现仅复制父标题，丢弃全部原子任务 | `groupTasks` 保留原子项、完成状态和截止日期；单层模型用“原任务 / 子项”保留归属；限制同板至少两项 | D |
| N06 | P2 | 开启父任务自动完成后，向已完成父任务追加未完成子项，父任务仍完成 | `appendSubtasks` 统一经过父子状态同步 | D |
| N07 | P3 | 切换任务板后重启，又回到第一个板 | 保存、恢复额外本地键 `matrixflow-active-board`，不修改备份格式 | D |
| N08 | P2 | 快速批量创建、AI 返回相同子项标题，原微秒/标题 hash id 可能重复 | 统一时间、递增序列与安全随机数生成 id；相同标题子项也有独立 id | D |
| N09 | P2 | 新增/编辑截止日期、调整阈值后需等一小时才升级；昨日深夜截止被算成“今天” | 增删改相关流程和前台恢复检查截止；标签按本地日历日期计算 | D/W；前台恢复接线 S |
| N10 | P2 | 在卡片上直接上滑，`Draggable` 抢占滚动 | `quadrant_pane.dart` 改为 `LongPressDraggable`；普通滑动滚动，长按拖拽；切板列表状态隔离、外层稳定任务 key | W |
| N11 | P2 | 点击“选择”后卡片没有选择回调，无法编组；返回键直接离开 | 接通主页→象限→卡片选择状态，选择与完成复选分离；`PopScope` 返回退出选择；切板清空选择 | W |
| N12 | P2 | 输入弹层外内两次加键盘高度；编辑弹层不可滚动，键盘遮挡确认按钮 | 输入只消费一次 inset；编辑/拆解弹层可滚动，补安全区；小高度矩阵允许整体滚动 | W |
| N13 | P2 | 长任务板名、半宽卡片多按钮、子项按钮、三协议长标签、固定宽 SnackBar 挤压小屏 | 标题独占可用行、操作区换行、板名省略、协议下拉、提示宽度随屏幕；保持四象限 2×2 | W（320px、中英日、1.5 倍字体） |
| N14 | P2 | 右下 FAB 遮住象限最后一张卡片底部操作 | 象限列表底部留出 80px 可滚动空间 | S |
| N15 | P2 | 设置为中文/日文但 Material 日期控件未接本地化；导入 2300 年日期后打开选择器断言 | `main.dart` 接 `flutter_localizations`；日期编辑初始选择限制在选择器范围，未确认前保留原截止值 | W；主入口接线 S |
| N16 | P3 | 重复打开标题/子项/日期编辑，临时控制器不释放；编辑期间任务更新后旧对象写回覆盖新状态 | 新增 `text_prompt.dart` 由路由持有控制器；任务编辑独立 State；保存时读取当前任务后仅更新编辑字段 | W/S |
| N17 | P1 | 单任务拆解中按返回，响应到达后 `finally pop()` 再次弹出主页；批量弹层关闭后 `setState` | 单/批量统一为有状态拆解弹层；关闭立即取消请求，检查 mounted/closed 后才应用结果 | W/A |
| N18 | P2 | AI 添加长期任务时先关闭输入页，再用该页 context 打开拆解弹层 | 输入页返回长期任务列表，由仍存活的主页打开下一弹层 | W |
| N19 | P2 | 桌面 AI 成功后 `_busy` 不清除，无法再次提交；等待时切板会写入另一板；继续编辑输入可能被清空 | `finally` 恢复状态；提交时快照任务板、AI 配置和设置；处理中输入只读；原板删除则保留输入报错 | W（连续提交、跨板、错误保留输入） |
| N20 | P2 | 长期任务拆解出的步骤被误判为分组；返回分组确认等同选择“拆开” | AI 结果新增内部 `isGrouped` 标记及旧响应兜底；返回取消整次审查并保留输入 | A/W；分组返回分支 S |
| N21 | P1 | AI 返回空数组、无效文本、空 choices 或部分非法条目，原流程可能当成功清空输入 | 协议层拒绝无效/不完整结果，UI 保留输入并允许重试；HTTP 错误只显示可理解消息与状态码 | A/W |
| N22 | P2 | 批量拆解改写 originalTitle、缺少部分结果时静默跳过，甚至仅应用一部分 | 提示词要求原样标题；先校验全部请求标题再应用，重新检查当前任务是否仍存在且可拆解 | A/S |
| N23 | P2 | 响应头和 body 各自 30 秒，合计可接近 60 秒；Future 超时没有终止底层 HTTP | `AIService._send` 使用完整响应的单一截止时间和 `AbortableRequest`；支持弹层取消，Store 释放客户端 | A（虚拟时钟、取消信号） |
| N24 | P2 | Anthropic 地址填 `/v1` 后实际请求 `/v1/v1/messages`，探活同样失败 | 统一 Anthropic 版本前缀；校验 URL、修剪密钥空白 | A |
| N25 | P2 | 请求声明 `json_object`，提示词却强制顶层 JSON 数组，协议要求冲突 | 分类/拆解统一请求 `{"tasks": [...]}`，继续兼容旧数组和围栏响应 | A + 原协议测试 |
| N26 | P1 | Android 导出未传 `bytes`，file_picker 8.3.7 直接抛错；取消保存又弹出包含整份备份的窗口 | 向系统保存器传 UTF-8 bytes；移动端由插件写入，桌面异步落盘；取消直接结束，错误用提示 | W + 插件本地源码 S |
| N27 | P2 | 文件选择器异常在 try 外；同步读文件阻塞 UI；覆盖后 AI 输入框显示旧配置 | 导入全链路捕获、异步读取并支持无 path 的 bytes；覆盖后同步控制器；防重入 | W |
| N28 | P1 | debug 可以联网，release 主清单缺少 INTERNET 权限，AI 在发布包不可用 | `android/app/src/main/AndroidManifest.xml` 显式添加 INTERNET | 清单 S；见构建边界 |
| N29 | P2 | SharedPreferences 写入 Future 被丢弃，失败可能未处理且用户无提示 | 存储写入串行化、捕获 false/异常、首页显示保存失败提示；提供 flush 供导入等待 | S；正常持久化往返 D |

## 已运行的验证

| 检查 | 结果与边界 |
|---|---|
| 修复前 `flutter test --reporter expanded` | 原有 20 项通过，说明原测试没有覆盖此次大部分问题 |
| 首批回归测试在修复前运行 | 7 项全部失败，分别复现启动、导入批内重复、覆盖半更新、编组丢子项、父状态、AI 空结果和范围归一化问题 |
| 修复后 `flutter test --no-pub --reporter expanded` | **64/64 通过**：原有 20 + 数据回归 13 + AI 回归 12 + 交互回归 19 |
| `flutter analyze --no-pub` | **No issues found** |
| Android debug 构建 | 成功生成 `build/app/outputs/flutter-apk/app-debug.apk`；构建出现本机 C:/D: 跨盘 Kotlin 增量缓存异常，编译器回退后成功 |
| Android release 构建 | 两次失败；第二次单独顺序构建仍失败，确认不是仅由并行验证造成，见 B01 |
| Windows release 构建 | 用户安装 C++ 工具链后重试成功，103.7 秒，产物 `build/windows/x64/runner/Release/matrixflow_native.exe` |
| Android 实机端到端 | 本轮未执行；已修正 `integration_test/app_test.dart` 输入选择器，不能把 widget 测试视为实机验收 |

原始日志保留在 `docs/native-tests-final.log`、`docs/native-analyze.log`、`docs/native-regression-before.log` 以及相应构建日志，均为本地忽略文件。测试使用构造数据及 mock AI，不读取或输出真实备份、用户 API 密钥。

## 未关闭项与工作量评估

### B01 · P1 · Android release 测试插件注册不一致（已复现）

- 命令：`flutter build apk --release --no-pub`。
- 错误：`GeneratedPluginRegistrant.java` 引用 `dev.flutter.plugins.integration_test.IntegrationTestPlugin`，release Java 编译找不到该包。
- 当前 SDK 为 **Flutter 3.31.0-1.0.pre.88，master 预发行版**；项目正确将 integration_test 声明在 dev_dependencies。SDK 生成插件注册与 Gradle 排除 dev 插件之间存在不一致，最终根因仍需进一步核实。
- 不把 integration_test 移入生产 dependencies，不手工修改自动生成的注册文件，也不修改全局 SDK 来掩盖错误。
- 预估：**中等，单独 30–90 分钟**定位/验证 SDK 或工程范围的兼容处理；升级 SDK 涉及面更大，应作为独立批次。此为经验估计，不是运行承诺。
- 影响：当前 debug 可构建，release 发布链路仍不通过；本轮不能交付已验证的发布包。

### B02 · Windows 构建环境复核（已关闭）

此前命令返回 `Unable to find suitable Visual Studio toolchain`。用户安装 C++ 工具链后，本轮重新执行 `flutter build windows --release --no-pub`，**编译成功**。仅验证构建，不宣称完成 Windows 窗口实机交互验收。

因此截至交付，**已确认但未修复的构建阻塞只有 B01 一项**；B03 是实机验证清单，不能计为新增确定 Bug。

### B03 · 实机验收（验证缺口，不冒充已确认 Bug）

建议 20–40 分钟完成一轮：

1. 360px 左右手机，系统字体正常/放大、竖屏/横屏：添加、编辑任务，键盘弹起后确认按钮可滚动到达；底部手势条不遮挡。
2. 同象限加入 15 条任务：轻滑滚动，长按跨象限拖动，右下最后一条可操作；点标题可编辑。
3. 选择两条任务并编组，检查原子任务、完成状态、截止日期仍在；按返回退出选择，切板清空选择。
4. AI 请求中按返回/下拉关闭、断网、服务端报错、连续提交；不能退出主页、吞掉输入或重复创建任务。使用用户自行配置的测试服务。
5. Android 系统文件选择器：成功导出、取消导出、导入合并/覆盖；退出重开后验证最后活动板及删空状态。
6. 中英日日期控件、今日/昨日截止、切后台跨日再恢复；验证真实 IME 和系统返回手势。

### 已知后续事项

- release 仍使用 debug 签名，图标/应用显示名仍为模板配置；属于既有打包待办，本轮未扩展到正式发布配置。
- SharedPreferences 多键写入仍不具备数据库事务保证；已捕获失败，但系统强杀/磁盘故障的跨键原子性与逐版迁移未实现。
- 原生导入仍没有 Web 的逐字段勾选预览；合并模式保留本地设置/AI 配置，为已有明确差异。
- 未做大规模任务压测、无障碍读屏全验收或第三方 AI 真实服务全协议实测。不存在可据此声称的“全 Bug 清零”。

## 兼容性与建议

保持纯本地架构、原有四个核心存储键和 ExportData v1；新增活动板键仅是本地 UI 元数据，内部 AI 分组标志不导出。新增 `flutter_localizations`，HTTP 最低约束提升到已解析安装的 1.6.0 以使用可取消请求；未批量升级其他依赖。

建议先用本轮代码进行实机复测，优先处理 B01。应用交互修复已经有回归保障，继续投入的主要收益来自真实设备反馈和发布链路收敛，而非继续无界静态扩改。

## 参考依据

- Android 主清单联网声明：[Flutter Networking](https://docs.flutter.dev/data-and-backend/networking)。
- 日期控件本地化接线：[Flutter 国际化文档](https://docs.flutter.dev/ui/internationalization)。
- Sheet 安全区参数：[showModalBottomSheet API](https://api.flutter.dev/flutter/material/showModalBottomSheet.html)。
- 请求取消能力：[Dart HTTP 官方包文档](https://pub.dev/packages/http)。
- 文件保存行为核对已安装 `file_picker 8.3.7/lib/src/file_picker_io.dart:140`；不能用当前新版文档替代旧版本实现证据。
