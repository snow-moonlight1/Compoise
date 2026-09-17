# 基础功能复审：WP20-N 至 WP28-P

复审日期：2026-09-16。代码基线：`main / 3a711c8`。范围：执行计划已登记完成的 **30 个子批次**，不含 UI 实验分支、WP10 及后续附加功能、WP29 托管服务。开工时工作区干净，无 Git remote。

**结论：基础功能尚未全部修好，不能按“V1.0 全部闭环”验收。** 主要业务实现已经存在，原有 255 项测试与双端构建确实通过；但复审发现 **22 项问题（9 项 P1、13 项 P2）**，包括确定的数据覆盖、损坏备份导入丢数据，以及尚未接入系统的 Windows 托盘/全局热键。新增 21 个针对性探针均在预期的业务断言处失败，说明原有测试没有覆盖这些场景；不代表随机抽样的 21 个功能全部失败。

本轮只复审、补充证据和更正交接入口，未修改产品实现、未提交 Git、未发布安装包、未读取或覆盖用户真实待办/密钥。所有探针使用 SharedPreferences mock、合成任务与假插件，不访问商业 AI。

## 1. 实际验证与证据边界

在 `matrixflow-native/`，使用 `D:\Dev_SDKs\Flutter_SDK\bin\flutter.bat`：

| 命令 | 结果 | 能证明什么 |
|---|---|---|
| `flutter test --no-pub` | 255/255 通过 | 原有单元/Widget 用例通过 |
| `flutter analyze --no-pub` | 0 issues | 原有实现及本轮探针静态检查通过 |
| `flutter build apk --release --no-pub` | 成功，24.6 MB | 当前本机 Android Release 可编译 |
| `flutter build windows --release --no-pub` | 成功 | 当前本机 Windows Release 可编译 |
| `flutter test --no-pub test/review/wp28_review_probe.dart --reporter expanded` | 21 个业务断言失败，退出码 1 | 以下具体反例可复现 |

探针文件：[wp28_review_probe.dart](../matrixflow-native/test/review/wp28_review_probe.dart)。其文件名有意不以 `_test.dart` 结尾，默认测试集仍是原来的 255 项；必须显式运行。修复时应将相关探针整理成正常回归测试，而不是删除断言或把错误行为改成预期。运行后根目录的 `review-repro.log`、`review-flutter-test.log`、`review-analyze.log`、`review-android-build.log`、`review-windows-build.log` 为本机忽略日志，不纳入提交。

未做：真实 Android/Windows 安装与输入设备操作、系统通知实际弹出/冷启动/重启/休眠、真实供应商 Key 请求、正式签名与原位升级、干净 Windows 环境启动、远端 CI、公开仓库/Release/商店提交。Widget 尺寸/键盘/IME 模拟不冒充实机验收；插件探针证明调用链问题，不声称观察了系统横幅。

## 2. 优先处理的问题

### F01 · P1 · 切换宽屏详情会把任务 A 的字段写入任务 B

- 范围：WP04、WP12-S、WP07、WP13-A、WP22。
- 位置：`lib/screens/matrix_screen.dart:345`，`screens/search_screen.dart:131`，`screens/completed_screen.dart:131`；`widgets/task_detail_panel.dart:62–98,188–230`。
- 复现：宽屏打开 Alpha，再直接点 Beta，点击保存。**Beta 的标题变成 Alpha**（R01）；备注、象限、日期和子项也使用同一批旧草稿字段，存在同样风险。
- 根因：三个入口都不以 taskId 给详情 State 分配身份；State 的 `late final` 控制器/子项/初始快照不随 `widget.task` 更新。保存却使用新 taskId。
- 修复方向：切换任务之前处理脏草稿，再明确重建/更新编辑状态；仅加 Key 虽能隔离任务，但仍须补切换时的草稿保护。矩阵、搜索、已完成三个入口一并回归。

### F02 · P1 · 损坏备份被静默跳过后仍可覆盖清空原数据

