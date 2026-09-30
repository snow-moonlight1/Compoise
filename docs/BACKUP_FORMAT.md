# JSON 备份格式

本文是 Android、Windows 与 Linux 预览版共用的**文件备份契约**：格式、导入结果和恢复方法。

## 先看恢复方法

在设置页导入单个 `.json` 文件时，先选“覆盖”或一种“合并”方式，查看影响预览后确认。**覆盖会替换当前任务板、任务和日程集合**；请先保留当前数据的备份。v1/v2 覆盖会清空日程，只有 v3 可无损备份日程。

多卷备份必须全部保存，并按文件名的卷号顺序导入：**第 1 卷覆盖，其余卷合并**。合并到现有任务板时，每卷都要选同一个目标板；通常按备份任务板合并即可。只有第 1 卷携带设置和 AI 配置。取消、保存失败或无法完整恢复时，应用不会报告导出成功。

## 文件结构与版本

设置页通过 Store 默认导出 UTF-8 JSON `ExportData` **v3**；导入接受 v1、v2、v3，缺少 `version` 按 v1 处理。未知未来版本拒绝。旧版应用会拒绝 v3；旧 React 原型不保证读取 v2/v3。以下是可导入的 v3 示例：

```json
{
  "version": 3,
  "boards": [{"id": "board-1", "name": "示例板", "createdAt": 1726000000000}],
  "tasks": [{"id": "task-1", "boardId": "board-1", "title": "示例任务", "quadrant": 2, "createdAt": 1726000000000, "subtasks": []}],
  "scheduleItems": [
    {"id":"block-1","kind":"timeBlock","taskId":"task-1","startAt":1790701200000,"endAt":1790704800000,"timeZoneId":"Asia/Shanghai"},
    {"id":"event-1","kind":"event","title":"评审会","boardId":"board-1","startAt":1790701200000,"endAt":1790704800000,"timeZoneId":"Asia/Shanghai"}
  ]
}
```

| 顶层字段 | 导入行为 |
|---|---|
| `version` | `1`、`2`、`3` 或缺省；缺省视为 v1。 |
| `boards`、`tasks` | 必须是数组；空数组合法。 |
| `scheduleItems` | v3 必须是数组，空数组合法。v1/v2 即使碰巧包含此字段，也提示未知字段并忽略，不恢复日程。 |
| `settings`、`aiConfig` | 可省略或为 `null`；覆盖导入缺省时保留本机对应配置，合并不导入它们。 |
| `timestamp` | 导出时间，Unix 毫秒；导入不使用。 |
| `recovery`、`recoveryChunks` | 应用生成的恢复归档标记和大字段分块；见下文。 |

板、任务和子项的 `id` 是不透明的非空白字符串。板 ID 和任务 ID 各自在整个文件内唯一，子项 ID 在同一任务内唯一。`boardId` 指向所属板。日期时间字段使用 Unix 毫秒；`deadline` 用于本地日历日的紧急性判断，`reminderAt` 表示提醒的绝对时刻，`plannedDate` 是本地日历日的零点（当天开始），只表示安排在哪天做。

v3 保留所有 v2 字段，并增加独立的日程集合；完整序列化和默认值以 [models.dart](../lib/models.dart) 与 [schedule_item.dart](../lib/schedule_item.dart) 为准：

| 对象 | 字段 |
|---|---|
| 板 | `id`、`name`、`createdAt` |
| 任务 | `id`、`boardId`、`title`、`quadrant`、`isLongTerm`、`completed`、`createdAt`、`deadline`、`plannedDate`、`subtasks`、`reasoning`、`urgencyMode`、`notesMarkdown`、`reminderAt`、`reminderTimezone`、`completedAt`、`tags` |
| 子项 | `id`、`title`、`completed`、`deadline`、`notesMarkdown`、`reminderAt`、`completedAt` |
| 日程 | `id`、`kind`、`startAt`、`endAt`、`timeZoneId`；时间块必需 `taskId`；事件必需非空白 `title` 和 `taskId`/`boardId` 二选一。 |
| 设置和 AI 配置 | `AppSettings`、`AIConfig` 的公开 JSON 字段；备份默认省略 `aiConfig.customApiKey`。 |

`tags` 是字符串数组，只属于父任务，空数组和缺省都不写出。读入时统一去掉首尾空格与空标签，大小写等价的重复只保留第一次出现的写法。

`plannedDate` 只属于父任务，缺省与 null 都不写出，含义是“没有安排”。它不参与紧急性判断，也不会改变象限；`deadline` 才会在临近时把任务推入紧急一侧。两者互相独立，读取对方都不会改写自己。子项没有计划日。

日程 ID 全库唯一，与任务 ID 分属不同命名空间。`taskId` 只可指向文件中的父任务，不能指向子项；独立事件的 `boardId` 必须存在。关联任务事件不再保存 `boardId`；时间块没有独立标题。起止必须是 ±8,640,000,000,000,000 范围内的整数 Unix 毫秒，且 `startAt < endAt`；IANA 时区必须可解析。重复日程 ID（即使内容相同）、未知 kind、坏时区、非法关联和悬空引用拒绝整批输入；不将孤儿改造成事件。时间重叠合法，不自动调整。

