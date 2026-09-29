# WP15-A2：本地日程状态接入

状态：A2 实现说明，接在 [WP15-A1](WP15_A1_NOTES.md) 纯模型与时间规则之后。此包只处理本机 Store；目标行为见 [WP15 契约](WP15_CONTRACT.md)。备份文件仍按现有 v1/v2 规则运行，v3 属于 WP15-B。

## Store 接口

- Store.scheduleItems 返回不可修改的当前记录列表；记录对象本身不可变。Store.captureSnapshot().scheduleItems 和 scheduleRevisions 提供离线读取。
- addScheduleItem(item) 校验全库 id、父任务/板关联；重复或孤儿引用抛 FormatException。调用方提供稳定 id；Store 不代替 UI 生成 id。
- scheduleRevision(id) 返回当前会话修订号。updateScheduleItem(item, expectedRevision:) 和 deleteScheduleItem(id, expectedRevision:) 对不存在或已变更记录返回 false；相同内容更新返回 true 且不增加修订号。成功变更提交整库快照；启动恢复待处理时拒绝命令。
- 删除父任务、清空象限/板、删除板均在同一次状态变更里清理关联记录；删板还删除该板独立事件。删除任务的撤销快照包含关联记录，恢复时检测 id 冲突。编组把原任务关联重指向新父任务。任务改名、完成或跨板移动不改日程 JSON；关联记录的板归属由当前任务派生。

## 本地兼容与失败行为

新提交的双槽快照和兼容镜像均包含 matrixflow-schedule。读取旧提交槽时，该键可缺省并解释为空数组；不会从可能较新的镜像补读。键存在但不是合法数组、含坏 IANA 时区、重复 id 或孤儿引用时进入启动恢复，保留原始槽和镜像，不提交空数组。恢复复制内容包含新键；用户显式丢弃损坏数据后，才移除已失效引用并提交。

Store 当前仍只接收 v1/v2 备份：合并保留现有日程；覆盖把日程置空，并在原子提交失败时一起回滚。WP15-B 须把 v3 日程集合接入 ExportData、预检、导入预览/冲突、导出分卷和恢复模拟，同时补上覆盖预览中日程删除数量。当前 v1/v2 导出不携带日程，因此不能作为新增记录的无损备份。旧可执行文件重写本地槽也可能丢弃新键；发行前需按 [契约](WP15_CONTRACT.md)处理回退提示。

编组在现有产品中没有独立的“撤销编组”命令；若后续增加，该命令须保存并恢复每条记录原来的 taskId，不能只撤销任务结构。设备时区到 IANA id 的映射、Planner 视图和通知联动也不在 A2。

## 验证结果

工作树从 origin/main 的 `c131dab` 新建，cherry-pick 原提交 `34dedb587c0c8d2630647c1a9c990168ee33d575` 后得到 `64efd81`（未 rebase、未 push）。本轮验收只补测试与一条跨包断言，没有重写 A2 实现。

定向套件 `test/wp15_schedule_store_test.dart` **15 项全部通过**（原 12 项 + 本轮补 3 项）。补充项对应契约第 4 节里原先只被代码路径覆盖、没有断言的三种读取损坏：

- `malformed schedule JSON in a committed slot enters recovery`：已提交槽里的日程值不是合法 JSON 时进入启动恢复，槽字节保持原样，`recoveryCopyJson()` 含原始坏文本，不被空数组顶替。
- `a duplicated schedule id in a committed slot enters recovery`：同一槽内重复 id 触发 `validateScheduleCollection` 后进入恢复，同批任务仍完整读出。
- `a damaged schedule is only cleared after an explicit discard`：损坏期间镜像保持原值；只有 `discardDamagedStartupData()` 之后才提交 `matrixflow-schedule: "[]”`，重开库不再报告恢复，任务的 plannedDate 不变。

读取行为已核对：坏 JSON 与合法但空数组都走同一条 `read()` 判定；缺键记为 `missing`（不判损坏），坏时区/重复 id/孤儿引用记为 `corrupt` 并把该键加入 `_protectedStartupKeys`，`init()` 在 `_persistAll()` 之前返回，因此旧槽和镜像都不被改写。`_loadJson` 改为“有已提交批次时只信该批次”，所以旧槽不会从未提交的镜像补读日程。

