# WP17-R 系统笔记待办导入 · 可行性研究

基线：`main / 45cd517`（研究分支 `wp17r-notes-import-research`）。本轮**只研究，不改产品代码**：`lib/`、`android/`、`test/` 零改动。

研究边界（按 `docs/ROADMAP.md:40` 与本轮指令）：不读取私有数据库、不使用需要 root 的数据、不做无障碍或屏幕抓取；只做包与公开接口的元数据检查，以及合成样例。

## 先看结论

1. **“直接读取系统笔记待办库”这条路走不通，也不该走。** 小米笔记（`com.miui.notes` 2.4.3.3）的官方跨应用入口全部由 `com.miui.notes.permission.ACCESS_NOTE` 保护，该权限在实测机上登记为 `prot=signature|privileged`，第三方应用永远拿不到。待办数据提供者 `com.miui.todo.provider` 在清单里没有声明权限门禁，但那是**未公开、未契约、随时可变**的内部实现，依赖它等于把用户数据挂在厂商每次升级的赌博上；Android 16 的 AppFunctions 通道同样被 `EXECUTE_APP_FUNCTIONS`（实测 `prot=internal|privileged`）挡住。
2. **“分享/粘贴/选中文本处理”三条用户主动入口是可行的，而且成本很低。** 实测机上 `ACTION_SEND` `text/plain` 有 101 个接收方，HyperOS 自身的组件（`com.miui.voiceassist.ShareReceiverActivity`）就在其中，说明该通道在小米 ROM 上是活的。本仓库**已经有逐行转待办的解析**（`lib/widgets/input_sheet.dart:373-394`）和批量落库入口（`lib/storage.dart:659` `addTasks`），所以分享入口的增量主要是平台侧把 Intent 送进 Dart，而不是再造一个解析器。
3. **文件导入是稳妥的第二条路，零新权限。** SAF（`ACTION_OPEN_DOCUMENT`）实测结论：用户挑选即授权，不需要存储权限，`takePersistableUriPermission` 可跨重启保留。本仓库已有 `file_picker` 与备份导入门禁（`lib/import_preflight.dart`），复用即可。
4. **剪贴板不能作为后台通道。** Android 10+ 剪贴板读取仅限前台聚焦应用，Android 12+ 读取粘贴会弹 toast。可作为“用户显式点粘贴”使用，不能做静默桥接。
5. **本轮不建议直接进入实现包。** 缺的不是方案，而是**真机实测数据**：小米笔记的分享到底给什么（纯文本？长图？带不带完成态和日期？待办和普通笔记是否区分？）。这些只能在一台小米机器上花 20 分钟测出来。判定标准和测试协议见 `probe-protocol.md`。

一句话给决策：**做“用户主动分享/粘贴 + 文件导入”的最小入口，不做“读系统笔记库”。**

## 出处核查：记忆里说研究已结项，但查无实据

项目记忆里有一条“WP17 已按用户决定重定义、WP17-R 已于 2026-09-29 结项”，并列出 `docs/WP17_NOTES.md`、`docs/WP17_ANDROID_CAPTURE_CONTRACT.md`、`lib/services/task_capture.dart`、8 个 `test/wp17_*` 等产物。逐项核查结果：

| 核查动作 | 结果 |
|---|---|
| `ls docs`（工作树与主检出） | 无 `WP17*` 文档；`docs/` 仍是 13 个文件 + `evidence/` |
| `ls lib/services` | 无 `task_capture.dart` |
| `ls test \| grep wp17` | 无匹配 |
| `git log --all --grep=wp17 -i` | 空 |
| `git branch -a \| grep wp17` | 空 |
| `git reflog` / `git stash list` | 无 WP17 条目，无 stash |
| `git log --all --diff-filter=A --name-only \| grep -i wp17` | 空 |
| 同级工作树（`martix-wp14-today`、`martix-wp12-tags`、`.codex/worktrees/*`） | 无 WP17 文件 |
| `git fsck --lost-found` 悬空对象逐个 grep | 唯一命中是一个悬空 blob，见下 |
| 记忆目录 `memory/`、`projects/*/memory/` | **没有任何 WP17 的 `.md` 记忆文件**，只有会话转录 `.jsonl` |
| 会话转录（本项目全部 `.jsonl`） | WP17 只作为 ROADMAP 表格里的“系统笔记待办导入”出现；**没有任何一段用户批准记录** |

结论：**“D1–D6 已获用户批准”找不到任何记录出处**——记忆文件本身不存在，批准的对话不存在，产物也不在 git 里。因此本轮不把它们当作既定前提，只按 `docs/ROADMAP.md` 的定义推进。

那个唯一命中的悬空 blob（`f04c387d`，93 KB）是 2026-09-16 版执行计划，它是 WP17-R 的**最早书面定义**，比现在的 ROADMAP 更具体，值得保留参考：

- 交付物名字当时定为 `docs/SYSTEM_NOTES_IMPORT_RESEARCH.md`；
- 研究范围与本轮指令一致：只做包/公开接口元数据检查与合成待办样例，不读私有库、不申请 root、不用无障碍抓屏遍历用户笔记；
- 完成标准是给出“可直接授权读取 / 可分享或文件导入 / 无公开接口”三态证据 + 小米适配实施计划；
- 需求源头是 MF03（来源 A3）：小米 `com.miui.notes` 优先，其余厂商逐家核验，不能按相同包结构假定兼容。

