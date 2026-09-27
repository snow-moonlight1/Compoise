# Compoise JSON 备份格式

应用写出 `ExportData` v2，并继续读取旧版 v1。本文说明 Flutter Android 与 Windows 客户端当前使用的格式、导入限制和恢复流程。

备份可能包含任务名称、备注、日期、看板名称和 AI 配置。默认不导出 API 密钥；用户明确选择包含时，文件中的密钥为明文。请将备份视为敏感文件。

## RF04 对称备份契约（2026-09-26 当前）

- **两个不同的上限**：`ImportPreflight.maxBytes`（4 MiB）是**单个备份文件承载的文本内容预算**；`maxFileBytes`（8 MiB）是**单个文件的字节上限**，也就是有界读取的上限。二者必须分开：一条记录占满内容预算时，JSON 包装（实测 +996 bytes）已使文件大于内容预算，用同一个数字当文件上限会拒绝应用自己导出的备份（RF-R04）。`maxFileBytes` 的取值同时覆盖“按计数上限填满的现实库”的实测 6.52 MiB，因此合法计数的库仍以单文件导出。
- **字节而非字符**：中文/日文每 UTF-16 单元 3 字节，`"` 与换行转义为 2 字节，所以按字符定义的上限会低估 2–3 倍；全部门禁按 UTF-8 字节实测。
- **数量按结果库校验**：500 板 / 10000 任务 / 50000 子项约束**没有** `recovery: true` 的文件，也约束这种文件 merge 之后的库。此前多次合法 merge 可把库推过上限；未标记的文件现在仍会整笔拒绝。已经超过这些数量的库走下面的恢复归档，而不是把新增入口改成静默丢数据。
- **合并目标必须明确**：设置页将合并分为“按备份任务板合并”和“合并到现有任务板”。前者复用同 ID 板、为缺少的板新建；后者由用户选择一个现有板，将备份中的任务全部挂到该板，不创建备份板。两种合并都不导入设置或 AI 配置；多卷按顺序选择现有板时复用同一个目标板。
- **成功导出必须可恢复**：`Store.exportBackup()` 先让整份导出通过与恢复相同的 `ImportPreflight` 门禁；通过则按原样输出单文件（文件名不变，旧版本读法不变）。不通过时按板分卷（每卷 ≤ `maxFileBytes`，分片目标为内容预算；单板过限时其任务跨卷分布并**重复该板记录**，合并按相同记录计跳过而非冲突）。恢复方式：第 1 卷覆盖导入，其余卷依次合并导入；只有第 1 卷含 `settings`/`aiConfig`，因此显式含密钥的备份中密钥只出现一次。
- **不可恢复时不报成功**：会在恢复时跳下没有所属任务板的任务时不写文件，也不显示“备份已保存”。每一卷仍受 `maxFileBytes`（8 MiB）和嵌套深度限制。
- **恢复归档（2026-09-27）**：板、任务或子项已经超过 500/10000/50000 的库，导出为带顶层 `recovery: true` 的文件。第 1 卷覆盖导入、其后各卷合并导入；该标记让累计数量可以超过普通上限。没有这个标记的超计数文件，包括更早导出的多卷，仍然会在越界那一卷被拒绝。普通计数以内、且能放进一个文件的导出仍是不含该标记的原文字节。
- **超大笔记与超过 8 卷**：是否分块看任务 JSON 序列化后的体积。父笔记、子笔记、标题和说明会一起计算；`"`、`\` 和换行的转义字节也算进去，不能只看某一段原文的 UTF-8 长度。放不进一个文件的字段整段抽出，再按 `maxBytes`（4 MiB）的转义后字节切成 `recoveryChunks`。每一段包含 `taskId`、可选 `subtaskId`、`field`、`index`、`offset`（UTF-16 码元偏移）、`length`（该字段全文的码元长度）、`archiveId`、`prefixSha256` 和 `text`。导入时，偏移之前的文本必须与 `prefixSha256` 一致，且进行中的归档身份必须相同。字段达到 `length` 时，全文 UTF-8 的 SHA-256 必须等于 `archiveId`，一致才删除 `recoveryPending`；不一致则整份文件拒绝，已恢复文本和游标都留在原处。带 `offset` 却缺少 `length` 或 `archiveId` 的分块同样拒绝，不能退回旧的直接拼接。同一段再次导入（包括重启后）跳过。缺卷、乱序、另一份归档，或恢复过程中该字段已被修改，整笔拒绝，不改已恢复的文本。没有 `offset` 的旧续卷若已经以该段 `text` 结尾，也按已导入跳过。用户选择合并到某块现有任务板时，续卷只能续写已经在该板上的任务；首卷会把备份任务改挂到这块板，后续卷必须继续选择它。未完成的字段在任务或子项上保留 `recoveryPending`。卷数可以超过 `maxParts`（8）；每一卷仍不超过 `maxFileBytes`（8 MiB）。取消或中途写失败不会把整套说成已保存。
- **仍属限制**：本地输入层尚未按字节拒绝超长笔记，所以超长内容可以先被接受，再靠上面的分块备份带走。真机多卷保存/恢复手感归 RF10。

## OS08/OS09 当前密钥契约

- 默认导出 v2 JSON（代码请求 v1 时同样）完整保留板、任务、设置和非敏感 AI 配置，**完全省略 `aiConfig.customApiKey` 键**。每次从设置页选择显式包含时先展示明文警告，再从系统凭据存储读出并写入该键；读失败不导出。取消、文件选择或写入失败不显示成功提示；文件名和错误不带密钥。明文导出文件需要用户自行保护。
- 旧 v1/v2 含 `customApiKey` 的文件仍可读。覆盖导入时缺键默认保留本机凭据；有键也默认保留，并在影响预览中提供“使用备份密钥”显式选项。merge 只导入任务/板，不导入配置或凭据。选择替换时先写系统存储并读回，批次提交失败会尝试恢复原凭据；错误只给类别。预览及日志不展示密钥值。
- 本机 `matrixflow-config` 与 OS06 的两个保存槽仅存非敏感 AI 配置。升级时先将旧密钥写入系统存储并读回，再清理两槽和兼容镜像；失败保留旧值与重试入口，普通保存暂停。Android 自动系统备份及设备转移被禁用；Windows 加密文件依赖同一系统凭据上下文，跨设备恢复请使用用户显式选择含凭据的 JSON。OS05 的旧恢复副本若在迁移前生成仍可能含明文密钥，不属于普通备份。

## OS06/OS07 已实施行为（历史记录，下文当前契约优先）

- 本机保存：`SaveProtocol` 在 SharedPreferences 中维护两个含 revision 与 Adler-32 校验的完整槽，以提交指针指定已提交槽；四个核心键及活跃板/onboarding 继续镜像供旧版本读取。启动优先读指针所指完整槽，提交槽损坏进入 OS05 恢复页；指针写入前中断保留旧批次，写入后镜像失败仍读新批次。`flush` 返回 `SaveResult`，失败可见并可重试。校验仅发现意外损坏；SharedPreferences 不保证返回后已抗强杀或掉电，不承诺跨进程原子性。
- 导入限值（OS07 当时）：设置页先用文件元信息/本地路径限制 **4 MiB**，分段读到最多上限加 1 字节；RF04 后当前单文件上限为 **8 MiB**，见上文。解码前扫描最大嵌套深度 **12**，解析后限制 **500 板、10000 任务、50000 子项**。无路径但选择器提供内存字节时也检查长度。超过即拒绝，现有库不变。
- 预检：v1/无版本和 v2 共用 `ImportPreflight` → `DataMigrator`；未知版本、坏记录或错误时间拒绝。板与任务 ID 分别全局唯一，子项 ID 同父任务内唯一；同 ID 且归一化字段相同的文件内记录计跳过，不同内容拒绝。合并与本机相同 ID 且不同内容记冲突，默认禁止确认；完全相同计跳过。合并孤儿计跳过并警告；覆盖非空孤儿拒绝，空 `boardId` 归首板并计修复；空合法覆盖创建默认板。
- 预览显示新增、跳过、冲突、修复、警告、被替换的板/任务数及是否包含设置/AI 配置；未知字段名称经过安全字符筛选后在警告中展示，值不显示。取消不变更库。用户确认后先写完整已提交批次，再替换内存；保存失败保留旧库并提示重试。旧同步 `Store.importData` 供内部兼容测试使用同一预检，但仍先改内存后排队写入，产品文件入口只调用异步 `applyImport`。
- OS07 未修改密钥行为：当前普通导出仍包含 `customApiKey`，覆盖含配置时仍按现有模型读取 key（缺失将读为空串）。默认排除密钥与凭据导入选择归 OS08；文中的旧现状表关于此项仍有效。

## 决策与范围

- 完整、可携带备份继续使用版本化 UTF-8 JSON：默认导出 **v2**，继续读取旧 Web/Native **v1**（无 `version` 按 v1 解释）。Android 与 Windows 共用模型和导入/导出实现。备份是手动交换文件，不是自动同步。
- CSV 以后可以用于展平的任务报表，不能替代父子任务、提醒和设置的完整备份；当前无附件需求，不引入 ZIP；不以数据库文件替代交换格式。JSON 文件本身不加密，也不解决本机多键写入的原子性；本机损坏保留和保存协议分别由 OS05/06 处理。
- 旧 React 原型已冻结，不承诺它无损读取 v2。本文契约以当前 Flutter 导入与导出实现为准。

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
| `merge` | 默认按备份任务板复用/新建；也可指定一个现有板作为目标，此时所有有效来源任务都改挂到该板，备份板不创建。已有任务 ID 使导入项跳过，相同 ID 不同内容冲突；孤儿任务跳过并告警；不导入设置或 AI 配置；返回**新增任务数**。 | 预检和提交重算保留目标板选择；目标板消失、冲突或结果库超限整笔拒绝，取消不得改数据。 |
| `overwrite` | 先迁移并检查任务所属板；空 `boardId` 改指首板，非空孤儿报错。然后整体替换板/任务；缺少设置/配置时保留本机值，存在时覆盖；活跃板设为首板；返回新任务数。UI 再次确认覆盖，应用后还可能自动升级过期任务的象限。 | OS07 显示板/任务/设置/配置影响，明确空 `boardId` 修复与孤儿策略；应用和持久化复用 OS06 的可恢复提交协议。 |
| 写入或取消 | 选文件/模式/二次确认取消前不调用 Store。迁移/关系错误在状态修改前抛出；但成功应用后多键 SharedPreferences 写入非事务，`flush()` 不等于掉电原子性。UI 失败仅显示通用导入错误；持久化错误可能仅显示错误横幅/文本。 | OS06 解决保存结果/批次，OS07 在应用失败时保持旧库或恢复完整批次，并向用户给出可操作结果。 |

**目标（OS07）冲突规则**：先生成不含敏感内容的预检摘要。相同 ID 且字段相同的记录可计为“跳过”；相同 ID 但内容不同的记录计为“冲突”，默认不替换现有记录，需明确选择处理或拒绝本次导入；同一文件内的重复也执行该规则。覆盖模式的全部影响先显示再确认。具体批量修复与重命名策略在 OS07 实现时固定限值和测试，不在 OS04 假称已有 UI。

## 密钥策略（OS04 历史差异；当前见页首）

**现状：** `AIConfig.toJson` 总写 `customApiKey`，`Store.exportJson` 无排除选项；设置页默认导出包含它的 v2 明文 JSON。`overwrite` 若有 `aiConfig` 会覆盖本机配置和 key，即使 JSON 里省略 `customApiKey`，`AIConfig.fromJson` 也会把 key 读为空串；`merge` 不导入配置。用户应把**当前所有备份文件视为可能含凭据**。

**目标（OS08）：** 默认导出任务、板、允许的设置和非敏感 AI 配置，**省略 `customApiKey` 键**；每次显式选择包含凭据时说明明文风险，才写入该键。旧含密钥的 v1/v2 仍可读；导入文件缺 key 默认保留本机 key，导入/覆盖凭据需用户明确选择。任何预览、文件名、错误、日志和测试输出都不显示 key。OS08 与 OS07 共用导入预检/应用路径；OS09 再处理本机凭据保护。

## 差异登记（OS04 原记录；OS08/09 状态见页首）

| 归属 | 与本页目标契约的差异 |
|---|---|
| OS07 已实施 | 设置页已统一预检、限制文件字节/记录/深度、校验时间与 ID、显示未知字段/修复/孤儿/空备份、预览 merge/overwrite 影响；产品入口用 OS06 批次先保存后应用。历史同步 `Store.importData` 仍是先更新内存后排队保存，待 OS20 移除。 |
| OS08 | 默认排除 `customApiKey`、显式包含凭据、旧含 key 备份的导入选择、缺 key 时保留本机凭据。当前默认明文导出及覆盖缺 key 清空凭据均不满足目标。 |

代码事实入口：[模型与 v1/v2 序列化](../lib/models.dart)、[迁移门禁](../lib/data_migrations.dart)、[Store 导入/导出及持久化](../lib/storage.dart)、[设置页文件流程](../lib/screens/settings_screen.dart)、[合成 v1 fixture](../test/fixtures/export-v1-minimal.json)、[合成 v2 fixture](../test/fixtures/export-v2-minimal.json)。