- 范围：WP11。
- 位置：`lib/data_migrations.dart:101–117`，`lib/storage.dart:895–945`；设置导入只捕获抛出的异常，未展示 `migration.warnings`。
- 复现：现有一个合法任务，覆盖导入含合法 boards、但任务缺少必需 id 的 v2 文件。**没有拒绝导入，现有任务变成空列表**（R06）。子项结构损坏导致整个父任务解析失败时也进入静默跳过路径。
- 根因：迁移器把记录解析失败转换成 warnings，Store 把残缺结果当完整候选覆盖。与计划“损坏拒绝、失败不覆盖旧数据”不符。
- 修复方向：覆盖模式在不可恢复记录错误时整份拒绝；如要支持抢救导入，另做明确预览和保留原数据的路径，不能静默执行残缺覆盖。

### F03 · P1 · 详情旧快照会撤回面板外已发生的子项操作

- 范围：WP04、WP20、WP27、WP25。
- 位置：`lib/widgets/task_detail_panel.dart:76–78,207–228`。
- 复现：打开父任务详情，在旁边矩阵完成该任务，再在详情保存。**旧草稿中的子项未完成状态覆盖最新完成状态**（R11）。同理，打开期间 AI 追加/其他入口新增的子项会被旧列表覆盖。
- 根因：保存虽重新查询 current，但无条件替换全部 subtasks，没有修订号、冲突检测或字段级合并。
- 修复方向：区分用户实际修改字段与外部更新；发生冲突时刷新或提示，禁止整份陈旧子项列表覆盖。

### F04 · P1 · Windows 托盘、关闭拦截和全局热键仍是状态模拟

- 范围：WP26-B-N-Windows，影响 WP25-N-Windows。
- 位置：`lib/services/desktop_shell_service.dart:38–119`，`main.dart:13`，`screens/matrix_screen.dart:120–122`，`screens/settings_screen.dart:800–850`。
- 证据：服务只修改 `_isTrayInitialized`、`_isWindowVisible`、快捷键字符串；`registerGlobalHotkey` 连传入的 `onTrigger` 都未保存。没有托盘插件/FFI/MethodChannel 系统操作；没有产品调用 `handleWindowCloseRequest` 或 `registerGlobalHotkey`。Windows runner 仍是常规销毁退出流程，恢复回调仅 `setState`。设置显示全局快捷键，但不可配置。
- 影响：启用“关闭到托盘”并不会让系统关闭按钮执行该行为，系统全局唤起无实现；不能以 mock 布尔值测试宣称托盘保活完成，也不能保证依赖它的提醒。
- 修复方向：实际接入窗口、托盘菜单和 OS 热键，启动/设置变更/退出统一管理；真实 Release 验收关闭、恢复、冲突和进程退出。

### F05 · P1 · 首次设置提醒没有请求通知权限，也没有拒绝反馈

- 范围：WP25-N-Android。
- 位置：`lib/widgets/input_sheet.dart:323–374`，`widgets/task_detail_panel.dart:286–340,850–913`；权限申请仅见 `screens/settings_screen.dart:1229`。
- 复现：模拟未授权，详情设置“明天 9 点”并保存。任务保留提醒时间，但 **requestPermission 调用次数为 0**（R20）。父项、子项选择器和新建路径都未接权限服务。
- 影响：新安装用户按正常任务流程设置提醒，在需运行时授权的 Android 上可能完全收不到通知，却看到已设置闹钟的图标。
- 修复方向：用户首次选提醒时申请；拒绝仍保存任务并在入口明确提示不可用；精确权限不足提示可能延迟。导入只保存字段，不应偷偷弹授权。

### F06 · P1 · 异步排程与取消无序，删除后可重新排回提醒