引用维护已核对全部任务增删点：`deleteTask`、`deleteTaskWithUndo`、`clearBoard`、`clearQuadrant`、`deleteBoard` 都在同一次状态变更里清理关联记录，`deleteBoard` 另删该板独立事件；`groupTasks` 把被编组任务的关联重指向新父任务；合并导入保留现有日程，覆盖导入清空集合并把每条记录的修订号推进，使旧详情无法再写回。`_applyImportState` 的合并分支不会留下悬空引用，因为 `ImportPreflight` 的合并结果以 `List<Task>.from(currentTasks)` 起步。提交失败回滚把日程与任务/板一起过 `_carryPostCommitRecords`，并由 `_retainDependenciesOfKeptSchedule` + `_removeOrphanScheduleItems` 收敛引用。

过期编辑防护：`updateScheduleItem`/`deleteScheduleItem` 要求 `expectedRevision` 等于当前会话修订号，删除和编组都会推进修订号，因此旧详情面板的写入返回 false 而不是静默覆盖；相同内容更新返回 true 且不推进修订号。日程命令不触碰 reminder、plannedDate、deadline 或象限（`addScheduleItem`/`updateScheduleItem`/`deleteScheduleItem` 只做校验、改集合、置脏）。

### 需要评审者注意的跨包改动

`test/rf09_serialization_test.dart` 的 `S4 a single task edit produces exactly one whole-library batch` 锁死了整库批次的键序。A2 把 `matrixflow-schedule` 插进 `_snapshotValues()` 后该断言**确定性失败**（首次全量运行 `+1009 -1`，唯一失败就是它），原提交没有更新它。本轮只在该文件里加了 `kSchedule` 常量并把两处期望列表补上这一键，没有改 `_snapshotValues()` 的键序，也没有动同文件的字节级 golden（golden 用的是测试自带的 `fixtureValues()`，与 Store 键集无关，本来就通过）。`S2 a dropped value fails as incomplete` 继续只要求 6 个旧键，这正是“日程键对旧批次可选”的契约，故未加入期望列表。

### 门禁状态

- `flutter analyze --no-pub`：`No issues found!`。
- `flutter test --no-pub`（全量）：**1013 项通过，exit 0**。修复 rf09 期望后跑了两次全量（默认并发一次、`--concurrency=16` 一次）都是绿的。
- 单独 `test/bug_regression_test.dart` 17 项通过；`test/rf09_serialization_test.dart` 31 项通过；RF04 备份套件在全量内通过。

### 关于此前 bug_regression 的偶发失败

上一轮报告的 `failed overwrite leaves all state unchanged` 失败在本轮**三次全量运行（含修复前那一次）和单文件重跑中均未复现**，但它不是 A2 的产品缺陷，而是测试夹具里一条真实的跨用例污染通道，已用临时探针复现并确认可稳定触发（探针文件用完即删，未进入提交）：

`helpers.dart` 的 `makeStore()` 只 `await store.init()`，而 `init()` 末尾的 `_persistAll()` 会把整库提交排进串行队列。`SharedPreferences.setMockInitialValues` 重置的是**进程级平台存储**，但旧 `SharedPreferences` 句柄的写仍会落到重置后的新数据里。于是上一条用例尚未落盘的批次会连同 `matrixflow-save-pointer`、双槽和全部镜像键一起写进下一条用例刚清空的 mock，下一条用例的 `Store()` 直接从上一次的库启动——探针里表现为 `next.tasks=[leak-me and-me]`，3/3 次复现。在同一个 c131dab 分离工作树（不含 A2）跑同一探针得到完全相同的结果（只差 `matrixflow-schedule` 一个键），所以这条通道先于本包存在。反过来，一次把 `dispose()` 提前到重置 mock 之前的对照探针没有留下任何键，说明泄漏取决于“提交是否已经排进队列/在飞”，也就是 CPU 争用会放大这个窗口——这正好对应“混合运行偶发、单跑通过”。

建议后续单独开一个测试卫生包（不属于 A2，也不该在并行包之间顺手改共享夹具）：要么让 `makeStore()` 在返回前 `await store.flush()`，要么约定每个用例在用结束前显式 flush/dispose。本轮没有改 `helpers.dart`，因为它被多个包共用。

### 仍未完成的门禁

- 设备级验收未做：Android/Windows/Linux 上设备时区到 IANA id 的映射、DST 样例和真机重开库都属于 WP15-C/D，本轮只有桌面 Dart 虚拟机内的自动化证据。
- 备份 v3（WP15-B）未接：`Store.exportJson`、预检、分卷与恢复模拟仍只认 v1/v2，覆盖导入的预览没有列出将被删除的日程条数；当前 v1/v2 文件不能作为新增记录的无损备份。
- 旧可执行文件回退会丢弃 `matrixflow-schedule`，发布说明需要先保留 v3 备份；这条属于 WP15-D。
- `Planner` 界面、未知字段提示的 UI 呈现、以及“撤销编组”若将来加入时的 taskId 还原，都不在本包。

