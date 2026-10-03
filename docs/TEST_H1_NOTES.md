# TEST-H1：消除 SharedPreferences 测试跨用例污染

执行日期：2026-10-04（Asia/Shanghai）。基线 **`459f9a28cefdcac9196825b2d4ac70250dbf3b8d`**，分支 `codex/test-h1`，工作树 `D:/Dev_project/martix-test-h1`。仓库内没有适用的 AGENTS.md（全仓查找无 AGENTS/CLAUDE/QODER/.cursorrules），按交接包约束执行。提交身份只写入本工作树：`git config user.name test-h1-agent` / `user.email test-h1-agent@local`。

工具链：`D:/Dev_SDKs/Flutter_3.32.8` → Flutter 3.32.8、framework revision `edada7c56e`、engine `ef0cd00091`、Dart 3.8.1，与 `toolchain.json` 的 `verified` 三项逐字一致。`flutter pub get --enforce-lockfile` 退出码 0；`pubspec.yaml`/`pubspec.lock` 未改。

## 结论

`makeStore` 交给用例的 Store 不再欠着写入：初始整库提交在 `makeStore` 返回前落盘，纯 Dart 用例结束时再排空该用例登记的 Store。跨用例污染由确定性复现变为确定性不复现，默认全量套件与高并发套件全绿。

## 机制（已实证，非推测）

- `Store.init()` 尾部调用 `_persistAll()`（`lib/storage.dart:626`），它只经 `_markDirty()` → `_scheduleCommit()` → `_runTransaction()` 把整库提交挂在串行 `_commitGate` 上（`lib/storage.dart:2437-2472`）。`await store.init()` 返回时该批次只是"已排队"，`makeStore` 随即把 Store 交出去。
- `SharedPreferences.setMockInitialValues` 替换进程级 `SharedPreferencesStorePlatform.instance` 并清空单例（shared_preferences 2.5.3 `lib/src/shared_preferences_legacy.dart:279-291`），而句柄每次调用都动态解析该实例（同文件 `:30-31`）。于是上一个用例仍持有的句柄会把旧库写进**下一个用例的 mock**。
- 新 mock 被旧写入污染后，`getInstance()` 的快照即含旧 `matrixflow-save-pointer` 与对应 slot，`SaveProtocol.load()` 返回旧批次 → 下一用例从上一个库启动，表现为 `store.tasks.single` 类偶发失败。
- 若用例边界恰好切在 slot 与 pointer 两次写之间，新用例还会读到"有指针无批次"，`SaveProtocol.readCommitted` 抛 `FormatException: Missing committed batch`，`init` 把它记为 corrupt 并进入启动恢复态。

## 前后证据

修复前（提交 `f857224b3ced25f90fb91a33b329864457b7a956`，helper 只加了可控写入接缝）：

```
$ flutter test --no-pub test/test_h1_store_lifecycle_test.dart   EXIT:1
+1 -1: ... case B boots from its own seed only [E]
  Expected: non-empty / Actual: []      # 上一用例的提交点在本用例开始时仍未落盘
+1 -2: ... the helper returns a store whose initial commit already landed [E]
  Expected: an object with length of <1> / Actual: []
```

同一状态下的症状探针（一次性脚本，非提交内容，2/2 复现；日志 `/tmp/h1_symptom_red_final.log`）：

```
PROBE A  ready=true tasks=[leak-me] pointersLanded=0
PROBE B  pointersLandedBeforeReset=0        # 上一用例还欠着整库提交
PROBE B  bootedTasks=[leak-me] recovery=false
Expected: ['case-b']  Actual: ['leak-me']   # 下一用例从上一个库启动
```

修复后（`427e011863122e8880dfede803021b674c9bc2b6`）：同一回归 `EXIT:0`、`+4 All tests passed`；探针变为 `pointersLandedBeforeReset=1`、`bootedTasks=[case-b]`，新代次里已无外来提交（`pointerNow=null`）。

## 踩到的假时钟坑（本包最重要的约束）

第一版把"用例结束前排空"登记到所有用例的 `addTearDown`，结果 `test/deadline_policy_test.dart` 从第 20 项起整文件挂死到 10 分钟超时，并在后续用例触发 `'!inTest': is not true`（`binding.dart:1562`；日志 `/tmp/h1_dl_exclusive.log`）。原因是双重的：

1. widget 交互在 `testWidgets` 的假时钟区排队提交，`FakeAsync` 随用例销毁后不再有人 pump 这条链，从销毁后的区域 `await` 它永远不返回；
2. 该用例自己的 `addTearDown(store.dispose)` 晚于 helper 登记的排空（`addTearDown` 先进先出），所以排空时 Store 尚未 `_disposed`，队列里的批次仍会被推进。

而这样的滞留写入根本到不了平台存储，本来就不可能污染下一用例——在假时钟下排空它既危险又无必要。最终实现只在没有假时钟的用例里登记排空；`makeStore` 的"初始提交收敛"在两种分区下都保留（隔离探针 V2/V6 通过，`EXIT:0`）。修复后 `deadline_policy_test.dart` 22/22、耗时约 2 秒（`/tmp/h1_dl_fixed.log`）。

## 改动与边界

只改三个文件（`git diff --stat 459f9a2..HEAD` → 485 insertions，1 deletion）：

