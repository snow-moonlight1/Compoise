# MatrixFlow JSON 备份格式（OS04）

状态：**格式决策已确定；本页同时记录 2026-09-23 `main / 0ed6fc7` 的实际行为和待 OS07/08 实施的契约**。适用客户端为 Flutter Android 与 Windows。本文的 JSON 均为无密钥合成数据；不代表真实用户备份。

后续状态：OS05 已处理本机启动时的损坏源保留与恢复入口，未改变本页所述 `ExportData` 备份格式或导入策略；多键保存可靠性仍归 OS06。

## 决策与范围

- 完整、可携带备份继续使用版本化 UTF-8 JSON：默认导出 **v2**，继续读取旧 Web/Native **v1**（无 `version` 按 v1 解释）。Android 与 Windows 共用模型和导入/导出实现。备份是手动交换文件，不是自动同步。
- CSV 以后可以用于展平的任务报表，不能替代父子任务、提醒和设置的完整备份；当前无附件需求，不引入 ZIP；不以数据库文件替代交换格式。JSON 文件本身不加密，也不解决本机多键写入的原子性；本机损坏保留和保存协议分别由 OS05/06 处理。
- 本文描述当前代码时使用“现状”；标记“目标（OS07/08）”的条款是后续实现和验收依据，**尚未实现**。旧 React 已冻结，不承诺它无损读取 v2，也不修改其格式实现。[决策来源：ADR-OS-01](FLUTTER_REVIEW_2026-09-22.md)；[实施计划：OS04](IMPLEMENTATION_PLAN_2026-09-22_OPEN_SOURCE_READINESS.md)。

## 外层结构与合成示例

`ExportData.toJson` 当前固定输出 `version`、`timestamp`、`boards`、`tasks`、`settings`、`aiConfig`。导入走 `DataMigrator.migratePayload`，它只要求 `boards` 与 `tasks` 为数组；`settings`、`aiConfig` 可缺失或为 `null`，缺失时覆盖导入保留本机对应配置。顶层 `timestamp` **不参与导入**。以下是最小、可读取的合成示例，不是完整导出字段清单：

```json
{
  "version": 1,
  "timestamp": 1726000000000,
  "boards": [{"id": "board-example", "name": "示例板", "createdAt": 1726000000000}],
  "tasks": [{"id": "task-example", "boardId": "board-example", "title": "示例任务", "quadrant": 2, "createdAt": 1726000000000, "subtasks": [{"id": "step-example", "title": "示例步骤", "completed": false}]}]
}
```

```json
{
  "version": 2,
  "timestamp": 1726000000000,
  "boards": [{"id": "board-example", "name": "示例板", "createdAt": 1726000000000}],
  "tasks": [{"id": "task-example", "boardId": "board-example", "title": "示例任务", "quadrant": 2, "createdAt": 1726000000000, "subtasks": [{"id": "step-example", "title": "示例步骤", "completed": false, "notesMarkdown": "仅合成文本"}], "urgencyMode": "manual", "reminderAt": 1726086400000}],
  "settings": {"language": "zh", "viewMode": "list", "reduceMotion": true},
  "aiConfig": {"provider": "openai", "providerId": "custom", "protocol": "openai", "customBaseUrl": "https://example.invalid/v1", "customApiKey": "", "customModel": "example-model", "enableThinking": false}
}
```

示例省略字段由读取器补默认值；再次导出时会写出规范化后的字段。`example.invalid` 是不可用的保留示例域名。实际当前导出即使密钥为空也会包含 `customApiKey` 键；**非空密钥也会原样明文导出**，详见下文。

## 字段、缺省与时间

以下是 Flutter `models.dart` / `data_migrations.dart` 的**现状**；“可选”表示读取时允许缺省，不等于导出一定省略。

