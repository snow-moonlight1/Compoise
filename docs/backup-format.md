# 备份格式

Android、Windows 和 Linux 共用同一种 JSON 备份文件。本文说明文件结构、导入时的检查，以及大量数据时的多卷备份。

## 恢复方法

- 在设置 → 数据备份里导入一个 `.json` 文件。先选择“覆盖”或一种“合并”方式，看过影响预览后再确认。
- **覆盖会替换当前的任务板、任务和日程**，建议先导出一份当前数据。
- **多卷备份**要全部保存，并按文件名里的卷号顺序导入：第 1 卷选“覆盖”，其余各卷选“合并”。每卷都选同一个目标任务板（通常是“按备份任务板合并”）。只有第 1 卷带有设置和 AI 配置。
- 导出被取消、保存失败或者无法完整恢复时，应用不会报告导出成功。

## 文件结构

文件是 UTF-8 编码的 JSON，示例：

```json
{
  "version": 4,
  "timestamp": 1790700000000,
  "boards": [{"id": "board-1", "name": "示例板", "createdAt": 1726000000000}],
  "tasks": [{"id": "task-1", "boardId": "board-1", "title": "示例任务", "quadrant": 2, "createdAt": 1726000000000, "subtasks": []}],
  "scheduleItems": [
    {"id": "block-1", "kind": "timeBlock", "taskId": "task-1", "startAt": 1790701200000, "endAt": 1790704800000, "timeZoneId": "Asia/Shanghai"},
    {"id": "event-1", "kind": "event", "title": "评审会", "boardId": "board-1", "startAt": 1790701200000, "endAt": 1790704800000, "timeZoneId": "Asia/Shanghai"}
  ]
}
```

| 顶层字段 | 说明 |
| --- | --- |
| `version` | 文件格式号，当前为 `4`。比当前更新的格式号会被拒绝。 |
| `boards`、`tasks`、`scheduleItems` | 必须是数组，可以为空。 |
| `settings`、`aiConfig` | 可以省略或为 `null`。覆盖导入时，缺少的部分保留本机设置；合并导入不导入它们。 |
| `timestamp` | 导出时间（Unix 毫秒），导入时不使用。 |
| `recovery`、`recoveryChunks` | 恢复归档的标记和大字段分块，见下文。 |

| 对象 | 字段 |
| --- | --- |
| 任务板 | `id`、`name`、`createdAt` |
| 任务 | `id`、`boardId`、`title`、`quadrant`、`isLongTerm`、`completed`、`createdAt`、`deadline`、`plannedDate`、`subtasks`、`reasoning`、`urgencyMode`、`notesMarkdown`、`reminderAt`、`reminderTimezone`、`completedAt`、`tags`、`countProgress` |
| 子项 | `id`、`title`、`completed`、`deadline`、`notesMarkdown`、`reminderAt`、`completedAt` |
| 日程 | `id`、`kind`、`startAt`、`endAt`、`timeZoneId`；时间块必须有 `taskId`；事件必须有非空的 `title`，以及 `taskId` 或 `boardId` 二选一 |
| 设置、AI 配置 | `AppSettings` 和 `AIConfig` 的 JSON 字段；默认不写出 `aiConfig.customApiKey` |

完整的序列化规则和默认值以 `lib/models.dart` 和 `lib/schedule_item.dart` 为准。

### 计次与旧版本兼容

- v4 的任务可带 `countProgress: {"value": 12, "target": 50}`；没有 `target` 表示无限累计；没有整个字段表示普通任务。
- 次数必须是非负整数，有限目标必须为正整数且不小于当前次数；未知计次字段或损坏的数据会拒绝导入。
- 继续导入 v1/v2/v3；导入时按旧格式缺省为普通任务。旧版方寸不能读取 v4 备份。
- 含计次的任务不允许导出为 v1/v2/v3，避免静默丢失进度。界面默认导出完整的当前格式。

### 字段规则