- 范围：WP25、WP02、WP24、WP11。
- 位置：`lib/services/reminder_service.dart:581–626`；Store 中的 schedule/cancel 调用均未串行化，覆盖导入 `storage.dart:935,942` 也未等待取消完成。
- 复现：Android `scheduleReminder` 等待精确权限检查时，执行 `cancelReminder`，随后完成权限检查。**取消之后仍调用 zonedSchedule**（R14，模拟 MethodChannel 延迟，运行真实生产调度方法）。
- 影响：快速删除、完成、改期、清空/覆盖导入均可能让旧异步请求最后落地；内存 mock 的立即执行掩盖了顺序问题。
- 修复方向：按稳定通知 ID 使用修订号/失效令牌和串行调度；覆盖导入先完成取消再重新排程。覆盖 schedule→cancel、旧改期→新改期、cancelAll→重排。

### F07 · P2 · 删除子任务没有注销旧通知

- 范围：WP25、WP04。
- 位置：`lib/storage.dart:416–446`。
- 复现：存在未来提醒的子项，保存去掉该子项的父任务。**旧 notification ID 仍在调度表**（R04）。
- 根因：只遍历 updated.subtasks，不比较 oldTask.subtasks 中已删除的 ID。详情提前修改原对象还会破坏旧集合，修复时需同时消除该副作用。
- 修复方向：保存前获取真正旧快照，取消所有删除的子项通知，再排程保留项。

### F08 · P1 · 通知初始化与 Store 启动并行，恢复排程可能直接丢弃

- 范围：WP25 Android/Windows。
- 位置：`lib/main.dart:11–20`，`lib/storage.dart:163`，`lib/services/reminder_service.dart:679–680`。
- 复现：让插件 initialize 晚于 Store 的恢复请求完成。**初始化完成后仍未排程任何提醒**（R12）。
- 根因：main 不等待服务初始化；`rescheduleAllFuture` 遇到 `_initialized == false` 直接 return，无排队或重试。
- 影响：应用启动时的恢复动作依赖时序，尤其是需要重建的 Windows 进程内计时器。不是断言所有系统已存排程都会丢失，而是恢复链路确定可能不执行。
- 修复方向：初始化完成后才启动恢复，或服务内部等待同一个初始化 Future；失败状态可见并支持重试。

### F09 · P2 · 通知冷启动没有读取启动载荷

- 范围：WP25 Android/Windows。
- 位置：`lib/services/reminder_service.dart:386–427`，`lib/main.dart:14–18`。
- 证据：全库没有 `getNotificationAppLaunchDetails`；只注册运行期间响应回调，MatrixHome 加载后才挂接导航。插件 19.5.0 源码明确将“通知启动应用”的处理指向 launch-details API。
- 影响：后台已存在进程的模拟点击通过，不证明从完全退出状态点通知会定位原任务；冷启动缺少载荷缓存和 ready 后消费。
- 修复方向：初始化读取 launch details，排队到 Store/导航 ready；避免 main 的回调读取同一个回调属性形成自引用转发；把 subtaskId 传给详情高亮入口。
- 依据：[插件 19.5.0 官方说明](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0)。未做 OS 冷启动实测。

### F10 · P2 · Windows 同一提醒同时使用 Timer 与原生排程

- 范围：WP25-N-Windows。
- 位置：`lib/services/reminder_service.dart:540–578`。
- 复现：原生 zonedSchedule 成功，推进时间到期。**仍调用一次 show，合计发起两条送达路径**（R13）。本地锁定版本的 Windows 插件已有原生排程实现，不是必定不支持。
- 影响：系统支持原生排程时存在重复/覆盖通知和重复提示风险；实际横幅表现仍需实机验证。当前“原生不支持时备用”的注释与无条件创建 Timer 的代码不符。
- 修复方向：明确选择一种送达机制；确实失败才使用备用机制，并保证两者不会同时激活，改期和取消能覆盖原生待发通知。

### F11 · P2 · Android 排程失败会立即弹出未来提醒

