# WP17-R 系统笔记待办导入 · 可行性研究

基线：`main / 45cd517`（研究分支 `wp17r-notes-import-research`）。本轮**只研究，不改产品代码**：`lib/`、`android/`、`test/` 零改动。

研究边界（见[工作包状态](../../ROADMAP.md)）：不读取私有数据库、不使用需要 root 的数据、不做无障碍或屏幕抓取；只做包与公开接口的元数据检查，以及合成样例。

## 先看结论

1. **没有稳定的公开接口可直接读取系统笔记待办库。** 小米笔记（`com.miui.notes` 2.4.3.3）的已识别跨应用入口由 `com.miui.notes.permission.ACCESS_NOTE` 保护，该权限在实测机上登记为 `prot=signature|privileged`，普通第三方应用无法取得。待办数据提供者 `com.miui.todo.provider` 在清单里没有声明权限门禁，但属于未公开实现，没有兼容性契约；Android 16 的 AppFunctions 通道也受 `EXECUTE_APP_FUNCTIONS`（实测 `prot=internal|privileged`）限制。
2. **单篇笔记的手动文本分享有官方说明，待办分享仍未证实。** [小米支持页](https://www.mi.com/global/support/faq/details/KA-559533/)列出“分享笔记为文本”；[小米设备手册](https://ams-go.buy.mi.com/uk/servicecenter/file/POCO_C40_User_Guide___uk?binaryId=204632&namespaceId=2&publicationId=204657)把笔记分享和待办清单分开描述。Android 可接收 `ACTION_SEND text/plain`，但实测机上的小米待办能否分享、能否带出完成态和提醒，仍无证据。本仓库已有逐行转待办逻辑（`lib/widgets/input_sheet.dart`）和批量落库入口（`Store.addTasks`）。
3. **通用文件选择可做，小米待办批量文本导出未证实。** Android 的 SAF（`ACTION_OPEN_DOCUMENT`）在用户选取文件后授予读取权限，必要时可持久化。上述小米支持页虽然以“导出所有内容到 txt”为标题，正文实际列的是逐篇复制、逐篇分享以及系统备份；它没有提供待办批量导出为可解析文本的证据。现有 `file_picker` 与备份导入门禁也不能证明笔记导入已可用。
4. **剪贴板不能作为后台通道。** Android 10+ 剪贴板读取仅限前台聚焦应用，Android 12+ 读取粘贴会弹 toast。可作为“用户显式点粘贴”使用，不能做静默桥接。
5. **先做真机分享探针。** 还需验证小米笔记分享出的内容形态（纯文本、图片或文件）、完成态和日期是否保留，以及待办与普通笔记是否区分。判定标准和步骤见 [真机探针协议](probe-protocol.md)。

**产品判断：不按“系统待办导入”直接排实现包。** 自动读取、批量迁移与保留完整待办结构都缺少可依赖的公开接口。若仍希望支持手动迁移，先按 [真机探针协议](probe-protocol.md)验证待办页能否分享文本；只有实际拿到可用内容，才评估一个明确标注数据损失的“用户主动分享文本导入”。如果待办只能分享图片或无法分享，结束小米专属适配，通用粘贴/文本文件输入可以独立于 WP17 评估。

## Android 入口盘点

| 入口 | 方向 | 需要的新权限 | 可行性 | 证据 |
|---|---|---|---|---|
| `ACTION_SEND` / `SEND_MULTIPLE` `text/plain` | 笔记 → 我们 | 无（清单 intent-filter + `exported=true`） | **Android 可接收；小米分享内容待实测** | 官方接收文档；实测机有 101 个接收方，含 HyperOS 自身组件 |
| `ACTION_PROCESS_TEXT`（选中文本菜单） | 笔记 → 我们 | 无 | **Android 可接收；小米菜单待实测** | API 23+；接收方清单需 `PROCESS_TEXT` + `DEFAULT` + `text/plain` 的 filter；本仓 `minSdk=23` 满足 |
| SAF `ACTION_OPEN_DOCUMENT` 挑导出文件 | 用户导出 → 我们 | 无（挑中即授权，可持久化） | **Android 可选文件；小米导出格式待实测** | 官方 SAF 文档：grant 默认到重启，`takePersistableUriPermission` 可延长；无需存储权限 |
| 应用内“粘贴”按钮（用户自己复制） | 笔记 → 剪贴板 → 我们 | 无 | **可行，非自动化** | 官方剪贴板说明：Android 10+ 仅前台聚焦应用可读，Android 12+ 粘贴有 toast |
| 静默读剪贴板 / 后台轮询 | 同上但自动 | — | **不可行** | 同上，Android 10 起禁止后台读取 |
| ContentProvider 直读（`content://com.miui.todo.provider`） | 我们 → 笔记数据 | — | **不作为方案** | 清单上 `exported=true` 且无权限声明，但属未公开实现；官方入口一律 `signature\|privileged` |
| Android 16 AppFunctions / NOTES role | 系统级代理 | — | **第三方不可用** | 决定性证据是 `EXECUTE_APP_FUNCTIONS` 实测为 `internal\|privileged`。该机确有 notes 角色开关（`/product/overlay/NotesRoleEnabled/NotesRoleEnabledOverlay.apk` = `com.android.role.notes.enabled`，min/targetSdk 36），但 `cmd role get-role-holders android.app.role.NOTES` 返回空，且与传入非法角色名的输出**无法区分**（已用对照实验验证），因此角色是否可申领属未定，需实现期用 `RoleManager` API 实测 |
| 无障碍服务 / 屏幕抓取 | — | — | **禁区，本包明确排除** | 见[工作包状态](../../ROADMAP.md) |

### 平台侧要付的代价（不写代码也得先量出来）

- 现在 `MainActivity` 是 5 行空壳（`android/app/src/main/kotlin/com/matrixflow/matrixflow_native/MainActivity.kt:5`，`class MainActivity : FlutterActivity()`），**没有** `onNewIntent`、没有 MethodChannel。要接分享就得加平台代码 + 一个 channel；本仓库只有桌面侧有 channel（`lib/services/desktop_shell_windows.dart:41`、`lib/services/single_instance.dart:47`）。
- 清单里唯一的 `<queries>` 是 Flutter 模板自带的 `PROCESS_TEXT`（`android/app/src/main/AndroidManifest.xml:52-62`，注释写明供 Flutter engine 的 `ProcessTextPlugin` 使用）。**它的方向是“我们把选中文本发给别人”，不是“别人把选中文本交给我们”**，别把它当成已具备接收能力。
- 当前活动配置 `launchMode="singleTop"`、`exported="true"`、只有一个 `MAIN/LAUNCHER` filter（`AndroidManifest.xml:15-36`）。加分享 filter 会让 `MainActivity` 成为外部可达入口，必须自己校验入参（官方文档原话：“要特别留意检查进入的数据”）。
- `singleTop` 下热启动走 `onNewIntent`、冷启动走 `getIntent()`，两条都要处理；Flutter 侧需要一个“待处理分享队列”，否则冷启动时引擎还没 attach 就丢数据。

## Xiaomi / HyperOS 兼容边界（实测机数据）

实测环境：Redmi `23117RK66C`（Redmi K70 Pro），Android 16 / SDK 36，HyperOS `V816` / `OS3.0.305.0.WNMCNXM`。目标包 `com.miui.notes`：`versionName=2.4.3.3`，`versionCode=2433`，`minSdk=29`，`targetSdk=35`。

登记的 ContentProvider（authority → 类，含清单属性）：

| authority | 组件 | exported | 清单权限声明 |
|---|---|---|---|
| `notes` | `.provider.NotesProvider` | true | 无权限声明；带 3 条 `grant-uri-permission`（`/data/media/`、`/scrap`、`/file`） |
| `com.miui.todo.provider` | `com.miui.todo.data.provider.TodoProvider` | true | 无权限声明 |
| `com.miui.notes` | `.tool.util.CompatFileProvider` | false | — |
| `com.miui.trans.provider` | `com.miui.common.trans.TransferRestoreProvider` | true | 无权限声明 |
| `com.miui.notes.androidx-startup` | `androidx.startup.InitializationProvider` | false | — |
| （未列 authority） | `.ai.provider.AiTextWidgetBlockProvider` | true | 由 `com.miui.notes.permission.AI_TEXT_WIDGET`（`signature\|privileged`）保护 |

被 `com.miui.notes.permission.ACCESS_NOTE` 保护的官方跨应用入口（这才是“小米打算给外部用的接口”）：`WidgetNoteListActivity`、`PadWidgetNoteListActivity`、全部 `NoteWidgetProvider_*`（含 `2x1_Todo`）、`NotesPreferenceActivity`、`PadAppPreferenceActivity`。该权限登记为 `prot=signature|privileged` → 第三方不可获得。

其它对边界有影响的事实：

- `com.miui.notes` 自身申请了 `MANAGE_EXTERNAL_STORAGE`、`READ_CLIPBOARD_IN_BACKGROUND`、`miui.permission.USE_INTERNAL_GENERAL_API` 等特权权限，进一步说明小米笔记与系统能力之间是特权关系，不是对外契约。
- 导出/分享入口 `PhoneExportShareActivity` 与 `ExportShareActivity`（pad）都是 `exported=false` → 外部无法调起，只能用户在系统 UI 里点。所以“结构化导出文件”这条路的可用性取决于系统 UI 现状，**必须实测**。
- `SystemShareMiddleActivity` 是 `exported=true` 且带 `SEND` filter → 反方向（别的应用分享进小米笔记）是通的，说明小米自己就在这条标准通道上实现分享。
- 深链 `minote://data/todos`、`minote://notes`、`minote://page/navi` 与动作 `com.miui.todo.action.VIEW` / `com.miui.todo.action.INSERT_OR_EDIT` 挂在 `NotesListActivity`（`exported=true`）上。**注意：`INSERT_OR_EDIT` 是“写入/新建小米待办”，不是“读取待办”**，对本包无用；用它反向写数据也属于未公开契约，不建议。
- ROM 侧还有 `com.android.permission.GET_INSTALLED_APPS` 这一层额外门（原生 `<queries>` 之外的厂商限制），会影响“检测装了哪些笔记应用”这类逻辑。
- **厂商限制是否影响分享落地（例如 MIUI 的后台启动/前台 Activity 限制是否会拦我们被拉起的接收路径），本轮未实测**，只能由 `probe-protocol.md` 的第 4 步判定。

## 条件性实现建议（仅在待办分享探针通过后考虑）

**分层范围**

- P0：文本进入。应用内“从笔记粘贴”+ 系统分享接收（`ACTION_SEND text/plain`），复用现有逐行解析；预览后一次落库。
- P1：文件进入。SAF 挑用户导出的 `.txt/.md/.csv`，走同一解析；`.json` 继续只走既有备份门禁，不与笔记解析混用。
- P2：`ACTION_PROCESS_TEXT` 选中文本入口（语义弱、易误解，排在分享之后）。
- 不做：直读 `com.miui.todo.provider`、无障碍/通知监听、剪贴板后台轮询、`INSERT_OR_EDIT` 写回小米。

**落点与边界（尽量零新增依赖）**

- 平台侧：`AndroidManifest.xml` 增加 `SEND`（+P2 时 `PROCESS_TEXT`）filter；`MainActivity` 加 `onNewIntent`/冷启动暂存 + MethodChannel `matrixflow/capture`（getPending / consumed 两个方法即可）。这跟现有桌面 channel 的做法同构（`lib/services/desktop_shell_windows.dart:41`）。
- Dart 侧：新增一个纯 Dart 解析入口（输入 `List<String> lines` + 元数据，输出“草稿列表”），**不改** `input_sheet.dart` 的既有语义；落库走已有 `Store.newTask` + `addTasks`（`lib/storage.dart:659,697`）。
- 解析规则必须显式声明“丢掉了什么”：文本分享不含完成态、日期、所属清单、子任务层级，除非小米实测证明带标记。不能把“只能拿文本”说成“已导入笔记”。
- **`Task` 目前没有 `source` / `origin` / 外部 ID / 指纹字段**（`lib/models.dart:168-184`），`recoveryPending` 有白名单，`tags` 是唯一的自由载体。要么先加一个可选 `captureSource`（属于数据契约变更，需同步 `toJson` 的 v1 抑制规则与 `ImportPreflight` 的未知字段告警），要么先用 `tags` 承载并在文档里写清是权宜。不要静默塞进 `reasoning`。
- 去重：没有来源 ID 时按“标题规范化 + 同 board”判重，命中只提示不自动合并（现有 `DataMigrator` 的 id 去重思路可参考 `lib/data_migrations.dart:84-127`，但那按 id 去重，不适用于文本导入）。
- i18n：新文案必须同时进 `en/zh/ja` 三张表（`.github/CONTRIBUTING.md` 的要求，结构见 `lib/l10n.dart:6`）。
- Windows/Linux：不接手机私有接口；只做“剪贴板粘贴 + 文件导入”，与 Android 共用同一份纯 Dart 解析。

**必须先定的三个产品问题**（研究阶段无法替你决定）

1. 分享进来落哪个 board、哪个象限、是否今天计划日（与 WP14 的 `plannedDate` 契约耦合）。
2. 是否引入 `captureSource` 字段（数据模型变更 vs 用 `tags` 权宜）。
3. 完成态与日期：小米实测若证明能带 checkbox 标记，是否把“已完成”也导入。

## 验收门禁

WP17 实现前先完成[真机探针](probe-protocol.md)的分享与导出记录（含 Android/HyperOS/笔记 App 版本号和原始 Intent 元数据）；需要产品接收代码的冷/热启动验证在实现阶段补齐。P0 实现后运行 `flutter test --no-pub` 与 `flutter analyze --no-pub`。**未实测的厂商一律不显示“已支持”**。

## 测试夹具

见 `fixtures/README.md` 与 `fixtures/capture_cases.json`：15 个合成用例（`WP17R-001`…`015`），覆盖单行/多行/空白、完成态标记的三种情况、自然语言日期、控制字符、超长截断、`file://` 与未授权 `content://` 附件、非文本 MIME、`PROCESS_TEXT` 不回写、SAF 持久化授权、重复导入只提示不合并。每个用例用 `basis` 区分“复刻现有行为 / 本包提案 / 待实测”，避免实现时把提案当成事实。当前**没有**对应测试文件（本轮不改产品代码与测试），夹具留在证据目录，防止变成无人引用的死数据。

## 本轮实际执行过的操作与可复核性

- 只读命令：`adb shell getprop`、`pm list packages`、`pm list permissions`、`dumpsys package <pkg>`、`dumpsys package providers`、`cmd package query-activities --brief -a android.intent.action.SEND -t text/plain`、`cmd role get-role-holders android.app.role.NOTES`、`dumpsys package permission android.permission.EXECUTE_APP_FUNCTIONS`。
- 为读清单属性临时 `adb pull` 了 `com.miui.notes/base.apk`（83 MB）并用 `aapt2 dump xmltree --file AndroidManifest.xml` 解析；**只解析清单，未读取任何数据库或用户笔记内容，未使用 root**。用完即删（`/tmp/miui_notes_apk` 已删除），仓库未提交任何厂商 APK 或其原文副本。
- 未执行：屏幕抓取、无障碍、`content query`、任何写入用户笔记的操作。
- 证据等级标注：本文件的厂商结论来自实测元数据；`ACTION_SEND`/SAF/剪贴板/包可见性来自 Android 官方文档；“MIUI 是否会拦截被拉起的接收路径”“小米分享文本的具体形态”标为**未实测**。

## 来源

- [接收来自其他应用的简单数据](https://developer.android.com/training/sharing/receive) · [将简单的数据发送到其他应用](https://developer.android.com/training/sharing/send)
- [小米支持：逐篇复制或分享笔记文本](https://www.mi.com/global/support/faq/details/KA-559533/) · [小米设备手册：笔记分享与待办清单分列](https://ams-go.buy.mi.com/uk/servicecenter/file/POCO_C40_User_Guide___uk?binaryId=204632&namespaceId=2&publicationId=204657)
- [声明软件包可见性需求](https://developer.android.com/training/package-visibility/declaring) · [软件包可见性总览](https://developer.android.com/training/package-visibility)
- [通过 SAF 打开文档](https://developer.android.com/training/data-storage/shared/documents-files)
- [安全剪贴板处理](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling)
- [Intent 参考：ACTION_PROCESS_TEXT](https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT)（本轮抓取被页面截断，实现前需人工复核该页原文）
- [工作包状态](../../ROADMAP.md)中的 WP17 与 WP17-R 范围。