| 对象 | 导出字段及读取行为 |
|---|---|
| `Board` | `id` 必须为非空白字符串；`name` 缺省为 `Board`；`createdAt` 缺省为 `0`。导出三个字段。 |
| `Task` | `id` 必需；`boardId`、`title` 缺省 `""`；`quadrant` 接受 1–4 或 `Q1`–`Q4` 等，非法/缺失归 4；`isLongTerm`、`completed` 缺省 `false`；`createdAt` 缺省 `0`；`subtasks` 缺省 `[]`。`deadline`、`reasoning` 可缺省。v2 另含 `urgencyMode`（仅 `manual` 识别为手动，其余归 `auto`）、`notesMarkdown`、`reminderAt`、`reminderTimezone`、`completedAt`。 |
| `SubTask` | `id` 必需；`title` 缺省 `""`，`completed` 缺省 `false`，`deadline` 可缺省。v2 另含 `notesMarkdown`、`reminderAt`、`completedAt`。 |
| `AppSettings` | 存在时按白名单读。共同字段：`language`（en/zh/ja）、`theme`（system/light/dark）、`themeColor`（blue/purple/green/orange/pink）、`defaultInputMode`（single/brainDump）、`autoGroupAI`、`autoDecomposeAI`、`autoCompleteParent`、`suppressGroupPrompt`、`suppressLongTermPrompt`、`hideCompleted`、`urgencyThresholdDays`。布尔缺省 `false`；阈值缺省 3，夹在 1–14。v2 另写 `viewMode`（grid/list）、`fontSize`（small/standard/large）、`fontFamily`（system/sansSerif/serif/monospace）、`showCompletionRate`、`reduceMotion`、`closeToTray`、`globalShortcut`（缺省 `Ctrl+Alt+M`）。枚举非法值回退模型默认值。 |
| `AIConfig` | 序列化写 `provider`、`providerId`、`protocol`、`customBaseUrl`、`customApiKey`、`customModel`、`enableThinking`，**v1 降级输出也照写**。`protocol` 优先于旧 `provider`；openai/custom/gemini 旧值按 openai 协议读，另支持 openai-responses/anthropic。缺失 providerId 从准确 URL host 推断，未知 ID 归 custom；密钥缺省空串，thinking 缺省 false。已知预设缺 URL/模型时按预设和协议补值；只有准确 DeepSeek host + 预设 + 协议组合的旧 `deepseek-v4-flash` 默认名迁移为 `deepseek-flash`，自定义模型保留。 |

`timestamp`、板/任务 `createdAt`、任务/子项 `deadline`、`reminderAt`、`completedAt` 的单位是 **Unix 毫秒**；`reminderAt` 是绝对时刻，`deadline` 按本地日历日用于紧急性判断。`reminderTimezone` 是可选字符串，当前按原值保存，并非把备份时间戳转为其它单位。顶层 `timestamp` 由导出时生成；`DataMigrator` 不读取它。任务/子项可选时间由 `_timestamp` 检查为有限数、绝对值不超过 8640000000000000，再截为整数；板/任务 `createdAt` 只作数值转整数或默认 0，**没有同样的范围检查**。目标（OS07）：统一时间字段的类型/范围门禁，明确无效值和时区处理，不静默猜测秒与毫秒。

ID 是不透明非空白字符串，不依赖 `mf-` 前缀，也不重写旧 v1 ID；当前新建 ID 使用时间、序号和随机数组合。当前迁移器分别对**板 ID**和**任务 ID**在文件内去重，保留首条并产生内部 warning；**子项 ID 未去重**。板/任务 ID 可同名，因为它们处于不同对象域。子项操作与通知使用 `(taskId, subtaskId)`，因此目标（OS07）定义子项 ID 在**同一父任务内唯一**；不同父任务可复用子项 ID。任务 ID 在所有板之间唯一，板 ID 在所有板之间唯一。不得因相同 ID 的内容不同而静默丢弃或覆盖。

## 版本兼容与信息损失

| 路径 | 现状 |
|---|---|
| v1 或无 `version` → Flutter | `DataMigrator` 识别为 v1，按当前模型读入并给内部迁移 warning；导入后的内存模型相当于 v2。v1 输入中的已知 v2 字段事实上也会被读取，版本号目前不是字段过滤门禁。 |
| v2 → Flutter | 直接读入当前模型。整型 `1`、`2`（以及数值上等于它们的数字）受支持；0、负数和未来版本拒绝，非数字/非整数版本报格式错误。 |
| Flutter → v2 | 设置页调用 `Store.exportJson()`，默认 v2。未知字段不会进入模型，也不会在再次导出时保留。 |
| Flutter → v1 | `Store.exportJson(version: 1)` 可由代码调用，设置页没有版本选择。任务丢失 `urgencyMode`、任务/子项笔记、提醒、完成时间；任务 `reminderTimezone` 也丢失。设置丢失 v2 专有的视图、字体、完成率、减少动画、托盘和快捷键字段。AI 配置未按 v1 精简。降级是**有损**的，不承诺旧 React 完整读回 v2 或新增 v1 字段。 |

`ExportData.fromJson` 是另一个较宽松的直接读取入口：缺少板/任务数组时会用空数组，缺少设置/配置时会构造默认对象；它**不是**设置页/Store 的导入门禁。实际导入以 `DataMigrator` 为准，不能用前者的宽松行为描述用户导入。`Store.exportJson(version: ...)` 当前也没有独立版本门禁；设置页只调用无参数的 v2 默认路径，不应把任意代码参数写成受支持的交换版本。

## 导入与错误：现状 / 目标

