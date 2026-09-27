# JSON 备份格式

本文是 Android 与 Windows 客户端的**文件备份契约**：格式、导入结果和恢复方法。

## 先看恢复方法

在设置页导入单个 `.json` 文件时，先选“覆盖”或一种“合并”方式，查看影响预览后确认。**覆盖会替换当前任务板和任务**；请先保留当前数据的备份。

多卷备份必须全部保存，并按文件名的卷号顺序导入：**第 1 卷覆盖，其余卷合并**。合并到现有任务板时，每卷都要选同一个目标板；通常按备份任务板合并即可。只有第 1 卷携带设置和 AI 配置。取消、保存失败或无法完整恢复时，应用不会报告导出成功。

## 文件结构与版本

设置页默认导出 UTF-8 JSON `ExportData` v2；导入接受 v1、v2，缺少 `version` 按 v1 处理。未知版本拒绝。旧 React 原型不保证读取 v2。以下是最小可导入示例，省略的字段由模型填默认值：

```json
{
  "version": 2,
  "boards": [{"id": "board-1", "name": "示例板", "createdAt": 1726000000000}],
  "tasks": [{"id": "task-1", "boardId": "board-1", "title": "示例任务", "quadrant": 2, "createdAt": 1726000000000, "subtasks": []}]
}
```

| 顶层字段 | 导入行为 |
|---|---|
| `version` | `1`、`2` 或缺省；缺省视为 v1。 |
| `boards`、`tasks` | 必须是数组；空数组合法。 |
| `settings`、`aiConfig` | 可省略或为 `null`；覆盖导入缺省时保留本机对应配置，合并不导入它们。 |
| `timestamp` | 导出时间，Unix 毫秒；导入不使用。 |
| `recovery`、`recoveryChunks` | 应用生成的恢复归档标记和大字段分块；见下文。 |

板、任务和子项的 `id` 是不透明的非空白字符串。板 ID 和任务 ID 各自在整个文件内唯一，子项 ID 在同一任务内唯一。`boardId` 指向所属板。日期时间字段使用 Unix 毫秒；`deadline` 用于本地日历日的紧急性判断，`reminderAt` 表示提醒的绝对时刻。

常用 v2 字段如下；完整序列化和默认值以 [models.dart](../lib/models.dart) 为准：

| 对象 | 字段 |
|---|---|
| 板 | `id`、`name`、`createdAt` |
| 任务 | `id`、`boardId`、`title`、`quadrant`、`isLongTerm`、`completed`、`createdAt`、`deadline`、`subtasks`、`reasoning`、`urgencyMode`、`notesMarkdown`、`reminderAt`、`reminderTimezone`、`completedAt` |
| 子项 | `id`、`title`、`completed`、`deadline`、`notesMarkdown`、`reminderAt`、`completedAt` |
| 设置和 AI 配置 | `AppSettings`、`AIConfig` 的公开 JSON 字段；备份默认省略 `aiConfig.customApiKey`。 |

通过代码调用 `Store.exportJson(version: 1)` 可以生成有损 v1：任务和子项的笔记、提醒、完成时间，以及 v2 显示和桌面设置不会写出。设置页没有 v1 导出选项。v1 输入中的已知 v2 字段仍可能被当前读取器识别；不要把版本号当成字段过滤器。未知字段会在预检中提示名称，重新导出时不会保留。

## 导入前检查和提交

每个文件最多 **8 MiB UTF-8 字节**，JSON 最大嵌套深度 **12**。普通备份及其合并后的结果库最多 **500 板、10,000 任务、50,000 子项**。文件读取、结构、版本、时间和 ID 在应用数据变更前检查；同 ID 的相同记录计为跳过，不同内容计为冲突并阻止提交。子项 ID 的唯一范围是父任务。

| 模式 | 任务板和任务 | 设置与凭据 |
|---|---|---|
| 覆盖 | 以备份替换任务板和任务；空板列表会建立默认板；空 `boardId` 可修复到首板，非空的无效板引用会拒绝。 | 存在的设置和 AI 配置才参与覆盖；密钥另需显式选择。 |
| 按备份任务板合并 | 复用同 ID 板并新建缺少的板；同 ID 不同内容为冲突，无所属板任务跳过并提示。 | 不导入。 |
| 合并到现有任务板 | 将有效来源任务挂到用户选定的现有板，不新建备份板；同 ID 不同内容为冲突。 | 不导入。 |

预览显示新增、跳过、冲突、修复和覆盖影响。确认后产品入口用 `Store.applyImport` 提交完整批次；失败保留或恢复原库。代码中的同步 `Store.importData` 是兼容测试入口，不能用它描述设置页行为。

## 密钥与敏感数据

备份文件本身是**明文**，可能包含任务、笔记和配置。默认导出完整的非敏感 AI 配置，但**不写出** `aiConfig.customApiKey` 键。每次显式选择包含密钥时，设置页会警告，再从系统凭据存储读取；所得文件中的密钥为明文。旧 v1/v2 含密钥文件仍可导入；覆盖导入默认保留本机密钥，选择“使用备份密钥”才替换。合并从不导入密钥。不要把真实备份提交到仓库。

## 大库与恢复归档

**4 MiB** 是分卷时单卷任务文本的目标预算，按 JSON 转义后的 UTF-8 字节计算；它**不是**文件读取上限。每个实际文件仍须不超过 8 MiB。能通过导入预检的普通单文件会原样写出；否则导出器按板分卷，必要时同一板出现在多卷。导出器会按“第 1 卷覆盖、其余卷合并”模拟恢复，无法完整恢复就不交付成功文件。

当库超过普通数量上限，或单个任务字段无法放进一卷时，应用写出带 `"recovery": true` 的恢复归档。该标记允许多卷累计数量越过普通上限；无此标记的超量文件仍会被拒绝。大字段可以拆入 `recoveryChunks`，支持任务的 `notesMarkdown`、`title`、`reasoning` 和子项的 `notesMarkdown`、`title`。分块包含任务定位、`field`、`index`、`offset`（UTF-16 码元）、`length`、`archiveId`、`prefixSha256` 和 `text`；恢复进度保存在对应记录的 `recoveryPending`。续卷校验归档身份、前缀和最终全文 SHA-256；缺卷、乱序、内容被改动或不同归档混用会拒绝该卷。重复导入已经应用的同一段可跳过。卷数可能超过 8，但每卷仍受 8 MiB 和深度限制。

代码入口：[导出与分卷](../lib/backup_export.dart)、[文件预检](../lib/import_preflight.dart)、[模型与序列化](../lib/models.dart)、[版本迁移](../lib/data_migrations.dart)、[设置页文件流程](../lib/screens/settings_backup_flow.dart)。