- 范围：WP25-N-Android。
- 位置：`lib/services/reminder_service.dart:603–626`。
- 复现：合成明天的提醒，精确/非精确排程都失败。**立即调用 show**（R21）。
- 影响：原计划明天提醒却今天弹出，之后无可靠未来排程，用户还看不到失败状态。
- 修复方向：保留时间和失败状态，提示无法安排/允许重试；不能用立即通知伪装排程成功。

### F12 · P2 · 纯文本草稿按返回会静默丢失

- 范围：WP04、WP13-A、WP26-A。
- 位置：`lib/widgets/task_detail_panel.dart:651–661,744–778`；宽屏 Esc 路径 `screens/matrix_screen.dart:275–276`。
- 复现：手机详情只改标题，再触发 Navigator.maybePop。**面板直接关闭，没有丢弃确认**（R10）。
- 根因：TextField 控制器改变没有触发父 State 重建，PopScope.canPop 保留修改前 true。宽屏 Esc/切板/尺寸切换也直接移除详情，未统一经过 `_attemptClose`。
- 修复方向：文本修改同步更新 dirty 导航状态；返回、遮罩、Esc、切任务/板、尺寸变换统一保留/确认草稿。单测“点面板 X”不能覆盖所有退出入口。

### F13 · P2 · 详情修改象限不置顶

- 范围：WP05。
- 位置：`lib/widgets/task_detail_panel.dart:221–231`，`lib/storage.dart:354–360,409–413`。
- 复现：目标象限已有 Existing，详情将 Moving 移入后，**Existing 仍在 Moving 前面**（R02）。
- 根因：详情先修改 `widget.task.quadrant`，而该对象即 Store 的 oldTask；Store 比较时已经看不到象限变化，跳过置顶。
- 修复方向：详情不直接写 Store 对象，统一发送独立更新；同时回归手动 urgencyMode 和子项时间戳差异检测。

### F14 · P2 · 完成历史在多个真实操作路径中漏记/丢失

- 范围：WP27-B、WP20、WP04。
- 位置：`lib/widgets/task_card.dart:367–369`，`lib/storage.dart:370–377,553–565,790–806`，`lib/task_stats.dart:165–168,206–221`。
- R03：卡片直接勾选子项，**completed=true 但 completedAt=null**，因为先修改原对象再送入 updateTask，旧/新已不可区分。详情保存也先改原对象。
- R07：已完成任务编组成为子项，**原 completedAt 变 null**，复制字段遗漏。
- R08：未完成父任务里的已完成子项，**日分布子项计数为 0**，因为先按父 completed 过滤整份输入。
- R09（Store 边界）：历史完成任务没有时间，再调用 setParentCompleted(true)，**凭空补了现在的完成时间**，不符合重复设置不重记、历史未知不伪造的契约。
- 修复方向：在 Store 统一完成状态转换，保留真实前值，编组完整迁移字段；父/子统计分别过滤，历史 unknown 保持 unknown。不要只测试传入深拷贝对象的 updateTask。

### F15 · P2 · 撤销会覆盖后续子项完成命令

- 范围：WP24。
- 位置：`lib/storage.dart:634–651,705–716`。
- 复现：父任务完成生成撤销快照，之后取消再完成一个子项，点击旧撤销。**旧撤销仍被接受，回滚后续完成状态**（R05）。
- 根因：只核对标题、象限和 boardEpoch，没有任务命令修订号。boardEpoch 对清空/覆盖导入有作用，但不能识别普通后续修改。
- 修复方向：记录任务修订或核对命令执行后的状态；后续操作冲突时拒绝旧撤销，同时保持只恢复相关任务、不能复活已清空板的现有保护。

### F16 · P2 · 模型发现过程中切服务商导致持续加载

- 范围：WP01。
- 位置：`lib/screens/settings_screen.dart:59–68,91,115,137`。
- 复现：模型列表请求未返回时切服务商，旧请求完成。**刷新按钮仍不存在，loading 不复位**（R15）。
- 根因：切换取消请求但未重置 `_fetchingModels`；取消响应在 try/catch 内直接 return，自动触发又被 busy 门禁挡住。
- 修复方向：切换重置状态；使用请求代次统一收尾，保证旧请求不能复位/覆盖新请求。顺带覆盖同服务商换 Key/Base URL/协议、手选模型期间迟到返回。