旧版导出省略日程；v1 还省略任务和子项的笔记、提醒、完成时间、任务标签和计划日，以及 v2 显示和桌面设置。库含日程时，`Store.exportJson` 指定 `version: 1` 或 `version: 2` 和含密钥的字符串入口均抛出 `ScheduleExportLossException`，其中 `lostScheduleItems` 可供调用方展示。调用方告知数量并取得主动确认后，才可调用 `Store.exportJsonResult(version: 2, allowScheduleLoss: true)`（v1 改用 `version: 1`；含密钥用 `exportJsonResultWithCredential`）；返回 `BackupExportResult` 的 `json`、`version` 和 `lostScheduleItems`。低层 `ExportData.exportResult` 也提供相同结果，`toJson` 默认拒绝日程损失。数量只统计日程记录，v1 另有上述字段损失。设置页不提供旧版导出选项，v3 导出失败绝不自动降级。

v1 输入中的已知 v2 字段仍可能被当前读取器识别；不要把版本号当成一般字段过滤器。未知字段会在预检中提示名称，重新导出时不会保留；日程集合的版本门禁另按上表执行。

## 导入前检查和提交

每个文件最多 **8 MiB UTF-8 字节**，JSON 最大嵌套深度 **12**。普通备份及其合并后的结果库最多 **500 板、10,000 任务、50,000 子项、10,000 日程记录**。事件标题最多 **4,096 字节**，按 JSON 转义后 UTF-8 内容计算（不含两端引号）；多字节文字和转义字符占用实际预算。恢复归档只放宽记录总数，不放宽文件、深度、标题、时间或引用校验。容量实测、边界和复现命令见 [WP15-B1 验收记录](WP15_B1_NOTES.md)。

文件读取、结构、版本、时间和 ID 在应用数据变更前检查；跨文件或与当前库合并时，同 ID 同内容跳过，不同内容为冲突并阻止提交。文件内重复日程 ID 一律拒绝。子项 ID 的唯一范围是父任务。

| 模式 | 任务板和任务 | 设置与凭据 |
|---|---|---|
| 覆盖 | 替换任务板、任务及完整日程集合；v1/v2 的日程集合为空。空板列表会建立默认板；空任务 `boardId` 可修复到首板，非空的无效板引用会拒绝。 | 存在的设置和 AI 配置才参与覆盖；密钥另需显式选择。 |
| 按备份任务板合并 | 复用同 ID 板并新建缺少的板；同 ID 不同内容为冲突，无所属板任务跳过并提示。保留已有日程，按 ID 合并新记录；关联任务无法加入结果库时整批拒绝。 | 不导入。 |
| 合并到现有任务板 | 将有效来源任务挂到选定板，独立事件的 `boardId` 映射到该板，关联日程保持任务 ID；同 ID 不同内容为冲突。 | 不导入。 |

预检 `ImportPlan` 返回日程集合以及 `addedScheduleItems`、`skippedScheduleItems`、`conflictingScheduleItems`、`removedScheduleItems`，总跳过/冲突也计入日程。设置页已有任务预览；日程计数的界面呈现属于后续集成门禁，本包只完成数据层。确认后产品入口用 `Store.applyImport` 重算当前库、提交完整批次；失败保留或恢复原库。回滚推进被恢复记录的修订号，拒绝对临时导入内容打开的过期编辑；提交期间接受的后续编辑及依赖仍保留。同步 `Store.importData` 是兼容测试入口。

## 密钥与敏感数据

备份文件本身是**明文**，可能包含任务、笔记和配置。默认导出完整的非敏感 AI 配置，但**不写出** `aiConfig.customApiKey` 键。每次显式选择包含密钥时，设置页会警告，再从系统凭据存储读取；所得文件中的密钥为明文。旧 v1/v2 含密钥文件仍可导入；覆盖导入默认保留本机密钥，选择“使用备份密钥”才替换。合并从不导入密钥。不要把真实备份提交到仓库。

## 大库与恢复归档

**4 MiB** 是分卷时单卷内容的目标预算，包括板、任务、日程及依赖的转义 JSON 字节；它不是文件读取上限。不能拆开的依赖组可以超过目标预算，但每个实际文件仍须不超过 **8 MiB**，并计入设置、AI 配置和文件外壳。能通过导入预检及恢复模拟的普通单文件原样写出；否则按板分卷，必要时同一板出现在多卷。

每条日程只出现一次：关联任务记录与该任务首次出现的卷同卷；独立事件与其板首次出现的卷同卷。任务大字段续卷不重复日程，v3 续卷仍有 `scheduleItems: []`。导出器按“第 1 卷覆盖、其余卷合并”模拟恢复，并比较全部板、任务、日程 ID/引用/规范化内容和首卷配置；无法完整恢复不交付成功文件。单条标题超限、不可拆的任务及其关联日程或板及其独立事件不能装入单文件时，明确失败，返回空文件集合。

当库超过普通数量上限，或单个任务字段无法放进一卷时，应用写出带 `"recovery": true` 的恢复归档。该标记允许多卷累计数量越过普通上限；无此标记的超量文件仍会被拒绝。大字段可以拆入 `recoveryChunks`，支持任务的 `notesMarkdown`、`title`、`reasoning` 和子项的 `notesMarkdown`、`title`。分块包含任务定位、`field`、`index`、`offset`（UTF-16 码元）、`length`、`archiveId`、`prefixSha256` 和 `text`；恢复进度保存在对应记录的 `recoveryPending`。续卷校验归档身份、前缀和最终全文 SHA-256；缺卷、乱序、内容被改动或不同归档混用会拒绝该卷。重复导入已经应用的同一段可跳过。卷数可能超过 8，但每卷仍受 8 MiB 和深度限制。

代码入口：[导出与分卷](../lib/backup_export.dart)、[文件预检](../lib/import_preflight.dart)、[模型与序列化](../lib/models.dart)、[版本迁移](../lib/data_migrations.dart)、[设置页文件流程](../lib/screens/settings_backup_flow.dart)。
