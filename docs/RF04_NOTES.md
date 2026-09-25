# RF04 — 自身备份必须可恢复（对称备份契约）

基线：`main / ca1f209f06c5459b983ef492bfd69a92667380f5`。分支 `codex/rf04-backup-recovery`，worktree `D:\Dev_project\martix-rf04`。
范围：导出、备份预检与设置页文件流程。未改 `updateAIConfig`、凭据队列、`flush` 或退出协调（RF03 所有）。

## 1. 复现（修前）

共享探针 `test/review/os_final_review_probe.dart` 的 RF-R04 在基线为红：

```
RF-R04 app-produced backup must be accepted by its import gate [E]
  Expected: null
    Actual: FormatException:<FormatException: Backup exceeds 4 MiB>
```

`Store.exportJson()` 成功写出 4 MiB 笔记的备份，`ImportPreflight.decode` 因 JSON 包装后超过 4 MiB 直接拒绝。探针用
`ImportPreflight.maxBytes` 作为字段大小，所以任何把 `maxBytes` 同时当作“文件大小上限”的方案都不可能让它变绿：一条记录占满该
预算时，文件必然大于该预算。这是不对称的根因，而不只是数字太小。

## 2. 测量依据（`test/review/rf04_size_measurement.dart`，显式运行，不属于默认套件）

固定 Flutter 3.32.8 / Dart 3.8.1，Windows x64，合成中日韩文本，无真实库、无真实密钥。

| 测量 | 结果 |
|---|---|
| 空库导出信封 | 751 bytes |
| 裸任务记录（空标题、无子项） | 146 bytes |
| 裸子项记录 / 裸板记录 | 39 bytes / 34 bytes |
| 现实记录（CJK 标题 + 5 子项） | 662–683 bytes |
| 500 板 / 1000 任务 / 5000 子项 | 0.65 MiB |
| 5000 任务 / 25000 子项 | 3.25 MiB |
| **计数上限库：500 板 / 10000 任务 / 50000 子项** | **6.52 MiB（6,832,953 bytes）→ 旧 4 MiB 门禁拒绝** |
| 编码 / 解码 / 预检耗时 | 6.5 MiB：encode 63–102 ms、decode 135–144 ms；3.25 MiB inspect 192–238 ms |
| UTF-8 放大（每 UTF-16 code unit） | CJK 3.0、emoji 2.0、`"` 与 `\n` 转义 2.0、ASCII 1.0 |
| 4 MiB 单条笔记的包装开销 | +996 bytes |

关键结论：

1. **不是病态输入才坏**。按应用自己声明的计数上限（10000 任务、50000 子项）填满一个真实规模的库，编码后就是 6.52 MiB，
   超过 4 MiB 文件门禁。计数门禁与字节门禁互相矛盾，本地创建/合并允许存在的库无法被自己的备份格式表达。
2. **字符数不能当字节数**。CJK 每 UTF-16 单元 3 字节，`"`/换行转义翻倍，所以任何按“字符”定义的上限都会低估 2–3 倍。
3. 性能不是提高上限的障碍：6.5 MiB 的导出/解码在测试 VM 上是百毫秒级；真正的约束是内存（字节、字符串、解析后的对象
   同时存在约 3 份）和有界读取必须保留。

## 3. 采用的契约

单一事实来源在 `ImportPreflight`：

| 常量 | 值 | 依据 |
|---|---|---|
| `maxBytes` | 4 MiB（未改数值） | 含义固定为**单个备份文件承载的文本内容预算**；RF-R04 用它在一条记录里放满 4 MiB，因此文件门禁必须大于它 |
| `maxFileBytes` | 8 MiB（新） | (a) 必须 > `maxBytes` + 包装（实测 +996 bytes）才能让占满内容预算的单条记录往返；(b) 必须覆盖**按计数上限填满的现实库**的实测 6.52 MiB，使合法计数的库仍能以单文件导出。取 8 MiB：两项都满足且留约 23% 余量 |
| `maxParts` | 8 | 超过单文件上限的既有大库的可恢复路径：按板分卷，每卷 ≤ `maxFileBytes`。8 卷 ⇒ 受支持库约 64 MiB 编码，是实测最大合法库（6.52 MiB）的约 10 倍；超出即明确失败 |
| `maxBoards/maxTasks/maxSubtasks` | 500/10000/50000（未改） | 现在同时按**结果库**校验，而不只是按文件校验 |
| `maxDepth` | 12（未改） | — |