### F17 · P2 · 自定义协议思考开关被隐藏

- 范围：WP01，既有三协议/思考契约回归。
- 位置：`lib/ai_presets.dart:75–86`，`lib/screens/settings_screen.dart:507`。
- 复现：Custom + Anthropic 配置，**设置中找不到 thinking-switch**（R16）；Responses 同样依赖 custom。
- 根因：显示完全由 preset.supportsThinking 决定，custom 固定 false，但服务层仍读取 enableThinking。
- 修复方向：保留原协议思考控制或按所选协议显示能力；从 DeepSeek 切换继承的状态也应可见、可改。此问题不需要真实 Key 即可证实；没有把用户此前正常的 custom API 泛化判为不可用。

### F18 · P2 · 大字号聚焦页下方卡片溢出

- 范围：WP08-T、WP23。
- 位置：`lib/widgets/quadrant_focus_view.dart:86–89,187`。
- 复现：360×800 dp、中文、系统 2.0×应用大字 1.16（合计 2.32）。**三张收起卡各向下溢出 42 px**（R17）。
- 根因：高度封顶 78，内部标题/数量布局不随 TextScaler 增高。
- 修复方向：允许内容驱动高度或改为适应窄屏的大字布局；不能关闭系统文字缩放来掩盖。补 360/390/412 与横屏检查。

### F19 · P2 · 完成复选框的实际热区没有达到 48 dp

- 范围：WP03、WP20。
- 位置：`lib/widgets/task_card.dart:164–188`。
- 复现：点击复选框中心向右 18 dp，仍在外层 48 dp 范围内。**没有完成任务，而是触发行正文编辑**（R18）。
- 根因：48×48 只是布局容器，点击处理仍在 shrinkWrap 的 20×20 Checkbox；父 InkWell 接走空白部分。
- 修复方向：把独立完成手势覆盖整个 48 dp 区域，避免向行编辑冒泡；子项 28 dp 的热区也应按触摸要求检查。

### F20 · P2 · 命令面板 Enter 不区分输入法组词

- 范围：WP26-A。
- 位置：`lib/widgets/command_palette.dart:268–283`。
- 复现：TextEditingValue 带有效 composing 区间时按 Enter，**面板关闭并执行命令**（R19）。
- 根因：KeyboardListener 无条件把 Enter 当 confirmSelection，没有 composing 判断。
- 修复方向：组词状态下 Enter/方向键交给输入法；合成用例证明缺少门禁，仍需真实 Windows 中文 IME 验收。

### F21 · P1 · Android 更换 applicationId，未闭环旧版数据迁移