- `id` 是非空字符串。任务板 ID 和任务 ID 在整个文件里各自唯一，子项 ID 在所属任务内唯一，日程 ID 在整个文件里唯一。
- 日期时间都是 Unix 毫秒：
  - `deadline` 是用户选择的截止时刻，新建和编辑精确到分钟，未修改的导入时刻保留秒和毫秒；
  - `plannedDate` 是已移除计划日功能留下的可选字段，只保留原值用于往返，不影响界面或任务查询；
  - `reminderAt` 是提醒的绝对时刻。
  - 含义见[任务与日程](tasks-and-schedule.md)。
- `tags` 是字符串数组，只属于父任务。空数组和缺省时都不写出。
- 日程：
  - `taskId` 只能指向文件中的父任务；
  - 独立事件的 `boardId` 必须存在；
  - 起止时间必须是 ±8,640,000,000,000,000 以内的整数，并且 `startAt < endAt`；
  - `timeZoneId` 必须是能识别的 IANA 时区；
  - 允许时间重叠。
- 未知字段会在预检时列出名称，重新导出时不会保留。

## 导入前检查

- 每个文件最多 **8 MiB**（UTF-8 字节），JSON 嵌套深度最多 **12** 层。
- 普通备份及合并后的结果最多 **500 个任务板、10,000 个任务、50,000 个子项、10,000 条日程**。事件标题最多 4,096 字节（按 JSON 转义后的 UTF-8 计算）。
- 文件读取、结构、格式号、时间和 ID 都在修改数据之前检查。以下情况会拒绝整批导入：
  - 日程 ID 重复，或 `kind` 未知；
  - 时区无法识别；
  - 关联了不存在的任务或任务板。
- 合并时，ID 相同、内容也相同的记录会跳过；ID 相同但内容不同的视为冲突，会阻止导入。

| 模式 | 任务板和任务 | 设置与密钥 |
| --- | --- | --- |
| 覆盖 | 替换任务板、任务和全部日程。任务板列表为空时会建一个默认板。 | 文件里有的设置和 AI 配置会覆盖本机；密钥要另外明确选择才替换。 |
| 按备份任务板合并 | 复用同 ID 的任务板，新建缺少的板。保留已有日程，按 ID 合并新日程。 | 不导入 |
| 合并到现有任务板 | 把任务放到选定的板上；独立事件也归到这个板。 | 不导入 |

确认后，`Store.applyImport` 在当前数据上重新计算一遍并整批提交，失败时恢复原来的数据。

## 密钥与敏感数据

- 备份文件是**明文**，里面有任务、笔记和配置。
- 默认不写出 API 密钥。每次导出时如果明确选择包含密钥，应用会先警告，再从系统安全存储读取密钥并以明文写进文件。
- 覆盖导入默认保留本机的密钥，选择“使用备份密钥”才会替换。合并导入从不导入密钥。
- 不要把真实备份提交到仓库或发到 Issue 里。

## 大量数据与恢复归档

- 单卷内容的目标大小是 **4 MiB**，但每个实际文件仍然不能超过 8 MiB。
- 普通单文件如果能通过导入检查和恢复模拟，就原样写出；否则按任务板分卷，必要时同一个板会分到多卷里。
- 每条日程只出现一次：关联任务的日程，和那个任务第一次出现的卷放在一起；独立事件和它的任务板第一次出现的卷放在一起。
- 导出时会按“第 1 卷覆盖、其余卷合并”模拟一遍恢复，并逐项比较。不能完整恢复时，导出失败，不会给出不完整的文件。
- 数量超过普通上限，或者单个字段大到一卷放不下时，应用会写出带 `"recovery": true` 的**恢复归档**：
  - 这个标记允许多卷累计数量超过普通上限，没有这个标记的超量文件会被拒绝；
  - 太长的文字字段会拆进 `recoveryChunks`，支持任务的 `notesMarkdown`、`title`、`reasoning`，以及子项的 `notesMarkdown`、`title`；
  - 每个分块都带归档 ID、位置和前缀的 SHA-256，导入时会校验，缺卷、乱序、内容被改过或混用不同归档时都会拒绝。

## 相关代码

| 内容 | 代码 |
| --- | --- |
| 导出与分卷 | `lib/backup_export.dart` |
| 文件预检 | `lib/import_preflight.dart` |
| 模型与序列化 | `lib/models.dart` |
| 格式读取 | `lib/data_migrations.dart` |
| 设置页的备份流程 | `lib/screens/settings_backup_flow.dart` |
