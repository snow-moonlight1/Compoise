# RF04 超计数导出契约（10,599 条历史库不能既“导出成功”又“恢复不了”）

基线：`main / 22aa43d6f88bcbbb9efd778aef23e023454975e0`。分支 `codex/rf04-overcount-backup`，worktree `D:\Dev_project\martix-rf04-overcount`。
范围：`lib/backup_export.dart` 与本包测试 `test/rf04_backup_contract_test.dart`。未改 `storage.dart`、`save_protocol.dart`、`l10n.dart`、`settings_backup_flow.dart`，也未动其他并发包文件；共享文档由集成人统一更新。
固定 Flutter 3.32.8 / Dart 3.8.1，Windows x64，合成数据，无真实库、无真实密钥、无真实设备。

## 1. 复现（修前）

RF10 [第一阶段证据](RF10_PLATFORM_EVIDENCE.md) W7 在 Windows Release 上实测：10,599 条任务的历史库**导出成功且 `recoverable=true`**，得 2 卷；按提示逐卷恢复时第 1 卷成功（7,066 条），第 2 卷被结果库计数门禁拒绝（`Import would exceed the supported library limits`），10,599 条里只有 7,066 条回到新库，约 1/3 数据留在备份文件里。

用默认回归复现同一失败（新增测试，`flutter test --no-pub test/rf04_backup_contract_test.dart`，修前 **12 通过 / 3 失败**）：

```
00:07 +8 -1: RF04 an over-cap library is refused instead of exported as volumes [E]
  Expected: false
    Actual: <true>                       ← bundle.recoverable == true，缺陷本体
00:09 +8 -2: RF04 export of an over-cap library writes no file [E]
  Expected: BackupOutcome:<BackupOutcome.failed>
    Actual: BackupOutcome:<BackupOutcome.succeeded>   ← 界面照旧显示“备份已分成 2 个文件保存”
00:09 +8 -3: RF04 over-cap boards and subtasks are refused on the whole library [E]
  Expected: BackupStatus:<BackupStatus.libraryTooLarge>
    Actual: BackupStatus:<BackupStatus.split>       ← 501 板/54,000 子项也被当成可恢复分卷
```

同一现象的机理也写成了常驻回归：把 10,599 条任务按 RF10 的切分做成 7,066 + 3,533 两条**单看都合规**的文件（各自 ≤ 8 MiB、`inspect` 对空库均通过），按界面提示顺序恢复时第 1 卷成功、第 2 卷以 `importErrorTooManyRecords` 被拒，库中仍是 7,066 条、既没多也没少。

## 2. 根因

导出侧的自检是**逐文件**的：`buildBackupBundle` 把整份导出交给与恢复相同的门禁（`ImportPreflight.decode` + `inspect`），不通过就按板分卷，再把**每一卷**单独过一遍同一个门禁。两卷各自都远低于 10,000 任务，于是导出判定 `recoverable=true`。

但恢复门禁的计数上限约束的是**结果库**（本机 + 新增，`import_preflight.dart` 末段），而逐卷恢复的结果库是各卷的**累加**：10,599 = 7,066 + 3,533，第 2 卷提交时结果库越界。换句话说，**“每卷可恢复”推不出“整个文件集可恢复”**，而 RF04 此前只证明了前者。这是契约缺口，不是数字太小。

同一缺口也覆盖另外两个维度：分卷只看每卷的板/子项数，501 板或 54,000 子项的库同样能切出“每卷都合法”的卷集。

## 3. 采用的契约

在 `buildBackupBundle` 拆卷**之前**先按整份文档累计计数，超上限直接拒绝，不再返回可恢复卷集：

- 计数口径与恢复一致：按**不同 id** 计数（`_libraryCounts` / `_distinctIdCount`）。跨卷重复的板记录、逐卷重复的子项 id 都是导入时的“相同记录跳过”，不该重复计数；没有可用 id 的记录单独计一次（门禁本来也会拒它，提前拒只会更早、不会更晚）。
- 三个维度各自对 `ImportPreflight.maxBoards` / `maxTasks` / `maxSubtasks`（500 / 10000 / 50000，未改动）比较，任一超出即拒绝。
- 返回值复用既有 `BackupStatus.libraryTooLarge`：`recoverable=false`、`parts=[]`，**不写任何文件、不报成功**。设置页 `SettingsBackupFlow` 已把该状态映射到既有三语文案键 `exportErrorTooManyRecords`，因此**没有新增或修改任何文案**（en/zh/ja 保持 RF04 时的原文）。
- 单文件路径零额外成本：文档能过单文件门禁时它必然已在结果库上限内（该门禁的计数检查就是按结果库做的），所以累计计数只在“需要分卷”时执行一次 O(记录数) 的遍历。实测 10,599 条库反而更快：`exportBackup` 1355 ms → 347 ms（省掉分卷打包与逐卷自检）。

明确**不做**的事：不抬高 500/10000/50000，不静默截断，不删除或改写用户记录，不让导出返回 `recoverable=true` 却交出恢复不了的卷集；不为了“能导出”而放弃既有单文件字节门禁。

## 4. 验证