- `test/helpers.dart`：`makeStore` 返回前 `await store.flush(waitForReminders: false)`；新增 `registerTestStore(Store)` 与 `drainTestStores()`；`makeStore` 增加**可选** `saveWriter`（默认 null，保持既有 148 处调用的行为与 `Future<(Store, Map<String, Object>)>` 返回元组不变）。排空不 `dispose`：仓库 300+ 处用例自行 dispose，二次 dispose 会抛 `ChangeNotifier` 断言。
- `test/test_h1_store_lifecycle_test.dart`（新增，4 项）：跨用例未完成写入回归、`makeStore` 初始提交已落盘、以及直接证明"旧句柄会写进新一代 mock"的机制用例。
- `test/test_h1_helper_lifecycle_test.dart`（新增，10 项）：失败写入（拒绝提交点）后库仍可读且状态可报告、失败写入不毒化下一用例、dispose 撞上班排空时不再产生新批次、init 失败（`persistence.open` 抛错）后排空不写任何东西且不挂、重复 dispose 仍然响亮、同一用例调用 helper 两次互不污染、非 helper 创建的 Store 经登记同样被排空、同一 Store 重复登记只排空一次、widget 用例的收敛与事后排空、widget 用例之后的普通用例仍从自己的种子启动。

未触碰：生产 `Store`/`SaveProtocol`/`Reminder`/数据库、其它并行包的测试、共享 README/ROADMAP/导航/发行版本/模型锁。字节/像素/确认/提交/许可门禁未削弱（本包只动测试生命周期）。没有 `dart format`，手写匹配既有排版。生成的 `windows/linux/flutter/generated_*` 差异与探针/日志均未提交；未派子 Agent、未 push、未 amend、未 tag、未建 Release、未签名。

## 门禁与计数

| 命令 | 退出码 | 结果 |
|---|---|---|
| `flutter analyze --no-pub` | 0 | No issues found |
| `flutter test --no-pub test/bug_regression_test.dart` | 0 | +17 全通过 |
| `flutter test --no-pub test/rf09_serialization_test.dart` | 0 | +31 全通过 |
| `flutter test --no-pub test/test_h1_store_lifecycle_test.dart` | 0 | +4 全通过 |
| `flutter test --no-pub test/test_h1_helper_lifecycle_test.dart` | 0 | +10 全通过 |
| `flutter test --no-pub test/deadline_policy_test.dart` | 0 | +22 全通过 |
| `flutter test --no-pub`（默认并发，独占） | 0 | +1428 ~11 全通过（基线 1414 + 本包 14） |
| `flutter test --no-pub --concurrency=24`（独占） | 0 | +1428 ~11 全通过 |

两次全量的最终计数逐字相同（1428 通过 / 11 条件跳过 / 0 失败），`[E]` 行均为 0。高并发轮次的意义：默认轮次已排除"靠串行掩盖"，`--concurrency=24`（超过 16 逻辑核）进一步让套件重度重叠，仍全绿说明不变量不依赖调度顺序。上表的四个定向套件在最终提交 `db88f3e639ccc7592df3f2d0bd8be641d37907ed` 上复跑过一次，退出码同为 0（`/tmp/final_*.log`）。两次全量之间本机独占，无并发套件干扰。

## 遗留缺陷与建议（交集成端决定，不在本包边界内）

1. **不经 helper 创建的 `Store` 仍不受保护。** 具体位置：`test/bug_regression_test.dart:25-27`（`reopened`，其 init 尾部的整库提交未排空即结束用例）、`:37-39`、`:194-201`、`:437-439`。建议两种收口任选：(a) 各用例补一行 `registerTestStore(store)`（helper 已导出，零生产改动）；(b) 生产端提供 `Future<void> disposeAndDrain()`（或在 `dispose()` 前统一走 `flush()`），因为 `Store.dispose()` 目前只置 `_disposed`、取消定时器，不等待在途提交（`lib/storage.dart:697-704`）。本包没有自行改这些文件，也没有改生产语义。
2. **widget 用例的排空需要显式。** 假时钟销毁后无法安全 await，helper 因此在 widget 用例里只收敛初始提交。若 widget 用例在 `tester.runAsync` 内修改 Store，请在同一段 `runAsync` 内 `await store.flush(waitForReminders: false)`；本包已用两个用例钉住该边界与后果。
3. **排空不等提醒链路。** 提醒账本是真实文件 I/O（`lib/services/reminder_service.dart:882` 经 `ledgerStore.write`），在假时钟下会死锁；且提醒同步路径不脏化库（`_runReminderSync` 不调用 `_markDirty`），所以不影响"写入完成后才能重置 mock"这一不变量。

## 未验证事项

- 未在 Linux/Windows CI runner 上跑本套件（本机 Windows 10.0.26200 + 固定 SDK）；WSL Ubuntu-24.04 的 `/home/ubuntu/develop/flutter` 未用于本包，因为改动只在 Dart 测试生命周期，不含平台侧。
- 未做真机/独立进程验证：本包不涉及设备、GPU、AVD、原生 GUI 会话。没有任何 skip、注入或强杀被描述为真机通过。
- 未跑 `flutter build`：本包只改测试 helper 与新增测试，不改产品入口、构建脚本或资源；以 `flutter analyze --no-pub` 0 issues 与默认全量套件全绿作为"正常应用默认测试入口未被改变"的证据。
- 提交点被拒绝那类"半批落盘"只在测试接缝内注入，未验证真实断电/杀进程下的行为（那属于 SaveProtocol 的既有验收范围）。