- 范围：WP28-B。
- 位置：`matrixflow-native/android/app/build.gradle.kts:41`；历史 `66b4092~1` 同文件。
- 证据：旧值 `com.matrixflow.matrixflow_native`，新值 `com.matrixflow.app`。这会成为不同应用/数据沙箱，不能用“新 APK 构建成功”证明“旧版原位升级保留任务”。没有实现跨应用数据迁移。
- 修复方向：确定最终包名策略；继续旧 ID 才能走同应用升级，若有意更名，则明确旧版导出→新版导入、签名和版本路线，验证后再标迁移完成。不能指导用户先卸载旧版。
- 依据：[Android 应用标识说明](https://developer.android.com/build/configure-app-module)、[应用签名与更新](https://developer.android.com/studio/publish/app-signing)。本轮未操作真实安装。

### F22 · P1 · 发布 CI 缺签名仍自动公开 debug 签名 APK

- 范围：WP28-B/P。
- 位置：`.github/workflows/release.yml:35–46,149–158`，`matrixflow-native/android/app/build.gradle.kts:69–76`。
- 证据：没有 ANDROID_KEYSTORE_BASE64 时仅打印 fallback，仍继续编译；tag 路径发布 `draft:false, prerelease:false`。正式发行没有签名就绪门禁。
- 影响：一旦配置 remote 并推 tag，测试签名包可被作为正式版本公开；临时 runner 的 debug keystore/后续正式证书不能保证兼容升级。当前无 remote，本轮没有实际发生公开发布。
- 修复方向：允许本地测试构建回退，但正式发布缺凭据必须失败；校验证书身份、版本/tag 对应、产物可追溯性，审核后再发布。

## 3. 逐包覆盖表

“主体存在”表示已检查实现及相关原有用例，没有在本轮发现该包独有的新阻断；不是宣称全部设备/边界均通过。共享缺陷按关联包列出，不重复计数。

| 子批次 | 本轮核查结果 |
|---|---|
| WP20-N | 完成/选择/展开/删除线主体存在；完成热区 F19、子项完成历史 F14；外部编辑一致性 F03 |
| WP21-N | q1–q4 维度名称、字典及 AI 分类维度主体存在；原有测试通过；真实模型分类未测 |
| WP03-N | 十字/轻量行实现存在；真实完成热区 F19；大字/实机验收不完整 |
| WP04-N | 详情主体存在，但 F01/F03/F12/F13 阻止验收；不能按“编辑完成”关闭 |
| WP23-N | 主象限+下方三卡存在；F18。滚动缓存字段有清理但无写入/接线，恢复位置仍需专项补验 |
| WP12-S-N | 本地父子搜索与过滤主体存在；宽屏详情共用 F01；千条性能和真实中文 IME 未实测 |
| WP22-A-N | 普通/AI 新建截止日期快照主体存在，子项不强行继承；AI 在途清板 epoch 已接入 |
| WP22-B-N | 父子日期独立编辑存在；详情共用 F01/F03/F12；设备日期键盘待验 |
| WP05-N | Store.moveTask 置顶主体存在，但详情入口不置顶 F13；物理拖放待验 |
| WP06-N | 首次设备语言优先列表、缺省回退、已选语言保留主体存在，原有测试通过 |
| WP02-N | clearBoard 当前板范围、包含隐藏完成项、epoch 阻止新增 AI 复活主体存在；通知取消竞态 F06 |
| WP01-N | 预设/动态发现/手填存在；F16/F17；真实三家发现接口与思考能力不能只由 mock 宣称核验完成 |
| WP07-N | 当前/全部板已完成查询与级联恢复存在；宽屏详情 F01；历史视图依赖 F14 |
| WP08-V-N | 宫格/列表共用 Store 和 TaskCard；保留模式主体存在；继承共用任务行/详情缺陷 |
| WP08-T-N | 字号和系统缩放组合、字体栈/持久化存在；F18 推翻“所有界面大字已验收” |
| WP24-N | 双向滑动、5 秒 SnackBar、删除快照、清空 epoch 防复活存在；普通后续命令冲突 F15 |
| WP26-A-N | 应用内面板和按钮/快捷键存在；IME F20；Esc 草稿保护 F12 |
| WP26-B-N-Windows | **系统能力未接入，不能算完成**，见 F04 |
| WP27-A-N | 当前父/子计数分开、隐藏不改统计、空板 0% 主体存在；逾期跨日刷新仍需设备检查 |
| WP11-N | v1/v2、未知版本门禁、字段往返主体存在；损坏覆盖 F02 是基础数据安全缺陷 |
| WP22-C-N | calendarDaysLeft 用本地日期映射 UTC 日序、auto/manual/阈值主体存在；编辑变化检测 F13；午夜常驻刷新待验 |
| WP13-A-N | 纯文本备注、父子搜索和 v2 字段主体存在；详情状态和草稿 F01/F03/F12 |
| WP25-R | 设计文档存在，但写“托盘已实现”不符合代码 F04；设计约定不等于真实插件验收 |
| WP25-N-Android | 清单/插件/字段存在；F05/F06/F07/F08/F09/F11，不能验收为可靠提醒 |
| WP25-N-Windows | Toast 适配和 Timer 存在；F04/F06/F07/F08/F09/F10，不能验收为可靠托盘提醒 |
| WP27-B-N | 时间戳/趋势页面存在；四种完成历史反例 F14 |
| WP09-N | 五页教程、跳过/完成标记、设置重开主体存在；教程描述依赖尚未修好的交互，真实新装/返回待验 |
| WP28-R | 准备文档存在；依赖清单只列主要项，不支持“全量合规审查已完成”结论；来源/渠道证据仍需补齐 |
| WP28-B | 本机双端 Release 已重新构建通过；F21/F22；旧版升级、干净机器安装、正式签名未验 |
| WP28-P | LICENSE/README/隐私/发布说明/商店文案模板存在；**仅准备产物，不是实际发布完成**；无 remote/目标账户/商店记录 |

## 4. 其他明确的验收缺口（不混入 22 个缺陷计数）

- **发行状态表述失真**：HANDOFF/计划宣称“全量闭环”，正文同时承认未发布。WP28-P 按原计划缺账户时可以交付准备产物，但必须列出缺项。当前商店截图文档是 5 张截图的制作规范，不是已经交付的 5 张截图；隐私政策与 release notes 使用 `github.com/matrixflow/matrixflow`，本仓库没有相应 remote 证据，不能当作已确定渠道。
- **隐私表述需校正**：备份包含明文 API Key，隐私政策备份段没有说明；“安全明文”“encrypted or sandboxed”表述易造成误解。自定义地址代码没有强制 HTTPS，也不能笼统保证所有请求均到“官方 HTTPS 接口”。这是代码与文案的一致性检查，不是本轮法律合规认证。
- **模型与通知研究证据不足**：AI_PROVIDER_PRESETS 的接口格式仍需用官方版本文档/受控真实响应核验；本轮没有使用用户密钥，不声称三家连通。提醒设计写了 TIMEZONE_CHANGED/TIME_SET 与读任务库恢复，但实际 BootReceiver 为插件实现，清单不包含这两个 action；`reminderTimezone` 只有父任务字段、未在 UI 写入。应明确采用固定时刻还是随本地时区重算，分别验收。
- **日期边界**：截止日可选到 2200，而提醒 picker 上界是当前年+5；以超上界 deadline 作为 initialDate 只做下界截断，仍可能触发日期选择器断言。这一静态边界尚未补独立探针，应随日期修复验证。
- **聚焦/导航一致性**：`_focusScrollOffsets` 未实际记录/传递；菜单切板会清理 focus，命令面板/通知切板直接调用 Store，没有同一套页面状态清理。需要补滚动恢复、跨板后旧详情/聚焦状态测试。
- **减少动画/触摸细节**：Dismissible 读取系统减少动画，但外层 StaggerIn 始终延迟渐入；计划要求的减少动画设置没有完整接线。子项展开后仍保留行内添加框，与计划“控件集中详情”的约定有差异，后续可由用户决定是否接受。
- **文档基线漂移**：AGENTS 仍写 WP03 下一包/77 项，ARCHITECTURE 多处仍为早期 Web/v1/80 项描述，计划首页混杂多个历史基线。复审入口已加更正，后续修复收尾须统一当前事实，不改写 CHANGELOG 历史。

## 5. 建议修复顺序与验收门槛

1. **先数据安全**：F01/F02/F03；详情不可变草稿、切换/外部更新冲突、损坏覆盖整份拒绝。保留当前数据，并在合成数据上验证。
2. **再提醒与系统能力**：真正实现 F04；F05/F06/F07/F08/F09/F10/F11 作为完整生命周期处理，不能只修 mock。分别验 Android/Windows 新设→改期→完成/删除→撤销→清空→导入→冷启动。
3. **完成日常交互与历史一致性**：F12–F20。把相关探针迁入默认回归集；Windows 鼠标/IME/缩放、Android 触摸/软键盘分开记录。
4. **最后恢复发行验收**：F21/F22、正式包名/签名/升级路线、干净机器启动、真实素材和目标账户。未授权/未具备的渠道维持“待发布”，不能把模板完成写成上线。

修复分成小批串行执行，共享 Store/详情/模型不要多人同时改。每批通过原有回归、对应探针和 analyze；插件/打包变化后重建双端。**在数据安全和提醒基础闭环前，不建议接着推进 UI 实验或新增付费/同步功能。**

## 6. 2026-09-16 修复状态（追加，不改写上文原始发现）

默认回归现为 `flutter test --no-pub` **280** 项（原 255 + `test/foundation_regression_test.dart` 25 项）。原探针文件仍保留为历史反例，不以 `_test.dart` 结尾。

| 编号 | 状态 | 回归证据 | 剩余验证 |
|---|---|---|---|
| F01 | 已修并验证 | foundation F01/R01、脏草稿切任务 | 实机宽屏点选 |
| F02 | 已修并验证 | F02/R06、损坏 merge | 实机文件选择器导入 |
| F03 | 已修并验证 | F03/R11、外部追加子项 | — |
| F04 | 代码已修待实测 | F04 热键回调与 closeToTray 拦截；已接 window_manager / tray_manager / hotkey_manager | 干净 Windows：关闭到托盘、托盘菜单、恢复、退出、全局热键冲突 |
| F05 | 已修并验证 | F05/R20 | 新装 Android 拒绝/允许权限 |
| F06 | 已修并验证 | F06/R14 | 真机快速删改期 |
| F07 | 已修并验证 | F07/R04 | — |
| F08 | 已修并验证 | F08/R12 | 冷启动恢复 Windows Timer |
| F09 | 代码已修待实测 | 初始化读取 launch details | 完全退出后点通知定位任务 |
| F10 | 已修并验证 | F10/R13 | 实机横幅是否只出现一次 |
| F11 | 已修并验证 | F11/R21 | — |
| F12 | 已修并验证 | F12/R10、脏草稿切任务 | 实机返回/Esc/改窗口尺寸 |
| F13 | 已修并验证 | F13/R02 | — |
| F14 | 已修并验证 | F14/R03/R07/R08/R09 | — |
| F15 | 已修并验证 | F15/R05 | — |
| F16 | 已修并验证 | F16/R15 | — |
| F17 | 已修并验证 | F17/R16 | — |
| F18 | 已修并验证 | F18/R17 | 360/390/412 与横屏实机 |
| F19 | 已修并验证 | F19/R18 | Android 触摸 |
| F20 | 已修并验证 | F20/R19 | 真实 Windows 中文 IME |
| F21 | 方案已写，待用户决定 | [ANDROID_PACKAGE_MIGRATION.md](ANDROID_PACKAGE_MIGRATION.md) | 旧包名原位升级 vs 双包导出导入 |
| F22 | 已修并验证（配置） | CI 缺签名即失败；本地无 CI 仍可 debug 回退 | 正式证书与 tag 发布（当前无 remote） |

## 7. 2026-09-16 二次复审更正（保留上述原始记录）

第 6 节的部分关闭结论被新反例推翻。默认 280/280、analyze 0 issues 复验通过，但新增 7 个业务反例均失败；F06/F09/F11/F12/F16/F19 仍未完整修复。尤其冷启动会在 main 的自引用通知回调中 Stack Overflow，不能仅登记为“代码已修待实测”。

完整发现、逐项状态、验证边界及返修要求见 [二次复审报告](FOUNDATION_SECOND_REVIEW_2026-09-16.md)。新探针为 `matrixflow-native/test/review/foundation_second_review_probe.dart`，合成数据、显式运行、不改变默认测试数量。本轮仅复审及补证，未改产品实现或提交 Git。