- 定向默认回归 `test/rf04_backup_contract_test.dart`：**10/10 → 15/15**（新增 5 项）。修前 3 项红 → 修后全绿。
  - `RF04 volumes that restore one at a time still add up past the cap`：两卷单独合规、逐卷恢复在第 2 卷被拒、库不变（RF10 W7 的机理，常驻）。
  - `RF04 an over-cap library is refused instead of exported as volumes`：10,599 条库经 Store 导出 → `recoverable=false` / `libraryTooLarge` / `parts` 为空；随后 `flush` 并重启读回，内存与磁盘仍是 10,599 条（没截断、没删除）。
  - `RF04 export of an over-cap library writes no file`：设置页流程导出 → `BackupOutcome.failed` + `exportErrorTooManyRecords`，保存对话框一次未弹、写文件零次、库仍 10,599 条。
  - `RF04 over-cap boards and subtasks are refused on the whole library`：501 板（约 5.2 MiB，切 2 卷）与 9,000 任务 × 6 子项 = 54,000 子项（约 5.7 MiB，切 2 卷）都被拒；同体积、同 9,000 任务但 36,000 子项的库仍然正常导出（`single`），证明拒的是累计计数不是大小。
  - `RF04 a library at every cap still exports as volumes and restores whole`：1 板 / 10,000 任务 / 50,000 子项（约 9.3 MiB）切 3 卷，每卷 ≤ 8 MiB；按顺序（第 1 卷覆盖、其余合并）恢复到独立空 Store，每一步结果库都 ≤ 500/10000/50000，最终 10,000 条任务、50,000 个子项、笔记逐字一致——**受支持上限内的多卷成功路径未被误伤**。
- 相邻回归：共享探针 `test/review/os_final_review_probe.dart`（RF-R01–RF07 等）**全绿**；`os06_os07_transaction_test.dart`、`rf02_import_commit_race_test.dart`、`os08_os09_credential_test.dart`、`rf03_credential_close_test.dart` 合计 **62/62**。
- 全量默认套件 `flutter test --no-pub`：**722/722 → 727/727**（新增 5 项），`flutter analyze --no-pub` **0 issues**。测试串行运行。
- `flutter pub get` 只在 `windows/flutter/` 三个生成文件留下行尾差异，未纳入提交（同前几包做法）。

## 5. 仍不能备份的历史库：怎么向用户解释

**这一类库现在仍然不能备份**，改动只是把失败从“恢复端中途炸”提前到“导出端当场说清”，并且一个字节都不丢。

- 用户点导出时：不再弹出任何保存对话框、不会写出 2 个文件、不会显示“备份已分成 2 个文件保存”。改为在**持有数据的那台设备**上直接失败，并给出既有文案：
  - zh：`当前数据量超过本应用可恢复的备份上限，请删除或归档部分任务后再导出。`
  - en：`This library is larger than the backup this app can restore. Remove or archive tasks, then export again.`
  - ja：`このデータ量は本アプリが復元できるバックアップの上限を超えています。一部のタスクを削除またはアーカイブしてから再エクスポートしてください。`
- 用户数据原样保留：内存与磁盘都还是 10,599 条（回归里用 `flush` + 重启读回断言），没有静默截断、没有替用户删任务。删/归档是用户自己的决定，导出不做。
- 口径要说准：本版本受支持的库是 **≤ 500 板 / 10,000 任务 / 50,000 子项，且 ≤ 8 卷（约 64 MiB 编码）**。像 10,599 条这样的历史库**不在受支持计数契约内**，不是“备份功能坏了”，也不要说成“所有旧库都可恢复”。RF10 收口时按这个口径向用户呈现即可。
- 用户真要保住这类库，目前只有两条路：①按应用自己的建议先归档/删除到上限内再导出；②单独决定是否上调受支持计数上限或给分卷合并开例外——那是产品决策，**不在本包范围内**（上调还要与 OS22 的 10k 条帧测量一起复核，见 [RF04_NOTES](RF04_NOTES.md) 第 5 节与 [RF09 测量](RF09_MEASUREMENT.md)）。

## 6. 残余限制与交给集成人的点

1. **设备未测**：新的“超计数直接拒绝”路径只在单元/widget 层验证（文案、零文件、库不变）。真机上 Android SAF / Windows 另存为对话框不弹、提示按预期显示，仍归 RF10 定向验收。
2. **旧备份文件的处境不变**：本包不改导入侧。别人手里 2 卷的超计数备份（RF10 当时写出的 `overcount-*_part1of2.json`）在当前上限下仍只能在第 2 卷被拒——导入门禁本就该拒；本包只保证**本应用不再生产这种文件**。
3. **`libraryTooLarge` 语义变宽**：现在同时表示“超记录计数上限”和“需要超过 8 卷”。设置页对二者都用 `exportErrorTooManyRecords`（“数据量超过可恢复上限，请删除或归档”），对 64 MiB 量级的场景措辞也成立；如后续要更细分，需要新的三语文案键，届时单独派发。
4. **与 RF09 的交叉**：导出现在多一次 O(记录数) 的计数遍历，只发生在需要分卷时，且省掉了分卷打包的实测字节开销（10,599 条库 1355 ms → 347 ms）。若 RF09 要合并重复全库编码，**请保留这一累计计数检查**（或保留等价断言），它不是冗余工作。
5. **未改的相邻限制**：单条记录大过 8 MiB 仍不可分片（`oversizedRecord`，提示精简），本地输入层未按 UTF-8 字节限制笔记长度（属输入 widget，不在本包文件所有权内）。
6. **计数口径的取舍**：按不同 id 计数意味着“完全相同的重复记录”不算两条。若将来出现同 id 不同内容的冲突记录，导出侧不新增检测，仍由各卷的导入门禁在合并时按“冲突”阻断（与本包改动前一致）。