最可能的实情是：那轮研究确实做过，产物留在临时工作树 `wp17-notes-import` 里，归档前工作树被清理，于是记忆留下了结论、仓库什么都没接到（记忆自己也写过“研究结论文档不要留在执行工作树里”）。按用户决定，本轮记忆不动。

## Android 入口盘点

| 入口 | 方向 | 需要的新权限 | 可行性 | 证据 |
|---|---|---|---|---|
| `ACTION_SEND` / `SEND_MULTIPLE` `text/plain` | 笔记 → 我们 | 无（清单 intent-filter + `exported=true`） | **可行，首选** | 官方接收文档；实测机有 101 个接收方，含 HyperOS 自身组件 |
| `ACTION_PROCESS_TEXT`（选中文本菜单） | 笔记 → 我们 | 无 | **可行，但语义受限** | API 23+；接收方清单需 `PROCESS_TEXT` + `DEFAULT` + `text/plain` 的 filter；本仓 `minSdk=23` 满足 |
| SAF `ACTION_OPEN_DOCUMENT` 挑导出文件 | 用户导出 → 我们 | 无（挑中即授权，可持久化） | **可行，兜底** | 官方 SAF 文档：grant 默认到重启，`takePersistableUriPermission` 可延长；无需存储权限 |
| 应用内“粘贴”按钮（用户自己复制） | 笔记 → 剪贴板 → 我们 | 无 | **可行，非自动化** | 官方剪贴板说明：Android 10+ 仅前台聚焦应用可读，Android 12+ 粘贴有 toast |
| 静默读剪贴板 / 后台轮询 | 同上但自动 | — | **不可行** | 同上，Android 10 起禁止后台读取 |
| ContentProvider 直读（`content://com.miui.todo.provider`） | 我们 → 笔记数据 | — | **不作为方案** | 清单上 `exported=true` 且无权限声明，但属未公开实现；官方入口一律 `signature\|privileged` |
| Android 16 AppFunctions / NOTES role | 系统级代理 | — | **第三方不可用** | `EXECUTE_APP_FUNCTIONS` = `internal\|privileged`；`android.app.role.NOTES` 在实测机上无持有者；角色开关由 `/product/overlay/NotesRoleEnabled/` 提供 |
| 无障碍服务 / 屏幕抓取 | — | — | **禁区，本包明确排除** | 与 `docs/ROADMAP.md:40` 一致 |

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

## 实现建议（给 WP17 执行包，不含本轮改动）

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

WP17 执行包开工前必须有：`probe-protocol.md` 的 6 步实测记录（含 Android/HyperOS/笔记 App 三个版本号、每步原始 Intent 元数据摘录），以及 P0 的本地回归（`flutter test --no-pub` + `flutter analyze --no-pub`）。**未实测的厂商一律不显示“已支持”**。

## 测试夹具

见 `fixtures/README.md` 与 `fixtures/capture_cases.json`：15 个合成用例（`WP17R-001`…`015`），覆盖单行/多行/空白、完成态标记的三种情况、自然语言日期、控制字符、超长截断、`file://` 与未授权 `content://` 附件、非文本 MIME、`PROCESS_TEXT` 不回写、SAF 持久化授权、重复导入只提示不合并。每个用例用 `basis` 区分“复刻现有行为 / 本包提案 / 待实测”，避免实现时把提案当成事实。当前**没有**对应测试文件（本轮不改产品代码与测试），夹具留在证据目录，防止变成无人引用的死数据。

## 本轮实际执行过的操作与可复核性

- 只读命令：`adb shell getprop`、`pm list packages`、`pm list permissions`、`dumpsys package <pkg>`、`dumpsys package providers`、`cmd package query-activities --brief -a android.intent.action.SEND -t text/plain`、`cmd role get-role-holders android.app.role.NOTES`、`dumpsys package permission android.permission.EXECUTE_APP_FUNCTIONS`。
- 为读清单属性临时 `adb pull` 了 `com.miui.notes/base.apk`（83 MB）并用 `aapt2 dump xmltree --file AndroidManifest.xml` 解析；**只解析清单，未读取任何数据库或用户笔记内容，未使用 root**。用完即删（`/tmp/miui_notes_apk` 已删除），仓库未提交任何厂商 APK 或其原文副本。
- 未执行：屏幕抓取、无障碍、`content query`、任何写入用户笔记的操作。
- 证据等级标注：本文件的厂商结论来自实测元数据；`ACTION_SEND`/SAF/剪贴板/包可见性来自 Android 官方文档；“MIUI 是否会拦截被拉起的接收路径”“小米分享文本的具体形态”标为**未实测**。

## 来源

- [接收来自其他应用的简单数据](https://developer.android.com/training/sharing/receive) · [将简单的数据发送到其他应用](https://developer.android.com/training/sharing/send)
- [声明软件包可见性需求](https://developer.android.com/training/package-visibility/declaring) · [软件包可见性总览](https://developer.android.com/training/package-visibility)
- [通过 SAF 打开文档](https://developer.android.com/training/data-storage/shared/documents-files)
- [安全剪贴板处理](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling)
- [Intent 参考：ACTION_PROCESS_TEXT](https://developer.android.com/reference/android/content/Intent#ACTION_PROCESS_TEXT)（本轮抓取被页面截断，实现前需人工复核该页原文）
- 悬空对象 `f04c387d`（2026-09-16 版执行计划）中的 WP17/MF03 原始定义；`docs/ROADMAP.md:28,40`