| 情况 | 现状（设置页 → Store） | 目标与归属 |
|---|---|---|
| 文件、版本与空备份 | 文件选择器以 JSON 扩展名过滤；读入全部字节后 UTF-8 解码（去首个 BOM）、`jsonDecode`、顶层 Map 与板/任务数组检查。迁移器拒绝缺少/错误数组、记录解析错误、非法/未知版本。`{"version":2,"boards":[],"tasks":[]}` 合法；覆盖它会创建一个新默认板并清空任务，合并它则不改变板/任务。 | OS07 在分配整文件之前限制字节，预检结构、条目数、深度与影响；空合法备份单独提示，覆盖前展示将删除的内容。 |
| 未知字段与异常字段 | 未知顶层/对象字段忽略，重新导出丢失。板/任务/子项解析类型错误可拒绝全份；某些缺省或归一化（如象限、空标题、0 创建时间）静默发生。 | OS07 对已支持版本的未知字段显示名称/位置及丢弃数量，确认后可忽略，但不承诺往返保留；修复、丢弃、不可恢复错误分别预检。不可恢复错误在变更状态前拒绝，警告不含任务内容或密钥。 |
| 文件内重复 ID | 板/任务保留首条，warning 仅存在 `MigrationResult`；子项未查重，可能导致编辑/提醒目标歧义。 | OS07 检查上述 ID 作用域；相同记录与不同内容冲突分别处理，冲突需用户可见的处理策略，不能首条静默胜出。 |
| `merge` | 已有板/任务 ID 使导入项跳过；只追加有有效板 ID 的新任务，孤儿任务静默丢弃；不导入设置或 AI 配置；返回**新增任务数**。迁移 warning/跳过详情不传给 UI。新增任务还会经过截止日紧急性自动升级，象限可能变化。 | OS07 预检新增、相同而跳过、冲突、孤儿和修复；有歧义需用户选择或拒绝，取消不得改数据。 |
| `overwrite` | 先迁移并检查任务所属板；空 `boardId` 改指首板，非空孤儿报错。然后整体替换板/任务；缺少设置/配置时保留本机值，存在时覆盖；活跃板设为首板；返回新任务数。UI 再次确认覆盖，应用后还可能自动升级过期任务的象限。 | OS07 显示板/任务/设置/配置影响，明确空 `boardId` 修复与孤儿策略；应用和持久化复用 OS06 的可恢复提交协议。 |
| 写入或取消 | 选文件/模式/二次确认取消前不调用 Store。迁移/关系错误在状态修改前抛出；但成功应用后多键 SharedPreferences 写入非事务，`flush()` 不等于掉电原子性。UI 失败仅显示通用导入错误；持久化错误可能仅显示错误横幅/文本。 | OS06 解决保存结果/批次，OS07 在应用失败时保持旧库或恢复完整批次，并向用户给出可操作结果。 |

**目标（OS07）冲突规则**：先生成不含敏感内容的预检摘要。相同 ID 且字段相同的记录可计为“跳过”；相同 ID 但内容不同的记录计为“冲突”，默认不替换现有记录，需明确选择处理或拒绝本次导入；同一文件内的重复也执行该规则。覆盖模式的全部影响先显示再确认。具体批量修复与重命名策略在 OS07 实现时固定限值和测试，不在 OS04 假称已有 UI。

## 密钥策略

**现状：** `AIConfig.toJson` 总写 `customApiKey`，`Store.exportJson` 无排除选项；设置页默认导出包含它的 v2 明文 JSON。`overwrite` 若有 `aiConfig` 会覆盖本机配置和 key，即使 JSON 里省略 `customApiKey`，`AIConfig.fromJson` 也会把 key 读为空串；`merge` 不导入配置。用户应把**当前所有备份文件视为可能含凭据**。

**目标（OS08）：** 默认导出任务、板、允许的设置和非敏感 AI 配置，**省略 `customApiKey` 键**；每次显式选择包含凭据时说明明文风险，才写入该键。旧含密钥的 v1/v2 仍可读；导入文件缺 key 默认保留本机 key，导入/覆盖凭据需用户明确选择。任何预览、文件名、错误、日志和测试输出都不显示 key。OS08 与 OS07 共用导入预检/应用路径；OS09 再处理本机凭据保护。

## 待实施差异登记

| 归属 | 与本页目标契约的差异 |
|---|---|
| OS07 | 统一单一导入门禁；限制文件字节/记录/深度；统一时间验证；子项 ID 范围和所有冲突预检；未知字段/默认修复/孤儿/空备份可见；merge/overwrite 影响与取消语义；成功落盘依赖 OS06 的可恢复批次。当前重复板/任务首条胜出、孤儿静默跳过及内存先更新均不满足目标。 |
| OS08 | 默认排除 `customApiKey`、显式包含凭据、旧含 key 备份的导入选择、缺 key 时保留本机凭据。当前默认明文导出及覆盖缺 key 清空凭据均不满足目标。 |

代码事实入口：[模型与 v1/v2 序列化](../matrixflow-native/lib/models.dart)、[迁移门禁](../matrixflow-native/lib/data_migrations.dart)、[Store 导入/导出及持久化](../matrixflow-native/lib/storage.dart)、[设置页文件流程](../matrixflow-native/lib/screens/settings_screen.dart)、[合成 v1 fixture](../matrixflow-native/test/fixtures/export-v1-minimal.json)、[合成 v2 fixture](../matrixflow-native/test/fixtures/export-v2-minimal.json)。