导出侧新增 `lib/backup_export.dart`：

- `buildBackupBundle(document)` 先把整份导出交给**与恢复完全相同的门禁**（`ImportPreflight.decode` + `inspect`）自检；
  通过就原样输出单文件（今天的常见路径，逐字节不变）。
- 不通过时按板分组打包（分片目标 = `maxBytes`，逐条记录用 `utf8.encode(jsonEncode(record))` 实测字节，不估算）；
  单板超过一片时其任务跨片分布，**每片重复该板记录**（合并时按相同记录计跳过，不算冲突）。分卷顺序无关：先覆盖导入第
  1 卷，其余按合并导入。
- 只有第 1 卷带 `settings`/`aiConfig`：合并本来不导入配置，且显式含密钥时密钥只落一次，不随分卷复制。
- 打包后再逐片过一遍真实门禁；任何一片仍过不了（单条记录大过整文件）就返回 `oversizedRecord`，需要超过 8 片返回
  `libraryTooLarge`，两者都不写文件、不报成功。
- `Store.exportBackup({includeCredential})` 只做“取现有导出文本 → 分片”，不触碰凭据读写（RF03 范围）。

导入侧 `ImportPreflight`：

- `decode` 与 `inspect` 的文件门禁改用 `maxFileBytes`；拒绝原因变成携带 `copy` 键的 `BackupRejectedException`
  （仍 `implements FormatException`，因此既有 `throwsFormatException` 断言与 RF02 的重推导路径不变），设置页据此显示
  “超过大小/数量/嵌套上限”而不是笼统的“数据格式无效”。
- 数量校验新增对**结果库**（merge 后 = 本机 + 新增）的约束，关闭“多次合法 merge 累积突破上限”的口子；覆盖导入路径
  的文件级校验不变。

文件流程 `SettingsBackupFlow`：

- 导出改为按分卷逐个保存，文件名 `matrixflow_backup_<date>_partKofN.json`（单文件仍用旧名，旧版本读法不变）。
- 新增可注入的 `BackupFileWriter`（默认实现保留“Android/iOS 由 SAF 自己写、桌面再写一次”的判断）。这是为了让默认套件
  能断言“每片写了什么、写失败/中途取消时不报成功”而不必真的落盘几十 MB；真实磁盘写仍属设备验收。
- 不可恢复的导出返回失败并给出可执行文案（精简该记录 / 删除或归档部分任务后重试），绝不显示“备份已保存”。

三语文案：`exportPartsSuccess`、`exportPartsHint`、`exportErrorTooLarge`、`exportErrorTooManyRecords`、
`importErrorTooLarge`、`importErrorTooManyRecords`、`importErrorTooDeep`（en/zh/ja 各 7 条，与既有键同区）。

## 4. 验证

- 共享探针 `RF-R04`：修前红 → **修后绿**（原断言未改，`test/review/` 未编辑）。
- 默认新增 `test/rf04_backup_contract_test.dart` **9/9**（约 10 s）：
  RF-R04 迁移（4 MiB 单记录导出 + 独立空 Store 预检与完整恢复）；文件门禁界限前/等于/超出；CJK 与非 CJK 同字符数的
  字节差异（含日文 3 bytes/字）；500/10000/50000 数量界限内与 +1；多次合法 merge 累积（含“预览时仍有空间、提交时按活库
  重推导后拒绝”，且库与 prefs 保持 500 板）；10.6 MB 旧大库分卷并在独立空 Store 按顺序完整恢复（重复板记录计跳过）；
  `oversizedRecord` / `libraryTooLarge` 不写文件不报成功；分卷文件名、中途取消只写到第 1 片、写失败 → `exportError`；
  超上限导入给出大小文案且原库不变；默认导出不含密钥、显式合成密钥在分卷中只出现一次且在第 1 卷。
- 相邻回归：`test/os06_os07_transaction_test.dart`（OS06/07 提交与预检）、`test/rf02_import_commit_race_test.dart`
  （RF02 导入竞态/重推导）、`test/os08_os09_credential_test.dart`（OS08/09 密钥）、`test/data_migration_test.dart`
  集成前定向 **56/56** 全绿。`os06` 中一处 `maxBytes + 1` 的越界断言按新常量名改为 `maxFileBytes + 1`，意图不变。
- 完整默认套件与 `flutter analyze --no-pub` 结果见提交回复（门禁：analyze 0 issues）。

## 5. 残余限制与交给集成人的点

1. **超计数库不是无损一键恢复**。分卷保证“数据出得来”，但合并仍受结果库 500/10000/50000 约束：本机已超计数上限的
   历史库（>10000 任务）逐卷合并会在超过上限那一卷被拒绝，应用会给出明确的数量上限文案，不静默丢弃。要让这类库也能
   整体恢复，需要单独决定受支持计数上限（建议与 OS22 的 10k 帧测量一起复核），不属于 RF04 自行放宽的范围。
2. **单条记录大过 `maxFileBytes`（8 MiB）不可分片**，导出会明确失败并提示精简；本地创建路径未加长度上限（属于
   `task_detail_panel.dart`/`subtask_edit_dialog.dart` 等输入层，不在本包文件所有权内）。若要在写入时就挡住，需要一个
   单独派发的小包，按 `utf8` 字节而非字符长度校验。
3. **设置字号/字体等 v2 专有字段的往返**行为未改；`ExportData` 外层格式仍是 v1/v2，未引入 ZIP 或新 schema。
4. **导出多跑一遍全库序列化**（对称保证的代价）。`exportBackup` 会先完整导出，再对导出的文本做一次 `utf8.encode` +
   `decode` + `inspect` 自检；超过单文件上限时还会 `jsonDecode` 整份并按记录实测字节重新编码分卷。按实测这约等于导出
   本身再付一次 encode（6.5 MiB 库 ~100 ms）+ 一次 inspect（~200 ms）。RF09 的目标正是消除重复全库序列化：如果要共享
   一次编码结果，请把该自检保留为等价断言，不要直接删掉。
5. **设备未测**：真实 Android SAF / Windows 文件对话框的多卷连续保存、几十 MB 写入耗时与内存、用户按提示分卷恢复的
   实际操作路径都未经真机验收（归 RF10）。`FilePicker.saveFile` 在多卷下会连续弹 N 次保存对话框，这一交互仅在单元层
   以注入 writer 验证。
6. **与 RF03 的交叉点（集成 RF03 后再合本包时必须复核）**：
   - `Store.exportBackup` 走 `exportJsonWithCredential()`，其中 `await _credentialWrites` 与 `credentialError` 判断由
     RF03 改写；本包只消费其结果文本，若 RF03 改成新的 completion 对象，这里应改为 await 那个 completion，语义
     （“已确认的凭据才允许显式含密钥导出”）不能放松。
   - 分卷只让**第 1 卷**携带 `aiConfig`，所以 `applyImport(importCredential: true)` 只在第 1 卷发生一次凭据写入；RF03
     的最后意图/回滚队列要确认“多次导入中的单次凭据写入”与其模型一致。
   - 预检的结果库数量校验会在 `applyImport` 的重推导里抛错并被 `_rebaseImport` 转成 `SaveResult(false)`（RF02 行为），
     即“提交时上限变化 → 整笔拒绝、库不变”。RF03 若调整凭据/保存队列顺序，需保留该失败即无部分写入的性质。
7. `test/os06_os07_transaction_test.dart` 的一行常量名被更新（见上），是本包唯一越出新增文件的既有测试改动；
   `test/review/` 共享探针未改。
